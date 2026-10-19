import CoreGraphics
import Foundation
import ImageIO
import Metal
import simd

// 担当: battle-renderer（ステージ）。バンドルのステージ素材（App/Resources/Stage/）を読む。
// 形式は docs/STAGE.md の 3 章。画像の展開・バイナリの解析は背景スレッドで行ってよい（main actor 不要）。

/// 小物 1 種のメッシュ（StageProps.bin の 1 件）。座標は RealityKit と同じ（+Y が上、m）。
struct StagePropMesh: Sendable {
    let id: String
    let positions: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let uvs: [SIMD2<Float>]
    let indices: [UInt32]
    let boundsMin: SIMD3<Float>
    let boundsMax: SIMD3<Float>

    var size: SIMD3<Float> { boundsMax - boundsMin }
}

enum StagePropKind: String, CaseIterable, Sendable {
    case cliffRockA = "cliff_rock_a"
    case cliffRockB = "cliff_rock_b"
    case boulder
    case treeRound = "tree_round"
    case treeTall = "tree_tall"
    case bush
    case ruinPillar = "ruin_pillar"
    /// 旧セットだけ（配置には使っていない）。
    case ruinArch = "ruin_arch"
    /// 新セットだけ: 泉（出撃地点）の遺跡の台座。歩ける所に置く飾りなので、硬い物の配置（placements）には入れない。
    case spawnDais = "spawn_dais"
    case sanctuary
    case rootWall = "root_wall"
    case campCrescent = "camp_crescent"
    case campGate = "camp_gate"
    case riverWall = "river_wall"

    static let fieldKinds: [StagePropKind] = [.rootWall, .campCrescent, .campGate, .riverWall]

    /// 風で揺れるか（木・茂み）。
    var isFoliage: Bool { self == .treeRound || self == .treeTall || self == .bush }
}

/// ステージの素材のセット（docs/STAGE.md 2 章）。App/Resources/Stage/ はバンドルの直下に平らに入るので、
/// ファイル名の頭でセットを分ける。祭壇の模様（StageDecal_rune.jpg）とシェーダーは共用。
enum StageArtSet: String, CaseIterable, Sendable {
    /// 2026-10-12 の「遺跡と森」（既定）。灰緑の花崗岩・苔・踏み固めた土・遺跡の石畳。小物は Tripo 製。
    case ruins
    /// 2026-10-05 の旧セット（Meshy 製）。起動引数 -legacyStage で選ぶ（DEBUG / SCREENSHOTS ビルド）。
    case legacy

    /// 起動引数で選ばれたセット。
    static var current: StageArtSet { DebugLaunch.args.contains("-legacyStage") ? .legacy : .ruins }

    var tilePrefix: String { self == .legacy ? "StageTile_" : "StageRuinsTile_" }
    var propsResource: String { self == .legacy ? "StageProps" : "StageRuinsProps" }
    var atlasResource: String { self == .legacy ? "StagePropsAtlas" : "StageRuinsPropsAtlas" }

    /// 小物の種類（StageProps.bin の並び = アトラスのセル順）。
    var propKinds: [StagePropKind] {
        switch self {
        case .legacy: return [.cliffRockA, .cliffRockB, .boulder, .treeRound, .treeTall, .bush, .ruinPillar, .ruinArch]
        case .ruins: return [.cliffRockA, .cliffRockB, .boulder, .treeRound, .treeTall, .bush, .ruinPillar, .spawnDais]
        }
    }
}

enum StageTile: String, CaseIterable, Sendable {
    case grass, grassDark = "grass_dark", dirt, paving, rock, moss, riverbed
}

/// ステージの素材一式。読み込みは 1 度だけ（以後はキャッシュ）。
final class StageAssets: @unchecked Sendable {
    let set: StageArtSet
    let props: [StagePropKind: StagePropMesh]
    let atlas: CGImage
    let tiles: [StageTile: CGImage]
    let rune: CGImage
    let shaderURL: URL
    var sanctuary: StagePropMesh?
    var sanctuaryAtlas: CGImage?
    var fieldProps: [StagePropKind: StagePropMesh] = [:]
    var fieldAtlas: CGImage?

    private init(set: StageArtSet, props: [StagePropKind: StagePropMesh], atlas: CGImage, tiles: [StageTile: CGImage],
                 rune: CGImage, shaderURL: URL) {
        self.set = set
        self.props = props
        self.atlas = atlas
        self.tiles = tiles
        self.rune = rune
        self.shaderURL = shaderURL
    }

