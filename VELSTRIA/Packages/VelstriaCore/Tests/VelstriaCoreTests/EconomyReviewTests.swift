import XCTest
@testable import VelstriaCore

/// レビュー修正の回帰テスト: 事前計算表・推奨購入の完走・無限 Gold・マルチキル上限・キーフレームシーク・試合中の不変条件。
final class EconomyReviewTests: XCTestCase {

    // MARK: - 装備・ルーンの事前計算表

    func testItemTableMatchesMasterParsing() throws {
        let m = MasterData.shared
        let table = EconomyItemTable.table(for: m)
        XCTAssertTrue(table === EconomyItemTable.shared)
        for it in m.items { XCTAssertEqual(table.percent(item: it), it.passivePercent, it.itemID) }
        for r in m.runes { XCTAssertEqual(table.percent(rune: r), r.percent, r.runeID) }
        for cat in ItemCategory.allCases {
            // 素朴な並べ替え（毎回 % を解析）と同じ順
            let naive = m.items.filter { $0.category == cat && !$0.isConsumable }.sorted { a, b in
                if a.tier != b.tier { return a.tier > b.tier }
                let va = ItemSystem.itemValue(a), vb = ItemSystem.itemValue(b)
                if va != vb { return va > vb }
                return a.itemID < b.itemID
            }
            XCTAssertEqual(ItemSystem.rankedItems(category: cat, master: m).map(\.itemID), naive.map(\.itemID))
        }

        // 同梱以外のマスターでも同じ結果（その場で表を作る）
        let url = try XCTUnwrap(Bundle.module.url(forResource: "master_runtime", withExtension: "json"))
        let other = try MasterData(jsonData: Data(contentsOf: url))
        XCTAssertFalse(EconomyItemTable.table(for: other) === EconomyItemTable.shared)
        XCTAssertTrue(EconomyItemTable.table(for: other) === EconomyItemTable.table(for: other))
        for role in Role.allCases {
            XCTAssertEqual(ItemSystem.recommendedBuild(role: role, master: other),
                           ItemSystem.recommendedBuild(role: role, master: m))
        }
        var a = Stats(), b = Stats()
        a.attack = 100; b.attack = 100
        // 能力値・固有の能力値・適応攻撃・能力値で決まる固有効果（神秘・撃砕）を含む組み合わせ
        let items = ["EQ109", "EQ112", "EQ210", "EQ113", "EQ105", "EQ122"]
        ItemStats.apply(items: items, runes: ["RN06", "RN15", "RN24"], to: &a, master: m)
        ItemStats.apply(items: items, runes: ["RN06", "RN15", "RN24"], to: &b, master: other)
        XCTAssertEqual(a, b)
    }

    // MARK: - 推奨購入

    /// 全ロール × 狩猟印の有無 × ポジションで、推奨購入だけを繰り返せば失敗なく 6 完成品が揃う。
    func testRecommendedPurchasesCompleteBuildForEveryRole() {
        for role in Role.allCases {
            for spells in [["BS01", "BS03"], ["BS05", "BS01"]] {
                for position in [LanePosition.jungle, .mid] {
                    var f = EconomyFixture.standard()
                    let i = f.human
                    f.s.units[i].hero!.role = role
                    f.s.units[i].hero!.position = position
                    f.s.units[i].hero!.spells = spells
                    f.s.units[i].hero!.gold = Balance.startingGold
                    let label = "\(role) \(spells) \(position)"
                    let build = ItemSystem.recommendedBuild(for: f.hero(i), master: f.master)
                    XCTAssertEqual(build.count, 6, label)
                    XCTAssertEqual(Set(build).count, 6, label)

                    var steps = 0
                    while steps < 500, f.hero(i).items.sorted() != build.sorted() {
                        steps += 1
                        if let next = ItemSystem.nextRecommendedPurchase(f.hero(i), ctx: f.ctx) {
                            f.s.events.removeAll()
                            ItemSystem.buy(&f.s, f.ctx, heroIndex: i, itemID: next)
                            XCTAssertEqual(f.s.events.purchaseFailures, [], "\(label) \(next)")
                        } else {
                            // 買える物が無い → 収入を待つ
                            f.s.units[i].hero!.gold += 200
                        }
                        let h = f.hero(i)
                        XCTAssertLessThanOrEqual(h.items.count, Balance.itemSlots, label)
                        XCTAssertGreaterThanOrEqual(h.gold, 0, label)
                        let cats = h.items.compactMap { f.master.item($0)?.category }
                        XCTAssertLessThanOrEqual(cats.filter { $0 == .movement }.count, 1, label)
                        XCTAssertFalse(h.items.contains { f.master.item($0)?.isConsumable == true }, label)
                    }
                    XCTAssertEqual(f.hero(i).items.sorted(), build.sorted(), label)
                    XCTAssertNil(ItemSystem.nextRecommendedPurchase(f.hero(i), ctx: f.ctx), label)
                }
            }
        }
    }

