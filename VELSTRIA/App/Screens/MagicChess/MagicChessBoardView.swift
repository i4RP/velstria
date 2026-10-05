import SwiftUI
import VelstriaCore

// 担当: ui（マジックチェス）。盤面グリッド（配置）と戦闘フィールド（再生）のビュー。

/// チビ駒（ポートレート + 星 + HP バー）。
struct MCUnitChip: View {
    @Environment(AppModel.self) private var app
    let heroID: String
    var star: Int = 1
    var hpRatio: Double = 1
    var size: CGFloat = 38
    var selected: Bool = false
    var dimmed: Bool = false

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 1) {
                ForEach(0..<max(1, star), id: \.self) { _ in
                    Image(systemName: "star.fill").font(.system(size: 6)).foregroundStyle(Theme.gold)
                }
            }
            .frame(height: 7)
            HeroPortraitView(heroID: heroID, size: size)
                .overlay(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                    .stroke(selected ? Theme.gold : .clear, lineWidth: 2.5))
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.black.opacity(0.5))
                .frame(height: 3)
                .overlay(alignment: .leading) {
                    GeometryReader { g in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(hpRatio > 0.5 ? Theme.success : (hpRatio > 0.2 ? Theme.gold : Color.red))
                            .frame(width: g.size.width * max(0, min(1, hpRatio)))
                    }
                }
                .frame(width: size)
        }
        .opacity(dimmed ? 0.35 : 1)
    }
}

/// 配置グリッド（ショップフェーズ）。
struct MCBoardGrid: View {
    @Environment(AppModel.self) private var app
    @Bindable var controller: MagicChessController

    var body: some View {
        let board = controller.human?.board ?? []
        VStack(spacing: 6) {
            ForEach((0..<MagicChessData.boardRows).reversed(), id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(0..<MagicChessData.boardCols, id: \.self) { col in
                        cell(row: row, col: col, board: board)
                    }
                }
            }
        }
    }

    private func cell(row: Int, col: Int, board: [BoardUnit]) -> some View {
        let gc = GridCell(col: col, row: row)
        let unit = board.first { $0.cell == gc }
        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.white.opacity(0.05))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.panelStroke))
            .overlay {
                if let unit {
                    MCUnitChip(heroID: unit.heroID, star: unit.star, size: 34,
                               selected: controller.selected == unit.instanceID)
                }
            }
            .frame(height: 54)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                app.haptics.tap()
                if let sel = controller.selected, controller.isOnBench(sel) {
                    controller.place(sel, at: gc)
                    controller.selected = nil
                } else if let unit {
                    controller.selected = (controller.selected == unit.instanceID) ? nil : unit.instanceID
                }
            }
            .accessibilityIdentifier("mc_cell_\(col)_\(row)")
    }
}

/// 戦闘フィールド（フレーム再生）。team 0 = 下（自分）, team 1 = 上（相手）。
struct MCCombatField: View {
    @Environment(AppModel.self) private var app
    let frame: MCCombatFrame

    private var halfW: Double { Double(MagicChessData.boardCols - 1) / 2 * 220 + 140 }
    private var halfH: Double { 170 + Double(MagicChessData.boardRows - 1) * 220 + 180 }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [Color.red.opacity(0.10), Color.clear, Theme.cyan.opacity(0.10)],
                                         startPoint: .top, endPoint: .bottom))
                Rectangle().fill(Theme.panelStroke).frame(height: 1)
                ForEach(Array(frame.units.enumerated()), id: \.offset) { _, u in
                    if u.alive || u.hp > 0 {
                        MCUnitChip(heroID: u.heroID, star: u.star, hpRatio: u.maxHP > 0 ? u.hp / u.maxHP : 0,
                                   size: 30, dimmed: !u.alive)
                            .position(point(u, in: geo.size))
                    }
                }
            }
        }
    }

    private func point(_ u: MCCombatUnit, in size: CGSize) -> CGPoint {
        let nx = (u.x + halfW) / (2 * halfW)          // 0...1
        let ny = (u.y + halfH) / (2 * halfH)          // 0...1（下=team0 を画面下に）
        let x = nx * size.width
        let y = (1 - ny) * size.height
        return CGPoint(x: max(16, min(size.width - 16, x)), y: max(16, min(size.height - 16, y)))
    }
}
