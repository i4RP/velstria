import Foundation
import VelstriaCore

// 担当: battle-renderer / battle-hud。キット層（ヒーロー固有スキル。docs/SKILL_KITS.md）の状態の「見え方」を決める純粋な対応表。
// 世界の表示（StatusIndicators / HeroVisual）と HUD の状態アイコン（HUDSymbols）が同じ判定を使う。RealityKit・SwiftUI に依存しない。
// 元の情報は sim の StatusEffect.kind と tag（Core の KitTags と同じ書式）:
//   マーク      kind == .mark、tag = "kit.<ヒーロー ID>.<名前>.<所有者の ID>"（例: kit.H026.sc.12）、magnitude = スタック数
//   H031 の凍結  kind == .stun、tag = "kit.H031.freeze"（霜風・氷河）
//   氷の誇り     kind == .suppress、tag = "kit.H031.prideFreeze"（致命傷を受けた H031 自身の凍結）

/// 状態の表示の種類（種類 + tag から決まる）。
enum KitStatusLook: Equatable {
    case generic
    /// H031 の凍結（スタンの一種）。
    case freeze
    /// 氷の誇り（H031 自身の凍結。suppress）。
    case prideFreeze
    /// マーク（所有者のヒーロー ID と名前）。
    case mark(heroID: String, name: String)
}

enum KitStatusVisuals {
    static let freezeHeroID = "H031"
    static let freezeTag = "kit.H031.freeze"
    static let prideFreezeTag = "kit.H031.prideFreeze"
    /// ステルス中の自分・味方（と観戦）に見えるモデルの不透明度。
    static let stealthAllyOpacity: Float = 0.4

    // MARK: タグの読み取り

    struct MarkTag: Equatable {
        var heroID: String
        var name: String
        /// 所有者のユニット ID（書式に無ければ nil）。
        var owner: EntityID?
    }

    /// "kit.H026.sc.12" → (H026, sc, 12)。キットの tag でなければ nil。
    static func parseMark(_ tag: String) -> MarkTag? {
        let parts = tag.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3, parts[0] == "kit", isHeroID(parts[1]), !parts[2].isEmpty else { return nil }
        let owner: EntityID? = parts.count >= 4 ? EntityID(parts[3]) : nil
        return MarkTag(heroID: String(parts[1]), name: String(parts[2]), owner: owner)
    }

    private static func isHeroID(_ s: Substring) -> Bool {
        s.count == 4 && s.first == "H" && s.dropFirst().allSatisfy { $0 >= "0" && $0 <= "9" }
    }

    /// 種類 + tag → 表示の種類。
    static func look(kind: StatusKind, tag: String) -> KitStatusLook {
        switch kind {
        case .stun where tag == freezeTag: return .freeze
        case .suppress where tag == prideFreezeTag: return .prideFreeze
        case .mark:
            guard let m = parseMark(tag) else { return .generic }
            return .mark(heroID: m.heroID, name: m.name)
        default: return .generic
        }
    }

    /// 氷の殻で表す状態か（スタン・suppress のうち H031 の凍結）。
    static func isFreeze(_ s: StatusEffect) -> Bool {
        switch look(kind: s.kind, tag: s.tag) {
        case .freeze, .prideFreeze: return true
        default: return false
        }
    }

    /// 同じ状態アイコンにまとめる区別（HUD の状態アイコンが 種類 + この値 でまとめる。0 = 汎用）。
    static func variant(kind: StatusKind, tag: String) -> Int {
        switch look(kind: kind, tag: tag) {
        case .generic: return 0
        case .freeze: return 1
        case .prideFreeze: return 2
        case .mark(let heroID, _): return 100 + (Int(heroID.dropFirst()) ?? 0)
        }
    }

    // MARK: 世界の表示

    /// ユニットの頭上に出すマークの記号（所有者のヒーロー ID とスタック数）。
    struct MarkGlyph: Equatable {
        var heroID: String
        var stacks: Int
    }

    /// 付いているマークのうち、頭上に出す 1 つ（スタックが最大のもの。同数なら先に付いたもの）。
    static func markGlyph(in statuses: [StatusEffect]) -> MarkGlyph? {
        var best: MarkGlyph?
        for s in statuses where s.kind == .mark && s.remaining > 0 {
            let stacks = max(1, Int(s.magnitude.rounded()))
            if let b = best, b.stacks >= stacks { continue }
            best = MarkGlyph(heroID: parseMark(s.tag)?.heroID ?? "", stacks: stacks)
        }
        return best
    }

