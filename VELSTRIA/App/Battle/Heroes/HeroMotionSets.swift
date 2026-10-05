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
    /// スキル詠唱（Skill1, Skill2, Skill3, Ultimate の順。nil = 手続き）。
    var casts: [String?] = [nil, nil, nil, nil]
    var idle: String?
    var run: String?
    var death: String?
    var victory: String?
    var stunned: String?
    var channel: String?
    /// 手の区間に対する武器（Prop 空間: 握りが原点・+Y へ伸びる）の向き。既定は +Y → 手の区間の正面 -Z
    /// （腕を下ろすと刃先が前、腕を前へ出すと刃先が上 = 拳で握った向き）。
    var weaponGrip: simd_quatf = HeroMotionSet.fistGrip
    var offhandGrip: simd_quatf = HeroMotionSet.fistGrip

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
    /// Skill1, Skill2, Skill3, Ultimate。
    let casts: [Int?]
    let idle: Int?
    let run: Int?
    let death: Int?
    let victory: Int?
    let stunned: Int?
    let channel: Int?
    let weaponGrip: simd_quatf
    let offhandGrip: simd_quatf

    /// どのクリップも見つからなければ nil（重ねる層を持たず、手続きと完全に同じ）。
    init?(set: HeroMotionSet, library: HeroMotionLibrary) {
        func find(_ name: String?) -> Int? { name.flatMap { library.index(of: $0) } }
        attacks = set.attacks.compactMap { library.index(of: $0) }
        casts = (0..<4).map { $0 < set.casts.count ? find(set.casts[$0]) : nil }
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

    // 共通の部品
    private static let swordCombo = ["sword_combo_1", "sword_combo_2", "sword_combo_3"]
    private static let dualCombo = ["dual_combo_a", "dual_combo_b", "dual_combo_c", "dual_combo_d"]

    private static func make(_ attacks: [String], casts: [String?], death: String = "death_back",
                             victory: String = "victory_pump", mask: HeroClipMask = .full,
                             weaponGrip: simd_quatf = HeroMotionSet.fistGrip,
                             offhandGrip: simd_quatf = HeroMotionSet.fistGrip) -> HeroMotionSet {
        var s = HeroMotionSet()
        s.attacks = attacks
        s.attackMask = mask
        s.casts = casts
        s.death = death
        s.victory = victory
        // 帰還・詠唱の片膝立ち（非ループなら膝をついて止まる）。待機・移動は手続きのまま（QA 後に決める）
        s.channel = "kneel"
        s.weaponGrip = weaponGrip
        s.offhandGrip = offhandGrip
        return s
    }

    /// 暫定表（H001〜H024）。casts は Skill1, Skill2, Skill3, Ultimate。
    static let table: [String: HeroMotionSet] = [
        // 広刃剣 + 城門盾（近接）
        "H001": make(swordCombo, casts: ["sword_charged", "sword_slash_r", "sword_upward", "sword_judgment"]),
        // 星の細剣（突き）+ 竪琴弓
        "H002": make(["thrust", "sword_slash_l", "sword_slash_r"], casts: ["sword_charged", "dodge_spin", "bow_shot", "bow_draw_back"],
                     death: "death_forward"),
        // 弓（左手）
        "H003": make(["bow_shot", "bow_shot_b"], casts: ["bow_shot_b", "dodge_spin", "bow_draw_back", "bow_draw_back"],
                     death: "death_forward", victory: "victory_cheer"),
        // 潮の杖
        "H004": make(["cast_a", "cast_b"], casts: ["cast_push", "cast_c", "cast_throw", "cast_charged"],
                     victory: "victory_cheer"),
        // 黒雷の槍（遠隔: 投擲・指し示し）
        "H005": make(["javelin_throw", "cast_point"], casts: ["cast_point", "cast_push", "javelin_throw", "cast_charged"],
                     victory: "victory_cheer"),
        // 三日月の短刀 + 月の灯籠
        "H006": make(["dual_combo_a", "dual_combo_b"], casts: ["dual_spin", "dodge_spin", "dual_combo_c", "dual_combo_d"],
                     death: "death_forward"),
        // 岩の籠手（拳）
        "H007": make(["punch_a", "punch_b", "hook_l", "uppercut_r"], casts: ["double_punch", "leap_punch", "uppercut_r", "ground_slam"]),
        // 風の旗槍（近接の突き）
        "H008": make(["thrust", "sword_slash_r"], casts: ["sword_upward", "dodge_spin", "axe_spin", "jump_attack"],
                     death: "death_forward"),
        // 連弩
        "H009": make(["gun_fire"], casts: ["gun_kneel_shot", "dodge_spin", "gun_fire", "gun_kneel_shot"],
                     death: "death_forward", weaponGrip: HeroMotionSet.pistolGrip),
        // 掌の炎 + 魔導書
        "H010": make(["cast_throw", "cast_a"], casts: ["cast_throw", "cast_push", "cast_b", "cast_charged"],
                     victory: "victory_cheer"),
        // 灯火の杖（支援）
        "H011": make(["cast_a", "cast_b"], casts: ["cast_point", "cast_push", "cast_c", "jump_attack"]),
        // 硝子の短剣 二刀
        "H012": make(["dual_combo_a", "dual_combo_b", "dual_combo_c"], casts: ["dual_combo_d", "dodge_spin", "dual_spin", "cast_charged"],
                     death: "death_forward"),
        // 骨の棍棒 + 獣皮の盾
        "H013": make(["axe_chop", "sword_slash_r", "sword_combo_2"], casts: ["sword_charged", "axe_spin", "ground_slam", "jump_attack"]),
        // 霧の刀 + 小太刀
        "H014": make(dualCombo, casts: ["sword_slash_l", "dodge_spin", "dual_spin", "sword_judgment"], death: "death_forward"),
        // 鐘口の大筒
        "H015": make(["gun_fire"], casts: ["gun_fire", "dodge_spin", "gun_kneel_shot", "gun_kneel_shot"],
                     weaponGrip: HeroMotionSet.pistolGrip),
        // 環の杖
        "H016": make(["cast_a", "cast_c"], casts: ["cast_point", "cast_b", "cast_push", "cast_charged"],
                     death: "death_forward", victory: "victory_cheer"),
        // 深淵の香炉灯
        "H017": make(["cast_throw", "cast_b"], casts: ["cast_throw", "cast_point", "cast_push", "cast_charged"],
                     victory: "victory_cheer"),
        // 花弁の双刃
        "H018": make(["dual_combo_a", "dual_combo_c"], casts: ["dual_combo_b", "dodge_spin", "dual_spin", "dual_combo_d"],
                     death: "death_forward", victory: "victory_cheer"),
        // 攻城槌（両手の重い振り）
        "H019": make(["hammer_swing", "axe_chop"], casts: ["overhead_2h", "reaping", "axe_spin", "ground_slam"]),
        // 光矢の刃 + 光の弓
        "H020": make(["sword_slash_r", "sword_slash_l", "sword_combo_3"], casts: ["sword_upward", "dodge_spin", "bow_shot", "bow_draw_back"],
                     death: "death_forward", victory: "victory_cheer"),
        // 長銃
        "H021": make(["gun_fire"], casts: ["gun_kneel_shot", "dodge_spin", "gun_fire", "gun_kneel_shot"],
                     weaponGrip: HeroMotionSet.pistolGrip),
        // 蒼い爪（遠隔: 投げる・鉤突き）
        "H022": make(["cast_throw", "hook_l"], casts: ["cast_throw", "dodge_spin", "dual_spin", "cast_charged"],
                     death: "death_forward", victory: "victory_cheer"),
        // 雷の騎槍（遠隔: 投擲・指し示し）
        "H023": make(["javelin_throw", "cast_point"], casts: ["thrust", "cast_push", "javelin_throw", "jump_attack"]),
        // 針の双刃
        "H024": make(["dual_combo_b", "dual_combo_d"], casts: ["dual_combo_a", "dodge_spin", "dual_spin", "cast_c"],
                     death: "death_forward", victory: "victory_cheer"),
    ]
}
