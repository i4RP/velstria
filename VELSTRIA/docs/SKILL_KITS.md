# ヒーロー固有スキル（キット）層の設計

`SkillCatalog` / `SkillArchetypes` / `PassiveHooks` は今、(スロット × 近接/遠隔 × ロール) の関数でスキルを決めている。
`docs/SKILL_REWORK.md` が予告していた「ヒーロー × スロットで上書きできる層」を **キット** として足す。
元ヒーローの調査は `docs/kits/*.md`。割り当ては `docs/NEW_HEROES.md`。

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
    public static func resourceCost(_ raw: Double, hero: HeroDef) -> Double     // Mana 基準の値を Energy のヒーローなら × 0.6
}
```

`KitText.fill(_:numbers:targeting:)` は `{damage} {total} {hits} {shield} {heal} {range} {radius} {cd} {x0}..{x3}` を
sim の数値で埋める（説明文の数値と sim をずらさない）。さらに `numbers.extras` の **全要素**を `KitStat.key` で引く
`{key}` も埋める（`{x#}` は先頭 4 つの別名で、値・書式は同じ: 整数に近ければ整数、そうでなければ小数 1 桁）。
例: extras が `[KitStat(key: "bleed", value: 2.5)]` なら `{bleed}` も `{x0}` も `2.5`。組み込みの名前（`damage` など）が先に勝ち、
同じ key が複数あれば先頭が勝つ。空の key と未知の `{名前}` はそのまま残る。5 つ以上の数値は `{key}` で引く。

### UI が読めるもの（スキル詳細の表・タグ）

- **タグ**: `HeroKits.tags(heroID:slot:)`（`KitText.tags`）。キーは小文字で固定（`KitTag.all`）: `buff aoe slow clash disrupt burst mobility heal shield control stun pull execute`。
  表示順 = 配列の順。キットが無い・text が無いスロットは `[]`（その場合 UI は従来の汎用の見せ方）。表示名（範囲技・減速 / AoE・Slow ...）は UI 側の対応表。
- **ランクごとの表**: `SkillCatalog.numbers(for:hero:rank:stats:)`（キットのヒーローはキットの上書き込み）を rank 1...`slot.maxRank` で引く。
  - `cooldown`: 実効秒（CD 短縮込み。キットのクールダウンは MLBB の秒数をランクへ線形補間した値で、全体倍率 `cooldownScale` は 1.0）。`cost`: ランクごとのコスト（`HeroKit.cost` の結果。Energy のヒーローは × 0.6 込み）。
    `damage` / `hits` / `ccDuration` / `cc`、再使用のあるスキルは `stage:`（`HeroKits.numbers(for:hero:rank:stats:stage:)`）で段ごとの値。
  - `extras`（`KitStat.key` で引く）: キットが表示用に足す値。H029 は `base`（換算後の基礎ダメージ）/ `atkPct`（攻撃力に対する割合 %）など。
  - 単体のコストだけ要るときは `SkillSystem.cost(for: skill, hero: heroDef, rank: rank)`（HUD の「足りるか」・スキル詳細の「コスト」はこれ）。
    旧 `SkillSystem.cost(for:resource:)` は汎用の値（キットを含まない）。

## `HeroKit` プロトコル（`Systems/Kits/HeroKit.swift`、internal・Sendable）

すべてのメソッドにプロトコル拡張で既定実装がある。キットは上書きしたいものだけ実装する。

- **A. 記述（HUD・AI・ツールチップ）**: `targeting(slot, stage, skill, hero, base)` / `numbers(slot, stage, skill, hero, rank, stats, base)` /
  `text(slot)`（`KitText(ja:en:tags:)`）/ `badge(slot, hero)` / `cost(slot, rank, skill, hero, base) -> Double`（既定 = base）。
  `base` は汎用の結果。ダメージは `base.damage` の比で表し TTK を保つ（公式の表をそのまま写すキットは、sim の通常の式 × 換算で絶対値を出してよい: H029）。
  **コストの上書き**: `cost` は発動の検証・消費（`SkillSystem.validate`）・`numbers.cost`・ボットの「足りるか」・HUD が共通で読む唯一の値。
  `base` は汎用の実効コスト（Energy は × 0.6 込み）。固定値を返すときは `HeroKits.resourceCost(raw, hero:)` を通すと Energy の倍率が付く。
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
  `skipsItemOnHit: Bool`（装備の命中時効果を外す）/ `kitHitsStructures: Bool`（ゾーンが敵の構造物にキットの onHit だけを呼ぶ）。
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
- `stateHash()` に kit のレジスタ・形態・窓の段・予約中の各 `KitTimer`（code・remaining・slot・targetID・index。挿入順）・
  突進の有無と `arriveCode`・status の (kind, tag, magnitude) を混ぜる。

### 決定性のルール（キットを書く人向け）
- ユニットは添字昇順で列挙する。乱数は `s.rng` だけ。`Date` / `Dictionary` の列挙順は使わない。
- zone / projectile / timer の生成順を固定する。クロージャや参照を状態に持たない。
- ダメージは `base.damage`（Double）から計算する。

## プリミティブ（`enum Kit`、`Systems/Kits/Kit*.swift`）

| 部品 | 要点 |
|---|---|
| 再使用の窓 `openRecast / closeRecast / window` | 最初の発動は **必ず** コストと CD を消費する（ボットの「当たった」判定が CD > 0 で見るため）。再使用は CD・コスト無視で同じ `castSkill` コマンド。窓が閉じたら `cooldownOnClose` を適用。 |
| 遅延・連撃 `schedule / cancelScheduled / strikeSequence` | `KitState.scheduled` を挿入順に消化し `onTimer` を呼ぶ。remaining 0 は同 tick に発火。 |
| 経路ヒット突進 `dashSweeping` | `MovementSystem.dash` + `KitSweep`。毎 tick `prevPos → pos` の線分上の敵を 1 度ずつ。着地で `arriveCode`。 |
| 扇状の弾 `fan` | `ProjectileSystem.spawn` のループ（角度は均等、乱数なし）。 |
| 対象指定突進 | `.targetedBlink` + `requiresTarget`。移動するなら `MovementSystem.dash` + 到着時に `strikeSequence`。 |
| 打ち上げ `knockUp` | `.airborne` status（既存）。 |
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
  許容帯は |差| ≤ 35 pt（Lv 6/12）・45 pt（Lv 1）。あわせて「開幕 3 秒の瞬間火力」（資源満タン・CD 0 の攻撃側が、動かないダミー H001 へ
  3 秒間に与える実ダメージ。距離 300/450 の平均）を同ロール汎用の中央値との比で報告する（報告のみ）。
- クールダウン: **MLBB の秒数そのまま**（6 段のランクを 4 段・奥義 3 段へ線形補間。`Balance.Skills.cooldownScale` = 1.0）。CD 短縮・レイジなど時間に関わる値も MLBB の値を基準にする。
  勝率の調整にクールダウンは使わず、ダメージ・効果の量で合わせる（CD が汎用より短い・長いスキルは単発の倍率を予算の外にしてよい。理由を書く）。
- バランス: 1 スロットの単体総ダメージは汎用の 0.8〜1.3 倍（意図的に変えるときは理由を書く）。
- クールダウンを MLBB の秒数にしたとき（2026-10、`cooldownScale` 0.5 → 1.0）の同ロール中央値との差（pt、Lv1 / Lv6 / Lv12。Release の `KitBalanceTests`）:

  | キット | 変更前（CD × 0.5） | 変更後 | 変えた値 |
  |---|---|---|---|
  | H025 ルミナ | −2.5 / −13.4 / −8.6 | +4.8 / −12.8 / −11.0 | S2 の CD をマスター → MLBB の 8 秒。攻撃速度 / 段 9% → 5%（MLBB と同じ。7% でも Lv1 +20 pt） |
  | H026 エウリア | −11.4 / +13.6 / +24.0 | −21.2 / +1.6 / +24.1 | 終わりの一撃の短縮 0.75 → 1.5 秒、鎖のロックアウト 3 → 6 秒、ボットは S2 → S1 の順 |
  | H027 ジャルド | +6.1 / −3.5 / +8.1 | +24.7 / −1.5 / +13.4 | なし |
  | H028 ザイル | +4.2 / −9.5 / −1.8 | +15.0 / +29.7 / +14.3 | 剣撃の短縮 0.5 → 1 秒、S1 の CD の特例（全体倍率のまま 5 秒）を外して 10 秒 |
  | H029 ボルグ | −8.3 / −1.3 / −7.3 | +19.1 / +17.8 / +4.4 | なし |
  | H030 ライナ | −29.8 / −0.3 / −1.5 | −5.3 / −3.4 / +3.4 | CD をマスター → ライラの 6→4 / 7.5→6.5 / 37→27 秒 |
  | H031 オーリア | +13.4 / +6.8 / +21.0 | −5.1 / −3.4 / +30.2 | CD を 6.5→5.3 / 40→32 秒 → MLBB の 6→4 / 50→40 秒。氷塊 0.85 → 0.70・雹 0.06 → 0.05 |
  | H032 ディアス | +7.6 / −5.6 / +4.5 | +21.7 / +18.2 / +28.0 | レイジ ×2 を外す（2〜5%/s）、CD 短縮 0.3 / 0.05 → 0.6 / 0.1 秒 |
  | H033 ヴァルド | −11.0 / −0.9 / −0.3 | −12.2 / +4.9 / +22.3 | CD の倍率（S1 0.55〜0.70・S2 × 1.2）を外す。S1 0.78 / 0.70 / 0.64 → 0.76 / 0.67 / 0.60（ランク 2〜4）、S2 0.81 → 0.50 |
  | H034 ゴルム | −7.8 / +4.0 / +7.8 | −17.3 / +12.8 / +13.0 | 鉤のランク 1 の特例（10 秒）を外して 15 秒 |

  変更前の H033 の S2 0.81 のままだと Lv6 / Lv12 が +39 / +42（帯の外。S2 の CD が汎用の約半分になるため）、H031 の S1 を変えないと Lv12 +40 だった。
  Release の `SkillBalanceTests`（全員総当たりの TTK 帯）、`BotMatchTests`、`WorldMatchTests`、`SkillDeterminismTests` を通してから `isReady = true` にする。

## 進め方

0. 枠組み（挙動変更なし、スタブはすべて `isReady = false`）。
1. 最初の 2 体: ライラ（H030: 距離スケーリングのみで最小）と趙子龍（H027: 再使用・突進・連撃・パッシブ差し替えで最も多くの部品を使う）。
2. ティグリアル（H029）とフランコ（H034）: 引き寄せ・suppress・段階 ULT。
3. 残り 6 体（ミヤ・エウドラ・オーロラ・ディロス・セイバー・アルカード）を並行。
4. App 側の仕上げ（再使用の光、バッジ、`AimLayer` の形、演出の段別、打ち上げの持ち上げ、鎖の演出）。
