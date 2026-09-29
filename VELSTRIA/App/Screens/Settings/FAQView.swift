import SwiftUI
import VelstriaCore

// 担当: ui-liveops。UI068 よくある質問（カテゴリ別・開閉式）。

struct FAQEntry: Identifiable, Equatable {
    enum Category: String, CaseIterable, Identifiable {
        case controls, gameplay, purchases, data, safety
        var id: String { rawValue }

        var title: String {
            switch self {
            case .controls: return L("操作", "Controls")
            case .gameplay: return L("ゲーム", "Gameplay")
            case .purchases: return L("購入", "Purchases")
            case .data: return L("データ", "Data")
            case .safety: return L("年齢・安全", "Age & Safety")
            }
        }

        var symbol: String {
            switch self {
            case .controls: return "gamecontroller.fill"
            case .gameplay: return "shield.lefthalf.filled"
            case .purchases: return "creditcard.fill"
            case .data: return "externaldrive.fill"
            case .safety: return "person.2.badge.gearshape.fill"
            }
        }
    }

    let id: String
    let category: Category
    let questionJa: String
    let questionEn: String
    let answerJa: String
    let answerEn: String

    var question: String { L(questionJa, questionEn) }
    var answer: String { L(answerJa, answerEn) }
}

enum FAQCatalog {
    static let entries: [FAQEntry] = [
        FAQEntry(id: "controls_aim", category: .controls,
                 questionJa: "スキルの狙い方を変えられますか？", questionEn: "Can I change how skills are aimed?",
                 answerJa: "設定 > 操作 の「スキル発動」で選べます。スマートはタップで自動照準、マニュアルは常にドラッグして狙い、指を離して発動します。",
                 answerEn: "Yes. In Settings > Controls, choose Skill Casting. Smart auto-aims on tap; Manual always lets you drag to aim and casts on release."),
        FAQEntry(id: "controls_left", category: .controls,
                 questionJa: "左利きでも遊びやすくできますか？", questionEn: "Is there a left-handed layout?",
                 answerJa: "設定 > 操作 の「左利きレイアウト」をオンにすると、スティックが右、スキルボタンが左に入れ替わります。HUD の不透明度も調整できます。",
                 answerEn: "Turn on Left-handed Layout in Settings > Controls to swap the stick to the right and skills to the left. You can also adjust HUD opacity."),
        FAQEntry(id: "controls_target", category: .controls,
                 questionJa: "通常攻撃で狙う相手を選びたい", questionEn: "How do I choose what basic attacks target?",
                 answerJa: "設定 > 操作 の「攻撃優先」で、ヒーロー・ミニオン・建物・低HP のいずれを優先するか選べます。",
                 answerEn: "Pick Heroes, Minions, Structures or Low HP under Attack Priority in Settings > Controls."),
        FAQEntry(id: "gameplay_offline", category: .gameplay,
                 questionJa: "オフラインで遊べますか？", questionEn: "Can I play offline?",
                 answerJa: "はい。すべての対戦は AI の味方・敵と行うため、インターネット接続なしで遊べます。購入時のみ App Store への接続が必要です。",
                 answerEn: "Yes. Every match is played with AI allies and opponents, so no internet connection is needed. Only purchases require the App Store."),
        FAQEntry(id: "gameplay_pvp", category: .gameplay,
                 questionJa: "他のプレイヤーと対戦できますか？", questionEn: "Can I play against other people?",
                 answerJa: "現在のバージョンでは、プレイヤー 1 人と AI 9 体による 5 対 5 の対戦のみです。",
                 answerEn: "In the current version, matches are 5v5 with you and nine AI heroes."),
        FAQEntry(id: "gameplay_ranked", category: .gameplay,
                 questionJa: "ランク戦の仕組みは？", questionEn: "How does Ranked work?",
                 answerJa: "対 AI のランク戦で、勝利で星 +1、敗北で星 −1 となります（隕鉄は降格なし）。ランクが上がるほど AI が強くなります。",
                 answerEn: "Ranked is played against AI. Wins add a star and losses remove one (no demotion in Meteorite). Higher ranks face stronger AI."),
        FAQEntry(id: "gameplay_surrender", category: .gameplay,
                 questionJa: "試合を途中で終えたい", questionEn: "Can I end a match early?",
                 answerJa: "試合開始 8:00 以降に降参を提案できます。大きく不利な場合に AI 味方が賛成し、5 人中 3 人の賛成で成立します。",
                 answerEn: "From 8:00 you can propose a surrender. AI allies agree when the team is far behind; 3 of 5 votes are needed."),
        FAQEntry(id: "purchases_p2w", category: .purchases,
                 questionJa: "課金すると強くなりますか？", questionEn: "Do purchases make me stronger?",
                 answerJa: "いいえ。販売しているのは見た目を変えるコスメとヒーローの解放のみで、対戦の強さに影響するものは販売していません。",
                 answerEn: "No. Only cosmetics and hero unlocks are sold. Nothing that affects battle power is for sale."),
        FAQEntry(id: "purchases_refund", category: .purchases,
                 questionJa: "返金を希望したい", questionEn: "How do I request a refund?",
                 answerJa: "App Store での購入は Apple が管理しています。Apple の「問題を報告する」ページ（reportaproblem.apple.com）から返金をリクエストしてください。返金された場合、付与済みのジェムが差し引かれることがあります。",
                 answerEn: "App Store purchases are handled by Apple. Request a refund at reportaproblem.apple.com. Refunded gems may be deducted from your balance."),
        FAQEntry(id: "purchases_missing", category: .purchases,
                 questionJa: "購入したジェムが反映されません", questionEn: "My purchased gems didn't arrive",
                 answerJa: "通信状態を確認してアプリを再起動してください。未完了の購入は起動時に自動で処理されます。スターパス プレミアムはストアの「購入の復元」で復元できます。解決しない場合はお問い合わせください。",
                 answerEn: "Check your connection and restart the app; unfinished purchases are processed at launch. The Star Pass Premium can be recovered via Restore Purchases. Contact us if it persists."),
        FAQEntry(id: "data_backup", category: .data,
                 questionJa: "データはどこに保存されますか？", questionEn: "Where is my data stored?",
                 answerJa: "すべてのデータはこの端末内にのみ保存され、サーバーには送信されません。設定 > データ引き継ぎ からバックアップを書き出せます。",
                 answerEn: "All data is stored only on this device and never sent to a server. Export a backup from Settings > Data Transfer."),
        FAQEntry(id: "data_transfer", category: .data,
                 questionJa: "機種変更するときは？", questionEn: "I'm switching to a new iPhone",
                 answerJa: "旧端末の 設定 > データ引き継ぎ でバックアップを書き出し、新しい端末で同じ画面から読み込んでください。",
                 answerEn: "Export a backup from Settings > Data Transfer on your old device, then import it from the same screen on the new one."),
        FAQEntry(id: "data_delete", category: .data,
                 questionJa: "アプリを削除するとどうなりますか？", questionEn: "What happens if I delete the app?",
                 answerJa: "端末内のデータ（所持品・通貨・戦績・リプレイ）はすべて消去され、復元できません。削除する前にバックアップを書き出してください。",
                 answerEn: "All on-device data (items, currencies, history, replays) is erased and cannot be recovered. Export a backup first."),
        FAQEntry(id: "safety_limits", category: .safety,
                 questionJa: "年齢による購入の上限はありますか？", questionEn: "Are there spending limits by age?",
                 answerJa: "はい。15 歳以下は月 5,000 円、16〜19 歳は月 10,000 円までに制限しています。年齢区分は初回起動時に確認します。",
                 answerEn: "Yes. Players aged 15 or under are limited to ¥5,000 per month, and ages 16–19 to ¥10,000. Your age group is confirmed on first launch."),
        FAQEntry(id: "safety_parents", category: .safety,
                 questionJa: "保護者の方へ", questionEn: "For parents and guardians",
                 answerJa: "iOS の「スクリーンタイム」でアプリ内課金の制限やプレイ時間の管理ができます。本作にはチャットなど他者と交流する機能はありません。",
                 answerEn: "Use iOS Screen Time to restrict in-app purchases and manage play time. The game has no chat or other ways to interact with strangers."),
    ]
}

