// 担当: hero-assets。正規化済み USDZ を RealityKit（macOS）で読み、骨・向き・寸法を検査する。
// 使い方: swift tools/blender/verify_usdz.swift <file.usdz> [--expect auto|hero|prop] [--height 1.7]
//          [--grip 0.1] [--length 1.0] [--thin-axis x|z|any] [--long-axis y|any]
//   （tools/tripo.mjs は swiftc で build/tripo/verify_usdz にコンパイルしてキャッシュし、取り込みの関門に使う）
// スケルトンがあればヒーロー検査、無ければ武器検査（--expect で種類を固定すると、違う種類のファイルは FAIL）。
// FAIL が 1 つでもあれば終了コード 1。
// --thin-axis z: normalize_prop.py を --yaw ±90 で通した Prop（盾・竪琴・弩。面が ±Z）。any は調べない。
// --long-axis y: Y（長さ方向）が最も長い（正規化の長軸 = PCA の第 1 軸が Y に来たか）。面が ±Z の副手や
//   --axis vertical の Prop は長軸と高さが一致しないので any。
// ヒーローの必須の骨は HeroSkeletonRig.swift の HeroJointRole.required / normalize と同じ規則で調べる。

import Foundation
import RealityKit
import simd

struct Opts {
    var path = ""
    var grip: Float = 0.1
    var length: Float = 1.0
    var height: Float = 1.7
    var thinAxis = "x"
    var longAxis = "any"
    var expect = "auto"
}

func parseOpts() -> Opts {
    var o = Opts()
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let a = it.next() {
        switch a {
        case "--grip": o.grip = Float(it.next() ?? "") ?? o.grip
        case "--length": o.length = Float(it.next() ?? "") ?? o.length
        case "--height": o.height = Float(it.next() ?? "") ?? o.height
        case "--thin-axis": o.thinAxis = it.next() ?? o.thinAxis
        case "--long-axis": o.longAxis = it.next() ?? o.longAxis
        case "--expect": o.expect = it.next() ?? o.expect
        default:
            if a.hasPrefix("--") { print("unknown option \(a)"); exit(2) }
            o.path = a
        }
    }
    return o
}

var failures = 0
func check(_ name: String, _ ok: Bool, _ detail: String) {
    print("\(ok ? "PASS" : "FAIL")  \(name)  \(detail)")
    if !ok { failures += 1 }
}

func f3(_ v: SIMD3<Float>) -> String { String(format: "(%.4f, %.4f, %.4f)", v.x, v.y, v.z) }

@MainActor
func dumpHierarchy(_ e: Entity, _ depth: Int = 0) {
    let t = e.transform
    let ang = t.rotation.angle * 180 / .pi
    let axis = ang.magnitude < 1e-4 ? SIMD3<Float>(0, 0, 0) : t.rotation.axis
    var tags: [String] = []
    if e is ModelEntity { tags.append("ModelEntity") }
    if let m = e.components[ModelComponent.self] {
        tags.append("ModelComponent(skeletons=\(m.mesh.contents.skeletons.count))")
    }
    if let sp = e.components[SkeletalPosesComponent.self] {
        tags.append("SkeletalPosesComponent(poses=\(Array(sp.poses).map { "\($0.id):\($0.jointNames.count)" }))")
    }
    let pad = String(repeating: "  ", count: depth)
    print("\(pad)- \"\(e.name)\" [\(type(of: e))] t=\(f3(t.translation)) rot=\(String(format: "%.2f", ang))° axis=\(f3(axis)) s=\(f3(t.scale)) \(tags.joined(separator: " "))")
    for c in e.children { dumpHierarchy(c, depth + 1) }
}

@MainActor
func findSkinned(_ e: Entity) -> Entity? {
    if let m = e.components[ModelComponent.self], !m.mesh.contents.skeletons.isEmpty { return e }
    for c in e.children { if let f = findSkinned(c) { return f } }
    return nil
}

func leaf(_ path: String) -> String { String(path.split(separator: "/").last ?? "") }

