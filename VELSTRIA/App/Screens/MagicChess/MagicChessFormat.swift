import SwiftUI
import VelstriaCore

// 担当: ui（マジックチェス）。表示用の小さなヘルパー（二言語）。

enum MagicChessFormat {
    static func placement(_ n: Int) -> String {
        Loc.isEnglish ? "\(n)\(ordinalSuffix(n))" : "\(n)位"
    }

    static func ordinalSuffix(_ n: Int) -> String {
        switch n % 100 {
        case 11, 12, 13: return "th"
        default:
            switch n % 10 {
            case 1: return "st"
            case 2: return "nd"
            case 3: return "rd"
            default: return "th"
            }
        }
    }

    static func stars(_ star: Int) -> String { String(repeating: "★", count: max(1, star)) }

    static func seedLabel(_ seed: UInt64) -> String { String(format: "#%08X", UInt32(truncatingIfNeeded: seed)) }
}
