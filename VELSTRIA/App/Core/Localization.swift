import Foundation
import VelstriaCore

// 担当: 統合（契約）。
// 文字列は `L("日本語", "English")` で書く（アプリ内言語切替に即時追従するため String Catalog は使わない）。

enum Loc {
    /// 現在の表示言語（AppModel が設定変更時に更新）。
    nonisolated(unsafe) static var current: AppLanguage = Loc.resolve(.system)

    static func resolve(_ setting: AppLanguage) -> AppLanguage {
        switch setting {
        case .ja, .en: return setting
        case .system:
            let pref = Locale.preferredLanguages.first ?? "ja"
            return pref.hasPrefix("ja") ? .ja : .en
        }
    }

    static var isEnglish: Bool { current == .en }
}

/// ローカライズ文字列。
func L(_ ja: String, _ en: String) -> String {
    Loc.isEnglish ? en : ja
}

/// マスターデータの表示名（英語は MasterText オーバーレイ、無ければ日本語）。
enum MasterText {
    private static let overlay: [String: String] = {
        guard let url = Bundle.main.url(forResource: "master_en", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return dict
    }()

    /// ID（hero_id / skill_id / item_id / spell_id / rune_id / cosmetic_id / sku）→ 表示名。
    static func name(id: String, ja: String) -> String {
        guard Loc.isEnglish else { return ja }
        return overlay[id] ?? ja
    }

    /// 説明文は "<id>.desc" キー。
    static func description(id: String, ja: String) -> String {
        guard Loc.isEnglish else { return ja }
        return overlay["\(id).desc"] ?? ja
    }

    static func hero(_ h: HeroDef) -> String {
        Loc.isEnglish ? (overlay[h.heroID] ?? h.codeName) : h.displayNameJa
    }

    static func skill(_ s: SkillDef) -> String { name(id: s.skillID, ja: s.nameJa) }
    static func item(_ i: ItemDef) -> String { name(id: i.itemID, ja: i.nameJa) }
    static func spell(_ s: SpellDef) -> String { name(id: s.spellID, ja: s.nameJa) }
    static func rune(_ r: RuneDef) -> String { name(id: r.runeID, ja: r.nameJa) }
    static func cosmetic(_ c: CosmeticDef) -> String { name(id: c.cosmeticID, ja: c.nameJa) }
    static func storeItem(_ s: StoreItemDef) -> String { name(id: s.sku, ja: s.nameJa) }

    static func role(_ r: Role) -> String {
        guard Loc.isEnglish else { return r.nameJa }
        return r.rawValue
    }
}
