import Foundation

// 担当: kit-H034（docs/SKILL_KITS.md / docs/NEW_HEROES.md / docs/kits/Franco.md）
// H034 鎖鉤のゴルム = Velstria 版の Franco（MLBB。調査: docs/kits/Franco.md、対応表: 同ファイル末尾）。
// 数値の正は MLBB の日本語クライアントのスキル詳細（docs/kits/Franco.md の「公式（日本語クライアント）の数値」。Fandom・Liquipedia と違うところはこちらが優先）。
//   パッシブ 鉄鎖の執念    — 5 秒ダメージを受けないと 移動速度 +10%・毎秒 最大 HP の 1% 回復、闘気が 1 秒に 1 つたまる（最大 10）。
//                           次に使うスキルが闘気をすべて消費し、1 つにつきそのスキルのダメージ +15%（最大 +150%）。ダメージで解除。
//                           ロール「サポート」の味方回復パッシブ・奥義の味方回復はキットが置き換える。
//   スキル1 鎖鉤           — 射程 680 の非貫通の鉤。最初に当たった敵（ミニオン・モンスター含む、タワーは除く）に
//                           400 → 650（+100% 物理攻撃）、スタンしてから自分の足元まで引き寄せる（スタンは引き寄せの間だけ）。
//                           壁は越えて飛び、引き寄せは壁の手前で止まる。
//   スキル2 鉄鎖旋         — 自身中心の範囲に 300 → 450 + 自分の最大 HP の 4% の物理ダメージ、70% 減速 1.5 秒。
//   アルティメット 狩猟鎖獄 — 敵ヒーロー 1 体を指定。踏み込んで 1.8 秒 suppress（解除不可・CC 無効も無視）し、その間に 6 回
//                           50 / 60 / 70（+70% 物理攻撃）で殴る。ゴルムも動けず、スタン等で中断されると相手は解放される。
// 数値の換算: 公式の表を Velstria のランクへ線形補間し、sim の通常の式 (基礎 + 係数 × 攻撃力 × 0.6) × スロット倍率 に
//   スキルごとの換算（Tune.*Scale）を掛ける（H029 と同じ）。最大 HP の 4% は換算しない。マナ消費も公式の表（HeroKit.cost）。
// 再使用の窓は Franco に無いので使わない。
//
// 状態（KitState）:
//   ints[0]   = 闘気（0..10）            ints[1] = 「5 秒の無被弾」状態に入っているか（0/1）
//   ints[2]   = 奥義の段（0 = なし / 1 = 踏み込み中 / 2 = 拘束中）   ints[3] = 拘束中に殴った回数
//   ints[4]   = 命中した鉤の数（検証用）  ints[5] = 直前のスキルが消費した闘気の数（検証用）
//   ints[6]   = 無被弾の間に闘気を消費した（1 = 次にダメージを受けるまで闘気はたまらない）
//   timers[0] = 最後のダメージからの待ち（5 秒）  timers[1] = 次の闘気まで   timers[2] = 次の回復まで
//   timers[3] = 奥義の拘束の残り秒
//   ids[0]    = 奥義の対象                reals[0] = 奥義の 1 撃のダメージ（闘気の補正込み）

extension KitState {
    var gormStacks: Int {
        get { ints[0] }
        set { ints[0] = newValue }
    }

    var gormCalmActive: Bool {
        get { ints[1] != 0 }
        set { ints[1] = newValue ? 1 : 0 }
    }

    var gormUltPhase: Int {
        get { ints[2] }
        set { ints[2] = newValue }
    }

    var gormUltStrikes: Int {
        get { ints[3] }
        set { ints[3] = newValue }
    }

    var gormHooksLanded: Int {
        get { ints[4] }
        set { ints[4] = newValue }
    }

    /// 無被弾の間にスキルで闘気を消費したら、次にダメージを受けるまで闘気はたまらない（公式の注記）。
    var gormStackLock: Bool {
        get { ints[6] != 0 }
        set { ints[6] = newValue ? 1 : 0 }
    }

    var gormLastConsumed: Int {
        get { ints[5] }
        set { ints[5] = newValue }
    }

    var gormCalm: Double {
        get { timers[0] }
        set { timers[0] = newValue }
    }

    var gormStackTimer: Double {
        get { timers[1] }
        set { timers[1] = newValue }
    }

    var gormRegenTimer: Double {
        get { timers[2] }
        set { timers[2] = newValue }
    }

    var gormUltRemaining: Double {
        get { timers[3] }
        set { timers[3] = newValue }
    }

    var gormUltTarget: EntityID {
        get { ids[0] }
        set { ids[0] = newValue }
    }

    var gormUltDamage: Double {
        get { reals[0] }
        set { reals[0] = newValue }
    }
}

struct Kit_H034: HeroKit {
    let heroID = "H034"
    let isReady: Bool

    /// 既定は有効。テストは `Kit_H034(isReady: true)` を HeroKits.testOverride に差しても試せる（有効化とは独立）。
    init(isReady: Bool = true) {
        self.isReady = isReady
    }

    // MARK: - 数値（MLBB の値はそのまま。距離は Velstria 単位 ≈ MLBB × 100。調査に無い値は Franco.md の対応表に理由）

