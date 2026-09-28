import Foundation

/// シミュレーション平面上の 2D ベクトル（単位: ユニット）。
public struct Vec2: Codable, Hashable, Sendable, CustomStringConvertible {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Vec2(0, 0)

    public var length: Double { (x * x + y * y).squareRoot() }
    public var lengthSquared: Double { x * x + y * y }

    /// 長さ 0 の場合は .zero を返す。
    public var normalized: Vec2 {
        let len = length
        return len > 1e-9 ? Vec2(x / len, y / len) : .zero
    }

    /// x 軸からの角度（ラジアン）。
    public var angle: Double { atan2(y, x) }

    public static func fromAngle(_ radians: Double, length: Double = 1) -> Vec2 {
        Vec2(cos(radians) * length, sin(radians) * length)
    }

    public func distance(to other: Vec2) -> Double { (self - other).length }
    public func distanceSquared(to other: Vec2) -> Double { (self - other).lengthSquared }
    public func dot(_ other: Vec2) -> Double { x * other.x + y * other.y }
    public func cross(_ other: Vec2) -> Double { x * other.y - y * other.x }
    public var perpendicular: Vec2 { Vec2(-y, x) }

    public func rotated(by radians: Double) -> Vec2 {
        let c = cos(radians), s = sin(radians)
        return Vec2(x * c - y * s, x * s + y * c)
    }

    /// 長さを最大 `maxLength` に制限する。
    public func clamped(maxLength: Double) -> Vec2 {
        let len = length
        return len > maxLength && len > 0 ? self * (maxLength / len) : self
    }

    /// `target` へ最大 `maxDistance` だけ近づいた点。
    public func moved(toward target: Vec2, maxDistance: Double) -> Vec2 {
        let d = target - self
        let len = d.length
        if len <= maxDistance || len < 1e-9 { return target }
        return self + d * (maxDistance / len)
    }

    public static func lerp(_ a: Vec2, _ b: Vec2, _ t: Double) -> Vec2 { a + (b - a) * t }

    /// 中心 (6000,6000) に対する点対称写像（Blue 座標 → Red 座標）。
    public var mirrored: Vec2 { Vec2(Balance.mapSize - x, Balance.mapSize - y) }

    public static func + (l: Vec2, r: Vec2) -> Vec2 { Vec2(l.x + r.x, l.y + r.y) }
    public static func - (l: Vec2, r: Vec2) -> Vec2 { Vec2(l.x - r.x, l.y - r.y) }
    public static func * (l: Vec2, r: Double) -> Vec2 { Vec2(l.x * r, l.y * r) }
    public static func * (l: Double, r: Vec2) -> Vec2 { Vec2(l * r.x, l * r.y) }
    public static func / (l: Vec2, r: Double) -> Vec2 { Vec2(l.x / r, l.y / r) }
    public static prefix func - (v: Vec2) -> Vec2 { Vec2(-v.x, -v.y) }
    public static func += (l: inout Vec2, r: Vec2) { l = l + r }
    public static func -= (l: inout Vec2, r: Vec2) { l = l - r }
    public static func *= (l: inout Vec2, r: Double) { l = l * r }

    public var description: String { String(format: "(%.1f, %.1f)", x, y) }
}

/// 線分 a-b と点 p の最短距離。
public func distancePointToSegment(_ p: Vec2, _ a: Vec2, _ b: Vec2) -> Double {
    let ab = b - a
    let lenSq = ab.lengthSquared
    if lenSq < 1e-9 { return p.distance(to: a) }
    let t = max(0, min(1, (p - a).dot(ab) / lenSq))
    return p.distance(to: a + ab * t)
}

/// 軸平行矩形。
public struct Rect2: Codable, Hashable, Sendable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = min(minX, maxX)
        self.minY = min(minY, maxY)
        self.maxX = max(minX, maxX)
        self.maxY = max(minY, maxY)
    }

    public init(center: Vec2, width: Double, height: Double) {
        self.init(minX: center.x - width / 2, minY: center.y - height / 2,
                  maxX: center.x + width / 2, maxY: center.y + height / 2)
    }

    public var center: Vec2 { Vec2((minX + maxX) / 2, (minY + maxY) / 2) }
    public var width: Double { maxX - minX }
    public var height: Double { maxY - minY }

    public func contains(_ p: Vec2) -> Bool { p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY }

    public func expanded(by d: Double) -> Rect2 {
        Rect2(minX: minX - d, minY: minY - d, maxX: maxX + d, maxY: maxY + d)
    }

    public var mirrored: Rect2 {
        Rect2(minX: Balance.mapSize - maxX, minY: Balance.mapSize - maxY,
              maxX: Balance.mapSize - minX, maxY: Balance.mapSize - minY)
    }

    /// 矩形上で点 p に最も近い点。
    public func closestPoint(to p: Vec2) -> Vec2 {
        Vec2(max(minX, min(maxX, p.x)), max(minY, min(maxY, p.y)))
    }
}
