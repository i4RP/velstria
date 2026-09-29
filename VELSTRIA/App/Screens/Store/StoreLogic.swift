import SwiftUI
import VelstriaCore

// 担当: ui-collection。ストア画面の分類・表示用の純粋ロジック（購入処理そのものは EconomyService / StoreKitService）。

/// ストアのカテゴリ。
enum StoreCategory: String, CaseIterable, Identifiable {
    case skins, effects, emotes, frames, heroes, gems
    var id: String { rawValue }

    var title: String {
        switch self {
        case .skins: return L("スキン", "Skins")
        case .effects: return L("演出", "Effects")
        case .emotes: return L("エモート", "Emotes")
        case .frames: return L("アバターフレーム", "Avatar Frames")
        case .heroes: return L("ヒーロー解放", "Heroes")
        case .gems: return "AstralGem"
        }
    }

    var subtitle: String {
        switch self {
        case .skins: return L("ヒーローの外見", "Hero outfits")
        case .effects: return L("帰還・出現・キル", "Recall, spawn, kill")
        case .emotes: return L("戦闘中の意思表示", "Express yourself")
        case .frames: return L("プロフィールの枠", "Profile borders")
        case .heroes: return L("Coin で解放", "Unlock with Coin")
        case .gems: return L("有償通貨の購入", "Buy premium gems")
        }
    }

    var symbol: String {
        switch self {
        case .skins: return "paintpalette.fill"
        case .effects: return "sparkles"
        case .emotes: return "bubble.left.fill"
        case .frames: return "person.crop.square.fill"
        case .heroes: return "person.2.fill"
        case .gems: return "diamond.fill"
        }
    }

    var color: Color {
        switch self {
        case .skins: return Color(red: 1.0, green: 0.55, blue: 0.70)
        case .effects: return Color(red: 0.72, green: 0.52, blue: 1.0)
        case .emotes: return Color(red: 0.45, green: 0.92, blue: 0.75)
        case .frames: return Theme.gold
        case .heroes: return Color(red: 0.45, green: 0.72, blue: 1.0)
        case .gems: return Theme.cyan
        }
    }

    var cosmeticTypes: [CosmeticType] {
        switch self {
        case .skins: return [.heroSkin]
        case .effects: return [.recall, .spawn, .killEffect]
        case .emotes: return [.emote]
        case .frames: return [.avatarFrame]
        case .heroes, .gems: return []
        }
    }
}

enum StoreCatalog {
    static func cosmetic(for item: StoreItemDef, master: MasterData) -> CosmeticDef? {
        item.type == .cosmetic ? master.cosmetic(item.grantID) : nil
    }

    /// カテゴリの商品（SKU 昇順）。
    static func items(in category: StoreCategory, master: MasterData) -> [StoreItemDef] {
        switch category {
        case .heroes:
            return master.store.filter { $0.type == .heroUnlock }
        case .gems:
            return []
        default:
            let types = category.cosmeticTypes
            return master.store.filter { item in
                guard let c = cosmetic(for: item, master: master) else { return false }
                return types.contains(c.type)
            }
        }
    }

    static func bundles(master: MasterData) -> [StoreItemDef] {
        master.store.filter { $0.type == .bundle }
    }

    /// 注目バンドル（日替わりで先頭をずらす）。
    static func featuredBundles(master: MasterData, day: Int, count: Int = 5) -> [StoreItemDef] {
        let all = bundles(master: master)
        guard !all.isEmpty else { return [] }
        let start = ((day % all.count) + all.count) % all.count
        return (0..<min(count, all.count)).map { all[(start + $0) % all.count] }
    }

