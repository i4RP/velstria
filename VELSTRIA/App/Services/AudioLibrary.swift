import Foundation
import VelstriaCore

// 担当: app-services
// 効果音と BGM の「楽譜」。すべて SynthCanvas への書き込みで作る（音源ファイルなし）。
// 効果音: サイン・三角波中心の柔らかい音色、短いアタックと指数減衰、最長 0.8 秒。
// BGM: メニュー（D マイナーの穏やかなパッド + アルペジオ、84 BPM・16 小節ループ）、
//      バトル（D マイナー 128 BPM の 4 つ打ち・8 分ベース・後半にリード、16 小節ループ）、
//      勝利 / 敗北のスティンガー（約 5 秒・ループなし）。

enum SFXSynth {
    static let sampleRate: Double = 44_100
    static let maxDuration: Double = 0.8

    /// 連打される戦闘音は音程違いのバリエーションを持たせて単調さを避ける。
    static func variantCount(_ sfx: SFX) -> Int {
        switch sfx {
        case .hit, .attackMelee, .attackRanged, .gold: return 3
        default: return 1
        }
    }

    private static func m(_ note: Double) -> Double { SynthCanvas.midi(note) }

    /// モノラル PCM（-1...1）。
    static func render(_ sfx: SFX, variant: Int = 0) -> [Float] {
        let p = [1.0, 1.06, 0.95][max(0, variant) % 3]
        var c: SynthCanvas
        var peak: Float = 0.5
        func canvas(_ d: Double) -> SynthCanvas { SynthCanvas(duration: min(d, maxDuration), sampleRate: sampleRate, stereo: false) }

        switch sfx {
        case .uiTap:
            c = canvas(0.07)
            c.add(SynthNote(start: 0, duration: 0.06, frequency: 1400, endFrequency: 1100, sweepTime: 0.04,
                            amplitude: 0.6, attack: 0.002, decay: 0.018, release: 0.01))
            c.add(SynthNote(start: 0, duration: 0.03, frequency: 2800, wave: .triangle, amplitude: 0.12, attack: 0.001, decay: 0.008))
            peak = 0.32
        case .uiConfirm:
            c = canvas(0.3)
            for (t, note) in [(0.0, 88.0), (0.07, 95.0)] {
                c.add(SynthNote(start: t, duration: 0.22, frequency: m(note), wave: .triangle, amplitude: 0.45,
                                attack: 0.003, decay: 0.08, release: 0.03))
                c.add(SynthNote(start: t, duration: 0.22, frequency: m(note), amplitude: 0.3, attack: 0.003, decay: 0.09, release: 0.03))
            }
            peak = 0.38
        case .uiBack:
            c = canvas(0.16)
            c.add(SynthNote(start: 0, duration: 0.15, frequency: 880, endFrequency: 587, sweepTime: 0.09,
                            amplitude: 0.6, attack: 0.003, decay: 0.05, release: 0.02))
            c.add(SynthNote(start: 0, duration: 0.12, frequency: 440, endFrequency: 294, sweepTime: 0.09, wave: .triangle,
                            amplitude: 0.15, attack: 0.003, decay: 0.04))
            peak = 0.32
        case .uiError:
            c = canvas(0.32)
            for t in [0.0, 0.15] {
                c.add(SynthNote(start: t, duration: 0.13, frequency: m(55), wave: .softSquare, amplitude: 0.5,
                                attack: 0.004, decay: 0.08, release: 0.03, lowpass: 1400))
            }
            peak = 0.38
        case .purchase:
            c = canvas(0.6)
            for (i, note) in [84.0, 88, 91, 96].enumerated() {
                c.add(SynthNote(start: Double(i) * 0.055, duration: 0.3, frequency: m(note), wave: .triangle,
                                amplitude: 0.45, attack: 0.003, decay: 0.1, release: 0.04))
            }
            c.addBell(start: 0.2, frequency: m(96), amplitude: 0.18, decay: 0.14)
            c.add(SynthNote(start: 0.2, duration: 0.3, frequency: m(108), amplitude: 0.06, attack: 0.01, decay: 0.1))
            c.add(SynthNoise(start: 0.15, duration: 0.4, amplitude: 0.08, attack: 0.05, decay: 0.12, release: 0.05,
                             lowpassFrom: 12_000, highpass: 6000, seed: 11))
            peak = 0.48
        case .reward:
            c = canvas(0.75)
            for (i, note) in [79.0, 83, 86, 91].enumerated() {
                c.addBell(start: Double(i) * 0.045, frequency: m(note), amplitude: 0.35, decay: 0.28)
            }
            c.add(SynthNote(start: 0, duration: 0.7, frequency: m(67), amplitude: 0.12, attack: 0.08, decay: 0.35, release: 0.1))
            c.add(SynthNote(start: 0, duration: 0.7, frequency: m(74), amplitude: 0.1, attack: 0.08, decay: 0.35, release: 0.1))
            peak = 0.52
        case .levelUp:
            c = canvas(0.8)
            for (i, note) in [74.0, 78, 81, 86, 90].enumerated() {
                c.add(SynthNote(start: Double(i) * 0.065, duration: 0.22, frequency: m(note), wave: .triangle,
                                amplitude: 0.4, attack: 0.003, decay: 0.08, release: 0.03))
            }
            for note in [86.0, 93] {
                c.add(SynthNote(start: 0.34, duration: 0.45, frequency: m(note), amplitude: 0.3, attack: 0.01, decay: 0.2,
                                release: 0.08, vibratoRate: 5.5, vibratoDepth: 0.004))
            }
            c.add(SynthNoise(start: 0.3, duration: 0.45, amplitude: 0.06, attack: 0.1, decay: 0.15, release: 0.05,
                             lowpassFrom: 12_000, highpass: 5000, seed: 21))
            peak = 0.58
        case .attackMelee:
            c = canvas(0.18)
            c.add(SynthNoise(start: 0, duration: 0.15, amplitude: 0.8, attack: 0.03, decay: 0.05, release: 0.02,
                             lowpassFrom: 900 * p, lowpassTo: 5000 * p, highpass: 300, seed: 31))
            c.add(SynthNote(start: 0, duration: 0.08, frequency: 160 * p, endFrequency: 80 * p, sweepTime: 0.05,
                            amplitude: 0.35, attack: 0.002, decay: 0.03))
            peak = 0.44
        case .attackRanged:
            c = canvas(0.18)
            c.add(SynthNote(start: 0, duration: 0.15, frequency: 1600 * p, endFrequency: 520 * p, sweepTime: 0.1,
                            amplitude: 0.5, attack: 0.002, decay: 0.05))
            c.add(SynthNote(start: 0, duration: 0.15, frequency: 800 * p, endFrequency: 260 * p, sweepTime: 0.1, wave: .triangle,
                            amplitude: 0.2, attack: 0.002, decay: 0.05))
            c.add(SynthNoise(start: 0, duration: 0.025, amplitude: 0.2, attack: 0.001, decay: 0.008, lowpassFrom: 4000, seed: 41))
            peak = 0.38
        case .hit:
            c = canvas(0.15)
            c.add(SynthNote(start: 0, duration: 0.14, frequency: 180 * p, endFrequency: 55 * p, sweepTime: 0.07,
                            amplitude: 0.8, attack: 0.001, decay: 0.05))
            c.add(SynthNoise(start: 0, duration: 0.04, amplitude: 0.4, attack: 0.001, decay: 0.015, lowpassFrom: 3500, seed: 51))
            peak = 0.48
        case .crit:
            c = canvas(0.32)
            c.add(SynthNote(start: 0, duration: 0.16, frequency: 200, endFrequency: 55, sweepTime: 0.08,
                            amplitude: 0.8, attack: 0.001, decay: 0.06))
            c.add(SynthNoise(start: 0, duration: 0.06, amplitude: 0.35, attack: 0.001, decay: 0.02, lowpassFrom: 7000, seed: 61))
            c.addBell(start: 0.01, frequency: 2350, amplitude: 0.28, decay: 0.07)
            peak = 0.58
        case .skillCast:
            c = canvas(0.45)
            c.add(SynthNoise(start: 0, duration: 0.35, amplitude: 0.5, attack: 0.08, decay: 0.12, release: 0.05,
                             lowpassFrom: 500, lowpassTo: 5000, highpass: 200, seed: 71))
            c.add(SynthNote(start: 0, duration: 0.42, frequency: 330, endFrequency: 990, sweepTime: 0.25, wave: .triangle,
                            amplitude: 0.35, attack: 0.03, decay: 0.14, release: 0.06, vibratoRate: 7, vibratoDepth: 0.01))
            peak = 0.48
        case .ultimateCast:
            c = canvas(0.8)
            c.add(SynthNote(start: 0, duration: 0.78, frequency: 95, endFrequency: 38, sweepTime: 0.35,
                            amplitude: 0.8, attack: 0.005, decay: 0.28, release: 0.1))
            c.add(SynthNote(start: 0, duration: 0.72, frequency: 220, endFrequency: 880, sweepTime: 0.45, wave: .softSaw,
                            amplitude: 0.25, attack: 0.12, decay: 0.25, release: 0.1, lowpass: 2400))
            c.addBell(start: 0.32, frequency: m(86), amplitude: 0.2, decay: 0.2)
            c.addBell(start: 0.34, frequency: m(93), amplitude: 0.14, decay: 0.18)
            c.add(SynthNoise(start: 0, duration: 0.72, amplitude: 0.25, attack: 0.25, decay: 0.2, release: 0.1,
                             lowpassFrom: 1000, lowpassTo: 7000, seed: 81))
            peak = 0.68
        case .heal:
            c = canvas(0.65)
            for (i, note) in [72.0, 76, 79].enumerated() {
                c.add(SynthNote(start: Double(i) * 0.06, duration: 0.5, frequency: m(note), wave: .triangle, amplitude: 0.3,
                                attack: 0.04, decay: 0.22, release: 0.08, vibratoRate: 6, vibratoDepth: 0.004))
            }
            c.add(SynthNote(start: 0.18, duration: 0.45, frequency: m(84), amplitude: 0.15, attack: 0.05, decay: 0.2, release: 0.08))
            peak = 0.44
        case .shield:
            c = canvas(0.55)
            let partials: [(Double, Float, Double)] = [(1, 0.45, 0.22), (2.32, 0.22, 0.14), (4.25, 0.1, 0.09), (6.63, 0.05, 0.05)]
            for (ratio, amp, decay) in partials {
                c.add(SynthNote(start: 0, duration: 0.52, frequency: 620 * ratio, amplitude: amp, attack: 0.002, decay: decay, release: 0.05))
            }
            c.add(SynthNote(start: 0, duration: 0.4, frequency: 310, amplitude: 0.2, attack: 0.01, decay: 0.15))
            peak = 0.44
        case .death:
            c = canvas(0.75)
            c.add(SynthNote(start: 0, duration: 0.72, frequency: 392, endFrequency: 98, sweepTime: 0.6, wave: .triangle,
                            amplitude: 0.5, attack: 0.01, decay: 0.3, release: 0.1, lowpass: 1500))
            c.add(SynthNote(start: 0, duration: 0.72, frequency: 196, endFrequency: 49, sweepTime: 0.6,
                            amplitude: 0.3, attack: 0.01, decay: 0.3, release: 0.1))
            c.add(SynthNoise(start: 0, duration: 0.3, amplitude: 0.2, attack: 0.005, decay: 0.15, lowpassFrom: 700, seed: 91))
            peak = 0.52
        case .kill:
            c = canvas(0.38)
            c.add(SynthNote(start: 0, duration: 0.1, frequency: m(81), wave: .softSquare, amplitude: 0.35,
                            attack: 0.002, decay: 0.05, release: 0.02, lowpass: 2600))
            c.add(SynthNote(start: 0.07, duration: 0.3, frequency: m(86), wave: .softSquare, amplitude: 0.4,
                            attack: 0.002, decay: 0.11, release: 0.05, lowpass: 2600))
            c.add(SynthNoise(start: 0, duration: 0.05, amplitude: 0.3, attack: 0.001, decay: 0.02, lowpassFrom: 5000, seed: 101))
            peak = 0.54
        case .multiKill:
            c = canvas(0.65)
            for (i, note) in [81.0, 86, 89].enumerated() {
                c.add(SynthNote(start: Double(i) * 0.09, duration: 0.12, frequency: m(note), wave: .softSquare, amplitude: 0.35,
                                attack: 0.002, decay: 0.06, release: 0.02, lowpass: 3000))
            }
            c.addBell(start: 0.27, frequency: m(98), amplitude: 0.3, decay: 0.2)
            c.add(SynthNote(start: 0.27, duration: 0.36, frequency: m(86), wave: .triangle, amplitude: 0.3,
                            attack: 0.003, decay: 0.22, release: 0.06))
            peak = 0.6
        case .towerDestroyed:
            c = canvas(0.8)
            c.add(SynthNote(start: 0, duration: 0.8, frequency: 72, endFrequency: 34, sweepTime: 0.4,
                            amplitude: 0.9, attack: 0.003, decay: 0.35, release: 0.1))
            c.add(SynthNoise(start: 0, duration: 0.75, amplitude: 0.7, attack: 0.005, decay: 0.3, release: 0.1,
                             lowpassFrom: 2200, lowpassTo: 250, seed: 111))
            for (i, t) in [0.12, 0.2, 0.29, 0.38, 0.5].enumerated() {
                c.add(SynthNoise(start: t, duration: 0.06, amplitude: 0.25 - Float(i) * 0.03, attack: 0.002, decay: 0.02,
                                 lowpassFrom: 1800, seed: 120 + UInt64(i)))
            }
            peak = 0.72
        case .objective:
            c = canvas(0.8)
            for note in [62.0, 69] {
                c.add(SynthNote(start: 0, duration: 0.4, frequency: m(note), wave: .softSaw, amplitude: 0.3,
                                attack: 0.05, decay: 0.35, release: 0.06, lowpass: 1600))
            }
            for note in [69.0, 74] {
                c.add(SynthNote(start: 0.22, duration: 0.56, frequency: m(note), wave: .softSaw, amplitude: 0.3,
                                attack: 0.05, decay: 0.35, release: 0.1, lowpass: 1600))
            }
            c.add(SynthNote(start: 0, duration: 0.7, frequency: m(50), amplitude: 0.3, attack: 0.01, decay: 0.3, release: 0.1))
            peak = 0.62
        case .gold:
            c = canvas(0.24)
            c.add(SynthNote(start: 0, duration: 0.12, frequency: m(96) * p, amplitude: 0.35, attack: 0.001, decay: 0.04))
            c.add(SynthNote(start: 0.05, duration: 0.18, frequency: m(103) * p, amplitude: 0.35, attack: 0.001, decay: 0.06))
            c.add(SynthNote(start: 0.05, duration: 0.1, frequency: m(103) * p * 2.76, amplitude: 0.06, attack: 0.001, decay: 0.03))
            peak = 0.32
        case .recall:
            c = canvas(0.8)
            c.add(SynthNote(start: 0, duration: 0.8, frequency: 300, endFrequency: 1200, sweepTime: 0.7, wave: .triangle,
                            amplitude: 0.3, attack: 0.2, release: 0.15, tremoloRate: 12, tremoloDepth: 0.5))
            c.add(SynthNote(start: 0, duration: 0.8, frequency: 600, endFrequency: 2400, sweepTime: 0.7,
                            amplitude: 0.1, attack: 0.2, release: 0.15, tremoloRate: 12, tremoloDepth: 0.5))
            c.add(SynthNoise(start: 0, duration: 0.8, amplitude: 0.06, attack: 0.3, decay: nil, release: 0.2,
                             lowpassFrom: 10_000, highpass: 4000, seed: 131))
            peak = 0.42
        case .respawn:
            c = canvas(0.65)
            for note in [74.0, 78, 81] {
                c.add(SynthNote(start: 0, duration: 0.62, frequency: m(note), amplitude: 0.25, attack: 0.25, decay: 0.3, release: 0.1))
            }
            c.add(SynthNote(start: 0, duration: 0.62, frequency: m(62), wave: .triangle, amplitude: 0.2, attack: 0.2, decay: 0.3, release: 0.1))
            peak = 0.48
        case .countdown:
            c = canvas(0.16)
            c.add(SynthNote(start: 0, duration: 0.14, frequency: 880, amplitude: 0.6, attack: 0.002, decay: 0.06))
            c.add(SynthNote(start: 0, duration: 0.08, frequency: 1760, amplitude: 0.12, attack: 0.002, decay: 0.03))
            peak = 0.42
        case .victory:
            c = canvas(0.8)
            let notes = [74.0, 78, 81, 86]
            for (i, note) in notes.enumerated() {
                let last = i == notes.count - 1
                c.add(SynthNote(start: Double(i) * 0.08, duration: last ? 0.55 : 0.14, frequency: m(note), wave: .triangle,
                                amplitude: 0.4, attack: 0.003, decay: last ? 0.25 : 0.08, release: last ? 0.1 : 0.03))
            }
            c.add(SynthNote(start: 0.24, duration: 0.55, frequency: m(74), wave: .softSquare, amplitude: 0.15,
                            attack: 0.01, decay: 0.25, release: 0.1, lowpass: 2500))
            peak = 0.58
        case .defeat:
            c = canvas(0.8)
            for (i, note) in [69.0, 65, 62].enumerated() {
                let last = i == 2
                c.add(SynthNote(start: Double(i) * 0.16, duration: last ? 0.48 : 0.3, frequency: m(note), wave: .triangle,
                                amplitude: 0.4, attack: 0.005, decay: last ? 0.25 : 0.12, release: 0.06, lowpass: 2000))
            }
            c.add(SynthNote(start: 0.32, duration: 0.48, frequency: m(50), amplitude: 0.3, attack: 0.01, decay: 0.25, release: 0.08))
            peak = 0.5
        case .announcement:
            c = canvas(0.6)
            c.addBell(start: 0, frequency: m(79), amplitude: 0.4, decay: 0.18)
            c.addBell(start: 0.14, frequency: m(84), amplitude: 0.4, decay: 0.25)
            peak = 0.48
        }
        c.fadeOut(0.006)
        c.normalize(peak: peak)
        return c.left
    }
}

