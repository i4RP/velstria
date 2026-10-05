import Foundation
import RealityKit
import simd

// 担当: hero-models。スキンメッシュ（Tripo 生成・Mixamo 名の骨）を手続きアニメーション（HeroPose）で動かすための骨対応と姿勢計算。
// ヒーロー空間 = motion エンティティのローカル（Y 上・正面 -Z・右手 +X・足元が原点、bp.scale 適用前）。
// 骨ごとの目標回転をヒーロー空間で作り（区間回転 Q × レスト補正 D × レスト回転）、親から順にローカルへ戻して jointTransforms に書く。

/// HeroPose が動かす骨の役割（Mixamo の骨名を正規化して対応づける）。
enum HeroJointRole: String, CaseIterable {
    case hips, spine, spine1, spine2, neck, head
    case shoulderL = "leftshoulder", armL = "leftarm", foreArmL = "leftforearm", handL = "lefthand", indexL = "lefthandindex1"
    case shoulderR = "rightshoulder", armR = "rightarm", foreArmR = "rightforearm", handR = "righthand", indexR = "righthandindex1"
    case upLegL = "leftupleg", legL = "leftleg", footL = "leftfoot", toeL = "lefttoebase"
    case upLegR = "rightupleg", legR = "rightleg", footR = "rightfoot", toeR = "righttoebase"

    /// 欠けていたら手続きモデルへ戻す骨。
    static let required: [HeroJointRole] = [.hips, .spine, .head, .armL, .foreArmL, .handL, .armR, .foreArmR, .handR,
                                            .upLegL, .legL, .upLegR, .legR]

    /// 骨名（パスの末尾）を正規化する: "mixamorig:LeftArm" / "mixamorig_LeftArm" / "mixamorig1:LeftArm" → "leftarm"。
    static func normalize(_ jointPath: String) -> String {
        let leaf = jointPath.split(separator: "/").last.map(String.init) ?? jointPath
        var s = Substring(leaf.lowercased())
        if s.hasPrefix("mixamorig") {
            s = s.dropFirst("mixamorig".count)
            while let c = s.first, c.isNumber { s = s.dropFirst() }
            if let c = s.first, c == ":" || c == "_" { s = s.dropFirst() }
        }
        return String(s)
    }
}

/// 上半身・下半身のどちらへ重ねるか（クリップのマスク）。
enum HeroClipMask: Equatable {
    /// 全身（腰・脚・足も含む）。
    case full
    /// 上半身（胴・頭・腕・前腕・手）。腰・脚・足は手続きのまま。
    case upper
}

/// 区間ごとの回転（ヒーロー空間）。HeroModel.apply の骨階層と同じ合成順。
/// 並びはモーションクリップの区間（docs/HERO_MOTION.md）と同じ 15 個。手・足は手続きでは前腕・脛と同じ回転。
struct HeroSegmentRotations {
    var hips = qIdentity
    var torso = qIdentity
    var head = qIdentity
    var armR = qIdentity
    var foreArmR = qIdentity
    var handR = qIdentity
    var armL = qIdentity
    var foreArmL = qIdentity
    var handL = qIdentity
    var thighR = qIdentity
    var shinR = qIdentity
    var footR = qIdentity
    var thighL = qIdentity
    var shinL = qIdentity
    var footL = qIdentity

    /// 区間の数と名前（クリップ JSON の segments と同じ順）。
    static let count = 15
    static let names = ["hips", "torso", "head", "armR", "foreArmR", "handR", "armL", "foreArmL", "handL",
                        "thighR", "shinR", "footR", "thighL", "shinL", "footL"]

    init() {}