    /// 端末ローカル日付の通し日数（日替わり用）。
    static func dayNumber(_ date: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: date)
        return Int(start.timeIntervalSince1970 / 86_400)
    }

    static func storeItem(forCosmetic cosmeticID: String, master: MasterData) -> StoreItemDef? {
        master.store.first { $0.type == .cosmetic && $0.grantID == cosmeticID }
    }

    static func unlockItem(heroID: String, master: MasterData) -> StoreItemDef? {
        master.store.first { $0.type == .heroUnlock && $0.grantID == heroID }
    }

    static func purchaseCount(sku: String, profile: Profile) -> Int {
        profile.storePurchases.first { $0.sku == sku }?.count ?? 0
    }

    /// 購入不可（所持済み・上限到達）か。
    static func isUnavailable(_ item: StoreItemDef, profile: Profile) -> Bool {
        if EconomyService.isOwned(item, profile: profile) { return true }
        return item.type == .bundle && item.purchaseLimit > 0
            && purchaseCount(sku: item.sku, profile: profile) >= item.purchaseLimit
    }

    static func balance(_ currency: Currency, profile: Profile) -> Int {
        currency == .astralGem ? profile.totalGem : profile.starlightCoin
    }

    static func canAfford(_ item: StoreItemDef, profile: Profile) -> Bool {
        balance(item.currency, profile: profile) >= EconomyService.price(of: item)
    }

    /// Gem 消費の内訳（無償 → 有償の順）。
    static func gemSplit(cost: Int, profile: Profile) -> (free: Int, paid: Int) {
        let free = min(profile.freeGem, cost)
        return (free, max(0, min(profile.paidGem, cost - free)))
    }

    /// 商品のレアリティ（ヒーロー解放は nil、バンドルは中身の最高、中身不明なら Epic）。
    static func rarity(of item: StoreItemDef, master: MasterData) -> Rarity? {
        switch item.type {
        case .cosmetic:
            return master.cosmetic(item.grantID)?.rarity
        case .heroUnlock:
            return nil
        case .bundle:
            let contents = EconomyService.bundleContents(item.grantID, master: master).compactMap { master.cosmetic($0) }
            let rank = { (r: Rarity) in Rarity.allCases.firstIndex(of: r) ?? 0 }
            return contents.map(\.rarity).max { rank($0) < rank($1) } ?? .epic
        }
    }

    /// 商品の種類表示。
    static func typeLabel(_ item: StoreItemDef, master: MasterData) -> String {
        switch item.type {
        case .cosmetic:
            return master.cosmetic(item.grantID).map { CollectionStyle.cosmeticTypeName($0.type) } ?? L("コスメ", "Cosmetic")
        case .heroUnlock:
            return L("ヒーロー解放", "Hero Unlock")
        case .bundle:
            return L("バンドル", "Bundle")
        }
    }

    /// 重複時の扱い。マスターの duplicate_policy は「購入不可または同価値通貨へ変換（商品設定で固定）」という
    /// 両論併記のため、購入者に誤解を与えないよう商品種別ごとに確定した扱いを表示する（EconomyService の購入処理と一致）。
    static func duplicateRule(_ item: StoreItemDef) -> String {
        switch item.type {
        case .cosmetic, .heroUnlock:
            return L("所持済みの場合は購入できません。", "Can't be purchased if you already own it.")
        case .bundle:
            return L("所持済みのコスメは付与されず、代わりに無償 AstralGem が付与されます。中身をすべて所持している場合は購入できません。",
                     "Cosmetics you already own aren't granted again; you receive free AstralGem instead. Can't be purchased if you own everything inside.")
        }
    }

    /// バンドルの中身のうち所持済みのもの（購入しても付与されない分）。
    static func ownedBundleContents(_ item: StoreItemDef, profile: Profile, master: MasterData) -> [String] {
        guard item.type == .bundle else { return [] }
        return EconomyService.bundleContents(item.grantID, master: master).filter { profile.ownedCosmeticIDs.contains($0) }
    }

    /// 商品毎の購入条件（重複時の扱い・返金・上限）。返金の文言はマスターが日本語のみのため英語は定型訳を使う。
    static func policyRows(_ item: StoreItemDef) -> [StoreLegalText.Row] {
        let refund = Loc.isEnglish
            ? "Unspent purchases are handled within the platform's rules."
            : item.refundPolicy
        var rows: [StoreLegalText.Row] = [.init(label: L("重複時の扱い", "Duplicates"), value: duplicateRule(item))]
        if !item.refundPolicy.isEmpty { rows.append(.init(label: L("返金", "Refunds"), value: refund)) }
        if item.purchaseLimit > 0 {
            rows.append(.init(label: L("購入上限", "Purchase limit"),
                              value: L("\(item.purchaseLimit) 回まで", "Up to \(item.purchaseLimit)")))
        }
        return rows
    }

    static func typeSymbol(_ item: StoreItemDef, master: MasterData) -> String {
        switch item.type {
        case .cosmetic:
            return master.cosmetic(item.grantID).map { CollectionStyle.cosmeticTypeSymbol($0.type) } ?? "sparkles"
        case .heroUnlock:
            return "person.fill.badge.plus"
        case .bundle:
            return "gift.fill"
        }
    }
}

// MARK: - コスメ

