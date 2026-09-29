import SwiftUI
import VelstriaCore

// 担当: ui-liveops。UI073 クレジット。

enum CreditsCatalog {
    struct Role: Identifiable, Equatable {
        let id: String
        let titleJa: String
        let titleEn: String
        var title: String { L(titleJa, titleEn) }
    }

    static let teamName = "VELSTRIA Team"

    static let roles: [Role] = [
        Role(id: "direction", titleJa: "ゲームディレクション", titleEn: "Game Direction"),
        Role(id: "design", titleJa: "ゲームデザイン・バランス", titleEn: "Game Design & Balance"),
        Role(id: "engineering", titleJa: "プログラム", titleEn: "Engineering"),
        Role(id: "ai", titleJa: "AI・シミュレーション", titleEn: "AI & Simulation"),
        Role(id: "art", titleJa: "アート・3D", titleEn: "Art & 3D"),
        Role(id: "ui", titleJa: "UI / UX デザイン", titleEn: "UI / UX Design"),
        Role(id: "audio", titleJa: "サウンド", titleEn: "Sound"),
        Role(id: "qa", titleJa: "品質保証", titleEn: "Quality Assurance"),
        Role(id: "loc", titleJa: "ローカライズ", titleEn: "Localization"),
    ]

    static let technologies = ["SwiftUI", "RealityKit", "StoreKit"]

    /// 技術タグの記号（Apple 製品を表す制限付き SF Symbols は使わず、汎用記号にする）。
    static func technologySymbol(_ tech: String) -> String {
        switch tech {
        case "SwiftUI": return "rectangle.3.group.fill"
        case "RealityKit": return "cube.transparent.fill"
        case "StoreKit": return "bag.fill"
        default: return "hammer.fill"
        }
    }
}

struct CreditsView: View {
    var body: some View {
        ScreenScaffold(title: L("クレジット", "Credits"), showsCurrencies: false) {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 18) {
                    VStack(spacing: 4) {
                        Text("VELSTRIA")
                            .font(.system(size: 34, weight: .black, design: .serif))
                            .tracking(6)
                            .foregroundStyle(LinearGradient(colors: [Theme.gold, .white, Theme.cyan], startPoint: .leading, endPoint: .trailing))
                        Text(L("ヴェルストリア - 星環の戦場", "Velstria - Battlefield of the Star Ring"))
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                    .padding(.top, 6)

                    creditsBlock(L("開発", "Development")) {
                        VStack(spacing: 6) {
                            ForEach(CreditsCatalog.roles) { role in
                                HStack(spacing: 14) {
                                    Text(role.title)
                                        .font(Theme.body(13))
                                        .foregroundStyle(Theme.textSecondary)
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                    Text(CreditsCatalog.teamName)
                                        .font(Theme.heading(14))
                                        .foregroundStyle(Theme.textPrimary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }

                    creditsBlock(L("使用技術", "Technology")) {
                        VStack(spacing: 8) {
                            Text("Built with \(CreditsCatalog.technologies.joined(separator: ", "))")
                                .font(Theme.heading(15))
                                .foregroundStyle(Theme.textPrimary)
                            HStack(spacing: 8) {
                                ForEach(CreditsCatalog.technologies, id: \.self) { tech in
                                    LiveOpsTag(text: tech, symbol: CreditsCatalog.technologySymbol(tech), color: Theme.cyan)
                                }
                            }
                            Text(L("SwiftUI、RealityKit、StoreKit は Apple Inc. の商標です。",
                                   "SwiftUI, RealityKit and StoreKit are trademarks of Apple Inc."))
                                .font(Theme.body(11))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }

                    creditsBlock(L("オリジナル作品について", "Original Work")) {
                        Text(L("本作に登場するヒーロー・スキル・世界観・名称・アートはすべて VELSTRIA Team によるオリジナルです。実在の人物・団体・他の作品とは関係ありません。",
                               "All heroes, skills, lore, names and art in this game are original creations of the VELSTRIA Team. Any resemblance to real people, organisations or other works is coincidental."))
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.textPrimary.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    creditsBlock(L("スペシャルサンクス", "Special Thanks")) {
                        VStack(spacing: 4) {
                            Text(L("テストプレイにご協力いただいた皆さま", "Everyone who helped playtest"))
                            Text(L("そして、星環の戦場に集うすべてのプレイヤーの皆さま", "And every player who joins the Star Ring battlefield"))
                        }
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textPrimary.opacity(0.9))
                        .multilineTextAlignment(.center)
                    }

                    Text("© 2026 VELSTRIA Team  ·  v\(AppVersionInfo.display)")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.bottom, 16)
                }
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
            }
        }
    }

    private func creditsBlock<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Rectangle().fill(Theme.gold.opacity(0.5)).frame(height: 1)
                Text(title)
                    .font(Theme.heading(14))
                    .foregroundStyle(Theme.gold)
                    .fixedSize()
                    .accessibilityAddTraits(.isHeader)
                Rectangle().fill(Theme.gold.opacity(0.5)).frame(height: 1)
            }
            content()
        }
    }
}
