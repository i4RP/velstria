import XCTest
import SwiftUI
import UIKit
@testable import VELSTRIA
import VelstriaCore

// 担当: battle-hud。操作ボタンのラベル（スキルの種別タグ・ボタン内のスペル名）と死亡中の見た目:
// 全ヒーローの全スキルで短いタグになること、優先順位、スペル名の短縮とボタン内への収まり、
// 3 端末 × 左右配置 × 2 言語でタグが攻撃ボタン 3 つ・スキル・スペル・帰還・習得バッジ・下部パネル・ミニマップ・画面端と重ならないこと、
// 死亡中も絵柄が見えたまま暗くなること（全体を薄くしない）。

final class HUDControlLabelTests: XCTestCase {
    private let devices: [(name: String, size: CGSize, side: CGFloat, bottom: CGFloat)] = [
        ("iPhone 16e", CGSize(width: 844, height: 390), 47, 21),
        ("iPhone 17 Pro", CGSize(width: 874, height: 402), 62, 20),
        ("iPhone 17 Pro Max", CGSize(width: 956, height: 440), 62, 20),
    ]

    private var savedLanguage: AppLanguage = .ja

    override func setUp() {
        super.setUp()
        savedLanguage = Loc.current
    }

    override func tearDown() {
        Loc.current = savedLanguage
        super.tearDown()
    }

    private func targeting(_ skill: SkillDef) -> SkillTargeting {
        SkillCatalog.targeting(for: skill, hero: MasterData.shared.hero(skill.heroID)!)
    }

    private func layout(_ d: (name: String, size: CGSize, side: CGFloat, bottom: CGFloat), left: Bool) -> HUDLayout {
        HUDLayout(size: d.size, safe: EdgeInsets(top: 0, leading: d.side, bottom: d.bottom, trailing: d.side), leftHanded: left)
    }

    // MARK: スキルの種別タグ

    func testEveryHeroSkillHasShortTag() {
        let master = MasterData.shared
        XCTAssertFalse(master.heroes.isEmpty)
        var used = Set<HUDSkillTag>()
        for lang in [AppLanguage.ja, .en] {
            Loc.current = lang
            let limit = lang == .ja ? HUDSkillTag.maxLengthJa : HUDSkillTag.maxLengthEn
            for hero in master.heroes {
                for slot in SkillSlot.actives {
                    guard let skill = master.skill(hero: hero.heroID, slot: slot) else {
                        XCTFail("\(hero.heroID) \(slot) のスキルが無い")
                        continue
                    }
                    let t = targeting(skill)
                    let tag = HUDSkillTag.tag(for: skill, archetype: t.archetype)
                    used.insert(tag)
                    XCTAssertNotEqual(tag, .passive, "\(skill.skillID) 能動スキルにパッシブのタグ")
                    let label = HUDSkillTag.label(for: skill, archetype: t.archetype)
                    XCTAssertFalse(label.isEmpty, "\(skill.skillID)")
                    XCTAssertLessThanOrEqual(label.count, limit, "\(skill.skillID) のタグ「\(label)」が長い")
                }
            }
        }
        // 1 種類に偏らない（ボタンごとに見分けられる）
        XCTAssertGreaterThanOrEqual(used.count, 8, "使われたタグ: \(used.map(\.rawValue).sorted())")
        // 全タグの文言（未使用のものも）
        for lang in [AppLanguage.ja, .en] {
            Loc.current = lang
            for tag in HUDSkillTag.allCases {
                XCTAssertFalse(tag.label.isEmpty)
                XCTAssertLessThanOrEqual(tag.label.count, lang == .ja ? HUDSkillTag.maxLengthJa : HUDSkillTag.maxLengthEn,
                                         tag.label)
            }
        }
        // 必殺技のタグはボタン上の「必殺」バッジと重複しない（種別を示す）
        Loc.current = .ja
        for tag in HUDSkillTag.allCases { XCTAssertNotEqual(tag.label, "必殺") }
    }

