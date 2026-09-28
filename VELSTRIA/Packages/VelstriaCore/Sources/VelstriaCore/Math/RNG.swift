import Foundation

/// 決定論的乱数（SplitMix64）。シミュレーション内の乱数は必ずこれ（`state.rng`）を使う。
/// `Double.random` / `Int.random` / `SystemRandomNumberGenerator` はリプレイ・サーバー検証を壊すため使用禁止。
public struct SplitMix64: RandomNumberGenerator, Codable, Hashable, Sendable {
    public private(set) var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// [0, 1) の一様乱数。
    public mutating func nextDouble() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// [lower, upper) の一様乱数。
    public mutating func nextDouble(in range: Range<Double>) -> Double {
        range.lowerBound + nextDouble() * (range.upperBound - range.lowerBound)
    }

    /// [lower, upper] の整数。
    public mutating func nextInt(in range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % span)
    }

    /// 確率 p で true。
    public mutating func chance(_ p: Double) -> Bool { nextDouble() < p }

    /// 配列から決定論的に 1 要素を選ぶ（空なら nil）。
    public mutating func pick<T>(_ array: [T]) -> T? {
        array.isEmpty ? nil : array[nextInt(in: 0...(array.count - 1))]
    }
}
