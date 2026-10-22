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
        SpellInfo(id: "BS01", symbol: "bolt.fill", hue: 0.14,
                  effectJa: "指定方向に400瞬間移動。壁を越え、1秒間、物理・魔法防御が5+Lv上昇。",
                  effectEn: "Blink 400 units through walls. Gain 5 + level defense for 1s.", tipJa: nil, tipEn: nil),
        SpellInfo(id: "BS02", symbol: "sparkles", hue: 0.36,
                  effectJa: "制圧以外の状態異常を解除。1.2秒間CC無効、移動速度+15%。",
                  effectEn: "Cleanse except suppression. CC immunity and +15% speed for 1.2s.", tipJa: nil, tipEn: nil),
        SpellInfo(id: "BS03", symbol: "heart.fill", hue: 0.36,
                  effectJa: "自身と近くのHP割合が最も低い味方を最大HPの15%回復。2秒間移動速度+20%。",
                  effectEn: "Heal yourself and the lowest-health nearby ally for 15% max HP; +20% speed for 2s.", tipJa: nil, tipEn: nil),
        SpellInfo(id: "BS04", symbol: "shield.fill", hue: 0.12,
                  effectJa: "5秒間750+50×Lvのシールド。近くのHP割合が最も低い味方にも70%分を付与。",
                  effectEn: "Shield yourself for 750 + 50 × level for 5s, and the lowest-health nearby ally for 70%.", tipJa: nil, tipEn: nil),
        SpellInfo(id: "BS05", symbol: "pawprint.fill", hue: 0.07,
                  effectJa: "モンスター・ミニオンに750+150×Lvの確定ダメージ。狩猟報酬+60%、モンスター（星喰竜・古環の巨像を除く）からのダメージ−40%。試合開始後の2分間、味方とミニオンボーナスを共有しない。",
                  effectEn: "Deal 750 + 150 × level true damage to monsters/minions. +60% jungle rewards, −40% damage taken from monsters (except the Astral Wyrm and the Ancient Colossus). For the first 2 minutes, you don't share minion rewards with allies.", tipJa: nil, tipEn: nil),
        SpellInfo(id: "BS06", symbol: "figure.run", hue: 0.53,
                  effectJa: "6秒間、移動速度+50%、減速無効。",
                  effectEn: "Gain +50% speed and slow immunity for 6s.", tipJa: nil, tipEn: nil),
        SpellInfo(id: "BS09", symbol: "sparkles", hue: 0.56,
                  effectJa: "3秒詠唱後、味方のタワー・ベース・ミニオン・トラップへ転送。移動速度+60%が3秒で減衰。中断時CD−30秒。",
                  effectEn: "Channel 3s to an allied tower, base, minion or trap. +60% speed decays over 3s. Interrupted: cooldown −30s.", tipJa: nil, tipEn: nil),
        SpellInfo(id: "BS11", symbol: "bolt.shield.fill", hue: 0.03,
                  effectJa: "100+10×Lv+対象の損失HP13%の確定ダメージ。シールド無視。撃破時CDを40%短縮（54秒）。",
                  effectEn: "Deal 100 + 10 × level + 13% missing HP true damage, ignoring shields. Kill: cooldown reduced to 54s.", tipJa: nil, tipEn: nil),
        SpellInfo(id: "BS12", symbol: "arrow.up.right", hue: 0.11,
                  effectJa: "5秒間、8回まで通常攻撃速度×1.55（上限500%）。防御8+Lv無視。攻撃ごとに60+物理攻撃15%+魔法攻撃15%回復。",
                  effectEn: "For 5s, empower 8 attacks: ×1.55 speed (500% cap), ignore 8 + level armor, heal 60 + 15% attack + 15% magic power per hit.", tipJa: nil, tipEn: nil),
        SpellInfo(id: "BS13", symbol: "hexagon.fill", hue: 0.55,
                  effectJa: "周囲に100+15×Lvの魔法ダメージ。0.8秒石化後、0.8秒間50%減速。",
                  effectEn: "Deal 100 + 15 × level magic damage nearby. Petrify 0.8s, then slow 50% for 0.8s.", tipJa: nil, tipEn: nil),
        SpellInfo(id: "BS14", symbol: "flame.fill", hue: 0.06,
                  effectJa: "長距離の火炎弾。距離に応じ200〜680+魔法攻撃50〜170%の魔法ダメージ。発射時に周囲をノックバック。",
                  effectEn: "Long-range bolt deals 200–680 + 50–170% magic power with distance. Knock back nearby enemies on cast.", tipJa: nil, tipEn: nil),
        SpellInfo(id: "BS15", symbol: "burst.fill", hue: 0.57,
                  effectJa: "3秒間、35%のダメージ軽減を獲得する。また、ダメージを受けるたびに、受けたダメージ（軽減前）の25%の魔法ダメージを攻撃者に与える。",
                  effectEn: "Gain 35% damage reduction for 3s. Whenever you take damage, deal 25% of it (before reduction) as magic damage to the attacker.", tipJa: nil, tipEn: nil),
        SpellInfo(id: "BS16", symbol: "cross.case.fill", hue: 0.32,
                  effectJa: "4秒間、範囲内の味方を0.4秒ごとに最大HP2.5%回復。回復・シールド効果+25%。複数の泉は重複しない。",
                  effectEn: "For 4s heal allies in the pool for 2.5% max HP every 0.4s; +25% healing and shields. Pools do not stack.", tipJa: nil, tipEn: nil),
        SpellInfo(id: "Recall", symbol: "sparkles", hue: 0.55,
                  effectJa: "詠唱して泉に戻る。移動・被ダメージで中断。",
                  effectEn: "Channel to return to your fountain. Movement or damage interrupts.", tipJa: nil, tipEn: nil),
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
            if let art = PortraitArt.spell(spellID) {
                Image(uiImage: art)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(RadialGradient(colors: [info.color.opacity(0.85), info.color.opacity(0.25), Color.black.opacity(0.6)],
                                         center: .init(x: 0.35, y: 0.3), startRadius: 1, endRadius: size * 0.7))
                Image(systemName: info.symbol)
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: info.color, radius: size * 0.08)
            }
            Circle()
                .strokeBorder(AngularGradient(colors: [info.color, .white.opacity(0.8), info.color.opacity(0.4), info.color],
                                              center: .center), lineWidth: max(1.5, size * 0.05))
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(MasterData.shared.spell(spellID).map { MasterText.spell($0) } ?? spellID)
    }
}
