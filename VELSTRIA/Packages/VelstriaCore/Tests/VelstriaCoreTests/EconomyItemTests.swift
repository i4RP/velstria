import XCTest
@testable import VelstriaCore

/// 装備（Mobile Legends の図鑑をそのまま写した 92 個。tools/equipment_spec.mjs）:
/// データの整合・多段の合成・靴の制限・売却・ポーション・固有の能力値・適応攻撃・MP・ルーン・推奨購入（DESIGN §8）。
final class EconomyItemTests: XCTestCase {
    private let master = MasterData.shared

    /// 人間（H003、Mana の射手）の所持 Gold を決め、ルーンを外して能力値を計算し直す。
    private func setup(spells: [String]? = nil, gold: Double = 5000) -> EconomyFixture {
        var f = EconomyFixture.standard()
        let i = f.human
        f.s.units[i].hero!.gold = gold
        f.s.units[i].hero!.runes = []
        if let spells { f.s.units[i].hero!.spells = spells }
        StatCalculator.recompute(&f.s, i, f.ctx)
        f.s.events.removeAll()
        return f
    }

    private func buy(_ f: inout EconomyFixture, _ i: Int, _ id: String) -> [SimEvent] {
        f.s.events.removeAll()
        ItemSystem.buy(&f.s, f.ctx, heroIndex: i, itemID: id)
        return f.s.events
    }

    /// ItemStats に渡すヒーロー（試合の外で作る）。
    private func heroData(_ heroID: String, level: Int = 1) -> HeroData {
        let def = master.hero(heroID)!
        let slot = PlayerSlot(team: .blue, heroID: heroID, controller: .human, position: .mid, displayName: heroID)
        var u = UnitFactory.makeHero(def: def, slot: slot, pos: .zero)
        u.hero!.level = level
        return u.hero!
    }

    private func ids(_ hundreds: Int, _ count: Int) -> [String] {
        (1...count).map { "EQ\(hundreds)" + ($0 < 10 ? "0\($0)" : "\($0)") }
    }

    /// 合成の素材を基本素材まで展開する。
    private func leaves(_ id: String) -> [String] {
        let it = master.item(id)!
        return it.buildFrom.isEmpty ? [id] : it.buildFrom.flatMap(leaves)
    }

    // MARK: - データの整合

    func testRosterIsTheMLBBCatalog() {
        let ids = master.items.map(\.itemID)
        XCTAssertEqual(ids.count, 92)
        XCTAssertEqual(Set(ids).count, 92, "ID は重複しない")
        // 攻撃 EQ101–134、魔法 EQ201–225、防御 EQ301–325、移動 EQ401–408（EQ408 = スピードブーツ 250）
        XCTAssertEqual(Set(ids), Set(self.ids(1, 34) + self.ids(2, 25) + self.ids(3, 25) + self.ids(4, 8)))
        XCTAssertEqual(ids, ids.sorted(), "一覧は ID 順（図鑑の並び）")
        // ジャングル・ロームは装備ではなく靴の祝福（ItemCategory.utility は廃止）
        XCTAssertEqual(ItemCategory.allCases, [.attack, .magic, .defense, .movement, .jungle, .roam])
        let byCategory: [ItemCategory: Int] = [.attack: 1, .magic: 2, .defense: 3, .movement: 4]
        var tiers: [String: Int] = [:]
        for it in master.items {
            XCTAssertEqual(byCategory[it.category], Int(String(it.itemID.dropFirst(2).prefix(1))), "\(it.itemID) のタブ")
            XCTAssertTrue((1...3).contains(it.tier), it.itemID)
            XCTAssertFalse(it.alsoIn.contains(it.category), it.itemID)
            XCTAssertTrue(it.isListed(in: it.category))
            XCTAssertEqual(it.isBoots, it.category == .movement, it.itemID)
            XCTAssertGreaterThan(it.priceGold, 0, it.itemID)
            tiers["\(it.category.rawValue)\(it.tier)", default: 0] += 1
        }
        XCTAssertEqual(tiers, ["Attack3": 20, "Attack2": 7, "Attack1": 7, "Magic3": 14, "Magic2": 6, "Magic1": 5,
                               "Defense3": 13, "Defense2": 6, "Defense1": 6, "Movement2": 7, "Movement1": 1])
        // 図鑑の値の抜き取り（名前・価格・能力値）
        let despair = master.item("EQ106")!
        XCTAssertEqual(despair.priceGold, 3010)
        XCTAssertEqual(despair.attack, 160)
        XCTAssertEqual(despair.moveSpeedPct, 5)
        XCTAssertEqual(master.item("EQ309")?.hp, 1800)
        XCTAssertEqual(master.item("EQ210")?.abilityPower, 165)
        XCTAssertEqual(master.item(Balance.Gear.baseBootsID)?.priceGold, 250)
        XCTAssertEqual(master.item(Balance.Gear.baseBootsID)?.moveSpeed, 20)
        XCTAssertEqual(master.item("EQ113")?.alsoIn, [.magic])
        XCTAssertEqual(master.item("EQ114")?.alsoIn, [.magic, .defense])
    }

