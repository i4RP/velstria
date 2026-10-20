import Foundation
import VelstriaCore

// 担当: app-services
// 合成の BGM の「楽譜」（SynthCanvas への書き込みで作る）。効果音の合成は 2026-10-20 に外した（効果音はすべて録音のファイル。
// AudioFiles。ユーザー指示: 合成のピヨピヨした音をやめる。ファイルが無い効果音は鳴らさない）。
// BGM: メニュー（D マイナーの穏やかなパッド + アルペジオ、84 BPM・16 小節ループ）、
//      バトル（D マイナー 128 BPM の 4 つ打ち・8 分ベース・後半にリード、16 小節ループ）、
//      勝利 / 敗北のスティンガー（約 5 秒・ループなし）。

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
        // ファイルの曲（AudioFiles.music）が無い時の代わり
        case .menuLegend: canvas = renderMenu(style: 2)
        case .menuFantasia: canvas = renderMenu(style: 3)
        case .menuJourney: canvas = renderMenu(style: 1)
        case .lobby, .result: canvas = renderMenu(style: 0)
        case .draft, .draftTense, .loading: canvas = renderBattle()
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