    init(_ p: HeroPose) {
        hips = ry(p.hipsYaw) * rz(p.hipsRoll)
        torso = hips * ry(p.torsoYaw - p.hipsYaw) * rx(-p.torsoPitch) * rz(p.torsoRoll)
        head = torso * ry(p.headYaw) * rx(-p.headPitch) * rz(p.headRoll)
        armR = torso * ry(p.armR.yaw) * rx(p.armR.pitch) * rz(p.armR.out)
        foreArmR = armR * rx(p.armR.elbow)
        armL = torso * ry(-p.armL.yaw) * rx(p.armL.pitch) * rz(-p.armL.out)
        foreArmL = armL * rx(p.armL.elbow)
        thighR = hips * rx(p.legR.pitch) * rz(p.legR.out)
        shinR = thighR * rx(-p.legR.knee)
        thighL = hips * rx(p.legL.pitch) * rz(-p.legL.out)
        shinL = thighL * rx(-p.legL.knee)
        // 手続きは手首・足首を曲げない（C_手 = C_前腕 なので、従来の「親に追従」と同じ姿勢になる）
        handR = foreArmR
        handL = foreArmL
        footR = shinR
        footL = shinL
    }

    /// 添字（0..<count、names の順）で読み書きする。クリップの補間・重ね合わせ用。
    subscript(i: Int) -> simd_quatf {
        get {
            switch i {
            case 0: return hips
            case 1: return torso
            case 2: return head
            case 3: return armR
            case 4: return foreArmR
            case 5: return handR
            case 6: return armL
            case 7: return foreArmL
            case 8: return handL
            case 9: return thighR
            case 10: return shinR
            case 11: return footR
            case 12: return thighL
            case 13: return shinL
            default: return footL
            }
        }
        set {
            switch i {
            case 0: hips = newValue
            case 1: torso = newValue
            case 2: head = newValue
            case 3: armR = newValue
            case 4: foreArmR = newValue
            case 5: handR = newValue
            case 6: armL = newValue
            case 7: foreArmL = newValue
            case 8: handL = newValue
            case 9: thighR = newValue
            case 10: shinR = newValue
            case 11: footR = newValue
            case 12: thighL = newValue
            case 13: shinL = newValue
            default: footL = newValue
            }
        }
    }

    /// 上半身の区間か（胴・頭・腕・前腕・手）。それ以外（腰・腿・脛・足）が下半身。
    @inline(__always) static func isUpper(_ i: Int) -> Bool { i >= 1 && i <= 8 }

    /// 区間ごとに c へ寄せる（上半身は upper、下半身は lower の重みで slerp。0 の側は触らない）。
    mutating func blend(toward c: HeroSegmentRotations, upper: Float, lower: Float) {
        for i in 0..<Self.count {
            let w = Self.isUpper(i) ? upper : lower
            if w <= 0 { continue }
            self[i] = w >= 1 ? c[i] : simd_slerp(self[i], c[i], w)
        }
    }

    /// マスク付きの重ね合わせ（.upper は下半身を残す）。
    mutating func blend(toward c: HeroSegmentRotations, weight w: Float, mask: HeroClipMask) {
        blend(toward: c, upper: w, lower: mask == .full ? w : 0)
    }

    /// a → b の区間ごとの slerp（クリップのフレーム補間・クロスフェード）。
    static func slerp(_ a: HeroSegmentRotations, _ b: HeroSegmentRotations, _ t: Float) -> HeroSegmentRotations {
        var r = a
        r.blend(toward: b, upper: t, lower: t)
        return r
    }

    /// 武器の向き（ヒーロー空間）。HeroModel の weapon / offhand のローカル回転を前腕の回転に重ねたもの。
    /// 体に付ける籠手・爪（followsArm）は手の区間に追従する（手続きでは手 = 前腕）。
    func weaponR(_ p: HeroPose, followsArm: Bool) -> simd_quatf {
        followsArm ? handR : foreArmR * rx(-p.armR.elbow) * rz(-p.armR.out) * rx(p.weaponR - p.armR.pitch)
    }

    func weaponL(_ p: HeroPose, followsArm: Bool) -> simd_quatf {
        followsArm ? handL : foreArmL * rx(-p.armL.elbow) * rz(p.armL.out) * rx(p.weaponL - p.armL.pitch)
    }
}

