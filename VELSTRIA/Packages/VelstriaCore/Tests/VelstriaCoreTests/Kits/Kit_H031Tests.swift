import XCTest
@testable import VelstriaCore

/// H031 氷嵐のオーリア（MLBB オーロラの Velstria 版）のキット。docs/kits/Aurora.md の対応表と同じ並びで検査する。
/// 数値の出典: MLBB 日本語クライアントのスキル詳細の画面（REAL_DATA.md「H031 オーリア = オーロラ(Aurora)」の書き起こし、
/// docs/kits/Aurora.md の「日本語クライアントの画面」）。段は公式の Lv（スキル1・2 = Lv1〜6、アルティメット = Lv1〜3）。
/// キットは HeroKits.testOverride に有効な Kit_H031 を差して試す（本番の有効化とは独立。有効化後も同じ結果）。
final class Kit_H031Tests: XCTestCase {
    typealias T = OriaTuning
    static let east = Vec2(1, 0)

    // MARK: - 公式の表（REAL_DATA.md の日本語クライアントの値の写し。実装の定数ではなくこれと比べる）

    static let meteorTable: [Double] = [400, 460, 520, 580, 640, 700]   // +90% 魔法攻撃
    static let breezeTable: [Double] = [225, 255, 285, 315, 345, 375]   // +75% 魔法攻撃（凍結エリアの合計も同じ）
    static let s1CooldownTable: [Double] = [5.0, 4.8, 4.6, 4.4, 4.2, 4.0]
    static let s2CooldownTable: [Double] = [10.0, 9.6, 9.2, 8.8, 8.4, 8.0]
    static let s1ManaTable: [Double] = [60, 65, 70, 75, 80, 85]
    static let s2ManaTable: [Double] = [75, 80, 85, 90, 95, 100]
    static let pathTable: [Double] = [100, 150, 200]                    // +40% 魔法攻撃
    static let shatterTable: [Double] = [600, 900, 1200]                // +150% 魔法攻撃
    static let ultCooldownTable: [Double] = [50, 45, 40]
    static let ultManaTable: [Double] = [140, 160, 180]

    /// 凍結エリアの中心（術者から。推測の幾何、Kit_H031.castBreeze と同じ）。半径はスキル定義の radius（190）。
    static let areaCenter = T.s2Range - T.s2PatchBack

    override func setUp() {
        super.setUp()
        HeroKits.testOverride = [Kit_H031(isReady: true)]
    }

    override func tearDown() {
        HeroKits.testOverride = []
        super.tearDown()
    }

    // MARK: - 土台

    @discardableResult
    private func addOria(_ w: inout SkillWorld, ranks: [Int]? = [1, 1, 1], at pos: Vec2 = skillArena, level: Int = 1) -> Int {
        w.addHero("H031", team: .blue, at: pos, level: level, ranks: ranks, facing: 0)
    }

    private var def: HeroDef { MasterData.shared.hero("H031")! }

    private func skill(_ slot: SkillSlot) -> SkillDef { MasterData.shared.skill(hero: "H031", slot: slot)! }

    private func numbers(_ slot: SkillSlot, _ rank: Int, _ stats: Stats) -> SkillNumbers {
        SkillCatalog.numbers(for: skill(slot), hero: def, rank: rank, stats: stats)
    }

    /// 凍結エリアの半径（スキル定義の radius）。
    private var areaRadius: Double { skill(.skill2).radius }

    private func damageEvents(_ w: SkillWorld, to e: Int, _ source: DamageSource) -> [DamageEvent] {
        w.damageEvents.filter { $0.targetID == w.id(e) && $0.source == source }
    }

    private func status(_ w: SkillWorld, _ i: Int, _ kind: StatusKind, tag: String? = nil) -> StatusEffect? {
        w.s.units[i].statuses.first { $0.kind == kind && (tag == nil || $0.tag == tag) }
    }

    private func extra(_ n: SkillNumbers, _ key: String) -> Double {
        n.extras.first { $0.key == key }?.value ?? .nan
    }

    /// 対象 e に出た凍結（ccApplied）の回数。
    private func freezeNotices(_ w: SkillWorld, _ e: Int) -> Int {
        w.log.filter { if case .ccApplied(let id, .stun, _) = $0 { return id == w.id(e) } else { return false } }.count
    }

