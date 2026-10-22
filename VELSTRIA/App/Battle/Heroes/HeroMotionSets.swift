import Foundation
import simd

// 担当: hero-models。ヒーローごとに使うモーションクリップの割り当て（暫定表）。
// 名前は HeroMotionClips.json のクリップ名（docs/HERO_MOTION.md）。ライブラリに無い名前は黙って落とし、
// その動作は手続きアニメーションのまま（クリップが揃う前でも壊れない）。
// 表は武器・副手・AttackStyle（HeroBlueprints）から選んだ暫定値で、クリップを見てから調整する。

/// 1 ヒーロー分のクリップ割り当て。
struct HeroMotionSet {
    /// 通常攻撃（順に繰り返す）。
    var attacks: [String] = []
    /// 通常攻撃のマスク。.full = 立ち止まっている時は全身・移動中は上半身、.upper = 常に上半身。
    var attackMask: HeroClipMask = .full
    /// スキル詠唱（Skill1, Skill2, Ultimate の順。nil = 手続き）。
    var casts: [String?] = [nil, nil, nil]
    /// スキルが最初に当たった時（playCastHit）に始め直す詠唱のクリップ（Skill1, Skill2, Ultimate。H034 の鎖鉤の引き寄せ）。
    var castHits: [String?] = [nil, nil, nil]
    /// 詠唱のクリップを発動の瞬間（先頭）から再生する。クリップの impact は KitTimes の判定の時刻に置いてある（H034）。
    /// false = 既定（打撃が呼び出しの castLead 秒後に来るよう、打撃の手前から始める）。
    var castsFromStart = false
    /// 詠唱のクリップが移動中も脚を持つ（突進の間に足を回さない。H027 の竜牙突き）。Skill1, Skill2, Ultimate。
    var castLocksLegs: [Bool] = [false, false, false]
    /// 再使用の段（stage 1）の詠唱（Skill1, Skill2, Ultimate の順。nil = 段 0 と同じ）。
    var stageCasts: [String?] = [nil, nil, nil]
    var idle: String?
    /// 待機のクリップが専用の収録（H025・H034）。HeroIdle の個別の待機より優先する。
    var dedicatedIdle = false
    /// 通常攻撃のクリップが専用の収録（H034）。HeroSkillMotions の全身の通常攻撃（Motion_H0xx.attacks）より優先する。
    var dedicatedAttack = false
    /// キットの強い通常攻撃（三連突き）の専用クリップ。あれば手続きの全身のモーション（HeroSkillMotions）より優先する（H027）。
    var empowered: String?
    /// 待機・歩行・走行の切り替えのクロスフェード（秒）。
    var stateBlend: Float = HeroClipLayer.fadeIn
    var walk: String?
    var run: String?
    var death: String?
    var victory: String?
    var stunned: String?
    var channel: String?
    /// 手の区間に対する武器（Prop 空間: 握りが原点・+Y へ伸びる）の向き。既定は +Y → 手の区間の正面 -Z
    /// （腕を下ろすと刃先が前、腕を前へ出すと刃先が上 = 拳で握った向き）。
    /// nil = 向きは手続きの武器角を胴に対して保ち、位置だけ手に付ける（杖・槍・銃・弓・盾・灯籠。手首の向きで寝かせない）。
    var weaponGrip: simd_quatf? = HeroMotionSet.fistGrip
    var offhandGrip: simd_quatf? = nil
    /// 武器・副手を前腕に沿う縦の刃として持つ（H032 の刃の輪。grip は使わない。取得素材の手首・前腕のねじれで輪が傾かない）。
    var gripOnForeArm = false
    /// 状態のクリップ（待機・勝利など。腕を下ろした立ち姿）を重ねている間の武器角（grip が nil の武器だけ。手続きの武器角 θ と同じ:
    /// 胴座標の絶対角、0 = 真上、-π/2 = 前）。nil = 手続きの構え（rest）の角のまま。
    /// 槍の構え（rest -1.0 = 前へ寝かせる）は腕を下ろした待機だと穂先が顔の前を横切るので立てて持ち、
    /// 弓（rest 0 = 真っ直ぐ）は上の弓先を少し前へ傾けて手に握っているように見せる（下の弓先が足元に立たない）。
    var idleWeaponR: Float?
    var idleWeaponL: Float?

