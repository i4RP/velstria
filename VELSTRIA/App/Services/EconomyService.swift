import Foundation
import VelstriaCore

// 担当: app-services
// ゲーム内通貨（StarlightCoin / AstralGem）でのストア購入。
// - 価格: ヒーロー解放はマスター価格 × heroPriceMultiplier（0.25）、それ以外はマスター価格。
// - Gem 消費順: 無償 Gem → 有償 Gem（DESIGN §13）。
// - 購入上限: profile.storePurchases の SKU 別購入回数 ≥ purchase_limit で limitReached。
// - 重複ポリシー（マスター duplicate_policy「購入不可または同価値通貨へ変換（商品設定で固定）」の v1.0 設定）:
//     コスメ / ヒーロー単品 → 所持済みなら購入不可（alreadyOwned）
//     バンドル            → 中身が全て所持済みなら購入不可。一部所持の場合は購入でき、
//                           所持済みの中身 1 つにつき「その Gem 価格の 50%」を無償 Gem で返還する
//                           （ただし支払額のうち重複分の按分額が上限。bundlePreview 参照）。
// - バンドルの中身（決定論的な対応表）:
//     BUNDLE_nn（nn = 1 始まり）→ マスターのコスメ（cosmetic_id 昇順）の [4(nn−1), 4(nn−1)+3] 番目の 4 個。
//     例: BUNDLE_01 = CO001〜CO004、BUNDLE_18 = CO069〜CO072。
//     マスターは種別が 6 周期・レア度が 4 周期で並ぶため、各バンドルは Common/Rare/Epic/Mythic を 1 個ずつ含み、
//     種別も 4 種に分散する。コスメ数を超える番号は先頭へ回り込み、同一バンドル内の重複は除く。

enum StorePurchaseResult: Equatable {
    case success(granted: [String])
    case insufficientFunds
    case alreadyOwned
    case limitReached
    case invalid
}

/// バンドル購入前の確認内容（UI の確認ダイアログ用）。
struct BundlePreview: Equatable {
    /// 新たに入手するコスメ。
    var newItems: [String]
    /// 所持済み（無償 Gem へ変換される）コスメ。
    var duplicates: [String]
    /// 重複分の返還 Gem 合計。
    var refundGems: Int
    /// 中身を単品で買った場合の Gem 合計。
    var totalValueGems: Int
}

enum EconomyService {
    /// v1.0: ヒーロー解放価格はマスター価格 × 0.25（DESIGN §12）。
    static let heroPriceMultiplier = 0.25
    /// 重複コスメの返還率（Gem 価格に対する割合）。
    static let duplicateRefundRate = 0.5
    /// バンドル 1 個あたりのコスメ数。
    static let bundleSize = 4
    /// ストア SKU が無いコスメのレア度別 Gem 価格（マスターの単品価格帯と同じ）。
    static func referenceGemPrice(_ rarity: Rarity) -> Int {
        switch rarity {
        case .common: return 120
        case .rare: return 260
        case .epic: return 520
        case .mythic: return 880
        }
    }

    // MARK: - 価格・所持

    /// SKU の実売価格。
    static func price(of item: StoreItemDef) -> Int {
        item.type == .heroUnlock ? Int((Double(item.price) * heroPriceMultiplier).rounded()) : item.price
    }

    /// 既に所持している（購入不可）か。バンドルは中身が全て所持済みの場合。
    static func isOwned(_ item: StoreItemDef, profile: Profile) -> Bool {
        isOwned(item, profile: profile, master: .shared)
    }

    static func isOwned(_ item: StoreItemDef, profile: Profile, master: MasterData) -> Bool {
        switch item.type {
        case .heroUnlock: return profile.ownedHeroIDs.contains(item.grantID)
        case .cosmetic: return profile.ownedCosmeticIDs.contains(item.grantID)
        case .bundle:
            let contents = bundleContents(item.grantID, master: master)
            return !contents.isEmpty && contents.allSatisfy { profile.ownedCosmeticIDs.contains($0) }
        }
    }

    static func isOwned(cosmeticID: String, profile: Profile) -> Bool {
        profile.ownedCosmeticIDs.contains(cosmeticID)
    }

    static func isOwned(heroID: String, profile: Profile) -> Bool {
        profile.ownedHeroIDs.contains(heroID)
    }

    /// 所持通貨で支払えるか。
    static func canAfford(_ item: StoreItemDef, profile: Profile) -> Bool {
        let cost = price(of: item)
        switch item.currency {
        case .starlightCoin: return profile.starlightCoin >= cost
        case .astralGem: return profile.totalGem >= cost
        }
    }

    /// SKU の購入回数。
    static func purchaseCount(sku: String, profile: Profile) -> Int {
        profile.storePurchases.first { $0.sku == sku }?.count ?? 0
    }

    /// 残り購入可能回数（nil = 無制限）。
    static func remainingPurchases(_ item: StoreItemDef, profile: Profile) -> Int? {
        guard item.purchaseLimit > 0 else { return nil }
        return max(0, item.purchaseLimit - purchaseCount(sku: item.sku, profile: profile))
    }

