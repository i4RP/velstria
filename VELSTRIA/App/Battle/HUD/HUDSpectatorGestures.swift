import SwiftUI
import VelstriaCore

// 担当: battle-hud（観戦カメラ）。観戦者の 3D 画面の操作（ARView は入力を受けないので、HUD の最下層に重ねる）:
// - ドラッグ: 自由カメラ（指の下の地面が指に付いてくる。離すと少し滑って止まる）
// - ピンチ: 倍率（観戦者の広い範囲。自由カメラではピンチの中心の地面を動かさない）
// - ダブルタップ: 自動カメラが有効なら自動カメラへ戻す、無効なら直前に追っていたヒーローへ戻す（倍率も既定へ）
// 手動の操作は自動カメラへ知らせ、しばらく控えさせる。カメラは回転しないので 画面の右 = sim +x、画面の上 = sim +y。
// 毎フレーム変わる値（倍率の上書き・注視点）は非監視の場所へ書き、HUD 全体を描き直させない。

/// 観戦カメラの操作の計算（純関数。単体テスト対象）。
@MainActor
enum SpectatorCameraMath {
    /// HUD 座標の点 → 正規化した画面座標（x = -1 左 … 1 右、y = -1 下 … 1 上）。
    static func ndc(_ p: CGPoint, size: CGSize) -> SIMD2<Float> {
        guard size.width > 0, size.height > 0 else { return .zero }
        return SIMD2(Float(p.x / size.width * 2 - 1), Float(1 - p.y / size.height * 2))
    }

    /// 画面の点が指す地面の点の、注視点からのずれ（sim 座標）。倍率 zoom のカメラ。
    static func groundOffset(_ p: CGPoint, size: CGSize, zoom: Double) -> Vec2? {
        guard size.width > 0, size.height > 0,
              let g = CameraRig.groundOffsetPerDistance(ndc: ndc(p, size: size), aspectRatio: Float(size.width / size.height))
        else { return nil }
        let d = Double(CameraRig.distance(forZoom: zoom, range: CameraRig.spectatorZoomRange))
        return Vec2(Double(g.x) * d * Balance.unitsPerMeter, -Double(g.y) * d * Balance.unitsPerMeter)
    }

    /// パン: 開始時の注視点（sim）と、指の開始点・現在点（HUD 座標）から新しい注視点。開始点の下にあった地面が指の下に来る。
    static func panFocus(startFocus: Vec2, from a: CGPoint, to b: CGPoint, size: CGSize, zoom: Double) -> Vec2 {
        guard let ga = groundOffset(a, size: size, zoom: zoom), let gb = groundOffset(b, size: size, zoom: zoom) else {
            return startFocus
        }
        return clamp(startFocus + ga - gb, zoom: zoom)
    }

    /// ピンチ: 開始時の倍率と拡大率（> 1 で寄る）→ 新しい倍率（観戦者の範囲）。
    static func pinchZoom(startZoom: Double, magnification: CGFloat) -> Double {
        let m = magnification.isFinite && magnification > 0.01 ? Double(magnification) : 1
        let r = CameraRig.spectatorZoomRange
        return min(max(startZoom / m, r.lowerBound), r.upperBound)
    }

    /// ピンチの中心（HUD 座標）の下の地面を動かさない注視点（自由カメラ）。
    static func pinchFocus(startFocus: Vec2, anchor: CGPoint, size: CGSize, fromZoom: Double, toZoom: Double) -> Vec2 {
        guard let a = groundOffset(anchor, size: size, zoom: fromZoom),
              let b = groundOffset(anchor, size: size, zoom: toZoom) else { return startFocus }
        return clamp(startFocus + a - b, zoom: toZoom)
    }

    /// 注視点をカメラの地図内クランプ（倍率に応じた余白）へ合わせる（地図の端の先へ指を動かしても、戻す時に遊びが出ない）。
    static func clamp(_ focus: Vec2, zoom: Double) -> Vec2 {
        let world = SIMD2(Float(focus.x / Balance.unitsPerMeter), Float(-focus.y / Balance.unitsPerMeter))
        let c = CameraRig.clampFocus(world, mapMeters: MapScene.mapMeters, zoom: zoom)
        return Vec2(Double(c.x) * Balance.unitsPerMeter, -Double(c.y) * Balance.unitsPerMeter)
    }

    /// 離した時の滑り: 予測された終点までの移動を画面の短辺の 0.4 倍までに抑える。
    static func flingEnd(from location: CGPoint, predicted: CGPoint, size: CGSize) -> CGPoint {
        let dx = predicted.x - location.x, dy = predicted.y - location.y
        let len = (dx * dx + dy * dy).squareRoot()
        let cap = min(size.width, size.height) * 0.4
        guard len > cap, len > 0 else { return predicted }
        return CGPoint(x: location.x + dx / len * cap, y: location.y + dy / len * cap)
    }
}

/// 観戦者の 3D 画面の操作レイヤー（HUD の最下層。上の操作部品が先に触れる）。
struct HUDSpectatorGestureLayer: View {
    let model: HUDModel
    let layout: HUDLayout

    @State private var pan: PanAnchor?
    @State private var pinch: PinchAnchor?

    private struct PanAnchor {
        var focus: Vec2
        var start: CGPoint
        var zoom: Double
    }

    private struct PinchAnchor {
        var zoom: Double
        var focus: Vec2
        var anchor: CGPoint
        var free: Bool
    }