    func testTagPriority() {
        Loc.current = .ja
        let master = MasterData.shared
        func skill(where match: (SkillDef, SkillArchetype) -> Bool) -> SkillDef? {
            for hero in master.heroes {
                for slot in SkillSlot.actives {
                    if let s = master.skill(hero: hero.heroID, slot: slot), match(s, targeting(s).archetype) { return s }
                }
            }
            return nil
        }
        // 回復は CC より優先
        if let s = skill(where: { $0.cc != .none && ($1 == .healZone || $1 == .teamHeal) }) {
            XCTAssertEqual(HUDSkillTag.tag(for: s, archetype: targeting(s).archetype), .heal)
        } else { XCTFail("CC 付きの回復スキルがマスターに無い") }
        // 移動は CC より優先
        if let s = skill(where: { $0.cc == .stun && $1 == .dashStrike }) {
            XCTAssertEqual(HUDSkillTag.tag(for: s, archetype: .dashStrike), .dash)
        }
        // 攻撃技は CC → 妨害 / 減速、CC 無し → 形
        if let s = skill(where: { ($0.cc == .stun || $0.cc == .root || $0.cc == .knockback) && $1 == .cone }) {
            XCTAssertEqual(HUDSkillTag.tag(for: s, archetype: .cone), .control)
            XCTAssertEqual(HUDSkillTag.label(for: s, archetype: .cone), "妨害")
        } else { XCTFail("CC 付きの扇形スキルがマスターに無い") }
        if let s = skill(where: { $0.cc == .slow && $1 == .groundAoE }) {
            XCTAssertEqual(HUDSkillTag.tag(for: s, archetype: .groundAoE), .slow)
        }
        if let s = skill(where: { $0.cc == .none && $1 == .groundAoE }) {
            XCTAssertEqual(HUDSkillTag.label(for: s, archetype: .groundAoE), "範囲技")
        }
        if let s = skill(where: { $0.cc == .none && $1 == .lineSkillshot }) {
            XCTAssertEqual(HUDSkillTag.label(for: s, archetype: .lineSkillshot), "直線技")
        }
        // マスターが無い時はアーキタイプだけで決める
        XCTAssertEqual(HUDSkillTag.tag(for: nil, archetype: .selfAoE), .guardSelf)
        XCTAssertEqual(HUDSkillTag.tag(for: nil, archetype: .targetedBlink), .execute)
        XCTAssertEqual(HUDSkillTag.tag(for: nil, archetype: .blinkEmpower), .blink)
        XCTAssertEqual(HUDSkillTag.tag(for: nil, archetype: .leapSlam), .leap)
        XCTAssertEqual(HUDSkillTag.tag(for: nil, archetype: .multiStrike), .flurry)
        XCTAssertEqual(HUDSkillTag.tag(for: nil, archetype: .cone), .area)
        XCTAssertEqual(HUDSkillTag.tag(for: nil, archetype: .piercingLine), .pierce)
    }

    // MARK: スペル名（ボタン内）

    private func roundedFont(_ size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        return base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
    }

    func testSpellLabelsAreShortAndFitInsideButton() {
        let master = MasterData.shared
        XCTAssertFalse(master.spells.isEmpty)
        for lang in [AppLanguage.ja, .en] {
            Loc.current = lang
            let limit = lang == .ja ? HUDSkillTag.maxLengthJa : HUDSkillTag.maxLengthEn
            for spell in master.spells {
                let label = HUDSkillTag.spellLabel(spell.spellID)
                XCTAssertFalse(label.isEmpty, spell.spellID)
                XCTAssertLessThanOrEqual(label.count, limit, "\(spell.spellID) 「\(label)」")
                let full = MasterText.spell(spell)
                if full.count <= limit { XCTAssertEqual(label, full, "短い名前はそのまま") }
            }
            // ボタン内で縮小せずに収まる（名前の段の下端での円の幅 - 縁取り）
            for d in devices {
                let l = layout(d, left: false)
                let dia = l.spellDiameter
                let font = roundedFont(HUDSpellLabel.fontSize(dia), weight: .black)
                let stackBottom = HUDSpellLabel.stackOffset(dia) + HUDSpellLabel.stackHeight(dia) / 2
                XCTAssertLessThan(stackBottom, dia / 2 - 3, "\(d.name) 名前の段がボタンの下端からはみ出す")
                let halfChord = ((dia / 2) * (dia / 2) - stackBottom * stackBottom).squareRoot()
                let maxWidth = min(dia * HUDSpellLabel.maxWidthRatio, (halfChord - 2) * 2)
                for spell in master.spells {
                    let text = HUDSkillTag.spellLabel(spell.spellID)
                    let w = (text as NSString).size(withAttributes: [.font: font]).width
                    XCTAssertLessThanOrEqual(w, maxWidth, "\(d.name) \(lang) スペル名「\(text)」がボタンに収まらない")
                }
                // クールダウンの秒数は絵柄の位置（名前より上）に重ねる
                XCTAssertLessThan(HUDSpellLabel.iconCenterOffset(dia), 0)
                let numberBottom = HUDSpellLabel.iconCenterOffset(dia) + dia * 0.3 * 0.6
                let nameTop = stackBottom - HUDSpellLabel.fontSize(dia) * 1.2
                XCTAssertLessThanOrEqual(numberBottom, nameTop + 1, "\(d.name) 秒数が名前に重なる")
            }
        }
        XCTAssertEqual(HUDSkillTag.shortened("Healing Wave", maxLength: 8), "Healing")
        XCTAssertEqual(HUDSkillTag.shortened("Blink", maxLength: 8), "Blink")
        XCTAssertEqual(HUDSkillTag.shortened("Extraordinary", maxLength: 8), "Extraor…")
        XCTAssertEqual(HUDSkillTag.shortened("星々の長い名前", maxLength: 4), "星々の…")
    }