    static func isLimitReached(_ item: StoreItemDef, profile: Profile) -> Bool {
        remainingPurchases(item, profile: profile) == 0
    }

    // MARK: - 一覧（UI 用）

    /// 種別ごとのストア商品（SKU 昇順）。
    static func storeItems(ofType type: StoreItemType, master: MasterData = .shared) -> [StoreItemDef] {
        master.store.filter { $0.type == type }
    }

    /// 種別ごとのコスメ（cosmetic_id 昇順）。
    static func cosmetics(ofType type: CosmeticType, master: MasterData = .shared) -> [CosmeticDef] {
        master.cosmetics.filter { $0.type == type }
    }

    /// ヒーロー専用スキン。
    static func skins(forHero heroID: String, master: MasterData = .shared) -> [CosmeticDef] {
        master.cosmetics.filter { $0.type == .heroSkin && $0.heroID == heroID }
    }

    /// コスメを単品販売している SKU。
    static func storeItem(forCosmetic cosmeticID: String, master: MasterData = .shared) -> StoreItemDef? {
        master.store.first { $0.type == .cosmetic && $0.grantID == cosmeticID }
    }

    /// ヒーロー解放の SKU。
    static func storeItem(forHero heroID: String, master: MasterData = .shared) -> StoreItemDef? {
        master.store.first { $0.type == .heroUnlock && $0.grantID == heroID }
    }

    /// コスメの Gem 価格（単品 SKU があればその価格、無ければレア度別の参考価格）。
    static func gemPrice(ofCosmetic cosmeticID: String, master: MasterData = .shared) -> Int {
        if let item = storeItem(forCosmetic: cosmeticID, master: master), item.currency == .astralGem {
            return item.price
        }
        guard let def = master.cosmetic(cosmeticID) else { return 0 }
        return referenceGemPrice(def.rarity)
    }

    /// 重複コスメの返還 Gem（Gem 価格の 50%）。
    static func duplicateRefundGems(cosmeticID: String, master: MasterData = .shared) -> Int {
        Int((Double(gemPrice(ofCosmetic: cosmeticID, master: master)) * duplicateRefundRate).rounded(.down))
    }

    /// 所持済みヒーローを報酬で受け取った場合の返還 Coin（解放価格の 50%）。
    static func heroDuplicateRefundCoins(heroID: String, master: MasterData = .shared) -> Int {
        guard let item = storeItem(forHero: heroID, master: master) else { return 0 }
        return Int((Double(price(of: item)) * duplicateRefundRate).rounded(.down))
    }

    // MARK: - バンドル

    /// バンドルの中身（cosmetic_id の配列）。対応表はファイル冒頭のコメント参照。
    static func bundleContents(_ grantID: String, master: MasterData) -> [String] {
        guard grantID.hasPrefix("BUNDLE_"), let number = Int(grantID.dropFirst("BUNDLE_".count)), number >= 1 else {
            return []
        }
        let all = master.cosmetics
        guard !all.isEmpty else { return [] }
        var result: [String] = []
        let start = (number - 1) * bundleSize
        for k in 0..<bundleSize {
            let id = all[(start + k) % all.count].cosmeticID
            if !result.contains(id) { result.append(id) }
        }
        return result
    }

    /// バンドル購入時の内訳。
    /// 返還 Gem は重複 1 つにつき単品 Gem 価格の 50% だが、バンドルの支払額のうち重複分が占める按分額
    /// （価格 × 重複分の単品価値 / 中身の単品価値合計）を上限とする。
    /// 単品価値に比べて安いバンドルで、返還が支払額を上回って Gem が増えるのを防ぐため。
    static func bundlePreview(_ item: StoreItemDef, profile: Profile, master: MasterData = .shared) -> BundlePreview {
        let contents = bundleContents(item.grantID, master: master)
        var preview = BundlePreview(newItems: [], duplicates: [], refundGems: 0, totalValueGems: 0)
        var duplicateValue = 0
        for id in contents {
            let value = gemPrice(ofCosmetic: id, master: master)
            preview.totalValueGems += value
            if profile.ownedCosmeticIDs.contains(id) {
                preview.duplicates.append(id)
                preview.refundGems += duplicateRefundGems(cosmeticID: id, master: master)
                duplicateValue += value
            } else {
                preview.newItems.append(id)
            }
        }
        if item.currency == .astralGem, preview.totalValueGems > 0 {
            let share = Double(price(of: item)) * Double(duplicateValue) / Double(preview.totalValueGems)
            preview.refundGems = min(preview.refundGems, max(0, Int(share.rounded(.down))))
        }
        return preview
    }

    // MARK: - 購入

