import SwiftUI
import VelstriaCore

// 担当: battle-hud。装備のアクティブ（ウィンタークラウン・ナチュラルウィンド）と祝福のアクティブ（ロームの隠蔽）の
// 小さな丸ボタン、効果中のポーションの表示値。右側クラスタ（HUDActionCluster）に 1 行で差し込む。
// ・装備のアクティブ: 上の攻撃ボタンの画面中央側。装備のアイコン + クールダウンの扇形。押すと .useItemActive。
// ・隠蔽: 必殺技の習得バッジの上（共栄ゴールドで隠蔽を解放した時だけ）。押すと .useGearActive。
// どちらもスペルより画面の端側に置き、キルフィード（スペルより画面中央側）・シグナル列（上端の行）・
// 他の操作部品と重ならない（HUDItemActiveTests）。

/// アクティブ装備・祝福のアクティブ・効果中のポーションの表示値（15Hz で作り、変化した時だけ HUDModel が差し替える）。
struct HUDItemActiveSnapshot: Equatable {
    struct Ability: Equatable {
        /// アイコンに使う装備（祝福は nil で、祝福の記号を描く）。
        var itemID: String?
        /// 残りクールダウン（0.1 秒単位で切り上げ。0 なら使える）。
        var cooldown: Double = 0
        var cooldownTotal: Double = 1

        var ready: Bool { cooldown <= 0 }
        var cooldownFraction: Double { cooldown > 0 && cooldownTotal > 0 ? min(1, cooldown / cooldownTotal) : 0 }
    }

    struct Potion: Equatable {
        var itemID: String
        /// 残り秒数（切り上げ）。
        var remaining: Int
    }

    /// アクティブ装備（持っていなければ nil）。
    var item: Ability?
    /// 祝福のアクティブ（隠蔽。共栄ゴールドで解放するまで nil）。
    var gear: Ability?
    /// 効果中のポーション（所持枠を使わない）。
    var potion: Potion?
}

enum HUDItemActiveLogic {
    /// 表示値（純粋関数。単体テスト対象）。
    static func snapshot(_ h: HeroData, time: Double, master: MasterData) -> HUDItemActiveSnapshot {
        var snap = HUDItemActiveSnapshot()
        if let info = ItemEffects.activeInfo(h, time: time, master: master) {
            snap.item = .init(itemID: info.itemID, cooldown: rounded(info.remaining), cooldownTotal: info.cooldown)
        }
        if let cd = GearSystem.activeCooldown(h, time: time, master: master) {
            snap.gear = .init(itemID: nil, cooldown: rounded(cd), cooldownTotal: Balance.Gear.concealCooldown)
        }
        let rt = h.itemRuntime
        if let potion = rt.potionID, time < rt.potionUntil {
            snap.potion = .init(itemID: potion, remaining: Int((rt.potionUntil - time).rounded(.up)))
        }
        return snap
    }

    /// 15Hz のスナップショットが毎回変わらないよう、残り時間は 0.1 秒単位（切り上げ）にそろえる。
    static func rounded(_ cooldown: Double) -> Double {
        cooldown > 0 ? (cooldown * 10).rounded(.up) / 10 : 0
    }
}

// MARK: - 配置

extension HUDLayout {
    /// アクティブ装備・隠蔽のボタンの見た目の直径（タップ領域は 44pt 以上）。
    var itemActiveDiameter: CGFloat { 40 * scale }

    /// アクティブ装備: 上の攻撃ボタンの画面中央側（右手配置で中央の攻撃ボタンから左 60・上 80）。
    var itemActiveCenter: CGPoint { itemActionPoint(x: -60, y: -80) }

    /// 隠蔽: 必殺技の習得バッジの上（右手配置で中央の攻撃ボタンから左 114・上 125）。
    var gearActiveCenter: CGPoint { itemActionPoint(x: -114, y: -125) }

    /// 中央の攻撃ボタンからの位置（右手配置の向き。左利きは左右反転。スキル・スペルの配置と同じ規則）。
    private func itemActionPoint(x: CGFloat, y: CGFloat) -> CGPoint {
        let c = attackCenter
        let dx = x * scale
        return CGPoint(x: leftHanded ? c.x - dx : c.x + dx, y: c.y + y * scale)
    }
}

// MARK: - 操作