    /// 致命傷（HP・シールドを超える確定ダメージ）。
    private func fatal(_ w: inout SkillWorld, _ k: Int, from e: Int, source: DamageSource = .spell) {
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(e), targetIndex: k, amount: 1e9, type: .trueDamage,
                                 source: source)
        w.flushEvents()
    }

    // MARK: - レジストリ・照準・説明文

    func testRegistryTargetingAndTextPerSlot() throws {
        XCTAssertTrue(HeroKits.hasKit("H031"))
        XCTAssertNotNil(HeroKits.kit(for: "H031"))
        // 本番のレジストリでも有効（テストの差し込み無しで引ける）
        XCTAssertTrue(Kit_H031().isReady)
        HeroKits.testOverride = []
        XCTAssertTrue(HeroKits.hasKit("H031"))
        HeroKits.testOverride = [Kit_H031(isReady: true)]

        let t1 = SkillCatalog.targeting(for: skill(.skill1), hero: def)
        XCTAssertEqual(t1.archetype, .groundAoE)
        XCTAssertEqual(t1.aim, .point)
        XCTAssertEqual(t1.range, 650)
        XCTAssertEqual(t1.radius, T.s1Radius)
        XCTAssertEqual(t1.shape, .circleAtPoint)
        XCTAssertEqual(t1.reach, 650 + T.s1Radius)

        let t2 = SkillCatalog.targeting(for: skill(.skill2), hero: def)
        XCTAssertEqual(t2.archetype, .cone)
        XCTAssertEqual(t2.aim, .direction)
        XCTAssertEqual(t2.range, 650)
        XCTAssertEqual(t2.radius, 650)
        XCTAssertEqual(t2.shape, .fan)
        XCTAssertEqual(t2.halfAngle, T.s2HalfAngle, accuracy: 1e-12)
        XCTAssertEqual(t2.reach, 650)

        let t3 = SkillCatalog.targeting(for: skill(.ultimate), hero: def)
        XCTAssertEqual(t3.archetype, .piercingLine)
        XCTAssertEqual(t3.aim, .direction)
        XCTAssertEqual(t3.range, 770, "遠隔の奥義の射程の目安（≈ 100 × MLBB の 7.7 マス）")
        XCTAssertEqual(t3.radius, T.ultGlacierRadius, "照準の帯の半幅 = 氷河の半径（砕けて凍らせる範囲）")
        XCTAssertEqual(t3.shape, .wideLine)
        XCTAssertNotEqual(T.ultPathWidth, T.ultGlacierRadius, "霜の道の当たり幅は照準の帯とは別")

        XCTAssertEqual(SkillCatalog.targeting(for: skill(.passive), hero: def).archetype, .passive)

        // 説明文: 4 スロットとも ja/en があり、テンプレートの語が全部埋まる
        let stats = HeroGrowth.baseStats(def: def, level: 6)
        XCTAssertEqual(stats.abilityPower, 0, "装備なしの魔法攻撃は 0（説明文の数値 = 公式の基礎）")
        for slot in SkillSlot.allCases {
            let text = try XCTUnwrap(HeroKits.text(heroID: "H031", slot: slot), "\(slot)")
            for rank in [1, slot.maxRank] {
                let n = numbers(slot, rank, stats)
                let t = SkillCatalog.targeting(for: skill(slot), hero: def)
                for english in [false, true] {
                    let filled = text.filled(english: english, numbers: n, targeting: t)
                    XCTAssertFalse(filled.contains("{"), "\(slot) \(english): \(filled)")
                    XCTAssertFalse(filled.isEmpty)
                }
            }
        }
        // 数値は公式の値そのもの（{基礎}(+{係数}%魔法攻撃)。スロット倍率・換算は掛からない）
        let n1 = numbers(.skill1, 1, stats)
        let ja1 = HeroKits.text(heroID: "H031", slot: .skill1)!.filled(english: false, numbers: n1, targeting: t1)
        XCTAssertEqual(n1.damage, 400, accuracy: 1e-9)
        XCTAssertTrue(ja1.contains("400(+90%魔法攻撃)の魔法ダメージ"), ja1)
        XCTAssertTrue(ja1.contains("移動速度を1秒間40%低下させる"), ja1)
        XCTAssertTrue(ja1.contains("5個の雹が降り注ぎ、それぞれ40(+10%魔法攻撃)"), ja1)
        let n16 = numbers(.skill1, 6, stats)
        let en16 = HeroKits.text(heroID: "H031", slot: .skill1)!.filled(english: true, numbers: n16, targeting: t1)
        XCTAssertTrue(en16.contains("dealing 700 (+90% Magic Power)") && en16.contains("each dealing 40 (+10% Magic Power)"), en16)

        let n2 = numbers(.skill2, 6, stats)
        let ja2 = HeroKits.text(heroID: "H031", slot: .skill2)!.filled(english: false, numbers: n2, targeting: t2)
        XCTAssertTrue(ja2.contains("命中した敵に375(+75%魔法攻撃)の魔法ダメージを与える"), ja2)
        XCTAssertTrue(ja2.contains("攻撃の末端に凍結エリアを作り、エリア内の敵を1秒間凍結させて"), ja2)
        XCTAssertTrue(ja2.contains("合計375(+75%魔法攻撃)") && ja2.contains("魔法攻撃100ごとに凍結時間が0.06秒延びる"), ja2)
        XCTAssertFalse(ja2.contains("すぐ近く"), "外したルール（近くの敵は凍らない）の但し書きは無い: \(ja2)")
        let en2 = HeroKits.text(heroID: "H031", slot: .skill2)!.filled(english: true, numbers: n2, targeting: t2)
        XCTAssertTrue(en2.contains("enemies in it are frozen for 1s"), en2)
        XCTAssertFalse(en2.contains("right next to you"), en2)

        let n3 = numbers(.ultimate, 3, stats)
        let en3 = HeroKits.text(heroID: "H031", slot: .ultimate)!.filled(english: true, numbers: n3, targeting: t3)
        XCTAssertTrue(en3.contains("dealing 200 (+40% Magic Power)") && en3.contains("dealing 1200 (+150% Magic Power)"), en3)
        XCTAssertTrue(en3.contains("by 80% for 1.2s") && en3.contains("adds 0.2s to the freeze"), en3)

        let np = numbers(.passive, 1, stats)
        let jap = HeroKits.text(heroID: "H031", slot: .passive)!.filled(english: false, numbers: np, targeting: t1)
        XCTAssertTrue(jap.contains("1.5秒") && jap.contains("最大HPの30%を徐々に回復") && jap.contains("150秒"), jap)
        XCTAssertTrue(jap.contains("致命的なダメージを受けると"), jap)
        XCTAssertFalse(jap.contains("レベル"), "外したルール（回復がレベルで伸びる）の但し書きは無い: \(jap)")
        let enp = HeroKits.text(heroID: "H031", slot: .passive)!.filled(english: true, numbers: np, targeting: t1)
        XCTAssertTrue(enp.contains("Upon taking fatal damage") && enp.contains("recovering 30% Max HP"), enp)
        XCTAssertFalse(enp.contains("level"), enp)
        // 用語: スキル1 / スキル2 / アルティメットの略称は使わない
        for slot in SkillSlot.allCases {
            let n = numbers(slot, 1, stats)
            let ja = HeroKits.text(heroID: "H031", slot: slot)!.filled(english: false, numbers: n, targeting: t1)
            XCTAssertFalse(ja.contains("S1") || ja.contains("S2") || ja.contains("奥義"), "\(slot): \(ja)")
        }
    }

    // MARK: - 公式の表（6 / 6 / 3 段）

    /// ダメージ = 公式の基礎[段] + 公式の係数 × 魔法攻撃（REAL_DATA.md。換算・補間・スロット倍率なし）。
    func testDamageEqualsTheOfficialTableAtEveryRank() {
        XCTAssertEqual(SkillSlot.skill1.maxRank, 6)
        XCTAssertEqual(SkillSlot.ultimate.maxRank, 3)
        var st = HeroGrowth.baseStats(def: def, level: 12)
        st.abilityPower = 100
        for rank in 1...6 {
            let r = rank - 1
            let n1 = numbers(.skill1, rank, st)
            XCTAssertEqual(n1.damage, Self.meteorTable[r] + 0.90 * 100, accuracy: 1e-9, "隕石 Lv\(rank)")
            XCTAssertEqual(Kit_H031.hailDamage(rank: rank, stats: st), 40 + 0.10 * 100, accuracy: 1e-9, "雹は全 Lv 40")
            XCTAssertEqual(extra(n1, "hailDamage"), 50)
            XCTAssertEqual(extra(n1, "meteorBase"), Self.meteorTable[r])
            XCTAssertEqual(extra(n1, "meteorPct"), 90)
            XCTAssertEqual(extra(n1, "hailBase"), 40)
            XCTAssertEqual(extra(n1, "hailPct"), 10)
            let n2 = numbers(.skill2, rank, st)
            XCTAssertEqual(n2.damage, Self.breezeTable[r] + 0.75 * 100, accuracy: 1e-9, "霜風 Lv\(rank)")
            XCTAssertEqual(Kit_H031.patchTotal(rank: rank, stats: st), Self.breezeTable[r] + 0.75 * 100, accuracy: 1e-9,
                           "凍結エリアの合計 Lv\(rank)（霜風と同じ表）")
            XCTAssertEqual(extra(n2, "patchTotal"), Self.breezeTable[r] + 75)
            XCTAssertEqual(extra(n2, "hitBase"), Self.breezeTable[r])
            XCTAssertEqual(extra(n2, "patchBase"), Self.breezeTable[r])
            XCTAssertEqual(extra(n2, "hitPct"), 75)
            XCTAssertEqual(extra(n2, "patchPct"), 75)
        }
        for rank in 1...3 {
            let r = rank - 1
            let n = numbers(.ultimate, rank, st)
            XCTAssertEqual(n.damage, Self.pathTable[r] + 0.40 * 100, accuracy: 1e-9, "霜の道 Lv\(rank)")
            XCTAssertEqual(Kit_H031.shatterDamage(rank: rank, stats: st), Self.shatterTable[r] + 1.5 * 100, accuracy: 1e-9,
                           "砕け Lv\(rank)")
            XCTAssertEqual(extra(n, "shatterDamage"), Self.shatterTable[r] + 150)
            XCTAssertEqual(extra(n, "pathBase"), Self.pathTable[r])
            XCTAssertEqual(extra(n, "shatterBase"), Self.shatterTable[r])
            XCTAssertEqual(extra(n, "pathPct"), 40)
            XCTAssertEqual(extra(n, "shatterPct"), 150)
        }
        // 魔法攻撃 0 なら公式の基礎がそのままダメージ（全体の倍率は無い）
        XCTAssertEqual(numbers(.skill1, 1, Stats()).damage, 400, accuracy: 1e-9)
        XCTAssertEqual(numbers(.skill2, 1, Stats()).damage, 225, accuracy: 1e-9)
        XCTAssertEqual(numbers(.ultimate, 1, Stats()).damage, 100, accuracy: 1e-9)
        XCTAssertEqual(Kit_H031.shatterDamage(rank: 1, stats: Stats()), 600, accuracy: 1e-9)
        XCTAssertEqual(Kit_H031.hailDamage(rank: 6, stats: Stats()), 40, accuracy: 1e-9)
        // 段の表の外（未習得の 0・上限を超えた段）は端の段に丸める
        XCTAssertEqual(Kit_H031.meteorDamage(rank: 0, stats: Stats()), 400, accuracy: 1e-9)
        XCTAssertEqual(Kit_H031.meteorDamage(rank: 9, stats: Stats()), 700, accuracy: 1e-9)
        XCTAssertEqual(Kit_H031.shatterDamage(rank: 4, stats: Stats()), 1200, accuracy: 1e-9)
        // 物理攻撃（合計・追加）が変わってもダメージは変わらない（公式の係数は魔法攻撃だけ）
        var strong = st
        strong.attack += 300
        strong.extraAttack += 300
        for slot in SkillSlot.actives {
            XCTAssertEqual(numbers(slot, 2, strong).damage, numbers(slot, 2, st).damage, accuracy: 1e-9, "\(slot)")
            XCTAssertEqual(numbers(slot, 2, st).damageType, .magic)
            XCTAssertEqual(numbers(slot, 2, st).resource, .mana)
        }
        // 段が上がると強くなる
        for slot in SkillSlot.actives {
            XCTAssertGreaterThan(numbers(slot, slot.maxRank, st).damage, numbers(slot, 1, st).damage, "\(slot)")
        }
    }

    /// CD = 公式の秒数 × (1 − CD 短縮)、マナ = 公式の表（REAL_DATA.md。マスターの値・補間・丸めではない）。
    func testCooldownAndManaEqualTheOfficialTableAtEveryRank() {
        let st = HeroGrowth.baseStats(def: def, level: 12)
        for rank in 1...6 {
            let r = rank - 1
            XCTAssertEqual(numbers(.skill1, rank, Stats()).cooldown, Self.s1CooldownTable[r], accuracy: 1e-9, "S1 CD Lv\(rank)")
            XCTAssertEqual(numbers(.skill2, rank, Stats()).cooldown, Self.s2CooldownTable[r], accuracy: 1e-9, "S2 CD Lv\(rank)")
            XCTAssertEqual(SkillSystem.cost(for: skill(.skill1), hero: def, rank: rank), Self.s1ManaTable[r], "S1 MP Lv\(rank)")
            XCTAssertEqual(SkillSystem.cost(for: skill(.skill2), hero: def, rank: rank), Self.s2ManaTable[r], "S2 MP Lv\(rank)")
            XCTAssertEqual(numbers(.skill1, rank, st).cost, Self.s1ManaTable[r])
            XCTAssertEqual(numbers(.skill2, rank, st).cost, Self.s2ManaTable[r])
        }
        for rank in 1...3 {
            let r = rank - 1
            XCTAssertEqual(numbers(.ultimate, rank, Stats()).cooldown, Self.ultCooldownTable[r], accuracy: 1e-9, "奥義 CD Lv\(rank)")
            XCTAssertEqual(SkillSystem.cost(for: skill(.ultimate), hero: def, rank: rank), Self.ultManaTable[r], "奥義 MP Lv\(rank)")
            XCTAssertEqual(numbers(.ultimate, rank, st).cost, Self.ultManaTable[r])
        }
        // CD 短縮は公式の秒数に掛ける（上限は能力値の上限 = 40%）
        var cdr = Stats()
        cdr.cooldownReduction = 0.2
        XCTAssertEqual(numbers(.skill1, 1, cdr).cooldown, 5.0 * 0.8, accuracy: 1e-9)
        XCTAssertEqual(numbers(.skill2, 6, cdr).cooldown, 8.0 * 0.8, accuracy: 1e-9)
        XCTAssertEqual(numbers(.ultimate, 1, cdr).cooldown, 50 * 0.8, accuracy: 1e-9)
        cdr.cooldownReduction = 0.9
        XCTAssertEqual(numbers(.ultimate, 3, cdr).cooldown, 40 * (1 - Balance.maxCooldownReduction), accuracy: 1e-9)
    }

    func testTagsAndCrowdControlMatchTheJapaneseClient() {
        // タグ（日本語クライアント: パッシブ = 死亡無効、スキル1 = 範囲技・減速、スキル2 = 妨害・範囲技、アルティメット = 妨害・範囲技）
        XCTAssertEqual(HeroKits.tags(heroID: "H031", slot: .passive), ["deathimmunity"])
        XCTAssertEqual(HeroKits.tags(heroID: "H031", slot: .passive), [KitTag.deathImmunity])
        XCTAssertEqual(HeroKits.tags(heroID: "H031", slot: .skill1), ["aoe", "slow"])
        XCTAssertEqual(HeroKits.tags(heroID: "H031", slot: .skill2), ["disrupt", "aoe"])
        XCTAssertEqual(HeroKits.tags(heroID: "H031", slot: .ultimate), ["disrupt", "aoe"])
        for slot in SkillSlot.allCases {
            for tag in HeroKits.tags(heroID: "H031", slot: slot) { XCTAssertTrue(KitTag.all.contains(tag), tag) }
        }
        // CC（全 Lv 一定）: スキル1 減速 40% / 1 秒、スキル2 凍結 1 秒、アルティメット 減速 80% / 1.2 秒 + 凍結。凍結は stun で表す
        let stats = HeroGrowth.baseStats(def: def, level: 6)
        for rank in [1, 6] {
            let n1 = numbers(.skill1, rank, stats)
            XCTAssertEqual(n1.cc, .slow)
            XCTAssertEqual(n1.ccDuration, 1.0)
            XCTAssertEqual(extra(n1, "slow"), 40)
            let n2 = numbers(.skill2, rank, stats)
            XCTAssertEqual(n2.cc, .stun)
            XCTAssertEqual(n2.ccDuration, 1.0)
        }
        for rank in [1, 3] {
            let n3 = numbers(.ultimate, rank, stats)
            XCTAssertEqual(n3.cc, .stun)
            XCTAssertEqual(n3.ccDuration, 1.0)
            XCTAssertEqual(extra(n3, "slow"), 80)
            XCTAssertEqual(extra(n3, "slowDuration"), 1.2, accuracy: 1e-12)
        }
        // オーリアのスキルは術者を動かさない（敵のバインド中も撃てる）
        for slot in SkillSlot.actives {
            XCTAssertFalse(SkillCatalog.movesCaster(SkillCatalog.targeting(for: skill(slot), hero: def).archetype), "\(slot)")
        }
    }

    func testFreezeGrowsWithAbilityPowerLikeTheOfficialText() {
        // アルティメット: 1 秒 + 魔法攻撃 100 ごとに 0.2 秒（公式に上限の記載は無い）
        XCTAssertEqual(Kit_H031.glacierFreeze(abilityPower: 0), 1.0, accuracy: 1e-12)
        XCTAssertEqual(Kit_H031.glacierFreeze(abilityPower: 100), 1.2, accuracy: 1e-12)
        XCTAssertEqual(Kit_H031.glacierFreeze(abilityPower: 250), 1.5, accuracy: 1e-12)
        XCTAssertEqual(Kit_H031.glacierFreeze(abilityPower: 500), 2.0, accuracy: 1e-12, "上限なし")
        XCTAssertEqual(Kit_H031.glacierFreeze(abilityPower: -50), 1.0, accuracy: 1e-12)
        // スキル2: 1 秒 + 魔法攻撃 100 ごとに 0.06 秒
        XCTAssertEqual(Kit_H031.breezeFreeze(abilityPower: 0), 1.0, accuracy: 1e-12)
        XCTAssertEqual(Kit_H031.breezeFreeze(abilityPower: 100), 1.06, accuracy: 1e-12)
        XCTAssertEqual(Kit_H031.breezeFreeze(abilityPower: 250), 1.15, accuracy: 1e-12)
        var st = Stats()
        st.abilityPower = 200
        let n = numbers(.ultimate, 2, st)
        XCTAssertEqual(n.ccDuration, 1.4, accuracy: 1e-12)
        XCTAssertEqual(extra(n, "freeze"), 1.4, accuracy: 1e-12)
        let n2 = numbers(.skill2, 2, st)
        XCTAssertEqual(n2.ccDuration, 1.12, accuracy: 1e-12)
        // 実際の凍結: 魔法攻撃 250 なら凍結エリアの凍結は 1.15 秒（撃った時点の魔力）
        var w = SkillWorld()
        let k = addOria(&w)
        let e = w.addDummyEnemy(at: skillArena + Vec2(500, 0))
        w.s.units[k].stats.abilityPower = 250
        XCTAssertTrue(w.cast(k, .skill2, .direction(Self.east)))
        w.run(seconds: 0.34)
        let freeze = status(w, e, .stun, tag: T.freezeTag)
        XCTAssertGreaterThan(freeze?.remaining ?? 0, 1.05)
        XCTAssertLessThanOrEqual(freeze?.remaining ?? 0, 1.15 + 1e-9)
    }

    /// 公式の文（日本語クライアント）にスキル吸収率・攻撃エフェクト・「ミニオンには ○%」「モンスターに ○%」の記載が無い →
    /// すべて既定（スキル吸収率 100%、攻撃エフェクトなし、ミニオン・モンスターへ等倍）。ミニオンへの全体の × 0.2 は撤廃済み。
    func testNoSkillCarriesASpellVampRatioAttackEffectOrMinionModifier() {
        var w = SkillWorld()
        let k = addOria(&w, ranks: [6, 6, 3])
        XCTAssertTrue(w.cast(k, .skill1, .point(skillArena + Vec2(500, 0))))
        XCTAssertTrue(w.cast(k, .skill2, .direction(Self.east)))
        XCTAssertTrue(w.cast(k, .ultimate, .direction(Self.east)))
        let payloads = w.s.zones.map(\.payload) + w.s.projectiles.map(\.payload)
        XCTAssertEqual(w.s.zones.count, 1 + T.s1Hails + 2 + 1, "隕石・雹 5・霜風・凍結エリア・氷河")
        XCTAssertEqual(w.s.projectiles.count, 1, "霜の道")
        for p in payloads {
            XCTAssertEqual(p.spellVampRatio, 1, "スキル吸収率は既定 100%")
            XCTAssertNil(p.attackEffect)
            XCTAssertFalse(p.appliesOnHit)
            XCTAssertEqual(p.minionMultiplier, 1)
            XCTAssertEqual(p.monsterMultiplier, 1)
            XCTAssertEqual(p.damageType, .magic)
        }

        // ミニオンにも公式のダメージがそのまま入る（防御のみ）
        var v = SkillWorld()
        let k2 = addOria(&v)
        let minion = v.addMinion(team: .red, at: skillArena + Vec2(500, 0))
        let n = v.numbers(k2, .skill1)
        XCTAssertTrue(v.cast(k2, .skill1, .point(skillArena + Vec2(500, 0))))
        v.run(seconds: 0.6)
        let hit = damageEvents(v, to: minion, .skill(.skill1))
        XCTAssertEqual(hit.count, 1)
        XCTAssertEqual(hit.first?.amount ?? 0, v.mitigated(n.damage, .magic, on: minion), accuracy: 1e-6)
    }

    // MARK: - S1 氷の隕石と雹

    func testHailMeteorLandsAfterDelayWithSlowThenFiveHailstones() throws {
        var w = SkillWorld()
        let k = addOria(&w)
        let center = skillArena + Vec2(500, 0)
        let e = w.addDummyEnemy(at: center)
        let n = w.numbers(k, .skill1)
        let hail = Kit_H031.hailDamage(rank: n.rank, stats: w.s.units[k].stats)
        XCTAssertTrue(w.cast(k, .skill1, .point(center)))
        XCTAssertEqual(w.castEvents.last?.archetype, .groundAoE)
        XCTAssertEqual(w.castEvents.last?.shape, .circleAtPoint)
        XCTAssertEqual(w.castEvents.last?.count, T.s1Hails)

        w.run(seconds: 0.4)
        XCTAssertTrue(w.damageEvents.isEmpty, "隕石の着弾前は無傷")
        w.run(seconds: 0.2)   // 0.6 秒
        let meteor = damageEvents(w, to: e, .skill(.skill1))
        XCTAssertEqual(meteor.count, 1)
        XCTAssertEqual(meteor[0].amount, w.mitigated(n.damage, .magic, on: e), accuracy: 1e-6)
        let slow = try XCTUnwrap(status(w, e, .slow, tag: T.s1SlowTag))
        XCTAssertEqual(slow.magnitude, 0.40, accuracy: 1e-12)
        XCTAssertGreaterThan(slow.remaining, 0.85)
        XCTAssertLessThanOrEqual(slow.remaining, 1.0)
        // 雹は隕石のあとに、中心のまわり（隕石の半径の 0.9 / 1.2 倍）へ降る: 中心に立つ相手には当たらない
        w.run(seconds: 1.0)
        let all = damageEvents(w, to: e, .skill(.skill1))
        XCTAssertEqual(all.count, 1, "隕石の中心に立つ相手には雹が当たらない（隕石だけ）")
        XCTAssertEqual(w.damage(to: e), w.mitigated(n.damage, .magic, on: e), accuracy: 1e-5)

        // 雹の落ちる位置に立つ相手: 隕石 + その雹（向き east から 72° ずつ、偶数番は内側 0.9、奇数番は外側 1.2）
        var v = SkillWorld()
        let k2 = addOria(&v)
        let spot = center + Vec2(T.s1Radius * T.hailRingInner, 0)   // k = 0 の雹の中心
        let e2 = v.addDummyEnemy(at: spot)
        XCTAssertTrue(v.cast(k2, .skill1, .point(center)))
        v.run(seconds: 2)
        let hits = damageEvents(v, to: e2, .skill(.skill1))
        XCTAssertEqual(hits.count, 2, "隕石 + 雹 1 発")
        XCTAssertEqual(hits[1].amount, v.mitigated(hail, .magic, on: e2), accuracy: 1e-6)
        XCTAssertEqual(v.damage(to: e2), v.mitigated(n.damage + hail, .magic, on: e2), accuracy: 1e-5)
    }

    func testHailScatterGeometry() {
        // 雹は隕石の半径の 0.9 / 1.2 倍の輪の上、5 つが 72° ずつ
        XCTAssertEqual(T.hailRingInner, 0.9)
        XCTAssertEqual(T.hailRingOuter, 1.2)
        var w = SkillWorld()
        let k = addOria(&w)
        let center = skillArena + Vec2(500, 0)
        XCTAssertTrue(w.cast(k, .skill1, .point(center)))
        w.tick()
        let hailZones = w.log.compactMap { e -> Vec2? in
            if case .zoneCreated(_, _, _, let visual, let c, _, _, _, _) = e, visual == Kit_H031.passiveVisual(w.ctx) { return c }
            return nil
        }
        XCTAssertEqual(hailZones.count, T.s1Hails)
        for (idx, c) in hailZones.enumerated() {
            let ring = T.s1Radius * (idx % 2 == 0 ? T.hailRingInner : T.hailRingOuter)
            XCTAssertEqual(c.distance(to: center), ring, accuracy: 1e-6, "雹 \(idx)")
            XCTAssertGreaterThan(c.distance(to: center), T.hailRadius, "中心は雹の半径の外 = 中心に立つ相手に当たらない")
        }
    }

    func testHailSlowCutsMovementSpeedByForty() {
        var w = SkillWorld()
        let k = addOria(&w)
        let center = skillArena + Vec2(500, 0)
        let e = w.addDummyEnemy(at: center)
        let before = w.s.units[e].stats.moveSpeed
        XCTAssertTrue(w.cast(k, .skill1, .point(center)))
        w.run(seconds: 0.6)
        // 40% の減速。MLBB の移動速度の式（MLBB の単位で計算し、230 未満へ動いた分は逓減）の後にマップ縮尺
        XCTAssertEqual(w.s.units[e].stats.moveSpeed,
                       MoveSpeedMath.calculated(basic: before / Balance.mapScale, bonus: 0, slow: 0.4, decays: true) * Balance.mapScale,
                       accuracy: 1e-6)
        w.run(seconds: 1.2)
        XCTAssertNil(status(w, e, .slow, tag: T.s1SlowTag), "1 秒で解ける")
        XCTAssertEqual(w.s.units[e].stats.moveSpeed, before, accuracy: 1e-6)
    }

    func testHailGeometryOnlyHitsInsideTheLandingCircle() {
        var w = SkillWorld()
        let k = addOria(&w)
        let center = skillArena + Vec2(500, 0)
        let inside = w.addDummyEnemy(at: center + Vec2(0, 120))
        let edge = w.addDummyEnemy(at: center + Vec2(215, 0), hero: "H004")
        let outside = w.addDummyEnemy(at: center + Vec2(0, -400), hero: "H005")
        XCTAssertTrue(w.cast(k, .skill1, .point(center)))
        w.run(seconds: 2)
        XCTAssertEqual(damageEvents(w, to: inside, .skill(.skill1)).first.map { $0.amount },
                       w.mitigated(w.numbers(k, .skill1).damage, .magic, on: inside))
        XCTAssertGreaterThanOrEqual(damageEvents(w, to: edge, .skill(.skill1)).count, 1, "縁にも隕石は届く")
        XCTAssertLessThan(damageEvents(w, to: edge, .skill(.skill1)).count, 1 + T.s1Hails, "縁の相手は雹を全部は受けない")
        XCTAssertEqual(w.damage(to: outside), 0)
        XCTAssertNil(status(w, outside, .slow))
    }

    func testHailAimClampsToRangeAndAutoAimsAtNearbyEnemy() {
        var w = SkillWorld()
        let k = addOria(&w)
        let far = w.addDummyEnemy(at: skillArena + Vec2(1100, 0))
        XCTAssertTrue(w.cast(k, .skill1, .point(skillArena + Vec2(2000, 0))))
        // 射程 650 に丸められるので 1100 先は隕石の円（650 + 170 + 55 = 875）も、雹の輪（650 + 204 + 85 + 55 ≒ 995）も外
        w.run(seconds: 2)
        XCTAssertEqual(w.damage(to: far), 0)
        XCTAssertEqual(w.castEvents.last?.target.x ?? 0, skillArena.x + 650, accuracy: 1e-6)

        var v = SkillWorld()
        let k2 = addOria(&v)
        let e = v.addDummyEnemy(at: skillArena + Vec2(450, 100))
        XCTAssertTrue(v.cast(k2, .skill1, .none), "自動照準")
        v.run(seconds: 2)
        XCTAssertGreaterThan(v.damage(to: e, from: .skill(.skill1)), 0)
    }

    // MARK: - S2 霜風と凍結エリア

    /// 公式（原本）: 扇の霜風はダメージ、範囲の末端の凍結エリアの中の敵がフリーズ。扇の手前（凍結エリアの外）の敵はダメージだけ
    /// （以前の「撃った位置から 200 未満は凍らない、200 以上は扇の霜風で凍る」は外した）。
    func testBreezeConeDamagesAndOnlyEnemiesInTheFrozenAreaFreeze() throws {
        var w = SkillWorld()
        let k = addOria(&w)
        let inArea = w.addDummyEnemy(at: skillArena + Vec2(500, 0))
        let near = w.addDummyEnemy(at: skillArena + Vec2(120, 0), hero: "H004")
        // 扇の中（約 27°）だが凍結エリア（中心 540・半径 190 + 55）の外
        let mid = w.addDummyEnemy(at: skillArena + Vec2(250, 130), hero: "H006")
        let side = w.addDummyEnemy(at: skillArena + Vec2(400, 420), hero: "H005")
        let areaReach = areaRadius + Balance.heroRadius
        XCTAssertGreaterThan(w.s.units[mid].pos.distance(to: skillArena + Vec2(Self.areaCenter, 0)), areaReach)
        let n = w.numbers(k, .skill2)
        let tick = Kit_H031.patchTotal(rank: n.rank, stats: w.s.units[k].stats) / Double(T.s2PatchTicks)
        XCTAssertTrue(w.cast(k, .skill2, .direction(Self.east)))
        XCTAssertEqual(w.castEvents.last?.archetype, .cone)
        XCTAssertEqual(w.castEvents.last?.shape, .fan)
        XCTAssertEqual(w.castEvents.last?.halfAngle ?? 0, T.s2HalfAngle, accuracy: 1e-12)

        w.run(seconds: 0.2)
        XCTAssertTrue(w.damageEvents.isEmpty, "霜風が広がるまでの遅れがある")
        XCTAssertNil(status(w, inArea, .stun))
        w.run(seconds: 0.2)   // 0.4 秒
        let hit = damageEvents(w, to: inArea, .skill(.skill2))
        XCTAssertEqual(hit.count, 2, "霜風 + 凍結エリアの 1 回目")
        XCTAssertEqual(hit[0].amount, w.mitigated(n.damage, .magic, on: inArea), accuracy: 1e-6)
        XCTAssertEqual(hit[1].amount, w.mitigated(tick, .magic, on: inArea), accuracy: 1e-6)
        let freeze = try XCTUnwrap(status(w, inArea, .stun, tag: T.freezeTag), "凍結エリアの中の敵は凍結")
        XCTAssertGreaterThan(freeze.remaining, 0.85)
        XCTAssertLessThanOrEqual(freeze.remaining, 1.0)
        XCTAssertFalse(w.s.units[inArea].canAct)
        // 扇の手前（凍結エリアの外）はダメージだけ
        for e in [near, mid] {
            let d = damageEvents(w, to: e, .skill(.skill2))
            XCTAssertEqual(d.count, 1, "霜風だけ")
            XCTAssertEqual(d.first?.amount ?? 0, w.mitigated(n.damage, .magic, on: e), accuracy: 1e-6)
            XCTAssertNil(status(w, e, .stun), "凍結エリアの外は凍らない")
        }
        // 扇の外
        XCTAssertEqual(w.damage(to: side), 0)
        // 凍結は 1 秒で解ける
        w.run(seconds: 1.0)
        XCTAssertNil(status(w, inArea, .stun, tag: T.freezeTag))
        XCTAssertTrue(w.s.units[inArea].canAct)
        // CC の通知（凍結）は凍結エリアの中の敵にだけ
        XCTAssertEqual(freezeNotices(w, inArea), 1)
        XCTAssertEqual(freezeNotices(w, near), 0)
        XCTAssertEqual(freezeNotices(w, mid), 0)
    }

    /// 凍結エリアの縁（中心 = 術者から 540、半径 190 + 対象の半径 55）で凍るかが決まる。
    /// エリアは扇の端（650 + 55）より先まで届き、扇の外でもエリアの中なら凍る（霜風のダメージは無く、エリアのダメージだけ）。
    func testFrozenAreaEdgesDecideWhoFreezes() {
        var w = SkillWorld()
        let k = addOria(&w)
        let c = skillArena + Vec2(Self.areaCenter, 0)
        let reach = areaRadius + Balance.heroRadius
        let justIn = w.addDummyEnemy(at: c + Vec2(-200, 130))                         // 中心から 238.5
        let justOut = w.addDummyEnemy(at: c + Vec2(-200, -150), hero: "H004")         // 中心から 250（扇の中）
        let beyondCone = w.addDummyEnemy(at: skillArena + Vec2(780, 0), hero: "H005") // 扇の外、中心から 240
        let outside = w.addDummyEnemy(at: skillArena + Vec2(790, 150), hero: "H006")  // どちらの外
        XCTAssertLessThan(w.s.units[justIn].pos.distance(to: c), reach)
        XCTAssertGreaterThan(w.s.units[justOut].pos.distance(to: c), reach)
        XCTAssertLessThan(w.s.units[beyondCone].pos.distance(to: c), reach)
        XCTAssertGreaterThan(w.s.units[beyondCone].pos.distance(to: skillArena), T.s2Range + Balance.heroRadius)
        let n = w.numbers(k, .skill2)
        let tick = Kit_H031.patchTotal(rank: n.rank, stats: w.s.units[k].stats) / Double(T.s2PatchTicks)
        XCTAssertTrue(w.cast(k, .skill2, .direction(Self.east)))
        w.run(seconds: 0.4)
        XCTAssertNotNil(status(w, justIn, .stun, tag: T.freezeTag))
        XCTAssertGreaterThan(w.damage(to: justOut, from: .skill(.skill2)), 0, "扇の霜風は当たる")
        XCTAssertNil(status(w, justOut, .stun))
        XCTAssertNotNil(status(w, beyondCone, .stun, tag: T.freezeTag), "扇の外でも凍結エリアの中なら凍る")
        XCTAssertEqual(w.damage(to: beyondCone, from: .skill(.skill2)), w.mitigated(tick, .magic, on: beyondCone), accuracy: 1e-6,
                       "霜風は届かず、凍結エリアの 1 回目だけ")
        XCTAssertEqual(w.damage(to: outside), 0)
        XCTAssertNil(status(w, outside, .stun))
    }

    func testFrozenAreaAtTheFarEndDealsItsTotalInFourTicks() {
        var w = SkillWorld()
        let k = addOria(&w)
        // 扇の外（射程 650 + 55 の先）だが凍結エリア（中心 540・半径 190 + 55）には入る
        let patchOnly = w.addDummyEnemy(at: skillArena + Vec2(730, 0))
        let n = w.numbers(k, .skill2)
        XCTAssertTrue(w.cast(k, .skill2, .direction(Self.east)))
        w.run(seconds: 3)
        let ticks = damageEvents(w, to: patchOnly, .skill(.skill2))
        XCTAssertEqual(ticks.count, T.s2PatchTicks)
        let total = Kit_H031.patchTotal(rank: n.rank, stats: w.s.units[k].stats)
        for d in ticks { XCTAssertEqual(d.amount, w.mitigated(total / Double(T.s2PatchTicks), .magic, on: patchOnly), accuracy: 1e-6) }
        XCTAssertEqual(freezeNotices(w, patchOnly), 1, "凍結エリアの中なので凍る（1 回だけ）")
        // 凍結エリアの持続は 1.8 秒（0.3 秒の遅れのあと）
        XCTAssertTrue(w.s.zones.allSatisfy { $0.done })

        // 扇の中・凍結エリアの中の敵は、霜風 + エリアの合計を受ける
        var v = SkillWorld()
        let k2 = addOria(&v)
        let e = v.addDummyEnemy(at: skillArena + Vec2(450, 0))
        let n2 = v.numbers(k2, .skill2)
        XCTAssertTrue(v.cast(k2, .skill2, .direction(Self.east)))
        v.run(seconds: 3)
        let patch2 = Kit_H031.patchTotal(rank: n2.rank, stats: v.s.units[k2].stats)
        XCTAssertEqual(patch2, n2.damage, accuracy: 1e-9, "公式: 霜風と凍結エリアの合計は同じ表（1 : 1）")
        XCTAssertEqual(v.damage(to: e), v.mitigated(n2.damage + patch2, .magic, on: e), accuracy: 1e-5)
    }

    /// 凍結はエリアができた瞬間にエリア内にいる敵だけに 1 回（推測。持続の間の 4 回の当たりで掛け直さない）。
    /// 後から入ってきた敵はダメージだけ受ける。
    func testFrozenAreaFreezesOnceWhenItFormsAndLateEntrantsOnlyTakeDamage() {
        var w = SkillWorld()
        let k = addOria(&w)
        let early = w.addDummyEnemy(at: skillArena + Vec2(Self.areaCenter, 0))
        let late = w.addDummyEnemy(at: skillArena + Vec2(Self.areaCenter, 600), hero: "H004")
        XCTAssertTrue(w.cast(k, .skill2, .direction(Self.east)))
        w.run(seconds: 0.4)
        XCTAssertNotNil(status(w, early, .stun, tag: T.freezeTag))
        XCTAssertEqual(w.damage(to: late), 0)
        // エリアができた後に入ってくる
        w.s.units[late].pos = skillArena + Vec2(Self.areaCenter, 150)
        w.run(seconds: 2.0)
        XCTAssertEqual(damageEvents(w, to: late, .skill(.skill2)).count, T.s2PatchTicks - 1, "残りの 3 回のダメージは受ける")
        XCTAssertEqual(freezeNotices(w, late), 0, "後から入った敵は凍らない")
        XCTAssertNil(status(w, late, .stun))
        XCTAssertEqual(damageEvents(w, to: early, .skill(.skill2)).count, 1 + T.s2PatchTicks, "霜風 + エリア 4 回")
        XCTAssertEqual(freezeNotices(w, early), 1, "エリアの 2 回目以降で凍結を掛け直さない")
        XCTAssertNil(status(w, early, .stun), "1 秒で解けたまま")
    }

    func testBreezeFreezeStopsAttacksAndCasts() {
        var w = SkillWorld()
        let k = addOria(&w)
        let e = w.addDummyEnemy(at: skillArena + Vec2(450, 0), hero: "H004")
        XCTAssertTrue(w.cast(k, .skill2, .direction(Self.east)))
        w.run(seconds: 0.4)
        XCTAssertTrue(w.s.units[e].has(.stun))
        XCTAssertFalse(SkillSystem.canCast(w.s, w.ctx, heroIndex: e, slot: .skill1), "凍結中は撃てない")
    }

    // MARK: - 凍結はタワーにも効く

    /// TowerSystem（索敵）込みで進める（SkillWorld.tick は TowerSystem を回さない）。
    private func runWithTowers(_ w: inout SkillWorld, seconds: Double) {
        for _ in 0..<Int((seconds * Balance.tickRate).rounded(.up)) {
            TowerSystem.update(&w.s, w.ctx)
            w.tick()
        }
    }

    private func towerAttackStarts(_ w: SkillWorld, _ t: Int) -> Int {
        w.log.filter { if case .attackStarted(let src, _) = $0 { return src == w.id(t) } else { return false } }.count
    }

    /// 公式: 「自身のフリーズ効果はタワーにも適用」。凍結エリアの中の敵のタワーは凍り、凍結の間タワーは攻撃しない。
    /// エリアの 2 回目以降で掛け直さない。タワーへのダメージは無く、味方のタワーは凍らない。他の弱体はこれまでどおり構造物に付かない。
    func testFrozenAreaFreezesAnEnemyTurretSoItStopsAttackingWithoutDamage() throws {
        var w = SkillWorld()
        let k = addOria(&w)
        let tower = w.addTower(team: .red, at: skillArena + Vec2(450, 0))
        let ally = w.addTower(team: .blue, at: skillArena + Vec2(400, 150))
        for t in [tower, ally] { w.s.units[t].visibleMask = Team.blue.visionBit | Team.red.visionBit }
        let hp = w.s.units[tower].hp
        XCTAssertTrue(w.cast(k, .skill2, .direction(Self.east)))
        runWithTowers(&w, seconds: 0.4)
        let freeze = try XCTUnwrap(status(w, tower, .stun, tag: T.freezeTag), "凍結エリアの凍結はタワーにも効く")
        XCTAssertGreaterThan(freeze.remaining, 0.85)
        XCTAssertLessThanOrEqual(freeze.remaining, 1.0)
        XCTAssertFalse(w.s.units[tower].canAct)
        XCTAssertNil(w.s.units[tower].windupRemaining)
        XCTAssertEqual(freezeNotices(w, tower), 1)
        XCTAssertNil(status(w, ally, .stun), "味方のタワーは凍らない")
        // 凍結の間は攻撃しない（射程内のオーリアを狙ったまま）
        w.log.removeAll()
        runWithTowers(&w, seconds: 0.8)
        XCTAssertEqual(towerAttackStarts(w, tower), 0, "凍ったタワーは攻撃しない")
        XCTAssertEqual(w.s.units[tower].attackTargetID, w.id(k), "凍結の間は狙いを変えない")
        // 解けると攻撃を再開する（エリアの残りの当たりで掛け直さない）
        runWithTowers(&w, seconds: 1.5)
        XCTAssertNil(status(w, tower, .stun, tag: T.freezeTag))
        XCTAssertEqual(freezeNotices(w, tower), 0, "凍結エリアの 2 回目以降でタワーを凍らせ直さない")
        XCTAssertGreaterThan(towerAttackStarts(w, tower), 0, "解けたタワーは攻撃を再開する")
        // タワーへのダメージは無い
        XCTAssertEqual(w.damage(to: tower), 0)
        XCTAssertEqual(w.s.units[tower].hp, hp, accuracy: 1e-9)
        // 汎用の CC・弱体はこれまでどおり構造物に付かない
        CombatSystem.addStatus(&w.s, targetIndex: ally, StatusEffect(kind: .stun, duration: 1, sourceID: w.id(k)))
        CombatSystem.addStatus(&w.s, targetIndex: tower, StatusEffect(kind: .slow, duration: 1, magnitude: 0.5))
        XCTAssertFalse(w.s.units[ally].has(.stun))
        XCTAssertFalse(w.s.units[tower].has(.slow))
    }

    /// 扇の手前（凍結エリアの外）のタワーは凍らない。扇の外でも凍結エリアの中のタワーは凍る（ヒーローと同じ規則）。
    func testOnlyTurretsInsideTheFrozenAreaFreeze() {
        var w = SkillWorld()
        let k = addOria(&w)
        let near = w.addTower(team: .red, at: skillArena + Vec2(180, 0))
        XCTAssertGreaterThan(w.s.units[near].pos.distance(to: skillArena + Vec2(Self.areaCenter, 0)),
                             areaRadius + w.s.units[near].radius)
        XCTAssertTrue(w.cast(k, .skill2, .direction(Self.east)))
        w.run(seconds: 0.4)
        XCTAssertNil(status(w, near, .stun))
        XCTAssertEqual(w.damage(to: near), 0)

        var v = SkillWorld()
        let k2 = addOria(&v)
        let beyond = v.addTower(team: .red, at: skillArena + Vec2(800, 0))
        XCTAssertGreaterThan(v.s.units[beyond].pos.distance(to: skillArena), T.s2Range + v.s.units[beyond].radius,
                             "扇の外")
        XCTAssertTrue(v.cast(k2, .skill2, .direction(Self.east)))
        v.run(seconds: 0.4)
        XCTAssertNotNil(status(v, beyond, .stun, tag: T.freezeTag), "凍結エリアの中のタワーは凍る")
        XCTAssertEqual(v.damage(to: beyond), 0)
    }

    /// 氷河の砕けもタワーを凍らせる（発動時の魔力の秒数）。無敵の構造物（前段が残る内側のタワー）は凍らない。ダメージは無い。
    func testGlacierShatterFreezesEnemyTurretsButNotInvulnerableOnes() throws {
        var w = SkillWorld()
        let k = addOria(&w)
        let outer = w.addTower(team: .red, at: skillArena + Vec2(600, 0))
        let innerUnit = UnitFactory.makeStructure(TowerSpot(team: .red, lane: .mid, tier: .inner,
                                                            pos: skillArena + Vec2(450, 250), isCore: false))
        let innerID = w.s.addUnit(innerUnit)
        let inner = try XCTUnwrap(w.s.index(of: innerID))
        XCTAssertTrue(TowerSystem.isInvulnerable(w.s, w.ctx, index: inner))
        let expected = Kit_H031.glacierFreeze(abilityPower: w.s.units[k].stats.abilityPower)
        XCTAssertTrue(w.cast(k, .ultimate, .direction(Self.east)))
        w.run(seconds: 1.1)
        XCTAssertNil(status(w, outer, .stun), "砕ける前は凍らない")
        w.run(seconds: 0.2)   // 1.3 秒
        let freeze = try XCTUnwrap(status(w, outer, .stun, tag: T.freezeTag), "砕けの凍結はタワーにも効く")
        XCTAssertEqual(freeze.duration, expected, accuracy: 1e-9)
        XCTAssertFalse(w.s.units[outer].canAct)
        XCTAssertNil(status(w, inner, .stun), "無敵の構造物は凍らない")
        XCTAssertEqual(w.damage(to: outer), 0)
        XCTAssertEqual(w.damage(to: inner), 0)
    }

    // MARK: - 奥義

    func testUltimatePathSlowsThenGlacierShattersAndFreezes() throws {
        var w = SkillWorld()
        let k = addOria(&w)
        let onPath = w.addDummyEnemy(at: skillArena + Vec2(300, 0))
        let sideInArea = w.addDummyEnemy(at: skillArena + Vec2(450, 250), hero: "H004")
        let farSide = w.addDummyEnemy(at: skillArena + Vec2(450, 520), hero: "H005")
        let behind = w.addDummyEnemy(at: skillArena + Vec2(-250, 0), hero: "H006")
        let n = w.numbers(k, .ultimate)
        let shatter = Kit_H031.shatterDamage(rank: n.rank, stats: w.s.units[k].stats)
        XCTAssertTrue(w.cast(k, .ultimate, .direction(Self.east)))
        XCTAssertEqual(w.castEvents.last?.archetype, .piercingLine)
        XCTAssertEqual(w.castEvents.last?.shape, .wideLine)
        XCTAssertEqual(w.castEvents.last?.duration ?? 0, T.ultGlacierDelay, accuracy: 1e-12)

        // 霜の道: 小さなダメージと 80% の鈍足
        w.run(seconds: 0.4)
        let path = damageEvents(w, to: onPath, .skill(.ultimate))
        XCTAssertEqual(path.count, 1)
        XCTAssertEqual(path[0].amount, w.mitigated(n.damage, .magic, on: onPath), accuracy: 1e-6)
        let slow = try XCTUnwrap(status(w, onPath, .slow, tag: T.pathSlowTag))
        XCTAssertEqual(slow.magnitude, 0.8, accuracy: 1e-12)
        XCTAssertGreaterThan(slow.remaining, 0.8)
        XCTAssertEqual(w.damage(to: sideInArea), 0, "道の外（幅 120 + 55 の外）は鈍足も無い")
        XCTAssertNil(status(w, sideInArea, .slow))

        // 砕ける前
        w.run(seconds: 0.7)   // 1.1 秒
        XCTAssertEqual(damageEvents(w, to: onPath, .skill(.ultimate)).count, 1)
        XCTAssertNil(status(w, onPath, .stun))
        // 砕ける（1.2 秒）
        w.run(seconds: 0.2)   // 1.3 秒
        for e in [onPath, sideInArea] {
            let hits = damageEvents(w, to: e, .skill(.ultimate))
            XCTAssertEqual(hits.last?.amount ?? 0, w.mitigated(shatter, .magic, on: e), accuracy: 1e-6)
            let freeze = try XCTUnwrap(status(w, e, .stun, tag: T.freezeTag))
            XCTAssertGreaterThan(freeze.remaining, 0.85)
            XCTAssertLessThanOrEqual(freeze.remaining, 1.0)
            XCTAssertFalse(w.s.units[e].canAct)
        }
        XCTAssertEqual(w.damage(to: farSide), 0)
        XCTAssertEqual(w.damage(to: behind), 0)
        // 1 秒後に解ける
        w.run(seconds: 1.2)
        XCTAssertTrue(w.s.units[onPath].canAct)
        XCTAssertTrue(w.s.units[sideInArea].canAct)
        // 道 + 砕け（公式の Lv1: 100 + 600、魔法攻撃 0）
        XCTAssertEqual(n.damage + shatter, 700, accuracy: 1e-9)
        XCTAssertEqual(w.damage(to: onPath), w.mitigated(n.damage + shatter, .magic, on: onPath), accuracy: 1e-5)
    }

    func testUltimateFreezeIsLongerWithAbilityPowerAtCast() throws {
        var w = SkillWorld()
        let k = addOria(&w)
        let e = w.addDummyEnemy(at: skillArena + Vec2(400, 0))
        w.s.units[k].stats.abilityPower = 250
        XCTAssertTrue(w.cast(k, .ultimate, .direction(Self.east)))
        w.s.units[k].stats.abilityPower = 0   // 砕けるまでに魔力が変わっても、撃った時点の値
        w.run(seconds: 1.3)
        let freeze = try XCTUnwrap(status(w, e, .stun, tag: T.freezeTag))
        XCTAssertGreaterThan(freeze.remaining, 1.35)
        XCTAssertLessThanOrEqual(freeze.remaining, 1.5)
    }

    func testUltimateDoesNotFreezeCCImmuneOrInvulnerableTargets() {
        var w = SkillWorld()
        let k = addOria(&w)
        let immune = w.addDummyEnemy(at: skillArena + Vec2(400, 0))
        let guarded = w.addDummyEnemy(at: skillArena + Vec2(450, 150), hero: "H004")
        CombatSystem.addStatus(&w.s, targetIndex: immune, StatusEffect(kind: .ccImmune, duration: 5))
        CombatSystem.addStatus(&w.s, targetIndex: guarded, StatusEffect(kind: .invulnerable, duration: 5))
        XCTAssertTrue(w.cast(k, .ultimate, .direction(Self.east)))
        w.run(seconds: 1.4)
        XCTAssertNil(status(w, immune, .stun))
        XCTAssertNil(status(w, immune, .slow))
        XCTAssertGreaterThan(w.damage(to: immune), 0, "ダメージは入る")
        XCTAssertEqual(w.damage(to: guarded), 0)
        XCTAssertNil(status(w, guarded, .stun))
    }

    func testUltimateOnlyReachesEnemiesNotAllies() {
        var w = SkillWorld()
        let k = addOria(&w)
        let ally = w.addHero("H004", team: .blue, at: skillArena + Vec2(300, 0))
        let e = w.addDummyEnemy(at: skillArena + Vec2(400, 0))
        XCTAssertTrue(w.cast(k, .ultimate, .direction(Self.east)))
        w.run(seconds: 1.4)
        XCTAssertEqual(w.damage(to: ally), 0)
        XCTAssertGreaterThan(w.damage(to: e), 0)
    }

    // MARK: - パッシブ（氷の誇り）

    /// 公式: 最大 HP の 30% を徐々に回復（全レベル一定）。以前の「Lv1 0% → Lv15 30%」の伸び（prideHealLv1 / prideHealFullLevel）は外した。
    func testPrideHealIsThirtyPercentAtEveryLevel() {
        XCTAssertEqual(T.prideHealRatio, 0.30, accuracy: 1e-12)
        for level in [1, 6, 12, 15] {
            var w = SkillWorld()
            let k = addOria(&w, level: level)
            let e = w.addDummyEnemy(at: skillArena + Vec2(400, 0))
            let maxHP = w.s.units[k].stats.maxHP
            fatal(&w, k, from: e)
            w.run(seconds: 1.6)
            XCTAssertEqual(w.s.units[k].hp, 1 + maxHP * 0.30, accuracy: maxHP * 0.012, "Lv\(level)")
            XCTAssertTrue(w.s.units[k].isAlive)
        }
        // 説明文の数値も全レベル 30%（レベルの下限の項目は無い）
        let np = numbers(.passive, 1, HeroGrowth.baseStats(def: def, level: 1))
        XCTAssertEqual(extra(np, "heal"), 30)
        XCTAssertEqual(extra(np, "freeze"), 1.5)
        XCTAssertEqual(extra(np, "cooldown"), 150)
        XCTAssertFalse(np.extras.contains { $0.key == "healMin" })
    }

    func testFatalDamageIsNegatedAndFreezesTheOwnerInvulnerably() throws {
        var w = SkillWorld()
        let k = addOria(&w, level: 1)
        let e = w.addDummyEnemy(at: skillArena + Vec2(400, 0))
        let maxHP = w.s.units[k].stats.maxHP
        fatal(&w, k, from: e)
        XCTAssertTrue(w.s.units[k].isAlive)
        XCTAssertEqual(w.s.units[k].hp, 1, accuracy: 1e-9)
        XCTAssertTrue(w.s.pendingDeaths.isEmpty)
        XCTAssertEqual(w.kit(k).oriaSaves, 1)
        XCTAssertEqual(w.kit(k).oriaPrideCooldown, 150, accuracy: 1e-9)
        XCTAssertTrue(w.s.units[k].has(.invulnerable))
        XCTAssertTrue(w.s.units[k].has(.suppress))
        XCTAssertFalse(w.s.units[k].canAct, "凍結中は行動できない")
        XCTAssertTrue(w.damageEvents.filter { $0.targetID == w.id(k) }.isEmpty, "無効にしたダメージは通らない")
        // 凍結中の追加ダメージも通らない
        fatal(&w, k, from: e)
        XCTAssertEqual(w.s.units[k].hp, 1, accuracy: 1e-9)
        XCTAssertFalse(w.cast(k, .skill1, .direction(Self.east)), "凍結中は撃てない")
        // 凍結の弱体は（無敵なので）新たに付かない
        CombatSystem.addStatus(&w.s, targetIndex: k, StatusEffect(kind: .stun, duration: 2, sourceID: w.id(e)))
        XCTAssertNil(status(w, k, .stun))

        // 1.5 秒かけて最大 HP の 30% を回復する（Lv1 でも。自然回復の分だけ多少の誤差）
        w.run(seconds: 0.75)
        let half = w.s.units[k].hp
        XCTAssertEqual(half - 1, maxHP * 0.30 * 0.5, accuracy: maxHP * 0.01)
        XCTAssertGreaterThan(w.kit(k).oriaFreezeLeft, 0)
        w.run(seconds: 0.85)
        XCTAssertEqual(w.s.units[k].hp, 1 + maxHP * 0.30, accuracy: maxHP * 0.01)
        XCTAssertEqual(w.kit(k).oriaHealTicks, 0)
        XCTAssertFalse(w.s.units[k].has(.invulnerable), "1.5 秒で解ける")
        XCTAssertFalse(w.s.units[k].has(.suppress))
        XCTAssertTrue(w.s.units[k].canAct)
        XCTAssertEqual(w.kit(k).oriaFreezeLeft, 0)
        // 回復は 30% で止まる（以降は自然回復だけ）
        let afterFreeze = w.s.units[k].hp
        w.run(seconds: 1)
        XCTAssertLessThan(w.s.units[k].hp - afterFreeze, maxHP * 0.02)
    }

    func testPrideDoesNotTriggerOnSurvivableHitsAndCountsShieldsAsHealth() {
        var w = SkillWorld()
        let k = addOria(&w)
        let e = w.addDummyEnemy(at: skillArena + Vec2(400, 0))
        let hp = w.s.units[k].hp
        // 倒れない量
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(e), targetIndex: k, amount: hp - 1, type: .trueDamage, source: .spell)
        XCTAssertEqual(w.kit(k).oriaSaves, 0)
        XCTAssertGreaterThan(w.s.units[k].hp, 0)
        XCTAssertEqual(w.kit(k).oriaPrideCooldown, 0)
        // シールドで受けきれる量は致命傷ではない
        CombatSystem.addShield(&w.s, w.ctx, sourceID: w.id(k), targetIndex: k, amount: 500, duration: 5)
        let remaining = w.s.units[k].hp
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(e), targetIndex: k, amount: remaining + 400, type: .trueDamage, source: .spell)
        XCTAssertEqual(w.kit(k).oriaSaves, 0)
        XCTAssertTrue(w.s.units[k].isAlive)
        // シールドを超える致命傷は無効（シールドは失う）
        CombatSystem.addShield(&w.s, w.ctx, sourceID: w.id(k), targetIndex: k, amount: 300, duration: 5)
        let hp2 = w.s.units[k].hp
        let cover = w.s.units[k].totalShield
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(e), targetIndex: k, amount: hp2 + cover + 1, type: .trueDamage, source: .spell)
        XCTAssertEqual(w.kit(k).oriaSaves, 1)
        XCTAssertTrue(w.s.units[k].shields.isEmpty)
        XCTAssertEqual(w.s.units[k].hp, 1, accuracy: 1e-9)
    }

    func testPrideIsOnA150SecondCooldownAndSecondFatalBlowKills() {
        var w = SkillWorld()
        let k = addOria(&w)
        let e = w.addDummyEnemy(at: skillArena + Vec2(400, 0))
        fatal(&w, k, from: e)
        w.run(seconds: 2)   // 凍結が解ける
        XCTAssertTrue(w.s.units[k].canAct)
        XCTAssertEqual(w.kit(k).oriaPrideCooldown, 148, accuracy: 0.1)
        // クールダウン中の致命傷では倒れる
        fatal(&w, k, from: e)
        XCTAssertFalse(w.s.units[k].isAlive)
        DeathSystem.process(&w.s, w.ctx)
        XCTAssertEqual(w.kit(k).oriaSaves, 0, "死亡で全リセット")
        XCTAssertEqual(w.kit(k).oriaPrideCooldown, 148, accuracy: 0.1, "再発動までの残りは死亡しても残る")
        XCTAssertTrue(w.s.units[k].hero!.isDead)

        // 150 秒後には再び働く
        var v = SkillWorld()
        let k2 = addOria(&v)
        let e2 = v.addDummyEnemy(at: skillArena + Vec2(400, 0))
        fatal(&v, k2, from: e2)
        v.run(seconds: 151)
        XCTAssertEqual(v.kit(k2).oriaPrideCooldown, 0, accuracy: 1e-9)
        v.s.units[k2].hp = v.s.units[k2].stats.maxHP
        fatal(&v, k2, from: e2)
        XCTAssertTrue(v.s.units[k2].isAlive)
        XCTAssertEqual(v.kit(k2).oriaSaves, 2)
    }

    func testPrideTriggersBeforeTheImmortalItem() {
        var w = SkillWorld()
        let k = addOria(&w)
        let e = w.addDummyEnemy(at: skillArena + Vec2(400, 0))
        w.s.units[k].hero!.items = ["EQ304"]     // イモータル（倒れた後、その場で 2.5 秒後に復活）
        w.s.units[k].hero!.itemInvested = [2120]
        StatCalculator.recompute(&w.s, k, w.ctx)
        w.s.units[k].hp = w.s.units[k].stats.maxHP
        XCTAssertTrue(w.s.units[k].hero!.itemRuntime.ready(.immortal, at: w.s.time))
        fatal(&w, k, from: e)
        XCTAssertEqual(w.kit(k).oriaSaves, 1)
        XCTAssertTrue(w.s.units[k].isAlive)
        XCTAssertTrue(w.s.units[k].hero!.itemRuntime.ready(.immortal, at: w.s.time), "氷の誇りが先に働き、装備は残る")
        XCTAssertEqual(w.s.units[k].hp, 1, accuracy: 1e-9)
        // 氷の誇りが再使用待ちなら倒れ、装備がその場で復活させる
        w.run(seconds: 2)
        let deathPos = w.s.units[k].pos
        w.s.units[k].hp = 5
        fatal(&w, k, from: e)
        XCTAssertFalse(w.s.units[k].isAlive)
        DeathSystem.process(&w.s, w.ctx)
        XCTAssertFalse(w.s.units[k].hero!.itemRuntime.ready(.immortal, at: w.s.time))
        XCTAssertEqual(w.s.units[k].hero!.respawnTimer, 2.5, accuracy: 1e-9)
        for _ in 0..<90 where !w.s.units[k].isAlive {
            w.s.tick += 1
            w.s.time = Double(w.s.tick) * Balance.dt
            RespawnSystem.update(&w.s, w.ctx)
        }
        XCTAssertTrue(w.s.units[k].isAlive)
        XCTAssertEqual(w.s.units[k].pos, deathPos)
        XCTAssertEqual(w.s.units[k].hp, w.s.units[k].stats.maxHP * 0.16, accuracy: 1e-6)
    }

    func testPrideNeverFiresForEnemiesWithoutTheKitAndReplacesTheGenericArcanistPassive() {
        var w = SkillWorld()
        let k = addOria(&w)
        let e = w.addDummyEnemy(at: skillArena + Vec2(450, 0), hero: "H004")
        XCTAssertNil(w.s.units[e].hero?.kit)
        // 汎用アルカニストの「スキル命中で他スキルの CD −0.6 秒」は無い
        XCTAssertTrue(w.cast(k, .skill2, .direction(Self.east)))
        let cdAfterCast = w.s.units[k].hero!.cooldown(.skill2)
        XCTAssertTrue(w.cast(k, .skill1, .point(skillArena + Vec2(450, 0))))
        w.run(seconds: 0.6)
        XCTAssertGreaterThan(w.damage(to: e, from: .skill(.skill1)), 0)
        XCTAssertEqual(w.s.units[k].hero!.cooldown(.skill2), cdAfterCast - 0.6, accuracy: 0.1,
                       "経過した時間だけ減る（命中による短縮は無い）")
        // 敵側は致命傷で普通に倒れる
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(k), targetIndex: e, amount: 1e9, type: .trueDamage, source: .spell)
        XCTAssertFalse(w.s.units[e].isAlive)
    }

    func testPrideBadgeShowsFreezeThenCooldownThenReady() {
        var w = SkillWorld()
        let k = addOria(&w)
        let e = w.addDummyEnemy(at: skillArena + Vec2(400, 0))
        var b = HeroKits.badge(w.s.units[k].hero!, slot: .passive)
        XCTAssertEqual(b?.kind, .stacks)
        XCTAssertEqual(b?.value, 1)
        fatal(&w, k, from: e)
        b = HeroKits.badge(w.s.units[k].hero!, slot: .passive)
        XCTAssertEqual(b?.kind, .timer)
        XCTAssertEqual(b?.total, 1.5)
        w.run(seconds: 2)
        b = HeroKits.badge(w.s.units[k].hero!, slot: .passive)
        XCTAssertEqual(b?.kind, .timer)
        XCTAssertEqual(b?.total, 150)
        XCTAssertNil(HeroKits.badge(w.s.units[k].hero!, slot: .skill1))
    }

    // MARK: - 端の場合

    func testNoTargetCastsStillSpendButNothingBreaks() {
        var w = SkillWorld()
        let k = addOria(&w)
        for slot in SkillSlot.actives {
            let before = w.s.units[k].resource
            XCTAssertTrue(w.cast(k, slot, .none), "\(slot)")
            XCTAssertLessThan(w.s.units[k].resource, before)
            XCTAssertGreaterThan(w.s.units[k].hero!.cooldown(slot), 0)
        }
        w.run(seconds: 3)
        XCTAssertTrue(w.damageEvents.isEmpty)
        XCTAssertTrue(w.s.projectiles.allSatisfy { $0.done })
    }

    func testCastBlockedWhileStunnedAndSilencedAndPracticeHasNoCooldowns() {
        var w = SkillWorld()
        let k = addOria(&w)
        CombatSystem.addStatus(&w.s, targetIndex: k, StatusEffect(kind: .stun, duration: 0.5))
        for slot in SkillSlot.actives { XCTAssertFalse(w.cast(k, slot, .none), "\(slot)") }
        w.run(seconds: 0.6)
        CombatSystem.addStatus(&w.s, targetIndex: k, StatusEffect(kind: .silence, duration: 0.5))
        for slot in SkillSlot.actives { XCTAssertFalse(w.cast(k, slot, .none), "\(slot)") }
        XCTAssertTrue(w.damageEvents.isEmpty)

        var p = SkillWorld(noCooldowns: true)
        let pk = addOria(&p)
        let e = p.addDummyEnemy(at: skillArena + Vec2(400, 0))
        for slot in SkillSlot.actives {
            XCTAssertTrue(p.cast(pk, slot, .direction(Self.east)), "\(slot)")
            XCTAssertEqual(p.s.units[pk].hero!.cooldown(slot), 0, "練習場は CD なし")
        }
        XCTAssertEqual(p.s.units[pk].resource, p.s.units[pk].stats.maxResource, accuracy: 1e-9, "コストも無し")
        p.run(seconds: 2)
        XCTAssertGreaterThan(p.damage(to: e), 0)
        // 練習場では氷の誇りも再発動待ちにならない
        let e2 = p.addDummyEnemy(at: skillArena + Vec2(0, 400), hero: "H004")
        fatal(&p, pk, from: e2)
        XCTAssertEqual(p.kit(pk).oriaSaves, 1)
        XCTAssertEqual(p.kit(pk).oriaPrideCooldown, 0)
        p.run(seconds: 2)
        fatal(&p, pk, from: e2)
        XCTAssertEqual(p.kit(pk).oriaSaves, 2)
        XCTAssertTrue(p.s.units[pk].isAlive)
    }

    /// 練習場（CD なし）で凍結エリアを重ねても、凍らせるのは「今できたエリア」の中の敵だけ（先にできたエリアの残りの当たりでは凍らない）。
    func testOverlappingFrozenAreasInPracticeOnlyFreezeOnTheirOwnFormation() {
        var p = SkillWorld(noCooldowns: true)
        let pk = addOria(&p)
        let e = p.addDummyEnemy(at: skillArena + Vec2(Self.areaCenter, 0))
        // 凍結エリアは撃ってから 9 tick（0.3 秒）でできて、以降 15 tick（0.5 秒）ごとに当たる（9 / 24 / 39 / 54 tick）
        XCTAssertTrue(p.cast(pk, .skill2, .direction(Self.east)))
        p.tick(12)
        XCTAssertEqual(freezeNotices(p, e), 1)
        p.tick(33)   // 45 tick: 1 つ目の凍結（30 tick）は解けた
        XCTAssertNil(status(p, e, .stun))
        // 北へ撃った 2 つ目のエリアはこの敵を含まない。1 つ目の 4 回目の当たり（54 tick）と同じ tick にできても凍らせない
        XCTAssertTrue(p.cast(pk, .skill2, .direction(Vec2(0, 1))))
        p.tick(30)
        XCTAssertGreaterThanOrEqual(damageEvents(p, to: e, .skill(.skill2)).count, 1 + T.s2PatchTicks)
        XCTAssertEqual(freezeNotices(p, e), 1, "先のエリアの 2 回目以降・別のエリアの発動では凍らない")
        // 東へもう一度撃てば、新しいエリアができた瞬間に凍る
        XCTAssertTrue(p.cast(pk, .skill2, .direction(Self.east)))
        p.tick(12)
        XCTAssertEqual(freezeNotices(p, e), 2)
    }

    func testStunAfterCastDoesNotCancelTheFallingIceAndFrostPatch() {
        var w = SkillWorld()
        let k = addOria(&w)
        // 隕石の中心から雹の輪（0.9 倍）の位置 = k = 0 の雹が降る場所に立つ
        let center = skillArena + Vec2(450, 0)
        let e = w.addDummyEnemy(at: center + Vec2(T.s1Radius * T.hailRingInner, 0))
        XCTAssertTrue(w.cast(k, .skill1, .point(center)))
        XCTAssertTrue(w.cast(k, .skill2, .direction(Self.east)))
        XCTAssertTrue(w.cast(k, .ultimate, .direction(Self.east)))
        w.tick(2)
        CombatSystem.addStatus(&w.s, targetIndex: k, StatusEffect(kind: .stun, duration: 1.5))
        w.run(seconds: 2.5)
        let s1 = damageEvents(w, to: e, .skill(.skill1))
        XCTAssertEqual(s1.count, 2, "撃った隕石と雹はスタンでは消えない（隕石 + 立っている場所に降る雹 1 発）")
        XCTAssertFalse(damageEvents(w, to: e, .skill(.skill2)).isEmpty)
        XCTAssertFalse(damageEvents(w, to: e, .skill(.ultimate)).isEmpty)
    }

    func testDeathAfterCastLetsTheFrozenAreaAndGlacierWorkButResetsTheKit() {
        var w = SkillWorld()
        let k = addOria(&w)
        let e = w.addDummyEnemy(at: skillArena + Vec2(450, 0))
        XCTAssertTrue(w.cast(k, .skill2, .direction(Self.east)))
        XCTAssertTrue(w.cast(k, .ultimate, .direction(Self.east)))
        w.tick(2)
        let areaFreeze = w.kit(k).oriaAreaFreeze
        XCTAssertEqual(areaFreeze, 1.0, accuracy: 1e-12)
        w.s.units[k].hero!.kit!.oriaPrideCooldown = 40   // 氷の誇りは待機中
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(e), targetIndex: k, amount: 1e9, type: .trueDamage, source: .spell)
        DeathSystem.process(&w.s, w.ctx)
        XCTAssertTrue(w.s.units[k].hero!.isDead)
        XCTAssertEqual(w.kit(k).oriaSaves, 0)
        XCTAssertEqual(w.kit(k).oriaPrideCooldown, 40, "再発動までの残りは残る")
        XCTAssertEqual(w.kit(k).oriaAreaFreeze, areaFreeze, "遅れて働く凍結エリアの凍結秒は残る")
        w.run(seconds: 0.3)   // 撃ってから約 0.37 秒: 凍結エリアができている
        XCTAssertFalse(damageEvents(w, to: e, .skill(.skill2)).isEmpty)
        XCTAssertNotNil(status(w, e, .stun, tag: T.freezeTag), "術者が倒れても凍結エリアは凍らせる")
        XCTAssertEqual(freezeNotices(w, e), 1)
        w.run(seconds: 1.0)
        // 撃った後の氷は術者が倒れても残る（氷河の砕けも）
        XCTAssertFalse(damageEvents(w, to: e, .skill(.ultimate)).isEmpty)
        XCTAssertNotNil(status(w, e, .stun, tag: T.freezeTag), "氷河の凍結")
        XCTAssertFalse(SkillSystem.canCast(w.s, w.ctx, heroIndex: k, slot: .skill1))
        XCTAssertFalse(w.cast(k, .skill1, .direction(Self.east)), "死亡中は撃てない")
    }

    func testDeathDuringSelfFreezeCannotHappenBecauseOfInvulnerability() {
        var w = SkillWorld()
        let k = addOria(&w)
        let e = w.addDummyEnemy(at: skillArena + Vec2(400, 0))
        fatal(&w, k, from: e)
        CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(e), targetIndex: k, amount: 1e9, type: .trueDamage, source: .fountain)
        XCTAssertTrue(w.s.units[k].isAlive)
        w.run(seconds: 1.0)
        XCTAssertTrue(w.s.units[k].isAlive)
    }

    func testManaCostAndCooldownFollowTheOfficialCostAndKitCooldown() {
        var w = SkillWorld()
        let k = addOria(&w)
        // 公式のマナ消費（Lv1: スキル1 60 / スキル2 75 / アルティメット 140）。マスターデータの値（60 / 72 / 120）ではない
        for (slot, mp) in [(SkillSlot.skill1, 60.0), (.skill2, 75), (.ultimate, 140)] {
            let n = w.numbers(k, slot)
            let before = w.s.units[k].resource
            XCTAssertTrue(w.cast(k, slot, .direction(Self.east)))
            XCTAssertEqual(before - w.s.units[k].resource, mp, accuracy: 1e-9, "\(slot)")
            XCTAssertEqual(SkillSystem.cost(for: skill(slot), hero: def, rank: 1), mp)
            XCTAssertEqual(w.s.units[k].hero!.cooldown(slot), n.cooldown, accuracy: 1e-9)
            XCTAssertFalse(w.cast(k, slot, .direction(Self.east)), "CD 中")
        }
        // 最大の段（スキル1・2 = Lv6、アルティメット = Lv3）の消費と CD も公式の表
        var v = SkillWorld()
        let k2 = addOria(&v, ranks: [6, 6, 3])
        for (slot, mp, cd) in [(SkillSlot.skill1, 85.0, 4.0), (.skill2, 100, 8.0), (.ultimate, 180, 40)] {
            let before = v.s.units[k2].resource
            XCTAssertTrue(v.cast(k2, slot, .direction(Self.east)))
            XCTAssertEqual(before - v.s.units[k2].resource, mp, accuracy: 1e-9, "\(slot)")
            XCTAssertEqual(v.s.units[k2].hero!.cooldown(slot), cd, accuracy: 1e-9, "\(slot)")
        }
    }

    // MARK: - ボット

    /// ボットのスキル2 は相手が凍結エリアに入る距離（術者から 540 ± 190、遠い側は 30 の余裕）のときだけ撃つ。
    func testBotCastsFrostyBreezeOnlyWhenTheTargetIsInTheFrozenAreaRange() {
        let kit = Kit_H031()
        let t2 = SkillCatalog.targeting(for: skill(.skill2), hero: def)
        for (dx, expectCast) in [(200.0, false), (340, false), (360, true), (540, true), (690, true), (720, false)] {
            var w = SkillWorld()
            let k = addOria(&w)
            let e = w.addDummyEnemy(at: skillArena + Vec2(dx, 0))
            let d = kit.botCast(w.s, w.ctx, bot: k, slot: .skill2, targeting: t2, target: e, fighting: true)
            switch d {
            case .useDefault: XCTAssertTrue(expectCast, "距離 \(dx): 撃たないはず")
            case .skip: XCTAssertFalse(expectCast, "距離 \(dx): 撃つはず")
            default: XCTFail("距離 \(dx): \(d)")
            }
        }
    }

    // MARK: - 決定性

    private func script(_ w: inout SkillWorld, k: Int, step: Int) {
        switch step {
        case 0: w.cast(k, .skill1, .point(skillArena + Vec2(500, 0)))
        case 1: w.cast(k, .skill2, .direction(Self.east))
        case 2: w.cast(k, .ultimate, .direction(Self.east))
        case 3: w.s.units[k].attackTargetID = w.s.units.first { $0.team == .red && $0.kind == .hero }?.id
        case 5:
            // 氷の誇りを一度働かせる
            if let e = w.s.units.firstIndex(where: { $0.team == .red && $0.kind == .hero }) {
                CombatSystem.applyDamage(&w.s, w.ctx, sourceID: w.id(e), targetIndex: k, amount: 1e9, type: .trueDamage,
                                         source: .spell)
            }
        default: break
        }
    }

    private func makeScriptWorld() -> (SkillWorld, Int) {
        var w = SkillWorld()
        let k = addOria(&w, ranks: [2, 2, 2])
        w.addDummyEnemy(at: skillArena + Vec2(500, 0))
        w.addDummyEnemy(at: skillArena + Vec2(520, 150), hero: "H004")
        w.addMinion(team: .red, at: skillArena + Vec2(700, 40))
        return (w, k)
    }

    private func runScript(_ w: inout SkillWorld, k: Int, from: Int, to: Int) {
        for step in from..<to {
            script(&w, k: k, step: step)
            w.run(seconds: 0.45)
        }
    }

    func testScriptedRunIsDeterministic() {
        var (a, ka) = makeScriptWorld()
        var (b, kb) = makeScriptWorld()
        runScript(&a, k: ka, from: 0, to: 12)
        runScript(&b, k: kb, from: 0, to: 12)
        XCTAssertEqual(a.s.stateHash(), b.s.stateHash())
        XCTAssertEqual(a.s.units, b.s.units)
        XCTAssertEqual(a.log, b.log)
        XCTAssertEqual(a.kit(ka).oriaSaves, 1, "台本が氷の誇りまで通っている")
        for slot in SkillSlot.actives {
            XCTAssertFalse(a.damageEvents.filter { $0.source == .skill(slot) }.isEmpty, "\(slot)")
        }
    }

    func testJSONRoundTripMidUltimateAndMidFreezeResumesIdentically() throws {
        var (a, ka) = makeScriptWorld()
        runScript(&a, k: ka, from: 0, to: 12)

        var (b, kb) = makeScriptWorld()
        runScript(&b, k: kb, from: 0, to: 3)
        // 途中（霜の道は飛翔中・氷河は育成中・凍結エリアも生きている）: 奥義を撃った直後
        script(&b, k: kb, step: 2)
        b.tick(4)
        XCTAssertTrue(b.s.zones.contains { !$0.done && !$0.triggered }, "氷河の予告中にシリアライズする")
        let data = try JSONEncoder().encode(b.s)
        var resumed = b
        resumed.s = try JSONDecoder().decode(SimState.self, from: data)
        XCTAssertEqual(resumed.s.units, b.s.units)
        XCTAssertEqual(resumed.s.zones, b.s.zones)
        XCTAssertEqual(resumed.s.stateHash(), b.s.stateHash())
        b.run(seconds: 0.45 - 4 * Balance.dt)
        resumed.run(seconds: 0.45 - 4 * Balance.dt)
        runScript(&b, k: kb, from: 3, to: 12)
        runScript(&resumed, k: kb, from: 3, to: 12)
        XCTAssertEqual(resumed.s.stateHash(), b.s.stateHash())
        XCTAssertEqual(resumed.s.units, b.s.units)
        XCTAssertEqual(resumed.s.zones, b.s.zones)
        XCTAssertEqual(resumed.s.projectiles, b.s.projectiles)
        XCTAssertEqual(resumed.log.count, b.log.count)
        _ = a.s

        // 凍結エリアの発動の直前でシリアライズしても、発動の瞬間の凍結は同じ
        var f = SkillWorld()
        let kf = addOria(&f)
        let ef = f.addDummyEnemy(at: skillArena + Vec2(500, 0))
        XCTAssertTrue(f.cast(kf, .skill2, .direction(Self.east)))
        f.tick(8)
        var g = f
        g.s = try JSONDecoder().decode(SimState.self, from: try JSONEncoder().encode(f.s))
        f.run(seconds: 2.5)
        g.run(seconds: 2.5)
        XCTAssertEqual(g.s.stateHash(), f.s.stateHash())
        XCTAssertEqual(freezeNotices(f, ef), 1)
        XCTAssertEqual(freezeNotices(g, ef), 1)

        // 凍結中（回復の tick が残っている）でも同じ
        var c = SkillWorld()
        let kc = addOria(&c)
        let ec = c.addDummyEnemy(at: skillArena + Vec2(400, 0))
        fatal(&c, kc, from: ec)
        c.tick(10)
        XCTAssertGreaterThan(c.kit(kc).oriaHealTicks, 0)
        var d = c
        d.s = try JSONDecoder().decode(SimState.self, from: try JSONEncoder().encode(c.s))
        XCTAssertEqual(d.s.stateHash(), c.s.stateHash())
        c.run(seconds: 2)
        d.run(seconds: 2)
        XCTAssertEqual(d.s.stateHash(), c.s.stateHash())
        XCTAssertEqual(d.s.units[kc].hp, c.s.units[kc].hp)
    }

    func testStateHashSeesPrideAndFreezeState() {
        var (a, ka) = makeScriptWorld()
        var (b, kb) = makeScriptWorld()
        XCTAssertEqual(a.s.stateHash(), b.s.stateHash())
        b.s.units[kb].hero!.kit!.oriaPrideCooldown = 10
        XCTAssertNotEqual(a.s.stateHash(), b.s.stateHash())
        b.s.units[kb].hero!.kit!.oriaPrideCooldown = 0
        a.s.units[ka].hero!.kit!.oriaAreaFreeze = 1.12
        XCTAssertNotEqual(a.s.stateHash(), b.s.stateHash())
    }

    // MARK: - ボットの煙テスト

    /// 標準マップのボット戦で、青のアルカニスト枠をオーリアに置き換える。
    private func botConfig(seed: UInt64) -> MatchConfig {
        var cfg = MatchFactory.botMatch(seed: seed)
        let pos = MatchFactory.defaultPosition(for: .arcanist)
        for j in cfg.players.indices where cfg.players[j].heroID == "H031" { cfg.players[j].heroID = "H004" }
        if let idx = cfg.players.firstIndex(where: { $0.team == .blue && $0.position == pos }) {
            cfg.players[idx].heroID = "H031"
            cfg.players[idx].displayName = "Oria_AI"
        }
        return cfg
    }

    func testBotPlaysOriaForThreeMinutesWithAllSlotsAndSaneState() throws {
        var casts: [SkillSlot: Int] = [:]
        var skillDamage: [SkillSlot: Double] = [:]
        var found = false
        var pride = 0
        for seed in [UInt64(11), 12, 13, 14, 15] {
            let sim = Simulation(config: botConfig(seed: seed))
            guard let oi = sim.state.heroIndices.first(where: { sim.state.units[$0].hero?.heroID == "H031" }) else {
                continue
            }
            found = true
            let oriaID = sim.state.units[oi].id
            XCTAssertNotNil(sim.state.units[oi].hero?.kit, "ボットのオーリアにも KitState が付く")
            casts = [:]
            skillDamage = [:]
            pride = 0
            while !sim.isEnded && sim.state.time < 240 {
                // 奥義は「倒せる / 2 体以上を巻き込む」ときだけ撃つ AI で、試合の流れ次第では出ない。
                // 120 秒以降は 20 秒おきに自動照準で S2・奥義を撃たせ、霜風・氷河の状態遷移も通す（S1 は AI の判断のまま）
                var commands: [HeroCommand] = []
                if sim.state.time >= 120, sim.state.tick % 600 == 0 {
                    commands.append(HeroCommand(heroID: oriaID, command: .castSkill(slot: .ultimate, target: .none)))
                } else if sim.state.time >= 120, sim.state.tick % 600 == 300 {
                    commands.append(HeroCommand(heroID: oriaID, command: .castSkill(slot: .skill2, target: .none)))
                }
                for e in sim.step(commands: commands) {
                    switch e {
                    case .skillCast(let c) where c.casterID == oriaID:
                        casts[c.slot, default: 0] += 1
                    case .damage(let d) where d.sourceID == oriaID:
                        if case .skill(let slot) = d.source { skillDamage[slot, default: 0] += d.amount }
                    default:
                        break
                    }
                }
                guard let i = sim.state.index(of: oriaID) else { break }
                let u = sim.state.units[i]
                XCTAssertTrue(u.hp.isFinite && u.pos.x.isFinite && u.pos.y.isFinite && u.resource.isFinite)
                XCTAssertGreaterThanOrEqual(u.resource, 0)
                if let k = u.hero?.kit {
                    XCTAssertTrue(k.timers.allSatisfy { $0 >= 0 && $0.isFinite })
                    XCTAssertTrue(k.reals.allSatisfy { $0.isFinite })
                    XCTAssertTrue(k.windows.allSatisfy { !$0.isOpen }, "再使用の窓は使わない")
                    XCTAssertTrue(k.scheduled.isEmpty, "遅延タイマーは使わない")
                    XCTAssertNil(k.sweep)
                    pride = max(pride, k.oriaSaves)
                }
            }
            // 全スロットを撃ち、S1・S2 がダメージを出したシードで止める（下の判定はそのシードの値で見る）。
            // シード 11 は sim 16（H027 / H030 / H032 のボットがバトルプランの装備を買う）で S1 を 1 回だけ撃って外すので、次のシードへ進む。
            if casts[.skill1, default: 0] > 0, casts[.skill2, default: 0] > 0, casts[.ultimate, default: 0] > 0,
               skillDamage[.skill1, default: 0] > 0, skillDamage[.skill2, default: 0] > 0 { break }
        }
        XCTAssertTrue(found)
        XCTAssertGreaterThan(casts[.skill1, default: 0], 0, "S1: \(casts)")
        XCTAssertGreaterThan(casts[.skill2, default: 0], 0, "S2: \(casts)")
        XCTAssertGreaterThan(casts[.ultimate, default: 0], 0, "奥義: \(casts)")
        XCTAssertGreaterThan(skillDamage[.skill1, default: 0], 0)
        XCTAssertGreaterThan(skillDamage[.skill2, default: 0], 0)
        print("H031 bot smoke: casts \(casts) skillDamage \(skillDamage) pride \(pride)")
    }

    // MARK: - 1v1 の TTK（ロール代表との総当たり）

    func testDuelTimeToKillAgainstRoleRepresentativesStaysInBand() {
        var failures: [String] = []
        for level in SkillBalanceTests.levels {
            for foe in SkillBalanceTests.representatives {
                let r = SkillBalanceTests.duel("H031", foe, level: level)
                print(String(format: "H031 duel Lv%d vs %@: %.1f s winner=%@ hp=%.2f", level, foe, r.ttk, r.winnerIsA.map { $0 ? "H031" : foe } ?? "-", r.remainingHPRatio))
                if r.ttk < SkillBalanceTests.minTTK || r.ttk > SkillBalanceTests.maxTTK {
                    failures.append(String(format: "Lv%d H031 vs %@: %.2f s", level, foe, r.ttk))
                }
            }
        }
        XCTAssertTrue(failures.isEmpty, "\(failures)")
    }

    /// 診断: 全 34 ヒーローとの 1v1 の勝率（H031 と、汎用のアルカニスト H004/H010/H016/H022 を同じ場で比べる）。Release のみ。
    func testRoundRobinWinRateNextToGenericArcanists() throws {
        #if DEBUG
        throw XCTSkip("Release で実行する: swift test -c release --filter Kit_H031Tests/testRoundRobin")
        #else
        let ids = MasterData.shared.heroes.map(\.heroID)
        for level in SkillBalanceTests.levels {
            var line = "Lv\(level) win rate:"
            for hero in ["H031", "H004", "H010", "H016", "H022"] {
                var wins = 0.0, games = 0.0
                for foe in ids where foe != hero {
                    // 先手・後手の偏りを避けるため、双方向で戦わせる
                    let r1 = SkillBalanceTests.duel(hero, foe, level: level)
                    let r2 = SkillBalanceTests.duel(foe, hero, level: level)
                    wins += (r1.winnerIsA == true ? 1 : 0) + (r2.winnerIsA == false ? 1 : 0)
                    games += 2
                }
                line += String(format: " %@ %.1f%%", hero, wins / games * 100)
            }
            print(line)
        }
        #endif
    }
}
