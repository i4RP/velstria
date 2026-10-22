import Foundation

// 担当: core-data
// エンブレムの解放・レベル・天賦の解放・入手（MLBB のエンブレムを写したもの。docs/EMBLEMS.md「解放・レベル・入手」）。
// 数値はすべて仮（MLBB の画面で確かめた点・第三者の攻略の合計に合わせた、調整用の表）。ここが唯一の定義:
// ・強化の費用（EmblemProgression.upgradeCosts。Lv1→60 の合計 22,773・10 レベルごとの合計は攻略の値と同じ）
// ・能力値のレベル別の値（EmblemProgression.levelValues。画面で確かめた点を通り、Lv60 で最大）
// ・天賦の段の解放レベル（1 段目 Lv10・2 段目 Lv15・コア Lv20）
// ・解放の費用・入手（無料の宝箱・ミッション・試合・スターパス・初回）の量（EmblemEconomy）
// 有料のガチャ・確率で決まる入手は作らない（確率表示などの法令の要件があるため）。入手はすべて決まった量。

/// エンブレムのレベル・天賦の解放（仮の表）。
public enum EmblemProgression {
    /// 新しく解放したセットのレベル。
    public static let startLevel = 1

    /// キーレベル（コア属性が大きく伸びるレベル。画面で Lv30・Lv45 を確かめた。15 ごと）。
    public static let keyLevels = [15, 30, 45, 60]

    public static func isKeyLevel(_ level: Int) -> Bool { keyLevels.contains(level) }

    /// level より上で最初のキーレベル（最大なら nil）。画面の「Lv30 コア属性大幅アップ」。
    public static func nextKeyLevel(after level: Int) -> Int? { keyLevels.first { $0 > level } }

    // MARK: - 強化の費用

    /// Lv(n) → Lv(n+1) の費用（添字 0 = Lv1→2。59 個）。セットの欠片を先に使い、足りない分をマジックダストで払う（1:1）。
    /// 第三者の攻略の 10 レベルごとの合計（Lv1→10: 483 / 11→20: 1,210 / 21→30: 2,540 / 31→40: 3,880 / 41→50: 5,510 /
    /// 51→60: 9,150、合計 22,773）にちょうど合わせ、範囲の中は滑らかに増やし、キーレベルに上がる 1 回だけ 1.45 倍
    /// （サポートの 29→30 = 488 と タンクの 28→29 = 337 の比）にした。画面で確かめた 26→27 = 227・28→29 = 337・
    /// 29→30 = 488 は表のとおり。42→43 = 365（通常共通）は範囲の合計と合わない（表は 479。docs/EMBLEMS.md）。
    public static let upgradeCosts: [Int] = [
        // Lv1→2 … 9→10（合計 483）
        30, 36, 42, 48, 54, 60, 66, 71, 76,
        // Lv10→11 … 19→20（合計 1,210。14→15 がキーレベル）
        80, 88, 96, 104, 162, 120, 128, 136, 144, 152,
        // Lv20→21 … 29→30（合計 2,540。29→30 がキーレベル）
        190, 195, 199, 203, 207, 214, 227, 280, 337, 488,
        // Lv30→31 … 39→40（合計 3,880）
        345, 355, 364, 374, 383, 393, 402, 412, 421, 431,
        // Lv40→41 … 49→50（合計 5,510。44→45 がキーレベル）
        440, 459, 479, 498, 751, 537, 557, 576, 597, 616,
        // Lv50→51 … 59→60（合計 9,150。59→60 がキーレベル）
        640, 690, 740, 791, 841, 891, 941, 991, 1042, 1583,
    ]

    /// 攻略の 10 レベルごとの合計（到達レベル lo...hi の強化の合計。テスト・ドキュメント用）。
    public static let rangeTotals: [(lo: Int, hi: Int, total: Int)] = [
        (2, 10, 483), (11, 20, 1210), (21, 30, 2540), (31, 40, 3880), (41, 50, 5510), (51, 60, 9150),
    ]

    /// Lv1 から Lv60 までの費用の合計。
    public static var totalCost: Int { upgradeCosts.reduce(0, +) }

    /// level → level+1 の費用（最大レベル・範囲外は nil）。
    public static func upgradeCost(from level: Int) -> Int? {
        guard level >= 1, level < EmblemCatalog.maxLevel, level - 1 < upgradeCosts.count else { return nil }
        return upgradeCosts[level - 1]
    }

