# Miya (MLBB) - Kit Specification

Primary source: Mobile Legends Fandom hero page (fetched via the MediaWiki API, page edited 2026-09-29), cross-checked against gameboost.com, Fandom patch history and search extracts. "unknown" = not found. "disputed" = sources disagree. Ranges are in wiki "units" (one unit is roughly one map tile).

## Hero overview
- Role / lane: Marksman (Finisher/Damage), Gold Lane. Ranged, mana resource, physical damage. Ratings: durability 1, offense 7, control 4, difficulty 1.
- Basic attack: ranged single target, attack range 4.8 (Fandom current; an old patch note says 4.6 after a 1.1.23 nerf, so treat 4.8 as current). Attack speed is capped at 3 attacks/s. Projectile speed: unknown.
- Level 1 stats: HP 2225, HP regen 6.0, mana 500, mana regen 4, physical attack 115, physical defense 17 (12.4% reduction), magic defense 15 (11.1%), attack speed 1.06, movement speed 240, crit damage 200%.
- Level 15 stats: HP 4367, regen 9.0, mana 1900, physical attack 227, physical defense 74, magic defense 50, attack speed 1.41.
- Growth per level: HP +153, regen +0.2143, mana +100, mana regen +0.2, physical attack +8, physical defense +4.0714, magic defense +2.5, attack speed +0.025.
- Max skill levels: S1 6, S2 6, Ultimate 3.

## Passive - Moon Blessing
- Cast type: passive stacking buff.
- Each time a basic attack hits a target she gains 5% attack speed for 4 s; stacks up to 5 times (5/10/15/20/25%).
- At full stacks every basic attack also summons a Moonlight Shadow dealing 30 (+25% total physical attack) physical damage; it inherits a portion of attack effects (25% attack-effect ratio, 0% lifesteal ratio).
- Disputed: gameboost lists the shadow scaling as 30% total physical attack; Fandom says 25%. Use 25% (Fandom, current).
- Stack refresh behavior (whether each hit refreshes all stacks): unknown.

## Skill 1 - Moon Arrow
- Cast type: self buff (no aim); modifies basic attacks.
- Miya shoots two extra arrows with each basic attack for the duration: the target takes 10-35 (+100% total physical attack) physical damage (this is the primary arrow) and nearby targets take 30% damage. Extra arrows inherit 20% of attack effects, spell vamp ratio 50%, lifesteal ratio 0%.
- Duration: the effect text says 4 s. Fandom's level table lists duration 4/5/6/7/8/9 s by skill level; gameboost says 4 s flat. Disputed: use 4 s base, 9 s at level 6 only if the table is accepted.
- Cooldown 11.0 s at all levels, starts on cast. Cannot be recast until its duration ends.
- Mana: 50/55/60/65/70/75. Base damage: 10/15/20/25/30/35 (a patch note says this was reduced from 10-60 in 1.6.66).
- Arrow spread angle and range: unknown.

## Skill 2 - Arrow of Eclipse
- Cast type: ground-target circle skill with a delay (not a point-and-click). The wiki notes a cast delay, reduced 25% in patch 1.8.66; exact delay seconds: unknown. Cast range: unknown (a patch increased it slightly in 1.8.20).
- Effect 1: an empowered arrow lands on the target area, dealing 270-420 (+45% total physical attack) physical damage to enemies within and immobilizing them for 1.2 s (immobilize prevents movement and blink/charge skills, does not interrupt skills or stop attacks).
- Effect 2: the arrow then splits into 6 scattering minor arrows, each dealing 40-105 (+20% total physical attack) physical damage to the first enemy hit and slowing them 30% for 2 s.
- Cooldown 8.0 s at all levels. Mana 80/90/100/110/120/130.
- Base damage by level: arrow 270/300/330/360/390/420; minor arrow 40/53/66/79/92/105. Radius: patch history says it was 1.7 (damage and indicator radius) at 1.1.22; current radius: unknown.

## Ultimate - Hidden Moonlight
- Cast type: self-cast, instant.
- Removes all debuffs from Miya and conceals her (invisible to enemies unless revealed) and gives 65% extra movement speed. Lasts 2 s or until she launches an attack. The ending attacks are only basic attacks and non-ultimate skill casts.
- On leaving the state she gains full stacks of Moon Blessing (25% attack speed, shadow active).
- Cooldown 30/25/20 s (Fandom current). Disputed: gameboost lists 46-26 s (outdated; a 1.5.18 patch note listed 48-46 s and later patches changed it). Mana 120/145/170. gameboost also says the speed bonus is 35%-65% by level; Fandom shows flat 65%. Disputed.
- Whether she can be targeted by area effects while concealed: standard concealment, no invulnerability.

