import SwiftUI
import VelstriaCore

// 担当: ui-liveops。UI071 チュートリアル（章の案内 + MOBA 基礎のヒント集）。

struct TutorialChapter: Identifiable, Equatable {
    let id: Int
    let symbol: String
    let titleJa: String
    let titleEn: String
    let detailJa: String
    let detailEn: String
    let pointsJa: [String]
    let pointsEn: [String]

    var title: String { L(titleJa, titleEn) }
    var detail: String { L(detailJa, detailEn) }
    var points: [String] { Loc.isEnglish ? pointsEn : pointsJa }
}

struct TutorialTip: Identifiable, Equatable {
    enum Category: String, CaseIterable, Identifiable {
        case basics, laning, jungle, objectives, teamfight, items
        var id: String { rawValue }

        var title: String {
            switch self {
            case .basics: return L("基本", "Basics")
            case .laning: return L("レーン", "Laning")
            case .jungle: return L("ジャングル", "Jungle")
            case .objectives: return L("オブジェクト", "Objectives")
            case .teamfight: return L("集団戦", "Teamfights")
            case .items: return L("装備", "Items")
            }
        }

        var symbol: String {
            switch self {
            case .basics: return "book.fill"
            case .laning: return "road.lanes"
            case .jungle: return "tree.fill"
            case .objectives: return "flag.fill"
            case .teamfight: return "person.3.fill"
            case .items: return "bag.fill"
            }
        }
    }

    let id: String
    let category: Category
    let titleJa: String
    let titleEn: String
    let bodyJa: String
    let bodyEn: String

    var title: String { L(titleJa, titleEn) }
    var body: String { L(bodyJa, bodyEn) }
}

enum TutorialCatalog {
    /// チュートリアルで操作するヒーロー（扱いやすい近接デュエリスト）。
    static let heroID = "H002"
    /// チュートリアルは毎回同じ展開にする。
    static let seed: UInt64 = 20261001

    static func tutorialHeroID(master: MasterData = .shared) -> String {
        master.hero(heroID) != nil ? heroID : (master.heroes.first?.heroID ?? heroID)
    }

    static func config(playerName: String, master: MasterData = .shared) -> MatchConfig {
        MatchFactory.practiceMatch(humanHeroID: tutorialHeroID(master: master), humanName: playerName,
                                   options: PracticeOptions(), tutorial: true, seed: seed, master: master)
    }

    static let chapters: [TutorialChapter] = [
        TutorialChapter(id: 1, symbol: "figure.run",
                        titleJa: "移動と攻撃", titleEn: "Movement & Attacks",
                        detailJa: "左のスティックで移動し、攻撃ボタンで近くの敵を自動で狙います。",
                        detailEn: "Move with the left stick and tap Attack to auto-target nearby enemies.",
                        pointsJa: ["ミニオンにとどめを刺すとゴールドを獲得", "攻撃優先（ヒーロー / ミニオン）は設定で変更可能"],
                        pointsEn: ["Land the last hit on minions to earn gold", "Change attack priority in Settings"]),
        TutorialChapter(id: 2, symbol: "sparkles",
                        titleJa: "スキルとレベル", titleEn: "Skills & Levels",
                        detailJa: "経験値でレベルが上がるとスキルポイントを獲得し、スキルを強化できます。",
                        detailEn: "Level up with XP to earn skill points and rank up your skills.",
                        pointsJa: ["アルティメットは Lv 4 / 8 / 12 で強化", "タップで自動照準、ドラッグで手動照準"],
                        pointsEn: ["Ultimate ranks unlock at Lv 4 / 8 / 12", "Tap to auto-aim, drag to aim manually"]),
        TutorialChapter(id: 3, symbol: "bag.fill",
                        titleJa: "装備購入", titleEn: "Buying Items",
                        detailJa: "ゴールドでショップから装備を購入し、ヒーローを強化します。",
                        detailEn: "Spend gold in the shop on items to power up your hero.",
                        pointsJa: ["迷ったらおすすめ装備を購入", "装備枠は 6 つ。素材は上位装備に合成"],
                        pointsEn: ["Follow the recommended build when unsure", "6 item slots; components combine into upgrades"]),
        TutorialChapter(id: 4, symbol: "building.columns.fill",
                        titleJa: "タワーとオブジェクト", titleEn: "Towers & Objectives",
                        detailJa: "外塔 → 内塔 → 基部塔の順に攻略し、敵の Star Core を破壊すれば勝利です。",
                        detailEn: "Take outer, inner, then base towers, and destroy the enemy Star Core to win.",
                        pointsJa: ["ミニオンと一緒にタワーを攻撃", "星喰竜・古環の巨像はチームを強化"],
                        pointsEn: ["Push towers together with your minions", "Astral Wyrm and Ancient Colossus empower your team"]),
        TutorialChapter(id: 5, symbol: "arrow.uturn.backward.circle.fill",
                        titleJa: "帰還とスペル", titleEn: "Recall & Spells",
                        detailJa: "体力が減ったら帰還で泉に戻って回復。バトルスペルで危機を切り抜けます。",
                        detailEn: "Recall to your fountain to heal, and use battle spells to escape danger.",
                        pointsJa: ["帰還は 6 秒の詠唱。移動・攻撃・被ダメージで中断", "瞬歩で距離を取り、治癒波で味方ごと回復"],
                        pointsEn: ["Recall channels for 6s; moving, attacking or taking damage cancels it", "Blink to escape; the healing spell heals an ally too"]),
    ]