enum CosmeticInfo {
    /// CO001〜CO024 = 0、CO025〜 = 1 … のバリエーション番号（見た目の違いに使う）。
    static func variant(of c: CosmeticDef) -> Int {
        let n = Int(c.cosmeticID.dropFirst(2)) ?? 1
        return max(0, (n - 1) / 24)
    }

    /// 同じ種類の中での通し番号（0 起点・ID 昇順）。
    static func ordinal(of c: CosmeticDef, master: MasterData) -> Int {
        master.cosmetics.filter { $0.type == c.type }.firstIndex { $0.cosmeticID == c.cosmeticID } ?? 0
    }

    static let emoteSymbols = [
        "hand.wave.fill", "hand.thumbsup.fill", "face.smiling.fill", "star.fill",
        "heart.fill", "flame.fill", "bolt.fill", "crown.fill",
        "sparkles", "trophy.fill", "hands.clap.fill", "party.popper.fill",
    ]

    static func emoteSymbol(_ c: CosmeticDef, master: MasterData) -> String {
        emoteSymbols[ordinal(of: c, master: master) % emoteSymbols.count]
    }

    /// 所持コスメ（種類指定、ID 昇順）。
    static func owned(_ type: CosmeticType, profile: Profile, master: MasterData) -> [CosmeticDef] {
        master.cosmetics.filter { $0.type == type && profile.ownedCosmeticIDs.contains($0.cosmeticID) }
    }

    static func skins(heroID: String, master: MasterData) -> [CosmeticDef] {
        master.cosmetics.filter { $0.type == .heroSkin && $0.heroID == heroID }
    }

    static func isEquipped(_ c: CosmeticDef, profile: Profile) -> Bool {
        switch c.type {
        case .heroSkin: return profile.equippedSkins[c.heroID] == c.cosmeticID
        case .recall: return profile.equippedRecall == c.cosmeticID
        case .spawn: return profile.equippedSpawn == c.cosmeticID
        case .killEffect: return profile.equippedKillEffect == c.cosmeticID
        case .avatarFrame: return profile.equippedAvatarFrame == c.cosmeticID
        case .emote: return profile.equippedEmotes.contains(c.cosmeticID)
        }
    }

    /// 装備する。エモートは空き枠へ（空きが無ければ false）。
    @discardableResult
    static func equip(_ c: CosmeticDef, profile: inout Profile) -> Bool {
        guard profile.ownedCosmeticIDs.contains(c.cosmeticID) else { return false }
        switch c.type {
        case .heroSkin: profile.equippedSkins[c.heroID] = c.cosmeticID
        case .recall: profile.equippedRecall = c.cosmeticID
        case .spawn: profile.equippedSpawn = c.cosmeticID
        case .killEffect: profile.equippedKillEffect = c.cosmeticID
        case .avatarFrame: profile.equippedAvatarFrame = c.cosmeticID
        case .emote:
            let slots = EmoteSlots.normalized(profile.equippedEmotes)
            if slots.contains(c.cosmeticID) { return true }
            guard let empty = EmoteSlots.firstEmptySlot(in: slots) else { return false }
            profile.equippedEmotes = EmoteSlots.assigning(c.cosmeticID, slot: empty, in: slots)
        }
        return true
    }

    /// 既定（未装備）に戻す。スキンは heroID を指定。
    static func unequip(_ type: CosmeticType, heroID: String? = nil, profile: inout Profile) {
        switch type {
        case .heroSkin:
            if let heroID { profile.equippedSkins[heroID] = nil }
        case .recall: profile.equippedRecall = nil
        case .spawn: profile.equippedSpawn = nil
        case .killEffect: profile.equippedKillEffect = nil
        case .avatarFrame: profile.equippedAvatarFrame = nil
        case .emote: profile.equippedEmotes = []
        }
    }

    static func equippedID(_ type: CosmeticType, heroID: String? = nil, profile: Profile) -> String? {
        switch type {
        case .heroSkin: return heroID.flatMap { profile.equippedSkins[$0] }
        case .recall: return profile.equippedRecall
        case .spawn: return profile.equippedSpawn
        case .killEffect: return profile.equippedKillEffect
        case .avatarFrame: return profile.equippedAvatarFrame
        case .emote: return nil
        }
    }
}

// MARK: - 課金結果・年齢別上限

