import SwiftUI
import VelstriaCore

// 担当: ui-liveops。UI056 報酬受取ポップアップ。
// ミッション・スターパス・イベントのほか、メールや実績など他画面からも `.rewardClaimPopup($content)` で再利用できる。

/// ポップアップに表示する内容。
struct RewardClaimContent: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var subtitle: String?
    var attachments: [MailAttachment]

    init(title: String = L("報酬獲得！", "Rewards Claimed!"), subtitle: String? = nil, attachments: [MailAttachment]) {
        self.title = title
        self.subtitle = subtitle
        self.attachments = attachments
    }
}

/// 添付（報酬）の表示名・記号。
enum RewardClaimText {
    /// 「スターライトコイン ×100」などの表示名。
    static func name(_ a: MailAttachment, master: MasterData = .shared) -> String {
        switch a.kind {
        case .coin: return L("スターライトコイン ×\(a.amount.formatted())", "Starlight Coin ×\(a.amount.formatted())")
        case .gem: return L("アストラルジェム ×\(a.amount.formatted())", "Astral Gem ×\(a.amount.formatted())")
        case .passXP: return L("パス XP ×\(a.amount.formatted())", "Pass XP ×\(a.amount.formatted())")
        case .cosmetic:
            if let id = a.refID, let def = master.cosmetic(id) { return MasterText.cosmetic(def) }
            return L("コスメティック", "Cosmetic")
        case .hero:
            if let id = a.refID, let def = master.hero(id) { return L("ヒーロー: ", "Hero: ") + MasterText.hero(def) }
            return L("ヒーロー", "Hero")
        }
    }

    /// タイル下段の短い名称。
    static func shortName(_ a: MailAttachment, master: MasterData = .shared) -> String {
        switch a.kind {
        case .coin: return L("コイン", "Coins")
        case .gem: return L("ジェム", "Gems")
        case .passXP: return L("パス XP", "Pass XP")
        case .cosmetic:
            if let id = a.refID, let def = master.cosmetic(id) { return MasterText.cosmetic(def) }
            return L("コスメティック", "Cosmetic")
        case .hero:
            if let id = a.refID, let def = master.hero(id) { return MasterText.hero(def) }
            return L("ヒーロー", "Hero")
        }
    }

    /// チップ・マス用の短い表記（数量、コスメは種類名）。
    static func chipText(_ a: MailAttachment, master: MasterData = .shared) -> String {
        switch a.kind {
        case .coin, .gem: return a.amount.formatted()
        case .passXP: return "\(a.amount.formatted()) XP"
        case .cosmetic:
            if let id = a.refID, let def = master.cosmetic(id) { return typeName(def.type) }
            return L("コスメ", "Cosmetic")
        case .hero: return shortName(a, master: master)
        }
    }

    static func typeName(_ t: CosmeticType) -> String {
        switch t {
        case .heroSkin: return L("スキン", "Skin")
        case .recall: return L("帰還演出", "Recall FX")
        case .spawn: return L("出現演出", "Spawn FX")
        case .emote: return L("エモート", "Emote")
        case .avatarFrame: return L("アイコン枠", "Frame")
        case .killEffect: return L("撃破演出", "Kill FX")
        }
    }

    /// 数量系（コイン・ジェム・パス XP）を合算し、コスメ・ヒーローは重複を除いて並べる（出現順を維持）。
    /// 合計 0 以下の数量系（付与できなかった報酬の代替など）は表示しない。
    static func merged(_ list: [MailAttachment]) -> [MailAttachment] {
        var result: [MailAttachment] = []
        for a in list {
            switch a.kind {
            case .coin, .gem, .passXP:
                if let i = result.firstIndex(where: { $0.kind == a.kind }) {
                    result[i].amount += a.amount
                } else {
                    result.append(a)
                }
            case .cosmetic, .hero:
                if !result.contains(where: { $0.kind == a.kind && $0.refID == a.refID }) {
                    result.append(a)
                }
            }
        }
        return result.filter { $0.kind == .cosmetic || $0.kind == .hero || $0.amount > 0 }
    }

    static func symbol(for type: CosmeticType) -> String {
        switch type {
        case .heroSkin: return "tshirt.fill"
        case .recall: return "arrow.uturn.backward.circle.fill"
        case .spawn: return "sparkle"
        case .emote: return "face.smiling.inverse"
        case .avatarFrame: return "person.crop.square.fill"
        case .killEffect: return "burst.fill"
        }
    }

    static let passXPColor = Color(red: 0.74, green: 0.56, blue: 1.0)
}

/// 添付のアイコン（コイン・ジェム・パス XP・コスメ・ヒーロー）。
struct RewardClaimIcon: View {
    let attachment: MailAttachment
    var size: CGFloat = 44
    @Environment(AppModel.self) private var app