## Gameplay identity
- Pure auto-attack carry: DPS ramps with the 5-stack attack speed plus Moon Arrow's triple-arrow cleave.
- Weak early (patch 1.8.66 buffed Skill 2 to improve early 1v1) and falls off if she is caught; relies on kiting inside a 4.8 attack range.
- Arrow of Eclipse is the lane and pick tool: the 1.2 s immobilize lets her land the 6 minor arrows (slow) and then attack freely.
- Hidden Moonlight is both an escape/reposition (65% speed, debuff cleanse) and a reset to full attack-speed stacks, so an opening attack from stealth is her strongest burst.

## Simulation notes
- Standard: ranged basic attack, ground-target circle with delay, 1.2 s root-style immobilize (movement only, attacks and casts still allowed), slow, timed self buff, cleanse, stealth.
- Needs special state: Moon Blessing stack counter with a shared 4 s refresh and full-stack trigger for the extra Moonlight Shadow attack; Moon Arrow as a timed attack modifier that adds a primary-plus-cleave damage profile and is not recastable while active; stealth that breaks on basic attack or skill cast except the ultimate; entering/leaving Hidden Moonlight forcing full stacks; the 6-arrow fan after Arrow of Eclipse landing (spawned secondary projectiles, each hitting the first enemy only).
- Attack-effect inheritance (25%/20%) is item-system dependent and can be simplified.

## Sources
- https://mobile-legends.fandom.com/wiki/Miya
- https://mobile-legends.fandom.com/wiki/Miya/Patch_history
- https://gameboost.com/blog/mlbb-guide-miya
- https://www.oneesports.gg/mobile-legends/miya-guide-best-build-mlbb/ (descriptions only, no numbers)

## 公式（Fandom 現行）の数値

Fandom のヒーローのページ（MediaWiki API で 2026-10-10 に再取得。スキルの Lv は S1・S2 が 1〜6、アルティメットが 1〜3）。日本語クライアントの画面は手元に無いので、
Fandom の英語の説明文の構造を正とする（タグも Fandom の `skill-effect`）。上の調査で「割れている」とした値は、ここで Fandom の表を採った。

| スロット | 公式名 | タグ | CD | MP | 内容（Lv1 → Lv6 / Lv3） |
|---|---|---|---|---|---|
| パッシブ | Moon Blessing | Buff | – | – | 通常攻撃が命中するたびに攻撃速度 +5%（4 秒、最大 5 スタック = 25%）。最大スタックの間は通常攻撃のたびに Moonlight Shadow を呼び、30(+25%物理攻撃)の物理ダメージ（攻撃効果を 25% 継承） |
| スキル1 | Moon Arrow | Buff・AOE | 11.0（一定） | 50 / 55 / 60 / 65 / 70 / 75 | 通常攻撃のたびに追加の矢を 2 本放ち、対象の敵に 10〜35(+100%物理攻撃)の物理ダメージ、周囲の敵に 30% のダメージ。持続 4 / 5 / 6 / 7 / 8 / 9 秒（`level-scaling` の Duration）。発動で CD 開始、効果中は再使用不可 |
| スキル2 | Arrow of Eclipse | CC・AOE | 8.0（一定） | 80 / 90 / 100 / 110 / 120 / 130 | 指定範囲に強化された矢を放ち、範囲の敵に 270 / 300 / 330 / 360 / 390 / 420(+45%物理攻撃)の物理ダメージ + 1.2 秒の移動不能。矢は 6 本の小さな矢に分かれて散り、それぞれ最初に当たった敵に 40 / 53 / 66 / 79 / 92 / 105(+20%物理攻撃)の物理ダメージ + 2 秒の 30% 減速 |
| アルティメット | Hidden Moonlight | Conceal・Remove CC | 30 / 25 / 20 | 120 / 145 / 170 | 自身の弱体をすべて解除して姿を隠し、移動速度 +65%。2 秒、または攻撃（通常攻撃・アルティメット以外のスキル）で終わる。状態を抜けると Moon Blessing が最大スタックになる |