extension HUDModel {
    /// アクティブ装備を使う（ウィンタークラウン: 凍結、ナチュラルウィンド: 物理ダメージ無効）。
    func useItemActive() {
        guard canControl, let a = itemActives.item else { return }
        guard !hero.isDead, a.ready else { return activeUnavailableFeedback() }
        controller.send(.useItemActive)
        appModel?.haptics.tap()
    }

    /// 祝福のアクティブを使う（ロームの隠蔽）。
    func useGearActive() {
        guard canControl, let g = itemActives.gear else { return }
        guard !hero.isDead, g.ready else { return activeUnavailableFeedback() }
        controller.send(.useGearActive)
        appModel?.haptics.tap()
    }

    private func activeUnavailableFeedback() {
        appModel?.haptics.impact(.soft, intensity: 0.6)
        showToast(hero.isDead ? L("倒れている間は使えません", "Unavailable while dead") : L("クールダウン中", "On cooldown"),
                  symbol: "exclamationmark.circle.fill", isError: true)
    }
}

// MARK: - ボタン

/// 右側クラスタのアクティブ装備・隠蔽のボタン（持っている時だけ出る）。HUDActionCluster の ZStack に置く。
struct HUDItemActiveButtons: View {
    let model: HUDModel
    let layout: HUDLayout
    var dead = false

    var body: some View {
        let actives = model.itemActives
        let d = layout.itemActiveDiameter
        ZStack {
            if let a = actives.item {
                let name = a.itemID.flatMap { MasterData.shared.item($0) }.map { MasterText.item($0) } ?? L("アクティブ装備", "Item active")
                HUDItemActiveButton(ability: a, diameter: d, dead: dead, label: name, identifier: "hud_item_active") {
                    model.useItemActive()
                }
                .position(layout.itemActiveCenter)
                .transition(.scale.combined(with: .opacity))
            }
            if let g = actives.gear {
                HUDItemActiveButton(ability: g, diameter: d, dead: dead, symbol: GearInfo.symbol(.conceal),
                                    label: GearInfo.name(.conceal), identifier: "hud_gear_active") {
                    model.useGearActive()
                }
                .position(layout.gearActiveCenter)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: layout.width, height: layout.height)
        .animation(.spring(duration: 0.3), value: actives.item?.itemID)
        .animation(.spring(duration: 0.3), value: actives.gear != nil)
    }
}

/// 小さな丸ボタン（装備のアイコン、または祝福の記号 + クールダウンの扇形と秒数）。
struct HUDItemActiveButton: View {
    let ability: HUDItemActiveSnapshot.Ability
    let diameter: CGFloat
    var dead = false
    /// 祝福は記号で描く（装備は装備のアイコン）。
    var symbol: String?
    let label: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        let ready = ability.ready && !dead
        Button(action: action) {
            ZStack {
                ZStack {
                    face
                    Circle().strokeBorder(ready ? Theme.gold : HUDStyle.rim, lineWidth: ready ? 2 : 1.2)
                }
                .hudDeadDim(dead)
                if ability.cooldown > 0 {
                    HUDCooldownOverlay(cooldown: ability.cooldown, fraction: ability.cooldownFraction, diameter: diameter,
                                       fontRatio: 0.34)
                }
            }
            .frame(width: diameter, height: diameter)
            .shadow(color: ready ? Theme.gold.opacity(0.35) : .clear, radius: 4)
            .frame(width: max(44, diameter), height: max(44, diameter))
            .contentShape(Circle())
        }
        .buttonStyle(HUDPressStyle())
        .accessibilityLabel(label)
        .accessibilityValue(ability.cooldown > 0
                            ? L("残り \(HUDStyle.cooldown(ability.cooldown)) 秒", "\(HUDStyle.cooldown(ability.cooldown)) seconds left")
                            : L("使用可能", "Ready"))
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private var face: some View {
        if symbol == nil, let itemID = ability.itemID, let art = PortraitArt.item(itemID) {
            Image(uiImage: art)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(LinearGradient(colors: [HUDStyle.glassTop, HUDStyle.glassBottom], startPoint: .top, endPoint: .bottom))
            Image(systemName: symbol ?? "sparkles")
                .font(.system(size: diameter * 0.42, weight: .bold))
                .foregroundStyle(symbol == nil ? Theme.gold : Theme.cyan)
        }
    }
}