    /// 拳で握る（+Y → -Z）。剣・槍・杖・盾・弓。
    static let fistGrip = rx(-.pi / 2)
    /// 銃把で握る（+Y = 銃身 → 手の向き、上面 +Z → 親指の側）。銃・弩。
    static let pistolGrip = rx(.pi)
}

/// HeroMotionSet をライブラリの添字へ解決したもの（無い名前は落とす）。毎フレームは添字だけを使う。
struct HeroMotionBinding {
    let library: HeroMotionLibrary
    let attacks: [Int]
    let attackMask: HeroClipMask
    /// Skill1, Skill2, Ultimate。
    let casts: [Int?]
    let castHits: [Int?]
    let castsFromStart: Bool
    let castLocksLegs: [Bool]
    let stageCasts: [Int?]
    let idle: Int?
    let dedicatedIdle: Bool
    let empowered: Int?
    let stateBlend: Float
    let walk: Int?
    let run: Int?
    let death: Int?
    let victory: Int?
    let stunned: Int?
    let channel: Int?
    let weaponGrip: simd_quatf?
    let offhandGrip: simd_quatf?
    let gripOnForeArm: Bool
    let idleWeaponR: Float?
    let idleWeaponL: Float?

    /// どのクリップも見つからなければ nil（重ねる層を持たず、手続きと完全に同じ）。
    init?(set: HeroMotionSet, library: HeroMotionLibrary) {
        func find(_ name: String?) -> Int? { name.flatMap { library.index(of: $0) } }
        attacks = set.attacks.compactMap { library.index(of: $0) }
        casts = (0..<3).map { $0 < set.casts.count ? find(set.casts[$0]) : nil }
        castHits = (0..<3).map { $0 < set.castHits.count ? find(set.castHits[$0]) : nil }
        castsFromStart = set.castsFromStart
        castLocksLegs = (0..<3).map { $0 < set.castLocksLegs.count && set.castLocksLegs[$0] }
        stageCasts = (0..<3).map { $0 < set.stageCasts.count ? find(set.stageCasts[$0]) : nil }
        idle = find(set.idle)
        dedicatedIdle = set.dedicatedIdle && idle != nil
        empowered = find(set.empowered)
        stateBlend = set.stateBlend
        walk = find(set.walk)
        run = find(set.run)
        death = find(set.death)
        victory = find(set.victory)
        stunned = find(set.stunned)
        channel = find(set.channel)
        let any = !attacks.isEmpty || casts.contains { $0 != nil }
            || [idle, walk, run, death, victory, stunned, channel].contains { $0 != nil }
        guard any else { return nil }
        self.library = library
        attackMask = set.attackMask
        weaponGrip = set.weaponGrip
        offhandGrip = set.offhandGrip
        gripOnForeArm = set.gripOnForeArm
        idleWeaponR = set.idleWeaponR
        idleWeaponL = set.idleWeaponL
    }

    /// スキル枠 → casts の添字（パッシブは Skill1 と同じ。HeroAnimator.castIndex と同じ対応）。
    func cast(_ index: Int) -> Int? { index >= 0 && index < casts.count ? casts[index] : nil }
    func castHit(_ index: Int) -> Int? { index >= 0 && index < castHits.count ? castHits[index] : nil }
    func locksLegs(_ index: Int) -> Bool { index >= 0 && index < castLocksLegs.count && castLocksLegs[index] }

    /// 段（stage ≥ 1）の詠唱。段に専用のクリップが無ければ段 0 と同じ。
    func cast(_ index: Int, stage: Int) -> Int? {
        if stage >= 1, index >= 0, index < stageCasts.count, let c = stageCasts[index] { return c }
        return cast(index)
    }
}

