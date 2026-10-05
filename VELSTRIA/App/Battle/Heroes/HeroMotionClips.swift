import Foundation
import os
import simd

// 担当: hero-models。モーションキャプチャ由来の区間回転クリップ（docs/HERO_MOTION.md）の読み込みと補間。
// App/Resources/Heroes/HeroMotionClips.json を 1 度だけ読み、全クリップの回転・腰の位置を平坦な配列で持つ。
// 毎フレームの sample はヒープ確保をしない（配列の添字と値型だけ）。ファイルが無い・壊れている時は空のライブラリ
// （どのヒーローも手続きアニメーションのまま）。

private let motionLog = Logger(subsystem: "com.bitcoinpay.velstria", category: "HeroMotion")

/// クリップの打撃で振る手（武器の軌跡・通常攻撃の発射位置）。
enum HeroStrikeHand: Equatable {
    case right, left, both
}

/// クリップ 1 本の情報。回転・腰の位置はライブラリの平坦な配列の rotBase / rootBase から frames 分。
struct HeroMotionClip {
    let name: String
    let frames: Int
    let fps: Float
    let loop: Bool
    /// 腰の水平移動の倍率（0〜1。ヒーローの位置そのものはシミュレーションが決める）。
    let rootXZ: Float
    /// 打撃・発射の瞬間（フレーム、先頭から。小数可）。
    let impact: Float?
    /// 弓を離す等（フレーム）。
    let release: Float?
    /// 戻りの終わり（フレーム）。省略時は最終フレーム。
    let end: Float
    let rotBase: Int
    let rootBase: Int
    /// 打撃が武器・拳の近接の振り（武器の軌跡を出す）。JSON の "melee"、無ければ名前で決める（isMeleeName）。
    var melee = false
    /// 打撃で振る手。ライブラリの読み込み時に前腕の角速度から決める（HeroMotionLibrary.measureStrikeHand）。
    var strikeHand: HeroStrikeHand = .right

    /// 武器を振っている区間: 打撃の前 swingLead 秒〜後 swingTail 秒（クリップ時刻。再生速度に比例して実時間は縮む）。
    static let swingLead: Float = 0.18
    static let swingTail: Float = 0.06
    /// 左右の前腕の角速度の比がこれを超えれば速い側の片手で打つ、超えなければ両手。
    static let strikeHandRatio: Float = 1.5

    /// 名前の頭（最初の "_" まで）が詠唱・射撃・投擲・回避なら近接でない。それ以外（剣・二刀・拳・突き・跳び叩き等）は近接。
    static func isMeleeName(_ name: String) -> Bool {
        let head = name.split(separator: "_", maxSplits: 1).first.map(String.init) ?? name
        return !["cast", "bow", "gun", "javelin", "dodge"].contains(head)
    }

    /// 1 周の長さ（秒）。ループは最終フレーム → 先頭の 1 フレーム分を含む。
    var duration: Float { loop ? Float(frames) / fps : Float(max(0, frames - 1)) / fps }
    /// 打撃の時刻（秒）。impact が無ければ release、どちらも無ければ 40% の位置（通常攻撃の同期に使う）。
    var impactTime: Float { (impact ?? release ?? 0.4 * Float(max(0, frames - 1))) / fps }
    /// 再生の終わり（秒）。ループは 1 周。
    var endTime: Float { loop ? duration : min(end, Float(max(0, frames - 1))) / fps }
}

/// 読み込み済みのクリップ一式（不変。スレッド間で共有してよい）。
final class HeroMotionLibrary: @unchecked Sendable {
    static let empty = HeroMotionLibrary(clips: [], rot: [], root: [])

    let clips: [HeroMotionClip]
    /// フレーム × 区間（HeroSegmentRotations の順）の回転。
    private let rot: [simd_quatf]
    /// フレームごとの腰の位置（脚の長さ単位、rootXZ は掛けていない）。
    private let root: [V3]
    private let byName: [String: Int]

    init(clips: [HeroMotionClip], rot: [simd_quatf], root: [V3]) {
        var list = clips
        for i in list.indices { list[i].strikeHand = Self.measureStrikeHand(list[i], rot: rot) }
        self.clips = list
        self.rot = rot
        self.root = root
        var byName: [String: Int] = [:]
        for (i, c) in clips.enumerated() where byName[c.name] == nil { byName[c.name] = i }
        self.byName = byName
    }