    func testRecipesUseExistingCheaperLowerTierComponents() {
        for it in master.items {
            if it.tier == 1 {
                XCTAssertTrue(it.buildFrom.isEmpty, "\(it.itemID): 基本素材は合成しない")
            } else {
                XCTAssertFalse(it.buildFrom.isEmpty, "\(it.itemID): Tier \(it.tier) は素材から作る")
            }
            var sum = 0.0
            for c in it.buildFrom {
                guard let comp = master.item(c) else {
                    XCTFail("\(it.itemID): 素材 \(c) がマスターに無い")
                    continue
                }
                XCTAssertLessThanOrEqual(comp.priceGold, it.priceGold, "\(it.itemID) ← \(c)")
                XCTAssertLessThan(comp.tier, it.tier, "\(it.itemID) ← \(c)")
                XCTAssertFalse(comp.isConsumable, "\(it.itemID) ← \(c)")
                sum += comp.priceGold
            }
            // 素材の合計（基本素材まで展開しても）が完成品の価格を超えない＝合成で Gold が増えない
            XCTAssertLessThanOrEqual(sum, it.priceGold, it.itemID)
            XCTAssertLessThanOrEqual(leaves(it.itemID).reduce(0) { $0 + master.item($1)!.priceGold }, it.priceGold, it.itemID)
            XCTAssertLessThanOrEqual(leaves(it.itemID).count, Balance.itemSlots, "\(it.itemID): 基本素材を全部持てる")
        }
        // 靴: スピードブーツだけが Tier 1、ほかはすべてスピードブーツから作る
        let boots = master.items.filter(\.isBoots)
        XCTAssertEqual(boots.filter { $0.tier == 1 }.map(\.itemID), [Balance.Gear.baseBootsID])
        for b in boots where b.tier == 2 {
            XCTAssertEqual(b.buildFrom.first, Balance.Gear.baseBootsID, b.itemID)
            XCTAssertEqual(b.buildFrom.filter { self.master.item($0)!.isBoots }.count, 1, b.itemID)
            XCTAssertEqual(b.priceGold, 720, b.itemID)
        }
    }

    func testConsumablesArePotions() {
        let potions = master.items.filter(\.isConsumable)
        XCTAssertEqual(potions.map(\.itemID), ["EQ134", "EQ225", "EQ325"])
        for p in potions {
            XCTAssertEqual(p.consumableSec, 120, p.itemID)
            XCTAssertEqual(p.priceGold, 1500, p.itemID)
            XCTAssertEqual(p.tier, 1, p.itemID)
            XCTAssertTrue(p.buildFrom.isEmpty, p.itemID)
            XCTAssertTrue(p.effects.isEmpty, p.itemID)
            XCTAssertFalse(master.items.contains { $0.buildFrom.contains(p.itemID) }, "\(p.itemID) は素材にならない")
        }
        // 評価順の一覧・推奨ビルドにポーションは出ない
        for cat in ItemCategory.allCases {
            XCTAssertFalse(ItemSystem.rankedItems(category: cat, master: master).contains(where: \.isConsumable), "\(cat)")
        }
    }

    func testEveryEffectIsKnownAndEveryKindIsUsed() {
        // 実装が読む係数の数（ItemEffects の `where v.count >= N`）。足りないと効果が黙って働かない
        let minCount: [ItemEffectKind: Int] = [
            .maleficEnergy: 3, .supremeWarrior: 3, .lifebane: 2, .punish: 1, .dragonScale: 3, .lifeline: 6,
            .huntChase: 4, .despair: 3, .ambush: 5, .typhoon: 6, .divineJustice: 5, .doom: 1, .frenzy: 2,
            .breaker: 2, .frozen: 2, .timestream: 1, .lethality: 5, .fightingSpirit: 6, .windChant: 3,
            .goldenStaff: 4, .corrosive: 5, .impulse: 3, .engulf: 2, .devour: 3, .crossbow: 1,
            .butterfly: 3, .oasisBlessing: 5, .geniusShred: 4, .resonate: 3, .guardWings: 6, .crisis: 6,
            .scorch: 2, .iceBound: 3, .recharge: 5, .mystery: 2, .spellbreaker: 2, .destiny: 5, .gift: 4,
            .affliction: 2, .manaSpring: 1, .magicMastery: 1, .judgement: 3,
            .holyBlessing: 5, .chastise: 2, .redemption: 4, .bruteForce: 6, .immortal: 6, .fortress: 3,
            .lifebaneAura: 2, .valkyrie: 3, .deter: 3, .recovery: 2, .defender: 3, .burningSoul: 4, .curse: 3,
            .thunderbolt: 8, .demonize: 5, .defiance: 2, .bladedArmor: 4,
            .mysticism: 1, .valor: 3,
        ]
        XCTAssertEqual(Set(minCount.keys), Set(ItemEffectKind.allCases))
        var used = Set<ItemEffectKind>()
        for it in master.items {
            XCTAssertEqual(Set(it.effects.map(\.id)).count, it.effects.count, "\(it.itemID): 同じ効果を 2 つ持たない")
            XCTAssertEqual(it.effectID, it.effects.first?.id ?? "", it.itemID)
            for e in it.effects {
                guard let k = ItemEffectKind(rawValue: e.id) else {
                    XCTFail("\(it.itemID): 未実装の効果 \(e.id)")
                    continue
                }
                used.insert(k)
                XCTAssertGreaterThanOrEqual(e.v.count, minCount[k] ?? 0, "\(it.itemID) \(k) の係数")
            }
        }
        XCTAssertEqual(used, Set(ItemEffectKind.allCases), "すべての効果がどれかの装備に付いている")
        XCTAssertEqual(ItemEffectKind.allCases.filter(\.isActive), [.frozen, .windChant])
        XCTAssertEqual(master.items.filter { $0.effects.contains { ItemEffectKind(rawValue: $0.id)?.isActive == true } }
            .map(\.itemID), ["EQ113", "EQ117"])
        // 固有の能力値は ItemStats が足せるキーだけ（知らないキーは黙って捨てられる）
        let uniqueKeys: Set<String> = ["armor_pen_flat", "magic_pen_flat", "armor_pen_pct", "magic_pen_pct", "crit_damage_pct",
                                       "lifesteal_pct", "spell_vamp_pct", "heal_shield_power_pct", "crit_damage_reduction_pct",
                                       "move_speed", "attack_speed_pct", "crit_chance_pct", "hp", "cooldown_reduction_pct"]
        for it in master.items {
            for k in it.uniqueStats.keys { XCTAssertTrue(uniqueKeys.contains(k), "\(it.itemID): \(k)") }
        }
    }