    /// Lv1 から level までの費用の合計。
    public static func cumulativeCost(to level: Int) -> Int {
        upgradeCosts.prefix(max(0, min(upgradeCosts.count, level - 1))).reduce(0, +)
    }

    // MARK: - 天賦の解放

    /// 天賦の段を付けられる（試合で働く）ようになるセットのレベル（仮。MLBB の画面は「期間限定で全天賦解放」中で確かめられない）。
    public static let talentUnlockLevels: [EmblemTier: Int] = [.tier1: 10, .tier2: 15, .core: 20]

    /// MLBB の「期間限定で全天賦解放」（true の間はレベルに関係なく全段を付けられる）。
    public static let allTalentsUnlocked = false

    /// 段 tier の解放レベル。
    public static func unlockLevel(_ tier: EmblemTier) -> Int {
        allTalentsUnlocked ? 1 : (talentUnlockLevels[tier] ?? 1)
    }

    /// 天賦の解放レベル（天賦ごとの値があればそれ、無ければ段の解放レベル）。
    public static func unlockLevel(talent id: EmblemTalentID) -> Int {
        if allTalentsUnlocked { return 1 }
        return EmblemCatalog.talent(id).unlockLevel ?? unlockLevel(id.tier)
    }

    /// セットのレベル level で段 tier を使えるか。
    public static func isTierUnlocked(_ tier: EmblemTier, level: Int) -> Bool { level >= unlockLevel(tier) }

    // MARK: - 能力値のレベル別の値

    /// コア属性（ステータス欄の 1 つ目）の帯ごとの割合（Lv1〜14 / 15〜29 / 30〜44 / 45〜59 / 60。Lv60 の値に掛ける）。
    /// コア属性はキーレベルでだけ伸びる（フレンドの画面: 26→27・28→29・42→43 の予告にコア属性は出ない。Lv29→30 で
    /// サポートの回復効果が 3.33% → 4.75%）。確かめた帯（下の observed）はその値、ほかはこの割合（仮）。
    public static let coreBandFractions: [Double] = [0.15, 0.275, 0.385, 0.62, 1.0]

    /// コア以外の 2 つの Lv1 の値（Lv60 の値に掛ける。仮: 1 回に伸びる量 ≒ 最大の 1/30 から逆算。アサシンの移動速度は
    /// Lv1 0.10% から 1 回 0.10% ずつで Lv26 の 1.20% に届く）。
    public static let startFraction = 1.0 / 30

    /// 画面で確かめた値（セット → 能力値の並び順 → レベル → 値）。表は必ずこの点を通る。
    /// アサシン Lv26（Lv27 は移動速度だけ）・タンク Lv28（Lv29 は HP回復だけ）・サポート Lv29（Lv30 は回復効果だけ）・
    /// 通常共通 Lv42（Lv43 は適応攻撃だけ）。docs/EMBLEMS.md「確かめた値」。
    public static let observed: [EmblemSetID: [[Int: Double]]] = [
        .common: [[42: 4.40], [42: 193], [42: 14.70, 43: 15.40]],
        .tank: [[28: 140], [28: 4.40], [28: 1.74, 29: 1.86]],
        .assassin: [[26: 3.80], [26: 4.30], [26: 1.20, 27: 1.30]],
        .support: [[29: 3.33, 30: 4.75], [29: 4.72], [29: 2.82]],
    ]

    /// コア以外の能力値が伸びるレベル（そのレベルに上がった時）。1 レベルで伸びるのは 1 つだけ（予告の画面）:
    /// 2 つ目（添字 1）は偶数レベル、3 つ目（添字 2）は奇数レベルで伸び、キーレベルではコア属性だけが伸びる。
    /// 確かめた予告（アサシン 27・タンク 29・通常共通 43 で 3 つ目が伸びる）と合う。2 つ目は Lv58、3 つ目は Lv59 で最大。
    public static func growthLevels(attributeIndex index: Int) -> [Int] {
        guard index > 0 else { return keyLevels }
        let parity = index == 1 ? 0 : 1
        return (2..<EmblemCatalog.maxLevel).filter { $0 % 2 == parity && !isKeyLevel($0) }
    }

