import Foundation
import Accelerate

// 担当: app-services
// 手続き生成オーディオの DSP 部品（AVFoundation 非依存の値型。バックグラウンドスレッドで使える）。
// SynthCanvas に音符・ノイズを書き込み、エフェクト・正規化してから AVAudioPCMBuffer へ変換する。
// loop = true のキャンバスは末尾をはみ出した書き込み（リリース・ディレイの残響）を先頭へ回り込ませ、継ぎ目なくループさせる。
// 内側のループは Accelerate（vDSP / vForce）でベクトル化している（Debug ビルドでも数十倍遅くならないように）。

enum SynthWave: Sendable {
    case sine
    case triangle
    /// 奇数倍音 4 本の矩形波（耳に痛い高域を持たない）。
    case softSquare
    /// 倍音 5 本のノコギリ波。
    case softSaw
}

/// 1 音の指定。
struct SynthNote: Sendable {
    var start: Double
    var duration: Double
    var frequency: Double
    /// 指定時は sweepTime（省略時は duration）かけて指数的に移行する。
    var endFrequency: Double? = nil
    var sweepTime: Double? = nil
    var wave: SynthWave = .sine
    var amplitude: Float = 0.3
    var attack: Double = 0.005
    /// アタック後の指数減衰の時定数（秒）。nil = 減衰なし（持続）。
    var decay: Double? = nil
    /// 終端のフェードアウト（クリック防止）。
    var release: Double = 0.02
    /// −1（左）〜 +1（右）。モノラルキャンバスでは無視。
    var pan: Float = 0
    var vibratoRate: Double = 0
    /// 周波数比（0.01 = ±1%）。
    var vibratoDepth: Double = 0
    var tremoloRate: Double = 0
    var tremoloDepth: Float = 0
    /// 1 次ローパスのカットオフ（Hz）。
    var lowpass: Double? = nil
    var detuneCents: Double = 0
}

/// ノイズ（打楽器・風切り音・きらめき）。
struct SynthNoise: Sendable {
    var start: Double
    var duration: Double
    var amplitude: Float
    var attack: Double = 0.002
    var decay: Double? = 0.05
    var release: Double = 0.01
    var pan: Float = 0
    /// ローパスのカットオフ（lowpassTo 指定時は直線的に移行）。
    var lowpassFrom: Double = 9000
    var lowpassTo: Double? = nil
    /// 1 次ハイパスのカットオフ。
    var highpass: Double? = nil
    /// ノイズ表の読み出し位置（音ごとに変えると同じ波形の繰り返しにならない）。
    var seed: UInt64 = 0x5EED
}

struct SynthCanvas: Sendable {
    let sampleRate: Double
    let stereo: Bool
    let loop: Bool
    private(set) var left: [Float]
    private(set) var right: [Float]

    var frameCount: Int { left.count }
    var duration: Double { Double(frameCount) / sampleRate }

    init(duration: Double, sampleRate: Double = 44_100, stereo: Bool, loop: Bool = false) {
        self.sampleRate = sampleRate
        self.stereo = stereo
        self.loop = loop
        let n = max(1, Int((duration * sampleRate).rounded()))
        left = [Float](repeating: 0, count: n)
        right = stereo ? [Float](repeating: 0, count: n) : []
    }

    static func midi(_ note: Double) -> Double { 440 * pow(2, (note - 69) / 12) }

    /// 等パワーのパン係数。
    static func panGains(_ pan: Float) -> (Float, Float) {
        let p = Double(max(-1, min(1, pan)))
        let angle = (p + 1) * .pi / 4
        return (Float(cos(angle)), Float(sin(angle)))
    }

    // MARK: - 発音