struct FAQView: View {
    @Environment(AppModel.self) private var app
    @State private var category: FAQEntry.Category?
    @State private var expanded: Set<String> = []

    var body: some View {
        let entries = FAQCatalog.entries.filter { category == nil || $0.category == category }
        ScreenScaffold(title: L("よくある質問", "FAQ"), showsCurrencies: false) {
            HStack(alignment: .top, spacing: 14) {
                ScrollView(.vertical, showsIndicators: false) {
                    Panel(padding: 10) {
                        LiveOpsSegmented(options: [LiveOpsSegmentOption<FAQEntry.Category?>(value: nil, title: L("すべて", "All"),
                                                                                               symbol: "square.grid.2x2.fill", identifier: "faq_category_all")]
                                         + FAQEntry.Category.allCases.map {
                                             LiveOpsSegmentOption(value: Optional($0), title: $0.title, symbol: $0.symbol, identifier: "faq_category_\($0.rawValue)")
                                         },
                                         selection: $category, axis: .vertical, onChange: { _ in app.audio.play(.uiTap) })
                    }
                }
                .frame(width: 200)
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 8) {
                        ForEach(entries) { entry in
                            row(entry)
                        }
                        contactFooter
                    }
                    .padding(.bottom, 10)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }

    private func row(_ entry: FAQEntry) -> some View {
        let open = expanded.contains(entry.id)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                app.audio.play(.uiTap)
                withAnimation(.easeInOut(duration: 0.2)) {
                    if open { expanded.remove(entry.id) } else { expanded.insert(entry.id) }
                }
            } label: {
                HStack(spacing: 10) {
                    Text("Q")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.gold)
                    Text(entry.question)
                        .font(Theme.heading(14))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(entry.question)
            .accessibilityValue(open ? L("展開", "Expanded") : L("折りたたみ", "Collapsed"))
            .accessibilityIdentifier("faq_\(entry.id)")
            if open {
                HStack(alignment: .top, spacing: 10) {
                    Text("A")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.cyan)
                    Text(entry.answer)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textPrimary.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.bottom, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(open ? Color.white.opacity(0.08) : Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(open ? Theme.cyan.opacity(0.45) : Theme.panelStroke, lineWidth: 1))
        .clipped()
    }

    private var contactFooter: some View {
        HStack(spacing: 10) {
            Text(L("解決しない場合はお問い合わせください。", "Still need help? Contact us."))
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Button {
                app.audio.play(.uiTap)
                app.router.push(.contact)
            } label: {
                Label(L("お問い合わせ", "Contact Us"), systemImage: "envelope.fill").lineLimit(1)
            }
            .buttonStyle(LiveOpsTallButtonStyle(base: SecondaryButtonStyle()))
            .accessibilityIdentifier("faq_contact")
        }
        .padding(.top, 4)
    }
}