    /// 能力値 1 つのレベル別の値（添字 0 = Lv1、60 個。小数 2 桁に丸める。画面の表示と同じ桁）。
    /// - コア属性: 帯ごとに一定（coreBandFractions。確かめた帯はその値）、Lv60 で最大。
    /// - ほか: 伸びるレベル（growthLevels）でだけ伸び、Lv1 の値 → 確かめた点 → 最大を、伸びた回数で直線に結ぶ。
    public static func levelValues(set: EmblemSetID, attributeIndex index: Int, maxValue: Double) -> [Double] {
        let pins = (observed[set].flatMap { index < $0.count ? $0[index] : nil }) ?? [:]
        let maxLv = EmblemCatalog.maxLevel
        if index == 0 {
            // 帯: 0 = Lv1〜14、1 = 15〜29、2 = 30〜44、3 = 45〜59、4 = 60
            func bandIndex(_ lv: Int) -> Int { keyLevels.filter { $0 <= lv }.count }
            var band = coreBandFractions.map { round2(maxValue * $0) }
            for (lv, v) in pins { band[bandIndex(lv)] = v }
            band[band.count - 1] = maxValue
            return (1...maxLv).map { lv in band[bandIndex(lv)] }
        }
        let steps = growthLevels(attributeIndex: index)
        func count(_ lv: Int) -> Int { steps.filter { $0 <= lv }.count }
        // 伸びた回数 → 値 の点（Lv1 = 0 回、確かめた点、最後 = 最大）
        var points: [(n: Double, v: Double)] = [(0, round2(maxValue * startFraction))]
        for (lv, v) in pins.sorted(by: { $0.key < $1.key }) { points.append((Double(count(lv)), v)) }
        points.append((Double(steps.count), maxValue))
        return (1...maxLv).map { lv in
            let n = Double(count(lv))
            if let exact = points.last(where: { $0.n == n }) { return exact.v }
            guard let hi = points.firstIndex(where: { $0.n > n }), hi > 0 else { return maxValue }
            let a = points[hi - 1], b = points[hi]
            return round2(a.v + (b.v - a.v) * (n - a.n) / (b.n - a.n))
        }
    }

    /// セットの能力値にレベル別の表を付ける（EmblemCatalog.sets の作成時）。
    static func attachingLevelTables(_ def: EmblemSetDef) -> EmblemSetDef {
        var d = def
        for k in d.attributes.indices {
            d.attributes[k].levelValues = levelValues(set: d.id, attributeIndex: k, maxValue: d.attributes[k].maxValue)
        }
        return d
    }

    static func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }
}

/// 強化 1 回の支払い（欠片を先に、足りない分をマジックダストで）。画面の「10+217/227」。
public struct EmblemUpgradeQuote: Equatable, Sendable {
    /// 必要な量。
    public var needed: Int
    /// 使う欠片（持っている分まで）。
    public var fromFragments: Int
    /// 使うマジックダスト（足りない分を、持っている分まで）。
    public var fromDust: Int

    public init(needed: Int, fromFragments: Int, fromDust: Int) {
        self.needed = needed
        self.fromFragments = fromFragments
        self.fromDust = fromDust
    }

    /// 払えるか。
    public var affordable: Bool { fromFragments + fromDust >= needed }

    /// 欠片 fragments・マジックダスト dust を持っている時の、費用 cost の払い方。
    public static func make(cost: Int, fragments: Int, dust: Int) -> EmblemUpgradeQuote {
        let need = max(0, cost)
        let f = min(max(0, fragments), need)
        let d = min(max(0, dust), need - f)
        return EmblemUpgradeQuote(needed: need, fromFragments: f, fromDust: d)
    }
}

/// 無料のエンブレム宝箱（4 時間ごとに 1 回分たまり、2 回分まで貯められる）の状態。時刻を渡すと決まった結果になる。
public struct EmblemChestState: Codable, Equatable, Sendable {
    /// 貯まっている回数（0...EmblemEconomy.chestMaxCharges）。
    public var charges: Int
    /// 次の 1 回を数え始めた時刻（nil = まだ数えていない。満タンの間は数えない）。
    public var anchor: Date?
    /// これまでに開けた回数（欠片のセットの巡回に使う）。
    public var opened: Int

    /// 新しいプレイヤーは 1 回分を持って始める。
    public init(charges: Int = 1, anchor: Date? = nil, opened: Int = 0) {
        self.charges = charges
        self.anchor = anchor
        self.opened = opened
    }

    private enum CodingKeys: String, CodingKey { case charges, anchor, opened }

