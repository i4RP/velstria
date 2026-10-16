# ヒーロー固有スキル（キット）層の設計

`SkillCatalog` / `SkillArchetypes` / `PassiveHooks` は今、(スロット × 近接/遠隔 × ロール) の関数でスキルを決めている。
`docs/SKILL_REWORK.md` が予告していた「ヒーロー × スロットで上書きできる層」を **キット** として足す。
元ヒーローの調査は `docs/kits/*.md`。割り当ては `docs/NEW_HEROES.md`。

**数値（2026-10-14 から）**: キットのスキルは MLBB の日本語クライアントの公式の表をそのまま使う。段は MLBB と同じ 6 / 6 / 3
（スキル1・2 = Lv1〜6、アルティメット = Lv1〜3。rank = 公式の Lv。`Balance.basicSkillMaxRank`）。ダメージ = 基礎[段] + 係数 × 能力値
（合計の物理攻撃 / 追加物理攻撃 `Stats.extraAttack` / 魔法攻撃 / 最大 HP。公式の文のとおり）で、スロット倍率・物理係数 × 0.6・キットの換算・
ミニオンへの全体の × 0.2 は無い。スキルごとのスキル吸収率・攻撃エフェクト・ミニオン / モンスターへの補正は `HitPayload` に持つ（下の「テスト方針」の表）。
汎用のヒーロー（H001–H024）は `docs/GENERIC_SKILLS.md`。

パスは `VELSTRIA/Packages/VelstriaCore/` 起点（`App/` `AppTests/` `tools/` `docs/` は `VELSTRIA/` 起点）。

## 原則

1. `SkillArchetype` と `AimType` の **case は増やさない**。キットのスキルは最も近い汎用アーキタイプを土台に宣言し、
   App の `switch`（HUD・FX・AI）は変えずに動かす。細部は `AimShape` などの追加フィールドで足す。
2. キットは **状態を持たない値型**。動的な状態はすべて `HeroData.kit`・ユニットの status・zone・projectile に置く
   （sim は `SimState` の純関数のまま。リプレイ・オンラインの決定性を守る）。
3. すべて任意。上書きしたところだけがキットの挙動で、残りは汎用のまま。`isReady == false` のキットは存在しないのと同じ。
4. sim とテストの接着部は module 内（internal）。App へ出すのは小さな facade（`HeroKits`）だけ。

## 登録と facade（`Systems/Kits/KitRegistry.swift`）

```swift
public enum HeroKits {
    static let all: [any HeroKit]            // H025..H034 のスタブを最初から全部並べる（以後このファイルは変えない）
    static func kit(for heroID: String) -> (any HeroKit)?       // isReady のものだけ
    static func kit(of u: Unit) -> (any HeroKit)?               // hot path: 先に u.hero?.kit != nil で弾く
    public static func hasKit(_ heroID: String) -> Bool
    public static func targeting(for: SkillDef, hero: HeroDef, stage: Int) -> SkillTargeting
    public static func activeStage(_ hero: HeroData, slot: SkillSlot) -> Int    // 0 = 通常の発動
    public static func recast(_ hero: HeroData, slot: SkillSlot) -> RecastInfo? // stage, remaining, total
    public static func badge(_ hero: HeroData, slot: SkillSlot) -> KitBadge?    // スタック/形態/タイマー
    public static func text(heroID: String, slot: SkillSlot) -> KitText?        // ja/en テンプレート + tags
    public static func tags(heroID: String, slot: SkillSlot) -> [String]        // UI のタグ（KitTag のキー。無ければ空）
    public static func cost(for:hero:rank:base:) -> Double                      // ランク込みの実効コスト（キットの cost）
    public static func resourceCost(_ raw: Double, hero: HeroDef) -> Double     // Mana 基準の値（Energy は × energyCostMultiplier、怒り・なしは 0）
}
```

`KitText.fill(_:numbers:targeting:)` は `{damage} {total} {hits} {shield} {heal} {range} {radius} {cd} {x0}..{x3}` を
sim の数値で埋める（説明文の数値と sim をずらさない）。さらに `numbers.extras` の **全要素**を `KitStat.key` で引く
`{key}` も埋める（`{x#}` は先頭 4 つの別名で、値・書式は同じ: 整数に近ければ整数、そうでなければ小数 1 桁）。
例: extras が `[KitStat(key: "bleed", value: 2.5)]` なら `{bleed}` も `{x0}` も `2.5`。組み込みの名前（`damage` など）が先に勝ち、
同じ key が複数あれば先頭が勝つ。空の key と未知の `{名前}` はそのまま残る。5 つ以上の数値は `{key}` で引く。

### UI が読めるもの（スキル詳細の表・タグ）