    var body: some View {
        Group {
            switch attachment.kind {
            case .hero:
                HeroPortraitView(heroID: attachment.refID ?? "H001", size: size, showsRole: size >= 40)
            case .cosmetic:
                let def = attachment.refID.flatMap { app.master.cosmetic($0) }
                let tint = def.map { Theme.rarityColor($0.rarity) } ?? Theme.cyan
                symbolTile(def.map { RewardClaimText.symbol(for: $0.type) } ?? "sparkles", tint: tint)
            case .coin:
                symbolTile("star.circle.fill", tint: Theme.gold)
            case .gem:
                symbolTile("diamond.fill", tint: Theme.cyan)
            case .passXP:
                symbolTile("bolt.fill", tint: RewardClaimText.passXPColor)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(RewardClaimText.name(attachment))
    }

    private func symbolTile(_ symbol: String, tint: Color) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [tint.opacity(0.45), tint.opacity(0.08)], center: .center,
                                     startRadius: 1, endRadius: size * 0.6))
            Image(systemName: symbol)
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(tint)
                .shadow(color: tint.opacity(0.6), radius: size * 0.08)
        }
    }
}

/// UI056 報酬受取ポップアップ本体。
struct RewardClaimSheet: View {
    let content: RewardClaimContent
    let onClose: () -> Void
    @State private var appeared = false

    var body: some View {
        let items = RewardClaimText.merged(content.attachments)
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text(content.title)
                    .font(Theme.title(24))
                    .foregroundStyle(LinearGradient(colors: [Theme.gold, .white], startPoint: .top, endPoint: .bottom))
                    .accessibilityAddTraits(.isHeader)
                if let subtitle = content.subtitle {
                    Text(subtitle)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            ViewThatFits(in: .horizontal) {
                row(items)
                ScrollView(.horizontal, showsIndicators: false) { row(items).padding(.horizontal, 4) }
            }
            .frame(maxWidth: 560)
            Button {
                onClose()
            } label: {
                Text(L("OK", "OK")).frame(minWidth: 140, minHeight: 22)
            }
            .buttonStyle(LiveOpsTallButtonStyle(base: PrimaryButtonStyle()))
            .accessibilityIdentifier("reward_claim_ok")
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .top, endPoint: .bottom))
        )
        .background(
            // 背面の光条
            Circle()
                .fill(RadialGradient(colors: [Theme.gold.opacity(0.35), .clear], center: .center, startRadius: 10, endRadius: 260))
                .frame(width: 520, height: 520)
                .scaleEffect(appeared ? 1 : 0.3)
                .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(LinearGradient(colors: [Theme.gold.opacity(0.9), Theme.cyan.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.5), radius: 20)
        .scaleEffect(appeared ? 1 : 0.85)
        .onAppear {
            withAnimation(.spring(duration: 0.45, bounce: 0.35)) { appeared = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reward_claim_sheet")
    }

    private func row(_ items: [MailAttachment]) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                tile(item)
                    .scaleEffect(appeared ? 1 : 0.4)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(duration: 0.5, bounce: 0.4).delay(0.08 * Double(index) + 0.1), value: appeared)
            }
        }
        .padding(.vertical, 4)
    }

    private func tile(_ a: MailAttachment) -> some View {
        VStack(spacing: 6) {
            RewardClaimIcon(attachment: a, size: 60)
                .frame(width: 84, height: 84)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.panelStroke, lineWidth: 1))
            Text(RewardClaimText.shortName(a))
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 96)
            if a.kind == .coin || a.kind == .gem || a.kind == .passXP {
                Text("×\(a.amount.formatted())")
                    .font(Theme.mono(15))
                    .foregroundStyle(Theme.gold)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RewardClaimText.name(a))
    }
}

private struct RewardClaimPopupModifier: ViewModifier {
    @Binding var item: RewardClaimContent?
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        content
            .overlay {
                ZStack {
                    if let current = item {
                        Color.black.opacity(0.6)
                            .ignoresSafeArea()
                            .onTapGesture { dismiss() }
                            .accessibilityHidden(true)
                            .transition(.opacity)
                        RewardClaimSheet(content: current) { dismiss() }
                            .padding(20)
                            .id(current.id)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                            .accessibilityAddTraits(.isModal)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: item?.id)
            }
            .onChange(of: item?.id) { _, newValue in
                guard newValue != nil else { return }
                app.audio.play(.reward)
                app.haptics.success()
            }
    }

    private func dismiss() {
        app.audio.play(.uiTap)
        item = nil
    }
}

extension View {
    /// 報酬受取ポップアップ（UI056）を重ねて表示する。nil で閉じる。
    func rewardClaimPopup(_ item: Binding<RewardClaimContent?>) -> some View {
        modifier(RewardClaimPopupModifier(item: item))
    }
}