enum HeroMotionSets {
    /// heroID の割り当て（未知の ID は nil = 手続きのみ）。
    static func set(heroID: String) -> HeroMotionSet? {
        guard var set = table[heroID] else { return nil }
        if HeroIdle.authored(for: heroID) != nil && !set.dedicatedIdle {
            set.idle = nil
            set.idleWeaponR = nil
            set.idleWeaponL = nil
        }
        return set
    }

    private static func make(_ attacks: [String], idle: String? = nil, death: String = "death_back",
                             victory: String = "victory_pump", mask: HeroClipMask = .full,
                             weaponGrip: simd_quatf? = HeroMotionSet.fistGrip,
                             offhandGrip: simd_quatf? = nil,
                             idleWeaponR: Float? = nil, idleWeaponL: Float? = nil) -> HeroMotionSet {
        var s = HeroMotionSet()
        s.attacks = attacks
        s.attackMask = mask
        // スキルの詠唱はスキル演出（SkillMotion の MotionClip。docs/SKILL_FX.md）の手続きモーションに任せる:
        // 演出の打撃の時刻はそのモーションのキーに合わせてあり、クリップを重ねるとずれる
        s.idle = idle
        s.death = death
        s.victory = victory
        // 移動は手続き（速度に合わせた歩幅）。帰還の片膝立ちは手続き（kneel クリップは脚の長さの違いで腰が浮く）
        s.weaponGrip = weaponGrip
        s.offhandGrip = offhandGrip
        s.idleWeaponR = idleWeaponR
        s.idleWeaponL = idleWeaponL
        return s
    }

    /// 杖・槍・銃など、向きを胴に対して保つ武器。
    private static let held: simd_quatf? = nil
    /// 待機のクリップ中に槍を立てて持つ角（わずかに穂先を前へ）。
    private static let spearIdle: Float = -0.22
    /// 待機のクリップ中の弓（上の弓先を前へ傾ける）。
    private static let bowIdle: Float = -0.38

    /// H027 竜槍のジャルド: Meshy prime の体の動き + 槍の軌道・両手の握り・接地を Blender で仕上げた専用クリップ
    /// （H027MotionClips.json、docs/H027_MOTION.md）。槍は右手の区間に追従させ（握りの向きは仕上げと同じ値）、
    /// 左手は仕上げで柄の上に置いてある。詠唱もクリップ（打撃の時刻 = 呼び出しの castLead 後。演出の時刻は FX_H027 のまま）。
    private static let jarld: HeroMotionSet = {
        var s = make(["h027_thrust", "h027_sweep", "h027_rising"], idle: "h027_idle", death: "death_forward",
                     weaponGrip: rx(-.pi / 2) * ry(-0.1658))
        s.dedicatedIdle = true
        s.walk = "h027_walk"
        s.run = "h027_run"
        s.empowered = "h027_flurry"
        s.casts = ["h027_flip", "h027_strike", "h027_warrior"]
        s.castHits = [nil, "h027_strike_hit", nil]
        s.castLocksLegs = [false, true, false]
        return s
    }()

    private static let lumina: HeroMotionSet = {
        var s = make(["h025_bow_attack"], idle: "h025_idle", death: "death_forward",
                     victory: "victory_cheer", offhandGrip: rx(-.pi / 2) * ry(-0.6))
        s.dedicatedIdle = true
        s.walk = "h025_walk"
        s.run = "h025_run"
        return s
    }()

    /// H033 ヴァルド: Meshy prime の収録を仕上げた専用クリップ（H033MotionClips.json、docs/H033_MOTION.md）。大剣は右手の片手持ち。
    /// 通常攻撃は斜めの斬り下ろし → 頭上からの叩き割りを交互に。スキルは S1 跳び叩き（跳び込みの間も脚はクリップ）・
    /// S2 回転斬りの構え（回転そのものは FX_H033.motion の手続きの spin）・奥義の吸収（段 0）と衝撃波の振り抜き（段 1）。
    private static let vald: HeroMotionSet = {
        var s = make(["sword_slash_h033", "sword_chop_h033"], idle: "idle_h033", death: "death_forward")
        s.dedicatedIdle = true
        s.walk = "walk_h033"
        s.run = "run_h033"
        s.casts = ["leap_slam_h033", "spin_slash_h033", "ult_absorb_h033"]
        s.stageCasts = [nil, nil, "ult_wave_h033"]
        s.castLocksLegs = [true, false, false]
        return s
    }()

