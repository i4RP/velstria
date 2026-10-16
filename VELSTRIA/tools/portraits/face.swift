// cards.py faces から使う。引数は (入力 PNG, 出力 PNG) の組。顔を検出し、顔を中心にした正方形で切り抜く。
// 顔が見つからなければ上部中央（縦 12〜62%）を使う。
import AppKit
import Vision

let args = Array(CommandLine.arguments.dropFirst())
let faceScale: CGFloat = 2.3   // 切り抜きの一辺 = 顔の高さ × この値
for i in stride(from: 0, to: args.count - 1, by: 2) {
    guard let img = NSImage(contentsOfFile: args[i]),
          let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("skip \(args[i])"); continue
    }
    let w = CGFloat(cg.width), h = CGFloat(cg.height)
    let req = VNDetectFaceRectanglesRequest()
    try? VNImageRequestHandler(cgImage: cg).perform([req])
    var side = w * 0.5, cx = w * 0.5, cy = h * 0.37   // 上から測る
    if let f = (req.results ?? []).max(by: { $0.boundingBox.height < $1.boundingBox.height }) {
        let b = f.boundingBox
        side = max(b.height * h, b.width * w) * faceScale
        cx = b.midX * w
        cy = (1 - b.midY) * h + side * 0.04
        print("\(args[i]) face \(b)")
    } else {
        print("\(args[i]) no face, fallback")
    }
    side = min(side, w, h)
    let x = min(max(0, cx - side / 2), w - side), y = min(max(0, cy - side / 2), h - side)
    guard let crop = cg.cropping(to: CGRect(x: x, y: y, width: side, height: side)) else { continue }
    let rep = NSBitmapImageRep(cgImage: crop)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 1]))
}