/// a を b へ向ける最小回転（反平行でも破綻しない）。
func rotationBetween(_ a: V3, _ b: V3) -> simd_quatf {
    let u = simd_normalize(a), v = simd_normalize(b)
    let c = simd_dot(u, v)
    if c > 0.9999 { return qIdentity }
    if c < -0.9999 {
        var axis = simd_cross(u, V3(1, 0, 0))
        if simd_length(axis) < 1e-3 { axis = simd_cross(u, V3(0, 0, 1)) }
        return simd_quatf(angle: .pi, axis: simd_normalize(axis))
    }
    return simd_quatf(from: u, to: v)
}

/// 骨対応とレスト姿勢（テンプレートごとに 1 度だけ作り、インスタンスで共有する）。
struct HeroSkeletonRig {
    /// 骨の駆動方法。
    enum Drive: Equatable {
        /// レストのローカル変換のまま（親に追従）。
        case rest
        case hips
        /// 背骨: 腰 → 胴の回転を t の割合で補間。
        case spine(Float)
        case neck
        case head
        case armR, foreArmR, armL, foreArmL
        case thighR, shinR, thighL, shinL
        /// 手・足（区間 handR / footR …）。前腕・脛の子孫で、間の骨がすべてレストの時だけ使う。
        case handR, handL, footR, footL
    }

    let jointNames: [String]
    /// 親の添字（-1 = ルート）。
    let parent: [Int]
    /// 親が先に来る評価順。
    let order: [Int]
    let restLocal: [Transform]
    /// レストのヒーロー空間回転・位置・拡縮（骨の累積）。
    let restRotation: [simd_quatf]
    let restPosition: [V3]
    let restScale: [Float]
    let drive: [Drive]
    /// 四肢のレスト補正（レストの骨の向き → 手続きのレスト方向 -Y）。
    let correction: [simd_quatf]
    let index: [HeroJointRole: Int]
    /// スキンエンティティ → ヒーロー空間（回転・平行移動・一様拡縮）。
    let entityRotation: simd_quatf
    let entityPosition: V3
    let entityScale: Float
    /// 手首の骨から武器の握り位置までの距離（m、ヒーロー空間）。
    let gripR: Float
    let gripL: Float