    // MARK: - 練習場の無限 Gold

    func testInfiniteGoldStaysPinnedOnRewards() {
        let opts = PracticeOptions(infiniteGold: true, spawnMinions: false, spawnDummies: false)
        var f = EconomyFixture(config: MatchFactory.practiceMatch(humanHeroID: "H002", humanName: "P",
                                                                  options: opts, seed: 3))
        let i = f.human
        f.economyTick()
        XCTAssertEqual(f.hero(i).gold, Balance.Economy.practiceGold)
        let m = f.addMinion(.siege, team: .red, at: f.s.units[i].pos)
        let ev = f.kill(m, by: f.id(i))
        // 報酬を得ても所持金は固定値のまま（獲得記録と演出イベントは残る）
        XCTAssertEqual(f.hero(i).gold, Balance.Economy.practiceGold)
        let siege = Balance.Economy.minionGold(.siege, at: f.s.time)
        XCTAssertEqual(f.hero(i).score.goldEarned, siege)
        XCTAssertEqual(ev.goldGained(by: f.id(i)), siege)

        // 通常戦では加算される
        var g = EconomyFixture.standard()
        let j = g.human
        let gold = g.hero(j).gold
        g.kill(g.addMinion(.siege, team: .red, at: g.s.units[j].pos), by: g.id(j))
        XCTAssertEqual(g.hero(j).gold - gold, Balance.Economy.minionGold(.siege, at: g.s.time))
    }

    // MARK: - マルチキル上限

    func testMultiKillAnnouncementStopsAtPenta() {
        var f = EconomyFixture.standard()
        f.parkHeroesAtFountains()
        let a = f.heroes(.blue)[0], red = f.heroes(.red)
        for i in f.s.heroIndices { f.s.units[i].hero!.autoLevelSkills = false }
        var counts: [Int] = []
        var multi: [Int] = []
        for (n, v) in red.enumerated() {
            f.s.time = 300 + Double(n) * 2
            let ev = f.kill(v, by: f.id(a))
            multi += ev.heroKills.map(\.multiKill)
            counts += ev.announcements.compactMap { if case .multiKill(_, let c) = $0 { return c } else { return nil } }
        }
        // 全員が倒れた直後に 1 人が復活し、10 秒以内にもう一度倒される
        let back = red[0]
        f.s.units[back].isAlive = true
        f.s.units[back].hp = f.s.units[back].stats.maxHP
        f.s.units[back].hero!.respawnTimer = 0
        f.s.time += 2
        let ev = f.kill(back, by: f.id(a))
        multi += ev.heroKills.map(\.multiKill)
        counts += ev.announcements.compactMap { if case .multiKill(_, let c) = $0 { return c } else { return nil } }

        XCTAssertEqual(counts, [2, 3, 4, 5])
        XCTAssertEqual(multi, [1, 2, 3, 4, 5, 5])
        XCTAssertEqual(f.hero(a).score.largestMultiKill, 5)
        XCTAssertEqual(f.hero(a).killStreak, 6)
    }

    // MARK: - キーフレームシーク

