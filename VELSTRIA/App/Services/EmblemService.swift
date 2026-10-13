import Foundation
import VelstriaCore

// 担当: app-services
// エンブレムの解放・強化・欠片・無料の宝箱（プロフィールの操作）。数値・規則は VelstriaCore の EmblemProgression / EmblemEconomy
// （docs/EMBLEMS.md「解放・レベル・入手」）。
// - 新規: 通常共通エンブレムだけ解放済みの Lv1。ほかの 6 つはマジックダスト（EmblemEconomy.unlockCost）で解放し、Lv1 から。
// - 旧版から引き継いだプレイヤー（Profile.emblemGrandfathered）: 全セット解放済みの Lv60 のまま。
// - 強化: そのセットの欠片を先に使い、足りない分をマジックダストで払う（1:1）。最大（Lv60）では強化できない。
// - 欠片: 通常共通には無い。最大レベルのセットの欠片は、受け取った時・最大になった時にマジックダストに 1:1 で替える。
// - 無料の宝箱: 4 時間ごとに 1 回分、2 回分まで。中身は決まった量のマジックダストと、巡回する 1 つのセットの欠片（確率は無い）。

enum EmblemService {
    // MARK: - 状態

    /// セットの解放とレベル（保存が無ければ既定: 旧版から引き継いだプレイヤーは解放済みの Lv60、新規は通常共通だけ解放済みの Lv1）。
    static func progress(_ set: EmblemSetID, profile: Profile) -> EmblemSetProgress {
        if let p = profile.emblemSetProgress[set.rawValue] {
            return set == .common ? EmblemSetProgress(unlocked: true, level: p.level) : p
        }
        if profile.emblemGrandfathered { return EmblemSetProgress(unlocked: true, level: EmblemCatalog.maxLevel) }
        return EmblemSetProgress(unlocked: set == .common, level: EmblemProgression.startLevel)
    }

    static func isUnlocked(_ set: EmblemSetID, profile: Profile) -> Bool { progress(set, profile: profile).unlocked }

    static func level(_ set: EmblemSetID, profile: Profile) -> Int { progress(set, profile: profile).level }

    static func isMaxLevel(_ set: EmblemSetID, profile: Profile) -> Bool {
        level(set, profile: profile) >= EmblemCatalog.maxLevel
    }

    /// セットの欠片（通常共通は常に 0）。
    static func fragments(_ set: EmblemSetID, profile: Profile) -> Int {
        set == .common ? 0 : max(0, profile.emblemFragments[set.rawValue] ?? 0)
    }

    /// 次のレベルへの強化の払い方（未解放・最大なら nil）。
    static func upgradeQuote(_ set: EmblemSetID, profile: Profile) -> EmblemUpgradeQuote? {
        let p = progress(set, profile: profile)
        guard p.unlocked, let cost = EmblemProgression.upgradeCost(from: p.level) else { return nil }
        return EmblemUpgradeQuote.make(cost: cost, fragments: fragments(set, profile: profile), dust: profile.magicDust)
    }

    static func canUpgrade(_ set: EmblemSetID, profile: Profile) -> Bool {
        upgradeQuote(set, profile: profile)?.affordable ?? false
    }

    static func canUnlock(_ set: EmblemSetID, profile: Profile) -> Bool {
        !isUnlocked(set, profile: profile) && profile.magicDust >= EmblemEconomy.unlockCost
    }

    /// タブの緑の上向きの矢印（強化か解放ができる）。
    static func canImprove(_ set: EmblemSetID, profile: Profile) -> Bool {
        canUpgrade(set, profile: profile) || canUnlock(set, profile: profile)
    }

    /// 段 tier の天賦をこのセットのレベルで使えるか。
    static func isTierUnlocked(_ tier: EmblemTier, set: EmblemSetID, profile: Profile) -> Bool {
        EmblemProgression.isTierUnlocked(tier, level: level(set, profile: profile))
    }

    // MARK: - 操作

    /// マジックダストでセットを解放する（Lv1 から）。払えない・解放済みなら false。
    @discardableResult
    static func unlock(_ set: EmblemSetID, profile: inout Profile) -> Bool {
        guard canUnlock(set, profile: profile) else { return false }
        profile.magicDust -= EmblemEconomy.unlockCost
        profile.emblemSetProgress[set.rawValue] = EmblemSetProgress(unlocked: true, level: EmblemProgression.startLevel)
        return true
    }

    /// 1 レベル上げる（欠片を先に、足りない分をマジックダストで）。払えない・未解放・最大なら false。
    /// 最大になったら、残りの欠片をマジックダストに替える。
    @discardableResult
    static func upgrade(_ set: EmblemSetID, profile: inout Profile) -> Bool {
        guard let q = upgradeQuote(set, profile: profile), q.affordable else { return false }
        if q.fromFragments > 0 { setFragments(fragments(set, profile: profile) - q.fromFragments, set: set, profile: &profile) }
        profile.magicDust -= q.fromDust
        let next = EmblemCatalog.clampLevel(level(set, profile: profile) + 1)
        profile.emblemSetProgress[set.rawValue] = EmblemSetProgress(unlocked: true, level: next)
        if next >= EmblemCatalog.maxLevel { convertFragmentsToDust(set, profile: &profile) }
        return true
    }