### 公式が置き換えた値

| 項目 | 以前の実装 | 公式 |
|---|---|---|
| S1 の持続 | 4 秒（調査で「4 秒 / 4〜9 秒」と割れていたので 4 秒） | **4 → 9 秒**（Fandom の `level-scaling`。ランクへ補間: 4 / 5.67 / 7.33 / 9 秒） |
| S1 の追加ダメージ | 汎用 S1 の 1.28 倍 ÷ 4 本（1 本 約 200〜360） | **10 → 35**（+100% 物理攻撃 = 通常攻撃そのもの）の形。基礎だけを換算して通常攻撃に足す |
| S2 のダメージ | 汎用 S2 の元の値 × 0.66、小さな矢 = その 0.15 倍 | **270 → 420(+45%) / 40 → 105(+20%)** の表 |
| 月影 | 70 + 攻撃力 40%（調整値） | **30(+25%物理攻撃)** の形（換算 × 2） |
| マナ | マスターの 50 / 55 / 100（キットで変えられなかった） | **50 → 75 / 80 → 130 / 120・145・170**（`HeroKit.cost`） |

ランクの対応: Velstria のスキルのランクは S1/S2 が 4 段、アルティメットが 3 段（`SkillSlot.maxRank`）。表は線形補間で写す（ランク 1 = Lv1、最大ランク = Lv6。
ランク r → Lv `1 + (r − 1) × 5 / 3`）。公式の表はどれも等差なので、補間は「最初と最後の値を結ぶ直線」と同じ。

## Velstria 実装対応表

H025 月弦のルミナ（レンジャー・遠隔 550・Mana）= Velstria 版の Miya。実装: `Packages/VelstriaCore/Sources/VelstriaCore/Systems/Kits/Kit_H025.swift`、
テスト: `Tests/VelstriaCoreTests/Kits/Kit_H025Tests.swift`、演出: `App/Battle/SkillFX/Heroes/FX_H025.swift`。
スロットは上の調査の順に割り当てる（パッシブ = Moon Blessing「月環の導き」、スキル1 = Moon Arrow「月弦分矢」、スキル2 = Arrow of Eclipse「月蝕の矢」、アルティメット = Hidden Moonlight「隠れ月光」。名前は master の最終名）。
マスターデータの説明文（`.desc`）は共通のまま変えず、アプリ内の説明は `KitText`（ja/en。UI の用語のスキル1 / スキル2 / アルティメット）が持つ。
距離は Velstria 単位（≈ MLBB × 100）。ダメージは Velstria 全体の係数（`Balance.Skills`）に合わせた換算で、MLBB の数値そのままではない。クールダウンは MLBB の秒数そのまま（6 段のランクを Velstria の 4 段・奥義 3 段へ線形補間。全体倍率 `cooldownScale` は 1.0）。
このキットは通常攻撃を整形する（月矢・月影）ので、ロールの「4 発毎の確定会心」は置き換える。

### 対応表（○ = 実装、△ = 簡略化・調整、× = 見送り）