/// BGM のレンダリング結果（スレッド間で受け渡すための素の配列）。
struct RenderedMusic: Sendable {
    var left: [Float]
    var right: [Float]
    var sampleRate: Double
    var loops: Bool
}

enum MusicComposer {
    static let sampleRate: Double = 44_100

    private struct Chord {
        var bass: Double
        var pad: [Double]
        var arp: [Double]
    }

    // D マイナーの和音（MIDI ノート番号）
    private static let dm = Chord(bass: 38, pad: [50, 53, 57], arp: [62, 65, 69, 74])
    private static let bb = Chord(bass: 34, pad: [50, 53, 58], arp: [58, 62, 65, 70])
    private static let f = Chord(bass: 41, pad: [48, 53, 57], arp: [60, 65, 69, 72])
    private static let c = Chord(bass: 36, pad: [48, 52, 55], arp: [60, 64, 67, 72])
    private static let gm = Chord(bass: 43, pad: [50, 55, 58], arp: [62, 67, 70, 74])
    private static let a = Chord(bass: 33, pad: [49, 52, 57], arp: [61, 64, 69, 73])

    private static func m(_ note: Double) -> Double { SynthCanvas.midi(note) }

    static func render(_ track: MusicTrack) -> RenderedMusic {
        let canvas: SynthCanvas
        switch track {
        case .menu: canvas = renderMenu(style: 0)
        case .menuDream: canvas = renderMenu(style: 1)
        case .menuAdventure: canvas = renderMenu(style: 2)
        case .menuAurora: canvas = renderMenu(style: 3)
        case .battle: canvas = renderBattle()
        case .victory: canvas = renderVictory()
        case .defeat: canvas = renderDefeat()
        }
        return RenderedMusic(left: canvas.left, right: canvas.right, sampleRate: canvas.sampleRate, loops: canvas.loop)
    }

