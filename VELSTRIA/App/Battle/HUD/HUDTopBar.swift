import SwiftUI
import VelstriaCore

// 担当: battle-hud。上部の HUD:
// 中央に小型のスコア（青キル・試合時間・赤キル、キルの下に破壊タワー数）、
// スコアのミニマップ側に味方 4 人の状態列（顔・HP・倒れた味方の赤い復活秒数・必殺技）、
// 情報側（右手配置は右上、左利きは左上 = HUDLayout.topInfoAlignment）に自分の K/D/A（剣・ドクロ・拍手のアイコン + 数字）・CS と
// スコアボード（UI029）、ミニマップの内側に端末状態と 設定（UI030）・消音・ズームの縦列（HUDUtilityColumn.swift）。
// ミニマップドック（左利きでは右上）に合わせ、味方列と縦列は左右反転する。
// 観戦・リプレイでは味方列と縦列を出さず、情報側にスコアボード・一時停止・退出を並べる。
// 各部品の位置は HUDLayout の拡張（下）で決め、HUDTopBarTests で重なりが無いことを確かめる。

/// 上部の HUD（スコア・味方列・情報側の成績とボタン・ミニマップ横のボタン列）。全画面の座標で配置する。
struct HUDTopLayer: View {
    let model: HUDModel
    let layout: HUDLayout

    var body: some View {
        // 15Hz で変わる値はここで読まない（各部品の小さなビューが読む）
        let spectating = model.isSpectating
        let score = layout.scoreFrame
        let info = layout.topInfoFrame(spectating: spectating)
        ZStack {
            HUDScoreLayer(model: model, size: score.size, scale: layout.topScale)
                .position(x: score.midX, y: score.midY)
            if !spectating {
                let strip = layout.allyStripFrame
                HUDAllyStrip(model: model, layout: layout)
                    .frame(width: strip.width, height: strip.height, alignment: layout.allyStripAlignment)
                    .position(x: strip.midX, y: strip.midY)
                HUDUtilityColumn(model: model, layout: layout)
            }
            HUDTopRight(model: model, layout: layout)
                .frame(width: info.width, height: info.height, alignment: layout.topInfoAlignment)
                .position(x: info.midX, y: info.midY)
        }
        .frame(width: layout.width, height: layout.height)
    }
}

// MARK: - スコア（中央）

/// 試合のスコアだけを観測する（毎秒変わる）。
private struct HUDScoreLayer: View {
    let model: HUDModel
    let size: CGSize
    let scale: CGFloat

    var body: some View {
        HUDScoreCapsule(top: model.top, colorblind: model.settings.colorblindMode, scale: scale)
            .equatable()
            .frame(width: size.width, height: size.height)
    }
}

/// 小型のスコア「3  11:27  35」（青キル・時刻・赤キル）。キルの下に小さく破壊タワー数。
/// 色覚サポートではチームの形（ブルー = 丸、レッド = ひし形）を添える。
struct HUDScoreCapsule: View, Equatable {
    let top: HUDTopSnapshot
    let colorblind: Bool
    let scale: CGFloat