    mutating func add(_ n: SynthNote) {
        let sr = sampleRate
        let count = Int((n.duration * sr).rounded())
        guard count > 1, n.frequency > 0 else { return }
        let len = vDSP_Length(count)
        var n32 = Int32(count)
        let detune = pow(2, n.detuneCents / 1200)
        let f0 = n.frequency * detune

        // 1 サンプルあたりの位相増分（周期単位）
        var inc = [Double](repeating: f0 / sr, count: count)
        if let target = n.endFrequency, target > 0 {
            let f1 = target * detune
            let sweepN = min(count, max(1, Int((n.sweepTime ?? n.duration) * sr)))
            var s = 0.0
            var step = log(f1 / f0) / Double(sweepN)
            var e = [Double](repeating: 0, count: sweepN)
            vDSP_vrampD(&s, &step, &e, 1, vDSP_Length(sweepN))
            var sweep32 = Int32(sweepN)
            var curve = [Double](repeating: 0, count: sweepN)
            vvexp(&curve, e, &sweep32)
            var scale = f0 / sr
            vDSP_vsmulD(curve, 1, &scale, &inc, 1, vDSP_Length(sweepN))
            if sweepN < count {
                for i in sweepN..<count { inc[i] = f1 / sr }
            }
        }
        if n.vibratoDepth > 0 && n.vibratoRate > 0 {
            var lfo = Self.sineLFO(count: count, rate: n.vibratoRate, sampleRate: sr)
            var depth = n.vibratoDepth
            var one = 1.0
            lfo.withPointer { p, _ in vDSP_vsmsaD(p, 1, &depth, &one, p, 1, len) }
            inc.withPointer { p, _ in vDSP_vmulD(p, 1, lfo, 1, p, 1, len) }
        }

        // 位相（累積和）→ 小数部
        var phase = [Double](repeating: 0, count: count)
        var unit = 1.0
        vDSP_vrsumD(inc, 1, &unit, &phase, 1, len)
        var whole = [Double](repeating: 0, count: count)
        vvfloor(&whole, phase, &n32)
        phase.withPointer { p, _ in vDSP_vsubD(whole, 1, p, 1, p, 1, len) }
        var x = [Float](repeating: 0, count: count)
        vDSP_vdpsp(phase, 1, &x, 1, len)

        var out = Self.oscillate(n.wave, phase: x)
        if let cutoff = n.lowpass {
            out = Self.onePoleLowpass(out, cutoff: cutoff, sampleRate: sr)
        }
        var env = Self.envelope(count: count, attack: n.attack, decay: n.decay, release: n.release, sampleRate: sr)
        if n.tremoloDepth > 0 && n.tremoloRate > 0 {
            let lfo = Self.sineLFO(count: count, rate: n.tremoloRate, sampleRate: sr)
            var lfoF = [Float](repeating: 0, count: count)
            vDSP_vdpsp(lfo, 1, &lfoF, 1, len)
            // 1 − d/2 − (d/2)·sin
            var scale = -n.tremoloDepth / 2
            var offset = 1 - n.tremoloDepth / 2
            lfoF.withPointer { p, _ in vDSP_vsmsa(p, 1, &scale, &offset, p, 1, len) }
            env.withPointer { p, _ in vDSP_vmul(p, 1, lfoF, 1, p, 1, len) }
        }
        var amp = n.amplitude
        out.withPointer { p, _ in
            vDSP_vmul(p, 1, env, 1, p, 1, len)
            vDSP_vsmul(p, 1, &amp, p, 1, len)
        }
        accumulate(out, at: Int((n.start * sr).rounded()), pan: n.pan)
    }

    mutating func add(_ n: SynthNoise) {
        let sr = sampleRate
        let count = Int((n.duration * sr).rounded())
        guard count > 1 else { return }
        let len = vDSP_Length(count)
        var x = Self.noise(count: count, seed: n.seed)
        if let to = n.lowpassTo {
            x = Self.onePoleLowpass(x, sampleRate: sr) { t in n.lowpassFrom + (to - n.lowpassFrom) * t }
        } else {
            x = Self.onePoleLowpass(x, cutoff: n.lowpassFrom, sampleRate: sr)
        }
        if let hp = n.highpass {
            let low = Self.onePoleLowpass(x, cutoff: hp, sampleRate: sr)
            x.withPointer { p, _ in vDSP_vsub(low, 1, p, 1, p, 1, len) }
        }
        let env = Self.envelope(count: count, attack: n.attack, decay: n.decay, release: n.release, sampleRate: sr)
        var amp = n.amplitude
        x.withPointer { p, _ in
            vDSP_vmul(p, 1, env, 1, p, 1, len)
            vDSP_vsmul(p, 1, &amp, p, 1, len)
        }
        accumulate(x, at: Int((n.start * sr).rounded()), pan: n.pan)
    }