    static let tips: [TutorialTip] = [
        TutorialTip(id: "basics_lasthit", category: .basics,
                    titleJa: "ラストヒットを狙う", titleEn: "Go for last hits",
                    bodyJa: "ミニオンやモンスターのゴールドは、とどめを刺したヒーローだけが獲得します。HP が減ったミニオンに攻撃を合わせましょう。",
                    bodyEn: "Minion and monster gold only goes to the hero who lands the killing blow. Time your attacks on low-health minions."),
        TutorialTip(id: "basics_brush", category: .basics,
                    titleJa: "草むらと視界", titleEn: "Brush and vision",
                    bodyJa: "草むらの中のユニットは、近くに敵がいない限り見えません。見えない草むらには敵が潜んでいるかもしれません。",
                    bodyEn: "Units in brush are hidden unless an enemy is close. Unseen brush may hide an ambush."),
        TutorialTip(id: "basics_minimap", category: .basics,
                    titleJa: "ミニマップを見る習慣", titleEn: "Watch the minimap",
                    bodyJa: "敵の姿が消えたら奇襲の合図かもしれません。数秒ごとにミニマップを確認しましょう。",
                    bodyEn: "When enemies vanish from sight, they may be coming for you. Glance at the minimap every few seconds."),
        TutorialTip(id: "laning_tower", category: .laning,
                    titleJa: "敵タワーの下で戦わない", titleEn: "Avoid fighting under enemy towers",
                    bodyJa: "タワーの攻撃は連続で当たるほど強くなります。また、味方ミニオンがタワーの射程内にいないと、ヒーローからタワーへのダメージは半減します。",
                    bodyEn: "Tower shots ramp up with each consecutive hit, and heroes deal half damage to towers unless allied minions are within tower range."),
        TutorialTip(id: "laning_retreat", category: .laning,
                    titleJa: "引き際を見極める", titleEn: "Know when to back off",
                    bodyJa: "HP が 3 割を切ったら無理をせず帰還しましょう。デスは相手チームにゴールドと経験値を与えます。",
                    bodyEn: "Below 30% HP, recall instead of pushing your luck. Every death feeds gold and XP to the enemy."),
        TutorialTip(id: "laning_wave", category: .laning,
                    titleJa: "ミニオンと一緒に押す", titleEn: "Push with your wave",
                    bodyJa: "タワーは近くのミニオンを優先して狙います。ただし射程内で敵ヒーローを攻撃すると、すぐに標的にされます。味方ウェーブと一緒に攻めましょう。",
                    bodyEn: "Towers target nearby minions first, but switch to you if you attack an enemy hero in their range. Siege alongside your wave."),
        TutorialTip(id: "jungle_smite", category: .jungle,
                    titleJa: "狩猟印でジャングル", titleEn: "Jungle with the hunting spell",
                    bodyJa: "ジャングル担当はバトルスペル「狩猟印」でモンスターを素早く倒せます。キャンプは撃破後に再出現します。",
                    bodyEn: "Junglers take the hunting battle spell to clear monsters fast. Camps respawn after being cleared."),
        TutorialTip(id: "jungle_buffs", category: .jungle,
                    titleJa: "2 つのバフ", titleEn: "The two buffs",
                    bodyJa: "蒼晶の番人はスキル CD −10%・消費 Mana −60%（Energy −25%）と、敵を倒した時の回復。紅焔の番人は敵ヒーローへの攻撃に 3 秒ごとの追撃（確定ダメージとスロー）と貫通を付与します。トカゲ・甲虫・岩人を倒すと HP も回復します。",
                    bodyEn: "Azure Sentinel: −10% cooldowns, −60% mana cost (−25% energy) and healing on kills. Crimson Sentinel: hitting enemy heroes triggers a true-damage, slowing strike every 3s, plus penetration. Lizards, beetles and golems heal you when slain."),
        TutorialTip(id: "objectives_wyrm", category: .objectives,
                    titleJa: "星喰竜", titleEn: "Astral Wyrm",
                    bodyJa: "2:00 に河川へ出現。倒すとチーム全員にゴールドと経験値。とどめを刺した人には張り直すシールドと攻撃力、味方にはシールドが付きます。",
                    bodyEn: "Spawns in the river at 2:00. Slaying it grants the whole team gold and XP; the slayer gets a regenerating shield and bonus attack, allies get a shield."),
        TutorialTip(id: "objectives_colossus", category: .objectives,
                    titleJa: "古環の巨像", titleEn: "Ancient Colossus",
                    bodyJa: "8:00 に出現する最強の中立ボス。与ダメージ +15%、帰還短縮、周囲のミニオン強化で一気に押し込めます。",
                    bodyEn: "The strongest neutral boss, spawning at 8:00. +15% damage, faster recall and empowered minions help you siege."),
        TutorialTip(id: "objectives_core", category: .objectives,
                    titleJa: "Star Core の守り", titleEn: "Star Core protection",
                    bodyJa: "Star Core は基部塔が 1 本以上破壊されるまで無敵です。タワーは同じレーンの外側から順に攻略します。",
                    bodyEn: "The Star Core is invulnerable until at least one base tower falls. Towers in a lane must be taken outside-in."),
        TutorialTip(id: "teamfight_focus", category: .teamfight,
                    titleJa: "狙いを合わせる", titleEn: "Focus fire",
                    bodyJa: "集団戦では倒しやすい敵（HP の低いレンジャーやアルカニスト）から集中攻撃しましょう。",
                    bodyEn: "In teamfights, focus the easiest targets first, such as low-health Rangers and Arcanists."),
        TutorialTip(id: "teamfight_ult", category: .teamfight,
                    titleJa: "アルティメットは同時に", titleEn: "Combine ultimates",
                    bodyJa: "ヴァンガードの突撃に合わせて範囲アルティメットを重ねると、一気に形勢を逆転できます。",
                    bodyEn: "Layer area ultimates right after your Vanguard engages to swing the fight."),
        TutorialTip(id: "teamfight_surrender", category: .teamfight,
                    titleJa: "降参について", titleEn: "About surrendering",
                    bodyJa: "8:00 以降に降参を提案できます。AI 味方は大きく不利なときだけ賛成し、5 人中 3 人の賛成で成立します。",
                    bodyEn: "You can propose a surrender after 8:00. AI allies agree only when far behind; 3 of 5 votes are needed."),
        TutorialTip(id: "items_recommended", category: .items,
                    titleJa: "おすすめ装備", titleEn: "Recommended items",
                    bodyJa: "ショップのおすすめはヒーローのロールに合わせたビルドです。慣れたらビルド編集で自分好みに調整しましょう。",
                    bodyEn: "The shop recommends a build for your hero's role. Once comfortable, customise it in the Build Editor."),
        TutorialTip(id: "items_defense", category: .items,
                    titleJa: "防御と魔防", titleEn: "Armor vs. magic resist",
                    bodyJa: "物理ダメージの多い相手には防御、魔法ダメージの多い相手には魔防を積むと効率よく耐えられます。",
                    bodyEn: "Build armor against physical damage dealers and magic resist against magic damage dealers."),
    ]
}

