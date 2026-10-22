import Foundation

/// Shared footprint for the two river sanctuaries. Units are centimetres.
/// The southern sanctuary is a half turn of the northern one.
public enum BossPitGeometry {
    public static let outerRadius: Double = 410
    public static let innerRadius: Double = 342
    public static let segments = 40
    public static let startAngle = 18.0 * Double.pi / 180
    public static let sweep = 274.0 * Double.pi / 180

    public static func point(center: Vec2, lower: Bool, radius: Double, angle: Double) -> Vec2 {
        center + Vec2(cos(angle) * radius, sin(angle) * radius) * (lower ? -1 : 1)
    }

    public static func wall(center: Vec2, lower: Bool) -> [Vec2] {
        let outer = (0...segments).map {
            point(center: center, lower: lower, radius: outerRadius,
                  angle: startAngle + sweep * Double($0) / Double(segments))
        }
        let inner = (0...segments).reversed().map {
            point(center: center, lower: lower, radius: innerRadius,
                  angle: startAngle + sweep * Double($0) / Double(segments))
        }
        let outline = outer + inner
        return outline
    }
}
