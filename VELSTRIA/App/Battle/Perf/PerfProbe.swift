import Foundation
import os
import QuartzCore

// 担当: battle-renderer（性能）。iPhone 実機で「どこが重いか」を区間ごとに測る（テスター用の性能モニター）。
//
// - 区間: BattleRenderer / BattleWorld の毎フレームの処理を細かく分けて CPU 時間を測る（有効時のみ。無効なら分岐 1 回）。
// - メインスレッドの稼働: RunLoop の観測で「寝ていない時間」を測る。区間の合計を引いた残り = SwiftUI の HUD・UIKit・
//   RealityKit のメインスレッド側の処理（こちらから細かく測れない分）。
// - 推定: フレームが遅いのにメインスレッドが空いている → GPU（描画解像度・後処理・影・粒子の重ね塗り）が詰まっている。
// - Instruments では "Battle" カテゴリの区間（sec.*）として見える。
//
// 有効にする: 設定 > テスター用 > 性能モニター（DEBUG / TESTER_TOOLS のみ）、または起動引数 -perfProbe。
// 戦闘を抜けると最後の計測をテキストで保存し、設定画面からコピーできる（コミュニティへの報告用）。

@MainActor
final class PerfProbe {
    static let shared = PerfProbe()

    enum Section: Int, CaseIterable {
        case sim, events, units, projectiles, zones, vfx, skillFX, effekseer, map, aim, fog, text, camera, overlay, combatText, governor

        var label: String {
            switch self {
            case .sim: return "sim"
            case .events: return "events"
            case .units: return "units"
            case .projectiles: return "proj"
            case .zones: return "zones"
            case .vfx: return "vfx"
            case .skillFX: return "skillFX"
            case .effekseer: return "efk"
            case .map: return "map"
            case .aim: return "aim"
            case .fog: return "fog"
            case .text: return "heal"
            case .camera: return "camera"
            case .overlay: return "bars"
            case .combatText: return "dmgText"
            case .governor: return "misc"
            }
        }
    }

    static let enabledKey = "velstria.perfProbe"
    static let lastReportKey = "velstria.perfProbe.lastReport"

    /// 性能モニターを使えるビルドか（出荷用の App Store ビルドでは false）。
    static var isAvailable: Bool {
        #if DEBUG || SCREENSHOTS || TESTER_TOOLS
        return true
        #else
        return false
        #endif
    }

    static var isRequested: Bool {
        guard isAvailable else { return false }
        if UserDefaults.standard.bool(forKey: enabledKey) { return true }
        #if DEBUG || SCREENSHOTS
        if DebugLaunch.args.contains("-perfProbe") { return true }
        #endif
        return false
    }

    /// 計測中か（戦闘の開始で isRequested から決める）。
    private(set) var enabled = false

    private let n = Section.allCases.count
    // 表示用の窓（0.5 秒）
    private var winSec: [Double]
    private var winFrames = 0
    private var winFrameSum: Double = 0
    private var winWorst: Double = 0
    private var winBusy: Double = 0
    private var winElapsed: Double = 0
    // 試合全体
    private var totSec: [Double]
    private var totMax: [Double]
    private var totFrames = 0
    private var totFrameSum: Double = 0
    private var totBusy: Double = 0
    private var hitchFrames = 0
    private var gpuBoundFrames = 0
    private var cpuBoundFrames = 0
    private var peakEntities = 0
    private var peakMB: Double = 0
    private var thermal: [String] = []
    private var qualitySteps: [String] = []
    private var worstHitches: [(ms: Double, top: String)] = []
    private var frameSec: [Double]
    private var sampleTimer: Double = 0

    // RunLoop の稼働
    private var observer: CFRunLoopObserver?
    private var awakeAt: Double = 0
    private var busyAcc: Double = 0

    /// 直近の窓の表示文字列（オーバーレイ用）。
    private(set) var liveText = ""

    private init() {
        winSec = Array(repeating: 0, count: Section.allCases.count)
        totSec = winSec
        totMax = winSec
        frameSec = winSec
    }

    // MARK: 開始・終了

    func begin(context: String) {
        enabled = PerfProbe.isRequested
        guard enabled else { return }
        reset()
        self.context = context
        installObserver()
    }

    private var context = ""

    func end() {
        guard enabled else { return }
        removeObserver()
        if totFrames > 30 {
            UserDefaults.standard.set(report(), forKey: PerfProbe.lastReportKey)
        }
        enabled = false
    }