// HeroSkeletonRig.swift の HeroJointRole.normalize / required と同じ規則（実行時はアプリ側の型なのでここに写す）
func runtimeRole(_ jointPath: String) -> String {
    let leaf = jointPath.split(separator: "/").last.map(String.init) ?? jointPath
    var s = Substring(leaf.lowercased())
    if s.hasPrefix("mixamorig") {
        s = s.dropFirst("mixamorig".count)
        while let c = s.first, c.isNumber { s = s.dropFirst() }
        if let c = s.first, c == ":" || c == "_" { s = s.dropFirst() }
    }
    return String(s)
}

let runtimeRequired = ["hips", "spine", "head", "leftarm", "leftforearm", "lefthand", "rightarm", "rightforearm", "righthand",
                       "leftupleg", "leftleg", "rightupleg", "rightleg"]

@MainActor
func verifyHero(root: Entity, skinned: Entity, o: Opts) {
    let model = skinned.components[ModelComponent.self]!
    let skel = model.mesh.contents.skeletons.first!
    print("skeleton id=\(skel.id) joints=\(skel.joints.count)")
    if let hm = skinned as? HasModel {
        print("HasModel.jointNames count=\(hm.jointNames.count) jointTransforms count=\(hm.jointTransforms.count)")
        print("HasModel.jointNames[0..2]=\(hm.jointNames.prefix(3))")
    } else {
        print("skinned entity is not HasModel")
    }
    if let sp = skinned.components[SkeletalPosesComponent.self] {
        for p in sp.poses { print("SkeletalPose id=\(p.id) joints=\(p.jointNames.count) first=\(p.jointNames.first ?? "")") }
    } else {
        print("no SkeletalPosesComponent on skinned entity")
    }
    // レスト姿勢（親から累積）とバインド（inverseBindPose の逆）の両方でモデル空間位置を出す
    var model4 = [simd_float4x4](repeating: matrix_identity_float4x4, count: skel.joints.count)
    for (i, j) in skel.joints.enumerated() {
        let local = j.restPoseTransform.matrix
        model4[i] = j.parentIndex.map { model4[$0] * local } ?? local
    }
    let toRoot = skinned.transformMatrix(relativeTo: root)
    var pos: [String: SIMD3<Float>] = [:]
    var maxBindDiff: Float = 0
    for (i, j) in skel.joints.enumerated() {
        let p = toRoot * model4[i].columns.3
        let bind = toRoot * j.inverseBindPoseMatrix.inverse.columns.3
        maxBindDiff = max(maxBindDiff, simd_length(SIMD3(p.x, p.y, p.z) - SIMD3(bind.x, bind.y, bind.z)))
        pos[leaf(j.name)] = SIMD3(p.x, p.y, p.z)
    }
    print("joint names (\(skel.joints.count)):")
    for j in skel.joints { print("  \(j.name)") }
    let roles = Set(skel.joints.map { runtimeRole($0.name) })
    let missing = runtimeRequired.filter { !roles.contains($0) }
    check("required joints (runtime rules)", missing.isEmpty, missing.isEmpty ? "\(runtimeRequired.count) found" : "missing \(missing)")
    // Meshy の骨名（Spine02 → Spine01 → Spine = 胸）のままだと実行時は胸の骨を spine と取り違える。
    // normalize_hero.py が Mixamo 名へ付け替えるので、残っていれば付け替えの漏れ
    let meshyLeft = roles.intersection(["spine01", "spine02"]).sorted()
    check("no Meshy spine names left", meshyLeft.isEmpty, meshyLeft.isEmpty ? "" : "found \(meshyLeft) (normalize_hero.py の Meshy 付け替え漏れ)")
    // 骨の検索も実行時の規則（大文字小文字を問わず、mixamorig 接頭辞を外して完全一致）
    func same(_ key: String, _ n: String) -> Bool { runtimeRole(key) == n.lowercased() }
    func named(_ n: String) -> SIMD3<Float>? { pos.first { same($0.key, n) }?.value }
    for n in ["Hips", "Head", "HeadTop_End", "LeftArm", "RightArm", "LeftFoot", "LeftToeBase", "RightFoot", "RightToeBase"] {
        if let p = named(n) { print("  rest \(n) = \(f3(p))") }
    }
    check("rest == bind", maxBindDiff < 1e-3, String(format: "max |rest - inverse(invBind)| = %.6f", maxBindDiff))
    if let r = named("RightArm"), let l = named("LeftArm") {
        check("RightArm.x > 0 > LeftArm.x", r.x > 0 && 0 > l.x, String(format: "R=%.4f L=%.4f", r.x, l.x))
    } else { check("arms found", false, "") }
    for side in ["Left", "Right"] {
        if let f = named(side + "Foot"), let t = named(side + "ToeBase") {
            check("\(side) toe z < foot z (faces -Z)", t.z < f.z, String(format: "toe=%.4f foot=%.4f", t.z, f.z))
        } else {
            // つま先の骨は実行時の必須ではない（正規化は腕・脚の左右で向きを決めている）
            print("INFO  \(side) foot/toe absent (facing by toes skipped)")
        }
    }
    // HeadTop_End は GLB 取り込みでは落ちることがあり（スキンの関節でない葉の骨）、FBX のリグでは髪・兜の分だけ
    // 身長より上（1.75〜1.77）にある。大きく外れたときだけ FAIL。
    if let h = named("HeadTop_End") {
        check("head top ≈ \(o.height) (±0.1)", abs(h.y - o.height) < 0.1, String(format: "%.4f", h.y))
    } else { print("INFO  HeadTop_End absent (skipped)") }
    // 頭部（Head〜HeadTop_End の高さ）の頂点の前後幅。顔（鼻など）が -Z 側に張り出すかの目安（情報のみ）
    if let h0 = named("Head"), let h1 = named("HeadTop_End") {
        var zs: [Float] = []
        for m in model.mesh.contents.models {
            for part in m.parts {
                for v in part.positions.elements {
                    let p = toRoot * SIMD4(v, 1)
                    if p.y > h0.y && p.y < h1.y { zs.append(p.z) }
                }
            }
        }
        if let lo = zs.min(), let hi = zs.max() {
            print(String(format: "  head region mesh z: front(min)=%.4f back(max)=%.4f", lo, hi))
        }
    }
    // スキンのウェイト: 各頂点の最大ウェイトの関節を数える。全頂点が Hips 1 本などのダミーのスキンを弾く
    var dominant: [Int: Int] = [:]
    var vertexCount = 0
    for m in model.mesh.contents.models {
        for part in m.parts {
            guard let ji = part.jointInfluences else { continue }
            let infl = ji.influences.elements
            let nv = part.positions.count
            guard nv > 0, infl.count % nv == 0 else { continue }
            let k = max(1, infl.count / nv)   // influencesPerVertex は読めないので頂点数から出す
            var i = 0
            while i + k <= infl.count {
                let best = infl[i..<(i + k)].max { $0.weight < $1.weight }!
                if best.weight > 0 { dominant[best.jointIndex, default: 0] += 1 }
                vertexCount += 1
                i += k
            }
        }
    }
    let top = dominant.max { $0.value < $1.value }
    let topName = top.map { leaf(skel.joints[$0.key].name) } ?? "-"
    let bend = ["Head", "LeftArm", "LeftForeArm", "RightArm", "RightForeArm", "LeftUpLeg", "LeftLeg", "RightUpLeg", "RightLeg"]
    let dominated = Set(dominant.keys.map { leaf(skel.joints[$0].name) })
    let dead = bend.filter { n in named(n) != nil && !dominated.contains { same($0, n) } }
    check("skin weights are not a dummy bind", vertexCount > 0 && dead.isEmpty && (top?.value ?? 0) * 2 <= vertexCount,
          "\(dominant.count) dominant joints, top \(topName) \(top?.value ?? 0)/\(vertexCount)" + (dead.isEmpty ? "" : ", none on \(dead)"))
    let b = root.visualBounds(relativeTo: root)
    // 骨とメッシュの食い違い（軸・縮尺のずれたスキン）: 主要な骨がメッシュの外接箱（高さの 5% の余白）の内側にあるか
    let pad = 0.05 * (b.max.y - b.min.y)
    let core = ["Hips", "Spine", "Head", "LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand",
                "LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot"]
    let outside = core.compactMap { n -> String? in
        guard let p = named(n) else { return nil }
        let inside = all(p .>= b.min - SIMD3(repeating: pad)) && all(p .<= b.max + SIMD3(repeating: pad))
        return inside ? nil : "\(n)\(f3(p))"
    }
    check("core joints inside mesh bounds", outside.isEmpty, outside.isEmpty ? "" : outside.joined(separator: " "))
    check("min y ≈ 0", abs(b.min.y) < 0.01, "bounds min=\(f3(b.min)) max=\(f3(b.max))")
    check("bounds height ≈ \(o.height)", abs(b.max.y - b.min.y - o.height) < 0.01, String(format: "%.4f", b.max.y - b.min.y))
    if let hp = named("Hips") {
        check("hips x,z ≈ 0", abs(hp.x) < 0.01 && abs(hp.z) < 0.01, String(format: "x=%.4f z=%.4f", hp.x, hp.z))
    } else { check("Hips found", false, "") }
}

