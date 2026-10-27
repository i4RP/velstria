import SwiftUI

extension HUDLayout {
    /// 補助ボタンの下、ホームインジケータの上に収まる細い自分のHP。
    var playerHealthFrame: CGRect {
        let w = min(230 * scale, width * 0.30)
        let h = 8 * scale
        return CGRect(x: (width - w) / 2, y: height - safe.bottom - h - 1,
                      width: w, height: h)
    }
}

/// 既存の15Hzスナップショットを使用する。見回しや移動のタッチを遮らない。
struct HUDPlayerHealth: View {
    let model: HUDModel
    let layout: HUDLayout

    var body: some View {
        let v = model.vitals
        let frame = layout.playerHealthFrame
        if !model.hero.isDead, !model.hero.heroID.isEmpty {
            HStack(spacing: 4) {
                Text("HP")
                    .font(.system(size: 8 * layout.scale, weight: .bold))
                    .foregroundStyle(.white)
                HUDBar(value: v.hp, max: v.maxHP, shield: v.shield,
                       color: v.hpRatio < 0.3 ? HUDStyle.hpLow : HUDStyle.hp,
                       height: 6 * layout.scale, showsText: false)
            }
            .frame(width: frame.width, height: frame.height)
            .shadow(color: .black.opacity(0.8), radius: 2)
            .position(x: frame.midX, y: frame.midY)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("自分のHP", "Your HP"))
            .accessibilityValue("\(HUDStyle.number(v.hp)) / \(HUDStyle.number(v.maxHP))")
            .accessibilityIdentifier("hud_player_hp")
        }
    }
}
