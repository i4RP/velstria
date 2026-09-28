import Foundation
import VelstriaCore

// 担当: app-services（最小実装。バンドル内容・購入上限・重複ポリシー・価格係数・Gem 消費順を実装すること）

enum StorePurchaseResult: Equatable {
    case success(granted: [String])
    case insufficientFunds
    case alreadyOwned
    case limitReached
    case invalid
}

enum EconomyService {
    /// v1.0: ヒーロー解放価格はマスター価格 × 0.25（DESIGN §12）。
    static let heroPriceMultiplier = 0.25

    /// SKU の実売価格。
    static func price(of item: StoreItemDef) -> Int {
        item.type == .heroUnlock ? Int((Double(item.price) * heroPriceMultiplier).rounded()) : item.price
    }

    /// 既に所持している（購入不可）か。
    static func isOwned(_ item: StoreItemDef, profile: Profile) -> Bool {
        switch item.type {
        case .heroUnlock: return profile.ownedHeroIDs.contains(item.grantID)
        case .cosmetic: return profile.ownedCosmeticIDs.contains(item.grantID)
        case .bundle: return false
        }
    }

    /// バンドルの中身（cosmetic_id の配列）。
    static func bundleContents(_ grantID: String, master: MasterData) -> [String] {
        []
    }

    /// ゲーム内通貨で購入。
    static func purchase(sku: String, profile: inout Profile, master: MasterData) -> StorePurchaseResult {
        guard let item = master.storeItem(sku) else { return .invalid }
        if isOwned(item, profile: profile) { return .alreadyOwned }
        let cost = price(of: item)
        switch item.currency {
        case .starlightCoin:
            guard profile.starlightCoin >= cost else { return .insufficientFunds }
            profile.starlightCoin -= cost
        case .astralGem:
            guard spendGems(cost, profile: &profile) else { return .insufficientFunds }
        }
        switch item.type {
        case .heroUnlock: profile.ownedHeroIDs.append(item.grantID)
        case .cosmetic: profile.ownedCosmeticIDs.append(item.grantID)
        case .bundle: break
        }
        return .success(granted: [item.grantID])
    }

    /// Gem 消費（無償 → 有償の順）。不足なら false で何もしない。
    static func spendGems(_ amount: Int, profile: inout Profile) -> Bool {
        guard profile.totalGem >= amount else { return false }
        let fromFree = min(profile.freeGem, amount)
        profile.freeGem -= fromFree
        profile.paidGem -= amount - fromFree
        return true
    }
}