    /// 欠片を足す。通常共通・最大レベルのセットの分はマジックダストに替え、替えた量を返す。
    @discardableResult
    static func addFragments(_ amount: Int, set: EmblemSetID, profile: inout Profile) -> Int {
        let n = max(0, amount)
        guard n > 0 else { return 0 }
        if set == .common || isMaxLevel(set, profile: profile) {
            profile.magicDust += n
            return n
        }
        setFragments(fragments(set, profile: profile) + n, set: set, profile: &profile)
        return 0
    }

    static func addDust(_ amount: Int, profile: inout Profile) {
        profile.magicDust += max(0, amount)
    }

    /// 最大レベルのセットの欠片をマジックダストに替える（1:1）。替えた量を返す。
    @discardableResult
    static func convertFragmentsToDust(_ set: EmblemSetID, profile: inout Profile) -> Int {
        let n = fragments(set, profile: profile)
        profile.emblemFragments[set.rawValue] = nil
        profile.magicDust += n
        return n
    }

    private static func setFragments(_ n: Int, set: EmblemSetID, profile: inout Profile) {
        profile.emblemFragments[set.rawValue] = n > 0 ? n : nil
    }

    /// 全セットを解放済みの Lv60 にする（旧版から引き継いだプレイヤーと同じ。デバッグの -grant・テスト用）。
    static func grandfather(_ profile: inout Profile) {
        profile.emblemGrandfathered = true
        for set in EmblemSetID.allCases {
            profile.emblemSetProgress[set.rawValue] = EmblemSetProgress(unlocked: true, level: EmblemCatalog.maxLevel)
            convertFragmentsToDust(set, profile: &profile)
        }
    }

    // MARK: - 無料のエンブレム宝箱

    /// now の宝箱（貯まった分を足した状態。保存はしない）。
    static func chest(_ profile: Profile, now: Date) -> EmblemChestState {
        profile.emblemChest.refreshed(now: now)
    }

    /// 開けられる回数。
    static func chestCharges(_ profile: Profile, now: Date) -> Int { chest(profile, now: now).charges }

    /// 次の 1 回が貯まるまでの秒（満タンなら nil）。
    static func chestSecondsUntilNext(_ profile: Profile, now: Date) -> TimeInterval? {
        profile.emblemChest.nextChargeAt(now: now).map { max(0, $0.timeIntervalSince(now)) }
    }

    /// 貯まった分を保存に反映する（起動時・エンブレム画面を開いた時。数え始めの時刻を残すため）。
    static func refreshChest(profile: inout Profile, now: Date) {
        profile.emblemChest = profile.emblemChest.refreshed(now: now)
    }

    /// 宝箱を 1 回開けて中身を受け取る（貯まっていなければ nil）。返すのは実際に付与した内容（最大のセットの欠片はマジックダスト）。
    static func openChest(profile: inout Profile, now: Date) -> [MailAttachment]? {
        var c = profile.emblemChest
        guard let r = c.open(now: now) else {
            profile.emblemChest = c
            return nil
        }
        profile.emblemChest = c
        return [dustAttachment(r.dust), fragmentAttachment(r.fragments, set: r.fragmentSet)]
            .map { LiveOpsService.grantResolved($0, to: &profile) }
    }

    /// "3:59:59" / "59:59"（宝箱のボタンの残り時間）。
    static func countdownText(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    // MARK: - 報酬の添付

    static func dustAttachment(_ amount: Int) -> MailAttachment { MailAttachment(kind: .magicDust, amount: amount) }

    static func fragmentAttachment(_ amount: Int, set: EmblemSetID) -> MailAttachment {
        MailAttachment(kind: .emblemFragment, amount: amount, refID: set.rawValue)
    }

    /// 欠片の添付の名前（「タンクの欠片」）。
    static func fragmentName(_ attachment: MailAttachment) -> String {
        guard let raw = attachment.refID, let set = EmblemSetID(rawValue: raw) else {
            return L("エンブレムの欠片", "Emblem Fragments")
        }
        return L("\(EmblemMath.shortSetName(set))の欠片", "\(EmblemMath.shortSetName(set)) Fragments")
    }

    /// 添付を所持に反映する（LiveOpsService.grantResolved から）。最大レベル・通常共通の欠片はマジックダストにして返す。
    static func grant(_ attachment: MailAttachment, to profile: inout Profile) -> MailAttachment {
        let amount = max(0, attachment.amount)
        switch attachment.kind {
        case .emblemFragment:
            guard let raw = attachment.refID, let set = EmblemSetID(rawValue: raw) else { return dustAttachment(0) }
            let converted = addFragments(amount, set: set, profile: &profile)
            return converted > 0 ? dustAttachment(converted) : attachment
        default:
            addDust(amount, profile: &profile)
            return attachment
        }
    }
}
