import SwiftUI
import VelstriaCore

// 担当: battle-hud。観戦・リプレイの操作（controller.isSpectating）:
// 再生速度（1×/2×/4×）・一時停止・10 体のヒーローから追従対象を選ぶ・両チームのミニスコア・リプレイの進行バー。
// 自由カメラはミニマップで操作する。

struct HUDSpectateBar: View {
    let model: HUDModel
    let layout: HUDLayout

    var body: some View {
        let snap = model.spectate
        let cb = model.settings.colorblindMode
        VStack(spacing: 6) {
            if let final = snap.finalTick, final > 0 {
                replayProgress(tick: snap.tick, final: final)
            }
            HStack(spacing: 10) {
                heroRow(snap.heroes.filter { $0.team == .blue }, colorblind: cb)
                controls
                heroRow(snap.heroes.filter { $0.team == .red }, colorblind: cb)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .hudGlass(cornerRadius: 16)
    }

    private var controls: some View {
        HStack(spacing: 4) {
            Button { model.toggleSpectatorPause() } label: {
                Image(systemName: model.spectatorPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.1)))
                    .contentShape(Circle())
            }
            .buttonStyle(HUDPressStyle())
            .accessibilityLabel(model.spectatorPaused ? L("再生", "Play") : L("一時停止", "Pause"))
            .accessibilityIdentifier("spectate_pause")
            ForEach([1.0, 2.0, 4.0], id: \.self) { speed in
                let selected = model.controller.speed == speed
                Button { model.setSpeed(speed) } label: {
                    Text("\(Int(speed))×")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(selected ? Color.black : .white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(selected ? Theme.gold : Color.white.opacity(0.1)))
                        .contentShape(Circle())
                }
                .buttonStyle(HUDPressStyle())
                .accessibilityLabel(L("再生速度 \(Int(speed)) 倍", "Speed \(Int(speed))x"))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("spectate_speed_\(Int(speed))x")
            }
        }
    }

    private func heroRow(_ heroes: [HUDSpectateHero], colorblind: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(heroes) { h in
                let focused = model.cameraFollowID == h.id
                let color = Theme.teamColor(h.team, colorblind: colorblind)
                Button { model.follow(h.id) } label: {
                    VStack(spacing: 2) {
                        ZStack {
                            HeroPortraitView(heroID: h.heroID, size: 36, showsRole: false)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .saturation(h.isDead ? 0 : 1)
                            if h.isDead {
                                Text("\(Int(h.respawn))")
                                    .font(.system(size: 14, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black, radius: 2)
                            }
                            Text("\(h.level)")
                                .font(.system(size: 9, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 3)
                                .background(Capsule().fill(Color.black.opacity(0.8)))
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        }
                        .frame(width: 36, height: 36)
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(focused ? Color.white : color, lineWidth: focused ? 2.5 : 1.2))
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.black.opacity(0.6))
                                Capsule().fill(h.hpRatio < 0.3 ? HUDStyle.hpLow : HUDStyle.hp)
                                    .frame(width: g.size.width * CGFloat(h.isDead ? 0 : h.hpRatio))
                            }
                        }
                        .frame(width: 36, height: 4)
                    }
                    .frame(width: 40, height: 46)
                    .contentShape(Rectangle())
                }
                .buttonStyle(HUDPressStyle())
                .accessibilityLabel(MasterData.shared.hero(h.heroID).map { MasterText.hero($0) } ?? h.heroID)
                .accessibilityValue(L("レベル \(h.level)", "Level \(h.level)"))
                .accessibilityAddTraits(focused ? .isSelected : [])
                .accessibilityIdentifier("spectate_hero_\(h.id)")
            }
        }
    }

    private func replayProgress(tick: Int, final: Int) -> some View {
        let fraction = min(1, Double(tick) / Double(max(1, final)))
        return HStack(spacing: 8) {
            Image(systemName: "video.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.gold)
            Text(HUDStyle.clock(Double(tick) * 0.5))
                .font(.system(size: 11, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.5))
                    Capsule().fill(LinearGradient(colors: [Theme.gold, Theme.cyan], startPoint: .leading, endPoint: .trailing))
                        .frame(width: g.size.width * CGFloat(fraction))
                }
            }
            .frame(height: 6)
            Text(HUDStyle.clock(Double(final) * 0.5))
                .font(.system(size: 11, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white.opacity(0.7))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("リプレイの進行", "Replay progress"))
        .accessibilityValue("\(Int(fraction * 100))%")
        .accessibilityIdentifier("replay_progress")
    }
}

/// 観戦中の両チームのミニスコア（上部中央の下）。
struct HUDSpectateScore: View {
    let model: HUDModel

    var body: some View {
        let snap = model.spectate
        let top = model.top
        let cb = model.settings.colorblindMode
        HStack(spacing: 14) {
            side(gold: snap.blueGold, towers: top.blueTowers, color: Theme.teamColor(.blue, colorblind: cb))
            Text("VS").font(.system(size: 10, weight: .black, design: .rounded)).foregroundStyle(.white.opacity(0.5))
            side(gold: snap.redGold, towers: top.redTowers, color: Theme.teamColor(.red, colorblind: cb))
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
        .hudGlass(cornerRadius: 13)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("ゴールド ブルー \(snap.blueGold) レッド \(snap.redGold)", "Gold Blue \(snap.blueGold) Red \(snap.redGold)"))
    }

    private func side(gold: Int, towers: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                HUDCoin(size: 11)
                Text(String(format: "%.1fk", Double(gold) / 1000)).foregroundStyle(color)
            }
            HStack(spacing: 2) {
                Image(systemName: "building.columns.fill").font(.system(size: 9)).foregroundStyle(.white.opacity(0.7))
                Text("\(towers)").foregroundStyle(color)
            }
        }
        .font(.system(size: 12, weight: .heavy, design: .rounded))
        .monospacedDigit()
    }
}