    var body: some View {
        let blue = Theme.teamColor(.blue, colorblind: colorblind)
        let red = Theme.teamColor(.red, colorblind: colorblind)
        let clock = HUDStyle.clock(Double(top.seconds))
        HStack(spacing: 0) {
            teamSide(top.blueKills, towers: top.blueTowers, color: blue, symbol: "circle.fill", leading: true)
            Text(clock)
                .font(.system(size: 12.5 * scale, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.94))
                .shadow(color: .black.opacity(0.5), radius: 1, y: 0.5)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .layoutPriority(1)
            teamSide(top.redKills, towers: top.redTowers, color: red, symbol: "diamond.fill", leading: false)
        }
        .padding(.horizontal, 5 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
                .fill(LinearGradient(stops: [.init(color: blue.opacity(0.45), location: 0),
                                             .init(color: HUDStyle.glassBottom, location: 0.34),
                                             .init(color: HUDStyle.glassBottom, location: 0.66),
                                             .init(color: red.opacity(0.45), location: 1)],
                                     startPoint: .leading, endPoint: .trailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
                .strokeBorder(LinearGradient(colors: [blue.opacity(0.75), Color.white.opacity(0.16), red.opacity(0.75)],
                                             startPoint: .leading, endPoint: .trailing), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("キル数 ブルー \(top.blueKills) 対 レッド \(top.redKills)、破壊タワー ブルー \(top.blueTowers) 対 レッド \(top.redTowers)、経過 \(clock)",
                              "Kills Blue \(top.blueKills) to Red \(top.redKills), towers destroyed Blue \(top.blueTowers) to Red \(top.redTowers), time \(clock)"))
        .accessibilityIdentifier("hud_score")
    }

    /// チームのキル数と、その下に破壊したタワー数。
    private func teamSide(_ kills: Int, towers: Int, color: Color, symbol: String, leading: Bool) -> some View {
        VStack(spacing: -1 * scale) {
            HStack(spacing: 2 * scale) {
                if colorblind && leading { mark(symbol, color: color) }
                Text("\(kills)")
                    .font(.system(size: 16 * scale, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .shadow(color: .black.opacity(0.6), radius: 1, y: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if colorblind && !leading { mark(symbol, color: color) }
            }
            HStack(spacing: 1.5 * scale) {
                Image(systemName: Self.towerSymbol)
                    .font(.system(size: 6 * scale, weight: .bold))
                Text("\(towers)")
                    .font(.system(size: 7.5 * scale, weight: .heavy, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(color.opacity(0.9))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    private func mark(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 6 * scale, weight: .bold))
            .foregroundStyle(color)
    }

    /// 破壊タワー数のアイコン。
    static let towerSymbol = "building.2.fill"
}

// MARK: - 味方の状態列（スコアのミニマップ側）

/// 味方（自分以外、最大 4 人）の顔と HP。味方の状態だけを観測する（HP は 1/40 刻みで変わった時だけ）。
private struct HUDAllyStrip: View {
    let model: HUDModel
    let layout: HUDLayout

    var body: some View {
        let allies = Array(model.allies.prefix(HUDLayout.allyStripMax))
        let colorblind = model.settings.colorblindMode
        HStack(alignment: .top, spacing: layout.allySpacing) {
            ForEach(Array(allies.enumerated()), id: \.element.id) { index, ally in
                HUDAllyIcon(ally: ally, index: index, size: layout.allyFaceSize,
                            barGap: layout.allyBarGap, barHeight: layout.allyBarHeight, colorblind: colorblind)
                    .equatable()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("味方", "Allies"))
        .accessibilityIdentifier("hud_allies")
    }
}

/// 味方 1 人: 角丸の顔、下に細い HP バー。倒れている間は顔を白黒で暗くし、中央に赤い復活秒数。
/// 必殺技が使える時は右上に小さな金の点。
struct HUDAllyIcon: View, Equatable {
    let ally: HUDAllyStatus
    let index: Int
    let size: CGFloat
    let barGap: CGFloat
    let barHeight: CGFloat
    let colorblind: Bool

    /// HP がこの割合未満で HP バーを赤くする。
    static let lowHPRatio = 0.3

    var body: some View {
        let corner = size * 0.2
        VStack(spacing: barGap) {
            HeroPortraitView(heroID: ally.heroID, size: size, showsRole: false)
                .saturation(ally.isDead ? 0 : 1)
                .overlay {
                    if ally.isDead {
                        RoundedRectangle(cornerRadius: corner, style: .continuous).fill(Color.black.opacity(0.25))
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(Theme.teamColor(.blue, colorblind: colorblind).opacity(ally.isDead ? 0.25 : 0.7),
                                      lineWidth: 1)
                )
                .overlay {
                    if ally.isDead {
                        HUDOutlinedNumber(value: ally.respawn, size: size * 0.66)
                            .transition(.scale(scale: 1.3).combined(with: .opacity))
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if ally.ultReady && !ally.isDead {
                        Circle()
                            .fill(RadialGradient(colors: [.white, Theme.gold], center: .center, startRadius: 0, endRadius: 3.5))
                            .overlay(Circle().strokeBorder(Color.black.opacity(0.6), lineWidth: 0.8))
                            .frame(width: 7, height: 7)
                            .shadow(color: Theme.gold.opacity(0.9), radius: 2.5)
                            .offset(x: 2.5, y: -2.5)
                    }
                }
            bar
        }
        .animation(.easeInOut(duration: 0.25), value: ally.isDead)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityName(ally))
        .accessibilityValue(Self.accessibilityStatus(ally))
        .accessibilityIdentifier("hud_ally_\(index)")
    }

    private var bar: some View {
        let ratio = min(1, max(0, ally.hpRatio))
        return ZStack(alignment: .leading) {
            Capsule().fill(Color.black.opacity(0.6))
            Capsule()
                .fill(ratio < Self.lowHPRatio ? HUDStyle.hpLow : HUDStyle.hp)
                .frame(width: size * ratio)
        }
        .frame(width: size, height: barHeight)
        .overlay(Capsule().strokeBorder(Color.black.opacity(0.5), lineWidth: 0.5))
        .opacity(ally.isDead ? 0.5 : 1)
    }

    static func accessibilityName(_ ally: HUDAllyStatus) -> String {
        MasterData.shared.hero(ally.heroID).map { MasterText.hero($0) } ?? ally.heroID
    }

    /// VoiceOver の値（倒れている: 「復活まで N 秒」、生存: 「HP N%」と必殺技の可否）。
    static func accessibilityStatus(_ ally: HUDAllyStatus) -> String {
        if ally.isDead { return L("復活まで \(ally.respawn) 秒", "Respawns in \(ally.respawn) s") }
        let hp = Int((min(1, max(0, ally.hpRatio)) * 100).rounded())
        let status = L("HP \(hp)%", "HP \(hp)%")
        return ally.ultReady ? status + L("、必殺技 使用可能", ", ultimate ready") : status
    }
}

/// 黒い縁取りの赤い太字の数字（倒れた味方の復活秒数）。
struct HUDOutlinedNumber: View {
    let value: Int
    let size: CGFloat
    var color = Color(red: 1.0, green: 0.22, blue: 0.20)

    var body: some View {
        let text = Text("\(value)")
            .font(.system(size: size, weight: .black, design: .rounded))
            .monospacedDigit()
        let w = max(1, size * 0.07)
        ZStack {
            // 8 方向にずらした黒で縁取る
            ForEach(0..<8, id: \.self) { k in
                let a = Double(k) * .pi / 4
                text.foregroundStyle(Color.black.opacity(0.9))
                    .offset(x: cos(a) * w, y: sin(a) * w)
            }
            text.foregroundStyle(color)
        }
        .fixedSize()
        .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
        .accessibilityHidden(true)
    }
}

// MARK: - 情報側（K/D/A・CS・スコアボード）

/// 右上（左利きは左上）の列。操作中: 自分の成績 + スコアボード、観戦: スコアボード・一時停止・退出。
struct HUDTopRight: View {
    let model: HUDModel
    let layout: HUDLayout

    var body: some View {
        let spectating = model.isSpectating
        HStack(alignment: .top, spacing: 6) {
            if spectating {
                // 観戦・リプレイ: 従来どおりスコアボード・一時停止・退出
                HUDRoundButton(symbol: "list.bullet.rectangle.fill", label: L("スコアボード", "Scoreboard"),
                               identifier: "hud_scoreboard") { toggleScoreboard() }
                HUDRoundButton(symbol: "pause.fill", label: L("ポーズ・設定", "Pause & Settings"), identifier: "hud_pause") {
                    model.openPanel(.pause)
                }
                // ホストの実況は観戦の画面でも試合を回している: やめると全員の試合が終わる（確認もその旨を出す）
                let hostCaster = model.controller.isOnlineHost
                HUDRoundButton(symbol: hostCaster ? "stop.circle.fill" : "rectangle.portrait.and.arrow.right",
                               label: hostCaster ? L("全員の試合を終了", "End the match for everyone")
                                                 : L("観戦をやめる", "Leave"),
                               identifier: "spectate_leave", tint: Theme.danger) {
                    model.requestLeave()
                }
            } else {
                // 成績の欄はボタンの見た目と中心の高さをそろえる（ボタンのタップ領域は下へ広げる）
                HUDPlayerStats(top: model.top, scale: layout.topScale)
                    .equatable()
                    .padding(.top, max(0, (layout.utilityButtonSize - layout.topStatsHeight) / 2))
                HUDUtilityButton(symbol: "list.bullet.rectangle.fill", label: L("スコアボード", "Scoreboard"),
                                 identifier: "hud_scoreboard", size: layout.utilityButtonSize,
                                 hitAlignment: .top) { toggleScoreboard() }
            }
        }
        .fixedSize()
        .opacity(model.isAiming ? 0.25 : 1)
    }

    private func toggleScoreboard() {
        if model.panel == .scoreboard { model.closePanel() } else { model.openPanel(.scoreboard) }
    }
}

/// 自分の成績: キル（剣）・デス（ドクロ）・アシスト（拍手）・CS。
struct HUDPlayerStats: View, Equatable {
    let top: HUDTopSnapshot
    let scale: CGFloat

    /// アシストのアイコン（SF Symbols に握手は無いため、iOS 14 からある拍手）。
    static let assistSymbol = "hands.clap.fill"
    static let creepSymbol = "person.3.fill"

    /// 試合時間（毎秒変わる）では描き直さない。
    static func == (a: Self, b: Self) -> Bool {
        a.top.kills == b.top.kills && a.top.deaths == b.top.deaths && a.top.assists == b.top.assists
            && a.top.creepScore == b.top.creepScore && a.scale == b.scale
    }

    var body: some View {
        let icon = 11 * scale
        HStack(spacing: 7 * scale) {
            stat(top.kills) {
                HUDCrossedSwords().fill(Color.white.opacity(0.85)).frame(width: icon * 1.15, height: icon * 1.15)
            }
            .accessibilityLabel(L("キル \(top.kills)", "Kills \(top.kills)"))
            stat(top.deaths) {
                HUDSkull().fill(Color.white.opacity(0.85)).frame(width: icon * 0.92, height: icon * 0.92)
            }
            .accessibilityLabel(L("デス \(top.deaths)", "Deaths \(top.deaths)"))
            stat(top.assists) {
                Image(systemName: Self.assistSymbol)
                    .font(.system(size: icon * 0.82, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: icon, height: icon)
            }
            .accessibilityLabel(L("アシスト \(top.assists)", "Assists \(top.assists)"))
            Rectangle().fill(Color.white.opacity(0.18)).frame(width: 1, height: 12 * scale)
            stat(top.creepScore) {
                Image(systemName: Self.creepSymbol)
                    .font(.system(size: icon * 0.78, weight: .bold))
                    .foregroundStyle(Theme.gold)
            }
            .accessibilityLabel("CS \(top.creepScore)")
        }
        .font(.system(size: 13 * scale, weight: .heavy, design: .rounded))
        .monospacedDigit()
        .padding(.horizontal, 9 * scale)
        .frame(height: 26 * scale)
        .hudGlass(cornerRadius: 13 * scale)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("hud_kda")
    }

    private func stat<Icon: View>(_ value: Int, @ViewBuilder icon: () -> Icon) -> some View {
        HStack(spacing: 2.5 * scale) {
            icon()
            Text("\(value)").foregroundStyle(.white)
        }
        .accessibilityElement(children: .ignore)
    }
}

/// 小さなドクロ（デス数のアイコン）。頭蓋と顎の輪郭から目・鼻・歯の隙間を抜く。
struct HUDSkull: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func r(_ x: CGFloat, _ y: CGFloat, _ rw: CGFloat, _ rh: CGFloat) -> CGRect {
            CGRect(x: rect.minX + x * w, y: rect.minY + y * h, width: rw * w, height: rh * h)
        }
        let cranium = Path(ellipseIn: r(0.06, 0, 0.88, 0.76))
        let jaw = Path(roundedRect: r(0.24, 0.52, 0.52, 0.48), cornerSize: CGSize(width: 0.1 * w, height: 0.1 * h))
        var holes = Path()
        holes.addEllipse(in: r(0.19, 0.32, 0.25, 0.25))
        holes.addEllipse(in: r(0.56, 0.32, 0.25, 0.25))
        // 鼻
        holes.move(to: CGPoint(x: rect.minX + 0.5 * w, y: rect.minY + 0.58 * h))
        holes.addLine(to: CGPoint(x: rect.minX + 0.43 * w, y: rect.minY + 0.71 * h))
        holes.addLine(to: CGPoint(x: rect.minX + 0.57 * w, y: rect.minY + 0.71 * h))
        holes.closeSubpath()
        // 歯の隙間
        holes.addRect(r(0.39, 0.82, 0.06, 0.18))
        holes.addRect(r(0.55, 0.82, 0.06, 0.18))
        return cranium.union(jaw).subtracting(holes)
    }
}

// MARK: - 配置（上部）

extension HUDLayout {
    /// 上部の部品の倍率（大きい端末でも上部は控えめに）。
    var topScale: CGFloat { min(scale, 1.1) }

    /// 上端の帯（味方の顔・スコア・成績）の中心の高さ。
    var topBandMidY: CGFloat { topEdge + allyStripHeight / 2 }

    // MARK: スコア

    /// 中央のスコアの大きさ（参考画面の「3 11:27 35」程度。キルの下に破壊タワー数）。
    var scoreSize: CGSize { CGSize(width: 102 * topScale, height: 30 * topScale) }

    /// 中央のスコア（味方の顔の帯と中心の高さをそろえる）。
    var scoreFrame: CGRect {
        let s = scoreSize
        return CGRect(x: width / 2 - s.width / 2, y: topBandMidY - s.height / 2, width: s.width, height: s.height)
    }

    // MARK: 味方列

    static let allyStripMax = 4
    var allySpacing: CGFloat { 3 * topScale }
    var allyBarGap: CGFloat { 2 }
    var allyBarHeight: CGFloat { 3 }
    /// 味方列とスコア・縦列の間の隙間。
    var allyGap: CGFloat { 4 * topScale }

    /// 味方列はスコアのミニマップ側（右手配置は左、左利きは右）。人数が少ない時はスコア側へ寄せる。
    var allyStripAlignment: Alignment { leftHanded ? .topLeading : .topTrailing }

    /// 縦列とスコアの間で味方列に使える幅。
    private var allyRoom: CGFloat {
        let scoreHalf = scoreSize.width / 2
        if leftHanded {
            return (utilityColumnMinX - allyGap) - (width / 2 + scoreHalf + allyGap)
        }
        return (width / 2 - scoreHalf - allyGap) - (utilityColumnMinX + utilityHitSize + allyGap)
    }

    /// 味方の顔（角丸）の一辺。狭い端末では縦列とスコアの間に 4 人が収まる大きさまで縮める。
    var allyFaceSize: CGFloat {
        let n = CGFloat(Self.allyStripMax)
        let fit = (allyRoom - allySpacing * (n - 1)) / n
        return max(20, min(28, 26 * scale, fit.rounded(.down)))
    }

    var allyStripHeight: CGFloat { allyFaceSize + allyBarGap + allyBarHeight }

    /// 味方列（最大 4 人分）。
    var allyStripFrame: CGRect {
        let n = CGFloat(Self.allyStripMax)
        let w = allyFaceSize * n + allySpacing * (n - 1)
        let scoreHalf = scoreSize.width / 2
        let x = leftHanded ? width / 2 + scoreHalf + allyGap : width / 2 - scoreHalf - allyGap - w
        return CGRect(x: x, y: topEdge, width: w, height: allyStripHeight)
    }

    // MARK: ミニマップ横の縦列

    static let utilityButtonCount = 3
    /// 縦列のボタンの見た目の直径（タップ領域は utilityHitSize）。
    var utilityButtonSize: CGFloat { min(34, 32 * scale) }
    var utilityHitSize: CGFloat { max(44, utilityButtonSize) }
    /// 端末状態（電池・時刻）の行の高さ。
    var utilityStatusHeight: CGFloat { 14 }
    /// ミニマップとタップ領域の隙間（見た目のボタンとは 7pt ほど空く）。
    var utilityColumnGap: CGFloat { 2 }

    /// 縦列のタップ領域の左端（ミニマップの内側 = 右手配置は右、左利きは左）。
    var utilityColumnMinX: CGFloat {
        leftHanded ? minimapFrame.minX - utilityColumnGap - utilityHitSize : minimapFrame.maxX + utilityColumnGap
    }

    /// 縦列の中心 x。
    var utilityColumnX: CGFloat { utilityColumnMinX + utilityHitSize / 2 }

    var utilityStatusFrame: CGRect {
        CGRect(x: utilityColumnMinX, y: topEdge, width: utilityHitSize, height: utilityStatusHeight)
    }

    /// 縦列のボタン（0 = 設定、1 = 消音、2 = ズーム）のタップ領域。
    func utilityButtonFrame(_ index: Int) -> CGRect {
        CGRect(x: utilityColumnMinX, y: utilityStatusFrame.maxY + CGFloat(index) * utilityHitSize,
               width: utilityHitSize, height: utilityHitSize)
    }

    /// 端末状態と各ボタンのタップ領域（重なりの確認用）。
    var utilityFrames: [CGRect] {
        [utilityStatusFrame] + (0..<Self.utilityButtonCount).map { utilityButtonFrame($0) }
    }

    /// 縦列全体の外接矩形。
    var utilityColumnFrame: CGRect {
        utilityStatusFrame.union(utilityButtonFrame(Self.utilityButtonCount - 1))
    }

    // MARK: 情報側（右上 / 左利きは左上）

    /// 自分の成績（K/D/A・CS）の欄の高さ。
    var topStatsHeight: CGFloat { 26 * topScale }
    /// 自分の成績の欄に確保する幅（2 桁の K/D/A と 3 桁の CS まで収まる）。
    var topStatsWidth: CGFloat { 176 * topScale }

    /// 情報側の列（操作中: 成績 + スコアボード、観戦: スコアボード・一時停止・退出）。Safe Area の内側の端に寄せる。
    func topInfoFrame(spectating: Bool) -> CGRect {
        let w = spectating ? topButtonSize * 3 + 12 : topStatsWidth + 6 + utilityHitSize
        let h = spectating ? topButtonSize : utilityHitSize
        return CGRect(x: leftHanded ? leadingEdge : trailingEdge - w, y: topEdge, width: w, height: h)
    }
}