    // MARK: - 合成（多段）

    func testOwnedComponentsDiscountExactlyTheirPriceWithoutFloor() throws {
        let f = setup(gold: 100_000)
        var h = f.hero(f.human)
        for it in master.items where !it.buildFrom.isEmpty {
            // 直接の素材を全部持つ → 価格 − 素材の合計（下限なし）
            h.items = it.buildFrom
            h.itemInvested = it.buildFrom.map { self.master.item($0)!.priceGold }
            var q = ItemSystem.quote(h, itemID: it.itemID, ctx: f.ctx)
            XCTAssertNil(q.failure, it.itemID)
            XCTAssertEqual(q.cost, it.priceGold - h.itemInvested.reduce(0, +), accuracy: 1e-9, it.itemID)
            XCTAssertEqual(q.consumedSlots, Array(h.items.indices), it.itemID)
            // 基本素材だけを持つ → 途中の素材を飛ばして割り引く
            let base = leaves(it.itemID)
            h.items = base
            h.itemInvested = base.map { self.master.item($0)!.priceGold }
            q = ItemSystem.quote(h, itemID: it.itemID, ctx: f.ctx)
            XCTAssertNil(q.failure, it.itemID)
            XCTAssertEqual(q.cost, it.priceGold - h.itemInvested.reduce(0, +), accuracy: 1e-9, it.itemID)
            XCTAssertEqual(q.consumedSlots, Array(h.items.indices), it.itemID)
        }
        XCTAssertEqual(Balance.minCombineCostRatio, 0)
    }

    func testDaggerDiscountsHunterStrikeThroughFuryHammer() {
        var f = setup(gold: 5000)
        let i = f.human
        // ハンターストライク 2010 = レイシハンマー（830 = ダガー + 580）+ ハンティングボウ 450 + ダガー 250
        XCTAssertEqual(ItemSystem.effectiveCost(f.hero(i), itemID: "EQ105", ctx: f.ctx), 2010)
        _ = buy(&f, i, "EQ133")
        // レイシハンマーは持っていないが、その素材のダガーを持っている
        XCTAssertEqual(ItemSystem.effectiveCost(f.hero(i), itemID: "EQ105", ctx: f.ctx), 2010 - 250)
        XCTAssertEqual(ItemSystem.quote(f.hero(i), itemID: "EQ105", ctx: f.ctx).consumedSlots, [0])
        _ = buy(&f, i, "EQ133")
        XCTAssertEqual(ItemSystem.effectiveCost(f.hero(i), itemID: "EQ105", ctx: f.ctx), 2010 - 500)
        // ダガー 2 本からレイシハンマーを作ると 1 本は残る
        XCTAssertEqual(ItemSystem.effectiveCost(f.hero(i), itemID: "EQ122", ctx: f.ctx), 830 - 250)
        _ = buy(&f, i, "EQ122")
        XCTAssertEqual(f.hero(i).items, ["EQ133", "EQ122"])
        XCTAssertEqual(f.hero(i).itemInvested, [250, 830])
        _ = buy(&f, i, "EQ129")
        XCTAssertEqual(ItemSystem.effectiveCost(f.hero(i), itemID: "EQ105", ctx: f.ctx), 2010 - 830 - 450 - 250)
        let ev = buy(&f, i, "EQ105")
        XCTAssertTrue(ev.contains(.itemPurchased(heroID: f.id(i), itemID: "EQ105")))
        XCTAssertEqual(f.hero(i).items, ["EQ105"])
        // 投資額は素材の分を引き継ぐ（＝定価）
        XCTAssertEqual(f.hero(i).itemInvested, [2010])
        XCTAssertEqual(f.hero(i).gold, 5000 - 2010)
        // 能力値は完成品だけ（攻撃 80・CD 短縮 10%・固有の物理貫通 15）
        let def = f.master.hero(f.hero(i).heroID)!
        let base = HeroGrowth.baseStats(def: def, level: f.hero(i).level)
        XCTAssertEqual(f.s.units[i].stats.attack, base.attack + 80, accuracy: 1e-6)
        XCTAssertEqual(f.s.units[i].stats.cooldownReduction, base.cooldownReduction + 0.10, accuracy: 1e-9)
        XCTAssertEqual(f.s.units[i].stats.armorPenFlat, 15, accuracy: 1e-9)
    }