    // MARK: 種別タグの配置

    /// 見積もりが実際の描画幅以上であること（重なりテストの前提。カプセルはこの大きさで描く）。
    func testLabelSizeEstimateCoversRenderedText() {
        let sizes: [CGFloat] = [9 * 0.84, 9, 9 * 1.18]
        for fs in sizes {
            let font = roundedFont(fs, weight: .heavy)
            for text in allTagTexts() {
                let real = (text as NSString).size(withAttributes: [.font: font])
                let est = HUDControlLabel.estimatedSize(text, fontSize: fs)
                XCTAssertGreaterThanOrEqual(HUDControlLabel.estimatedTextWidth(text, fontSize: fs), ceil(real.width),
                                            "「\(text)」の幅の見積もり")
                XCTAssertGreaterThanOrEqual(est.width, ceil(real.width) + HUDControlLabel.horizontalPadding * 2)
                XCTAssertGreaterThanOrEqual(est.height, floor(real.height), "「\(text)」の高さの見積もり")
            }
        }
    }

    private func allTagTexts() -> [String] {
        var out: [String] = []
        for lang in [AppLanguage.ja, .en] {
            Loc.current = lang
            out += HUDSkillTag.allCases.map(\.label)
        }
        Loc.current = savedLanguage
        return out
    }

    private struct Circle2 {
        var name: String
        var center: CGPoint
        var radius: CGFloat
    }

    private struct Label {
        var name: String
        var slot: SkillSlot
        var rect: CGRect
    }

    private func buttons(_ l: HUDLayout) -> [Circle2] {
        var out = AttackButtonSlot.allCases.map {
            Circle2(name: "attack_\($0.rawValue)", center: l.attackCenter(for: $0), radius: l.attackDiameter(for: $0) / 2)
        }
        for slot in SkillSlot.actives {
            out.append(Circle2(name: "skill\(slot.rawValue)", center: l.skillCenter(slot),
                               radius: (slot == .ultimate ? l.ultDiameter : l.skillDiameter) / 2))
        }
        out.append(Circle2(name: "spell0", center: l.spellCenter(0), radius: l.spellDiameter / 2))
        out.append(Circle2(name: "spell1", center: l.spellCenter(1), radius: l.spellDiameter / 2))
        out.append(Circle2(name: "recall", center: l.recallCenter, radius: l.recallDiameter / 2))
        return out
    }

    /// 習得バッジ（上下 2pt の揺れを含む）。
    private func badges(_ l: HUDLayout) -> [Circle2] {
        SkillSlot.actives.map { Circle2(name: "level\($0.rawValue)", center: l.levelBadgeCenter($0), radius: l.levelBadgeReach) }
    }

    /// 各スキルのタグの矩形（全タグのうち最も幅の広いものと最も狭いもの。どちらも同じ規則で置く）。
    private func labels(_ l: HUDLayout, language: AppLanguage) -> [Label] {
        Loc.current = language
        let fs = l.controlLabelFontSize
        let sizes = HUDSkillTag.allCases.filter { $0 != .passive }.map { HUDControlLabel.estimatedSize($0.label, fontSize: fs) }
        let wide = sizes.max { $0.width < $1.width }!
        let short = sizes.min { $0.width < $1.width }!
        func rect(_ c: CGPoint, _ s: CGSize) -> CGRect {
            CGRect(x: c.x - s.width / 2, y: c.y - s.height / 2, width: s.width, height: s.height)
        }
        var out: [Label] = []
        for slot in SkillSlot.actives {
            out.append(Label(name: "skill\(slot.rawValue)", slot: slot, rect: rect(l.skillLabelCenter(slot, size: wide), wide)))
            out.append(Label(name: "skill\(slot.rawValue)-short", slot: slot, rect: rect(l.skillLabelCenter(slot, size: short), short)))
        }
        Loc.current = savedLanguage
        return out
    }

