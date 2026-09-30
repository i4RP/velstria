import Foundation
import RealityKit
import SwiftUI
import VelstriaCore

// 担当: hero-models。全ヒーローの 3D モデル一覧（起動引数 -heroGallery）。
// 追加の起動引数（スクリーンショット用）:
//   -galleryPage <0...>        0-3 = 6 体ずつ、4 以降 = スキン比較
//   -galleryState <idle|run|attack|skill1|skill2|skill3|ult|channel|stunned|dead|victory>
//   -galleryCamera <showcase|battle>
//   -galleryTeam <blue|red|none>
//   -galleryFreeze <秒>        指定秒だけ進めて静止
//   -galleryDetail <heroID>    単体プレビュー（HeroPreview3DView）を表示
//   -galleryYaw <度>           台の回転（側面・背面の確認）

struct HeroGalleryView: View {
    @Environment(AppModel.self) private var app
    @State private var page = 0
    @State private var stateKey = "idle"
    @State private var camera: HeroStageCamera = .showcase
    @State private var team: Team = .neutral
    @State private var freeze: Double?
    @State private var detailHeroID: String?
    @State private var detailSkin: String?
    @State private var didApplyArgs = false
    @State private var yaw: Float = 0

    private var master: MasterData { app.master }

    /// スキンを持つヒーロー（スキン比較ページ）。
    private var skinnedHeroes: [String] {
        master.heroes.map(\.heroID).filter { !HeroSkins.skins(for: $0, master: master).isEmpty }
    }

    private var rosterPages: Int { (master.heroes.count + 5) / 6 }
    private var pageCount: Int { rosterPages + skinnedHeroes.count }

    private static let states: [(String, String)] = [
        ("idle", "Idle"), ("run", "Run"), ("attack", "Attack"), ("skill1", "S1"), ("skill2", "S2"), ("skill3", "S3"),
        ("ult", "Ult"), ("channel", "Recall"), ("stunned", "Stun"), ("dead", "Dead"), ("victory", "Win"),
    ]

    private var animState: HeroAnimState {
        switch stateKey {
        case "run": return .run
        case "attack": return .attack
        case "skill1": return .cast(.skill1)
        case "skill2": return .cast(.skill2)
        case "skill3": return .cast(.skill3)
        case "ult": return .cast(.ultimate)
        case "channel": return .channel
        case "stunned": return .stunned
        case "dead": return .dead
        case "victory": return .victory
        default: return .idle
        }
    }

    private var slots: [HeroStageSlot] {
        if page < rosterPages {
            let ids = master.heroes.map(\.heroID)
            let start = page * 6
            return ids[start..<min(ids.count, start + 6)].map { HeroStageSlot(heroID: $0, skinID: nil) }
        }
        let heroID = skinnedHeroes[min(skinnedHeroes.count - 1, page - rosterPages)]
        return [HeroStageSlot(heroID: heroID, skinID: nil)]
            + HeroSkins.skins(for: heroID, master: master).map { HeroStageSlot(heroID: heroID, skinID: $0.cosmeticID) }
    }