    /// ゲーム内通貨で購入。成功時の granted は新たに入手した ID（バンドルの重複分は含まない）。
    static func purchase(sku: String, profile: inout Profile, master: MasterData) -> StorePurchaseResult {
        guard let item = master.storeItem(sku) else { return .invalid }
        switch item.type {
        case .heroUnlock: guard master.hero(item.grantID) != nil else { return .invalid }
        case .cosmetic: guard master.cosmetic(item.grantID) != nil else { return .invalid }
        case .bundle: guard !bundleContents(item.grantID, master: master).isEmpty else { return .invalid }
        }
        if isOwned(item, profile: profile, master: master) { return .alreadyOwned }
        if isLimitReached(item, profile: profile) { return .limitReached }
        let cost = price(of: item)
        guard cost >= 0 else { return .invalid }
        switch item.currency {
        case .starlightCoin:
            guard profile.starlightCoin >= cost else { return .insufficientFunds }
            profile.starlightCoin -= cost
        case .astralGem:
            guard spendGems(cost, profile: &profile) else { return .insufficientFunds }
        }
        var granted: [String] = []
        switch item.type {
        case .heroUnlock:
            profile.ownedHeroIDs.append(item.grantID)
            granted = [item.grantID]
        case .cosmetic:
            profile.ownedCosmeticIDs.append(item.grantID)
            granted = [item.grantID]
        case .bundle:
            let preview = bundlePreview(item, profile: profile, master: master)
            profile.ownedCosmeticIDs.append(contentsOf: preview.newItems)
            profile.freeGem += preview.refundGems
            granted = preview.newItems
        }
        incrementPurchaseCount(sku: item.sku, profile: &profile)
        // 所持数の実績（コスメ・ヒーロー）を購入直後に反映する
        LiveOpsService.evaluateAchievements(profile: &profile, master: master, now: Date())
        return .success(granted: granted)
    }

    private static func incrementPurchaseCount(sku: String, profile: inout Profile) {
        if let i = profile.storePurchases.firstIndex(where: { $0.sku == sku }) {
            profile.storePurchases[i].count += 1
        } else {
            profile.storePurchases.append(StorePurchaseCount(sku: sku, count: 1))
        }
    }

    /// Gem 消費（無償 → 有償の順）。不足なら false で何もしない。
    static func spendGems(_ amount: Int, profile: inout Profile) -> Bool {
        guard amount >= 0, profile.totalGem >= amount else { return false }
        let fromFree = min(profile.freeGem, amount)
        profile.freeGem -= fromFree
        profile.paidGem -= amount - fromFree
        return true
    }

    // MARK: - 装備（UI 用）

    /// 所持コスメを装備する。種別に応じた枠へ入れる（エモートは 4 枠、満杯なら先頭を押し出す）。
    @discardableResult
    static func equip(cosmeticID: String, profile: inout Profile, master: MasterData = .shared) -> Bool {
        guard profile.ownedCosmeticIDs.contains(cosmeticID), let def = master.cosmetic(cosmeticID) else { return false }
        switch def.type {
        case .heroSkin:
            guard !def.heroID.isEmpty else { return false }
            profile.equippedSkins[def.heroID] = cosmeticID
        case .recall: profile.equippedRecall = cosmeticID
        case .spawn: profile.equippedSpawn = cosmeticID
        case .killEffect: profile.equippedKillEffect = cosmeticID
        case .avatarFrame: profile.equippedAvatarFrame = cosmeticID
        case .emote:
            guard !profile.equippedEmotes.contains(cosmeticID) else { return true }
            if profile.equippedEmotes.count >= 4 { profile.equippedEmotes.removeFirst() }
            profile.equippedEmotes.append(cosmeticID)
        }
        return true
    }

    /// 装備を外す。
    static func unequip(cosmeticID: String, profile: inout Profile, master: MasterData = .shared) {
        guard let def = master.cosmetic(cosmeticID) else { return }
        switch def.type {
        case .heroSkin:
            if profile.equippedSkins[def.heroID] == cosmeticID { profile.equippedSkins[def.heroID] = nil }
        case .recall: if profile.equippedRecall == cosmeticID { profile.equippedRecall = nil }
        case .spawn: if profile.equippedSpawn == cosmeticID { profile.equippedSpawn = nil }
        case .killEffect: if profile.equippedKillEffect == cosmeticID { profile.equippedKillEffect = nil }
        case .avatarFrame: if profile.equippedAvatarFrame == cosmeticID { profile.equippedAvatarFrame = nil }
        case .emote: profile.equippedEmotes.removeAll { $0 == cosmeticID }
        }
    }

    static func isEquipped(cosmeticID: String, profile: Profile, master: MasterData = .shared) -> Bool {
        guard let def = master.cosmetic(cosmeticID) else { return false }
        switch def.type {
        case .heroSkin: return profile.equippedSkins[def.heroID] == cosmeticID
        case .recall: return profile.equippedRecall == cosmeticID
        case .spawn: return profile.equippedSpawn == cosmeticID
        case .killEffect: return profile.equippedKillEffect == cosmeticID
        case .avatarFrame: return profile.equippedAvatarFrame == cosmeticID
        case .emote: return profile.equippedEmotes.contains(cosmeticID)
        }
    }
}