    /// 左右にデチューンした 2 声のパッド。
    private static func addPad(_ canvas: inout SynthCanvas, notes: [Double], start: Double, length: Double,
                               amp: Float, attack: Double, release: Double, cutoff: Double) {
        for (i, note) in notes.enumerated() {
            let spread: Float = i % 2 == 0 ? -0.35 : 0.35
            canvas.add(SynthNote(start: start, duration: length + release, frequency: m(note), wave: .triangle,
                                 amplitude: amp, attack: attack, release: release, pan: spread,
                                 lowpass: cutoff, detuneCents: -6))
            canvas.add(SynthNote(start: start, duration: length + release, frequency: m(note),
                                 amplitude: amp, attack: attack, release: release, pan: -spread,
                                 vibratoRate: 0.3, vibratoDepth: 0.0015, detuneCents: 6))
        }
    }

    // MARK: メニュー（84 BPM、16 小節、Dm–B♭–F–C–Dm–B♭–Gm–A を 2 小節ずつ）

    private static func renderMenu(style: Int) -> SynthCanvas {
        let beat = 60.0 / [84.0, 72.0, 98.0, 78.0][style]
        let bar = beat * 4
        let bars = 16
        var main = SynthCanvas(duration: bar * Double(bars), sampleRate: sampleRate, stereo: true, loop: true)
        var arp = SynthCanvas(duration: bar * Double(bars), sampleRate: sampleRate, stereo: true, loop: true)
        let progressions = [[dm, bb, f, c, dm, bb, gm, a], [f, c, dm, bb, f, c, gm, bb],
                            [c, gm, dm, f, c, gm, bb, f], [bb, f, c, dm, bb, f, gm, c]]
        let progression = progressions[style]
        var rng = SplitMix64(seed: 0x4D45_4E55 + UInt64(style)) // 曲ごとに安定した異なる揺らぎ
        let patterns = [[0, 1, 2, 3, 1, 2, 3, 2], [0, 2, 1, 3, 2, 1, 3, 0],
                        [0, 1, 0, 2, 3, 2, 1, 3], [0, 2, 3, 1, 0, 3, 2, 1]]
        let pattern = patterns[style]

        for (s, chord) in progression.enumerated() {
            let start = Double(s) * 2 * bar
            addPad(&main, notes: chord.pad, start: start, length: 2 * bar, amp: 0.05, attack: 1.0, release: 1.4, cutoff: 1800)
            // ベース: 1 拍目と 3 拍目
            for b in 0..<4 {
                let t = start + Double(b) * 2 * beat
                main.add(SynthNote(start: t, duration: 2 * beat + 0.3, frequency: m(chord.bass + 12), amplitude: 0.2,
                                   attack: 0.012, decay: 0.9, release: 0.1))
                main.add(SynthNote(start: t, duration: 2 * beat + 0.3, frequency: m(chord.bass + 12), wave: .triangle,
                                   amplitude: 0.06, attack: 0.012, decay: 0.6, release: 0.1, lowpass: 600))
            }
            // アルペジオ（8 分）
            for step in 0..<16 {
                let t = start + Double(step) * beat / 2
                var note = chord.arp[pattern[step % 8]]
                if step >= 8 && step % 8 == 3 { note += 12 }
                let accent: Float = step % 4 == 0 ? 1.0 : 0.8
                let vel = accent * Float(0.85 + 0.3 * rng.nextDouble())
                let pan: Float = step % 2 == 0 ? -0.3 : 0.3
                arp.add(SynthNote(start: t, duration: 0.9, frequency: m(note), amplitude: 0.1 * vel,
                                  attack: 0.004, decay: 0.28, release: 0.1, pan: pan))
                arp.add(SynthNote(start: t, duration: 0.6, frequency: m(note), wave: .triangle, amplitude: 0.035 * vel,
                                  attack: 0.004, decay: 0.2, release: 0.08, pan: pan, lowpass: 2500))
            }
            // きらめき（高音のベル）
            let sparkleStep = Int(rng.nextDouble() * 16)
            let sparkleNote = chord.arp[Int(rng.nextDouble() * 4) % 4] + 24
            main.addBell(start: start + Double(sparkleStep) * beat / 2, frequency: m(sparkleNote), amplitude: 0.035,
                         decay: 0.6, pan: Float(rng.nextDouble() * 1.2 - 0.6))
        }
        arp.applyDelay(time: beat * 0.75, feedback: 0.38, mix: 0.35)
        main.mix(arp)
        main.normalize(peak: 0.8)
        return main
    }