    var isEmpty: Bool { clips.isEmpty }

    /// 名前 → クリップの添字（無ければ nil = 手続きへ戻す）。
    func index(of name: String) -> Int? { byName[name] }

    /// 時刻 t（秒、クリップ先頭から）の区間回転と腰の位置（脚の長さ単位、rootXZ 適用前）。
    /// フレーム間は slerp / 線形補間。ループは末尾 → 先頭へ折り返し、非ループは両端で止める（負の時刻は先頭）。
    func sample(_ clip: Int, time t: Float, into q: inout HeroSegmentRotations, root r: inout V3) {
        let c = clips[clip]
        let n = c.frames
        guard n > 0 else { return }
        var f = t * c.fps
        let i0: Int, i1: Int
        if c.loop {
            f = f.truncatingRemainder(dividingBy: Float(n))
            if f < 0 { f += Float(n) }
            if !(f.isFinite) { f = 0 }
            i0 = min(n - 1, Int(f))
            i1 = i0 + 1 < n ? i0 + 1 : 0
        } else {
            f = min(max(f.isFinite ? f : 0, 0), Float(n - 1))
            i0 = min(n - 1, Int(f))
            i1 = min(n - 1, i0 + 1)
        }
        let a = f - Float(i0)
        let b0 = c.rotBase + i0 * HeroSegmentRotations.count
        let b1 = c.rotBase + i1 * HeroSegmentRotations.count
        for s in 0..<HeroSegmentRotations.count {
            q[s] = a <= 0 ? rot[b0 + s] : simd_slerp(rot[b0 + s], rot[b1 + s], a)
        }
        let r0 = root[c.rootBase + i0], r1 = root[c.rootBase + i1]
        r = r0 + (r1 - r0) * a
    }

    /// 打撃で振る手: 武器を振っている区間（打撃の前 swingLead 〜後 swingTail 秒）の左右の前腕の角速度（胴に対する回転の
    /// 中心差分の平均）を比べ、strikeHandRatio 倍より速い側の片手、どちらでもなければ両手。胴に対して測るのは、
    /// 体のひねり・回転は左右の腕を同じだけ回し、打つ腕の見分けを鈍らせるため（hook_l の左・uppercut_r の右が分かれる）。
    static func measureStrikeHand(_ c: HeroMotionClip, rot: [simd_quatf]) -> HeroStrikeHand {
        let n = c.frames, stride = HeroSegmentRotations.count
        guard n >= 2, c.rotBase >= 0, c.rotBase + n * stride <= rot.count else { return .right }
        // 区間の添字（HeroSegmentRotations.names の順）
        let torso = 1, foreArmR = 4, foreArmL = 7
        let impact = c.impactTime * c.fps
        let lo = max(0, Int((impact - HeroMotionClip.swingLead * c.fps).rounded(.down)))
        let hi = min(n - 1, Int((impact + HeroMotionClip.swingTail * c.fps).rounded(.up)))
        guard lo <= hi else { return .right }
        func arm(_ f: Int, _ s: Int) -> simd_quatf {
            let b = c.rotBase + f * stride
            return rot[b + torso].inverse * rot[b + s]
        }
        // 差の回転の角度。acos(内積) は小さな角度で丸めの誤差が大きいので atan2 で求める
        func angle(_ a: simd_quatf, _ b: simd_quatf) -> Float {
            let d = a.inverse * b
            return 2 * atan2(simd_length(d.imag), abs(d.real))
        }
        var right: Float = 0, left: Float = 0, count: Float = 0
        for f in lo...hi {
            let f0 = max(0, f - 1), f1 = min(n - 1, f + 1)
            guard f1 > f0 else { continue }
            let dt = Float(f1 - f0) / c.fps
            right += angle(arm(f0, foreArmR), arm(f1, foreArmR)) / dt
            left += angle(arm(f0, foreArmL), arm(f1, foreArmL)) / dt
            count += 1
        }
        // どちらの腕も胴に対してほぼ止まっている（平均 0.1 rad/s 未満）なら既定の右
        if count == 0 || max(right, left) < 0.1 * count { return .right }
        if left > right * HeroMotionClip.strikeHandRatio { return .left }
        if right > left * HeroMotionClip.strikeHandRatio { return .right }
        return .both
    }