- **タグ**: `HeroKits.tags(heroID:slot:)`（`KitText.tags`）。キーは小文字で固定（`KitTag.all`）: `buff aoe slow clash disrupt burst mobility heal shield control stun pull execute debuff damage conceal cleanse haste deathimmunity`
  （`debuff damage conceal cleanse` は公式のタグ Debuff / Damage / Conceal / Remove CC = デバフ・攻撃・隠れ身・コントロール解除。`haste` = 日本語クライアントの「加速」（子龍の武神降臨。英語版 Speed Up）、
  `deathimmunity` = 「死亡無効」（オーロラのプライド・オブ・アイス。Swift の定数名は `KitTag.deathImmunity`、キーは小文字だけ）。
  キーは日本語クライアントの札に合わせる: 妨害 = `disrupt`、攻撃 = `damage`、ブリンク = `mobility`、ヒール = `heal`、加速 = `haste`、死亡無効 = `deathimmunity`）。
  表示順 = 配列の順。キットが無い・text が無いスロットは `[]`（その場合 UI は従来の汎用の見せ方）。表示名（範囲技・減速 / AoE・Slow ...）と色は UI 側の対応表
  （`App/Screens/Collection/SkillShowcaseLogic.swift` の `SkillTags`。加速はバフと同じ青系、死亡無効は MLBB の札と同じ金）。新しいキーを足したら `SkillTags.knownKeys`・`name`・`symbol`・`rgb` にも足す（`AppTests/SkillShowcaseTests` が `KitTag.all` を検証する）。
- **ランクごとの表**: `SkillCatalog.numbers(for:hero:rank:stats:)`（キットのヒーローはキットの上書き込み）を rank 1...`slot.maxRank` で引く。
  - `cooldown`: 実効秒（CD 短縮込み。キットのクールダウンは公式の段の表の秒数そのまま。全体の倍率は無い）。`cost`: ランクごとのコスト（`HeroKit.cost` の結果 = 公式の段の表の MP）。
    `damage` / `hits` / `ccDuration` / `cc`、再使用のあるスキルは `stage:`（`HeroKits.numbers(for:hero:rank:stats:stage:)`）で段ごとの値。
  - `extras`（`KitStat.key` で引く）: キットが表示用に足す値。`base`（公式の基礎ダメージ）/ `atkPct`（公式の係数 %）など。
  - 単体のコストだけ要るときは `SkillSystem.cost(for: skill, hero: heroDef, rank: rank)`（HUD の「足りるか」・スキル詳細の「コスト」はこれ）。
    旧 `SkillSystem.cost(for:resource:)` は汎用の値（キットを含まない）。

## `HeroKit` プロトコル（`Systems/Kits/HeroKit.swift`、internal・Sendable）

すべてのメソッドにプロトコル拡張で既定実装がある。キットは上書きしたいものだけ実装する。

- **A. 記述（HUD・AI・ツールチップ）**: `targeting(slot, stage, skill, hero, base)` / `numbers(slot, stage, skill, hero, rank, stats, base)` /
  `text(slot)`（`KitText(ja:en:tags:)`）/ `badge(slot, hero)` / `cost(slot, rank, skill, hero, base) -> Double`（既定 = base）。
  `base` は汎用の結果。**キットのダメージは公式の表そのまま**（`Kit.official` = 基礎[段] + 係数 × 能力値。汎用の値の比や換算は使わない）。
  `movesCaster(slot, stage, base) -> Bool`: そのスキルが術者を動かすか（バインドで撃てない）。base は照準の型からの既定（dashStrike / leapSlam / targetedBlink / blinkEmpower）。
  **コストの上書き**: `cost` は発動の検証・消費（`SkillSystem.validate`）・`numbers.cost`・ボットの「足りるか」・HUD が共通で読む唯一の値。
  `base` は汎用の実効コスト。公式の MP を返すときは `HeroKits.resourceCost(Kit.level(表, rank:), hero:)` を通す（怒り・リソースなしのヒーローは 0）。
  再使用（窓が開いている間）と練習場の `noCooldowns` はこれまでどおりコスト 0。
- **B. 実行**: `resolveAim`（nil = 既定、`.some(nil)` = 拒否）/ `canStart` / `cast(KitCast) -> KitCastOutcome`
  （`.done` か `.generic(targeting?, numbers?)` で `SkillArchetypes.execute` に委ねる）/ `recast(KitCast, window:)` /
  `onTimer` / `onWindowClosed` / `onHit` / `update` / `onInterrupted` / `onDeath`。
- **C. パッシブ（キットのヒーローはロールのパッシブを置き換える）**: `outgoingDamageBonus` / `modifyIncomingDamage` /
  `forceCrit` / `shapeBasicAttack(plan: inout BasicAttackPlan)` / `onBasicAttackHit` / `onSkillHit` / `onSkillCast` /
  `onDamageTaken` / `onKillOrAssist`。
- **D. ボット**: `botCast(...) -> BotKitDecision`（`.useDefault` / `.cast(SkillTarget)` / `.castNow(SkillTarget)` / `.skip`）。
  - 奥義には汎用の関門（倒せる or 2 体以上を巻き込む）がある。`.useDefault` と `.cast` は関門を通った時だけ有効（従来どおり）。
    **`.castNow` は関門を飛び越えて今撃つ**（関門の外で奥義を使いたいキット用。その分、条件はキット側で厳しく書く）。
    再使用の窓が開いている奥義は、決定の種類にかかわらず関門を通さない（`HeroKits.isRecasting`）。
  - `botFarm(_:_:bot:slot:targeting:center:count:) -> Bool`（既定 `false`）: ミニオン・モンスターの集団（`castFarmSkills`）に対して
    突入・瞬間移動系（dashStrike / leapSlam / targetedBlink / blinkEmpower / multiStrike）を撃ってよいか。center = 集団の中心、
    count = 巻き込む数。タワー下や HP の安全判断はキットで行う（teamHeal は常に撃たない）。
  - `botEscape(_:_:bot:slot:targeting:flee:enemyDistance:) -> BotKitDecision`（既定 `.useDefault`）: 撤退中（敵が 500 以内）に
    スロットごとに呼ばれる（奥義 → スキル2 → スキル1）。`.cast` / `.castNow` で発動、`.skip` で見送り、`.useDefault` は従来どおり
    （突進・ブリンク系のスキル1/2 だけ `flee` 方向へ。奥義は撃たない）。奥義を逃走に使うのはキットが明示した時だけ。

