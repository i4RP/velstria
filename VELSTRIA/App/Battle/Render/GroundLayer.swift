import Foundation

// 担当: battle-renderer。地面付近に重ねる平面の高さ（m）の一覧。
// 平面を同じ高さに置くと、メッシュ毎に三角形分割が違うため深度の丸め誤差で勝ち負けが画素毎に入れ替わり、
// カメラが動くたびに模様が変わる（Z-fighting のちらつき）。地面付近の高さは必ずここから取る。
//
// 規則:
// 1. xz で重なる不透明な静的平面同士は 4 mm 以上離す（深度 32bit・near 1 m で 25 m 先の分解能は約 0.04 mm）。
// 2. 動的な足元表示（影・リング・ゾーン・照準）は半透明かつ深度を書かず、静的平面の最上段より上に置く。
//    それら同士の前後は高さではなく OverlayOrder（ModelSortGroup の順）で決める。
// 3. 地図全体を覆う半透明の板（細部・水面・霧）も深度を書かず、OverlayOrder で順序を固定する。

enum GroundLayer {
    /// 地図外周の森の地面（地面の下）。
    static let outerGround: Float = -0.04
    static let ground: Float = 0
    /// 砂粒・草の細部タイル（半透明・深度書き込みなし）。石畳より下なので石畳の目地にだけ見える。
    static let detail: Float = 0.004
    /// 本拠点広場の石畳（不透明・ライティングあり）。
    static let paving: Float = 0.010
    /// 泉の紋章の輪・タワー台座の輪・ボスの巣の輪（互いに xz で重ならない）。
    static let marking: Float = 0.014
    /// 泉の八芒星の線・ボスの巣の星（輪と交差するので一段上）。
    static let markingLine: Float = 0.018
    /// Core 周囲の輪（泉の紋章・タワーの輪と交差するので最上段）。
    static let markingTop: Float = 0.022
    /// ボスの巣の星の厚み（markingLine を中心に上下へ半分ずつ）。
    static let bossStarThickness: Float = 0.01
    /// 静的な地面の印の最上面（Core の輪とボスの巣の星の上面の高い方）。
    static let staticTop: Float = max(markingTop, markingLine + bossStarThickness / 2)

    /// 河川の水面（半透明・深度書き込みなし）。
    static let water: Float = 0.026
    /// ヒーローの丸影（半透明・深度書き込みなし）。
    static let unitShadow: Float = 0.028
    /// ヒーローのチームリング・正面の矢印。
    static let teamMarker: Float = 0.032
    /// 戦闘中の選択リング（UnitVisuals）。
    static let unitRing: Float = 0.036
    /// 帰還・奥義の足元の輪（HeroModel.groundRing）・帰還リング。
    static let castRing: Float = 0.040
    /// 鈍足の輪（不透明の発光。半透明の表示とは描画パスが違うので高さだけ他と重ならなければよい）。
    static let statusRing: Float = 0.042
    /// 地面ゾーンの塗り（予告の進捗 +0.004、縁 +0.008）。
    static let zone: Float = 0.045
    /// 構造物の射程リング。
    static let rangeRing: Float = 0.050
    /// 演出の広がる輪。
    static let vfxRing: Float = 0.060
    /// 照準の基準高さ。
    static let aim: Float = 0.070
    /// 戦場の霧の板。
    static let fog: Float = 0.10
    /// 環境パーティクル（河川のきらめき）の放出面。霧の板より上に置き、半透明の板との前後を深度で決める
    /// （霧の板と同じ高さ付近だと粒子が板を出入りして明滅する）。平面ではないので overlays には含めない。
    static let ambient: Float = 0.14

    /// 不透明な静的平面（xz で重なりうる順に下から）。テストで間隔を検証する。
    static let opaqueStack: [Float] = [ground, paving, marking, markingLine, markingTop]
    /// 動的な足元表示（静的平面より上にあること）。
    static let overlays: [Float] = [unitShadow, teamMarker, unitRing, castRing, statusRing, zone, rangeRing, vfxRing, aim]
}