    /// 値で返す版（テスト・ツール用）。
    func sample(_ clip: Int, time t: Float) -> (HeroSegmentRotations, V3) {
        var q = HeroSegmentRotations()
        var r = V3.zero
        sample(clip, time: t, into: &q, root: &r)
        return (q, r)
    }
}

// MARK: - デコード

extension HeroMotionLibrary {
    enum DecodeError: Error, CustomStringConvertible {
        case notObject
        case unsupportedVersion(Int)
        case missingSegment(String)
        case noClips

        var description: String {
            switch self {
            case .notObject: return "JSON の最上位がオブジェクトでない"
            case .unsupportedVersion(let v): return "未対応の version \(v)"
            case .missingSegment(let s): return "segments に \(s) が無い"
            case .noClips: return "clips が無い"
            }
        }
    }

    /// HeroMotionClips.json（docs/HERO_MOTION.md）をデコードする。全体の形が違えば throw、
    /// クリップ単位の不備（配列の長さ違い等）はそのクリップだけ落とす（落とした名前は skipped に入れる）。
    static func decode(_ data: Data, skipped: inout [String]) throws -> HeroMotionLibrary {
        guard let top = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw DecodeError.notObject }
        if let v = (top["version"] as? NSNumber)?.intValue, v != 1 { throw DecodeError.unsupportedVersion(v) }
        let fps = (top["fps"] as? NSNumber)?.floatValue ?? 30
        // ファイルの区間の並び → 実行時の並び（同じ順なら恒等）。未知の区間は読み捨てる
        let names = HeroSegmentRotations.names
        let fileSegments = (top["segments"] as? [String]) ?? names
        var map = [Int](repeating: -1, count: names.count)
        for (k, name) in names.enumerated() {
            guard let i = fileSegments.firstIndex(of: name) else { throw DecodeError.missingSegment(name) }
            map[k] = i
        }
        let stride = fileSegments.count
        guard let list = top["clips"] as? [[String: Any]] else { throw DecodeError.noClips }

        var clips: [HeroMotionClip] = []
        var rot: [simd_quatf] = []
        var root: [V3] = []
        var seen = Set<String>()
        func floats(_ v: Any?) -> [Float]? {
            guard let a = v as? [Any] else { return nil }
            var out = [Float]()
            out.reserveCapacity(a.count)
            for x in a {
                guard let n = x as? NSNumber else { return nil }
                out.append(n.floatValue)
            }
            return out
        }
        for c in list {
            guard let name = c["name"] as? String, !name.isEmpty, !seen.contains(name) else {
                skipped.append((c["name"] as? String) ?? "?")
                continue
            }
            let clipFPS = (c["fps"] as? NSNumber)?.floatValue ?? fps
            guard let r = floats(c["rot"]), clipFPS > 0, clipFPS.isFinite else {
                skipped.append(name)
                continue
            }
            let frames = (c["frames"] as? NSNumber)?.intValue ?? r.count / max(1, stride * 4)
            let rootValues = floats(c["root"]) ?? [Float](repeating: 0, count: max(0, frames) * 3)
            guard frames > 0, r.count == frames * stride * 4, rootValues.count == frames * 3,
                  r.allSatisfy(\.isFinite), rootValues.allSatisfy(\.isFinite) else {
                skipped.append(name)
                continue
            }
            let events = c["events"] as? [String: Any] ?? [:]
            func event(_ key: String) -> Float? {
                guard let v = (events[key] as? NSNumber)?.floatValue, v.isFinite else { return nil }
                return min(max(v, 0), Float(frames - 1))
            }
            let impact = event("impact")
            let clip = HeroMotionClip(name: name, frames: frames, fps: clipFPS, loop: (c["loop"] as? Bool) ?? false,
                                      rootXZ: min(1, max(0, (c["rootXZ"] as? NSNumber)?.floatValue ?? 0)),
                                      impact: impact, release: event("release"),
                                      end: event("end") ?? Float(frames - 1),
                                      rotBase: rot.count, rootBase: root.count,
                                      melee: (c["melee"] as? Bool) ?? (impact != nil && HeroMotionClip.isMeleeName(name)))
            rot.reserveCapacity(rot.count + frames * names.count)
            for f in 0..<frames {
                for k in 0..<names.count {
                    let o = (f * stride + map[k]) * 4
                    let q = simd_quatf(ix: r[o], iy: r[o + 1], iz: r[o + 2], r: r[o + 3])
                    // 小数 4 桁に丸めた値なので正規化し直す（長さ 0 は単位回転）
                    rot.append(q.length > 1e-6 ? q.normalized : qIdentity)
                }
                root.append(V3(rootValues[f * 3], rootValues[f * 3 + 1], rootValues[f * 3 + 2]))
            }
            seen.insert(name)
            clips.append(clip)
        }
        return HeroMotionLibrary(clips: clips, rot: rot, root: root)
    }
}