    enum Tune {
        // パッシブ 鉄鎖の執念
        /// 最後のダメージからこの秒数 ダメージを受けないと「無被弾」状態に入る。
        static let calmDelay = 5.0
        static let calmSpeed = 0.10
        /// 毎秒の回復（最大 HP の割合）。回復は regenPulse 秒ごとにまとめて行う（イベントを増やさない）。
        static let calmRegen = 0.01
        static let regenPulse = 0.5
        static let maxStacks = 10
        /// 闘気は無被弾の間 1 秒に 1 つ（調査に無い: 10 個で 15 秒＝無被弾の 5 秒 + 10 秒）。
        static let stackInterval = 1.0
        /// 1 つにつきスキルのダメージ +15%（調査: 最大 +150% の 1/10）。
        static let stackBonus = 0.15
        static let speedTag = KitTags.buff("H034", "calmSpeed")
        /// 「ダメージを受けるまで続く」加速のステータスに持たせる持続（実質無期限）。
        static let permanent = 1_000_000.0

        // S1 鎖鉤
        static let hookRange = 680.0
        /// 鉤の当たり幅（半径）。ヒーロー半径 55 と合わせて、左右 110 の筋に届く。
        static let hookWidth = 55.0
        static let hookSpeed = 1800.0
        /// 引き寄せの所要時間（この間は強制移動で動けない）。
        static let hookPull = 0.30
        /// 引き寄せた後に止まる、端同士の隙間。
        static let hookGap = 10.0
        /// 命中から数えるスタンの長さ。公式は「先にスタンを付け、それから引き寄せる」で、スタンは引き寄せの間だけ（= hookPull）。
        /// 着いたあとの追加のスタンは無い（以前は 0.7 秒を足して 1.0 秒にしていた）。
        static let hookStun = hookPull
        static let hookStunTag = KitTags.buff("H034", "hookStun")
        /// 公式: 400 → 650（+100% 総物理攻撃）。Lv1 → Lv6 を最大ランクへ線形補間。
        static let hookBase = (400.0, 650.0)
        static let hookAttackRatio = 1.0
        /// 公式の値 → Velstria の換算（sim の通常の式 × スロット倍率の後ろに掛ける）。鉤 1 回は汎用 S1 の約 1.3〜1.47 倍（予算の上限 1.3 を
        /// 少し超える）: スタンが公式の「引き寄せの間だけ」（1.0 → 0.3 秒）になり、Lv1（スキル1 だけの決闘）が同ロール中央値 −25 pt まで
        /// 落ちたので、勝率で上げた（予算内の 0.39 では帯の外）。
        static let hookScale = 0.45

        // スキル2 鉄鎖旋
        static let shockRadius = 260.0
        static let shockSlow = 0.70
        static let shockSlowDuration = 1.5
        static let shockSlowTag = KitTags.buff("H034", "shockSlow")
        /// 自分の最大 HP の 4%（公式。Velstria の HP は MLBB と同じ桁なので換算しない）。
        static let shockMaxHPRatio = 0.04
        /// 公式: 300 → 450（+ 自分の最大 HP の 4%）。攻撃力の係数は無い。
        static let shockBase = (300.0, 450.0)
        /// 公式の基礎 → Velstria の換算（最大 HP の 4% には掛けない）。最大 HP の 4% と合わせて汎用 S2 の 1.05〜1.25 倍。
        static let shockScale = 0.65

        // 奥義 狩猟鎖獄
        /// 術者の中心から対象の縁までの射程（短い）。
        static let ultReach = 350.0
        static let ultSuppress = 1.8
        static let ultHits = 6
        /// 拘束してから最初の 1 撃まで・撃つ間隔（6 回が拘束の 1.8 秒に収まる: 0.15, 0.45, ... 1.65）。
        static let ultFirst = 0.15
        static let ultInterval = 0.30
        /// 公式: 1 撃 50 / 60 / 70（+70% 総物理攻撃）。アルティメットの 3 ランク = 公式の Lv1〜3 そのまま。
        static let ultHitBase = (50.0, 70.0)
        static let ultHitAttackRatio = 0.7
        /// 公式の値 → Velstria の換算。サポートの汎用の奥義は回復でダメージ 0 なので比べる式は無く、勝率で決めた
        /// （クールダウンが汎用（34 秒）より長い 62 → 48 秒）。
        static let ultScale = 1.0
        /// 6 回の合計（軽減前）の上限 = 相手の最大 HP × この割合。闘気 10 個の +150% が通常の相手を一撃で倒さないための安全弁。
        static let ultMaxHPFraction = 0.8
        static let ultRushSpeed = 2600.0
        /// 踏み込んだ後に止まる、端同士の隙間。
        static let ultContactGap = 10.0
        /// 踏み込み終わりにこれより離れていたら外れ（追尾はしない）。
        static let ultSlack = 140.0
        static let lockRootTag = KitTags.buff("H034", "lockRoot")
        static let lockTag = KitTags.buff("H034", "lock")
        /// ボットのアルティメット: 相手の HP がこの割合未満 / 鉤でスタン中 / 近く（この距離以内）に味方ヒーローが居るとき、関門なしで撃つ。
        static let botWeakHP = 0.7
        static let botAllyRange = 800.0

        // クールダウン（公式の秒数そのまま。ランク間を線形補間し、CD 短縮を掛ける。全体倍率 Balance.Skills.cooldownScale は 1.0）
        /// 公式の 15 → 11 秒そのまま（ランク 1 も 15 秒）。
        static let hookCooldown = (15.0, 11.0)
        /// 公式の 7.0 → 4.5 秒そのまま（汎用の S2 は 9.8 秒からランクで短縮）。
        static let shockCooldown = (7.0, 4.5)
        /// 公式（日本語クライアント）62 / 55 / 48 秒（Liquipedia・以前の調査と同じ。Fandom の 45 は誤り）。3 段なので補間せず表で引く。
        static let ultCooldowns: [Double] = [62, 55, 48]
        // マナ消費（公式: スキル1 135 → 160、スキル2 40 → 65、アルティメット 110 / 125 / 140）
        static let hookCost = (135.0, 160.0)
        static let shockCost = (40.0, 65.0)
        static let ultCost = (110.0, 140.0)
    }

