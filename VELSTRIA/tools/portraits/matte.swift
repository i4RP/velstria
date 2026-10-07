// ヒーローアートの前景（人物）マスクを Vision で作る。splash.py の matte / variants から呼ばれる（単体でも使える）。
//
//   xcrun swiftc -O tools/portraits/matte.swift -o build/splash/matte-tool
//   build/splash/matte-tool <出力フォルダ> <画像> [<画像> ...]
//
// 画像ごとに VNGenerateForegroundInstanceMaskRequest（macOS 14 以降）を実行し、見つかった全インスタンスを合成した
// マスクを元画像と同じ大きさの 8bit グレースケール PNG（白 = 前景）として <出力フォルダ>/<元のファイル名>.png に書く。
// swift の起動は重いので、1 回の起動で渡された画像をすべて処理する。
// 標準出力には 1 画像 1 行で「名前 <TAB> 状態 <TAB> インスタンス数 <TAB> 被覆率 <TAB> 各インスタンスの被覆率」を出す
// （状態: OK / NONE = 前景が見つからない / ERROR）。余白の追加・切り出し・縮小・ぼかしは splash.py 側（ffmpeg）で行う。
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

guard #available(macOS 14.0, *) else {
    FileHandle.standardError.write("matte: macOS 14 以降が必要（VNGenerateForegroundInstanceMaskRequest）\n".data(using: .utf8)!)
    exit(2)
}

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: matte-tool <出力フォルダ> <画像> [<画像> ...]\n".data(using: .utf8)!)
    exit(2)
}
let outDir = URL(fileURLWithPath: args[1], isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

/// 1 成分 32bit 浮動小数（0…1）のマスクを 8bit の配列へ。行のパディングを除く。
func bytes(of buffer: CVPixelBuffer) -> (pixels: [UInt8], width: Int, height: Int, coverage: Double)? {
    guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent32Float else { return nil }
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
    let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
    let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
    var pixels = [UInt8](repeating: 0, count: width * height)
    var sum = 0.0
    for y in 0..<height {
        let row = (base + y * rowBytes).assumingMemoryBound(to: Float32.self)
        for x in 0..<width {
            let v = min(max(row[x], 0), 1)
            sum += Double(v)
            pixels[y * width + x] = UInt8((v * 255).rounded())
        }
    }
    return (pixels, width, height, sum / Double(width * height))
}

func writeGrayPNG(_ pixels: [UInt8], width: Int, height: Int, to url: URL) -> Bool {
    guard let provider = CGDataProvider(data: Data(pixels) as CFData),
          let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                              space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                              provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
    CGImageDestinationAddImage(dest, image, nil)
    return CGImageDestinationFinalize(dest)
}

struct MatteError: Error, CustomStringConvertible {
    let description: String
}

var failures = 0
for path in args.dropFirst(2) {
    let url = URL(fileURLWithPath: path)
    let name = url.deletingPathExtension().lastPathComponent
    do {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw MatteError(description: "load failed") }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            print("\(name)\tNONE\t0\t0\t")
            fflush(stdout)
            continue
        }
        let all = observation.allInstances
        guard let merged = bytes(of: try observation.generateScaledMaskForImage(forInstances: all, from: handler)) else {
            throw MatteError(description: "unexpected mask format")
        }
        // インスタンスごとの被覆率（背景の塊を別インスタンスとして拾っていないかの手掛かり）
        var parts: [String] = []
        if all.count > 1 {
            for index in all {
                let one = try observation.generateScaledMaskForImage(forInstances: IndexSet(integer: index), from: handler)
                parts.append(String(format: "%.3f", bytes(of: one)?.coverage ?? 0))
            }
        }
        guard writeGrayPNG(merged.pixels, width: merged.width, height: merged.height,
                           to: outDir.appendingPathComponent("\(name).png")) else { throw MatteError(description: "write failed") }
        print("\(name)\tOK\t\(all.count)\t\(String(format: "%.3f", merged.coverage))\t\(parts.joined(separator: ","))")
    } catch {
        print("\(name)\tERROR\t0\t0\t\(error)")
        failures += 1
    }
    fflush(stdout)
}
exit(failures == 0 ? 0 : 1)
