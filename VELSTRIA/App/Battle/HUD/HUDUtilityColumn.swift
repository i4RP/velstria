import SwiftUI
import UIKit
import VelstriaCore

// 担当: battle-hud。ミニマップ横の縦列（操作中のみ。観戦・リプレイでは出さない）:
// 上から 端末状態（電池残量・充電中、現在時刻 HH:mm）、設定（UI030 のポーズメニュー）、消音（一時的。保存しない。
// 設定の BGM・効果音がどちらも 0 の間は消音の表示で、押すと音量の設定へ案内する）、
// ズーム（視野を広げる。保存しない）。オフライン対 AI のため通信の ms 表示とボイスチャットは無い。
// 見た目は小さな丸ボタン（HUDLayout.utilityButtonSize）、タップ領域は 44pt。
// ミニマップの内側に置く（右手配置はミニマップの右、左利きはミニマップが右上へ移るのでその左。位置は HUDLayout.utilityButtonFrame）。

struct HUDUtilityColumn: View {
    let model: HUDModel
    let layout: HUDLayout

    var body: some View {
        let status = layout.utilityStatusFrame
        let size = layout.utilityButtonSize
        ZStack {
            HUDDeviceStatusView(scale: layout.topScale)
                .frame(width: status.width, height: status.height)
                .position(x: status.midX, y: status.midY)
            column(0) {
                HUDUtilityButton(symbol: "gearshape.fill", label: L("ポーズ・設定", "Pause & Settings"),
                                 identifier: "hud_pause", size: size) {
                    model.openPanel(.pause)
                }
            }
            column(1) { HUDSoundButton(model: model, size: size) }
            column(2) { HUDZoomButton(model: model, size: size) }
        }
        .frame(width: layout.width, height: layout.height)
    }

    private func column<Content: View>(_ index: Int, @ViewBuilder _ content: () -> Content) -> some View {
        let f = layout.utilityButtonFrame(index)
        return content().position(x: f.midX, y: f.midY)
    }
}

/// 消音ボタン（消音中は赤）。消音の状態と設定の音量だけを観測する。
/// 設定の BGM・効果音がどちらも 0（既定値）の間は実際に無音なので、一時消音していなくても消音の表示にする
/// （押すと設定で音量を上げるよう案内する。HUDModel.toggleSound）。
private struct HUDSoundButton: View {
    let model: HUDModel
    let size: CGFloat

    var body: some View {
        let muted = model.soundSilenced
        HUDUtilityButton(symbol: HUDUtilityColumnStyle.soundSymbol(muted: muted),
                         label: L("サウンド", "Sound"),
                         value: model.soundMuted ? L("消音中", "Muted")
                             : (muted ? L("音量 0（設定）", "Volume off in Settings") : L("オン", "On")),
                         identifier: "hud_sound", size: size,
                         tint: muted ? Theme.danger : .white, rim: muted ? Theme.danger.opacity(0.8) : HUDStyle.rim) {
            model.toggleSound()
        }
    }
}

/// ズームボタン（視野を広げている間は金色）。ズームの状態だけを観測する。
private struct HUDZoomButton: View {
    let model: HUDModel
    let size: CGFloat

    var body: some View {
        let boosted = model.zoomBoost
        HUDUtilityButton(symbol: HUDUtilityColumnStyle.zoomSymbol(boosted: boosted),
                         label: boosted ? L("視野を元に戻す", "Zoom Back In") : L("視野を広げる", "Zoom Out"),
                         value: boosted ? L("広い視野", "Wide view") : L("通常", "Normal"),
                         identifier: "hud_zoom", size: size,
                         tint: boosted ? Theme.gold : .white, rim: boosted ? Theme.gold.opacity(0.8) : HUDStyle.rim) {
            model.toggleZoom()
        }
    }
}

enum HUDUtilityColumnStyle {
    /// 状態を表すアイコン（通常 = 音あり / 消音中 = 斜線）。
    static func soundSymbol(muted: Bool) -> String { muted ? "speaker.slash.fill" : "speaker.wave.2.fill" }
    /// 状態を表すアイコン（通常の寄った視野 = ＋ / 広げた視野 = −）。
    static func zoomSymbol(boosted: Bool) -> String { boosted ? "minus.magnifyingglass" : "plus.magnifyingglass" }
}

