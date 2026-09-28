import Foundation

// 担当: core-economy
// 装備・ルーンの事前計算表。ItemDef.passivePercent / RuneDef.percent は呼ぶ度に正規表現で文字列を解析するため、
// 毎 tick の能力値再計算（ItemStats.apply）や AI の購入判断で直接使うと tick 予算を圧迫する。
// マスターは試合中不変なので、% 値とカテゴリ別の評価順を一度だけ求めて使い回す。

final class EconomyItemTable: @unchecked Sendable {
    /// 同梱マスター用（遅延初期化はスレッド安全）。
    static let shared = EconomyItemTable(master: .shared)

    /// master に対応する表。同梱マスター以外（差し替えデータ）は直近の 1 つを保持して使い回す。
    static func table(for master: MasterData) -> EconomyItemTable {
        if master === MasterData.shared { return shared }
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let t = cached, t.owner === master { return t }
        let t = EconomyItemTable(master: master)
        cached = t
        return t
    }

    private static let cacheLock = NSLock()
    /// 同梱以外のマスター用の表（cacheLock で保護。純粋な計算結果のキャッシュなので決定論に影響しない）。
    private static var cached: EconomyItemTable?

    /// 表の元になったマスター（キャッシュの照合用）。
    private weak var owner: MasterData?

    /// 装備 ID → passive_text の %（検索専用・列挙禁止）。
    private let itemPercent: [String: Double]
    /// ルーン ID → effect の %（検索専用・列挙禁止）。
    private let runePercent: [String: Double]
    /// ItemCategory.allCases の順。各カテゴリの装備を評価順（上位 Tier → 評価値 → ID 昇順）に並べたもの。
    private let ranked: [[ItemDef]]

    init(master: MasterData) {
        owner = master
        var ip: [String: Double] = [:]
        for it in master.items { ip[it.itemID] = it.passivePercent }
        var rp: [String: Double] = [:]
        for r in master.runes { rp[r.runeID] = r.percent }
        itemPercent = ip
        runePercent = rp
        ranked = ItemCategory.allCases.map { cat in
            master.items.filter { $0.category == cat }.sorted { a, b in
                if a.tier != b.tier { return a.tier > b.tier }
                let va = EconomyItemTable.value(a, percent: ip[a.itemID] ?? 0)
                let vb = EconomyItemTable.value(b, percent: ip[b.itemID] ?? 0)
                if va != vb { return va > vb }
                return a.itemID < b.itemID
            }
        }
    }

    func percent(item it: ItemDef) -> Double { itemPercent[it.itemID] ?? it.passivePercent }
    func percent(rune r: RuneDef) -> Double { runePercent[r.runeID] ?? r.percent }

    func rankedItems(_ category: ItemCategory) -> [ItemDef] {
        guard let k = ItemCategory.allCases.firstIndex(of: category) else { return [] }
        return ranked[k]
    }

    /// 推奨ビルド用の評価値（カテゴリの主要能力 + パッシブ% × 2）。
    static func value(_ it: ItemDef, percent: Double) -> Double {
        let main: Double
        switch it.category {
        case .attack: main = it.attack
        case .magic: main = it.abilityPower + it.cooldownReductionPct * 2
        case .defense: main = it.hp / 10 + it.armor + it.magicResist
        case .movement: main = it.moveSpeed
        case .utility: main = it.hp / 10 + it.cooldownReductionPct * 3
        case .jungle: main = 0
        }
        return main + percent * 2
    }
}