enum IAPResultText {
    /// 年齢区分の月間上限の説明（上限なしは nil）。
    static func monthlyLimitDescription(_ bracket: AgeBracket?) -> String? {
        guard let bracket, let limit = bracket.monthlySpendLimitJPY else { return nil }
        let yen = "¥\(limit.formatted())"
        switch bracket {
        case .under13, .age13to15:
            return L("15 歳以下の方の月間購入上限は \(yen) です。", "Players aged 15 or under can spend up to \(yen) per month.")
        case .age16to19:
            return L("16〜19 歳の方の月間購入上限は \(yen) です。", "Players aged 16–19 can spend up to \(yen) per month.")
        case .adult:
            return nil
        }
    }

    /// 購入結果のメッセージ（キャンセルは nil = 何も表示しない）。
    static func message(for result: IAPResult, bracket: AgeBracket?, remaining: Int?) -> (title: String, body: String, isError: Bool)? {
        switch result {
        case .success(let gems):
            return (L("購入完了", "Purchase Complete"),
                    L("AstralGem ×\(gems.formatted()) を受け取りました。", "You received \(gems.formatted()) AstralGem."), false)
        case .pending:
            return (L("承認待ち", "Pending Approval"),
                    L("購入は承認待ちです（保護者の承認など）。承認されると自動で付与されます。",
                      "Your purchase is pending (e.g. Ask to Buy). Gems will be delivered automatically once approved."), false)
        case .cancelled:
            return nil
        case .limitExceeded:
            var body = monthlyLimitDescription(bracket) ?? L("月間購入上限に達しています。", "You have reached your monthly spending limit.")
            if let remaining {
                body += L(" 今月の残り購入可能額は ¥\(remaining.formatted()) です。",
                          " Remaining this month: ¥\(remaining.formatted()).")
            }
            return (L("購入上限", "Spending Limit"), body, true)
        case .failed(let reason):
            return (L("購入できませんでした", "Purchase Failed"),
                    L("時間をおいて再度お試しください。", "Please try again later.") + (reason.isEmpty ? "" : "\n(\(reason))"), true)
        }
    }

    /// 参考価格が今月の残り額を超えるか。
    static func exceedsLimit(priceJPY: Int, remaining: Int?) -> Bool {
        guard let remaining else { return false }
        return priceJPY > remaining
    }
}

// MARK: - 法定表示（資金決済法・特定商取引法）

enum StoreLegalText {
    struct Row: Identifiable, Equatable {
        var id: String { label }
        let label: String
        let value: String
    }

    // 事業者情報は docs/legal（payment_services_act_ja.md・tokushoho_ja.md）と同じプレースホルダで持ち、
    // App Store 公開前にリポジトリ全体の {{…}} を確定値へ置き換える。表示内容も docs/legal と一致させる。
    static let issuerName = "{{PUBLISHER_NAME}}"
    static let issuerAddress = "{{POSTAL_ADDRESS}}"
    static let responsiblePerson = "{{REPRESENTATIVE_NAME}}"
    static let phoneNumber = "{{PHONE_NUMBER}}"

    /// 年齢区分別の月間購入上限の説明（AgeBracket の値から生成し、DESIGN §12 と一致させる）。
    static var monthlyLimitSummary: String {
        let young = AgeBracket.age13to15.monthlySpendLimitJPY ?? 0
        let teen = AgeBracket.age16to19.monthlySpendLimitJPY ?? 0
        return L("年齢区分に応じた月間購入上限があります（15 歳以下 \(young.formatted()) 円、16〜19 歳 \(teen.formatted()) 円）。スターパス プレミアムはシーズンごとに 1 回のみ購入できます。",
                 "Monthly spending limits apply by age (15 and under: ¥\(young.formatted()), 16–19: ¥\(teen.formatted())). Star Pass Premium can be bought once per season.")
    }