    private enum Code {
        static let strike = 1
        static let ultArrive = 2
    }

    /// HitPayload.kitEvent
    private enum Event {
        static let hook = 1
    }

    // MARK: - A. 記述

    func targeting(slot: SkillSlot, stage: Int, skill: SkillDef, hero: HeroDef, base: SkillTargeting) -> SkillTargeting {
        switch slot {
        case .skill1:
            // 長い直線の鉤（非貫通）。radius は弾の半幅
            return SkillTargeting(archetype: .lineSkillshot, aim: .direction, range: Tune.hookRange,
                                  radius: Tune.hookWidth, shape: .wideLine)
        case .skill2:
            // 自身中心の範囲（対象なし）
            return SkillTargeting(archetype: .selfAoE, aim: .none, range: 0, radius: Tune.shockRadius,
                                  shape: .selfRing)
        case .ultimate:
            // 対象指定（敵ヒーロー 1 体）。必要なら踏み込む
            return SkillTargeting(archetype: .targetedBlink, aim: .unit, range: Tune.ultReach, radius: 150,
                                  shape: .lockOn, requiresTarget: true)
        case .passive:
            return base
        }
    }

    func numbers(slot: SkillSlot, stage: Int, skill: SkillDef, hero: HeroDef, rank: Int, stats: Stats,
                 base: SkillNumbers) -> SkillNumbers {
        var n = base
        switch slot {
        case .passive:
            n.hits = Tune.maxStacks
            n.extras = [KitStat(key: "calmDelay", value: Tune.calmDelay),
                        KitStat(key: "speedPercent", value: Tune.calmSpeed * 100),
                        KitStat(key: "regenPercent", value: Tune.calmRegen * 100),
                        KitStat(key: "stackPercent", value: Tune.stackBonus * 100),
                        KitStat(key: "maxAmp", value: Tune.stackBonus * Double(Tune.maxStacks) * 100),
                        KitStat(key: "stackInterval", value: Tune.stackInterval)]
        case .skill1:
            n.damage = Self.hookDamage(rank: rank, stats: stats)
            n.cooldown = Self.cooldown(Tune.hookCooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.cc = .stun
            n.ccDuration = Tune.hookStun
            n.extras = [KitStat(key: "stun", value: Tune.hookStun),
                        KitStat(key: "pull", value: Tune.hookPull),
                        KitStat(key: "reachMult", value: Tune.hookRange / hero.attackRange),
                        KitStat(key: "base", value: Self.scaledBase(Tune.hookBase, slot: .skill1, scale: Tune.hookScale,
                                                                    rank: rank, maxRank: slot.maxRank).rounded()),
                        KitStat(key: "atkPct", value: Self.attackPercent(Tune.hookAttackRatio, slot: .skill1,
                                                                         scale: Tune.hookScale).rounded())]
        case .skill2:
            n.damage = Self.shockDamage(rank: rank, stats: stats)
            n.cooldown = Self.cooldown(Tune.shockCooldown, rank: rank, maxRank: slot.maxRank, stats: stats)
            n.cc = .slow
            n.ccDuration = Tune.shockSlowDuration
            n.extras = [KitStat(key: "slowPercent", value: Tune.shockSlow * 100),
                        KitStat(key: "slowDuration", value: Tune.shockSlowDuration),
                        KitStat(key: "maxHPPercent", value: Tune.shockMaxHPRatio * 100),
                        KitStat(key: "reachMult", value: Tune.shockRadius / hero.attackRange),
                        KitStat(key: "base", value: Self.scaledBase(Tune.shockBase, slot: .skill2, scale: Tune.shockScale,
                                                                    rank: rank, maxRank: slot.maxRank).rounded())]
        case .ultimate:
            // 汎用のサポートの奥義は味方回復（ダメージなし）。1 撃 = 公式の 50 / 60 / 70（+70% 物理攻撃）を換算した値
            n.damage = Self.ultHitDamage(rank: rank, stats: stats)
            n.hits = Tune.ultHits
            n.heal = 0
            n.shield = 0
            n.shieldDuration = 0
            n.cc = .stun
            n.ccIsUltimate = true
            n.ccDuration = Tune.ultSuppress
            n.cooldown = Self.ultCooldown(rank: rank, stats: stats)
            n.extras = [KitStat(key: "suppress", value: Tune.ultSuppress),
                        KitStat(key: "interval", value: Tune.ultInterval),
                        KitStat(key: "reachMult", value: Tune.ultReach / hero.attackRange),
                        KitStat(key: "base", value: Self.scaledBase(Tune.ultHitBase, slot: .ultimate, scale: Tune.ultScale,
                                                                    rank: rank, maxRank: slot.maxRank).rounded()),
                        KitStat(key: "atkPct", value: Self.attackPercent(Tune.ultHitAttackRatio, slot: .ultimate,
                                                                         scale: Tune.ultScale).rounded())]
        }
        return n
    }

    /// ランクごとのマナ消費（公式: スキル1 135 → 160、スキル2 40 → 65、アルティメット 110 / 125 / 140）。
    func cost(slot: SkillSlot, rank: Int, skill: SkillDef, hero: HeroDef, base: Double) -> Double {
        let table: (Double, Double)
        switch slot {
        case .skill1: table = Tune.hookCost
        case .skill2: table = Tune.shockCost
        case .ultimate: table = Tune.ultCost
        case .passive: return base
        }
        return HeroKits.resourceCost(Self.lerp(table.0, table.1, rank: rank, maxRank: slot.maxRank), hero: hero)
    }

    /// 説明文は公式（日本語クライアント）の文の構造に合わせる（数値は {トークン} で sim から。{base}(+{atkPct}%物理攻撃) は sim の式に換算した値）。
    /// 名前は master のもの（ワイルドフォース = 闘気、アイアンフック = 鎖鉤）。距離は近接攻撃の射程に対する倍率で括弧に足す。
    func text(slot: SkillSlot) -> KitText? {
        switch slot {
        case .passive:
            return KitText(
                ja: "{calmDelay}秒間ダメージを受けなかった場合、移動速度が{speedPercent}%上昇し、1秒ごとに最大HPの{regenPercent}%を回復し、闘気が蓄積され始める（{stackInterval}秒に1スタック、最大{hits}スタック）。\n\n"
                    + "次のスキル発動時にすべての闘気を消費し、そのスキルダメージを最大{maxAmp}%増加させる（1スタックにつき+{stackPercent}%）。",
                en: "If no damage is taken for {calmDelay}s, Gorm's Movement Speed increases by {speedPercent}%, he recovers {regenPercent}% of his Max HP every second, "
                    + "and Resolve begins to accumulate (1 stack every {stackInterval}s, up to {hits} stacks).\n\n"
                    + "His next skill cast consumes all Resolve to increase that skill's damage by up to {maxAmp}% (+{stackPercent}% per stack).",
                tags: [KitTag.buff])
        case .skill1:
            return KitText(
                ja: "指定方向へ鎖鉤を放ち（届くのは近接攻撃の射程の約{reachMult}倍）、最初に命中した敵に{base}(+{atkPct}%物理攻撃)の物理ダメージを与え、自身の元へ引き寄せる。\n\n"
                    + "鉤は先にスタンを付けてから引き寄せる（スタンは引き寄せの{x0}秒の間）。鉤は壁を越えて飛ぶが、引き寄せは壁の手前で止まる。タワーには当たらない。",
                en: "Launch the chain hook in the target direction (reaching about {reachMult}x the melee attack range), dealing {base} (+{atkPct}% Physical Attack) "
                    + "physical damage to the first enemy hit and pulling them to Gorm.\n\n"
                    + "The hook stuns first, then pulls (the stun lasts for the {x0}s pull). It flies over walls, but the pull stops at walls; it does not hit turrets.",
                tags: [KitTag.disrupt, KitTag.damage])
        case .skill2:
            return KitText(
                ja: "怒りの一撃で周囲（近接攻撃の射程の約{reachMult}倍）の敵に{base}(+自身の最大HPの{maxHPPercent}%)の物理ダメージを与え、{slowDuration}秒間移動速度を{slowPercent}%低下させる。",
                en: "Strike in fury, dealing {base} (+{maxHPPercent}% of Gorm's Max HP) physical damage to nearby enemies (within about {reachMult}x the melee attack range) "
                    + "and reducing their Movement Speed by {slowPercent}% for {slowDuration}s.",
                tags: [KitTag.slow])
        case .ultimate:
            return KitText(
                ja: "対象の敵ヒーロー（近接攻撃の射程の約{reachMult}倍以内。離れていれば踏み込む）を{suppress}秒間、制圧状態にし、その間に{hits}回攻撃する。攻撃ごとに{base}(+{atkPct}%物理攻撃)の物理ダメージを与える。\n\n"
                    + "制圧は浄化で解除できず、CC無効も無視する。ゴルムがコントロール効果を受けると、スキルは途中で終わる。",
                en: "Suppress the target enemy hero (within about {reachMult}x the melee attack range; Gorm rushes in if needed) for {suppress}s and attack them {hits} times "
                    + "during that time. Each attack deals {base} (+{atkPct}% Physical Attack) physical damage.\n\n"
                    + "Suppression cannot be cleansed and ignores crowd-control immunity. The skill ends early if Gorm is crowd controlled.",
                tags: [KitTag.burst, KitTag.disrupt])
        }
    }

    func badge(slot: SkillSlot, hero: HeroData) -> KitBadge? {
        guard let k = hero.kit else { return nil }
        switch slot {
        case .passive:
            return KitBadge(kind: .stacks, value: min(k.gormStacks, Tune.maxStacks), maxValue: Tune.maxStacks)
        case .ultimate:
            guard k.gormUltRemaining > 0 else { return nil }
            return KitBadge(kind: .timer, remaining: k.gormUltRemaining, total: Tune.ultSuppress)
        default:
            return nil
        }
    }

    // MARK: - B. 実行

    func resolveAim(_ s: SimState, _ ctx: SimContext, caster: Int, slot: SkillSlot, stage: Int,
                    targeting: SkillTargeting, target: SkillTarget) -> SkillAim?? {
        guard slot == .ultimate else { return nil }
        // 敵ヒーロー 1 体の対象指定: 射程内に居なければ拒否（コスト・CD を消費しない）
        guard let u = Self.pickHero(s, caster: caster, reach: targeting.reach, target: target) else {
            return .some(nil)
        }
        return .some(SkillAiming.aim(at: u, s, caster: caster, range: targeting.range,
                                     facing: Vec2.fromAngle(s.units[caster].facing)))
    }

    /// 奥義の最中は、他のスキルも奥義も撃てない（鎖で相手と繋がっている）。
    func canStart(_ s: SimState, _ ctx: SimContext, caster: Int, slot: SkillSlot) -> Bool {
        (s.units[caster].hero?.kit?.gormUltPhase ?? 0) == 0
    }

    func cast(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) -> KitCastOutcome {
        switch c.slot {
        case .skill1: castHook(&s, c)
        case .skill2: castShock(&s, ctx, c)
        case .ultimate: castHunt(&s, ctx, c)
        case .passive: break
        }
        return .done
    }

    /// 闘気をすべて消費し、そのスキルのダメージ倍率（1 + 0.15 × 闘気）を返す。外れても消費する（調査: 次のスキルの発動で消費）。
    private func consumeStacks(_ s: inout SimState, _ i: Int) -> Double {
        guard let k = s.units[i].hero?.kit else { return 1 }
        let n = k.gormStacks
        s.units[i].hero!.kit!.gormStacks = 0
        s.units[i].hero!.kit!.gormLastConsumed = n
        // 無被弾の間に消費したら、次にダメージを受けるまで闘気はたまらない（加速・回復は続く）
        if k.gormCalmActive { s.units[i].hero!.kit!.gormStackLock = true }
        return 1 + Tune.stackBonus * Double(n)
    }

    /// S1: 非貫通の鉤。最初に当たった敵へダメージ + スタン + 足元への引き寄せ。
    private func castHook(_ s: inout SimState, _ c: KitCast) {
        let i = c.caster
        let amp = consumeStacks(&s, i)
        let stun = StatusEffect(kind: .stun, duration: Tune.hookStun, sourceID: s.units[i].id, tag: Tune.hookStunTag)
        // 距離は十分に大きく取る（実際の移動量は gap で決まる）
        let pull = HitEffect.pullToOwner(distance: Tune.hookRange + 400, duration: Tune.hookPull, gap: Tune.hookGap)
        let p = HitPayload(damage: c.numbers.damage * amp, damageType: c.numbers.damageType, source: .skill(.skill1),
                           statuses: [stun], skillID: c.check.skill.skillID, effects: [pull],
                           originPos: s.units[i].pos, kitEvent: Event.hook)
        Kit.emitCast(&s, c, target: s.units[i].pos + c.aim.direction * Tune.hookRange, unit: c.aim.unit,
                     shape: .wideLine, duration: Tune.hookRange / Tune.hookSpeed, count: 1)
        ProjectileSystem.spawn(&s, ownerIndex: i, motion: .linear(direction: c.aim.direction, maxDistance: Tune.hookRange),
                               speed: Tune.hookSpeed, width: Tune.hookWidth, pierce: false, payload: p,
                               visual: c.check.skill.effectID)
    }

    /// S2: 自身中心の円。固定部分 + 自分の最大 HP の 4%（numbers に含まれる）に闘気の補正、70% 減速。
    private func castShock(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) {
        let i = c.caster
        let amp = consumeStacks(&s, i)
        let slow = StatusEffect(kind: .slow, duration: Tune.shockSlowDuration, magnitude: Tune.shockSlow,
                                sourceID: s.units[i].id, tag: Tune.shockSlowTag)
        let p = HitPayload(damage: c.numbers.damage * amp, damageType: c.numbers.damageType, source: .skill(.skill2),
                           statuses: [slow], skillID: c.check.skill.skillID, originPos: s.units[i].pos)
        Kit.emitCast(&s, c, target: s.units[i].pos, shape: .selfRing, count: 1)
        SkillArchetypes.hitArea(&s, ctx, caster: i, center: s.units[i].pos, radius: c.targeting.radius, shape: .circle,
                                payload: p)
    }

    /// 奥義: 対象へ踏み込み（離れていれば）、着いたら拘束して 6 回殴る。
    private func castHunt(_ s: inout SimState, _ ctx: SimContext, _ c: KitCast) {
        let i = c.caster
        guard let t = c.aim.unit else { return }
        let amp = consumeStacks(&s, i)
        s.units[i].hero!.kit!.gormUltTarget = s.units[t].id
        s.units[i].hero!.kit!.gormUltDamage = c.numbers.damage * amp
        Kit.emitCast(&s, c, target: s.units[t].pos, unit: t, shape: .lockOn, duration: Tune.ultSuppress,
                     count: Tune.ultHits)

        let from = s.units[i].pos
        let to = s.units[t].pos
        let gap = s.units[i].radius + s.units[t].radius + Tune.ultContactGap
        let dist = from.distance(to: to)
        guard dist - gap > 1 else {
            beginLock(&s, ctx, owner: i)
            return
        }
        // 踏み込み（経路上の敵には当てない carrier。ハード CC の中断と着地の通知だけを使う）
        s.units[i].hero!.kit!.gormUltPhase = 1
        let dir = (to - from).normalized
        let carrier = HitPayload(damage: 0, damageType: .physical, source: .skill(.ultimate), affectsEnemies: false)
        Kit.dashSweeping(&s, ctx, caster: i, slot: .ultimate, to: from + dir * (dist - gap), speed: Tune.ultRushSpeed,
                         payload: carrier, radius: 0, arriveCode: Code.ultArrive)
    }

    /// 拘束の開始: 対象を suppress し、自分は動けない詠唱に入り、6 回の連撃を予約する。成立しなければ何もせず終わる。
    private func beginLock(_ s: inout SimState, _ ctx: SimContext, owner i: Int) {
        guard let k = s.units[i].hero?.kit else { return }
        let tid = k.gormUltTarget
        guard tid != 0, let t = s.index(of: tid), CombatSystem.isLiving(s, t), s.units[t].team != s.units[i].team,
              s.units[t].kind == .hero else {
            endLock(&s, owner: i, release: false)
            return
        }
        let reach = s.units[i].radius + s.units[t].radius + Tune.ultContactGap + Tune.ultSlack
        guard s.units[i].pos.distanceSquared(to: s.units[t].pos) <= reach * reach else {
            endLock(&s, owner: i, release: false)
            return
        }
        let id = s.units[i].id
        Kit.suppress(&s, target: t, duration: Tune.ultSuppress, sourceID: id)
        // 無敵などで拘束できなかった（suppress が付かない）なら、連撃に入らない
        guard s.units[t].has(.suppress) else {
            endLock(&s, owner: i, release: false)
            return
        }
        CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .root, duration: Tune.ultSuppress, sourceID: id,
                                                                 tag: Tune.lockRootTag))
        CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .channeling, duration: Tune.ultSuppress,
                                                                 sourceID: id, tag: Tune.lockTag))
        let face = s.units[t].pos - s.units[i].pos
        if face != .zero { s.units[i].facing = face.angle }
        s.units[i].windupRemaining = nil
        s.units[i].hero!.kit!.gormUltPhase = 2
        s.units[i].hero!.kit!.gormUltRemaining = Tune.ultSuppress
        s.units[i].hero!.kit!.gormUltStrikes = 0
        Kit.strikeSequence(&s, caster: i, slot: .ultimate, code: Code.strike, count: Tune.ultHits,
                           interval: Tune.ultInterval, firstDelay: Tune.ultFirst, targetID: tid)
    }

    /// 奥義の終わり（自然終了・対象の消失・中断）。release なら相手の拘束も外す。
    private func endLock(_ s: inout SimState, owner i: Int, release: Bool) {
        guard s.units[i].hero?.kit != nil else { return }
        if release { Kit.releaseSuppress(&s, bySource: s.units[i].id) }
        s.units[i].statuses.removeAll {
            ($0.kind == .root && $0.tag == Tune.lockRootTag) || ($0.kind == .channeling && $0.tag == Tune.lockTag)
        }
        Kit.cancelScheduled(&s, caster: i, slot: .ultimate)
        s.units[i].hero!.kit!.gormUltPhase = 0
        s.units[i].hero!.kit!.gormUltRemaining = 0
        s.units[i].hero!.kit!.gormUltTarget = 0
        s.units[i].hero!.kit!.gormUltDamage = 0
    }

    func onTimer(_ s: inout SimState, _ ctx: SimContext, owner: Int, timer: KitTimer) {
        guard let k = s.units[owner].hero?.kit else { return }
        switch timer.code {
        case Code.ultArrive:
            guard k.gormUltPhase == 1 else { return }
            beginLock(&s, ctx, owner: owner)
        case Code.strike:
            guard k.gormUltPhase == 2, k.gormUltTarget == timer.targetID else { return }
            strike(&s, ctx, owner: owner, timer: timer)
        default:
            break
        }
    }

    /// 拘束中の 1 撃。対象が倒れた・居なくなった・拘束が外れていたら、残りの連撃を取りやめて解放する。
    private func strike(_ s: inout SimState, _ ctx: SimContext, owner i: Int, timer: KitTimer) {
        guard let t = s.index(of: timer.targetID), CombatSystem.isLiving(s, t), s.units[t].has(.suppress) else {
            endLock(&s, owner: i, release: true)
            return
        }
        // 闘気 10 個の +150% でも、6 回の合計（軽減前）は相手の最大 HP の ultMaxHPFraction までに抑える（一撃にならないように）
        let cap = s.units[t].stats.maxHP * Tune.ultMaxHPFraction / Double(Tune.ultHits)
        let damage = min(s.units[i].hero?.kit?.gormUltDamage ?? 0, cap)
        let p = HitPayload(damage: damage, damageType: .physical, source: .skill(.ultimate), ccIsUltimate: true,
                           skillID: Self.skillID(ctx, .ultimate), originPos: s.units[i].pos)
        CombatSystem.applyHit(&s, ctx, sourceID: s.units[i].id, team: s.units[i].team, targetIndex: t, payload: p,
                              from: s.units[i].pos)
        s.units[i].hero?.kit?.gormUltStrikes += 1
        if !CombatSystem.isLiving(s, t) { endLock(&s, owner: i, release: true) }
    }

    func onHit(_ s: inout SimState, _ ctx: SimContext, owner: Int, target: Int, event: Int, dealt: Double) {
        guard event == Event.hook, s.units[owner].hero?.kit != nil else { return }
        s.units[owner].hero!.kit!.gormHooksLanded += 1
    }

    func update(_ s: inout SimState, _ ctx: SimContext, owner i: Int) {
        guard let k = s.units[i].hero?.kit else { return }
        // カウントダウンは 0 まで減らすだけで厳密には 0 にならないことがある（浮動小数の端数）
        let eps = 1e-6

        // 奥義の拘束中: 通常攻撃はしない。時間が来たら終わり（相手の拘束は自然に切れる）
        if k.gormUltPhase == 2 {
            if k.gormUltRemaining <= eps {
                endLock(&s, owner: i, release: false)
            } else {
                s.units[i].windupRemaining = nil
                if s.units[i].attackCooldown < 0.1 { s.units[i].attackCooldown = 0.1 }
            }
        }

        // パッシブ: 5 秒ダメージを受けていない間の加速・回復・闘気
        guard k.gormCalm <= eps else { return }
        let id = s.units[i].id
        if !k.gormCalmActive {
            s.units[i].hero!.kit!.gormCalmActive = true
            s.units[i].hero!.kit!.gormStackTimer = Tune.stackInterval
            s.units[i].hero!.kit!.gormRegenTimer = Tune.regenPulse
        } else if k.gormStackTimer <= eps {
            if !k.gormStackLock {
                s.units[i].hero!.kit!.gormStacks = min(Tune.maxStacks, k.gormStacks + 1)
            }
            s.units[i].hero!.kit!.gormStackTimer = Tune.stackInterval
        }
        if !s.units[i].statuses.contains(where: { $0.kind == .speedBoost && $0.tag == Tune.speedTag }) {
            CombatSystem.addStatus(&s, targetIndex: i, StatusEffect(kind: .speedBoost, duration: Tune.permanent,
                                                                     magnitude: Tune.calmSpeed, sourceID: id,
                                                                     tag: Tune.speedTag))
        }
        if s.units[i].hero!.kit!.gormRegenTimer <= eps, s.units[i].hp < s.units[i].stats.maxHP {
            s.units[i].hero!.kit!.gormRegenTimer = Tune.regenPulse
            // 自己再生（回復強化・回復量スコア・アシスト記録の対象外。被回復の増減は受ける）
            CombatSystem.restoreHealth(&s, ctx, sourceID: id, targetIndex: i,
                                       amount: s.units[i].stats.maxHP * Tune.calmRegen * Tune.regenPulse, isVamp: true)
        }
    }

    func onInterrupted(_ s: inout SimState, _ ctx: SimContext, owner: Int) {
        // 踏み込み・拘束中のハード CC（スタン・打ち上げ・suppress）: 連撃は取り消され、相手は解放される
        guard (s.units[owner].hero?.kit?.gormUltPhase ?? 0) != 0 else { return }
        endLock(&s, owner: owner, release: true)
    }

    // MARK: - C. パッシブ（鉄鎖の執念）

    func onDamageTaken(_ s: inout SimState, _ ctx: SimContext, victim: Int, attacker: Int?, amount: Double) {
        guard amount > 0, s.units[victim].hero?.kit != nil else { return }
        // 無被弾の待ちをやり直し。加速と回復は止まり、闘気はそのまま残る（調査: 減衰の規則は不明）
        s.units[victim].hero!.kit!.gormCalm = Tune.calmDelay
        s.units[victim].hero!.kit!.gormCalmActive = false
        s.units[victim].hero!.kit!.gormStackLock = false
        s.units[victim].hero!.kit!.gormStackTimer = 0
        s.units[victim].hero!.kit!.gormRegenTimer = 0
        s.units[victim].statuses.removeAll { $0.kind == .speedBoost && $0.tag == Tune.speedTag }
    }

    // MARK: - D. ボット

    func botCast(_ s: SimState, _ ctx: SimContext, bot: Int, slot: SkillSlot, targeting: SkillTargeting,
                 target: Int, fighting: Bool) -> BotKitDecision {
        let me = s.units[bot].pos
        switch slot {
        case .skill1:
            // 鉤は最初に当たった敵を引く: 狙う相手より手前の線上にミニオン・モンスターが居るなら撃たない（鉤を無駄にしない）。
            // 手前に別の敵ヒーローが居る場合は、その相手を引けるので撃ってよい
            let delta = s.units[target].pos - me
            let dist = delta.length
            guard dist > 1e-6 else { return .useDefault }
            let dir = delta.normalized
            let team = s.units[bot].team
            for j in s.units.indices where j != target && s.units[j].team != team && !s.units[j].isStructure
                && s.units[j].kind != .hero {
                guard CombatSystem.isLiving(s, j) else { continue }
                let rel = s.units[j].pos - me
                let along = rel.dot(dir)
                guard along > 0, along < dist, along <= Tune.hookRange else { continue }
                let lateral = abs(rel.x * dir.y - rel.y * dir.x)
                if lateral <= Tune.hookWidth + s.units[j].radius { return .skip }
            }
            return .useDefault
        case .ultimate:
            // 鉤 → 奥義が持ち味: 射程内の敵ヒーローが、傷ついている / 鉤でスタン中 / 近くに味方が居る、のいずれかなら
            // 汎用の関門（倒せる・2 体）を飛び越えて撃つ。それ以外は汎用の判断
            guard fighting, s.units[target].kind == .hero, s.units[target].team != s.units[bot].team else {
                return .useDefault
            }
            let reach = Tune.ultReach + s.units[target].radius
            guard s.units[target].pos.distanceSquared(to: me) <= reach * reach else { return .skip }
            let hooked = s.units[target].statuses.contains { $0.kind == .stun && $0.tag == Tune.hookStunTag }
            var ready = hooked || s.units[target].hpRatio < Tune.botWeakHP
            if !ready {
                for j in s.units.indices where j != bot && s.units[j].kind == .hero
                    && s.units[j].team == s.units[bot].team {
                    guard CombatSystem.isLiving(s, j) else { continue }
                    if s.units[j].pos.distanceSquared(to: me) <= Tune.botAllyRange * Tune.botAllyRange {
                        ready = true
                        break
                    }
                }
            }
            return ready ? .castNow(.unit(s.units[target].id)) : .useDefault
        default:
            return .useDefault
        }
    }

    // MARK: - 部品

    /// MLBB のクールダウン（秒）をランクで線形補間し、CD 短縮を掛ける（全体倍率 cooldownScale は 1.0 = MLBB の秒数のまま）。
    static func cooldown(_ range: (Double, Double), rank: Int, maxRank: Int, stats: Stats) -> Double {
        let sec = lerp(range.0, range.1, rank: rank, maxRank: maxRank)
        let reduction = min(Balance.maxCooldownReduction, max(0, stats.cooldownReduction))
        return sec * (1 - reduction) * Balance.Skills.cooldownScale
    }

    /// アルティメットのクールダウン（公式 62 / 55 / 48 秒を表で引き、CD 短縮を掛ける）。
    static func ultCooldown(rank: Int, stats: Stats) -> Double {
        let sec = Tune.ultCooldowns[min(max(1, rank), Tune.ultCooldowns.count) - 1]
        let reduction = min(Balance.maxCooldownReduction, max(0, stats.cooldownReduction))
        return sec * (1 - reduction) * Balance.Skills.cooldownScale
    }

    static func lerp(_ a: Double, _ b: Double, rank: Int, maxRank: Int) -> Double {
        guard maxRank > 1 else { return a }
        let t = Double(min(max(1, rank), maxRank) - 1) / Double(maxRank - 1)
        return a + (b - a) * t
    }

    // MARK: - ダメージ（公式の表 → sim の式）

    /// 公式の基礎ダメージ（ランクで補間）を sim の通常の式に通した「換算後の基礎」。
    static func scaledBase(_ table: (Double, Double), slot: SkillSlot, scale: Double, rank: Int, maxRank: Int) -> Double {
        lerp(table.0, table.1, rank: rank, maxRank: maxRank) * Balance.Skills.damageScale(slot) * scale
    }

    /// 公式の「+N% 物理攻撃」を sim の通常の式（× skillAttackScalingFactor × スロット倍率 × 換算）に通した、攻撃力に対する割合（%）。
    static func attackPercent(_ ratio: Double, slot: SkillSlot, scale: Double) -> Double {
        ratio * Balance.skillAttackScalingFactor * Balance.Skills.damageScale(slot) * scale * 100
    }

    /// (公式の基礎 + 係数 × 攻撃力 × skillAttackScalingFactor) × スロット倍率 × 換算。
    private static func damage(base: (Double, Double), ratio: Double, slot: SkillSlot, scale: Double, rank: Int,
                               stats: Stats) -> Double {
        let b = lerp(base.0, base.1, rank: rank, maxRank: slot.maxRank)
        return (b + ratio * stats.attack * Balance.skillAttackScalingFactor) * Balance.Skills.damageScale(slot) * scale
    }

    /// スキル1 の鉤（400 → 650 + 100% 物理攻撃）。
    static func hookDamage(rank: Int, stats: Stats) -> Double {
        damage(base: Tune.hookBase, ratio: Tune.hookAttackRatio, slot: .skill1, scale: Tune.hookScale, rank: rank,
               stats: stats)
    }

    /// スキル2（300 → 450 を換算 + 自分の最大 HP の 4%。最大 HP の部分は換算しない）。
    static func shockDamage(rank: Int, stats: Stats) -> Double {
        damage(base: Tune.shockBase, ratio: 0, slot: .skill2, scale: Tune.shockScale, rank: rank, stats: stats)
            + stats.maxHP * Tune.shockMaxHPRatio
    }

    /// アルティメットの 1 撃（50 / 60 / 70 + 70% 物理攻撃）。
    static func ultHitDamage(rank: Int, stats: Stats) -> Double {
        damage(base: Tune.ultHitBase, ratio: Tune.ultHitAttackRatio, slot: .ultimate, scale: Tune.ultScale, rank: rank,
               stats: stats)
    }

    static func skillID(_ ctx: SimContext, _ slot: SkillSlot) -> String? {
        ctx.master.skill(hero: "H034", slot: slot)?.skillID
    }

    /// 奥義の対象の選び方: 指定ユニット → 指定地点に近い敵 → 向きに近い敵 → 自動（HP + シールド最小）。
    /// すべて「術者の中心から対象の縁まで reach 以内」の視認中の敵ヒーロー（無敵・対象不可を除く）。
    static func pickHero(_ s: SimState, caster i: Int, reach: Double, target: SkillTarget) -> Int? {
        let team = s.units[i].team
        let pos = s.units[i].pos
        func inReach(_ j: Int) -> Bool {
            guard j != i, s.units[j].kind == .hero, s.isTargetableEnemy(j, of: team),
                  !s.units[j].has(.invulnerable) else { return false }
            let r = reach + s.units[j].radius
            return s.units[j].pos.distanceSquared(to: pos) <= r * r
        }
        if case .unit(let id) = target, let j = s.index(of: id), inReach(j) { return j }

        var best: Int?
        var bestKey = Double.infinity
        for j in s.units.indices where inReach(j) {
            let key: Double
            switch target {
            case .point(let p):
                key = s.units[j].pos.distanceSquared(to: p)
            case .direction(let d):
                let delta = s.units[j].pos - pos
                let len = delta.length
                let cosine = len > 1e-9 ? delta.dot(d.normalized) / len : 1
                key = (1 - cosine) * 1e7 + len
            case .unit, .none:
                key = max(0, s.units[j].hp) + s.units[j].totalShield
            }
            if key < bestKey {
                bestKey = key
                best = j
            }
        }
        return best
    }
}