| 元の仕様 | 状態 | Velstria での実装・理由 |
|---|---|---|
| 通常攻撃: 遠隔単体、射程 4.8、攻撃速度上限 3/s | ○ | 射程 550（マスター）。攻撃速度の上限は Velstria 共通の 2.5（`Balance.maxAttackSpeed`） |
| パッシブ: 通常攻撃が命中するたび攻撃速度 +5%、4 秒、最大 5 段 | ○ | `onBasicAttackHit` で 1 段（`ints[0]`）+ `attackSpeedBoost`（段 × 5%、持続 4 秒。最大 25%）。MLBB と同じ（CD が半分だったころは 9%、2026-10 に 5% へ戻した） |
| 段の更新（命中で全段の持続が戻るか: 不明） | △ | 命中のたびに 4 秒へ戻す（`timers[0]`）。持続が切れる（またはステータスが外れる）と全段が消える。死亡で 0 |
| 最大の段では通常攻撃のたびに月影が 30 + 攻撃力 25% の物理ダメージ（Fandom 25% / gameboost 30%: 25% を採用） | △ | `shapeBasicAttack` で `plan.extras` に追加ヒット。公式の形 30(+25%) を `shadowScale` 倍（下の「公式の数値に合わせる」。以前は調整値の 70 + 攻撃力 40%）。会心にならず、命中時効果（吸血・段の加算）を持たない。構造物には働かない |
| 月影の「攻撃効果の継承 25% / 吸血 0%」 | × | 装備の効果層に依存（簡略化してよいと調査にある）。月影は固定のダメージのみ |
| ロールの「4 発毎の確定会心」 | – | キットのパッシブが置き換える（`forceCrit` は nil。会心は装備の確率のみ） |
| S1 Moon Arrow: 自己強化（照準なし）、通常攻撃に矢が 2 本加わる | ○ | `.selfAoE` + `aim: .none` + `.selfRing`（照準リングの半径は通常攻撃の射程と同じ 550。以前は 350。撃てる距離の目安 `reachOverride` は 600）。ボットの奥義の関門が数える周囲の半径（リング × 1.4）は 490 → 770 に広がる（連弾・奥義を始める判断は `botCast` が先に絞るので影響は小さい）。敵が居なくても発動できる（`resolveAim`）。効果中（`timers[1]`）の `shapeBasicAttack` で整形 |
| 主矢: 10〜35（+100% 攻撃力）、周囲の敵に 30% | ○ | 主矢 = 通常攻撃（会心を含む。= 公式の +100% 物理攻撃）+ 追加ダメージ。追加ダメージ（発動時のランクで固定、`reals[0]`）は公式の基礎 10 → 35 をランクで補間し × スロット倍率 4.0 × `s1Scale`（以前は 1 本あたり 汎用 S1 の 1.28 倍 ÷ 標準 4 本）。周囲の敵 = 主矢の対象から 300 以内で最も近い敵 2 体（主矢の対象・構造物を除く、術者の射程 + 150 以内）へ、主矢（追加ダメージ込み・会心の表示も引き継ぐ）の 30% の追尾弾。周囲に敵が居なければ飛ばない |
| 副矢の攻撃効果 20% / スペルヴァンプ 50% | × | 装備の効果層に依存。副矢は命中時効果を持たない（段も積まない） |
| S1 持続 4 秒（Fandom の表は 4〜9 秒）、CD 11 秒（全ランク固定）、再使用は効果が終わるまで不可 | ○ | 持続は Fandom の表 4 → 9 秒をランクで補間（4 / 5.67 / 7.33 / 9 秒。以前は 4 秒固定）。CD は MLBB と同じ 11 秒（CD 短縮を反映、ランクで変わらない）。`canStart` が効果中は false（練習場でも） |
| S1 マナ 50〜75 | ○ | `HeroKit.cost` で 50 → 75 をランクで補間（以前はマスターの 50 のまま） |
| 構造物への月矢 | – | 調査に無い。構造物には追加ダメージも副矢も働かない（攻城の火力は汎用のまま。攻撃速度の段は積む） |
| S2 Arrow of Eclipse: 地点指定の円（遅延あり） | ○ | `.groundAoE` + `aim: .point`、射程 650、半径 170（パッチ履歴の 1.7）、遅延 0.35 秒（調査に秒数なし）。`ZoneSystem` のゾーンで着弾（予告の演出も出る） |
| S2 ダメージ 270〜420 + 45%、1.2 秒の移動不能（攻撃・スキルは可、ブリンク・突進は不可） | ○ | 公式の表 `(270 → 420 + 0.45 × 攻撃力 × 0.6) × 3.0 × s2Scale`（以前は汎用 S2 の元の値の 0.66 倍）+ `root` 1.2 秒。Velstria の `root` は移動と突進・跳躍だけを止め、攻撃・スキル（ブリンクは含む）は止めない。CC 無効には入らない |
| S2 のあと 6 本の小さな矢が散り、それぞれ最初の敵に 40〜105 + 20%、30% スロウ 2 秒 | △ | `Kit.fan` で着弾点から 6 本（中心 = 撃った向き、±30° / ±90° / ±150° の 60° おき）。幅 35、速度 1800、射程 420、貫通しない（最初に当たった敵だけ）。1 本 = 公式の表 `(40 → 105 + 0.20 × 攻撃力 × 0.6) × 3.0 × s2Scale`（以前は着弾の 0.15 倍）、`slow` 30% 2 秒。散る向き・射程は調査に無く、等間隔と仮定。矢は放たれた後なので術者がスタンしても散る（タイマーは非中断）。術者が死亡すると散らない（着弾は止まらない）。着弾点の近くの敵には複数本が当たり得る（1 本 1 回） |
| S2 CD 8 秒、マナ 80〜130 | ○ | CD は MLBB と同じ 8 秒（全ランク固定、`Tune.s2Cooldown`。以前はマスターの CD 8.7 秒 × 0.5 ≒ 4.35 秒）。マナは `HeroKit.cost` で 80 → 130（以前はマスターの 55） |
| 奥義 Hidden Moonlight: 自己発動、全ての弱体を解除、姿を隠す、移動速度 +65%、2 秒 | ○ | `CombatSystem.cleanse`（スタン・ルート・スロウ・沈黙・燃焼・回復阻害・与ダメ低下）+ `armorShred` / `magicShred` を解除。`stealth` 2 秒 + `speedBoost` 0.65 を 2 秒。標準の隠密なので、敵の 250 以内・塔の真視・泉では見え、無敵ではない。**ボット**: 撤退中（敵が 500 以内）に HP 45% 以下、または減速・移動不能を受けていて HP 70% 以下なら `botEscape` の `.castNow` で使う（弱体の解除 + 隠密 + 加速で離脱）。交戦中でも HP 40% 以下なら `botCast` の `.castNow` で汎用の関門（倒せる / 2 体以上）を飛ばして使う。すでに隠れている間は使わない。隠密の描画（自分・味方に半透明で見せる）は App 側の `KitStatusVisuals` が済ませている |
| 隠密は攻撃（通常攻撃・奥義以外のスキル）で解ける | ○ | `KitTags.persistentStealth` は使わない（通常の隠密タグ）ので、`SkillPassives.breakStealth` が通常攻撃の発射・スキルの発動で外す。加速も一緒に終わる。奥義の発動では外れない（発動の後に付与） |
| 隠密が解けた瞬間に月環の導きが最大の段（25% AS・月影つき） | ○ | 時間切れ・攻撃・発動のいずれも `settleHidden` が拾う（`update`、通常攻撃の発射 = `forceCrit`、S1/S2 の発動）。攻撃で解けた場合はその攻撃から月影・月矢がのる（隠密からの最初の一撃が最大の火力）。「入った瞬間も最大の段」（シミュレーション注記）は効果文（解けたとき）に従い見送り |
| 奥義 CD 30/25/20 秒、マナ 120〜170、速度 35〜65%（gameboost）| ○ | CD は MLBB と同じ 30 / 25 / 20 秒（以前は × 0.5 で 15 / 12.5 / 10 秒）。マナは `HeroKit.cost` で 120 / 145 / 170（以前はマスターの 100）。速度は 65% 固定（Fandom） |
| スキルのタグ（UI） | △ | パッシブ `buff`、スキル1 `buff aoe`、スキル2 `disrupt aoe`、アルティメット `buff mobility`（Fandom の Buff / Buff・AOE / CC・AOE / Conceal・Remove CC。隠密・CC 解除はタグの語彙 `KitTag` に無いので、近い バフ・移動 にした） |
| 奥義にダメージは無い | ○ | ダメージ 0。「1 スロットの単体ダメージは汎用の 0.8〜1.3 倍」の予算は奥義には適用しない（自己強化のみ。価値は逃走・位置取りと、最大の段による通常攻撃の火力）。H001〜H006 との 1v1 の TTK は 2.5〜22 秒（CD が半分だったころの帯は 2.5〜15 秒）に収まる |
| 再使用の窓 | – | Miya には無いので使わない（窓は開かない） |