@MainActor
func verifyProp(root: Entity, o: Opts) {
    let b = root.visualBounds(relativeTo: root)
    let e = b.max - b.min
    print("bounds min=\(f3(b.min)) max=\(f3(b.max)) extents=\(f3(e))")
    check("y min ≈ -grip*length", abs(b.min.y + o.grip * o.length) < 0.01, String(format: "%.4f", b.min.y))
    check("y max ≈ (1-grip)*length", abs(b.max.y - (1 - o.grip) * o.length) < 0.01, String(format: "%.4f", b.max.y))
    switch o.thinAxis {
    case "z": check("thinnest axis is Z", e.z <= e.x && e.z <= e.y, String(format: "x=%.4f z=%.4f", e.x, e.z))
    case "x": check("thinnest axis is X", e.x <= e.z && e.x <= e.y, String(format: "x=%.4f z=%.4f", e.x, e.z))
    default: print(String(format: "INFO  thin axis not checked (x=%.4f z=%.4f)", e.x, e.z))
    }
    if o.longAxis == "y" {
        // 2% の余裕（間引き・断面中心の丸め）
        check("longest axis is Y", e.y * 1.02 >= max(e.x, e.z), String(format: "x=%.4f y=%.4f z=%.4f", e.x, e.y, e.z))
    }
}

