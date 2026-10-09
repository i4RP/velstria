import Foundation
import QuartzCore
import os

/// Fixed-size CPU counters; reports deliberately exclude loading and warmup.
@MainActor
final class SyncWorkStats {
    enum Part: String, CaseIterable {
        case map, units, projectiles, effects, fog, effekseer

        var signpost: StaticString {
            switch self {
            case .map: return "sync.map"
            case .units: return "sync.units"
            case .projectiles: return "sync.projectiles"
            case .effects: return "sync.effects"
            case .fog: return "sync.fog"
            case .effekseer: return "sync.effekseer"
            }
        }
    }

    struct Sample: Codable {
        var calls = 0
        var totalMs: Double = 0
        var maxMs: Double = 0
        var averageMs: Double { totalMs / Double(max(1, calls)) }
    }

    private var samples: [Part: Sample] = Dictionary(uniqueKeysWithValues: Part.allCases.map { ($0, Sample()) })

    func measure(_ part: Part, live: Bool, _ body: () -> Void) {
        guard live else { body(); return }
        let interval = FrameStats.signposter.beginInterval(part.signpost)
        let start = CACurrentMediaTime()
        body()
        let ms = (CACurrentMediaTime() - start) * 1000
        FrameStats.signposter.endInterval(part.signpost, interval)
        samples[part]!.calls += 1
        samples[part]!.totalMs += ms
        samples[part]!.maxMs = max(samples[part]!.maxMs, ms)
    }

    var summary: [String: Sample] {
        Dictionary(uniqueKeysWithValues: samples.map { ($0.key.rawValue, $0.value) })
    }
}