    /// 必須の骨が欠けていれば missing に名前を入れて nil。
    /// entityToHero: スキンエンティティのローカル → ヒーロー空間の変換。
    init?(jointNames: [String], restLocal: [Transform], entityToHero: Transform, missing: inout [HeroJointRole]) {
        let n = jointNames.count
        guard n > 0, restLocal.count == n else { return nil }
        self.jointNames = jointNames
        self.restLocal = restLocal

        // 親はパス（"a/b/c" の親は "a/b"）から求める
        var byPath: [String: Int] = [:]
        for (i, name) in jointNames.enumerated() { byPath[name] = i }
        var parent = [Int](repeating: -1, count: n)
        for (i, name) in jointNames.enumerated() {
            if let slash = name.lastIndex(of: "/") { parent[i] = byPath[String(name[..<slash])] ?? -1 }
        }
        self.parent = parent

        var order: [Int] = []
        order.reserveCapacity(n)
        var done = [Bool](repeating: false, count: n)
        func visit(_ i: Int, _ depth: Int) {
            if done[i] || depth > n { return }
            if parent[i] >= 0 { visit(parent[i], depth + 1) }
            if !done[i] { done[i] = true; order.append(i) }
        }
        for i in 0..<n { visit(i, 0) }
        self.order = order

        var index: [HeroJointRole: Int] = [:]
        for (i, name) in jointNames.enumerated() {
            if let role = HeroJointRole(rawValue: HeroJointRole.normalize(name)), index[role] == nil { index[role] = i }
        }
        self.index = index
        missing = HeroJointRole.required.filter { index[$0] == nil }
        guard missing.isEmpty else { return nil }

        entityRotation = entityToHero.rotation
        entityPosition = entityToHero.translation
        entityScale = entityToHero.scale.x

        var rr = [simd_quatf](repeating: qIdentity, count: n)
        var pr = [V3](repeating: .zero, count: n)
        var sr = [Float](repeating: 1, count: n)
        for j in order {
            let l = restLocal[j]
            let p = parent[j]
            if p < 0 {
                rr[j] = entityRotation * l.rotation
                pr[j] = entityPosition + entityRotation.act(entityScale * l.translation)
                sr[j] = entityScale * l.scale.x
            } else {
                rr[j] = rr[p] * l.rotation
                pr[j] = pr[p] + rr[p].act(sr[p] * l.translation)
                sr[j] = sr[p] * l.scale.x
            }
        }
        restRotation = rr
        restPosition = pr
        restScale = sr

        var drive = [Drive](repeating: .rest, count: n)
        var correction = [simd_quatf](repeating: qIdentity, count: n)
        func set(_ role: HeroJointRole, _ d: Drive) { if let i = index[role] { drive[i] = d } }
        set(.hips, .hips)
        // 背骨は存在する分だけで腰 → 胴を分担する
        let spines = [HeroJointRole.spine, .spine1, .spine2].compactMap { index[$0] }
        for (k, i) in spines.enumerated() { drive[i] = .spine(Float(k + 1) / Float(spines.count)) }
        set(.neck, .neck)
        set(.head, .head)
        set(.armR, .armR)
        set(.foreArmR, .foreArmR)
        set(.armL, .armL)
        set(.foreArmL, .foreArmL)
        set(.upLegR, .thighR)
        set(.legR, .shinR)
        set(.upLegL, .thighL)
        set(.legL, .shinL)

        // 四肢: レストの骨の向き（次の関節へ）を手続きのレスト方向（真下）へ合わせる
        func child(of j: Int) -> Int? { parent.firstIndex(of: j) }
        let down = V3(0, -1, 0)
        let limbs: [(HeroJointRole, HeroJointRole?)] = [
            (.armR, .foreArmR), (.foreArmR, .handR), (.armL, .foreArmL), (.foreArmL, .handL),
            (.upLegR, .legR), (.legR, .footR), (.upLegL, .legL), (.legL, .footL)]
        for (role, next) in limbs {
            guard let j = index[role] else { continue }
            var dir: V3?
            if let next, let k = index[next] { dir = pr[k] - pr[j] } else if let k = child(of: j) { dir = pr[k] - pr[j] }
            // 末端が無ければ親の骨の向きを使う
            if (dir.map { simd_length($0) } ?? 0) < 1e-5, parent[j] >= 0 { dir = pr[j] - pr[parent[j]] }
            if let d = dir, simd_length(d) > 1e-5 { correction[j] = rotationBetween(d, down) }
        }
        // 手・足は前腕・脛の補正をそのまま使う（docs/HERO_MOTION.md の C_手 = C_前腕、C_足 = C_脛）。
        // 区間回転が前腕・脛と同じなら R = Q·C·R0_手 = 前腕の回転·（レストのローカル）となり、従来の「親に追従」と一致する。
        // 前腕・脛の子孫でない・間に駆動される骨がある時は一致しないので、従来どおり親に追従させる。
        func setEnd(_ role: HeroJointRole, _ limb: HeroJointRole, _ d: Drive) {
            guard let j = index[role], let l = index[limb] else { return }
            var p = parent[j]
            while p >= 0 && p != l {
                if drive[p] != .rest { return }
                p = parent[p]
            }
            guard p == l else { return }
            drive[j] = d
            correction[j] = correction[l]
        }
        setEnd(.handR, .foreArmR, .handR)
        setEnd(.handL, .foreArmL, .handL)
        setEnd(.footR, .legR, .footR)
        setEnd(.footL, .legL, .footL)
        self.drive = drive
        self.correction = correction

        func grip(_ hand: HeroJointRole, _ finger: HeroJointRole) -> Float {
            guard let h = index[hand], let f = index[finger] else { return 0.06 }
            let d = simd_distance(pr[h], pr[f])
            return d > 1e-4 ? 0.6 * d : 0.06
        }
        gripR = grip(.handR, .indexR)
        gripL = grip(.handL, .indexL)
    }