## 既存の型への追加（すべて加算・既定値付き）

- `AimShape`（`.auto .fan .wideLine .circleAtPoint .selfRing .lockOn .dashToPoint`）。HUD と FX のヒント。
- `SkillCastEvent` に `stage / shape / halfAngle / duration / count` を追加（既定値あり）。
- `SkillTargeting` に `shape / halfAngle / reachOverride / requiresTarget / recastable`。`reach` は `reachOverride ?? 既存`。
- `SkillNumbers` に `extras: [KitStat]`（順序付き）/ `stages / recastWindow`。
- `SkillCatalog.targeting` / `numbers` は同じシグネチャのままキット対応にし、旧実装は `genericTargeting` / `genericNumbers`。
  ステージ対応は `activeTargeting(s, caster:, slot:, skill:, hero:)`（`SkillSystem.cast`・ボット・HUD が使う）。
- `StatusKind` の **末尾に** 追加: `mark`（magnitude = スタック数）/ `lifestealBoost` / `spellVampBoost` / `attackRangeBoost` /
  `armorShred` / `untargetable` / `suppress`（解除不可・`ccImmune` 無視）/ `channeling`。`preventsMovement` / `preventsActions` /
  `combatIsHarmful` / `combatIsBeneficial` / `StatusModifiers` も更新。App の `StatusKind` の網羅 switch（`HUDSnapshots.swift` の
  `status` / `statusName` / `all` など）は同じ PR で直す。
- `HitPayload` に `effects: [HitEffect]` / `scaling: DamageScaling?` / `originPos: Vec2?` / `kitEvent: Int` /
  `skipsItemOnHit: Bool`（装備の命中時効果を外す）/ `kitHitsStructures: Bool`（ゾーンが敵の構造物にキットの onHit だけを呼ぶ）/
  `spellVampRatio: Double`（スキル吸収率。既定 1）/ `attackEffect: Double?`（攻撃エフェクト。nil = appliesOnHit で 1 か 0）/
  `minionMultiplier` / `monsterMultiplier`（スキルごとのミニオン・モンスターへの倍率。既定 1）。
  `HitEffect`: `knockUp / pullToOwner / pushAway / addMark / healOwner / refundCooldown`。
  `DamageScaling`: `missingHealth / maxHealth / distance(near,far,minMult,maxMult) / marks(tag, perStack, consume)`。
- `AreaZone.followsTargetID`。
- `HeroData.kit: KitState?`（キットのヒーローだけ非 nil。`UnitFactory.makeHero` が設定）。

## 状態（`Sim/KitState.swift`）

固定フィールドのみ（`Dictionary` / `Set` 禁止: 列挙順が非決定的）。

```swift
public struct KitState: Codable, Hashable, Sendable {
    public var windows: [RecastWindow]  // 4。SkillSlot.rawValue で添字
    public var ints: [Int]              // 8 レジスタ（スタック・カウンタ・フラグ）
    public var reals: [Double]          // 8 レジスタ
    public var timers: [Double]         // 8 カウントダウン（毎 tick 0 まで自動で減る）
    public var ids: [EntityID]          // 4（0 = なし）
    public var form = 0
    public var scheduled: [KitTimer]    // 遅延・連撃
    public var sweep: KitSweep?         // 経路上にヒットする突進
}
```

- 各キットは自分のファイルの `extension KitState` に名前付きアクセサを置く（レジスタは重ねてよい: 1 ヒーロー = 1 キット）。
- 敵側のスタック/マークは `.mark` status（tag に所有者 ID を含める: `KitTags.mark("H032","brand", owner:)`）。
- 死亡で全リセット（`onDeath` で残すものを選べる）。ハード CC（スタン・打ち上げ・suppress）で `interruptible` なタイマーを取り消し `onInterrupted`。
  進行中の経路ヒット突進を止めるのは打ち上げと suppress だけ（MLBB の CC の段階: ノックアップ・制圧だけがブリンク・突進を中断する。スタンは止めない。`StatusKind.ccTier` / `interruptsDash`）。
- `stateHash()` に kit のレジスタ・形態・窓の段・予約中の各 `KitTimer`（code・remaining・slot・targetID・index。挿入順）・
  突進の有無と `arriveCode`・status の (kind, tag, magnitude) を混ぜる。

### 決定性のルール（キットを書く人向け）
- ユニットは添字昇順で列挙する。乱数は `s.rng` だけ。`Date` / `Dictionary` の列挙順は使わない。
- zone / projectile / timer の生成順を固定する。クロージャや参照を状態に持たない。
- ダメージは公式の段の表（Double）と能力値から計算する（`Kit.official`）。

## プリミティブ（`enum Kit`、`Systems/Kits/Kit*.swift`）