### ダメージの予算

2026-10 から、汎用スキルの比ではなく公式の表の形（下の「公式の数値に合わせる」）。以下は以前の予算（経緯として残す）。

- S1（以前）: 追加ダメージの合計（標準 4 本）= 汎用 S1 の 1.28 倍。CD が汎用（6.5 秒）より長い（11 秒）ぶんを上限近くまで使う。
- S2（以前）: 着弾 0.66 + 小さな矢 0.10 × 6 本 = 最悪（6 本すべてが 1 体に当たる）でも汎用 S2 の元の値の 1.26 倍、標準的な 2 本命中で 0.86 倍。
- 奥義: ダメージ 0（上記）。月影・月矢・攻撃速度が火力になる。
- バランス（計測ハーネス `KitBalanceTests`、同ロール汎用の中央値との差）: 見直し前は Lv1 -27 / Lv6 -25 / Lv12 -14 pt。攻撃速度 6% → 9% / 段と月影 54 + 30% → 70 + 40% で -15 pt 台以内に寄せた（その後 CD を MLBB の秒数にして攻撃速度は 5% へ戻した）。
- 全員との 1v1（静止した撃ち合い・開幕の CC を受ける・kiting なし）では立ち上がりの遅い射手は不利: 総当たり勝率（自分を除く 33 体、`Kit_H025Tests.testRoundRobinWinRateIsReportedAndNotDominant`）は見直し前 Lv1 45% / Lv6 3% / Lv12 2%。同じ条件で汎用レンジャー H003 は Lv6 / 12 で 15〜20%、H030（ライナ）は 3〜15%。反撃しない H001 を倒す速さでは全 34 体の中央付近（Lv6 6.6 秒、中央 6.2 秒 / Lv12 6.8 秒、中央 7.4 秒）で、火力が低いのではなく、開幕の CC とバーストに立ち上がりを潰される。
  H001〜H006 との TTK: Lv1 9.8〜11.8 秒、Lv6 4.7〜7.7 秒、Lv12 4.4〜7.6 秒（`SkillBalanceTests` の 2.5〜22 秒（CD が半分だったころの帯は 2.5〜15 秒）に収まる）。

