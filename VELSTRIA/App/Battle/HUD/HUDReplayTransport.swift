import SwiftUI
import VelstriaCore

// 担当: battle-hud（観戦）。再生バー（オフラインの観戦・リプレイ = controller.isSeekable の時だけ）:
// 一時停止 / 再生（終わっていれば最初から）・速度（0.5×〜8×）・±10 秒（幅があれば ±30 秒とコマ送り）・
// ドラッグできるシークバー（ドラッグ中は位置と時刻を先に見せ、離した所で controller.requestSeek）・
// 年表の印（キル・構造物・大型目標・全滅。有利になった側の色と形、重要度で大きさ）・すぐにシークできる区間の網掛け・
// シーク中の表示・0.1 秒単位の時刻・次の見どころ。
// 右端はリプレイなら最終 tick、AI 同士の観戦なら分かっている所（一度見た所・先に計算した所）まで。
// 再生が終わったら HUDSpectatorEndCard（もう一度見る / 結果へ）を出し、バーはそのまま使える。

struct HUDReplayTransport: View {
    let model: HUDModel
    let layout: HUDSpectatorLayout

    var body: some View {
        let t = model.spectator.transport
        let preview = model.spectator.dragPreviewTick
        HStack(spacing: HUDSpectatorLayout.gap) {
            playPause(t)
            if layout.inlineSpeeds {
                HStack(spacing: HUDSpectatorLayout.speedSpacing) {
                    ForEach(BattleController.spectatorSpeeds, id: \.self) { speed in
                        HUDSpeedButton(model: model, speed: speed)
                    }
                }
            } else {
                HUDSpeedCycleButton(model: model)
            }
            if layout.inlineSkip30 {
                skip(-30, t)
            }
            skip(-10, t)
            timeLabel(preview ?? t.displayTick, emphasized: preview != nil, seeking: t.seekingTo != nil)
            HUDSeekBar(model: model, transport: t, colorblind: model.settings.colorblindMode)
                .frame(width: layout.seekBarWidth)
            Text(HUDStyle.clock(Double(t.endTick) * Balance.dt))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(t.isEndKnown ? 0.7 : 0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: HUDSpectatorLayout.timeLabelWidth, alignment: .leading)
                .accessibilityHidden(true)
            skip(10, t)
            if layout.inlineSkip30 {
                skip(30, t)
            }
            if layout.inlineStep {
                HUDSpectateIconButton(symbol: "forward.frame.fill", label: L("コマ送り", "Step forward"),
                                      identifier: "spectate_step",
                                      enabled: t.isPaused && !t.isEnded && t.seekingTo == nil) { model.spectatorStep() }
            }
            HUDSpectateIconButton(symbol: "forward.end.fill", label: L("次の見どころへ", "Next fight"),
                                  identifier: "spectate_next_fight", enabled: t.nextFightTick != nil) {
                model.spectatorNextFight()
            }
        }
    }

    private func playPause(_ t: HUDTransportSnapshot) -> some View {
        let paused = model.spectatorPaused
        let symbol = t.isEnded ? "arrow.counterclockwise" : (paused ? "play.fill" : "pause.fill")
        let label = t.isEnded ? L("最初から見る", "Watch from the start") : (paused ? L("再生", "Play") : L("一時停止", "Pause"))
        return HUDSpectateIconButton(symbol: symbol, label: label, identifier: "spectate_pause", selected: paused && !t.isEnded) {
            model.spectatorPlayPause()
        }
    }

    private func skip(_ seconds: Int, _ t: HUDTransportSnapshot) -> some View {
        let back = seconds < 0
        let n = abs(seconds)
        let enabled = back ? t.displayTick > 0 : (!t.isEnded && t.displayTick < t.upperBound)
        return HUDSpectateIconButton(symbol: back ? "gobackward.\(n)" : "goforward.\(n)",
                                     label: back ? L("\(n) 秒戻る", "Back \(n) seconds") : L("\(n) 秒進む", "Forward \(n) seconds"),
                                     identifier: back ? "spectate_back\(n)" : "spectate_fwd\(n)", enabled: enabled) {
            model.spectatorSkip(seconds: Double(seconds))
        }
    }