| 部品 | 要点 |
|---|---|
| 公式の表 `Kit.level / official / cooldown`（`KitDamage.swift`） | `Kit.level(表, rank:)` = MLBB のスキル詳細の段の表（スキル1・2 = Lv1〜6、奥義 = Lv1〜3）をそのまま引く（換算・補間なし。全段同じなら 1 要素）。`Kit.official(表, rank:, ratio:, KitScaling, stats:)` = 基礎 + 係数 × 能力値。`KitScaling`: `.totalAttack`（(+N%) = 合計の物理攻撃）/ `.extraAttack`（(+N%追加) = `Stats.extraAttack`）/ `.magicPower` / `.maxHP`。`Kit.cooldown(表, rank:, stats:)` = 公式の CD × (1 − CD 短縮)。 |
| スキル吸収率・攻撃エフェクト・ミニオン補正 | `HitPayload.spellVampRatio`（エウドラの S1 0.5）/ `attackEffect`（ミヤの月影 0.2・分裂の矢 0.3、子龍の狂龍乱舞 0.5。0 < 値 < 1 の通常攻撃の追加の命中は、装備の命中時効果の量と通常攻撃吸収をその割合で与え、命中数・パッシブの命中フック・CD 型の装備効果は数えない: `ItemEffects.onPartialAttackEffect`）/ `minionMultiplier`（エウドラの S1 2.0・ディロスの S1 0.75・セイバーの剣撃 0.5）/ `monsterMultiplier`（アルカード 1.1）。 |
| 再使用の窓 `openRecast / closeRecast / window` | 最初の発動は **必ず** コストと CD を消費する（ボットの「当たった」判定が CD > 0 で見るため）。再使用は CD・コスト無視で同じ `castSkill` コマンド。窓が閉じたら `cooldownOnClose` を適用。 |
| 遅延・連撃 `schedule / cancelScheduled / strikeSequence` | `KitState.scheduled` を挿入順に消化し `onTimer` を呼ぶ。remaining 0 は同 tick に発火。 |
| 経路ヒット突進 `dashSweeping` | `MovementSystem.dash` + `KitSweep`。毎 tick `prevPos → pos` の線分上の敵を 1 度ずつ。着地で `arriveCode`。 |
| 扇状の弾 `fan` | `ProjectileSystem.spawn` のループ（角度は均等、乱数なし）。 |
| 対象指定突進 | `.targetedBlink` + `requiresTarget`。移動するなら `MovementSystem.dash` + 到着時に `strikeSequence`。 |
| 打ち上げ `knockUp` | `.airborne` status（既存）。受けた側の進行中の突進・跳躍も止める（ノックアップ = 高レベルのコントロール）。 |
| 引き寄せ `pull` / `pushAway` | `kind: .knockback` の変位（新しい `DisplacementKind` は作らない）。フックは非貫通の弾 + `HitEffect.pullToOwner`。 |
| 地形を無視する引き寄せ `pullIgnoringTerrain`（`KitPull.swift`） | 終点（`pull` と同じ位置）が歩ける場所なら、途中の壁を無視して直線で運ぶ。壁が無い・終点が歩けないときは `pull` と同じ。H034 の鉤（`onHit` で呼ぶ）。 |
| 構造物の凍結 `freezeStructure` | 敵のタワー・Core に `.stun` を付ける唯一の入口（`addStatus(allowStructure:)`）。凍ったタワーは索敵・攻撃をしない（`canAct`）。ダメージなし・無敵の構造物は対象外。ゾーンの payload に `kitHitsStructures` を立てると、`ZoneSystem` が範囲内の敵の構造物にキットの `onHit`（dealt = 0）だけを呼ぶ。H031 の凍結。 |
| 通常攻撃の命中時効果を外す | `HitPayload.skipsItemOnHit`: 通常攻撃（`appliesOnHit`）のまま、装備の命中時効果（`ItemEffects.onBasicAttackLanded`）だけを働かせない（吸血・パッシブの命中フックは残る）。H032 の円撃。 |
| シールド・回復・吸血 | `addShield`（tag 付き）/ `.lifestealBoost` / `HitEffect.healOwner`。 |
| ダメージ補正 | `applyHit` の `dealDamage` 前に `payload.scaling` を評価。 |
| 隠密・対象不可 | `.stealth` を維持する tag（`KitTags.persistentStealth`）/ `.untargetable`（範囲・直線は当たる）。 |
| パッシブ差し替え | `PassiveHooks` の各関数の先頭で `HeroKits.kit(of:)` に委譲。`SkillPassives.update` はキットのヒーローでは早期 return。 |
| 通常攻撃の整形 | `CombatSystem.releaseAttack` で `shapeBasicAttack(plan:)` を呼ぶ（追加弾・追加ヒット・突進付きの通常攻撃）。 |
| CD 操作 | `refundCooldown / setCooldown`（練習場の `noCooldowns` を尊重）。 |

## 統合

- **コマンド**: 再使用も `PlayerCommand.castSkill(slot:target:)`。サーバ側が状態から初回/再使用を決める。新コマンドなし。
- **ボット**（`BotCombat.swift`）: `SkillCatalog.activeTargeting` を使う / 再使用中はマナ判定と奥義の関門を飛ばす / `botCast`
  （`.castNow` は関門を飛び越える）・`botFarm`・`botEscape` で上書き。
- **HUD**: `HUDSkillSnapshot` に `recast` / `badge`。`isReady` は再使用中は CD とコストを無視。`AimLayer` は `shape` を先に見る（`.auto` は既存へ）。
- **説明文**: アプリ内のスキル説明は `SkillMath.description`（`CollectionLogic.swift`）。ここで `HeroKits.text` を優先する。
  `master_en.json` の `.desc`（汎用文）は存在チェックのため残す。`AppStoreAssetsTests.testSkillDescriptionsFollowDesignArchetypes` はキットのヒーローを除外。