### 選んだ値（調査に無い・換算した値）

| 項目 | 値 | 理由 |
|---|---|---|
| 攻撃速度 / 段 | 5%（ミヤと同じ） | 2026-10 に 9% → 5%（CD を MLBB の秒数にしたとき） |
| 月影 | 66 + 攻撃力 55%（ミヤ 30 + 25% の × 2.2） | 公式の形のまま Velstria の尺度へ（`shadowScale`）。以前は 70 + 40% |
| S1 の追加ダメージ | 1 本 72 / 132 / 192 / 252（公式 10 → 35 × 4.0 × 1.8） | 公式の形のまま（`s1Scale`）。以前は汎用 S1 の 1.28 倍 ÷ 4 本 |
| S2 の換算 | 着弾・小さな矢とも × 3.0 × 0.34（`s2Scale`） | 公式の 270 → 420(+45%) / 40 → 105(+20%) の形のまま |
| 副矢の範囲 | 主矢の対象から 300、術者の射程 + 150 | 調査に無い（「周囲」）。ミニオンの列に 2 体まで届く広さ |
| S2 の遅延 / 半径 | 0.35 秒 / 170 | 遅延は調査に無い（パッチで 25% 短縮）。半径はパッチ履歴の 1.7 |
| 小さな矢 | 6 本、60° おき、幅 35、速度 1800、射程 420 | 散り方は調査に無い。着弾の半径 170 の外まで届く長さ |
| 説明文の数値 | 名前で引くトークン: パッシブ `{attackSpeedPerStack}` `{stackDuration}` `{maxSpeed}` `{shadowFlat}` `{shadowRatio}` / S1 `{base}` `{duration}` `{splashPercent}` `{splashCount}` `{splashRadius}` / S2 `{base}` `{atkPct}` `{minorBase}` `{minorPct}` `{root}` `{slowPercent}` `{slowDuration}` / 奥義 `{duration}` `{speedPercent}` `{stacks}` | `KitText` のトークンに sim の数値を入れる。文は公式（Fandom）の説明文の構造 |

### 既知の差・リスク

