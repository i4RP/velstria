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
    public static func text(heroID: String, slot: SkillSlot) -> KitText?        // ja/en テンプレート
}
```

`KitText.fill(_:numbers:targeting:)` は `{damage} {total} {hits} {shield} {heal} {range} {radius} {cd} {x0}..{x3}` を
sim の数値で埋める（説明文の数値と sim をずらさない）。

## `HeroKit` プロトコル（`Systems/Kits/HeroKit.swift`、internal・Sendable）

すべてのメソッドにプロトコル拡張で既定実装がある。キットは上書きしたいものだけ実装する。

- **A. 記述（HUD・AI・ツールチップ）**: `targeting(slot, stage, skill, hero, base)` / `numbers(slot, stage, skill, hero, rank, stats, base)` /
  `text(slot)` / `badge(slot, hero)`。`base` は汎用の結果。ダメージは `base.damage` の比で表し TTK を保つ。
- **B. 実行**: `resolveAim`（nil = 既定、`.some(nil)` = 拒否）/ `canStart` / `cast(KitCast) -> KitCastOutcome`
  （`.done` か `.generic(targeting?, numbers?)` で `SkillArchetypes.execute` に委ねる）/ `recast(KitCast, window:)` /
  `onTimer` / `onWindowClosed` / `onHit` / `update` / `onInterrupted` / `onDeath`。
- **C. パッシブ（キットのヒーローはロールのパッシブを置き換える）**: `outgoingDamageBonus` / `modifyIncomingDamage` /
  `forceCrit` / `shapeBasicAttack(plan: inout BasicAttackPlan)` / `onBasicAttackHit` / `onSkillHit` / `onSkillCast` /
  `onDamageTaken` / `onKillOrAssist`。
- **D. ボット**: `botCast(...) -> BotKitDecision`（`.useDefault` / `.cast(SkillTarget)` / `.skip`）。

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
- `HitPayload` に `effects: [HitEffect]` / `scaling: DamageScaling?` / `originPos: Vec2?` / `kitEvent: Int`。
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
- `stateHash()` に kit のレジスタ・形態・窓の段・`scheduled.count`・status の (kind, tag, magnitude) を混ぜる。

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
| シールド・回復・吸血 | `addShield`（tag 付き）/ `.lifestealBoost` / `HitEffect.healOwner`。 |
| ダメージ補正 | `applyHit` の `dealDamage` 前に `payload.scaling` を評価。 |
| 隠密・対象不可 | `.stealth` を維持する tag（`KitTags.persistentStealth`）/ `.untargetable`（範囲・直線は当たる）。 |
| パッシブ差し替え | `PassiveHooks` の各関数の先頭で `HeroKits.kit(of:)` に委譲。`SkillPassives.update` はキットのヒーローでは早期 return。 |
| 通常攻撃の整形 | `CombatSystem.releaseAttack` で `shapeBasicAttack(plan:)` を呼ぶ（追加弾・追加ヒット・突進付きの通常攻撃）。 |
| CD 操作 | `refundCooldown / setCooldown`（練習場の `noCooldowns` を尊重）。 |

## 統合

- **コマンド**: 再使用も `PlayerCommand.castSkill(slot:target:)`。サーバ側が状態から初回/再使用を決める。新コマンドなし。
- **ボット**（`BotCombat.swift`）: `SkillCatalog.activeTargeting` を使う / 再使用中はマナ判定を飛ばす / `botCast` で上書き。
- **HUD**: `HUDSkillSnapshot` に `recast` / `badge`。`isReady` は再使用中は CD とコストを無視。`AimLayer` は `shape` を先に見る（`.auto` は既存へ）。
- **説明文**: アプリ内のスキル説明は `SkillMath.description`（`CollectionLogic.swift`）。ここで `HeroKits.text` を優先する。
  `master_en.json` の `.desc`（汎用文）は存在チェックのため残す。`AppStoreAssetsTests.testSkillDescriptionsFollowDesignArchetypes` はキットのヒーローを除外。
- **リプレイ**: 最初にキットを有効にする PR で `MatchConfig.currentSimVersion` を 5 → 6。
- **演出**: `SkillCastEvent.stage / count / duration` を `FX_H0xx.swift` が使い、再使用の段ごとに演出を分ける。

## ファイル構成

```
Sim/KitState.swift
Systems/Kits/HeroKit.swift  KitRegistry.swift  KitRuntime.swift  KitRecast.swift  KitTimers.swift
Systems/Kits/KitMovement.swift  KitProjectiles.swift  KitStatus.swift  KitDamage.swift  KitBasicAttack.swift
Systems/Kits/Kit_H025.swift ... Kit_H034.swift     （最初は isReady = false のスタブ）
Tests/VelstriaCoreTests/Kits/KitTestSupport.swift  KitFrameworkTests.swift  Kit_H0xxTests.swift
```

キットの実装者が触るのは自分の `Kit_H0xx.swift`・`Kit_H0xxTests.swift`・`App/Battle/SkillFX/Heroes/FX_H0xx.swift` だけ。
新しいプリミティブが要るときは新しいファイル（`Kit<名前>.swift`）で足し、共有ファイルは触らない。

## テスト方針

- 枠組み: `SkillWorld`（`Tests/.../SkillArchetypeTests.swift`）で各プリミティブを直接試す。**キット無効のとき既存の Core テスト全体が不変**であること。
- キットごと: レジストリ・ターゲティング・数値・各スキルのダメージ/CC/変位・再使用の窓・パッシブ・端の場合（スタン中・死亡・練習場）・
  決定性（同じ入力 2 回 / 途中でシリアライズして再開）・ボットの煙テスト。
- バランス: 1 スロットの単体総ダメージは汎用の 0.8〜1.3 倍（意図的に変えるときは理由を書く）。
  Release の `SkillBalanceTests`（全員総当たりの TTK 帯）、`BotMatchTests`、`WorldMatchTests`、`SkillDeterminismTests` を通してから `isReady = true` にする。

## 進め方

0. 枠組み（挙動変更なし、スタブはすべて `isReady = false`）。
1. 最初の 2 体: ライラ（H030: 距離スケーリングのみで最小）と趙子龍（H027: 再使用・突進・連撃・パッシブ差し替えで最も多くの部品を使う）。
2. ティグリアル（H029）とフランコ（H034）: 引き寄せ・suppress・段階 ULT。
3. 残り 6 体（ミヤ・エウドラ・オーロラ・ディロス・セイバー・アルカード）を並行。
4. App 側の仕上げ（再使用の光、バッジ、`AimLayer` の形、演出の段別、打ち上げの持ち上げ、鎖の演出）。