    /// ベル（非整数倍音の減衰サイン）。
    mutating func addBell(start: Double, frequency: Double, amplitude: Float, decay: Double, pan: Float = 0) {
        let partials: [(ratio: Double, amp: Float, decay: Double)] = [(1, 1, 1), (2.0, 0.3, 0.7), (2.76, 0.18, 0.5), (5.4, 0.07, 0.3)]
        for p in partials where frequency * p.ratio < sampleRate * 0.45 {
            add(SynthNote(start: start, duration: decay * p.decay * 5 + 0.02, frequency: frequency * p.ratio,
                          amplitude: amplitude * p.amp, attack: 0.002, decay: decay * p.decay, release: 0.02, pan: pan))
        }
    }

    /// 他のキャンバスを加算する（同じレートであること）。
    mutating func mix(_ other: SynthCanvas, gain: Float = 1) {
        let n = vDSP_Length(min(frameCount, other.frameCount))
        var g = gain
        left.withPointer { p, _ in vDSP_vsma(other.left, 1, &g, p, 1, p, 1, n) }
        guard stereo else { return }
        let src = other.stereo ? other.right : other.left
        right.withPointer { p, _ in vDSP_vsma(src, 1, &g, p, 1, p, 1, n) }
    }

    /// 書き込み（ループ時は先頭へ回り込む）。
    private mutating func accumulate(_ src: [Float], at start: Int, pan: Float) {
        let n = frameCount
        var (gl, gr) = stereo ? Self.panGains(pan) : (1, 1)
        var k = max(0, -start)
        var pos = max(0, start)
        let wrap = loop
        src.withUnsafeBufferPointer { s in
            guard let base = s.baseAddress else { return }
            while k < s.count {
                if pos >= n {
                    guard wrap else { return }
                    pos %= n
                }
                let chunk = min(s.count - k, n - pos)
                left.withUnsafeMutableBufferPointer { l in
                    vDSP_vsma(base + k, 1, &gl, l.baseAddress! + pos, 1, l.baseAddress! + pos, 1, vDSP_Length(chunk))
                }
                if stereo {
                    right.withUnsafeMutableBufferPointer { r in
                        vDSP_vsma(base + k, 1, &gr, r.baseAddress! + pos, 1, r.baseAddress! + pos, 1, vDSP_Length(chunk))
                    }
                }
                k += chunk
                pos += chunk
            }
        }
    }

    // MARK: - エフェクト・仕上げ

    /// フィードバック・ディレイ（右チャンネルは 0.75 倍の遅延で広がりを出す）。ループ時は残響を先頭へ回す。
    mutating func applyDelay(time: Double, feedback: Float, mix: Float) {
        let fb = max(0, min(0.9, feedback))
        Self.delay(&left, samples: max(1, Int(time * sampleRate)), feedback: fb, mix: mix, loop: loop)
        if stereo {
            Self.delay(&right, samples: max(1, Int(time * 0.75 * sampleRate)), feedback: fb, mix: mix, loop: loop)
        }
    }

    /// wet[i] = x[i−d] + fb·wet[i−d] を d サンプルずつのブロックで計算する。
    private static func delay(_ x: inout [Float], samples d: Int, feedback: Float, mix: Float, loop: Bool) {
        let n = x.count
        guard d < n else { return }
        var wet = [Float](repeating: 0, count: n)
        var fb = feedback
        // ループ時は 2 周して末尾の残響を先頭へ行き渡らせる
        let passes = loop ? 2 : 1
        x.withUnsafeBufferPointer { src in
            wet.withUnsafeMutableBufferPointer { w in
                let sp = src.baseAddress!
                let wp = w.baseAddress!
                for _ in 0..<passes {
                    var i = 0
                    while i < n {
                        let chunk = min(d, n - i)
                        if i >= d {
                            vDSP_vsma(wp + (i - d), 1, &fb, sp + (i - d), 1, wp + i, 1, vDSP_Length(chunk))
                        } else if loop {
                            // 先頭ブロックは末尾ブロックから続く
                            let j = n - d + i
                            vDSP_vsma(wp + j, 1, &fb, sp + j, 1, wp + i, 1, vDSP_Length(chunk))
                        }
                        i += chunk
                    }
                }
            }
        }
        var m = mix
        x.withPointer { p, len in vDSP_vsma(wet, 1, &m, p, 1, p, 1, len) }
    }