    /// 欠けたキー・範囲外の値を直して読む。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let n = (try? c.decodeIfPresent(Int.self, forKey: .charges)) ?? nil
        charges = min(EmblemEconomy.chestMaxCharges, max(0, n ?? 1))
        anchor = (try? c.decodeIfPresent(Date.self, forKey: .anchor)) ?? nil
        opened = max(0, ((try? c.decodeIfPresent(Int.self, forKey: .opened)) ?? nil) ?? 0)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(charges, forKey: .charges)
        try c.encodeIfPresent(anchor, forKey: .anchor)
        try c.encode(opened, forKey: .opened)
    }

    /// now までに貯まった分を足した状態。満タンになったら数えるのを止める（開けた時から数え直す）。
    /// 端末の時計が anchor より前に戻っていたら、増やさずに now から数え直す。
    public func refreshed(now: Date) -> EmblemChestState {
        var s = self
        let cap = EmblemEconomy.chestMaxCharges
        let interval = EmblemEconomy.chestInterval
        s.charges = min(cap, max(0, s.charges))
        guard s.charges < cap else {
            s.anchor = nil
            return s
        }
        guard let start = s.anchor, now >= start else {
            s.anchor = now
            return s
        }
        let gained = Int(now.timeIntervalSince(start) / interval)
        guard gained > 0 else { return s }
        s.charges = min(cap, s.charges + gained)
        s.anchor = s.charges >= cap ? nil : start.addingTimeInterval(Double(gained) * interval)
        return s
    }

    /// 次の 1 回が貯まる時刻（満タンなら nil）。
    public func nextChargeAt(now: Date) -> Date? {
        let s = refreshed(now: now)
        guard s.charges < EmblemEconomy.chestMaxCharges, let a = s.anchor else { return nil }
        return a.addingTimeInterval(EmblemEconomy.chestInterval)
    }

    /// 1 回開ける（貯まっていなければ nil）。中身は開けた回数で決まる（EmblemEconomy.chestReward）。
    public mutating func open(now: Date) -> EmblemChestReward? {
        var s = refreshed(now: now)
        guard s.charges > 0 else {
            self = s
            return nil
        }
        let wasFull = s.charges >= EmblemEconomy.chestMaxCharges
        s.charges -= 1
        if wasFull { s.anchor = now }
        let reward = EmblemEconomy.chestReward(opened: s.opened)
        s.opened += 1
        self = s
        return reward
    }
}

/// 宝箱 1 回の中身。
public struct EmblemChestReward: Equatable, Sendable {
    public var dust: Int
    public var fragmentSet: EmblemSetID
    public var fragments: Int
}

/// 解放の費用と入手の量（仮。docs/EMBLEMS.md「入手と 1 週間の見込み」）。どれも決まった量で、確率で決まるものは無い。
/// 目安: 普通に遊ぶ（1 日 4 試合・勝率 5 割・宝箱 1 日 3 回・デイリー / ウィークリーをすべて）と、1 つのセットを
/// Lv1 → 60 にするのに 3〜5 か月（weeklyIncome / weeksToMax）。
public enum EmblemEconomy {
    // MARK: 解放

    /// セットの解放に要るマジックダスト（MLBB の費用は不明。仮）。
    public static let unlockCost = 500
    /// 新しいプレイヤーへの最初のマジックダスト（ウェルカムメール。セットを 1 つ解放できる量）。
    public static let starterDust = 500

    // MARK: 無料のエンブレム宝箱

    /// 1 回分が貯まる間隔（4 時間）。
    public static let chestInterval: TimeInterval = 4 * 3600
    /// 貯められる回数。
    public static let chestMaxCharges = 2
    /// 1 回のマジックダスト。
    public static let chestDust = 15
    /// 1 回の欠片（1 つのセット）。
    public static let chestFragments = 10
    /// 欠片のセットの巡回（開けた回数の順。通常共通は欠片を使わない）。
    public static let chestRotation: [EmblemSetID] = [.tank, .assassin, .mage, .fighter, .support, .marksman]

    /// opened 回目（0 始まり）に開けた時の中身。
    public static func chestReward(opened: Int) -> EmblemChestReward {
        let set = chestRotation[((opened % chestRotation.count) + chestRotation.count) % chestRotation.count]
        return EmblemChestReward(dust: chestDust, fragmentSet: set, fragments: chestFragments)
    }

    // MARK: 試合