    private static let lock = NSLock()
    /// 小物のメッシュだけを覚えておく（セットごとに数 MB）。展開した画像（約 40 MB）は試合ごとに読み直し、試合が終われば解放する。
    nonisolated(unsafe) private static var cachedProps: [StageArtSet: [StagePropKind: StagePropMesh]] = [:]

    /// バンドルにステージの素材があるか（読み込みはしない。どちらの地形を準備するかの判断用）。
    static var isBundled: Bool { isBundled(.current) }

    static func isBundled(_ set: StageArtSet) -> Bool {
        Bundle.main.url(forResource: set.propsResource, withExtension: "bin") != nil
            && Bundle.main.url(forResource: shaderResourceName, withExtension: "metallib") != nil
    }

    /// 素材を読む。欠けていれば nil。
    static func load(set: StageArtSet = .current, bundle: Bundle = .main) -> StageAssets? {
        make(set: set, bundle: bundle)
    }

    static var shaderResourceName: String {
        #if targetEnvironment(simulator)
        return "StageShaders-sim"
        #elseif os(macOS)
        return "StageShaders-mac"
        #else
        return "StageShaders-ios"
        #endif
    }

    private static func make(set: StageArtSet, bundle: Bundle) -> StageAssets? {
        guard let atlas = image(bundle, set.atlasResource, "jpg"),
              let rune = image(bundle, "StageDecal_rune", "jpg"),
              let shaderURL = bundle.url(forResource: shaderResourceName, withExtension: "metallib"),
              let props = props(set: set, bundle: bundle, atlas: atlas) else { return nil }
        var tiles: [StageTile: CGImage] = [:]
        for t in StageTile.allCases {
            guard let img = image(bundle, "\(set.tilePrefix)\(t.rawValue)", "jpg") else { return nil }
            tiles[t] = img
        }
        let assets = StageAssets(set: set, props: props, atlas: atlas, tiles: tiles, rune: rune, shaderURL: shaderURL)
        if set == .ruins,
           let url = bundle.url(forResource: "StageFieldProps", withExtension: "bin"),
           let data = try? Data(contentsOf: url),
           let meshes = parseProps(data, kinds: StagePropKind.fieldKinds),
           meshes.values.allSatisfy({ $0.indices.count / 3 <= 6000 }),
           let texture = image(bundle, "StageFieldAtlas", "jpg"),
           texture.width <= 2048, texture.height <= 1024 {
            assets.fieldProps = meshes
            assets.fieldAtlas = texture
        }
        if set == .ruins,
           let url = bundle.url(forResource: "StageSanctuary", withExtension: "bin"),
           let data = try? Data(contentsOf: url),
           let mesh = parseProps(data, kinds: [.sanctuary])?[.sanctuary],
           mesh.indices.count / 3 <= 12000,
           let texture = image(bundle, "StageSanctuaryAtlas", "jpg"),
           texture.width <= 1024, texture.height <= 1024 {
            assets.sanctuary = mesh
            assets.sanctuaryAtlas = texture
        }
        return assets
    }

