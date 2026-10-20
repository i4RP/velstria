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

    static let teamName = "VELSIA Team"

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

    /// 同梱フォント（App/Resources/Fonts。ライセンス本文 OFL-*.txt も同梱）。
    static let fonts: [(name: String, copyright: String)] = [
        ("Chakra Petch", "Copyright 2018 The Chakra Petch Project Authors (https://github.com/m4rc1e/Chakra-Petch)"),
        ("Cinzel", "Copyright 2020 The Cinzel Project Authors (https://github.com/NDISCOVER/Cinzel)"),
    ]

    /// 音楽・効果音の素材（すべて CC0 1.0。tools/audio/build_audio.py で加工。出典の表は docs/audio/SOURCES.md）。
    /// CC0 は帰属表示が要らないが、作者と URL を載せる。素材を足したら build_audio.py の SOURCES と一緒に足す（AppTests の AudioFilesTests）。
    static let audio: [(title: String, author: String, url: String)] = [
        ("Interface Sounds", "Kenney", "https://kenney.nl/assets/interface-sounds"),
        ("Impact Sounds", "Kenney", "https://kenney.nl/assets/impact-sounds"),
        ("RPG Audio", "Kenney", "https://kenney.nl/assets/rpg-audio"),
        ("Sci-Fi Sounds", "Kenney", "https://kenney.nl/assets/sci-fi-sounds"),
        ("Digital Audio", "Kenney", "https://kenney.nl/assets/digital-audio"),
        ("Music Jingles", "Kenney", "https://kenney.nl/assets/music-jingles"),
        ("Casino Audio", "Kenney", "https://kenney.nl/assets/casino-audio"),
        ("A Legend Will Rise", "CodeManu", "https://opengameart.org/content/a-legend-will-rise-orchestral"),
        ("Fantasy Orchestral Theme", "Joth", "https://opengameart.org/content/fantasy-orchestral-theme"),
        ("Treasure Hunter", "TAD", "https://opengameart.org/content/treasure-hunter"),
        ("Once Upon a Time (loop)", "TAD", "https://opengameart.org/content/once-upon-a-time-loop"),
        ("Battle Theme", "Wolfgang_", "https://opengameart.org/content/battle-theme-0"),
        ("Final Stand", "iamoneabe", "https://opengameart.org/content/final-stand"),
        ("Intro Cue", "Vehicle", "https://opengameart.org/content/intro-cue"),
        ("At Home (orchestral)", "Wolfgang_", "https://opengameart.org/content/at-home-orchestral"),
    ]

    /// ヒーロー固有の音（tools/audio/skill_sounds_v2.py）に使った Sonniss GDC Game Audio Bundle の素材集（題名（年）・作者）。
    /// ロイヤリティフリー・商用可・帰属表示は不要（https://sonniss.com/gdc-bundle-license/）。加工した完成品だけを入れる。
    /// 素材集の一覧 `sonniss` は AudioCredits.swift（tools/audio/build_audio.py が SOURCES.md と一緒に書く）。
    static let sonnissPage = "https://gdc.sonniss.com/"

    /// 静的にリンクしているオープンソース（ThirdParty/。MIT License は著作権表示と許諾表示の掲載が条件）。
    /// Effekseer の静的ライブラリ（libEffekseerAll.a）には LLGI（zlib）と stb_image（MIT / パブリックドメインの選択制。MIT を選ぶ）が入っている。
    /// 本文は ThirdParty/Effekseer/LICENSE.txt・docs/legal/licenses/llgi.txt・stb-image.txt と一致させる（AppTests の OnlineSafetyTests で確認）。
    static let openSource: [(name: String, license: String, text: String)] = [
        ("Effekseer", "MIT License", effekseerLicense),
        ("stb_image", "MIT License", stbImageLicense),
        ("LLGI", "zlib License", llgiLicense),
    ]

    static let stbImageLicense = """
    ------------------------------------------------------------------------------
    This software is available under 2 licenses -- choose whichever you prefer.
    ------------------------------------------------------------------------------
    ALTERNATIVE A - MIT License
    Copyright (c) 2017 Sean Barrett
    Permission is hereby granted, free of charge, to any person obtaining a copy of
    this software and associated documentation files (the "Software"), to deal in
    the Software without restriction, including without limitation the rights to
    use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
    of the Software, and to permit persons to whom the Software is furnished to do
    so, subject to the following conditions:
    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.
    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
    ------------------------------------------------------------------------------
    ALTERNATIVE B - Public Domain (www.unlicense.org)
    This is free and unencumbered software released into the public domain.
    Anyone is free to copy, modify, publish, use, compile, sell, or distribute this
    software, either in source code form or as a compiled binary, for any purpose,
    commercial or non-commercial, and by any means.
    In jurisdictions that recognize copyright laws, the author or authors of this
    software dedicate any and all copyright interest in the software to the public
    domain. We make this dedication for the benefit of the public at large and to
    the detriment of our heirs and successors. We intend this dedication to be an
    overt act of relinquishment in perpetuity of all present and future rights to
    this software under copyright law.
    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
    ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
    WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
    ------------------------------------------------------------------------------
    """

    static let llgiLicense = """
    Copyright (c) 2019 Altseed

    This software is provided 'as-is', without any express or implied
    warranty. In no event will the authors be held liable for any damages
    arising from the use of this software.

    Permission is granted to anyone to use this software for any purpose,
    including commercial applications, and to alter it and redistribute it
    freely, subject to the following restrictions:

       1. The origin of this software must not be misrepresented; you must not
       claim that you wrote the original software. If you use this software
       in a product, an acknowledgment in the product documentation would be
       appreciated but is not required.

       2. Altered source versions must be plainly marked as such, and must not be
       misrepresented as being the original software.

       3. This notice may not be removed or altered from any source
       distribution.
    """

    static let effekseerLicense = """
    The MIT License (MIT)

    Copyright (c) 2011 Effekseer Project

    Permission is hereby granted, free of charge, to any person obtaining a copy of
    this software and associated documentation files (the "Software"), to deal in
    the Software without restriction, including without limitation the rights to
    use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
    the Software, and to permit persons to whom the Software is furnished to do so,
    subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
    FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
    COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
    IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
    CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
    """

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
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScreenScaffold(title: L("クレジット", "Credits"), showsCurrencies: false) {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 18) {
                    VStack(spacing: 4) {
                        Text("VELSIA")
                            .font(.system(size: 34, weight: .black, design: .serif))
                            .tracking(6)
                            .foregroundStyle(LinearGradient(colors: [Theme.gold, .white, Theme.cyan], startPoint: .leading, endPoint: .trailing))
                        Text(L("ベルシア - 星環の戦場", "VELSIA: Star Ring Arena"))
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

                    creditsBlock(L("フォント", "Fonts")) {
                        VStack(spacing: 6) {
                            ForEach(CreditsCatalog.fonts, id: \.name) { font in
                                VStack(spacing: 1) {
                                    Text(font.name)
                                        .font(Theme.heading(14))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(font.copyright)
                                        .font(Theme.body(11))
                                        .foregroundStyle(Theme.textSecondary)
                                        .multilineTextAlignment(.center)
                                }
                                .accessibilityElement(children: .combine)
                            }
                            Text(L("SIL Open Font License, Version 1.1 のもとで使用しています。",
                                   "Licensed under the SIL Open Font License, Version 1.1."))
                                .font(Theme.body(11))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }

                    creditsBlock(L("音楽・効果音", "Music & Sound Effects")) {
                        VStack(spacing: 6) {
                            ForEach(CreditsCatalog.audio, id: \.title) { a in
                                VStack(spacing: 1) {
                                    Text("\(a.title) — \(a.author)")
                                        .font(Theme.heading(13))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(a.url)
                                        .font(Theme.body(10))
                                        .foregroundStyle(Theme.textSecondary)
                                        .multilineTextAlignment(.center)
                                }
                                .accessibilityElement(children: .combine)
                            }
                            Text(L("上の素材は CC0 1.0（パブリックドメイン）のものを加工して使っています。",
                                   "The assets above are CC0 1.0 (public domain), edited for this app."))
                                .font(Theme.body(11))
                                .foregroundStyle(Theme.textSecondary)
                            Text("Sonniss GDC Game Audio Bundle")
                                .font(Theme.heading(13))
                                .foregroundStyle(Theme.textPrimary)
                                .padding(.top, 6)
                            ForEach(CreditsCatalog.sonniss, id: \.title) { a in
                                Text("\(a.title) — \(a.author)")
                                    .font(Theme.body(11))
                                    .foregroundStyle(Theme.textPrimary)
                                    .multilineTextAlignment(.center)
                            }
                            Text(CreditsCatalog.sonnissPage)
                                .font(Theme.body(10))
                                .foregroundStyle(Theme.textSecondary)
                            Text(L("ヒーローのスキルの音は、Sonniss GDC Game Audio Bundle（ロイヤリティフリー・商用可）の録音を重ね・加工して作っています。",
                                   "Hero skill sounds are layered and edited from recordings in the Sonniss GDC Game Audio Bundle (royalty-free)."))
                                .font(Theme.body(11))
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                    }

                    creditsBlock(L("オープンソースライセンス", "Open Source Licenses")) {
                        VStack(spacing: 8) {
                            ForEach(CreditsCatalog.openSource, id: \.name) { lib in
                                VStack(spacing: 4) {
                                    Text("\(lib.name) — \(lib.license)")
                                        .font(Theme.heading(14))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(lib.text)
                                        .font(Theme.mono(9))
                                        .foregroundStyle(Theme.textSecondary)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(10)
                                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.05)))
                                        .textSelection(.enabled)
                                }
                                .accessibilityElement(children: .combine)
                            }
                            Button {
                                openURL(FeatureFlags.licensesURL)
                            } label: {
                                Label(L("ライセンスの一覧（Web）", "All licenses (web)"), systemImage: "arrow.up.right.square")
                                    .font(Theme.body(13))
                                    .foregroundStyle(Theme.cyan)
                                    .frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("credits_licenses")
                        }
                    }

                    creditsBlock(L("オリジナル作品について", "Original Work")) {
                        Text(L("本作に登場するヒーロー・スキル・世界観・名称・アートはすべて VELSIA Team によるオリジナルです。実在の人物・団体・他の作品とは関係ありません。",
                               "All heroes, skills, lore, names and art in this game are original creations of the VELSIA Team. Any resemblance to real people, organisations or other works is coincidental."))
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

                    Text("© 2026 VELSIA Team  ·  v\(AppVersionInfo.display)")
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