    /// 最大振幅を peak に揃える。
    mutating func normalize(peak: Float) {
        var m: Float = 0
        vDSP_maxmgv(left, 1, &m, vDSP_Length(frameCount))
        if stereo {
            var r: Float = 0
            vDSP_maxmgv(right, 1, &r, vDSP_Length(frameCount))
            m = max(m, r)
        }
        guard m > 0.000_01, m.isFinite else { return }
        var g = peak / m
        left.withPointer { p, len in vDSP_vsmul(p, 1, &g, p, 1, len) }
        if stereo { right.withPointer { p, len in vDSP_vsmul(p, 1, &g, p, 1, len) } }
    }

    /// 末尾を直線的にフェードアウト（非ループ用）。
    mutating func fadeOut(_ seconds: Double) {
        let n = min(frameCount, max(1, Int(seconds * sampleRate)))
        var start: Float = 1
        var step: Float = -1 / Float(n)
        var ramp = [Float](repeating: 0, count: n)
        vDSP_vramp(&start, &step, &ramp, 1, vDSP_Length(n))
        let offset = frameCount - n
        left.withUnsafeMutableBufferPointer { l in
            let p = l.baseAddress! + offset
            vDSP_vmul(p, 1, ramp, 1, p, 1, vDSP_Length(n))
        }
        if stereo {
            right.withUnsafeMutableBufferPointer { r in
                let p = r.baseAddress! + offset
                vDSP_vmul(p, 1, ramp, 1, p, 1, vDSP_Length(n))
            }
        }
    }

    // MARK: - 部品

    /// 波形（x = 位相の小数部 0..<1）。
    private static func oscillate(_ wave: SynthWave, phase x: [Float]) -> [Float] {
        let count = x.count
        let len = vDSP_Length(count)
        var n32 = Int32(count)
        var out = [Float](repeating: 0, count: count)
        switch wave {
        case .triangle:
            // 1 − 4·|x − 0.5|
            var half: Float = -0.5
            var scale: Float = -4
            var one: Float = 1
            out.withPointer { p, _ in
                vDSP_vsadd(x, 1, &half, p, 1, len)
                vDSP_vabs(p, 1, p, 1, len)
                vDSP_vsmsa(p, 1, &scale, &one, p, 1, len)
            }
        case .sine, .softSquare, .softSaw:
            let harmonics: [(k: Float, gain: Float)]
            switch wave {
            case .sine: harmonics = [(1, 1)]
            case .softSquare: harmonics = [(1, 0.9), (3, 0.3), (5, 0.18), (7, 0.128_571)]
            default: harmonics = [(1, 0.55), (2, 0.275), (3, 0.183_333), (4, 0.1375), (5, 0.11)]
            }
            var t = [Float](repeating: 0, count: count)
            var s = [Float](repeating: 0, count: count)
            for h in harmonics {
                var w = 2 * Float.pi * h.k
                vDSP_vsmul(x, 1, &w, &t, 1, len)
                vvsinf(&s, t, &n32)
                var g = h.gain
                out.withPointer { p, _ in vDSP_vsma(s, 1, &g, p, 1, p, 1, len) }
            }
        }
        return out
    }

    /// アタック（直線）→ 指数減衰（または持続）→ 終端のリリース（直線）。
    private static func envelope(count: Int, attack: Double, decay: Double?, release: Double, sampleRate sr: Double) -> [Float] {
        var env = [Float](repeating: 1, count: count)
        let attackN = min(count, max(1, Int(attack * sr)))
        var s: Float = 0
        var step: Float = 1 / Float(attackN)
        vDSP_vramp(&s, &step, &env, 1, vDSP_Length(attackN))
        if let tau = decay, count > attackN {
            let rest = count - attackN
            var k = Float(-1 / (max(0.001, tau) * sr))
            var start = k
            var expo = [Float](repeating: 0, count: rest)
            vDSP_vramp(&start, &k, &expo, 1, vDSP_Length(rest))
            var r32 = Int32(rest)
            env.withUnsafeMutableBufferPointer { e in
                vvexpf(e.baseAddress! + attackN, expo, &r32)
            }
        }
        let releaseN = min(count, max(1, Int(release * sr)))
        var one: Float = 1
        var down: Float = -1 / Float(releaseN)
        var ramp = [Float](repeating: 0, count: releaseN)
        vDSP_vramp(&one, &down, &ramp, 1, vDSP_Length(releaseN))
        env.withUnsafeMutableBufferPointer { e in
            let p = e.baseAddress! + (count - releaseN)
            vDSP_vmul(p, 1, ramp, 1, p, 1, vDSP_Length(releaseN))
        }
        return env
    }