    private func scripted(tick: Int, hero: EntityID) -> [HeroCommand] {
        var out: [HeroCommand] = []
        func add(_ c: PlayerCommand) { out.append(HeroCommand(heroID: hero, command: c, sequence: UInt32(tick))) }
        if tick == 10 { add(.moveTo(point: Vec2(3000, 3000))) }
        if tick == 400 { add(.buyItem(itemID: "EQ133")) }
        if tick >= 200 && tick % 60 == 0 { add(.attackNearest(priority: .minionsFirst)) }
        if tick == 700 { add(.recall) }
        return out
    }

    func testKeyframeSeekMatchesContinuousPlayback() {
        let cfg = MatchFactory.standardMatch(humanHeroID: "H001", humanName: "K", seed: 99)
        let sim = Simulation(config: cfg)
        let recorder = ReplayRecorder(config: cfg)
        sim.recorder = recorder
        let human = sim.state.humanHeroID!
        let checkpoints = [100, 350, 700, 800]
        var hashes: [Int: UInt64] = [:]
        while sim.state.tick < 800 {
            sim.step(commands: scripted(tick: sim.state.tick + 1, hero: human))
            if checkpoints.contains(sim.state.tick) { hashes[sim.state.tick] = sim.state.stateHash() }
        }
        let player = ReplayPlayer(data: recorder.finish(summary: nil), keyframeInterval: 300)
        XCTAssertEqual(ReplayPlayer(data: recorder.finish(summary: nil)).keyframeInterval,
                       ReplayPlayer.defaultKeyframeInterval)

        player.seek(toTick: 800)
        XCTAssertEqual(player.state.stateHash(), hashes[800])
        XCTAssertEqual(player.keyframeTicks, [300, 600])
        // 後退: tick 300 のキーフレームから再開
        player.seek(toTick: 350)
        XCTAssertEqual(player.currentTick, 350)
        XCTAssertEqual(player.state.stateHash(), hashes[350])
        // 前進: 保存済みの tick 600 へ跳んでから進む
        player.seek(toTick: 700)
        XCTAssertEqual(player.currentTick, 700)
        XCTAssertEqual(player.state.stateHash(), hashes[700])
        // キーフレームより前は先頭から
        player.seek(toTick: 100)
        XCTAssertEqual(player.state.stateHash(), hashes[100])
        // 再生し直しても保存済みキーフレームは重複しない
        while !player.isFinished { player.stepOnce() }
        XCTAssertEqual(player.state.stateHash(), hashes[800])
        XCTAssertEqual(player.keyframeTicks, [300, 600])
    }

    // MARK: - 報酬処理の堅牢性

    /// HeroData を持たない hero 種別のユニット（不正な状態）が止め・与ダメ記録に居てもクラッシュせず、報酬も与えない。
    func testHeroUnitWithoutHeroDataIsNeverCredited() {
        var f = EconomyFixture.standard()
        f.parkHeroesAtFountains()
        f.s.firstBloodTaken = true
        let v = f.heroes(.red)[0]
        let blue = f.heroes(.blue)
        var bogus = VelstriaCore.Unit(id: 0, kind: .hero, team: .blue, pos: Vec2(6000, 6000), radius: 55, stats: Stats())
        bogus.hero = nil
        let bogusID = f.s.addUnit(bogus)
        let b = blue[1]
        f.s.units[v].hero!.recentDamagers.append(DamageRecord(sourceID: bogusID, time: f.s.time - 1))
        f.addDamager(victim: v, source: b, secondsAgo: 3)
        let gb = f.hero(b).gold
        // 止めが不正ユニット → 10 秒以内に与ダメのある正規ヒーロー b に帰属
        let ev = f.kill(v, by: bogusID)
        XCTAssertEqual(ev.heroKills.first?.killerID, f.id(b))
        XCTAssertEqual(ev.heroKills.first?.assistIDs, [])
        XCTAssertEqual(f.hero(b).gold - gb, 300)

        // ミニオン・モンスター・タワーの止めでも報酬なし（チーム報酬は通常どおり）
        let m = f.addMinion(.melee, team: .red, at: Vec2(6000, 6000))
        f.kill(m, by: bogusID)
        let t = f.tower(team: .red, lane: .bot, tier: .outer)
        let golds = blue.map { f.hero($0).gold }
        f.kill(t, by: bogusID)
        for (n, i) in blue.enumerated() { XCTAssertEqual(f.hero(i).gold - golds[n], 120) }
        f.kill(f.addMonster(.campLarge, at: Vec2(6000, 6000)), by: bogusID)
    }