@MainActor
func main() async {
    let o = parseOpts()
    guard !o.path.isEmpty else {
        print("usage: swift verify_usdz.swift <file.usdz> [--expect auto|hero|prop] [--height 1.7] [--grip 0.1] [--length 1.0] "
              + "[--thin-axis x|z|any] [--long-axis y|any]")
        exit(2)
    }
    guard ["auto", "hero", "prop"].contains(o.expect), ["x", "z", "any"].contains(o.thinAxis), ["y", "any"].contains(o.longAxis) else {
        print("bad option value: --expect \(o.expect) --thin-axis \(o.thinAxis) --long-axis \(o.longAxis)")
        exit(2)
    }
    let url = URL(fileURLWithPath: o.path)
    let root: Entity
    do {
        root = try await Entity(contentsOf: url)
    } catch {
        print("FAIL  load  \(error)")
        exit(1)
    }
    print("loaded \(url.lastPathComponent) root type=\(type(of: root))")
    print("hierarchy:")
    dumpHierarchy(root)
    if let s = findSkinned(root) {
        print("skinned entity: \"\(s.name)\" type=\(type(of: s)) isModelEntity=\(s is ModelEntity)")
        print("skinned -> root transform:\n\(s.transformMatrix(relativeTo: root))")
        if o.expect == "prop" { check("expected a static prop", false, "the file has a skeleton") }
        verifyHero(root: root, skinned: s, o: o)
    } else {
        print("no skeleton: prop mode")
        if o.expect == "hero" { check("expected a skinned hero", false, "no skeleton in the file") }
        verifyProp(root: root, o: o)
    }
    print(failures == 0 ? "RESULT PASS" : "RESULT FAIL (\(failures))")
    exit(failures == 0 ? 0 : 1)
}

await main()