    /// 最後の背骨（翼の取り付け位置）。
    var upperSpine: Int { index[.spine2] ?? index[.spine1] ?? index[.spine]! }
}

/// インスタンスごとの姿勢計算（作業配列を使い回し、毎フレームのヒープ確保をしない）。
struct HeroSkeletonPoser {
    let rig: HeroSkeletonRig
    /// 現在のヒーロー空間回転・位置。
    private(set) var rotation: [simd_quatf]
    private(set) var position: [V3]
    /// jointTransforms に書くローカル変換。
    private(set) var local: [Transform]

    init(rig: HeroSkeletonRig) {
        self.rig = rig
        rotation = rig.restRotation
        position = rig.restPosition
        local = rig.restLocal
    }

    /// 区間回転と腰の沈み・ずれからローカル変換を求める。
    /// hipsOffset: クリップの腰の位置（ヒーロー空間・m、脚の長さを掛けた後）。hipsDrop と足し合わせる。
    mutating func solve(_ q: HeroSegmentRotations, hipsDrop: Float, hipsOffset: V3 = .zero) {
        let hips = rig.index[.hips] ?? -1
        let drop = V3(0, -hipsDrop, 0) + hipsOffset
        for j in rig.order {
            let p = rig.parent[j]
            let rest = rig.restLocal[j]
            var pos: V3
            if p < 0 {
                pos = rig.entityPosition + rig.entityRotation.act(rig.entityScale * rest.translation)
            } else {
                pos = position[p] + rotation[p].act(rig.restScale[p] * rest.translation)
            }
            if j == hips { pos += drop }

            let rot: simd_quatf
            switch rig.drive[j] {
            case .rest: rot = p < 0 ? rig.entityRotation * rest.rotation : rotation[p] * rest.rotation
            case .hips: rot = q.hips * rig.restRotation[j]
            case .spine(let t): rot = simd_slerp(q.hips, q.torso, t) * rig.restRotation[j]
            case .neck: rot = simd_slerp(q.torso, q.head, 0.5) * rig.restRotation[j]
            case .head: rot = q.head * rig.restRotation[j]
            case .armR: rot = q.armR * rig.correction[j] * rig.restRotation[j]
            case .foreArmR: rot = q.foreArmR * rig.correction[j] * rig.restRotation[j]
            case .armL: rot = q.armL * rig.correction[j] * rig.restRotation[j]
            case .foreArmL: rot = q.foreArmL * rig.correction[j] * rig.restRotation[j]
            case .thighR: rot = q.thighR * rig.correction[j] * rig.restRotation[j]
            case .shinR: rot = q.shinR * rig.correction[j] * rig.restRotation[j]
            case .thighL: rot = q.thighL * rig.correction[j] * rig.restRotation[j]
            case .shinL: rot = q.shinL * rig.correction[j] * rig.restRotation[j]
            case .handR: rot = q.handR * rig.correction[j] * rig.restRotation[j]
            case .handL: rot = q.handL * rig.correction[j] * rig.restRotation[j]
            case .footR: rot = q.footR * rig.correction[j] * rig.restRotation[j]
            case .footL: rot = q.footL * rig.correction[j] * rig.restRotation[j]
            }
            rotation[j] = rot
            position[j] = pos

            var t = rest
            if p < 0 {
                let inv = rig.entityRotation.inverse
                t.rotation = (inv * rot).normalized
                t.translation = inv.act(pos - rig.entityPosition) / rig.entityScale
            } else {
                let inv = rotation[p].inverse
                t.rotation = (inv * rot).normalized
                t.translation = inv.act(pos - position[p]) / rig.restScale[p]
            }
            local[j] = t
        }
    }

    /// 役割の骨の現在位置（ヒーロー空間）。
    func jointPosition(_ role: HeroJointRole) -> V3? {
        rig.index[role].map { position[$0] }
    }
}