    static var paymentServicesAct: [Row] {
        [
            Row(label: L("前払式支払手段の名称", "Name of prepaid payment instrument"), value: L("AstralGem（有償）", "AstralGem (paid)")),
            Row(label: L("発行者の名称", "Issuer"), value: issuerName),
            Row(label: L("支払可能金額等", "Amount available"),
                value: L("購入した商品に表示された AstralGem の数量（ボーナス分を含みます。例: 800 円の商品で有償 AstralGem 330 個）。ゲーム内の報酬として無償で付与される AstralGem（無償分）は前払式支払手段に該当しません。",
                         "The number of AstralGem shown on the purchased pack, bonus included (e.g. 330 paid gems for the ¥800 pack). Free AstralGem granted as in-game rewards is not a prepaid payment instrument.")),
            Row(label: L("有効期間", "Validity"), value: L("有効期限はありません。", "No expiration date.")),
            Row(label: L("使用できる場所", "Where it can be used"),
                value: L("本アプリ内のストア（コスメ・バンドル等との交換）。戦闘能力に影響する商品は販売していません。",
                         "The in-app store (exchange for cosmetics, bundles, etc.). No items affecting combat power are sold.")),
            Row(label: L("苦情・相談窓口", "Complaints & inquiries"),
                value: L("\(issuerName) サポート窓口\n所在地: \(issuerAddress)\n電話: \(phoneNumber)\nメール: \(FeatureFlags.supportEmail)",
                         "\(issuerName) Support\nAddress: \(issuerAddress)\nPhone: \(phoneNumber)\nEmail: \(FeatureFlags.supportEmail)")),
            Row(label: L("残高の確認方法", "Checking your balance"),
                value: L("ストア・AstralGem 購入画面・インベントリで、有償分と無償分を区別して確認できます。",
                         "Paid and free balances are shown separately in the Store, Buy AstralGem and Inventory screens.")),
            Row(label: L("利用上の注意", "Notes"),
                value: L("・無償 AstralGem から先に消費されます。\n・残高は端末内に保存されます。端末の紛失・初期化やアプリの削除で失われた残高は復元できません。\n・他の利用者への譲渡・貸与、現金その他の財産との交換はできません。",
                         "• Free AstralGem is always spent first.\n• Balances are stored on this device. Balances lost by losing or resetting the device or deleting the app can't be restored.\n• Gems can't be transferred or lent to other players or exchanged for cash or other property.")),
            Row(label: L("利用規約", "Terms of Use"), value: FeatureFlags.termsURL.absoluteString),
            Row(label: L("払い戻し", "Refunds"),
                value: L("法令に定める場合を除き、払い戻しはできません。本アプリの提供終了など法令に定める事由が生じた場合は、資金決済法第 20 条に基づき未使用の有償 AstralGem を払い戻します。",
                         "No refunds except as required by law. If the service ends or another statutory event occurs, unused paid AstralGem will be refunded under Article 20 of the Payment Services Act.")),
        ]
    }

    static var commercialTransactions: [Row] {
        [
            Row(label: L("販売事業者", "Seller"), value: issuerName),
            Row(label: L("運営統括責任者", "Responsible person"), value: responsiblePerson),
            Row(label: L("所在地", "Address"), value: issuerAddress),
            Row(label: L("電話番号", "Phone"),
                value: L("\(phoneNumber)（お問い合わせはできるだけメールでお願いします）", "\(phoneNumber) (please contact us by email where possible)")),
            Row(label: L("メールアドレス", "Email"), value: FeatureFlags.supportEmail),
            Row(label: L("販売価格", "Price"), value: L("各商品の購入画面に表示された価格（税込）。", "The price shown on each product (tax included).")),
            Row(label: L("商品代金以外の必要料金", "Additional fees"),
                value: L("アプリのダウンロード・更新に必要な通信料はお客様のご負担となります。",
                         "Data charges for downloading and updating the app are borne by the customer.")),
            Row(label: L("支払方法", "Payment method"),
                value: L("App Store が提供する決済方法（Apple Account に登録された支払方法）。",
                         "Payment methods provided by the App Store (registered to your Apple Account).")),
            Row(label: L("支払時期", "Payment timing"), value: L("App Store の定める時期。", "As determined by the App Store.")),
            Row(label: L("商品の引渡時期", "Delivery"),
                value: L("購入手続き完了後、直ちにアプリ内で付与します。", "Delivered in the app immediately after the purchase completes.")),
            Row(label: L("返品・キャンセル", "Returns & cancellation"),
                value: L("デジタルコンテンツの性質上、購入後の返品・キャンセルはできません。返金は Apple の定める手続き（https://reportaproblem.apple.com）により Apple が判断します。",
                         "Due to the nature of digital content, purchases can't be returned or cancelled. Refunds are decided by Apple through its procedure (https://reportaproblem.apple.com).")),
            Row(label: L("販売数量の制限", "Purchase limits"), value: monthlyLimitSummary),
            Row(label: L("動作環境", "Requirements"),
                value: L("iOS 18.0 以降を搭載した iPhone。", "iPhone with iOS 18.0 or later.")),
            Row(label: L("特記事項", "Note"),
                value: L("有償アイテムはゲーム内の外見等を変更するもので、試合の勝敗に影響する能力は販売していません。",
                         "Paid items change in-game appearance only; nothing that affects match outcomes is sold.")),
        ]
    }
}