    /// H034 ゴルム: Meshy prime の叩きつけと Tripo の歩容を仕上げた専用の収録（H034MotionClips.json、docs/H034_MOTION.md）。
    /// 待機・歩行・走行・通常攻撃・スキルの詠唱（発動から再生し、打撃は KitTimes: hookDelay・shockDelay・ultDelay + ultInterval）。
    /// 鎖鉤が当たると引き寄せ（hookHold → hookPull）のクリップへ。クリップが無ければ Motion_H034 の詠唱のまま。
    private static let gorm: HeroMotionSet = {
        var s = make(["chain_slam_h034"], idle: "idle_h034")
        s.casts = ["hook_throw_h034", "chain_smash_h034", "chain_frenzy_h034"]
        s.castHits = ["hook_pull_h034", nil, nil]
        s.castsFromStart = true
        s.dedicatedIdle = true
        s.dedicatedAttack = true
        s.walk = "walk_h034"
        s.run = "run_h034"
        return s
    }()

    /// H031 オーリア: Meshy prime を土台に仕上げた待機・歩行・走行・通常攻撃・スキル詠唱（H031MotionClips.json、
    /// docs/H031_MOTION.md）。氷華の右手から放つので武器の向きは手続きのまま（held）。詠唱クリップの先頭が呼び出しの瞬間。
    private static let aurora: HeroMotionSet = {
        var s = make(["cast_frost_h031"], idle: "idle_h031", death: "death_forward", victory: "victory_cheer", weaponGrip: held)
        s.dedicatedIdle = true
        s.walk = "walk_h031"
        s.run = "run_h031"
        s.casts = ["cast_s1_h031", "cast_s2_h031", "cast_ult_h031"]
        return s
    }()

    /// H028 ザイル: 専用の収録（H028MotionClips.json、docs/H028_MOTION.md）。低い半身の構え・低い歩行と前傾の走行・
    /// 3 段の通常攻撃（袈裟 → 返し → 低い薙ぎ）。スキルの詠唱も専用のクリップ（環剣の一回し・断空突進・三連断空）。
    private static let zail: HeroMotionSet = {
        var s = make(["sword_slash_a_h028", "sword_slash_b_h028", "sword_slash_c_h028"], idle: "idle_h028",
                     death: "death_forward", victory: "victory_cheer")
        s.dedicatedIdle = true
        s.stateBlend = 0.18
        s.walk = "walk_h028"
        s.run = "run_h028"
        s.casts = ["sword_whirl_h028", "dash_charge_h028", "sword_triple_h028"]
        return s
    }()

    /// H032 ディアス: 拳の構えの待機・構えたままの歩行・前傾の走り・左ジャブ → 右ストレート（3 発目の円撃は
    /// Motion_H032.empoweredAttack の全身のモーション）・スキル（S1 の 3 連打・S2 の突進 / 致命の一撃・奥義の溜め突き）。
    private static let dyrroth: HeroMotionSet = {
        // 刃の輪は前腕に沿う縦の刃（SkinnedHeroModel.forearmBlade）。正面・俯瞰からは縁だけが見え、顎の前の構えでも
        // 顔・頭を覆わない
        var s = make(["punch_jab_l_h032", "punch_cross_r_h032"], idle: "idle_h032", death: "death_forward",
                     offhandGrip: HeroMotionSet.fistGrip)
        s.gripOnForeArm = true
        s.castsFromStart = true
        // 突進・飛びかかりの間は脚もクリップ（走る脚に戻さない）
        s.castLocksLegs = [false, true, false]
        s.dedicatedIdle = true
        s.walk = "walk_h032"
        s.run = "run_h032"
        s.casts = ["punch_s1_h032", "dash_s2_h032", "punch_ult_h032"]
        s.stageCasts = [nil, "punch_s2_strike_h032", nil]
        return s
    }()