    /// 記号の大きさ（スタックが多いほど少し大きく。上限あり）。
    static func markScale(stacks: Int) -> Float { 1 + 0.14 * Float(min(max(stacks, 1), 5) - 1) }

    /// 所有者ごとの記号の色（ヒーローの演出の色味に合わせる。キットの無いヒーローは金）。
    static func markColor(heroID: String) -> RGB {
        switch heroID {
        case "H025": return RGB(0.55, 1.0, 0.72)    // ルミナ: 翠緑・月光
        case "H026": return RGB(0.78, 0.55, 1.0)    // エウリア: 紫・電光
        case "H027": return RGB(0.65, 0.78, 1.0)    // ジャルド: 銀青
        case "H028": return RGB(0.35, 0.88, 1.0)    // ザイル: シアン
        case "H029": return RGB(1.0, 0.82, 0.35)    // ボルグ: 金
        case "H030": return RGB(1.0, 0.58, 0.82)    // ライナ: 桃
        case "H031": return RGB(0.65, 0.92, 1.0)    // オーリア: 氷青
        case "H032": return RGB(1.0, 0.55, 0.22)    // ディアス: 熾火の橙
        case "H033": return RGB(0.95, 0.2, 0.3)     // ヴァルド: 深紅
        case "H034": return RGB(0.88, 0.45, 0.28)   // ゴルム: 錆びた赤
        default: return RGB(1.0, 0.86, 0.45)
        }
    }

    /// ステルス中のモデルの不透明度: 自分・味方・観戦者には薄く見せる。敵の視点では変えない
    /// （敵のステルスは視界の判定で見えないままで、見えている = 看破された敵を薄くもしない）。
    static func stealthOpacity(stealthed: Bool, dead: Bool, unitTeam: Team, viewerTeam: Team?) -> Float {
        guard stealthed, !dead else { return 1 }
        guard let viewer = viewerTeam else { return stealthAllyOpacity }
        return viewer == unitTeam ? stealthAllyOpacity : 1
    }

    /// 氷の誇りの「準備できた」輪を出すか: H031 の生きているヒーローで、パッシブのバッジが「準備できた」（上限 1 のスタックが満ちた）。
    /// 凍結中・再発動待ちはタイマー表示なので出さない。
    static func showsIceReady(heroID: String, alive: Bool, badge: KitBadge?) -> Bool {
        guard heroID == freezeHeroID, alive, let b = badge else { return false }
        return b.kind == .stacks && b.maxValue > 0 && b.value >= b.maxValue
    }

    /// 同上（ユニットから。バッジは sim の状態から計算する純粋な関数なので、描画側のスナップショットから誰のものでも読める）。
    static func showsIceReady(of u: VelstriaCore.Unit) -> Bool {
        guard let h = u.hero, h.heroID == freezeHeroID, u.isAlive, !h.isDead else { return false }
        return showsIceReady(heroID: h.heroID, alive: true, badge: HeroKits.badge(h, slot: .passive))
    }

    // MARK: HUD の状態アイコン

    /// マークの名前（ja, en）。未登録のマークは nil（汎用の「刻印」）。
    static func markName(heroID: String, name: String) -> (ja: String, en: String)? {
        switch (heroID, name) {
        case ("H026", "sc"): return ("超伝導", "Superconduct")
        case ("H028", "bane"): return ("空断の理", "Enemy's Bane")
        case ("H029", "wave"): return ("衝撃波の印", "Shockwave mark")
        case ("H030", "void"): return ("虚空の印", "Void mark")
        default: return nil
        }
    }

    /// マークの SF Symbols 名（未登録は nil = 汎用の "scope"）。
    static func markSymbol(heroID: String, name: String) -> String? {
        switch (heroID, name) {
        case ("H026", "sc"): return "bolt.fill"
        case ("H030", "void"): return "sparkle"
        default: return nil
        }
    }

    static let freezeSymbol = "snowflake"

    /// HUD の存在確認テスト用（HUDSymbols.all に加える）。
    static let hudSymbols: [String] = [freezeSymbol, "bolt.fill", "sparkle"]
}