- **リプレイ**: 最初にキットを有効にする PR で `MatchConfig.currentSimVersion` を 5 → 6。
- **演出**: `SkillCastEvent.stage / count / duration` を `FX_H0xx.swift` が使い、再使用の段ごとに演出を分ける。

## App 統合（実装済み）

パスは `VELSTRIA/` 起点。コンパイル・実機確認は Mac 側（この節の実装は Windows で書いたため CI 未実行）。

- **説明文**: `SkillMath.kitDescription`（`App/Screens/Collection/CollectionLogic.swift`）が `HeroKits.text` を現在の言語で `KitText.fill`（ランク 1・能力値ボーナスなしの
  `SkillMath.numbers` / `SkillCatalog.targeting`）で埋める。`SkillMath.description` はこれを先に引き、キットが無い・そのスロットの文が空なら従来の生成文に戻る
  （HUD の長押しの説明 `HUDModel.makeSkillTip`・スキル詳細・パッシブの文が共用）。スキル詳細はキットのヒーローで「固有係数」タグ・アーキタイプ説明・汎用の補足・
  マスターの CC を隠し、CD は `SkillMath.cooldown(_:hero:rank:)`（キットの numbers）、ランク表の列は値があるものだけ（`SkillMath.figures(_:hero:archetype:)`）、
  図の名前は `SkillMath.shapeName(targeting.shape)`。
- **HUD**: `HUDSkillSnapshot` に `recast: RecastInfo?` / `badge: KitBadge?`（`HUDKitDisplay.rounded` で 0.1 秒単位）。`isReady` は再使用中は CD・コストを見ない
  （`castable` は sim の `validate` と同じ判定）。`buildHeroPanel` は再使用の窓が開いている間、`HeroKits.targeting(stage: activeStage)` の照準（形・射程・対象指定）を
  スナップショットに入れる（= 照準セッションがその段で動く）。スキルボタンは再使用中に残り時間の輪と光（`HUDRecastRing`）、右上にバッジ（`HUDKitBadgeChip`:
  スタック数 / 形態 / タイマー秒）、CD の幕は出さない。パッシブのバッジは `HUDHeroSnapshot.passiveBadge` → 状態アイコン列の先頭（金の印、`HUDStatusRow.passive`）。
- **照準**: `AimShapePlan.make`（`App/Battle/Render/AimLayer.swift`）が `SkillTargeting.shape` を先に見る。`.fan`（`halfAngle` > 0 の扇、半径 = 射程）/ `.wideLine`
  （半幅 = `radius` の帯 + 矢印）/ `.dashToPoint`（半幅 = `radius` の帯 + 終点の輪）/ `.circleAtPoint` / `.selfRing` / `.lockOn`（対象の輪）。`.auto`、および aim と合わない
  組み合わせ（扇で角度なし など）は `.legacy` = 従来の archetype / aim の分岐。`HUDAim.castTarget` は変えない（`lockOn` は aim `.unit` なので敵ヒーローを送り、居なければ `.none`
  = sim が自動選択・`requiresTarget` は拒否）。
- **演出**: キットのヒーローは **通常攻撃 = Effekseer、スキル = SkillFX**（`EffekseerRouting`。理由は `docs/EFFEKSEER.md`。造形を作り直して `atk_*` の `.efk` と
  合わなくなった H025・H027・H030・H033 は通常攻撃も `HeroFXProfiles` = `EffekseerRouting.staleAttackHeroes`）。SkillFX は `SkillCastEvent.stage` が 1 以上のとき
  `HeroFXSet.recipe(_:stage:_:)` の段の演出を使える（既定 nil。FX_H0xx はまだ使っていない）。キットのヒーローのパッシブの演出は、ロールの合図ではなくパッシブのバッジの変化で出す
  （`SkillFXDirector.observeKitPassives`）。`duration` は **`durationFromCast` を立てた合図だけ**が読む（`FXEmit` の継続放出の `duration`・`FXMesh` の `life` を
  `SkillCastEvent.duration` に置き換える。cast と発動と同時の impact のみ。0 なら書いた値、上限 `FXCue.castDurationLimit` = 10 秒。予算の検査は書いた値にかかる。
  例: H025 S1 の効果中の足元の三日月と弓のきらめき = 効果時間 4→9 秒）。`count` / `shape` はまだ読まない（FX_H0xx は固定のタイミングで書いてある）。
- **演出（追加の hook）**: (1) 多段ヒットのスキルは同じ相手へ `hit` を **0.9 秒に 1 回**しか再生しない（キットのヒーローのみ。`SkillFXDirector.hitInterval`。
  1 発ごとに出したい短い演出だけ `r.hitPerHit = true`、それ以外のヒーローは従来の 0.15 秒）。(2) パッシブのスタックを**使い切った**（>= 1 → 0）のが
  スキルの発動の直後（0.6 秒以内）なら、積む演出ではなく `HeroFXSet.passiveRelease(_ s: FXSkillInfo, released: Int) -> [FXCue]?` を術者に追従して再生する
  （既定 nil = 何も出さない。`released` = 消費したスタック数、`s` は passive スロットの寸法。ボルグの防御・ゴルムのスタック消費用。同時にタイマーが始まるなら
  `passiveRelease` が nil のとき通常の合図に進む）。段の演出（`recipe(_:stage:_:)`）と同じく FX_H0xx が足すだけでよく、Director・Catalog の変更は要らない。
