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
    var idle: String?
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
    let idle: Int?
    let run: Int?
    let death: Int?
    let victory: Int?
    let stunned: Int?
    let channel: Int?
    let weaponGrip: simd_quatf?
    let offhandGrip: simd_quatf?

    /// どのクリップも見つからなければ nil（重ねる層を持たず、手続きと完全に同じ）。
    init?(set: HeroMotionSet, library: HeroMotionLibrary) {
        func find(_ name: String?) -> Int? { name.flatMap { library.index(of: $0) } }
        attacks = set.attacks.compactMap { library.index(of: $0) }
        casts = (0..<3).map { $0 < set.casts.count ? find(set.casts[$0]) : nil }
        idle = find(set.idle)
        run = find(set.run)
        death = find(set.death)
        victory = find(set.victory)
        stunned = find(set.stunned)
        channel = find(set.channel)
        let any = !attacks.isEmpty || casts.contains { $0 != nil }
            || [idle, run, death, victory, stunned, channel].contains { $0 != nil }
        guard any else { return nil }
        self.library = library
        attackMask = set.attackMask
        weaponGrip = set.weaponGrip
        offhandGrip = set.offhandGrip
    }

    /// スキル枠 → casts の添字（パッシブは Skill1 と同じ。HeroAnimator.castIndex と同じ対応）。
    func cast(_ index: Int) -> Int? { index >= 0 && index < casts.count ? casts[index] : nil }
}

enum HeroMotionSets {
    /// heroID の割り当て（未知の ID は nil = 手続きのみ）。
    static func set(heroID: String) -> HeroMotionSet? { table[heroID] }

    private static func make(_ attacks: [String], idle: String? = nil, death: String = "death_back",
                             victory: String = "victory_pump", mask: HeroClipMask = .full,
                             weaponGrip: simd_quatf? = HeroMotionSet.fistGrip,
                             offhandGrip: simd_quatf? = nil) -> HeroMotionSet {
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
        return s
    }

    /// 杖・槍・銃など、向きを胴に対して保つ武器。
    private static let held: simd_quatf? = nil

    /// H001〜H024: 通常攻撃（順に繰り返す）・待機・死亡・勝利。
    static let table: [String: HeroMotionSet] = [
        // 広刃剣 + 城門盾（Vanguard・近接）
        "H001": make(["sword_combo_1", "sword_combo_2", "sword_combo_3"],
                     idle: "combat_idle"),
        // 星の細剣 + 竪琴弓（Duelist・近接）
        "H002": make(["thrust", "sword_slash_r", "sword_combo2_b"],
                     idle: "ready_idle",
                     death: "death_forward", victory: "victory_cheer"),
        // 灰刃の弓（Ranger・遠隔。弓は左手の副手）
        "H003": make(["bow_shot", "bow_shot_b"], idle: "idle_b", death: "death_forward"),
        // 潮の杖（Arcanist・遠隔）
        "H004": make(["cast_point", "cast_a"], idle: "idle_b", victory: "victory_cheer", weaponGrip: held),
        // 黒雷の槍（Support・遠隔: 投げ・指し示し）
        "H005": make(["javelin_throw", "cast_point"], idle: "idle_b", weaponGrip: held),
        // 三日月の短刀 + 月の灯籠（Assassin・近接）
        "H006": make(["dual_combo_c", "sword_slash_r"], idle: "ready_idle", death: "death_forward"),
        // 岩の籠手（Vanguard・拳）
        "H007": make(["punch_a", "punch_a2", "punch_b", "hook_l"], idle: "ready_idle"),
        // 風の旗槍（Duelist・近接の突き）
        "H008": make(["thrust", "sword_upward"], idle: "idle_b", death: "death_forward", victory: "victory_cheer", weaponGrip: held),
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
        "H015": make(["gun_fire"], idle: "idle_b", weaponGrip: held),
        // 環の杖（Arcanist）
        "H016": make(["cast_a", "cast_point"], idle: "idle_b", death: "death_forward", victory: "victory_cheer", weaponGrip: held),
        // 深淵の香炉（Support・吊るす）
        "H017": make(["cast_throw", "cast_point"], idle: "idle_b", weaponGrip: held),
        // 花弁の双刃（Assassin）
        "H018": make(["dual_combo_c", "dual_combo_d", "dual_combo_a"], idle: "ready_idle", death: "death_forward", victory: "victory_cheer", offhandGrip: HeroMotionSet.fistGrip),
        // 攻城槌（Vanguard・両手の重い振り）
        "H019": make(["overhead_2h", "axe_chop"], idle: "idle_b"),
        // 光矢の刃 + 光の弓（Duelist）
        "H020": make(["sword_slash_r", "sword_combo2_a", "sword_slash_l"], idle: "ready_idle", death: "death_forward", victory: "victory_cheer"),
        // 長銃（Ranger・両手）
        "H021": make(["gun_fire"], idle: "idle_b", weaponGrip: held),
        // 蒼い爪（Arcanist・遠隔: 爪を振って放つ）
        "H022": make(["hook_l", "cast_throw"], idle: "ready_idle", death: "death_forward", victory: "victory_cheer"),
        // 雷の騎槍（Support・遠隔: 投げ・指し示し）
        "H023": make(["javelin_throw", "cast_point"], idle: "idle_b", weaponGrip: held),
        // 夢の針 二刀（Assassin）
        "H024": make(["dual_combo_b", "dual_combo_d", "thrust"], idle: "ready_idle", death: "death_forward", victory: "victory_cheer", offhandGrip: HeroMotionSet.fistGrip),
    ]
}