    /// 通常戦・ランク戦・乱闘の 1 試合のマジックダスト（Coin と同じ時間係数を掛ける）。
    public static let matchDustWin = 15
    public static let matchDustLoss = 8

    /// 1 試合のマジックダスト（時間係数 0.3〜1.0 を掛けて四捨五入）。
    public static func matchDust(won: Bool, durationFactor: Double) -> Int {
        let f = durationFactor.isFinite ? min(1, max(0, durationFactor)) : 0
        return Int((Double(won ? matchDustWin : matchDustLoss) * f).rounded())
    }

    // MARK: ミッション（アプリの LiveOpsService がこの値を使う）

    /// デイリー: 参加（D01〜D04）。
    public static let dailyParticipationDust = 30
    /// デイリー: 戦闘（D05〜D08）。
    public static let dailyCombatDust = 20
    /// デイリー: タワー（D09）。
    public static let dailyObjectiveDust = 20
    /// デイリー: ロールでプレイ（D10〜D12）。そのロールのセットの欠片。
    public static let dailyRoleFragments = 15
    /// ウィークリー: W01（15 試合）・W03（40 キル）・W04（タワー 12 本）のマジックダスト。
    public static let weeklyPlayDust = 120
    public static let weeklyKillsDust = 80
    public static let weeklyTowersDust = 80
    /// ウィークリー: W02（7 勝）の欠片のまとめ（6 つのセットに同じ数ずつ）。
    public static let weeklyFragmentsPerSet = 15

    // MARK: スターパス

    /// 無料トラックでマジックダストを配る段階（Coin の段階の一部と入れ替える）と量。
    public static let passDustLevels = [3, 8, 13, 18, 23, 28]
    public static let passDust = 150

    // MARK: 1 週間の見込み

    /// 1 週間に入る量の見込み（docs/EMBLEMS.md の計算と同じ）。デイリーの 3 枠目は 4 つのうち 1 つが選ばれる（D09 が 1/4、
    /// ロールの 3 つが 1/4 ずつ）。fragments はセットごと（通常共通は 0）。
    public struct WeeklyIncome: Equatable, Sendable {
        public var dust: Double
        public var fragments: [EmblemSetID: Double]

        /// set を上げるのに使える 1 週間の量（マジックダスト + そのセットの欠片）。
        public func usable(for set: EmblemSetID) -> Double { dust + (fragments[set] ?? 0) }
    }

    /// matchesPerDay 試合 / 日（勝率 winRate、時間係数 1）、宝箱 chestOpensPerDay 回 / 日、デイリー・ウィークリーをすべて達成。
    public static func weeklyIncome(matchesPerDay: Double = 4, winRate: Double = 0.5,
                                    chestOpensPerDay: Double = 3) -> WeeklyIncome {
        let days = 7.0
        var dust = 0.0
        var frag: [EmblemSetID: Double] = [:]
        for s in EmblemSetID.allCases where s != .common { frag[s] = 0 }
        // 試合
        dust += days * matchesPerDay * (winRate * Double(matchDustWin) + (1 - winRate) * Double(matchDustLoss))
        // 宝箱（巡回なので 6 つのセットに均等）
        let opens = days * min(chestOpensPerDay, 24 * 3600 / chestInterval)
        dust += opens * Double(chestDust)
        for s in chestRotation { frag[s, default: 0] += opens * Double(chestFragments) / Double(chestRotation.count) }
        // デイリー（グループ 0・1 は毎日、グループ 2 は 4 つから 1 つ）
        dust += days * Double(dailyParticipationDust + dailyCombatDust)
        dust += days * 0.25 * Double(dailyObjectiveDust)
        for s in [EmblemSetID.tank, .marksman, .support] { frag[s, default: 0] += days * 0.25 * Double(dailyRoleFragments) }
        // ウィークリー
        dust += Double(weeklyPlayDust + weeklyKillsDust + weeklyTowersDust)
        for s in chestRotation { frag[s, default: 0] += Double(weeklyFragmentsPerSet) }
        return WeeklyIncome(dust: dust, fragments: frag)
    }

    /// set を Lv1 → 60 にするのに掛かる週（解放の費用は最初のマジックダストで払う前提。スターパスの粉は入れない）。
    public static func weeksToMax(_ set: EmblemSetID, income: WeeklyIncome = weeklyIncome()) -> Double {
        Double(EmblemProgression.totalCost) / max(1, income.usable(for: set))
    }
}