    func testDuplicateComponentsMatchedOncePerOwnedCopy() {
        var f = setup(gold: 10_000)
        let i = f.human
        // ディスペアブレイド 3010 = レギオンソード 910 × 2
        _ = buy(&f, i, "EQ125")
        XCTAssertEqual(ItemSystem.effectiveCost(f.hero(i), itemID: "EQ106", ctx: f.ctx), 3010 - 910)
        _ = buy(&f, i, "EQ125")
        XCTAssertEqual(ItemSystem.effectiveCost(f.hero(i), itemID: "EQ106", ctx: f.ctx), 3010 - 1820)
        _ = buy(&f, i, "EQ133")
        _ = buy(&f, i, "EQ106")
        XCTAssertEqual(f.hero(i).items, ["EQ133", "EQ106"])
        XCTAssertEqual(f.hero(i).itemInvested, [250, 3010])
        XCTAssertEqual(f.hero(i).gold, 10_000 - 250 - 3010)
    }

    func testSlotLimitAppliesAfterConsumption() {
        var f = setup(gold: 20_000)
        let i = f.human
        for id in ["EQ133", "EQ133", "EQ129", "EQ131", "EQ132", "EQ324"] { _ = buy(&f, i, id) }
        XCTAssertEqual(f.hero(i).items.count, 6)
        XCTAssertEqual(buy(&f, i, "EQ221").purchaseFailures, ["slots_full"])
        XCTAssertEqual(f.hero(i).items.count, 6)
        // 素材 3 個を消費するハンターストライクは 6 枠でも買える
        let ok = buy(&f, i, "EQ105")
        XCTAssertTrue(ok.purchaseFailures.isEmpty)
        XCTAssertEqual(f.hero(i).items, ["EQ131", "EQ132", "EQ324", "EQ105"])
        // ポーションは枠を使わない
        for id in ["EQ221", "EQ221"] { _ = buy(&f, i, id) }
        XCTAssertEqual(f.hero(i).items.count, 6)
        XCTAssertTrue(buy(&f, i, "EQ134").purchaseFailures.isEmpty)
        XCTAssertEqual(f.hero(i).items.count, 6)
    }

    func testNotEnoughGoldAndUnknownItem() {
        var f = setup(gold: 100)
        let i = f.human
        XCTAssertEqual(buy(&f, i, "EQ133").purchaseFailures, ["not_enough_gold"])
        XCTAssertEqual(buy(&f, i, "EQ134").purchaseFailures, ["not_enough_gold"])
        XCTAssertEqual(buy(&f, i, "NOPE").purchaseFailures, ["unknown_item"])
        XCTAssertEqual(buy(&f, i, "EQ001").purchaseFailures, ["unknown_item"], "旧装備は無い")
        XCTAssertEqual(buy(&f, i, "EQJ01").purchaseFailures, ["unknown_item"], "旧ジャングル靴は無い")
        XCTAssertEqual(f.hero(i).gold, 100)
        XCTAssertTrue(f.hero(i).items.isEmpty)
        XCTAssertNil(f.hero(i).itemRuntime.potionID)
    }

    func testOnlyOnePairOfBoots() {
        var f = setup(gold: 5000)
        let i = f.human
        XCTAssertTrue(ItemSystem.isUniqueCategory(.movement))
        XCTAssertFalse(ItemSystem.isUniqueCategory(.attack))
        _ = buy(&f, i, Balance.Gear.baseBootsID)
        // スピードブーツを素材にした靴は買える（720 − 250）
        XCTAssertEqual(ItemSystem.effectiveCost(f.hero(i), itemID: "EQ406", ctx: f.ctx), 470)
        XCTAssertTrue(buy(&f, i, "EQ406").purchaseFailures.isEmpty)
        XCTAssertEqual(f.hero(i).items, ["EQ406"])
        XCTAssertEqual(f.hero(i).itemInvested, [720])
        // 2 足目は、素材の靴でも完成した靴でも不可（Gold・枠より先に判定）
        XCTAssertEqual(buy(&f, i, Balance.Gear.baseBootsID).purchaseFailures, ["unique_category"])
        XCTAssertEqual(buy(&f, i, "EQ403").purchaseFailures, ["unique_category"])
        f.s.units[i].hero!.gold = 0
        XCTAssertEqual(ItemSystem.quote(f.hero(i), itemID: "EQ403", ctx: f.ctx).failure, .uniqueCategory)
        f.s.units[i].hero!.gold = 5000
        XCTAssertEqual(f.hero(i).items, ["EQ406"])
        // 靴の素材（ナイフ）は靴ではない
        XCTAssertTrue(buy(&f, i, "EQ132").purchaseFailures.isEmpty)
        // 靴を売れば別の靴を買える
        ItemSystem.sell(&f.s, f.ctx, heroIndex: i, slotIndex: 0)
        XCTAssertTrue(buy(&f, i, "EQ403").purchaseFailures.isEmpty)
        XCTAssertEqual(f.hero(i).items, ["EQ403"], "ナイフはスイフトブーツの素材として消費される")
    }