    private static func props(set: StageArtSet, bundle: Bundle, atlas: CGImage) -> [StagePropKind: StagePropMesh]? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cachedProps[set] { return cached }
        guard let binURL = bundle.url(forResource: set.propsResource, withExtension: "bin"),
              let data = try? Data(contentsOf: binURL),
              let parsed = parseProps(data, kinds: set.propKinds) else { return nil }
        let props = softenFoliage(parsed, atlas: atlas)
        cachedProps[set] = props
        return props
    }

    /// JPEG を展開済みの CGImage にする（TextureResource 生成時に main で展開させない）。
    static func image(_ bundle: Bundle, _ name: String, _ ext: String) -> CGImage? {
        guard let url = bundle.url(forResource: name, withExtension: ext),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true]
        return CGImageSourceCreateImageAtIndex(src, 0, opts as CFDictionary)
    }

    // MARK: 葉の法線

    /// 木・茂みの葉の法線を樹冠の中心から外向きへ寄せる（手描き風の柔らかい陰影。面ごとの角張った陰を消す）。
    /// 葉かどうかはアトラスの色で決める（緑なら葉、茶色の幹はそのまま）。
    static func softenFoliage(_ props: [StagePropKind: StagePropMesh], atlas: CGImage) -> [StagePropKind: StagePropMesh] {
        let w = atlas.width, h = atlas.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return props }
        ctx.draw(atlas, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let base = ctx.data else { return props }
        let px = base.bindMemory(to: UInt8.self, capacity: w * h * 4)
        func isLeaf(_ uv: SIMD2<Float>) -> Bool {
            // UV は下端 0。CGContext のメモリは上端の行から
            let x = max(0, min(w - 1, Int(uv.x * Float(w))))
            let y = max(0, min(h - 1, Int((1 - uv.y) * Float(h))))
            let i = (y * w + x) * 4
            let r = Float(px[i]), g = Float(px[i + 1]), b = Float(px[i + 2])
            return g > r * 1.05 && g > b * 0.95
        }
        var out = props
        for kind in StagePropKind.allCases where kind.isFoliage {
            guard let m = props[kind] else { continue }
            let leaf = m.uvs.map(isLeaf)
            var c = SIMD3<Float>.zero, n = 0
            for (i, p) in m.positions.enumerated() where leaf[i] {
                c += p
                n += 1
            }
            guard n > 0 else { continue }
            c /= Float(n)
            // 樹冠は横に広いので、中心からの向きを高さ方向に少し潰して上面を明るく
            var normals = m.normals
            for i in normals.indices where leaf[i] {
                var d = m.positions[i] - c
                d.y *= 1.6
                let len = simd_length(d)
                guard len > 1e-4 else { continue }
                normals[i] = simd_normalize(simd_mix(m.normals[i], d / len, SIMD3(repeating: 0.75)))
            }
            out[kind] = StagePropMesh(id: m.id, positions: m.positions, normals: normals, uvs: m.uvs, indices: m.indices,
                                      boundsMin: m.boundsMin, boundsMax: m.boundsMax)
        }
        return out
    }

    // MARK: StageProps.bin

    private struct Header: Decodable {
        struct Prop: Decodable {
            let id: String
            let vertexCount: Int
            let indexCount: Int
            let vertexOffset: Int
            let indexOffset: Int
            let boundsMin: [Float]
            let boundsMax: [Float]
        }
        let props: [Prop]
    }

    /// kinds: セットの小物の種類（全部そろっていなければ nil）。
    static func parseProps(_ data: Data, kinds: [StagePropKind]) -> [StagePropKind: StagePropMesh]? {
        guard data.count >= 12, data.prefix(4) == Data("VSP1".utf8) else { return nil }
        func u32(_ at: Int) -> Int {
            data.withUnsafeBytes { Int($0.loadUnaligned(fromByteOffset: at, as: UInt32.self).littleEndian) }
        }
        guard u32(4) == 1 else { return nil }
        let jsonLength = u32(8)
        guard 12 + jsonLength <= data.count,
              let header = try? JSONDecoder().decode(Header.self, from: data.subdata(in: 12..<(12 + jsonLength))) else { return nil }
        let dataStart = (12 + jsonLength + 15) / 16 * 16
        var out: [StagePropKind: StagePropMesh] = [:]
        for p in header.props {
            guard let kind = StagePropKind(rawValue: p.id), kinds.contains(kind), p.boundsMin.count == 3,
                  p.boundsMax.count == 3 else { continue }
            let vStart = dataStart + p.vertexOffset, iStart = dataStart + p.indexOffset
            guard vStart >= dataStart, iStart >= dataStart, vStart + p.vertexCount * 32 <= data.count,
                  iStart + p.indexCount * 4 <= data.count, p.indexCount % 3 == 0 else { return nil }
            var positions = [SIMD3<Float>](), normals = [SIMD3<Float>](), uvs = [SIMD2<Float>](), indices = [UInt32]()
            positions.reserveCapacity(p.vertexCount)
            normals.reserveCapacity(p.vertexCount)
            uvs.reserveCapacity(p.vertexCount)
            indices.reserveCapacity(p.indexCount)
            let ok: Bool = data.withUnsafeBytes { raw in
                for k in 0..<p.vertexCount {
                    let o = vStart + k * 32
                    func f(_ i: Int) -> Float { Float(bitPattern: raw.loadUnaligned(fromByteOffset: o + i * 4, as: UInt32.self).littleEndian) }
                    positions.append(SIMD3(f(0), f(1), f(2)))
                    normals.append(SIMD3(f(3), f(4), f(5)))
                    uvs.append(SIMD2(f(6), f(7)))
                }
                for k in 0..<p.indexCount {
                    let i = raw.loadUnaligned(fromByteOffset: iStart + k * 4, as: UInt32.self).littleEndian
                    guard Int(i) < p.vertexCount else { return false }
                    indices.append(i)
                }
                return true
            }
            guard ok else { return nil }
            out[kind] = StagePropMesh(id: p.id, positions: positions, normals: normals, uvs: uvs, indices: indices,
                                      boundsMin: SIMD3(p.boundsMin[0], p.boundsMin[1], p.boundsMin[2]),
                                      boundsMax: SIMD3(p.boundsMax[0], p.boundsMax[1], p.boundsMax[2]))
        }
        return Set(out.keys) == Set(kinds) ? out : nil
    }
}