    // MARK: バトル（128 BPM、16 小節、Dm–B♭–C–A を 2 小節ずつ × 2）

    private static func renderBattle() -> SynthCanvas {
        let beat = 60.0 / 128
        let bar = beat * 4
        let bars = 16
        let step = beat / 2
        var main = SynthCanvas(duration: bar * Double(bars), sampleRate: sampleRate, stereo: true, loop: true)
        var lead = SynthCanvas(duration: bar * Double(bars), sampleRate: sampleRate, stereo: true, loop: true)
        let progression = [dm, bb, c, a, dm, bb, c, a]
        let motifs: [[Double]] = [
            [69, -1, 74, -1, 77, 76, 74, -1, 72, -1, 74, -1, 69, -1, -1, -1],
            [70, -1, 74, -1, 77, -1, 79, 77, 74, -1, 72, -1, 70, -1, -1, -1],
            [72, -1, 76, -1, 79, -1, 76, 74, 72, -1, 74, -1, 76, -1, -1, -1],
            [73, -1, 76, -1, 81, -1, 79, 76, 73, -1, 76, -1, 69, -1, -1, -1],
        ]
        let bassPattern: [Double] = [0, 0, 12, 0, 0, 12, 0, 7]

        for barIndex in 0..<bars {
            let barStart = Double(barIndex) * bar
            let chord = progression[barIndex / 2]
            // キック（4 つ打ち）
            for b in 0..<4 {
                let t = barStart + Double(b) * beat
                main.add(SynthNote(start: t, duration: 0.3, frequency: 120, endFrequency: 45, sweepTime: 0.09,
                                   amplitude: 0.55, attack: 0.001, decay: 0.16, release: 0.03))
                main.add(SynthNoise(start: t, duration: 0.012, amplitude: 0.12, attack: 0.0005, decay: 0.004,
                                    lowpassFrom: 3000, seed: UInt64(barIndex * 8 + b + 1)))
            }
            // スネア（2・4 拍）
            for b in [1, 3] {
                let t = barStart + Double(b) * beat
                main.add(SynthNoise(start: t, duration: 0.22, amplitude: 0.35, attack: 0.001, decay: 0.09, release: 0.03,
                                    lowpassFrom: 7000, highpass: 900, seed: UInt64(1000 + barIndex * 4 + b)))
                main.add(SynthNote(start: t, duration: 0.12, frequency: 200, endFrequency: 150, sweepTime: 0.05, wave: .triangle,
                                   amplitude: 0.22, attack: 0.001, decay: 0.06))
            }
            // 8 小節目・16 小節目の終わりにスネアのフィル
            if barIndex % 8 == 7 {
                for k in 0..<8 {
                    let t = barStart + 2 * beat + Double(k) * beat / 4
                    main.add(SynthNoise(start: t, duration: 0.1, amplitude: 0.12 + Float(k) * 0.025, attack: 0.001, decay: 0.05,
                                        lowpassFrom: 7000, highpass: 900, seed: UInt64(2000 + barIndex * 8 + k)))
                }
            }
            // ハイハット（裏拍、後半は 16 分を追加）
            for k in 0..<8 {
                let t = barStart + Double(k) * step
                if k % 2 == 1 {
                    main.add(SynthNoise(start: t, duration: 0.05, amplitude: 0.1, attack: 0.0005, decay: 0.02,
                                        pan: 0.3, lowpassFrom: 14_000, highpass: 7000, seed: UInt64(3000 + barIndex * 8 + k)))
                }
                if barIndex >= 8 {
                    main.add(SynthNoise(start: t + step / 2, duration: 0.03, amplitude: 0.045, attack: 0.0005, decay: 0.012,
                                        pan: -0.25, lowpassFrom: 14_000, highpass: 8000, seed: UInt64(4000 + barIndex * 8 + k)))
                }
            }
            // ベース（8 分）
            for k in 0..<8 {
                let t = barStart + Double(k) * step
                main.add(SynthNote(start: t, duration: step * 0.9, frequency: m(chord.bass + 12 + bassPattern[k]), wave: .softSaw,
                                   amplitude: 0.22, attack: 0.004, decay: 0.18, release: 0.02, lowpass: 700))
            }
            // 前半: 16 分の細かいアルペジオで推進力を出す
            if barIndex < 8 {
                for k in 0..<16 {
                    let t = barStart + Double(k) * beat / 4
                    let note = chord.arp[k % 4] + (k / 4 % 2 == 1 ? 12 : 0)
                    lead.add(SynthNote(start: t, duration: 0.18, frequency: m(note), amplitude: 0.05,
                                       attack: 0.002, decay: 0.07, release: 0.03, pan: k % 2 == 0 ? -0.25 : 0.25))
                }
            }
            // 和音のパッド（2 小節ごと）
            if barIndex % 2 == 0 {
                addPad(&main, notes: chord.pad.map { $0 + 12 }, start: barStart, length: 2 * bar, amp: 0.028,
                       attack: 0.3, release: 0.5, cutoff: 1500)
            }
        }
        // 後半: リード
        for phrase in 4..<8 {
            let phraseStart = Double(phrase) * 2 * bar
            let motif = motifs[phrase % 4]
            for (k, note) in motif.enumerated() where note > 0 {
                let t = phraseStart + Double(k) * step
                lead.add(SynthNote(start: t, duration: step * 1.6, frequency: m(note), wave: .triangle, amplitude: 0.12,
                                   attack: 0.01, decay: 0.35, release: 0.05, pan: 0.1, vibratoRate: 5.5, vibratoDepth: 0.004,
                                   lowpass: 3200))
                lead.add(SynthNote(start: t, duration: step * 1.6, frequency: m(note), amplitude: 0.06,
                                   attack: 0.01, decay: 0.35, release: 0.05, pan: -0.1))
            }
        }
        lead.applyDelay(time: beat * 0.75, feedback: 0.3, mix: 0.25)
        main.mix(lead)
        main.normalize(peak: 0.85)
        return main
    }