    func testSellRefundsSixtyPercentOfInvested() {
        var f = setup(gold: 2000)
        let i = f.human
        _ = buy(&f, i, "EQ133")
        _ = buy(&f, i, "EQ122")
        XCTAssertEqual(f.hero(i).itemInvested, [830])
        let gold = f.hero(i).gold
        XCTAssertEqual(ItemSystem.sellValue(f.hero(i), slotIndex: 0, master: f.master), (830 * 0.6).rounded())
        XCTAssertEqual(ItemSystem.sellValue(invested: 830), 498)
        f.s.events.removeAll()
        ItemSystem.sell(&f.s, f.ctx, heroIndex: i, slotIndex: 0)
        XCTAssertEqual(f.hero(i).gold - gold, 498)
        XCTAssertTrue(f.hero(i).items.isEmpty)
        XCTAssertTrue(f.hero(i).itemInvested.isEmpty)
        XCTAssertTrue(f.s.events.contains(.itemSold(heroID: f.id(i), itemID: "EQ122", refund: 498)))
        // 範囲外は無視
        ItemSystem.sell(&f.s, f.ctx, heroIndex: i, slotIndex: 3)
        XCTAssertEqual(f.hero(i).gold - gold, 498)
        // 外から items だけ書き換えた時は定価を投資額とみなす
        f.s.units[i].hero!.items = ["EQ106"]
        f.s.units[i].hero!.itemInvested = []
        XCTAssertEqual(ItemSystem.sellValue(f.hero(i), slotIndex: 0, master: f.master), (3010 * 0.6).rounded())
    }

    func testPotionIsUsedOnPurchaseAndReplacedByAnother() {
        var f = setup(gold: 5000)
        let i = f.human
        let before = f.s.units[i].stats
        let ev = buy(&f, i, "EQ134")    // パワーポーション: 物理攻撃 +30、ライフスティール +15%（120 秒）
        XCTAssertTrue(ev.contains(.itemPurchased(heroID: f.id(i), itemID: "EQ134")))
        XCTAssertTrue(f.hero(i).items.isEmpty, "所持枠を使わない")
        XCTAssertEqual(f.hero(i).gold, 3500)
        XCTAssertEqual(f.hero(i).itemRuntime.potionID, "EQ134")
        XCTAssertEqual(f.hero(i).itemRuntime.potionUntil, f.s.time + 120, accuracy: 1e-9)
        XCTAssertEqual(f.s.units[i].stats.attack, before.attack + 30, accuracy: 1e-6)
        XCTAssertEqual(f.s.units[i].stats.lifesteal, before.lifesteal + 0.15, accuracy: 1e-9)
        // 効果は 1 つだけ: マジックポーションで置き換わる
        f.s.time += 10
        _ = buy(&f, i, "EQ225")
        XCTAssertEqual(f.hero(i).itemRuntime.potionID, "EQ225")
        XCTAssertEqual(f.hero(i).itemRuntime.potionUntil, f.s.time + 120, accuracy: 1e-9)
        XCTAssertEqual(f.s.units[i].stats.attack, before.attack, accuracy: 1e-6)
        XCTAssertEqual(f.s.units[i].stats.abilityPower, before.abilityPower + 30, accuracy: 1e-6)
        XCTAssertEqual(f.s.units[i].stats.cooldownReduction, before.cooldownReduction + 0.10, accuracy: 1e-9)
        XCTAssertEqual(f.hero(i).gold, 2000)
        // 売れない（所持品に無い）
        XCTAssertEqual(ItemSystem.sellValue(f.hero(i), slotIndex: 0, master: f.master), 0)
        // ロックポーション: 最大 HP +500、ダメージ軽減 +5%
        _ = buy(&f, i, "EQ325")
        XCTAssertEqual(f.s.units[i].stats.maxHP, before.maxHP + 500, accuracy: 1e-6)
        XCTAssertEqual(f.s.units[i].stats.damageReduction, before.damageReduction + 0.05, accuracy: 1e-9)
    }

    func testPracticeInfiniteGold() {
        let opts = PracticeOptions(infiniteGold: true, spawnMinions: false, spawnDummies: false)
        var f = EconomyFixture(config: MatchFactory.practiceMatch(humanHeroID: "H002", humanName: "P",
                                                                  options: opts, seed: 1))
        let i = f.human
        ItemSystem.buy(&f.s, f.ctx, heroIndex: i, itemID: "EQ106")
        XCTAssertEqual(f.hero(i).items, ["EQ106"])
        XCTAssertEqual(f.hero(i).gold, Balance.Economy.practiceGold)
        ItemSystem.buy(&f.s, f.ctx, heroIndex: i, itemID: "EQ134")
        XCTAssertEqual(f.hero(i).itemRuntime.potionID, "EQ134")
        XCTAssertEqual(f.hero(i).gold, Balance.Economy.practiceGold)
        f.s.units[i].hero!.gold = 10
        f.economyTick()
        XCTAssertEqual(f.hero(i).gold, Balance.Economy.practiceGold)
        // 獲得 Gold には数えない
        XCTAssertEqual(f.hero(i).score.goldEarned, 0)
    }