    private func distance(_ r: CGRect, _ p: CGPoint) -> CGFloat {
        let nx = min(max(p.x, r.minX), r.maxX)
        let ny = min(max(p.y, r.minY), r.maxY)
        return hypot(nx - p.x, ny - p.y)
    }

    func testLabelsDoNotOverlapControlsOrEdges() {
        for d in devices {
            for left in [false, true] {
                let l = layout(d, left: left)
                let tag = "\(d.name) \(left ? "左利き" : "右手")"
                let cs = buttons(l)
                let bs = badges(l)
                // 下部パネル・おすすめ購入（パネル右上から上へ 46pt、脈動の分を含む）・詠唱バー
                let panelH = HUDRootMetrics.heroPanelHeight(l)
                let s = min(l.scale, 1.08)
                let panel = CGRect(x: l.heroPanelCenterX - l.heroPanelWidth / 2, y: l.bottomEdge - panelH,
                                   width: l.heroPanelWidth, height: panelH)
                let quickBuy = CGRect(x: panel.maxX - 44 + 2 * s, y: panel.minY - 46 * s, width: 44, height: 44).insetBy(dx: -2, dy: -2)
                let channel = CGRect(x: l.heroPanelCenterX - 105, y: panel.minY - 60 * s - 14, width: 210, height: 28)
                for lang in [AppLanguage.ja, .en] {
                    let ls = labels(l, language: lang)
                    for lb in ls {
                        let r = lb.rect
                        for c in cs + bs {
                            XCTAssertGreaterThan(distance(r, c.center), c.radius + 0.5,
                                                 "\(tag) \(lang) タグ \(lb.name) が \(c.name) に重なる")
                        }
                        XCTAssertGreaterThanOrEqual(r.minX, l.leadingEdge, "\(tag) \(lb.name) が左の Safe Area にかかる")
                        XCTAssertLessThanOrEqual(r.maxX, l.trailingEdge, "\(tag) \(lb.name) が右の Safe Area にかかる")
                        XCTAssertGreaterThan(r.minY, l.topEdge + l.topButtonSize, "\(tag) \(lb.name) が上部の情報にかかる")
                        XCTAssertLessThanOrEqual(r.maxY, l.bottomEdge, "\(tag) \(lb.name) がホームインジケータにかかる")
                        XCTAssertFalse(r.intersects(panel), "\(tag) \(lb.name) が下部パネルに重なる")
                        XCTAssertFalse(r.intersects(quickBuy), "\(tag) \(lb.name) がおすすめ購入に重なる")
                        XCTAssertFalse(r.intersects(channel), "\(tag) \(lb.name) が詠唱バーに重なる")
                        XCTAssertFalse(r.intersects(l.minimapDockFrame), "\(tag) \(lb.name) がミニマップに重なる")
                        // 自分のボタンの縁から 4pt 以内で、他のどのボタンより自分のボタンに近い（どのボタンのタグか迷わない）
                        let own = cs.first { $0.name == "skill\(lb.slot.rawValue)" }!
                        let ownGap = distance(r, own.center) - own.radius
                        XCTAssertLessThanOrEqual(ownGap, 4, "\(tag) \(lb.name) がボタンから離れている")
                        for c in cs where c.name != own.name {
                            XCTAssertGreaterThan(distance(r, c.center) - c.radius, ownGap + 2,
                                                 "\(tag) \(lang) \(lb.name) が \(c.name) の方に近い")
                        }
                    }
                    let main = ls.filter { !$0.name.hasSuffix("-short") }
                    for i in main.indices {
                        for j in main.indices where j > i {
                            XCTAssertFalse(main[i].rect.insetBy(dx: -1, dy: -1).intersects(main[j].rect),
                                           "\(tag) \(lang) タグ \(main[i].name) と \(main[j].name) が重なる")
                        }
                    }
                }
            }
        }
    }