    var body: some View {
        ZStack {
            StarfieldBackground()
            VStack(spacing: 0) {
                header
                ZStack(alignment: .bottom) {
                    HeroStageView(config: HeroStageConfig(slots: slots, team: team, state: animState, camera: camera,
                                                          freezeAt: freeze, showOverheadMarker: camera == .battle, yaw: yaw))
                    labels
                }
                stateBar
            }
            .padding(.horizontal, 12)
            if let id = detailHeroID {
                detail(id)
            }
        }
        .onAppear(perform: applyLaunchArgs)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("HERO GALLERY")
                .font(Theme.title(18))
                .foregroundStyle(Theme.textPrimary)
            Text(page < rosterPages ? "\(page + 1)/\(rosterPages)" : L("スキン", "Skins"))
                .font(Theme.mono(12))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Button { page = (page + pageCount - 1) % pageCount } label: { Image(systemName: "chevron.left") }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("gallery_prev")
            Button { page = (page + 1) % pageCount } label: { Image(systemName: "chevron.right") }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("gallery_next")
            Button { camera = camera == .showcase ? .battle : .showcase } label: {
                Image(systemName: camera == .showcase ? "person.fill.viewfinder" : "map")
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("gallery_camera")
            Button {
                team = team == .neutral ? .blue : (team == .blue ? .red : .neutral)
            } label: {
                Image(systemName: "circle.dashed")
                    .foregroundStyle(team == .neutral ? Theme.textSecondary : Theme.teamColor(team))
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("gallery_team")
        }
        .padding(.top, 6)
    }

    private var labels: some View {
        HStack(spacing: 0) {
            ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                Button {
                    detailHeroID = slot.heroID
                    detailSkin = slot.skinID
                } label: {
                    VStack(spacing: 1) {
                        if let def = master.hero(slot.heroID) {
                            HStack(spacing: 4) {
                                Image(systemName: Theme.roleSymbol(def.role))
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Theme.roleColor(def.role))
                                Text(MasterText.hero(def))
                                    .font(Theme.body(11))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                        Text(slotCaption(slot))
                            .font(Theme.mono(9))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.35)))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 4)
    }

    private func slotCaption(_ slot: HeroStageSlot) -> String {
        let skin = HeroSkins.resolve(heroID: slot.heroID, skinID: slot.skinID, master: master)
        let name = HeroSkins.variantName(skin.variant)
        return skin.variant == 0 ? "\(slot.heroID) · \(name)" : "\(name) · \(skin.rarity.rawValue)"
    }

    private var stateBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Self.states, id: \.0) { key, label in
                    Button {
                        stateKey = key
                        freeze = nil
                    } label: {
                        Text(label)
                            .font(Theme.heading(12))
                            .foregroundStyle(stateKey == key ? Color.black : Theme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(stateKey == key ? Theme.gold : Color.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("gallery_state_\(key)")
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func detail(_ heroID: String) -> some View {
        let skins = HeroSkins.skins(for: heroID, master: master)
        return ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture { detailHeroID = nil }
            HStack(spacing: 16) {
                HeroPreview3DView(heroID: heroID, skinID: detailSkin)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 10) {
                    if let def = master.hero(heroID) {
                        Text(MasterText.hero(def)).font(Theme.title(22)).foregroundStyle(Theme.textPrimary)
                        Label(MasterText.role(def.role), systemImage: Theme.roleSymbol(def.role))
                            .font(Theme.body(13)).foregroundStyle(Theme.roleColor(def.role))
                    }
                    ForEach([nil] + skins.map { Optional($0.cosmeticID) }, id: \.self) { id in
                        let info = HeroSkins.resolve(heroID: heroID, skinID: id, master: master)
                        Button {
                            detailSkin = id
                        } label: {
                            Text("\(HeroSkins.variantName(info.variant))\(info.isEpic ? " ✦" : "")")
                                .font(Theme.heading(13))
                                .foregroundStyle(detailSkin == id ? Color.black : Theme.textPrimary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(detailSkin == id ? Theme.rarityColor(info.rarity) : Color.white.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Button(L("閉じる", "Close")) { detailHeroID = nil }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("gallery_detail_close")
                }
                .frame(width: 220)
                .padding(.vertical, 20)
            }
            .padding(.horizontal, 30)
        }
    }

    private func applyLaunchArgs() {
        guard !didApplyArgs else { return }
        didApplyArgs = true
        if let p = DebugLaunch.value(after: "-galleryPage"), let n = Int(p) { page = max(0, min(pageCount - 1, n)) }
        if let s = DebugLaunch.value(after: "-galleryState") { stateKey = s }
        if DebugLaunch.value(after: "-galleryCamera") == "battle" { camera = .battle }
        switch DebugLaunch.value(after: "-galleryTeam") {
        case "blue": team = .blue
        case "red": team = .red
        default: break
        }
        if let f = DebugLaunch.value(after: "-galleryFreeze"), let t = Double(f) { freeze = t }
        if let y = DebugLaunch.value(after: "-galleryYaw"), let d = Float(y) { yaw = d * .pi / 180 }
        if let d = DebugLaunch.value(after: "-galleryDetail") {
            detailHeroID = d
            detailSkin = DebugLaunch.value(after: "-gallerySkin")
        }
    }
}