- スキルのマナ（コスト）は 2026-10 から公式の表（`HeroKit.cost`。以前はマスターデータ固定: S1 50、S2 55、奥義 100）。クールダウンは 3 つとも MLBB の秒数（11 / 8 / 30・25・20 秒）。Velstria の最大マナは 500 でレベルで増えないので、MLBB より早くマナが尽きる。
- S1 の持続はランクで 4 → 9 秒に伸びるが、App の演出（`FX_H025.swift` の弓の月光、4 秒）は固定のまま（App はこの変更の範囲外）。
- S2 の名前は共通の「星環シフト25」のまま（ブリンクではなく地点指定の矢）。マスターデータを変えない方針のため。
- 月影・月矢は構造物に働かない（攻城は汎用のレンジャー）。
- S2 を撃った術者が着弾までに死亡すると、着弾（ダメージ・移動不能）は起きるが小さな矢は散らない。
- 副矢は追尾弾なので、飛行中に対象が視界から消える・倒れると消える（主矢と同じ）。
- 1v1 の総当たり勝率は低め（レンジャー共通の傾向。調整後もレンジャー中央値の -15 pt 前後）。
- 満タンの月環の導き（月影）が出た瞬間の専用の演出は無い。月影は通常攻撃の追加ヒット（`DamageSource.basicAttack`）で、演出の `hit` はスキル由来のダメージにしか再生されず、パッシブの演出（頭上の月）は段が増えたとき（5 段目まで）にしか出ない。月影を `.skill(.passive)` にすれば `hit` を出せるが、装備のスキル命中効果（減速・魔防ダウンなど）が通常攻撃のたびに乗るため見送った。ボット戦・ワールド戦・SkillBalanceTests（TTK の帯）は通る。

### 演出（`FX_H025.swift`）

- スキル1 は着弾の無い自己強化: 弓に月光が集まり、主矢（中央・長く太い）と左右の副矢の三条の筋が 0.03 秒ずつずれて前へ走り、矢先に光が灯る。効果中は弓の先に月の粒が流れ続ける（4 秒）。
- S2 は予告（telegraph）= 着弾点の月の輪、着弾（impact）= 六条の矢の筋、矢（travel）= 小さな光の筋、命中（hit）= スロウの月の輪。
- 奥義は月影に紛れる霞と月の輪、2 秒の疾風の筋。照準リングの半径（350）は演出の大きさに使わず、固定値で描く。
- `SkillFXDirector` は `stage / count / duration` をまだ読まないので、レシピの構成だけで機構に合わせた。
### バランス調整

- 計測は `BalanceHarness`（両陣営 × 開始距離 300/450/600 × 種 2、Lv1/6/12）。レンジャー汎用の中央値との差（pt）。見直し前 -27.0 / -25.0 / -14.1（勝率 40.9 / 6.8 / 8.3 %）。
- 攻撃速度 / 段 0.06 → 0.09、月影 54 + 30% → 70 + 40%: 勝率 65.7 / 18.2 / 14.6 %。 試した他の組: 0.08 のみ 54.5 / 9.1 / 11.1、0.10 のみ 60.1 / 12.6 / 12.1、0.10 + 月影 70 + 40% 66.2 / 18.2 / 15.2、0.12 のみ 69.2 / 20.2 / 22.7（Lv12 が中央値を超える）。
  「控えめに −15 pt 以内」を満たす最小に近い値として 0.09 + 月影 70 + 40% を採った。Release の最終計測（レンジャー中央値 71.5 / 30.8 / 22.2 %）: Lv1 67.7 (-3.8) / Lv6 18.2 (-12.6) / Lv12 14.6 (-7.6) pt。開幕 3 秒の瞬間火力の比は Lv1 0.93 / Lv6 1.09 / Lv12 0.98（見直し前 0.93 / 0.86 / 0.95）。S1 の追加ダメージ（汎用の 1.28 倍で上限近く）と S2（最悪 1.26 倍）は触れない。

### クールダウンを MLBB の秒数に（2026-10）

- 全体の CD 倍率 0.5 を廃止し、S1 11 秒・S2 8 秒（以前はマスターの CD）・奥義 30 / 25 / 20 秒にした。1v1 が長くなって段の積み上がる Lv1 が強く（攻撃速度 9% のまま +28 pt、7% でも +20 pt、全員との総当たり 83%）、攻撃速度 / 段を MLBB と同じ 5% に戻した。
- `KitBalanceTests`（レンジャー中央値との差）: 変更前 −2.5 / −13.4 / −8.6 → 変更後 +4.8 / −12.8 / −11.0 pt（Lv1 / 6 / 12）。総当たり（`SkillBalanceTests.duel`）は Lv1 64% / Lv6 18% / Lv12 12%。

### 公式の数値に合わせる（2026-10）

上の「公式（Fandom 現行）の数値」を正として、クールダウン・マナ・S1 の持続・ダメージの表をランクへ線形補間した（方法は H029 ボルグ = Tigreal と同じ）。
ダメージは sim の通常の式 `(公式の基礎 + 係数 × 攻撃力 × 0.6) × スロット倍率` にスキルごとの換算（`LuminaTuning.s1Scale` ほか）を掛ける。数値は Lv1 / Lv12（スキルの自動習得で Lv1 = S1 ランク 1、Lv12 = 最大ランク）の素の能力値。