    func testLabelPlacementSidesAndMirror() {
        for d in devices {
            let r = layout(d, left: false)
            let l = layout(d, left: true)
            let s = HUDControlLabel.estimatedSize("範囲技", fontSize: r.controlLabelFontSize)
            for slot in SkillSlot.actives {
                let rc = r.skillLabelCenter(slot, size: s), lc = l.skillLabelCenter(slot, size: s)
                XCTAssertEqual(rc.x, d.size.width - lc.x, accuracy: 1e-6, "\(d.name) \(slot)")
                XCTAssertEqual(rc.y, lc.y, accuracy: 1e-6, "\(d.name) \(slot)")
            }
            // スキル1・2 はボタンの真下
            for slot in [SkillSlot.skill1, .skill2] {
                let c = r.skillCenter(slot)
                XCTAssertEqual(r.skillLabelCenter(slot, size: s).x, c.x, accuracy: 1e-6)
                XCTAssertGreaterThan(r.skillLabelCenter(slot, size: s).y - s.height / 2, c.y + r.skillDiameter / 2)
            }
            // スキル3・必殺技は画面中央側（右手配置は左、左利きは右）
            for slot in [SkillSlot.skill3, .ultimate] {
                XCTAssertLessThan(r.skillLabelCenter(slot, size: s).x, r.skillCenter(slot).x, "\(d.name) \(slot)")
                XCTAssertGreaterThan(l.skillLabelCenter(slot, size: s).x, l.skillCenter(slot).x, "\(d.name) \(slot)")
            }
        }
    }

    // MARK: 死亡中の見た目

    func testDeadStyleKeepsArtVisible() {
        // 全体を 0.45 まで薄くしていた以前と違い、絵柄は見えたまま（彩度・明度を少し落として少し透かすだけ）
        XCTAssertGreaterThanOrEqual(HUDDeadStyle.opacity, 0.7)
        XCTAssertGreaterThan(HUDDeadStyle.brightness, -0.25)
        XCTAssertLessThan(HUDDeadStyle.saturation, 1)
        XCTAssertLessThan(HUDDeadStyle.stickOpacity, 1)
        // クールダウンの幕は秒数を読める濃さ（絵柄は透ける）
        XCTAssertLessThan(HUDCooldownOverlay.shade, 0.6)
        for lang in [AppLanguage.ja, .en] {
            Loc.current = lang
            XCTAssertFalse(HUDVitalsBars.respawningCaption.isEmpty)
            XCTAssertFalse(HUDShopBeckon.hint.isEmpty)
        }
        Loc.current = .ja
        XCTAssertEqual(HUDVitalsBars.respawningCaption, "復活待ち")
    }

    @MainActor
    private func fixtureModel() -> HUDModel {
        let config = MatchFactory.practiceMatch(humanHeroID: "H001", humanName: "Tester", options: PracticeOptions(), seed: 17)
        return HUDModel(controller: BattleController(launch: BattleLaunch(config: config)))
    }

    /// 描画したボタンの平均の明るさ（0〜1、透明部分は除く）。
    @MainActor
    private func meanLuminance<V: View>(_ view: V, size: CGFloat) -> (luma: Double, alpha: Double) {
        let renderer = ImageRenderer(content: view.frame(width: size, height: size).environment(\.colorScheme, .dark))
        renderer.scale = 1
        guard let cg = renderer.cgImage else { XCTFail("描画できない"); return (0, 0) }
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var luma = 0.0, alpha = 0.0
        for k in stride(from: 0, to: px.count, by: 4) {
            let r = Double(px[k]), g = Double(px[k + 1]), b = Double(px[k + 2])
            luma += (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
            alpha += Double(px[k + 3]) / 255
        }
        let n = Double(w * h)
        return (luma / n, alpha / n)
    }

    @MainActor
    func testDeadSkillButtonIsDimmedButVisible() {
        let model = fixtureModel()
        var sn = HUDSkillSnapshot(slot: .skill1)
        sn.archetype = .cone
        sn.rank = 1
        sn.castable = true
        let d: CGFloat = 62
        let alive = meanLuminance(HUDSkillButton(model: model, snapshot: sn, role: .arcanist, diameter: d, center: .zero,
                                                 name: "", tag: "範囲技", dead: false, highlighted: false), size: d)
        var deadSnap = sn
        deadSnap.castable = false
        let dead = meanLuminance(HUDSkillButton(model: model, snapshot: deadSnap, role: .arcanist, diameter: d, center: .zero,
                                                name: "", tag: "範囲技", dead: true, highlighted: false), size: d)
        XCTAssertGreaterThan(alive.luma, 0.02)
        XCTAssertLessThan(dead.luma, alive.luma * 0.92, "死亡中は暗くなる")
        XCTAssertGreaterThan(dead.luma, alive.luma * 0.4, "死亡中も絵柄が見える")
        XCTAssertGreaterThan(dead.alpha, alive.alpha * 0.7, "全体を薄くしない")
    }
}
