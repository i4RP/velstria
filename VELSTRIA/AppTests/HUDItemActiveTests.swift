import XCTest
import SwiftUI
@testable import VELSTRIA
import VelstriaCore

// 担当: battle-hud。アクティブ装備（ウィンタークラウン・ナチュラルウィンド）・隠蔽のボタンと効果中のポーションの表示値
// （HUDItemActiveLogic）、ボタンの配置（HUDLayout.itemActiveCenter / gearActiveCenter）。

final class HUDItemActiveTests: XCTestCase {
    private func makeHero(items: [String] = []) -> (HeroData, SimContext) {
        let config = MatchFactory.standardMatch(humanHeroID: "H003", humanName: "T", seed: 11)
        let sim = Simulation(config: config)
        var h = sim.state.units[sim.state.humanHeroIndex!].hero!
        h.items = items
        h.itemInvested = items.map { sim.ctx.master.item($0)?.priceGold ?? 0 }
        return (h, sim.ctx)
    }

    // MARK: 表示値

    func testItemActiveFollowsEngine() throws {
        let (none, ctx) = makeHero(items: ["EQ133"])
        XCTAssertNil(HUDItemActiveLogic.snapshot(none, time: 10, master: ctx.master).item, "アクティブの無い装備では出ない")
        for id in ["EQ113", "EQ117"] {
            let (h, _) = makeHero(items: ["EQ133", id])
            let info = try XCTUnwrap(ItemEffects.activeInfo(h, time: 10, master: ctx.master))
            let snap = try XCTUnwrap(HUDItemActiveLogic.snapshot(h, time: 10, master: ctx.master).item)
            XCTAssertEqual(snap.itemID, id)
            XCTAssertEqual(snap.cooldownTotal, info.cooldown)
            XCTAssertTrue(snap.ready)
            XCTAssertEqual(snap.cooldownFraction, 0)
        }
    }

    func testItemActiveCooldownAfterUse() throws {
        let config = MatchFactory.standardMatch(humanHeroID: "H003", humanName: "T", seed: 11)
        var state = Simulation(config: config).state
        let i = try XCTUnwrap(state.humanHeroIndex)
        state.units[i].hero?.items = ["EQ113"]
        state.units[i].hero?.itemInvested = [MasterData.shared.item("EQ113")?.priceGold ?? 0]
        let sim = Simulation(snapshot: state)
        sim.step(commands: [HeroCommand(heroID: sim.state.units[i].id, command: .useItemActive)])
        let h = try XCTUnwrap(sim.state.units[i].hero)
        let info = try XCTUnwrap(ItemEffects.activeInfo(h, time: sim.state.time, master: sim.ctx.master))
        let snap = try XCTUnwrap(HUDItemActiveLogic.snapshot(h, time: sim.state.time, master: sim.ctx.master).item)
        XCTAssertGreaterThan(snap.cooldown, 0, "使った直後はクールダウン中")
        XCTAssertFalse(snap.ready)
        XCTAssertEqual(snap.cooldown, HUDItemActiveLogic.rounded(info.remaining))
        XCTAssertGreaterThan(snap.cooldownFraction, 0.9)
        XCTAssertLessThanOrEqual(snap.cooldownFraction, 1)
    }

    func testConcealButtonOnlyAfterUnlock() throws {
        let k = Balance.Gear.self
        let made = makeHero(items: [k.baseBootsID])
        var h = made.0
        let ctx = made.1
        var g = GearState(option: .conceal)
        g.roamGold = k.blessingUnlockGold - 1
        h.gear = g
        XCTAssertNil(HUDItemActiveLogic.snapshot(h, time: 10, master: ctx.master).gear, "共栄ゴールドで解放するまで出ない")
        h.gear?.roamGold = k.blessingUnlockGold
        let ready = try XCTUnwrap(HUDItemActiveLogic.snapshot(h, time: 10, master: ctx.master).gear)
        XCTAssertNil(ready.itemID)
        XCTAssertTrue(ready.ready)
        XCTAssertEqual(ready.cooldownTotal, k.concealCooldown)
        h.gear?.abilityReadyAt = 30
        XCTAssertEqual(HUDItemActiveLogic.snapshot(h, time: 10, master: ctx.master).gear?.cooldown, 20)
        // 他のロームの祝福・靴が無い時は出ない
        h.gear?.option = .encourage
        XCTAssertNil(HUDItemActiveLogic.snapshot(h, time: 10, master: ctx.master).gear)
        h.gear?.option = .conceal
        h.items = []
        h.itemInvested = []
        XCTAssertNil(HUDItemActiveLogic.snapshot(h, time: 10, master: ctx.master).gear)
    }