struct TutorialMenuView: View {
    @Environment(AppModel.self) private var app
    @State private var category: TutorialTip.Category = .basics

    var body: some View {
        ScreenScaffold(title: L("チュートリアル", "Tutorial")) {
            HStack(alignment: .top, spacing: 14) {
                chapterPanel
                    .frame(maxWidth: .infinity)
                tipsPanel
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
    }

    // MARK: 章

    private var chapterPanel: some View {
        Panel(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    LiveOpsSectionHeader(title: L("チュートリアルの内容", "What You'll Learn"), symbol: "graduationcap.fill")
                    Spacer(minLength: 0)
                    if app.profile.tutorialCompleted {
                        LiveOpsTag(text: L("クリア済み", "Completed"), symbol: "checkmark", color: Theme.success)
                    }
                }
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 8) {
                        ForEach(TutorialCatalog.chapters) { chapter in
                            chapterRow(chapter)
                        }
                    }
                }
                startButton
            }
        }
    }

    private func chapterRow(_ chapter: TutorialChapter) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(Theme.gold.opacity(0.18))
                Image(systemName: chapter.symbol)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.gold)
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(L("第\(chapter.id)章  \(chapter.title)", "Chapter \(chapter.id)  \(chapter.title)"))
                    .font(Theme.heading(14))
                    .foregroundStyle(Theme.textPrimary)
                Text(chapter.detail)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(chapter.points, id: \.self) { point in
                    Label(point, systemImage: "checkmark.circle")
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.cyan.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tutorial_chapter_\(chapter.id)")
    }

    private var startButton: some View {
        let heroID = TutorialCatalog.tutorialHeroID(master: app.master)
        return HStack(spacing: 10) {
            HeroPortraitView(heroID: heroID, size: 44)
            VStack(alignment: .leading, spacing: 1) {
                Text(L("使用ヒーロー", "Your hero"))
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textSecondary)
                Text(app.master.hero(heroID).map { MasterText.hero($0) } ?? heroID)
                    .font(Theme.heading(13))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 4)
            Button {
                start()
            } label: {
                Label(app.profile.tutorialCompleted ? L("もう一度プレイ", "Play Again") : L("チュートリアルを始める", "Start Tutorial"),
                      systemImage: "play.fill")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .buttonStyle(LiveOpsTallButtonStyle(base: PrimaryButtonStyle()))
            .accessibilityIdentifier("tutorial_start")
        }
    }

    private func start() {
        app.audio.play(.uiConfirm)
        let name = app.profile.displayName.isEmpty ? L("プレイヤー", "Player") : app.profile.displayName
        app.startBattle(BattleLaunch(config: TutorialCatalog.config(playerName: name, master: app.master)))
    }

    // MARK: ヒント集

    private var tipsPanel: some View {
        Panel(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                LiveOpsSectionHeader(title: L("ヒント集", "Tips Library"), symbol: "lightbulb.fill")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(TutorialTip.Category.allCases) { c in
                            categoryChip(c)
                        }
                    }
                }
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 8) {
                        ForEach(TutorialCatalog.tips.filter { $0.category == category }) { tip in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tip.title)
                                    .font(Theme.heading(14))
                                    .foregroundStyle(Theme.gold)
                                Text(tip.body)
                                    .font(Theme.body(12))
                                    .foregroundStyle(Theme.textPrimary.opacity(0.9))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .id(category)
                }
            }
        }
    }

    private func categoryChip(_ c: TutorialTip.Category) -> some View {
        let selected = c == category
        return Button {
            app.audio.play(.uiTap)
            withAnimation(.easeInOut(duration: 0.2)) { category = c }
        } label: {
            Label(c.title, systemImage: c.symbol)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(selected ? Color.black.opacity(0.85) : Theme.textPrimary)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Capsule().fill(selected ? AnyShapeStyle(Theme.cyan) : AnyShapeStyle(Color.white.opacity(0.08))))
                .overlay(Capsule().stroke(selected ? Color.white.opacity(0.5) : Theme.panelStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("tutorial_tips_\(c.rawValue)")
    }
}
