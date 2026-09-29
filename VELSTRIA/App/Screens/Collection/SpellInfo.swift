import SwiftUI
import VelstriaCore

// 担当: ui-collection。バトルスペルの表示情報（DESIGN §7 の効果を簡潔な日英テキストに）。
// マスターの description は汎用文のため、効果説明はここを正とする。

struct SpellInfo: Identifiable, Equatable {
    let id: String
    let symbol: String
    let hue: Double
    let effectJa: String
    let effectEn: String
    /// 選択時の補足（ジャングル必須など）。
    let tipJa: String?
    let tipEn: String?

    var effect: String { L(effectJa, effectEn) }
    var tip: String? {
        guard let tipJa, let tipEn else { return nil }
        return L(tipJa, tipEn)
    }
    var color: Color { Color(hue: hue, saturation: 0.62, brightness: 1.0) }

    static let all: [SpellInfo] = [
        SpellInfo(id: "BS01", symbol: "bolt.horizontal.fill", hue: 0.14,
                  effectJa: "指定方向へ 400 瞬間移動する（障害物の手前で停止）。",
                  effectEn: "Teleport 400 units in a direction (stops before walls).",
                  tipJa: "追撃にも離脱にも使える万能スペル。", tipEn: "Versatile for both chasing and escaping."),
        SpellInfo(id: "BS02", symbol: "wand.and.stars", hue: 0.52,
                  effectJa: "全ての CC を解除し、1.5 秒間 CC を無効化する。",
                  effectEn: "Removes all crowd control and grants 1.5s of CC immunity.",
                  tipJa: nil, tipEn: nil),
        SpellInfo(id: "BS03", symbol: "heart.fill", hue: 0.36,
                  effectJa: "自身と 800 以内で最も HP 割合の低い味方 1 名を最大 HP の 15% 回復し、2 秒間 移動速度 +20%。",
                  effectEn: "Heals you and the lowest-HP ally within 800 for 15% max HP, plus +20% move speed for 2s.",
                  tipJa: nil, tipEn: nil),
        SpellInfo(id: "BS04", symbol: "shield.fill", hue: 0.58,
                  effectJa: "3 秒間 最大 HP の 20% のシールドを得る。",
                  effectEn: "Gain a shield worth 20% max HP for 3s.",
                  tipJa: nil, tipEn: nil),
        SpellInfo(id: "BS05", symbol: "pawprint.fill", hue: 0.26,
                  effectJa: "500 以内の敵ミニオン/モンスターに 600 + 40×Lv の確定ダメージ。",
                  effectEn: "Deal 600 + 40×Lv true damage to an enemy minion or monster within 500.",
                  tipJa: "ジャングル担当は必須。ジャングル装備の前提スペル。",
                  tipEn: "Required for junglers and jungle items."),
        SpellInfo(id: "BS06", symbol: "hare.fill", hue: 0.47,
                  effectJa: "5 秒間 移動速度 +40%。",
                  effectEn: "+40% move speed for 5s.",
                  tipJa: nil, tipEn: nil),
        SpellInfo(id: "BS07", symbol: "flame.fill", hue: 0.04,
                  effectJa: "600 以内の敵ヒーローを燃焼させ 5 秒で 70 + 20×Lv の確定ダメージ、回復量 −50%。",
                  effectEn: "Burn an enemy hero within 600 for 70 + 20×Lv true damage over 5s and −50% healing.",
                  tipJa: nil, tipEn: nil),
        SpellInfo(id: "BS08", symbol: "eye.slash.fill", hue: 0.76,
                  effectJa: "1.5 秒間ステルス状態になり、移動速度 +25%。",
                  effectEn: "Become stealthed for 1.5s with +25% move speed.",
                  tipJa: nil, tipEn: nil),
        SpellInfo(id: "BS09", symbol: "door.left.hand.open", hue: 0.68,
                  effectJa: "3 秒詠唱後、指定した味方タワーか泉へ転移する（被ダメージで中断）。",
                  effectEn: "After a 3s channel, teleport to an allied tower or the fountain (interrupted by damage).",
                  tipJa: nil, tipEn: nil),
        SpellInfo(id: "BS10", symbol: "link", hue: 0.84,
                  effectJa: "650 以内の敵ヒーローに 2.5 秒間 スロー 40% と与ダメージ −30%。",
                  effectEn: "Slow an enemy hero within 650 by 40% and reduce their damage by 30% for 2.5s.",
                  tipJa: nil, tipEn: nil),
    ]

    static func of(_ id: String) -> SpellInfo {
        all.first { $0.id == id }
            ?? SpellInfo(id: id, symbol: "questionmark.circle", hue: 0.6, effectJa: "", effectEn: "", tipJa: nil, tipEn: nil)
    }
}

/// スペルアイコン（円形・スペル毎の記号と色）。他画面（対戦前フロー・HUD）からも `SpellIconView(spellID:size:)` で使う。
struct SpellIconView: View {
    let spellID: String
    var size: CGFloat = 48

    var body: some View {
        let info = SpellInfo.of(spellID)
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [info.color.opacity(0.85), info.color.opacity(0.25), Color.black.opacity(0.6)],
                                     center: .init(x: 0.35, y: 0.3), startRadius: 1, endRadius: size * 0.7))
            Circle()
                .strokeBorder(AngularGradient(colors: [info.color, .white.opacity(0.8), info.color.opacity(0.4), info.color],
                                              center: .center), lineWidth: max(1.5, size * 0.05))
            Image(systemName: info.symbol)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: info.color, radius: size * 0.08)
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(MasterData.shared.spell(spellID).map { MasterText.spell($0) } ?? spellID)
    }
}