    // MARK: - 能力値

    func testItemFlatStatsStackPerCopy() {
        var st = Stats()
        st.resourceRegen = 10
        // ダガー ×2・バイタリティクリスタル・守り人の兜・デモンブーツ・賢者の書
        ItemStats.apply(items: ["EQ133", "EQ133", "EQ324", "EQ309", "EQ401", "EQ221"], runes: [], to: &st, master: master)
        XCTAssertEqual(st.attack, 30, accuracy: 1e-9)
        XCTAssertEqual(st.abilityPower, 8, accuracy: 1e-9)
        XCTAssertEqual(st.maxHP, 1 + 230 + 1800, accuracy: 1e-9)
        XCTAssertEqual(st.hpRegen, 20, accuracy: 1e-9)
        XCTAssertEqual(st.moveSpeed, 40, accuracy: 1e-9)
        XCTAssertEqual(st.resourceRegen, 20, accuracy: 1e-9)
        XCTAssertEqual(st.cooldownReduction, 0.05, accuracy: 1e-9)
        XCTAssertEqual(st.monsterGoldBonus, 0, accuracy: 1e-9, "ジャングルの収入は装備ではなく祝福")
    }

    func testUniqueStatsTakeTheMaxOncePerItem() {
        var st = Stats()
        // 固有の物理貫通: ハンターストライク 15・オーシャンエッジ 15・レイシハンマー 12 → 15
        ItemStats.apply(items: ["EQ105", "EQ107", "EQ122", "EQ105"], runes: [], to: &st, master: master)
        XCTAssertEqual(st.armorPenFlat, 15, accuracy: 1e-9)
        XCTAssertEqual(st.attack, 80 * 2 + 70 + 35, accuracy: 1e-9, "通常の能力値は個数分")
        // 撃砕（物理貫通 30%）は重ならない
        var pen = Stats()
        ItemStats.apply(items: ["EQ101", "EQ112"], runes: [], to: &pen, master: master)
        XCTAssertEqual(pen.armorPenPct, 0.30, accuracy: 1e-9)
        // 固有のクリティカルダメージ +30% は 2 本でも 1 回、クリティカル率は足し算で 100% が上限
        var crit = Stats()
        let baseMultiplier = crit.critMultiplier
        ItemStats.apply(items: ["EQ110", "EQ110", "EQ110", "EQ110", "EQ110"], runes: [], to: &crit, master: master)
        XCTAssertEqual(crit.critMultiplier, baseMultiplier + 0.30, accuracy: 1e-9)
        XCTAssertEqual(crit.critChance, 1, accuracy: 1e-9)
        // 固有と通常は別: ジーニアスワンド（固有の魔法貫通 10）+ アーケインブーツ（通常の魔法貫通 10）
        var magic = Stats()
        ItemStats.apply(items: ["EQ203", "EQ404", "EQ203"], runes: [], to: &magic, master: master)
        XCTAssertEqual(magic.magicPenFlat, 20, accuracy: 1e-9)
        // 混合吸血: 濃縮エネルギー（固有 20/20）+ ブラッドクロウ（固有 20）→ 20/20、ヴァンパイアハンマー（通常 8）は足す
        var vamp = Stats()
        ItemStats.apply(items: ["EQ209", "EQ111", "EQ130"], runes: [], to: &vamp, master: master)
        XCTAssertEqual(vamp.lifesteal, 0.20 + 0.08, accuracy: 1e-9)
        XCTAssertEqual(vamp.spellVamp, 0.20, accuracy: 1e-9)
        // ブレイドアーマーのクリティカルダメージ軽減も固有
        var blade = Stats()
        ItemStats.apply(items: ["EQ313", "EQ313"], runes: [], to: &blade, master: master)
        XCTAssertEqual(blade.critDamageReduction, 0.20, accuracy: 1e-9)
        XCTAssertEqual(blade.armor, 160, accuracy: 1e-9)
    }