    func testPotionCountsDownAndExpires() {
        let made = makeHero()
        var h = made.0
        let ctx = made.1
        XCTAssertNil(HUDItemActiveLogic.snapshot(h, time: 10, master: ctx.master).potion)
        h.itemRuntime.potionID = "EQ134"
        h.itemRuntime.potionUntil = 100
        XCTAssertEqual(HUDItemActiveLogic.snapshot(h, time: 10.2, master: ctx.master).potion,
                       HUDItemActiveSnapshot.Potion(itemID: "EQ134", remaining: 90))
        XCTAssertNil(HUDItemActiveLogic.snapshot(h, time: 100, master: ctx.master).potion, "期限を過ぎたら消える")
        XCTAssertEqual(HUDItemActiveLogic.rounded(0.04), 0.1)
        XCTAssertEqual(HUDItemActiveLogic.rounded(-1), 0)
    }

    // MARK: 配置

    /// プレイヤーの右側の操作群を確認する端末（HUDLayoutTests と同じ。iPhone SE はプレイヤーの HUD の対象外）。
    private let devices: [(name: String, size: CGSize, side: CGFloat, bottom: CGFloat)] = [
        ("iPhone 13 mini", CGSize(width: 812, height: 375), 44, 21),
        ("iPhone 16e", CGSize(width: 844, height: 390), 47, 21),
        ("iPhone 17 Pro", CGSize(width: 874, height: 402), 62, 20),
        ("iPhone 17 Pro Max", CGSize(width: 956, height: 440), 62, 20),
    ]

    func testButtonsAvoidOtherControls() {
        for d in devices {
            for left in [false, true] {
                let safe = EdgeInsets(top: 0, leading: d.side, bottom: d.bottom, trailing: d.side)
                let l = HUDLayout(size: d.size, safe: safe, leftHanded: left)
                let tag = "\(d.name) \(left ? "左利き" : "右手")"
                let r = l.itemActiveDiameter / 2
                let tap = max(44, l.itemActiveDiameter) / 2
                let panelTop = l.bottomEdge - HUDRootMetrics.heroPanelHeight(l)
                for (name, c) in [("item", l.itemActiveCenter), ("gear", l.gearActiveCenter)] {
                    let disc = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
                    let hit = CGRect(x: c.x - tap, y: c.y - tap, width: tap * 2, height: tap * 2)
                    // 攻撃・スキル・スペル・帰還のボタン
                    for other in l.signalControlDiscs {
                        XCTAssertGreaterThan(hypot(c.x - other.center.x, c.y - other.center.y), r + other.radius + 2,
                                             "\(tag) \(name) が操作部品と重なる")
                    }
                    // 習得バッジのタップ領域
                    for badge in l.signalLevelBadgeRects {
                        XCTAssertFalse(badge.intersects(hit), "\(tag) \(name) が習得バッジと重なる")
                    }
                    // シグナル列
                    for slot in HUDSignalSlot.allCases {
                        XCTAssertFalse(l.signalSlotFrame(slot).intersects(disc), "\(tag) \(name) がシグナル列と重なる")
                    }
                    // キルフィードはスペル・習得バッジより画面中央側に置かれる（端からの深さが予約幅より浅い）
                    let depth = left ? disc.maxX - l.leadingEdge : l.trailingEdge - disc.minX
                    XCTAssertLessThan(depth, l.killFeedSideReserve, "\(tag) \(name) がキルフィードの位置にかかる")
                    // 画面内・Safe Area 内・下部パネルより上
                    XCTAssertGreaterThanOrEqual(disc.minX, l.leadingEdge, tag)
                    XCTAssertLessThanOrEqual(disc.maxX, l.trailingEdge, tag)
                    XCTAssertGreaterThan(disc.minY, l.signalRowTop, tag)
                    XCTAssertLessThan(disc.maxY, panelTop, tag)
                }
                XCTAssertGreaterThan(hypot(l.itemActiveCenter.x - l.gearActiveCenter.x, l.itemActiveCenter.y - l.gearActiveCenter.y),
                                     tap * 2, "\(tag) 2 つのボタンのタップ領域が重なる")
            }
        }
    }

    func testLeftHandedMirrorsButtons() {
        for d in devices {
            let safe = EdgeInsets(top: 0, leading: d.side, bottom: d.bottom, trailing: d.side)
            let r = HUDLayout(size: d.size, safe: safe, leftHanded: false)
            let l = HUDLayout(size: d.size, safe: safe, leftHanded: true)
            XCTAssertEqual(r.itemActiveCenter.x, d.size.width - l.itemActiveCenter.x, accuracy: 1e-6, d.name)
            XCTAssertEqual(r.itemActiveCenter.y, l.itemActiveCenter.y, accuracy: 1e-6, d.name)
            XCTAssertEqual(r.gearActiveCenter.x, d.size.width - l.gearActiveCenter.x, accuracy: 1e-6, d.name)
            XCTAssertEqual(r.gearActiveCenter.y, l.gearActiveCenter.y, accuracy: 1e-6, d.name)
            XCTAssertGreaterThanOrEqual(max(44, r.itemActiveDiameter), 44)
        }
    }
}