    private func reset() {
        for i in 0..<n { winSec[i] = 0; totSec[i] = 0; totMax[i] = 0; frameSec[i] = 0 }
        winFrames = 0; winFrameSum = 0; winWorst = 0; winBusy = 0; winElapsed = 0
        totFrames = 0; totFrameSum = 0; totBusy = 0
        hitchFrames = 0; gpuBoundFrames = 0; cpuBoundFrames = 0
        peakEntities = 0; peakMB = 0; thermal = []; qualitySteps = []; worstHitches = []
        sampleTimer = 0; busyAcc = 0; liveText = ""
    }

    // MARK: 区間

    @inline(__always)
    func start() -> Double { enabled ? CACurrentMediaTime() : 0 }

    @inline(__always)
    func stop(_ s: Section, _ t0: Double) {
        guard enabled else { return }
        frameSec[s.rawValue] += CACurrentMediaTime() - t0
    }

    /// 区間を測りながら実行する。
    @inline(__always)
    func measure<T>(_ s: Section, _ body: () throws -> T) rethrows -> T {
        guard enabled else { return try body() }
        let t0 = CACurrentMediaTime()
        defer { frameSec[s.rawValue] += CACurrentMediaTime() - t0 }
        return try body()
    }

    // MARK: フレームの締め

    /// 1 フレームの終わり（frameDt = 描画間隔、target = 目標間隔、秒）。
    func endFrame(frameDt: Double, target: Double, entities: Int, quality: String) {
        guard enabled else { return }
        let busy = busyAcc + (awakeAt > 0 ? CACurrentMediaTime() - awakeAt : 0)
        busyAcc = 0
        if awakeAt > 0 { awakeAt = CACurrentMediaTime() }
        var work: Double = 0
        for i in 0..<n {
            let v = frameSec[i]
            work += v
            winSec[i] += v
            totSec[i] += v
            totMax[i] = max(totMax[i], v)
        }
        winFrames += 1; winFrameSum += frameDt; winWorst = max(winWorst, frameDt); winBusy += busy; winElapsed += frameDt
        totFrames += 1; totFrameSum += frameDt; totBusy += busy
        peakEntities = max(peakEntities, entities)
        if qualitySteps.last != quality { qualitySteps.append(quality) }

        if frameDt > target * 1.5 {
            hitchFrames += 1
            // メインスレッドが目標の 7 割も働いていない遅延は GPU 待ち（描画側）とみなす
            if busy < target * 0.7 { gpuBoundFrames += 1 } else { cpuBoundFrames += 1 }
            let top = Section.allCases.max { frameSec[$0.rawValue] < frameSec[$1.rawValue] }!
            let note = String(format: "busy %.1f our %.1f top %@ %.1f", busy * 1000, work * 1000, top.label,
                              frameSec[top.rawValue] * 1000)
            worstHitches.append((frameDt * 1000, note))
            if worstHitches.count > 8 {
                worstHitches.sort { $0.ms > $1.ms }
                worstHitches.removeLast()
            }
        }
        for i in 0..<n { frameSec[i] = 0 }

        sampleTimer += frameDt
        if sampleTimer >= 1 {
            sampleTimer = 0
            peakMB = max(peakMB, PerfProbe.footprintMB())
            let t = PerfProbe.thermalName(ProcessInfo.processInfo.thermalState)
            if thermal.last != t { thermal.append(t) }
        }
        if winElapsed >= 0.5 { flushWindow(entities: entities, quality: quality) }
    }

    private func flushWindow(entities: Int, quality: String) {
        let f = Double(max(1, winFrames))
        let avg = winFrameSum / f
        var ours: Double = 0
        for v in winSec { ours += v }
        let busy = winBusy / f
        let other = max(0, busy - ours / f)
        let top = Section.allCases.sorted { winSec[$0.rawValue] > winSec[$1.rawValue] }.prefix(4)
        let tops = top.map { String(format: "%@ %.1f", $0.label, winSec[$0.rawValue] / f * 1000) }.joined(separator: " ")
        let bound = PerfProbe.bottleneck(frameMs: avg * 1000, busyMs: busy * 1000, targetMs: 1000.0 / 60)
        liveText = String(format: " %.0ffps %.1fms max %.0f  %@\n main %.1f = ours %.1f + HUD/RK %.1f\n %@\n e%d %@ %.0fMB %@",
                          f / max(0.0001, winFrameSum), avg * 1000, winWorst * 1000, bound,
                          busy * 1000, ours / f * 1000, other * 1000, tops,
                          entities, quality, PerfProbe.footprintMB(),
                          PerfProbe.thermalName(ProcessInfo.processInfo.thermalState))
        for i in 0..<n { winSec[i] = 0 }
        winFrames = 0; winFrameSum = 0; winWorst = 0; winBusy = 0; winElapsed = 0
    }