    func testAdaptiveAttackFollowsItemStatsThenSkillDamageType() {
        let physical = heroData("H002")     // スキルは物理
        let magical = heroData("H004")      // スキルは魔法
        func apply(_ items: [String], _ hero: HeroData?) -> Stats {
            var st = Stats()
            ItemStats.apply(items: items, runes: [], to: &st, master: master, hero: hero)
            return st
        }
        // エキスパートグローブ（適応 30）だけ: 装備の攻撃力・魔力が同じ（0）なのでスキルの種類
        XCTAssertEqual(apply(["EQ128"], physical).attack, 30, accuracy: 1e-9)
        XCTAssertEqual(apply(["EQ128"], physical).abilityPower, 0, accuracy: 1e-9)
        XCTAssertEqual(apply(["EQ128"], magical).abilityPower, 30, accuracy: 1e-9)
        XCTAssertEqual(apply(["EQ128"], magical).attack, 0, accuracy: 1e-9)
        XCTAssertEqual(apply(["EQ128"], nil).attack, 30, accuracy: 1e-9, "ヒーローが分からなければ物理")
        // 装備の魔力が多ければ、物理のヒーローでも魔力へ
        let pm = apply(["EQ128", "EQ219"], physical)
        XCTAssertEqual(pm.abilityPower, 45 + 30, accuracy: 1e-9)
        XCTAssertEqual(pm.attack, 0, accuracy: 1e-9)
        // 装備の攻撃力が多ければ、魔法のヒーローでも攻撃力へ
        let mp = apply(["EQ128", "EQ125", "EQ219"], magical)
        XCTAssertEqual(mp.attack, 60 + 30, accuracy: 1e-9)
        XCTAssertEqual(mp.abilityPower, 45, accuracy: 1e-9)
        // ウィンタークラウン（適応 45）+ フリーティングタイム（適応 70）は合計を 1 か所へ
        XCTAssertEqual(apply(["EQ113", "EQ114"], magical).abilityPower, 115, accuracy: 1e-9)
        XCTAssertEqual(apply(["EQ113", "EQ114"], physical).attack, 115, accuracy: 1e-9)
    }

    func testManaOnlyAppliesToManaHeroes() {
        var mana = heroData("H004")
        XCTAssertEqual(mana.resourceKind, .mana)
        var energy = heroData("H002")
        XCTAssertEqual(energy.resourceKind, .energy)
        mana.items = ["EQ223", "EQ201"]     // パワークリスタル 280 + ウィッシュランタン 400
        energy.items = mana.items
        var a = Stats(), b = Stats(), c = Stats()
        ItemStats.apply(items: mana.items, runes: [], to: &a, master: master, hero: mana)
        ItemStats.apply(items: energy.items, runes: [], to: &b, master: master, hero: energy)
        ItemStats.apply(items: mana.items, runes: [], to: &c, master: master)
        XCTAssertEqual(a.maxResource, 680, accuracy: 1e-9)
        XCTAssertEqual(b.maxResource, 0, accuracy: 1e-9)
        XCTAssertEqual(c.maxResource, 0, accuracy: 1e-9, "ヒーローが分からなければ足さない")
        // 試合中の能力値計算でも同じ（H003 は Mana）
        var f = setup(gold: 5000)
        let i = f.human
        XCTAssertEqual(f.hero(i).resourceKind, .mana)
        let before = f.s.units[i].stats.maxResource
        _ = buy(&f, i, "EQ223")
        XCTAssertEqual(f.s.units[i].stats.maxResource, before + 280, accuracy: 1e-9)
    }

    func testRunesValorArcanaResolve() {
        var st = Stats()
        st.attack = 100; st.abilityPower = 100; st.maxHP = 1000; st.armor = 50; st.magicResist = 40
        // RN01 Valor 3% (T1) / RN12 Arcana 7% (T2) / RN23 Resolve 4% (T3)。不正 ID・同 Tier の 2 個目は無視
        ItemStats.apply(items: [], runes: ["RN01", "BOGUS", "", "RN06", "RN12", "RN23"], to: &st, master: master)
        XCTAssertEqual(st.attack, 103, accuracy: 1e-9)
        XCTAssertEqual(st.abilityPower, 107, accuracy: 1e-9)
        XCTAssertEqual(st.skillDamageBonus, 0.035, accuracy: 1e-9)
        XCTAssertEqual(st.maxHP, 1040, accuracy: 1e-9)
        XCTAssertEqual(st.armor, 52, accuracy: 1e-9)
        XCTAssertEqual(st.magicResist, 41.6, accuracy: 1e-9)
        XCTAssertEqual(ItemStats.validRunes(["RN01", "BOGUS", "RN06", "RN12", "RN23"], master: master).map(\.runeID),
                       ["RN01", "RN12", "RN23"])
    }

    func testRunesCunningHarmonyApplyAfterItems() {
        var st = Stats()
        st.moveSpeed = 300; st.hpRegen = 10; st.resourceRegen = 5
        // RN04 Cunning 6% (T1) / RN20 Harmony 8% (T2) + スイフトブーツ（+40 移動速度）
        ItemStats.apply(items: ["EQ403"], runes: ["RN04", "RN20"], to: &st, master: master)
        XCTAssertEqual(st.moveSpeed, 340 * 1.03, accuracy: 1e-9)
        XCTAssertEqual(st.cooldownReduction, 0.03, accuracy: 1e-9)
        XCTAssertEqual(st.hpRegen, 10 * 1.24, accuracy: 1e-9)
        XCTAssertEqual(st.resourceRegen, 5 * 1.24, accuracy: 1e-9)
        XCTAssertEqual(st.healShieldPower, 0.08, accuracy: 1e-9)
    }

    func testHeroStatsIncludeRunesViaStatCalculator() {
        var f = setup()
        let i = f.human
        let before = f.s.units[i].stats.attack
        f.s.units[i].hero!.runes = ["RN06"]    // Valor 8%
        StatCalculator.recompute(&f.s, i, f.ctx)
        XCTAssertEqual(f.s.units[i].stats.attack, before * 1.08, accuracy: 1e-6)
    }

