import Foundation

// 担当: キット（読み取りだけの公開）。描画のモーション（App/Battle/Heroes/HeroSkillMotions・Motion_H0xx）が、打撃のキーを
// sim の判定の時刻へ置くための時間の定数。値はキットの Tune そのもの（ここで決めない・変えない）。sim の時刻を変えると、
// モーションの打撃のキーも一緒に動く（docs/vfx/H0xx.md「モーション（打撃の時刻）」）。

public enum KitMotionTimings {
    /// H029 ボルグ（Tigreal）。時刻は発動（指を離した tick）からの秒。
    public enum Borg {
        /// スキル1: 1 回目の衝撃波（槌が地を打つ）・回の間隔・回数。
        public static let waveFirstDelay = Kit_H029.Tune.waveFirstDelay
        public static let waveInterval = Kit_H029.Tune.waveInterval
        public static let waveCount = Kit_H029.Tune.waveCount
        /// スキル2: 突進の所要（最大の距離 ÷ 速さ。壁・敵の押し運びで短くなることはある）。
        public static let dashDuration = Kit_H029.Tune.dashRange / Kit_H029.Tune.dashSpeed
        /// スキル2 の再使用: 指を離してから打ち上げ（ダメージ・ノックアップ）まで。
        public static let smashDelay = Kit_H029.Tune.smashDelay
        public static let smashAirborne = Kit_H029.Tune.smashAirborne
        /// アルティメット: 引き寄せの所要・前半（CC で中断できる）・崩落（ダメージ）。
        public static let ultPullTime = Kit_H029.Tune.ultPullTime
        public static let ultGather = Kit_H029.Tune.ultGather
        public static let ultDetonate = Kit_H029.Tune.ultTotal
    }

    /// H034 ゴルム（Franco）。時刻は発動からの秒（hookHold / hookPull は鉤の命中から）。
    public enum Golm {
        /// スキル1: 振りかぶり（発動 → 鉤が飛び出す）・鉤の速さ（sim の単位 / 秒）・射程・命中から引き寄せまで・引き寄せの所要。
        public static let hookDelay = Kit_H034.Tune.hookDelay
        public static let hookSpeed = Kit_H034.Tune.hookSpeed
        public static let hookRange = Kit_H034.Tune.hookRange
        public static let hookHold = Kit_H034.Tune.hookHold
        public static let hookPull = Kit_H034.Tune.hookPull
        /// スキル2: 叩きつけ（ダメージ）。
        public static let shockDelay = Kit_H034.Tune.shockDelay
        /// アルティメット: 掴み（1 撃目）・連撃の間隔・回数・拘束の長さ（掴みから）。
        public static let ultDelay = Kit_H034.Tune.ultDelay
        /// 掴みから 1 撃目まで（0 = 掴んだ瞬間）。k 撃目（0 始まり）= ultDelay + ultFirst + ultInterval × k。
        public static let ultFirst = Kit_H034.Tune.ultFirst
        public static let ultInterval = Kit_H034.Tune.ultInterval
        public static let ultHits = Kit_H034.Tune.ultHits
        public static let ultSuppress = Kit_H034.Tune.ultSuppress
    }
}