    /// H029 ボルグの専用の収録（H029MotionClips.json、docs/H029_MOTION.md）。待機・歩行・走行・通常攻撃・スキルの詠唱
    /// （打撃は Motion_H029.clipStrike = KitTimes。S2 の再使用は段のクリップ、突進の間は脚もクリップ）。
    /// 槌は手の区間に持たせ（fistGrip: 柄 = 親指の側、打撃面 = 前腕の向き）、盾は前腕に付けた向き
    /// （盾の上 +Y → 親指の側 -Z、盾の面 -Z → 手の -X = 前腕を胸の前で横にした時の正面）。
    static let borgShieldGrip = simd_quatf(simd_float3x3(columns: (SIMD3<Float>(0, -1, 0), SIMD3<Float>(0, 0, -1), SIMD3<Float>(1, 0, 0))))
    private static let borg: HeroMotionSet = {
        var s = make(["maul_smash_h029"], idle: "idle_h029", offhandGrip: borgShieldGrip)
        s.dedicatedIdle = true
        s.dedicatedAttack = true
        s.stateBlend = 0.2
        s.walk = "walk_h029"
        s.run = "run_h029"
        s.casts = ["maul_wave_h029", "shield_charge_h029", "maul_sanctuary_h029"]
        s.stageCasts = [nil, "maul_upswing_h029", nil]
        s.castLocksLegs = [false, true, false]
        return s
    }()