| 項目 | 公式 | 以前 | 今 |
|---|---|---|---|
| パッシブ 攻撃速度 / 段 | 5%（4 秒・5 段） | 5% | 5%（同じ） |
| 月影 | 30(+25%物理攻撃) | 70 + 攻撃力 40%（Lv1 125） | 30(+25%) × 2.2 = 66 + 攻撃力 55%（Lv1 142） |
| S1 CD | 11 秒（一定） | 11 秒 | 11 秒（同じ） |
| S1 マナ | 50 → 75 | 50（マスター） | 50 / 58.3 / 66.7 / 75 |
| S1 持続 | 4 → 9 秒 | 4 秒 | 4 / 5.67 / 7.33 / 9 秒 |
| S1 主矢の追加ダメージ | 10 → 35（+100% 物理攻撃 = 通常攻撃） | 汎用 S1 × 1.28 ÷ 4（Lv1 204 / Lv12 359） | 72 / 132 / 192 / 252（10 → 35 × 4.0 × 1.8） |
| S1 副矢 | 周囲に 30% | 30%（2 体） | 同じ |
| S2 CD | 8 秒（一定） | 8 秒 | 8 秒（同じ） |
| S2 マナ | 80 → 130 | 55（マスター） | 80 / 96.7 / 113.3 / 130 |
| S2 着弾 | 270 → 420(+45%) | 汎用 S2 の元の値 × 0.66（Lv1 359 / Lv12 628） | (270 → 420 + 0.45 × 攻撃力 × 0.6) × 3.0 × 0.34（Lv1 313 / Lv12 483） |
| S2 小さな矢 × 6 | 40 → 105(+20%) | 着弾の 0.15 倍（Lv1 54 / Lv12 95） | (40 → 105 + 0.20 × 攻撃力 × 0.6) × 3.0 × 0.34（Lv1 58 / Lv12 131） |
| S2 CC | 移動不能 1.2 秒・減速 30% 2 秒 | 同じ | 同じ |
| 奥義 CD / マナ | 30 / 25 / 20 秒・120 / 145 / 170 | 30 / 25 / 20 秒・100（マスター） | 30 / 25 / 20 秒・120 / 145 / 170 |
| 奥義の効果 | 弱体解除・隠密・移動速度 +65%・2 秒 | 同じ | 同じ |
| タグ | Buff / Buff・AOE / CC・AOE / Conceal・Remove CC | なし | `buff` / `buff aoe` / `disrupt aoe` / `buff mobility` |

- 説明文（`KitText` ja/en）は公式の文の構造（「通常攻撃のたびに追加の矢を2本放ち、対象の敵に{base}(+100%物理攻撃)の物理ダメージを与え、周囲の敵に30%のダメージを与える。この効果は{duration}秒間続く。」など）に合わせた。名前は master（月環の導き / 月弦分矢 / 月蝕の矢 / 隠れ月光）。
- 換算の選び方（`KitBalanceTests` の総当たり、レンジャー中央値との差）: 公式の形では S1 の持続と基礎がランクで大きく伸びる（ランク 4 の追加ダメージの合計はランク 1 の約 8 倍）ので、
  以前（Lv1 が強く Lv6・12 が弱い）とは逆に Lv1 が下がり Lv12 が上がる。`s1Scale` 1.0 / 1.5 / 1.8 / 2.0 / 2.5 / 3.0、`s2Scale` 0.30 / 0.34 / 0.39、`shadowScale` 1.5 / 2.0 / 2.2 / 2.5 を比べて
  1.8 / 0.34 / 2.2 にした（例: 2.0 / 0.39 / 2.0 は Lv1 −7 / Lv6 +4 / Lv12 +12）。
- `KitBalanceTests`（Release、レンジャー中央値 63.9 / 38.8 / 28.9 %）: 変更前 +4.8 / −12.8 / −11.0 → 変更後 57.1 / 44.4 / 37.4 % = **−6.8 / +5.7 / +8.5 pt**（Lv1 / 6 / 12）。開幕 3 秒の瞬間火力（同ロール中央値との比）0.57 / 0.84 / 1.00。