/// 小さな丸いガラス調のボタン（見た目は size、タップ領域は 44pt 以上）。
/// hitAlignment = .top では見た目をタップ領域の上端に寄せる（上端の帯と高さをそろえ、タップ領域は下へ広げる）。
struct HUDUtilityButton: View {
    let symbol: String
    let label: String
    var value: String? = nil
    let identifier: String
    let size: CGFloat
    var tint: Color = .white
    var rim: Color = HUDStyle.rim
    var hitAlignment: Alignment = .center
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.44, weight: .bold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size, height: size)
                .background(Circle().fill(LinearGradient(colors: [HUDStyle.glassTop, HUDStyle.glassBottom],
                                                         startPoint: .top, endPoint: .bottom)))
                .overlay(Circle().strokeBorder(rim, lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .frame(width: max(44, size), height: max(44, size), alignment: hitAlignment)
                .contentShape(Rectangle())
        }
        .buttonStyle(HUDPressStyle())
        .accessibilityLabel(label)
        .accessibilityValue(value ?? "")
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - 端末状態（電池・時刻）

/// 電池の表示用の読み取り値。
struct HUDBatteryReading: Equatable {
    /// 0〜1。
    var level: Double
    var charging: Bool

    /// この割合未満で赤くする。
    static let lowLevel = 0.2

    var isLow: Bool { level < Self.lowLevel }
    var percent: Int { Int((level * 100).rounded()) }

    /// UIDevice の値から。残量が不明（シミュレータの -1・監視前の unknown）の時は nil（電池を出さない）。
    static func make(level: Float, state: UIDevice.BatteryState) -> HUDBatteryReading? {
        guard level >= 0, state != .unknown else { return nil }
        return HUDBatteryReading(level: min(1, Double(level)), charging: state == .charging || state == .full)
    }

    @MainActor static func current() -> HUDBatteryReading? {
        let d = UIDevice.current
        return make(level: d.batteryLevel, state: d.batteryState)
    }
}

/// 電池アイコン + 現在時刻（HH:mm）。電池は UIDevice の監視（表示中だけ有効にする）、時刻は毎分更新。
struct HUDDeviceStatusView: View {
    let scale: CGFloat
    @State private var battery: HUDBatteryReading?

    var body: some View {
        TimelineView(.everyMinute) { context in
            let clock = Self.clockText(context.date)
            HStack(spacing: 3) {
                if let battery {
                    HUDBatteryGlyph(reading: battery)
                        .frame(width: 15 * scale, height: 7.5 * scale)
                }
                Text(clock)
                    .font(.system(size: 9.5 * scale, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.88))
                    .shadow(color: .black.opacity(0.8), radius: 1, y: 0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.accessibilityText(battery: battery, clock: clock))
            .accessibilityIdentifier("hud_device_status")
        }
        .allowsHitTesting(false)
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            battery = HUDBatteryReading.current()
        }
        .onDisappear { UIDevice.current.isBatteryMonitoringEnabled = false }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in
            battery = HUDBatteryReading.current()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in
            battery = HUDBatteryReading.current()
        }
    }

    /// 24 時間表記の HH:mm。
    static func clockText(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    static func accessibilityText(battery: HUDBatteryReading?, clock: String) -> String {
        let time = L("時刻 \(clock)", "Time \(clock)")
        guard let battery else { return time }
        let charge = battery.charging ? L("、充電中", ", charging") : ""
        return L("電池 \(battery.percent)%\(charge)、", "Battery \(battery.percent)%\(charge), ") + time
    }
}

/// 電池の形（残量の幅で塗る。20% 未満は赤、充電中は緑に稲妻）。
struct HUDBatteryGlyph: View, Equatable {
    let reading: HUDBatteryReading

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let nub = max(1.5, w * 0.1)
            let shell = w - nub - 0.5
            let color = reading.isLow ? Theme.danger : (reading.charging ? Theme.success : Color.white.opacity(0.9))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: h * 0.28, style: .continuous)
                    .strokeBorder(reading.isLow ? Theme.danger : Color.white.opacity(0.75), lineWidth: 1)
                    .frame(width: shell, height: h)
                RoundedRectangle(cornerRadius: h * 0.14, style: .continuous)
                    .fill(color)
                    .frame(width: max(1, (shell - 3) * reading.level), height: h - 3)
                    .offset(x: 1.5)
                RoundedRectangle(cornerRadius: nub * 0.4)
                    .fill(reading.isLow ? Theme.danger : Color.white.opacity(0.75))
                    .frame(width: nub, height: h * 0.45)
                    .offset(x: shell + 0.5)
                if reading.charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: h * 0.95, weight: .black))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.8), radius: 0.5)
                        .frame(width: shell, height: h)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
