import SwiftUI
import VelstriaCore

// 担当: ui-liveops。UI070 パッチノート。

struct PatchNoteSection: Identifiable, Equatable {
    let id: String
    let symbol: String
    let titleJa: String
    let titleEn: String
    let itemsJa: [String]
    let itemsEn: [String]

    var title: String { L(titleJa, titleEn) }
    var items: [String] { Loc.isEnglish ? itemsEn : itemsJa }
}

struct PatchNote: Identifiable, Equatable {
    let version: String
    let headlineJa: String
    let headlineEn: String
    let sections: [PatchNoteSection]

    var id: String { version }
    var headline: String { L(headlineJa, headlineEn) }
}

enum PatchNotesCatalog {
    static let notes: [PatchNote] = [
        PatchNote(version: "1.0.0", headlineJa: "星環の戦場、開幕。", headlineEn: "The Star Ring battlefield opens.", sections: [
            PatchNoteSection(id: "highlights", symbol: "sparkles", titleJa: "主な内容", titleEn: "Highlights",
                             itemsJa: ["3 レーンの 5 対 5 バトル（プレイヤー + AI 味方 4 体 vs AI 敵 5 体）",
                                       "24 体のヒーローと 96 のアクティブスキル・24 のパッシブ",
                                       "72 種の装備、10 種のバトルスペル、30 種のルーン",
                                       "中立ボス「星喰竜」「古環の巨像」とジャングルキャンプ"],
                             itemsEn: ["3-lane 5v5 battles (you + 4 AI allies vs 5 AI enemies)",
                                       "24 heroes with 96 active skills and 24 passives",
                                       "72 items, 10 battle spells and 30 runes",
                                       "Neutral bosses Astral Wyrm and Ancient Colossus, plus jungle camps"]),
            PatchNoteSection(id: "modes", symbol: "gamecontroller.fill", titleJa: "モード", titleEn: "Modes",
                             itemsJa: ["通常戦（AI 難易度 3 段階）とランク戦（BAN あり・7 ランク）",
                                       "練習場（ゴールド無限・クールダウンなし・開始レベル指定）",
                                       "チュートリアル（5 章）とヒント集",
                                       "AI 同士の観戦と、最新 20 件のリプレイ再生"],
                             itemsEn: ["Standard (3 AI difficulty levels) and Ranked (with bans, 7 tiers)",
                                       "Practice (infinite gold, no cooldowns, custom starting level)",
                                       "5-chapter tutorial and tips library",
                                       "AI vs AI spectating and playback of your latest 20 replays"]),
            PatchNoteSection(id: "progression", symbol: "star.leadinghalf.filled", titleJa: "成長と報酬", titleEn: "Progression",
                             itemsJa: ["デイリー / ウィークリーミッションとイベント",
                                       "スターパス（無料 30 段階 + プレミアムトラック）",
                                       "実績・戦績・ヒーロー別の記録"],
                             itemsEn: ["Daily / weekly missions and events",
                                       "Star Pass (30 free levels + premium track)",
                                       "Achievements, match history and per-hero stats"]),
            PatchNoteSection(id: "access", symbol: "accessibility", titleJa: "快適さとアクセシビリティ", titleEn: "Comfort & Accessibility",
                             itemsJa: ["左利きレイアウト、HUD 不透明度、カメラ距離の調整",
                                       "色覚サポート（青 / 橙のチーム色と形状マーカー）",
                                       "字幕・触覚フィードバック・日本語 / English の即時切替"],
                             itemsEn: ["Left-handed layout, HUD opacity and camera distance",
                                       "Colorblind mode (blue / orange team colors with shape markers)",
                                       "Subtitles, haptics and instant Japanese / English switching"]),
            PatchNoteSection(id: "fair", symbol: "checkmark.shield.fill", titleJa: "公正なプレイ", titleEn: "Fair Play",
                             itemsJa: ["販売はコスメとヒーロー解放のみ。対戦の強さは購入できません",
                                       "すべてオフラインで動作し、データは端末内にのみ保存されます"],
                             itemsEn: ["Only cosmetics and hero unlocks are sold; battle power can't be bought",
                                       "Runs fully offline; your data stays on this device"]),
        ]),
    ]
}

struct PatchNotesView: View {
    @Environment(AppModel.self) private var app
    @State private var selected: String = PatchNotesCatalog.notes.first?.version ?? ""

    var body: some View {
        let note = PatchNotesCatalog.notes.first { $0.version == selected } ?? PatchNotesCatalog.notes.first
        ScreenScaffold(title: L("パッチノート", "Patch Notes"), showsCurrencies: false) {
            HStack(alignment: .top, spacing: 14) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(PatchNotesCatalog.notes) { n in
                            versionCard(n, isSelected: n.version == note?.version)
                        }
                    }
                }
                .frame(width: 200)
                if let note {
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(note.headline)
                                .font(Theme.title(20))
                                .foregroundStyle(LinearGradient(colors: [Theme.gold, .white], startPoint: .leading, endPoint: .trailing))
                                .accessibilityAddTraits(.isHeader)
                            ForEach(note.sections) { section in
                                SettingsSection(title: section.title, symbol: section.symbol) {
                                    ForEach(section.items, id: \.self) { item in
                                        HStack(alignment: .top, spacing: 8) {
                                            Circle().fill(Theme.cyan).frame(width: 5, height: 5).padding(.top, 7)
                                            Text(item)
                                                .font(Theme.body(13))
                                                .foregroundStyle(Theme.textPrimary.opacity(0.92))
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        .accessibilityElement(children: .combine)
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 10)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }

    private func versionCard(_ n: PatchNote, isSelected: Bool) -> some View {
        Button {
            app.audio.play(.uiTap)
            selected = n.version
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("v\(n.version)")
                        .font(Theme.heading(17))
                        .foregroundStyle(isSelected ? Theme.gold : Theme.textPrimary)
                    Spacer()
                    if n.version == AppVersionInfo.version {
                        LiveOpsTag(text: L("現在", "Current"), color: Theme.success)
                    }
                }
                Text(n.headline)
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(isSelected ? Theme.gold.opacity(0.12) : Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(isSelected ? Theme.gold : Theme.panelStroke, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("patch_notes_\(n.version)")
    }
}