    /// 遅さの原因の推定（表示用）。
    static func bottleneck(frameMs: Double, busyMs: Double, targetMs: Double) -> String {
        if frameMs < targetMs * 1.15 { return "OK" }
        return busyMs < frameMs * 0.6 ? "GPU?" : "CPU"
    }

    // MARK: レポート

    func report() -> String {
        let f = Double(max(1, totFrames))
        let avgFrame = totFrameSum / f
        var ours: Double = 0
        for v in totSec { ours += v }
        let busy = totBusy / f
        var lines: [String] = []
        lines.append("VELSTRIA perf \(context)")
        lines.append("device \(PerfProbe.deviceModel) iOS \(ProcessInfo.processInfo.operatingSystemVersionString) \(AppVersionInfo.display)")
        lines.append(String(format: "frames %d  %.0fs  avg %.0ffps (%.2fms)  hitch %d (GPU? %d / CPU %d)",
                            totFrames, totFrameSum, f / max(0.0001, totFrameSum), avgFrame * 1000,
                            hitchFrames, gpuBoundFrames, cpuBoundFrames))
        lines.append(String(format: "main busy %.2fms = ours %.2fms + HUD/UIKit/RealityKit %.2fms",
                            busy * 1000, ours / f * 1000, max(0, busy - ours / f) * 1000))
        lines.append("verdict \(PerfProbe.bottleneck(frameMs: avgFrame * 1000, busyMs: busy * 1000, targetMs: 1000.0 / 60))")
        lines.append("sections (avg / max ms):")
        for s in Section.allCases.sorted(by: { totSec[$0.rawValue] > totSec[$1.rawValue] }) {
            lines.append(String(format: "  %-8@ %6.3f / %6.2f", s.label as NSString, totSec[s.rawValue] / f * 1000,
                                totMax[s.rawValue] * 1000))
        }
        lines.append("peak entities \(peakEntities)  peak mem \(Int(peakMB))MB")
        lines.append("thermal \(thermal.joined(separator: ">"))  quality \(qualitySteps.suffix(12).joined(separator: ">"))")
        lines.append("worst hitches:")
        for h in worstHitches.sorted(by: { $0.ms > $1.ms }) {
            lines.append(String(format: "  %.0fms  %@", h.ms, h.top))
        }
        return lines.joined(separator: "\n")
    }

    static var lastReport: String? { UserDefaults.standard.string(forKey: lastReportKey) }

    // MARK: RunLoop の観測

    private func installObserver() {
        guard observer == nil else { return }
        awakeAt = CACurrentMediaTime()
        let activities = CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue
        let obs = CFRunLoopObserverCreateWithHandler(nil, activities, true, 0) { _, activity in
            MainActor.assumeIsolated {
                let probe = PerfProbe.shared
                let now = CACurrentMediaTime()
                if activity == .beforeWaiting {
                    if probe.awakeAt > 0 { probe.busyAcc += now - probe.awakeAt }
                    probe.awakeAt = 0
                } else {
                    probe.awakeAt = now
                }
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), obs, .commonModes)
        observer = obs
    }

    private func removeObserver() {
        if let observer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes) }
        observer = nil
        awakeAt = 0
    }

    // MARK: 端末情報

    static func thermalName(_ s: ProcessInfo.ThermalState) -> String {
        switch s {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    static var deviceModel: String {
        #if targetEnvironment(simulator)
        return "Simulator"
        #else
        var u = utsname()
        uname(&u)
        return withUnsafeBytes(of: &u.machine) { String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self) }
        #endif
    }
}

import UIKit

/// 性能モニターの表示（戦闘画面の下端中央。タッチは通す）。
final class PerfProbeLabel: UILabel {
    override init(frame: CGRect) {
        super.init(frame: frame)
        font = UIFont.monospacedSystemFont(ofSize: 9, weight: .semibold)
        textColor = UIColor(white: 1, alpha: 0.95)
        backgroundColor = UIColor(white: 0, alpha: 0.55)
        numberOfLines = 4
        adjustsFontSizeToFitWidth = true
        minimumScaleFactor = 0.7
        layer.cornerRadius = 4
        layer.masksToBounds = true
        isUserInteractionEnabled = false
        isHidden = true
        accessibilityIdentifier = "battle_perf_probe"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(_ s: String) {
        guard !s.isEmpty, s != text else { return }
        text = s
    }
}