    // MARK: - 推奨購入

    func testNextRecommendedPurchaseBuysComponentsFirst() {
        var f = setup(spells: ["BS01", "BS03"], gold: 300)
        let i = f.human
        XCTAssertEqual(f.hero(i).role, .ranger)
        let build = ItemSystem.recommendedBuild(for: f.hero(i), master: f.master)
        let first = f.master.item(build[0])!
        XCTAssertTrue(first.isBoots)
        let cheapest = first.buildFrom.map { f.master.item($0)!.priceGold }.min()!
        // 何も買えない
        f.s.units[i].hero!.gold = cheapest - 1
        XCTAssertNil(ItemSystem.nextRecommendedPurchase(f.hero(i), ctx: f.ctx))
        // 素材なら買える
        f.s.units[i].hero!.gold = cheapest
        let step = ItemSystem.nextRecommendedPurchase(f.hero(i), ctx: f.ctx)
        XCTAssertNotNil(step)
        XCTAssertTrue(first.buildFrom.contains(step!))
        // 完成品が買えるなら完成品
        f.s.units[i].hero!.gold = first.priceGold
        XCTAssertEqual(ItemSystem.nextRecommendedPurchase(f.hero(i), ctx: f.ctx), first.itemID)

        // 推奨に沿って買い進めると最終的にビルドが揃う
        f.s.units[i].hero!.gold = 50_000
        var guardCount = 0
        while let next = ItemSystem.nextRecommendedPurchase(f.hero(i), ctx: f.ctx), guardCount < 60 {
            XCTAssertTrue(buy(&f, i, next).purchaseFailures.isEmpty, next)
            guardCount += 1
        }
        XCTAssertEqual(f.hero(i).items.sorted(), build.sorted())
        XCTAssertNil(ItemSystem.nextRecommendedPurchase(f.hero(i), ctx: f.ctx))
    }

    func testNextRecommendedPurchaseDescendsIntoSubComponents() {
        var f = setup(gold: 260)
        let i = f.human
        let custom = ["EQ105"]
        // ハンターストライク（2010）もレイシハンマー（830）も買えない → レイシハンマーの素材のダガー
        XCTAssertEqual(ItemSystem.nextRecommendedPurchase(f.hero(i), ctx: f.ctx, customBuild: custom), "EQ133")
        f.s.units[i].hero!.gold = 900
        XCTAssertEqual(ItemSystem.nextRecommendedPurchase(f.hero(i), ctx: f.ctx, customBuild: custom), "EQ122")
        f.s.units[i].hero!.gold = 200
        XCTAssertNil(ItemSystem.nextRecommendedPurchase(f.hero(i), ctx: f.ctx, customBuild: custom))

        // 収入を少しずつ得ながら推奨どおりに買うと、無駄なく定価で完成する
        f.s.units[i].hero!.gold = 300
        var spent = 0.0, steps = 0
        while f.hero(i).items != ["EQ105"], steps < 50 {
            steps += 1
            if let next = ItemSystem.nextRecommendedPurchase(f.hero(i), ctx: f.ctx, customBuild: custom) {
                let gold = f.hero(i).gold
                XCTAssertTrue(buy(&f, i, next).purchaseFailures.isEmpty, next)
                spent += gold - f.hero(i).gold
            } else {
                f.s.units[i].hero!.gold += 300
            }
        }
        XCTAssertEqual(f.hero(i).items, ["EQ105"])
        XCTAssertEqual(f.hero(i).itemInvested, [2010])
        XCTAssertEqual(spent, 2010, accuracy: 1e-9)
        XCTAssertNil(ItemSystem.nextRecommendedPurchase(f.hero(i), ctx: f.ctx, customBuild: custom))
    }

    func testNextRecommendedPurchaseWithCustomBuildSkipsWhatCannotBeBought() {
        var f = setup(gold: 400)
        let i = f.human
        // ポーション・不明な ID は飛ばす
        XCTAssertEqual(ItemSystem.nextRecommendedPurchase(f.hero(i), ctx: f.ctx, customBuild: ["EQ134", "XXX", "EQ133"]),
                       "EQ133")
        // 2 足目の靴は飛ばす
        _ = buy(&f, i, Balance.Gear.baseBootsID)
        f.s.units[i].hero!.gold = 300
        XCTAssertEqual(ItemSystem.nextRecommendedPurchase(f.hero(i), ctx: f.ctx, customBuild: ["EQ406", "EQ133"]),
                       "EQ322", "スピードブーツを持っていればタフブーツの残りの素材")
        f.s.units[i].hero!.items = ["EQ403"]
        f.s.units[i].hero!.itemInvested = [720]
        XCTAssertEqual(ItemSystem.nextRecommendedPurchase(f.hero(i), ctx: f.ctx, customBuild: ["EQ406", "EQ133"]), "EQ133")
        _ = buy(&f, i, "EQ133")
        XCTAssertNil(ItemSystem.nextRecommendedPurchase(f.hero(i), ctx: f.ctx, customBuild: ["EQ406", "EQ133"]))
    }
}