- **世界の状態表示**（`App/Battle/Render/KitStatusVisuals.swift` が純粋な対応表、`StatusIndicators` / `HeroVisual` が描く）: `.mark` は頭上の回るひし形 + 輪
  （色は tag の所有者ヒーロー ID から。スタック数で少し大きく。複数ならスタック最大の 1 つ）、H031 の凍結（`stun` + `kit.H031.freeze`）と氷の誇り
  （`suppress` + `kit.H031.prideFreeze`）は回る星の代わりに氷の殻、`stealth` は**自分・味方・観戦**にだけモデルを 40% の不透明度で見せる（敵の視点は不変 =
  敵のステルスは視界の判定のまま）、H031 の足元の細い氷の輪 = パッシブのバッジが「準備できた」（`HeroKits.badge` は `HeroData` だけから計算する純粋な関数なので、
  描画のスナップショットの誰のユニットからでも読める = 全員に見える）。`suppress` は行動不能なので星・`.stunned` の姿勢も出す。HUD の状態アイコンは
  `HUDSymbols.status/statusName/statusColor(_:tag:)` が tag を見る（超伝導 H026 `sc`・虚空の印 H030 `void`・空断の理 H028 `bane`・衝撃波の印 H029 `wave`・
  凍結。未登録は汎用）。新しいマーク・凍結の tag は `KitStatusVisuals`（`markName` / `markSymbol` / `markColor`）に足す。
- **テスト**: `AppTests/HUDKitTests.swift`（スナップショットの再使用・バッジの表示値・ビルダー・照準の形・lockOn の対象・tag → 名前/アイコン/氷の殻/マーク/ステルス/氷の輪）、
  `CollectionLogicTests`（キットの説明・CD・列）、`EffekseerTests`（役割分担）、`SkillFXTests`（段の演出・パッシブの合図・解放の合図・被弾の間隔）。

## ファイル構成

```
Sim/KitState.swift
Systems/Kits/HeroKit.swift  KitRegistry.swift  KitRuntime.swift  KitRecast.swift  KitTimers.swift
Systems/Kits/KitMovement.swift  KitPull.swift  KitProjectiles.swift  KitStatus.swift  KitDamage.swift  KitBasicAttack.swift
Systems/Kits/Kit_H025.swift ... Kit_H034.swift     （最初は isReady = false のスタブ）
Tests/VelstriaCoreTests/Kits/KitTestSupport.swift  KitFrameworkTests.swift  Kit_H0xxTests.swift
```

キットの実装者が触るのは自分の `Kit_H0xx.swift`・`Kit_H0xxTests.swift`・`App/Battle/SkillFX/Heroes/FX_H0xx.swift` だけ。
新しいプリミティブが要るときは新しいファイル（`Kit<名前>.swift`）で足し、共有ファイルは触らない。

## テスト方針

- 枠組み: `SkillWorld`（`Tests/.../SkillArchetypeTests.swift`）で各プリミティブを直接試す。**キット無効のとき既存の Core テスト全体が不変**であること。
- キットごと: レジストリ・ターゲティング・数値・各スキルのダメージ/CC/変位・再使用の窓・パッシブ・端の場合（スタン中・死亡・練習場）・
  決定性（同じ入力 2 回 / 途中でシリアライズして再開）・ボットの煙テスト。
- 共有部品: `Tests/.../Kits/KitSharedTests.swift`（`{key}`・`stateHash` の予約タイマー・`fireTimers`・ボットのフック）。
- バランス計測: `Tests/.../Kits/KitBalanceHarness.swift`（`BalanceHarness`）と `KitBalanceTests.swift`。1 組を「両陣営の割り当て ×
  開始距離 300/450/600 × 乱数の種 2 つ」の 12 戦で平均し（引き分け = 0.5）、Lv 1/6/12 の全員総当たりの勝率を出して、キットのヒーローを
  **同ロールの汎用ヒーローの中央値**と比べる。表は Release のテスト出力に出る（`swift test -c release --filter KitBalanceTests`）。
  帯は |差| ≤ 35 pt（Lv 6/12）・45 pt（Lv 1）。比べる汎用ヒーローは **MLBB のロール**（ティグラル H029・フランコ H034 = タンク → ヴァンガード。
  `KitBalanceTests.peerRole`）。あわせて「開幕 3 秒の瞬間火力」（資源満タン・CD 0 の攻撃側が、動かないダミー H001 へ
  3 秒間に与える実ダメージ。距離 300/450 の平均）を同ロール汎用の中央値との比で報告する（報告のみ）。ゲームに出す 10 体（H025–H034）同士の
  総当たりも報告する（`testActiveRosterRoundRobin`。報告のみ）。
- **スキルの数値は公式の表そのまま**（2026-10-14 のスキルの段階から）: スキル1・2 = Lv1〜6、アルティメット = Lv1〜3 の表を `Kit.level` で引く
  （rank = 公式の Lv。補間・換算・スロット倍率・物理係数 × 0.6 は無い）。クールダウン・MP・持続も公式の表。
  **勝率・TTK を帯に合わせるために公式の値を変えない。** 帯を外れたら、実装の不具合を探し、無ければ理由を書いて帯（外れ値の表）を見直す。