    // MARK: スティンガー

    private static func renderVictory() -> SynthCanvas {
        var s = SynthCanvas(duration: 5.0, sampleRate: sampleRate, stereo: true)
        for (i, note) in [74.0, 78, 81].enumerated() {
            let t = Double(i) * 0.15
            s.add(SynthNote(start: t, duration: 0.3, frequency: m(note), wave: .triangle, amplitude: 0.3,
                            attack: 0.004, decay: 0.15, release: 0.05, pan: -0.15))
            s.add(SynthNote(start: t, duration: 0.3, frequency: m(note), wave: .softSquare, amplitude: 0.1,
                            attack: 0.004, decay: 0.12, release: 0.05, pan: 0.15, lowpass: 3000))
        }
        s.add(SynthNote(start: 0.45, duration: 2.4, frequency: m(86), wave: .triangle, amplitude: 0.32,
                        attack: 0.01, decay: 0.9, release: 0.3, vibratoRate: 5, vibratoDepth: 0.004))
        s.add(SynthNote(start: 0.45, duration: 2.2, frequency: m(81), amplitude: 0.16, attack: 0.02, decay: 0.8, release: 0.3, pan: -0.3))
        s.add(SynthNote(start: 0.45, duration: 2.2, frequency: m(78), amplitude: 0.14, attack: 0.02, decay: 0.8, release: 0.3, pan: 0.3))
        addPad(&s, notes: [62, 66, 69, 74], start: 0.45, length: 2.8, amp: 0.05, attack: 0.3, release: 1.5, cutoff: 2000)
        s.add(SynthNote(start: 0.45, duration: 2.6, frequency: m(38), amplitude: 0.3, attack: 0.01, decay: 1.0, release: 0.3))
        for (i, note) in [86.0, 90, 93, 98].enumerated() {
            s.addBell(start: 0.5 + Double(i) * 0.1, frequency: m(note), amplitude: 0.06, decay: 0.5, pan: Float(i) * 0.2 - 0.3)
        }
        s.add(SynthNoise(start: 0.3, duration: 2.0, amplitude: 0.08, attack: 0.15, decay: 0.8, release: 0.3,
                         lowpassFrom: 12_000, highpass: 5000, seed: 777))
        s.applyDelay(time: 0.3, feedback: 0.3, mix: 0.2)
        s.fadeOut(1.0)
        s.normalize(peak: 0.8)
        return s
    }