    // MARK: - 帰還の到着地点

    /// 帰還の到着地点は泉の中でチーム内の並び順に散らす（復活地点と同じ）。全員が 1 点に重ならない。
    func testRecallDestinationsAreSpreadInsideFountain() {
        var f = EconomyFixture.standard()
        let blue = f.heroes(.blue)
        for (n, i) in blue.enumerated() { f.place(i, at: Vec2(5000 + Double(n) * 100, 5000)) }
        for i in blue { RecallSystem.startRecall(&f.s, f.ctx, heroIndex: i) }
        for _ in 0..<Int((Balance.recallChannel / Balance.dt).rounded()) + 1 {
            f.s.tick += 1
            f.s.time = Double(f.s.tick) * Balance.dt
            RecallSystem.update(&f.s, f.ctx)
        }
        let spots = blue.map { f.s.units[$0].pos }
        for (n, i) in blue.enumerated() {
            XCTAssertNil(f.hero(i).channel)
            XCTAssertTrue(f.ctx.map.isInFountain(spots[n], team: .blue))
            XCTAssertEqual(spots[n], RespawnSystem.respawnPosition(f.s, f.ctx, heroIndex: i))
        }
        for a in spots.indices {
            for b in spots.indices where b > a {
                XCTAssertGreaterThan(spots[a].distance(to: spots[b]), 2 * Balance.heroRadius)
            }
        }
    }

    // MARK: - 試合中の不変条件

    /// AI 戦を回しながら、人間側は推奨購入を続ける。経済の不変条件が常に成り立つこと。
    /// （開始 300 Gold では最安の装備 305 にも届かないため、最初の購入まで 80 秒回す）
    func testEconomyInvariantsDuringBotMatch() {
        let cfg = MatchFactory.standardMatch(humanHeroID: "H003", humanName: "Inv", seed: 314)
        let sim = Simulation(config: cfg)
        let human = sim.state.humanHeroID!
        var failures: [String] = []
        var purchases = 0
        var seq: UInt32 = 0
        while sim.state.tick < 80 * 30 && !sim.isEnded {
            var cmds: [HeroCommand] = []
            if sim.state.tick % 30 == 0, let h = sim.state.unit(human)?.hero,
               let next = ItemSystem.nextRecommendedPurchase(h, ctx: sim.ctx) {
                seq += 1
                cmds.append(HeroCommand(heroID: human, command: .buyItem(itemID: next), sequence: seq))
            }
            for e in sim.step(commands: cmds) {
                if case .purchaseFailed(let id, let item, let reason) = e, id == human { failures.append("\(item) \(reason)") }
                if case .itemPurchased(let id, _) = e, id == human { purchases += 1 }
            }
            // XCTAssert を毎 tick 大量に呼ぶと遅いので、違反だけを集めて最後に確認する
            for i in sim.state.heroIndices {
                let h = sim.state.units[i].hero!
                let basicCap = min(Balance.basicSkillMaxRank, (h.level + 1) / 2)
                let ok = h.gold >= 0
                    && h.items.count <= Balance.itemSlots
                    && h.items.count == h.itemInvested.count
                    && (1...Balance.maxLevel).contains(h.level)
                    && h.skillPoints >= 0
                    && HeroGrowth.spentSkillPoints(h) + h.skillPoints == h.level
                    && h.rank(.ultimate) <= Balance.ultimateUnlockLevels.filter { h.level >= $0 }.count
                    && [SkillSlot.skill1, .skill2].allSatisfy { h.rank($0) <= basicCap }
                    && h.isDead == !sim.state.units[i].isAlive
                if !ok { failures.append("tick \(sim.state.tick) hero \(sim.state.units[i].id)") }
            }
        }
        XCTAssertEqual(failures, [])
        XCTAssertGreaterThanOrEqual(purchases, 1)
    }
}