- スキルごとの割合（公式の文にあるものだけ。無ければ既定 = 吸収率 100%・攻撃エフェクト = 通常攻撃なら 100%・ミニオン / モンスター 100%）:

  | キット | 割合 | 出典 |
  |---|---|---|
  | H025 ミヤ | 月影 攻撃エフェクト 20%、分裂の矢 攻撃エフェクト 30% | 日本語クライアント（REAL_DATA） |
  | H026 エウドラ | S1 スキル吸収率 50%、S1 ミニオンに 200% | 日本語クライアント |
  | H027 子龍 | 狂龍乱舞の 3 撃 攻撃エフェクト 50% | 日本語クライアント |
  | H028 セイバー | 剣撃 ミニオンへ 50%（進路上の 50% にも掛けて 25%） | 日本語クライアント |
  | H032 ディアス | S1 ミニオンに 75%、円撃は攻撃エフェクトなし（`skipsItemOnHit`） | 日本語クライアント |
  | H033 アルカード | デビルハンター モンスターに 110%（`monsterMultiplier`。ほかの与ダメ補正と掛け算） | 日本語クライアント |

- 外した独自ルール（MLBB に無い、旧尺度のバランスのためのもの）: エウドラの鎖の 6 秒の再リンク禁止（S1 の 50% の CD 短縮は 1 回の発動につき 1 回。
  鎖が 2 本でも CD が 0 にならない）、オーロラのパッシブの回復の Lv 補間（0% → 30%。今は常に 30%）・霜風の「近くは凍らない」、
  ディアスの円撃の回復 × 0.2（今は最大 HP の 7〜10%）・CD 短縮 0.55 / 0.05 秒と「敵ヒーローのみ」（今は敵にダメージを与えるたび 1 秒。1 回の行動につき 1 回）、
  フランコの奥義の最大 HP 80% の上限・奥義の踏み込み、セイバーの剣撃のモンスター 50%、アルカードの「追加物理攻撃」の係数を合計の物理攻撃に掛けていたこと・
  スキル吸収 × 0.33、子龍の通常攻撃の固定値 × 0.25・連撃 × 0.6・ヒーロー以外への回復 50%、エウドラの S2 の「ミニオンにはダメージのみ」。
  防御ダウンの割合への換算（子龍の S2・セイバーのパッシブ）は物理防御だけの固定値（`flatArmorMod`）。
- スキルの段階（2026-10-14、`MatchConfig.currentSimVersion` 21 → 22）の前後の Release の `KitBalanceTests`（同ロール中央値との差、pt、Lv1 / Lv6 / Lv12。
  Windows・`swift test -c release`。前 = 換算あり・汎用は旧倍率・ロールは Velstria のロール、後 = 公式の表・汎用は MLBB の型・ロールは MLBB のロール）:

  | キット | 前 | 後 | 後の外れ値の理由（`KitBalanceTests.knownOutliers`） |
  |---|---|---|---|
  | H025 ミヤ | −10.6 / +16.7 / +7.8 | +3.5 / +8.3 / +8.7 | |
  | H026 エウドラ | −9.1 / +27.8 / +19.4 | +41.2 / **+75.8** / **+75.8** | 汎用のアルカニストはダメージのスキルが実質 S1 と奥義だけ（S2 はブリンク + 強化攻撃）で、装備なしは魔法攻撃 0 |
  | H027 子龍 | +12.1 / −15.9 / −1.0 | +14.9 / +20.5 / +19.3 | |
  | H028 セイバー | −22.7 / +19.7 / +24.0 | +31.8 / **+63.4** / **+62.5** | MLBB のアサシンの多段（剣の接触・剣撃・三連撃）と汎用のアサシンの 1 撃ずつ |
  | H029 ティグラル | −19.2 / **+36.6** / **+48.0** | +33.3 / +33.1 / **+43.4** | MLBB のタンク（HP 成長 307）+ 奥義 3 段目 1000 (+130%)（比べるのはヴァンガード） |
  | H030 ライラ | −3.0 / +22.2 / +20.7 | +17.7 / +27.0 / +31.9 | |
  | H031 オーロラ | +2.3 / +12.1 / +29.8 | **+81.6** / **+75.0** / **+77.0** | H026 と同じ（汎用のアルカニストの中央値 4.5〜10.4%） |
  | H032 ディアス | −24.2 / +1.3 / +15.2 | +21.0 / +26.5 / +28.4 | |
  | H033 アルカード | +14.6 / +13.6 / +22.0 | +26.8 / **+53.3** / **+56.4** | H028 と同じ |
  | H034 フランコ | −31.6 / **+59.3** / **+55.8** | +8.1 / +22.0 / +24.7 | （ヴァンガードと比べると帯の中。以前の外れ値を外した） |

  前の太字は eb8d5b8 の時点の失敗（H029 Lv6 +36.6）と既知の外れ値。汎用ヒーローの中央値は前後で大きく動いた（Lv6: ヴァンガード 89.1 → 57.8・
  デュエリスト 79.5 → 73.5・レンジャー 23.7 → 35.1・アルカニスト 12.1 → 4.5・サポート 23.5 → 25.3・アサシン 52.5 → 31.6%）。
  汎用ヒーロー（H001–H024）はゲームに出していない（`HeroRoster.activeHeroIDs` = H025–H034）。ゲームに出す 10 体同士の総当たり（後、Lv1 / Lv6 / Lv12 %）:
  ミヤ 29.6 / 0.0 / 0.0、エウドラ 18.5 / 37.0 / 31.5、子龍 77.8 / 77.8 / 66.7、セイバー 48.1 / 81.5 / 77.8、ティグラル 66.7 / 66.7 / 88.9、
  ライラ 44.4 / 11.1 / 11.1、オーロラ 70.4 / 46.3 / 42.6、ディアス 100 / 100 / 100、アルカード 0.0 / 44.4 / 55.6、フランコ 44.4 / 35.2 / 25.9
  （装備なしの 1v1 の台本。公式の値どうしの結果なので帯で縛らない。ディアスの全勝はダメージ 1 回ごとの CD −1 秒と 3 連の爆発・奥義の損失 HP 25% による）。