    private var size: CGSize { CGSize(width: layout.width, height: layout.height) }
    private var controller: BattleController { model.controller }
    private var link: SpectatorCameraLink { SpectatorCameraLink.link(for: model.controller) }

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { panChanged($0) }
                    .onEnded { panEnded($0) }
            )
            .simultaneousGesture(
                MagnifyGesture(minimumScaleDelta: 0.02)
                    .onChanged { pinchChanged($0) }
                    .onEnded { _ in pinchEnded() }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded { returnToFollow() })
            .accessibilityElement()
            .accessibilityLabel(L("観戦カメラ", "Spectator camera"))
            .accessibilityHint(L("ドラッグで移動、ピンチで拡大・縮小、ダブルタップで追従に戻ります",
                                 "Drag to pan, pinch to zoom, double-tap to follow again"))
            .accessibilityAction(named: L("寄る", "Zoom in")) { stepZoom(by: 1 / 1.25) }
            .accessibilityAction(named: L("引く", "Zoom out")) { stepZoom(by: 1.25) }
            .accessibilityAction(named: L("追従に戻る", "Follow again")) { returnToFollow() }
            .accessibilityIdentifier("spectate_camera")
    }

    // MARK: パン

    private func panChanged(_ value: DragGesture.Value) {
        // ピンチ中の 2 本指のドラッグは移動に使わない（ピンチが終わったら指の位置から取り直す）
        guard pinch == nil else {
            pan = nil
            return
        }
        let link = link
        if pan == nil {
            if case .free = controller.cameraMode {} else { link.lastFollowedID = controller.presentationFocusID }
            pan = PanAnchor(focus: currentFocus(link), start: value.location, zoom: link.renderedZoom)
            link.isPanning = true
            link.noteManualCameraInput()
        }
        guard let pan else { return }
        let focus = SpectatorCameraMath.panFocus(startFocus: pan.focus, from: pan.start, to: value.location, size: size,
                                                 zoom: pan.zoom)
        model.minimapDragged(to: focus)
    }

    private func panEnded(_ value: DragGesture.Value) {
        defer {
            pan = nil
            link.isPanning = false
        }
        guard let pan, pinch == nil else { return }
        // 離した勢いで少し滑らせる（自由カメラのばねが減速しながら止める）
        let end = SpectatorCameraMath.flingEnd(from: value.location, predicted: value.predictedEndLocation, size: size)
        let focus = SpectatorCameraMath.panFocus(startFocus: pan.focus, from: pan.start, to: end, size: size, zoom: pan.zoom)
        model.minimapDragged(to: focus)
        link.noteManualCameraInput()
    }

    // MARK: ピンチ

    private func pinchChanged(_ value: MagnifyGesture.Value) {
        let link = link
        if pinch == nil {
            // 複数を収める画のピンチは主役の追従に切り替える（倍率は観戦者が決める）
            if case .framing(let ids) = controller.cameraMode, let first = ids.first { model.follow(first) }
            var free = false
            if case .free = controller.cameraMode { free = true }
            let anchor = CGPoint(x: value.startAnchor.x * size.width, y: value.startAnchor.y * size.height)
            pinch = PinchAnchor(zoom: link.renderedZoom, focus: currentFocus(link), anchor: anchor, free: free)
            link.isPinching = true
            link.noteManualCameraInput()
        }
        guard let pinch else { return }
        let zoom = SpectatorCameraMath.pinchZoom(startZoom: pinch.zoom, magnification: value.magnification)
        controller.cameraZoomOverride = zoom
        if pinch.free {
            model.minimapDragged(to: SpectatorCameraMath.pinchFocus(startFocus: pinch.focus, anchor: pinch.anchor, size: size,
                                                                    fromZoom: pinch.zoom, toZoom: zoom))
        }
    }

    private func pinchEnded() {
        pinch = nil
        let link = link
        link.isPinching = false
        link.noteManualCameraInput()
    }

    /// VoiceOver の操作: 一段寄る・引く。
    private func stepZoom(by factor: Double) {
        let link = link
        let r = CameraRig.spectatorZoomRange
        controller.cameraZoomOverride = min(max(link.renderedZoom * factor, r.lowerBound), r.upperBound)
        link.noteManualCameraInput()
    }

    // MARK: 追従に戻る

    /// ダブルタップ: 自動カメラが有効ならすぐ戻す。無効なら直前に追っていたヒーロー（無ければ最初のヒーロー）を追い、倍率も既定へ。
    private func returnToFollow() {
        let link = link
        if controller.spectatorDirectorEnabled, link.resumeDirector() {
            model.selectionFeedback()
            return
        }
        controller.cameraZoomOverride = nil
        let s = controller.state
        let target = link.lastFollowedID.flatMap { s.unit($0) != nil ? $0 : nil }
            ?? s.heroIndices.first.map { s.units[$0].id }
        if let target { model.follow(target) }
        link.noteManualCameraInput()
    }

    /// いま描いている注視点（描画側が書いた値。無ければカメラの地面の範囲の対角線の交点 = 画面の中心）。
    private func currentFocus(_ link: SpectatorCameraLink) -> Vec2 {
        if let f = link.renderedFocus { return f }
        if let c = HUDSpectatorGestureLayer.viewportCenter(controller.renderedCameraViewport) { return c }
        if case .free(let v) = controller.cameraMode { return v }
        let m = controller.ctx.map.size / 2
        return Vec2(m, m)
    }

    /// 地面の範囲（4 隅）の対角線の交点。射影変換は交点を保つので、これが画面の中心の指す地面の点になる。
    static func viewportCenter(_ quad: [Vec2]) -> Vec2? {
        guard quad.count == 4 else { return nil }
        let p = quad[0], r = quad[2] - quad[0]
        let q = quad[1], s = quad[3] - quad[1]
        let denom = r.cross(s)
        guard abs(denom) > 1e-9 else { return nil }
        let t = (q - p).cross(s) / denom
        return p + r * t
    }
}