// MARK: - 同梱ファイル

/// 同梱の HeroMotionClips.json を 1 度だけ読む入口。どのスレッドからでも呼べる（ロックで 1 度だけ読む）。
/// 戦闘はロード中に preloadAsync を呼び、デコード（〜1 MB）をメインスレッドの外で済ませる。
/// 呼ばずに shared を使った場合（プレビュー・テスト）は、その場で同期に読む。
enum HeroMotionClips {
    static let resourceName = "HeroMotionClips"
    private static let lock = NSLock()
    private static var cached: HeroMotionLibrary?
    private static var resolverOverride: (() -> URL?)?

    /// 読み込み済みのライブラリ（未読み込みなら同期で読む）。
    static var shared: HeroMotionLibrary {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        let url = resolverOverride.map { $0() } ?? Bundle.main.url(forResource: resourceName, withExtension: "json")
        let lib = load(url: url)
        cached = lib
        return lib
    }

    static var isLoaded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cached != nil
    }

    /// 同期で読み込んでおく（読み込み済みなら何もしない）。
    static func preload() { _ = shared }

    /// メインスレッドの外で読み込む（ロード画面から呼ぶ。読み込み済みなら何もしない）。
    static func preloadAsync() async {
        if isLoaded { return }
        await Task.detached(priority: .userInitiated) { _ = HeroMotionClips.shared }.value
    }

    /// URL のファイルを読む。無い・読めない・形が違う時は空のライブラリ（理由は 1 度だけ記録される: 結果は shared がキャッシュする）。
    static func load(url: URL?) -> HeroMotionLibrary {
        guard let url else {
            #if DEBUG
            motionLog.info("\(resourceName, privacy: .public).json が同梱されていない → 手続きアニメーションのみ")
            #endif
            return .empty
        }
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let data = try Data(contentsOf: url)
            var skipped: [String] = []
            let lib = try HeroMotionLibrary.decode(data, skipped: &skipped)
            #if DEBUG
            if !skipped.isEmpty {
                motionLog.error("\(url.lastPathComponent, privacy: .public): 不正なクリップを除外 \(skipped.joined(separator: ","), privacy: .public)")
            }
            #endif
            let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
            motionLog.info("\(url.lastPathComponent, privacy: .public): \(lib.clips.count) クリップ \(String(format: "%.1f", ms), privacy: .public) ms")
            return lib
        } catch {
            #if DEBUG
            motionLog.error("\(url.lastPathComponent, privacy: .public): 読み込み失敗 \(String(describing: error), privacy: .public) → 手続きアニメーションのみ")
            #endif
            return .empty
        }
    }

    /// テスト用: ライブラリを差し込む（nil で差し込みを外し、次の shared で同梱ファイルを読み直す）。
    static func setLibraryForTesting(_ lib: HeroMotionLibrary?) {
        lock.lock()
        defer { lock.unlock() }
        cached = lib
    }

    /// テスト用: 同梱ファイルの代わりに読む URL（nil で既定へ戻す）。キャッシュも捨てる。
    static func setResolverForTesting(_ resolver: (() -> URL?)?) {
        lock.lock()
        defer { lock.unlock() }
        resolverOverride = resolver
        cached = nil
    }
}