    private static func renderDefeat() -> SynthCanvas {
        var s = SynthCanvas(duration: 5.0, sampleRate: sampleRate, stereo: true)
        let melody: [(t: Double, note: Double, len: Double, decay: Double)] = [
            (0, 69, 0.6, 0.5), (0.55, 65, 0.6, 0.5), (1.1, 62, 0.7, 0.5), (1.75, 61, 0.5, 0.4), (2.2, 62, 2.5, 1.2),
        ]
        for n in melody {
            s.add(SynthNote(start: n.t, duration: n.len, frequency: m(n.note), wave: .triangle, amplitude: 0.28,
                            attack: 0.02, decay: n.decay, release: 0.15, lowpass: 1800))
        }
        addPad(&s, notes: [50, 53, 57], start: 0, length: 3.0, amp: 0.05, attack: 0.8, release: 1.8, cutoff: 1200)
        s.add(SynthNote(start: 0, duration: 2.2, frequency: m(38), amplitude: 0.25, attack: 0.02, decay: 1.2, release: 0.2))
        s.add(SynthNote(start: 2.2, duration: 2.6, frequency: m(38), amplitude: 0.25, attack: 0.02, decay: 1.5, release: 0.3))
        s.applyDelay(time: 0.4, feedback: 0.35, mix: 0.25)
        s.fadeOut(1.2)
        s.normalize(peak: 0.7)
        return s
    }
}