    /// H001〜H034: 通常攻撃（順に繰り返す）・待機・死亡・勝利。
    static let table: [String: HeroMotionSet] = [
        // 広刃剣 + 城門盾（Vanguard・近接）
        "H001": make(["sword_combo_1", "sword_combo_2", "sword_combo_3"],
                     idle: "combat_idle"),
        // 星の細剣 + 竪琴弓（Duelist・近接）
        "H002": make(["thrust", "sword_slash_r", "sword_combo2_b"],
                     idle: "ready_idle",
                     death: "death_forward", victory: "victory_cheer"),
        // 灰刃の弓（Ranger・遠隔。弓は左手の副手）
        "H003": make(["bow_shot", "bow_shot_b"], idle: "idle_b", death: "death_forward", idleWeaponL: bowIdle),
        // 潮の杖（Arcanist・遠隔）
        "H004": make(["cast_point", "cast_a"], idle: "idle_b", victory: "victory_cheer", weaponGrip: held),
        // 黒雷の槍（Support・遠隔: 投げ・指し示し）
        "H005": make(["javelin_throw", "cast_point"], idle: "idle_b", weaponGrip: held, idleWeaponR: spearIdle),
        // 三日月の短刀 + 月の灯籠（Assassin・近接）
        "H006": make(["dual_combo_c", "sword_slash_r"], idle: "ready_idle", death: "death_forward"),
        // 岩の籠手（Vanguard・拳）
        "H007": make(["punch_a", "punch_a2", "punch_b", "hook_l"], idle: "ready_idle"),
        // 風の旗槍（Duelist・近接の突き）
        "H008": make(["thrust", "sword_upward"], idle: "idle_b", death: "death_forward", victory: "victory_cheer", weaponGrip: held,
                     idleWeaponR: spearIdle),
        // 連弩（Ranger・両手）
        "H009": make(["gun_fire"], idle: "idle_b", death: "death_forward", weaponGrip: held),
        // 掌の炎 + 魔導書（Arcanist）
        "H010": make(["cast_throw", "cast_a"], idle: "idle_b", victory: "victory_cheer", weaponGrip: held),
        // 灯火の杖（Support）
        "H011": make(["cast_point", "cast_a"], idle: "idle_b", weaponGrip: held),
        // 硝子の短剣 二刀（Assassin）
        "H012": make(["dual_combo_a", "dual_combo_b", "dual_combo_c"], idle: "ready_idle", death: "death_forward", offhandGrip: HeroMotionSet.fistGrip),
        // 骨の棍棒 + 獣皮の盾（Vanguard）
        "H013": make(["sword_combo2_a", "sword_combo2_b", "sword_slash_l"], idle: "combat_idle"),
        // 霧の刀 + 小太刀（Duelist）
        "H014": make(["dual_combo_a", "dual_combo_b", "dual_combo_c", "dual_combo_d"],
                     idle: "ready_idle", death: "death_forward",
                     offhandGrip: HeroMotionSet.fistGrip),
        // 鐘口の大筒（Ranger・両手）
        // 待機は銃口を前の下へ下ろして持つ（腰だめの -0.75 だと大きな鐘口が正面・見下ろしのどちらからも顔に重なる）
        "H015": make(["gun_fire"], idle: "idle_b", weaponGrip: held, idleWeaponR: -2.2),
        // 環の杖（Arcanist）
        "H016": make(["cast_a", "cast_point"], idle: "idle_b", death: "death_forward", victory: "victory_cheer", weaponGrip: held),
        // 深淵の香炉（Support・吊るす）
        "H017": make(["cast_throw", "cast_point"], idle: "idle_b", weaponGrip: held),
        // 花弁の双刃（Assassin）
        "H018": make(["dual_combo_c", "dual_combo_d", "dual_combo_a"], idle: "ready_idle", death: "death_forward", victory: "victory_cheer", offhandGrip: HeroMotionSet.fistGrip),
        // 攻城槌（Vanguard・両手の重い振り）
        "H019": make(["overhead_2h", "axe_chop"], idle: "idle_b"),
        // 光矢の刃 + 光の弓（Duelist）
        "H020": make(["sword_slash_r", "sword_combo2_a", "sword_slash_l"], idle: "ready_idle", death: "death_forward", victory: "victory_cheer",
                     idleWeaponL: bowIdle),
        // 長銃（Ranger・両手）
        "H021": make(["gun_fire"], idle: "idle_b", weaponGrip: held),
        // 蒼い爪（Arcanist・遠隔: 爪を振って放つ）
        "H022": make(["hook_l", "cast_throw"], idle: "ready_idle", death: "death_forward", victory: "victory_cheer"),
        // 雷の騎槍（Support・遠隔: 投げ・指し示し）
        "H023": make(["javelin_throw", "cast_point"], idle: "idle_b", weaponGrip: held, idleWeaponR: spearIdle),
        // 夢の針 二刀（Assassin）
        "H024": make(["dual_combo_b", "dual_combo_d", "thrust"], idle: "ready_idle", death: "death_forward", victory: "victory_cheer", offhandGrip: HeroMotionSet.fistGrip),
        // 三日月の長弓（Ranger・遠隔。弓は左手の副手）
        "H025": lumina,
        // 右手の上の球電（Arcanist・遠隔: 杖は持たず、指し示し・払い）
        "H026": make(["cast_a", "cast_point", "cast_throw"], idle: "ready_idle", victory: "victory_cheer", weaponGrip: held),
        // 竜牙の長槍（Duelist・近接の突き）
        "H027": jarld,
        // 光刃の長剣（Assassin・近接の連斬り）
        "H028": zail,
        // 聖槌 + 大盾（Support・近接の片手振り）。専用の収録（borg）が Motion_H029 の全身の手続きの通常攻撃より優先する
        "H029": borg,
        // 星砲（Ranger・遠隔の両手持ち）
        "H030": make(["gun_fire"], idle: "ready_idle", death: "death_forward", victory: "victory_cheer", weaponGrip: held),
        // 氷華の右手（Arcanist・遠隔: 杖は持たず手から放つ・指し示し）
        "H031": aurora,
        // 両手首の刃の輪（Duelist・近接の左右交互の連撃）。専用の収録（H032MotionClips.json、docs/H032_MOTION.md）
        "H032": dyrroth,
        // 魔狩りの大剣（Assassin・近接の片手の連斬り。アルーカードは巨大な剣を片手で振る）。左手を柄へ添える両手の振り
        // （overhead_2h・sword_upward）や左手も大きく動く溜め斬り（sword_charged）ではなく、右手で振る剣のクリップ
        "H033": vald,
        // 鎖鉤（Support・近接の叩きつけ）。専用の収録（dedicatedAttack）が Motion_H034.attacks より先
        "H034": gorm,
    ]
}