    /// sin(2π·rate·i/sr)。
    private static func sineLFO(count: Int, rate: Double, sampleRate sr: Double) -> [Double] {
        var start = 0.0
        var step = 2 * .pi * rate / sr
        var ph = [Double](repeating: 0, count: count)
        vDSP_vrampD(&start, &step, &ph, 1, vDSP_Length(count))
        var out = [Double](repeating: 0, count: count)
        var n32 = Int32(count)
        vvsin(&out, ph, &n32)
        return out
    }

    /// 1 次ローパス y[n] = a·x[n] + (1−a)·y[n−1]（vDSP の 2 次 IIR で計算）。
    private static func onePoleLowpass(_ x: [Float], cutoff: Double, sampleRate sr: Double) -> [Float] {
        var state: Float = 0
        return onePoleBlock(x, from: 0, count: x.count, cutoff: cutoff, sampleRate: sr, state: &state)
    }

    /// カットオフが時間変化する 1 次ローパス（128 サンプルごとに係数を更新）。t = 0...1。
    private static func onePoleLowpass(_ x: [Float], sampleRate sr: Double, cutoffAt: (Double) -> Double) -> [Float] {
        var out = [Float](repeating: 0, count: x.count)
        var state: Float = 0
        var i = 0
        let block = 128
        while i < x.count {
            let n = min(block, x.count - i)
            let t = (Double(i) + Double(n) / 2) / Double(x.count)
            let y = onePoleBlock(x, from: i, count: n, cutoff: cutoffAt(t), sampleRate: sr, state: &state)
            out.replaceSubrange(i..<(i + n), with: y)
            i += n
        }
        return out
    }

    private static func onePoleBlock(_ x: [Float], from start: Int, count n: Int, cutoff: Double, sampleRate sr: Double,
                                     state: inout Float) -> [Float] {
        let fc = min(max(20, cutoff), sr * 0.45)
        let a = Float(1 - exp(-2 * .pi * fc / sr))
        let coeffs: [Float] = [a, 0, 0, -(1 - a), 0]
        var input = [Float](repeating: 0, count: n + 2)
        input.replaceSubrange(2..<(n + 2), with: x[start..<(start + n)])
        var output = [Float](repeating: 0, count: n + 2)
        output[1] = state
        vDSP_deq22(input, 1, coeffs, &output, 1, vDSP_Length(n))
        state = output[n + 1]
        return Array(output[2...])
    }

    /// 白色ノイズ表（xorshift で一度だけ生成）。
    private static let noiseTable: [Float] = {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        return (0..<(1 << 17)).map { _ in
            state ^= state >> 12
            state ^= state << 25
            state ^= state >> 27
            let r = state &* 0x2545_F491_4F6C_DD1D
            return Float(Double(r >> 11) / 9_007_199_254_740_992.0 * 2 - 1)
        }
    }()

    private static func noise(count: Int, seed: UInt64) -> [Float] {
        let table = noiseTable
        var out = [Float](repeating: 0, count: count)
        var pos = Int((seed &* 0x9E37_79B9) % UInt64(table.count))
        var k = 0
        while k < count {
            let chunk = min(count - k, table.count - pos)
            out.replaceSubrange(k..<(k + chunk), with: table[pos..<(pos + chunk)])
            k += chunk
            pos = 0
        }
        return out
    }
}

private extension Array {
    /// 自身を入出力に使う vDSP のインプレース演算用（同じ配列を読み書き両方に渡すと排他アクセス違反になるため）。
    mutating func withPointer(_ body: (UnsafeMutablePointer<Element>, vDSP_Length) -> Void) {
        let n = vDSP_Length(count)
        withUnsafeMutableBufferPointer { b in
            guard let p = b.baseAddress else { return }
            body(p, n)
        }
    }
}
