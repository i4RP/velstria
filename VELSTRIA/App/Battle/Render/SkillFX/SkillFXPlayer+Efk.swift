import Foundation
import VelstriaCore

// 担当: battle-renderer（スキル演出）。段の合図として重ねる Effekseer の効果（FXElement.efk）の中継。
// SkillFXPlayer は他の合図と同じ予定表（遅れ・繰り返し・画質・1 回の再生の上限・予約の上限）で発火し、位置・向き・追従の主体を
// ここへ渡すだけ。再生は EffekseerDirector.playStacked（BattleWorld.attach(effekseer:) が sink を設定）。
// 効果のファイル（Effects/Effekseer/Kit/<name>.efk）は試合のヒーローの分だけ読み込み幕の裏で読む（EffekseerOverlay.loadBundledEffects）。
// Effekseer が無い環境（Metal 無し）では sink が無いので何も出さない（他の合図はそのまま）。

@MainActor
final class FXEfkRelay {
    /// 再生する先（効果・位置・向き（yaw）・追従の主体・主体からのずれ）。
    var sink: ((FXEfk, SIMD3<Float>, Float, SkillFXPlayer.Follow?, SIMD3<Float>) -> Void)?
    /// 試合のレシピが使う効果の名前（prewarm で集める。読み込み済みかの確かめ・テスト用）。
    private(set) var names: Set<String> = []
    /// 発火した数（sink が無くて捨てた分を含む。テスト・計測用）。
    private(set) var fired = 0

    func note(_ x: FXEfk) { names.insert(x.name) }

    func fire(_ x: FXEfk, at p: SIMD3<Float>, yaw: Float, follow: SkillFXPlayer.Follow?, offset: SIMD3<Float>) {
        fired += 1
        sink?(x, p, yaw, follow, offset)
    }
}