- TTK（`SkillBalanceTests`）: ロール代表（H001–H006）の 1v1 は 4.1〜16.4 秒 → 10.5〜36.4 秒、ゲームに出す 10 体の総当たりの中央値は
  Lv1 12.2 → 13.5 / Lv6 7.5 → 8.5 / Lv12 8.1 → 9.1 秒（最短 1.6 → 2.2 秒・最長 21.8 → 24.2 秒）。帯は 2.5〜22 → 1.8〜38 秒
  （全員総当たりの絶対帯 2.0〜25 → 1.5〜40 秒）。理由はテストのコメント（伸びたのはタンク・サポートの組、縮んだのはディアスの柔らかい相手へのバースト）。
  キットごとの帯: ティグラルの総当たりの上限 0.75 → 0.9、ディアス・アルカードの総当たりの上限は汎用の同ロール → 同じロールの MLBB のヒーロー（子龍 + 35 pt・セイバー + 30 pt）。
- ティグラルの幾何と時間を MLBB の画面収録で測った値に変えた後（2026-10-15、`MatchConfig.currentSimVersion` 22 → 23。docs/kits/Tigreal.md
  「動画で測った値」。Windows・`swift test -c release`）: `KitBalanceTests` の同ロール中央値との差 +34.3 / +29.5 / **+38.9**（Lv12 は既知の外れ値のまま）、
  ゲームに出す 10 体の総当たり 70.4 / 53.7 / 72.2%、`Kit_H029Tests` の総当たり Lv6 66.7% / Lv12 77.8%。スキル1 が止まった相手に 1〜2 回しか当たらず、
  奥義の半径が 520 → 278 と狭くなったぶん下がった。
- フランコの幾何と時間を MLBB の画面収録で測った値に変えた後（2026-10-16、`MatchConfig.currentSimVersion` 23 → 24。docs/kits/Franco.md
  「動画で測った値」。Windows・`swift test -c release`）: `KitBalanceTests` のヴァンガードの中央値との差 +8.1 / +22.0 / +24.7 → +3.5 / +18.9 / +26.3、
  ゲームに出す 10 体の総当たり 44.4 / 35.2 / 25.9 → 44.4 / 22.2 / 25.9%、`Kit_H034Tests` の総当たり Lv6 82% → 79% / Lv12 79% → 79%、
  ロール代表との TTK 12.1〜22.1 → 13.1〜24.0 秒（17 → 16 / 18 勝）。鉤・S2・奥義に振りかぶりが入り、奥義の射程が 350 → 188 と短くなったぶん下がった
  （鉤の射程 680 → 823 と命中から 1.3 秒のスタンで一部を取り戻す）。
- オーロラの幾何と時間を MLBB の画面収録で測った値に変えた後（2026-10-16、`MatchConfig.currentSimVersion` 26 → 29。27・28 はフランコ・ミヤの作業が使う。
  docs/kits/Aurora.md「動画で測った値」。Windows・`swift test -c release`）: `KitBalanceTests` のアルカニストの中央値との差 +80.6 / +75.0 / +77.0 →
  +81.6 / +83.3 / +80.3（既知の外れ値のまま）、ゲームに出す 10 体の総当たり 66.7 / 46.3 / 42.6 → 70.4 / 55.6 / 44.4%、`Kit_H031Tests` の総当たり
  66.7 / 44.4 / 44.4 → 66.7 / 50.0 / 44.4%、ロール代表との TTK 10.3〜18.2 → 9.8〜15.8 秒。雹が隕石の円の全員に 5 発当たるようになったぶん上がった
  （扇の半角 37° → 25°・霜風の遅れ 0.3 → 0.56 秒・奥義の円 → 細い帯で一部を戻す）。ゾーンに内側の欠け（`innerRadius`）と端の四角い線分（`squareEnds`）を足した。
  `BotMatchTests` の泉に立つ人間の通常戦のシード 5（7:47 で 8 分未満）を 6 にした。

## 進め方

0. 枠組み（挙動変更なし、スタブはすべて `isReady = false`）。
1. 最初の 2 体: ライラ（H030: 距離スケーリングのみで最小）と趙子龍（H027: 再使用・突進・連撃・パッシブ差し替えで最も多くの部品を使う）。
2. ティグリアル（H029）とフランコ（H034）: 引き寄せ・suppress・段階 ULT。
3. 残り 6 体（ミヤ・エウドラ・オーロラ・ディロス・セイバー・アルカード）を並行。
4. App 側の仕上げ（再使用の光、バッジ、`AimLayer` の形、演出の段別、打ち上げの持ち上げ、鎖の演出）。