    private func timeLabel(_ tick: Int, emphasized: Bool, seeking: Bool) -> some View {
        ZStack {
            if seeking {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.gold)
                    .accessibilityLabel(L("移動中", "Seeking"))
            } else {
                Text(HUDStyle.preciseClock(Double(tick) * Balance.dt))
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(emphasized ? Theme.gold : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: HUDSpectatorLayout.timeLabelWidth, alignment: .trailing)
    }
}

/// 速度ボタン（0.5×〜8×。UI テストの spectate_speed_2x など）。
struct HUDSpeedButton: View {
    let model: HUDModel
    let speed: Double

    var body: some View {
        let selected = model.controller.speed == speed
        let label = HUDSpectatorState.speedLabel(speed)
        Button { model.setSpeed(speed) } label: {
            Text("\(label)×")
                .font(.system(size: label.count > 1 ? 12 : 14, weight: .heavy, design: .rounded))
                .foregroundStyle(selected ? Color.black : .white)
                .frame(width: HUDSpectatorLayout.button, height: HUDSpectatorLayout.button)
                .background(Circle().fill(selected ? Theme.gold : Color.white.opacity(0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(HUDPressStyle())
        .accessibilityLabel(L("再生速度 \(label) 倍", "Speed \(label)x"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("spectate_speed_\(label)x")
    }
}

/// 狭い画面の速度ボタン（タップで次の速度。選択肢は観戦メニューにもある）。
struct HUDSpeedCycleButton: View {
    let model: HUDModel

    var body: some View {
        let label = HUDSpectatorState.speedLabel(model.controller.speed)
        Button { model.cycleSpectatorSpeed() } label: {
            Text("\(label)×")
                .font(.system(size: label.count > 1 ? 12 : 14, weight: .heavy, design: .rounded))
                .foregroundStyle(.black)
                .frame(width: HUDSpectatorLayout.button, height: HUDSpectatorLayout.button)
                .background(Circle().fill(Theme.gold))
                .contentShape(Circle())
        }
        .buttonStyle(HUDPressStyle())
        .accessibilityLabel(L("再生速度", "Playback speed"))
        .accessibilityValue(L("\(label) 倍", "\(label)x"))
        .accessibilityHint(L("タップで次の速度", "Tap for the next speed"))
        .accessibilityIdentifier("spectate_speed_cycle")
    }
}

/// ドラッグできるシークバー（離した所へシーク。ドラッグ中は位置だけ先に動かす）。
struct HUDSeekBar: View {
    let model: HUDModel
    let transport: HUDTransportSnapshot
    let colorblind: Bool
    @GestureState private var dragging = false

    var body: some View {
        let t = transport
        let spec = model.spectator
        let preview = spec.dragPreviewTick
        GeometryReader { g in
            let w = max(1, g.size.width)
            ZStack(alignment: .topLeading) {
                HUDSeekBarCanvas(markers: spec.markers, transport: t, previewTick: preview, colorblind: colorblind)
                if let preview {
                    let x = HUDSeekBarGeometry.x(forTick: preview, endTick: t.endTick, width: w)
                    Text(HUDStyle.preciseClock(Double(preview) * Balance.dt))
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Theme.gold))
                        .fixedSize()
                        .position(x: min(max(x, 24), w - 24), y: -8)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($dragging) { _, state, _ in state = true }
                    .onChanged { v in
                        spec.dragPreviewTick = HUDSpectatorState.tick(atFraction: Double(v.location.x / w), endTick: t.endTick)
                    }
                    .onEnded { v in
                        let tick = HUDSpectatorState.tick(atFraction: Double(v.location.x / w), endTick: t.endTick)
                        spec.dragPreviewTick = nil
                        model.spectatorSeek(toTick: tick)
                    }
            )
        }
        .onChange(of: dragging) { _, active in
            // 取り消された（onEnded が来ない）ドラッグは位置を戻す
            if !active { spec.dragPreviewTick = nil }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("再生位置", "Replay progress"))
        .accessibilityValue(accessibilityValue(t))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: model.spectatorSkip(seconds: 10)
            case .decrement: model.spectatorSkip(seconds: -10)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("replay_progress")
    }

    private func accessibilityValue(_ t: HUDTransportSnapshot) -> String {
        let now = HUDStyle.clock(Double(t.displayTick) * Balance.dt)
        let end = HUDStyle.clock(Double(t.endTick) * Balance.dt)
        return "\(now) / \(end) (\(Int((t.fraction * 100).rounded()))%)"
    }
}

/// シークバーの座標計算（純粋関数）。
enum HUDSeekBarGeometry {
    static func x(forTick tick: Int, endTick: Int, width: CGFloat) -> CGFloat {
        width * CGFloat(min(1, max(0, Double(tick) / Double(max(1, endTick)))))
    }

    /// 印の半径（重要度 0〜1 → 2.5〜6pt）。
    static func markerRadius(weight: Double) -> CGFloat {
        2.5 + 3.5 * CGFloat(min(1, max(0, weight)))
    }
}

/// シークバーの描画（1 枚の Canvas: 網掛け・再生済み・年表の印・つまみ）。
struct HUDSeekBarCanvas: View {
    let markers: [HUDTimelineMarker]
    let transport: HUDTransportSnapshot
    let previewTick: Int?
    let colorblind: Bool

    var body: some View {
        let t = transport
        Canvas { ctx, size in
            let w = size.width
            let trackY = size.height * 0.66
            let trackH: CGFloat = 6
            let track = CGRect(x: 0, y: trackY - trackH / 2, width: w, height: trackH)
            ctx.fill(Path(roundedRect: track, cornerRadius: 3), with: .color(Color.black.opacity(0.55)))
            // すぐにシークできる区間（キーフレーム・一度見た所。controller.seekReadyTick）
            let coveredX = HUDSeekBarGeometry.x(forTick: t.coveredTick, endTick: t.endTick, width: w)
            if coveredX > 0 {
                ctx.fill(Path(roundedRect: CGRect(x: 0, y: track.minY, width: coveredX, height: trackH), cornerRadius: 3),
                         with: .color(Color.white.opacity(0.22)))
            }
            // 再生済み
            let playedX = HUDSeekBarGeometry.x(forTick: t.tick, endTick: t.endTick, width: w)
            if playedX > 0 {
                ctx.fill(Path(roundedRect: CGRect(x: 0, y: track.minY, width: playedX, height: trackH), cornerRadius: 3),
                         with: .linearGradient(Gradient(colors: [Theme.gold, Theme.cyan]),
                                               startPoint: CGPoint(x: 0, y: trackY), endPoint: CGPoint(x: max(1, playedX), y: trackY)))
            }
            // 年表の印（バーの上。重要な物ほど大きい。色に加えて形: ブルー = 丸、レッド = ひし形、中立 = 四角）
            let markY = trackY - trackH / 2 - 8
            for m in markers where m.tick <= t.endTick {
                let x = HUDSeekBarGeometry.x(forTick: m.tick, endTick: t.endTick, width: w)
                let r = HUDSeekBarGeometry.markerRadius(weight: m.weight)
                let color = m.team.map { Theme.teamColor($0, colorblind: colorblind) } ?? Theme.gold
                let p = CGPoint(x: x, y: markY)
                let shape: Path
                switch m.team {
                case .blue?: shape = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                case .red?:
                    var d = Path()
                    d.move(to: CGPoint(x: p.x, y: p.y - r - 0.5))
                    d.addLine(to: CGPoint(x: p.x + r + 0.5, y: p.y))
                    d.addLine(to: CGPoint(x: p.x, y: p.y + r + 0.5))
                    d.addLine(to: CGPoint(x: p.x - r - 0.5, y: p.y))
                    d.closeSubpath()
                    shape = d
                default: shape = Path(CGRect(x: p.x - r * 0.85, y: p.y - r * 0.85, width: r * 1.7, height: r * 1.7))
                }
                ctx.fill(shape, with: .color(color.opacity(m.tick <= t.tick ? 0.95 : 0.6)))
                ctx.stroke(shape, with: .color(.black.opacity(0.7)), lineWidth: 0.8)
                switch m.kind {
                case .structure, .objective, .ace:
                    // 構造物・大型目標・全滅はバーまで線を引く（キルの集まりと見分ける）
                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: markY + r))
                    tick.addLine(to: CGPoint(x: x, y: track.minY))
                    ctx.stroke(tick, with: .color(color.opacity(0.6)), lineWidth: 1)
                case .end:
                    var flag = Path()
                    flag.move(to: CGPoint(x: x, y: 0))
                    flag.addLine(to: CGPoint(x: x, y: track.maxY))
                    ctx.stroke(flag, with: .color(.white.opacity(0.8)), lineWidth: 1.5)
                case .kill:
                    break
                }
            }
            // シーク中の目標
            if let target = t.seekingTo {
                let x = HUDSeekBarGeometry.x(forTick: target, endTick: t.endTick, width: w)
                ctx.stroke(Path(ellipseIn: CGRect(x: x - 8, y: trackY - 8, width: 16, height: 16)),
                           with: .color(Theme.gold), style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
            }
            // つまみ（ドラッグ中は指の位置）
            let knobTick = previewTick ?? t.displayTick
            let kx = HUDSeekBarGeometry.x(forTick: knobTick, endTick: t.endTick, width: w)
            let knob = CGRect(x: kx - 7, y: trackY - 7, width: 14, height: 14)
            ctx.fill(Path(ellipseIn: knob.insetBy(dx: -1.5, dy: -1.5)), with: .color(.black.opacity(0.5)))
            ctx.fill(Path(ellipseIn: knob), with: .color(previewTick == nil ? .white : Theme.gold))
        }
        .allowsHitTesting(false)
    }
}

/// 再生が終わった時のカード（観戦・リプレイ）。ドックの上に出し、再生バーはそのまま使える。
/// phase = nil は記録が途中で終わったリプレイ（中断）。
struct HUDSpectatorEndCard: View {
    let model: HUDModel
    let phase: HUDEndPhase?
    let colorblind: Bool
    @State private var appeared = false

    var body: some View {
        let style = phase.map { HUDEndOfMatchView.style($0.kind, colorblind: colorblind) }
            ?? HUDEndOfMatchView.Style(title: L("再生終了", "END OF REPLAY"),
                                       subtitle: L("記録はここまでです", "The recording ends here"),
                                       symbol: "flag.fill", color: Color(red: 0.7, green: 0.72, blue: 0.85))
        VStack(spacing: 6) {
            Image(systemName: style.symbol)
                .font(.system(size: 30, weight: .black))
                .foregroundStyle(LinearGradient(colors: [.white, style.color], startPoint: .top, endPoint: .bottom))
                .shadow(color: style.color, radius: 10)
            Text(style.title)
                .font(.system(size: 36, weight: .black, design: .serif))
                .italic()
                .tracking(4)
                .foregroundStyle(LinearGradient(colors: [.white, style.color], startPoint: .top, endPoint: .bottom))
                .shadow(color: style.color.opacity(0.9), radius: 12)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(style.subtitle)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
            if let reason = phase.flatMap({ HUDText.endReason($0.reason) }) {
                Text(reason)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
            HStack(spacing: 10) {
                Button { model.spectatorRestart() } label: {
                    Label(L("もう一度見る", "Watch Again"), systemImage: "arrow.counterclockwise")
                        .frame(minWidth: 130)
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("spectate_watch_again")
                // 記録の終わり（中断で終わった記録を含む）まで見た後なので、途中退出ではなく「結果へ」として終える
                Button { model.continueAfterEnd() } label: {
                    Label(L("結果へ", "Results"), systemImage: "chevron.right.2")
                        .frame(minWidth: 130)
                }
                .buttonStyle(PrimaryButtonStyle(color: style.color))
                .accessibilityIdentifier("result_continue")
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.62))
        )
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(style.color.opacity(0.6), lineWidth: 1))
        .scaleEffect(appeared ? 1 : 0.85)
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.spring(duration: 0.5, bounce: 0.3)) { appeared = true } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hud_end")
    }
}
