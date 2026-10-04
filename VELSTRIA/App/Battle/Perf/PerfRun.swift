#if DEBUG || SCREENSHOTS
import Foundation
import UIKit

// 担当: battle-renderer（性能）。起動引数による自動計測（出荷ビルドには含めない）。
//
//   -perfRun <秒>     幕が上がってから指定秒プレイした時点の計測結果を JSON で書き出す
//   -perfSpeed <倍率>  試合の進行速度（既定 1。観戦で後半の負荷まで見るときに上げる）
//   -perfExit          書き出し後にアプリを終了する（tools/perf_run.sh が終了を待つ）
//
// 出力: <アプリのデータ>/Documents/perf/perf-report.json と、コンソールへの 1 行（"VELSTRIA_PERF_REPORT {...}"）。
// 計測の読み方は FrameStats / AssetLedger のコメントを参照。

struct PerfReport: Codable {
    var device: String
    var os: String
    var build: String
    var quality: String
    var frameRate: Int
    var speed: Double
    var requestedSeconds: Double
    /// 戦闘画面の生成から幕が上がるまで（ms）。
    var loadMs: Double
    /// 世界の構築から幕が上がるまで（幕の裏の準備。ms）。
    var warmupMs: Double
    var warmupFrames: Int
    var frame: FrameStats.Summary
    var ledger: AssetLedger.Snapshot
    var thermalStates: [String]
    var peakFootprintMB: Double
    var peakEntities: Int
    var notes: [String]
}

@MainActor
final class PerfRun {
    static var requestedSeconds: Double? {
        DebugLaunch.value(after: "-perfRun").flatMap(Double.init).flatMap { $0 > 0 ? $0 : nil }
    }
    static var requestedSpeed: Double {
        DebugLaunch.value(after: "-perfSpeed").flatMap(Double.init).map { min(max($0, 0.25), 8) } ?? 1
    }
    static var exitWhenDone: Bool { DebugLaunch.args.contains("-perfExit") }

    let seconds: Double
    private var elapsed: Double = 0
    private var done = false
    private var thermal: [String] = []
    private var peakFootprint: Double = 0
    private var peakEntities = 0
    private var sampleTimer: Double = 0

    init(seconds: Double) { self.seconds = seconds }

    /// プレイ中の毎フレーム。終了時刻に達したら true（呼び出し側が report を作って finish する）。
    func tick(dt: Double, entities: Int) -> Bool {
        guard !done else { return false }
        elapsed += dt
        peakEntities = max(peakEntities, entities)
        sampleTimer += dt
        if sampleTimer >= 0.5 {
            sampleTimer = 0
            peakFootprint = max(peakFootprint, PerfRun.footprintMB())
            let t = PerfRun.thermalName(ProcessInfo.processInfo.thermalState)
            if thermal.last != t { thermal.append(t) }
        }
        if elapsed >= seconds {
            done = true
            return true
        }
        return false
    }

    func finish(_ make: (_ thermal: [String], _ peakFootprintMB: Double, _ peakEntities: Int) -> PerfReport) {
        peakFootprint = max(peakFootprint, PerfRun.footprintMB())
        let report = make(thermal, peakFootprint, peakEntities)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(report) else { return }
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("perf")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: dir.appendingPathComponent("perf-report.json"), options: .atomic)
        enc.outputFormatting = [.sortedKeys]
        if let line = try? enc.encode(report), let s = String(data: line, encoding: .utf8) {
            print("VELSTRIA_PERF_REPORT \(s)")
        }
        if PerfRun.exitWhenDone {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exit(0) }
        }
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

    /// 物理メモリの使用量（phys_footprint。Xcode のメモリゲージと同じ値）。
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
        return "Simulator " + (ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "?")
        #else
        var u = utsname()
        uname(&u)
        return withUnsafeBytes(of: &u.machine) { String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self) }
        #endif
    }

    static var buildName: String {
        #if DEBUG
        return "Debug"
        #else
        return "Release"
        #endif
    }
}
#endif
