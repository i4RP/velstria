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

## Velstria 実装対応表

H025 月弦のルミナ（レンジャー・遠隔 550・Mana）= Velstria 版の Miya。実装: `Packages/VelstriaCore/Sources/VelstriaCore/Systems/Kits/Kit_H025.swift`、
テスト: `Tests/VelstriaCoreTests/Kits/Kit_H025Tests.swift`、演出: `App/Battle/SkillFX/Heroes/FX_H025.swift`。
スロットは上の調査の順に割り当てる（パッシブ = Moon Blessing「月環の導き」、スキル1 = Moon Arrow「月弦分矢」、スキル2 = Arrow of Eclipse「月蝕の矢」、アルティメット = Hidden Moonlight「隠れ月光」。名前は master の最終名）。
マスターデータの説明文（`.desc`）は共通のまま変えず、アプリ内の説明は `KitText`（ja/en。UI の用語のスキル1 / スキル2 / アルティメット）が持つ。
距離は Velstria 単位（≈ MLBB × 100）。ダメージ・クールダウンは Velstria 全体の係数（`Balance.Skills`）に合わせた換算で、MLBB の数値そのままではない。
このキットは通常攻撃を整形する（月矢・月影）ので、ロールの「4 発毎の確定会心」は置き換える。

### 対応表（○ = 実装、△ = 簡略化・調整、× = 見送り）

| 元の仕様 | 状態 | Velstria での実装・理由 |
|---|---|---|
| 通常攻撃: 遠隔単体、射程 4.8、攻撃速度上限 3/s | ○ | 射程 550（マスター）。攻撃速度の上限は Velstria 共通の 2.5（`Balance.maxAttackSpeed`） |
| パッシブ: 通常攻撃が命中するたび攻撃速度 +5%、4 秒、最大 5 段 | △ | `onBasicAttackHit` で 1 段（`ints[0]`）+ `attackSpeedBoost`（段 × 9%、持続 4 秒）。1 段 9%（最大 45%）に調整: Velstria は TTK が短く立ち上がりが遅いと火力が出ない（当初 6% → 総当たり勝率の見直しで 9%） |
| 段の更新（命中で全段の持続が戻るか: 不明） | △ | 命中のたびに 4 秒へ戻す（`timers[0]`）。持続が切れる（またはステータスが外れる）と全段が消える。死亡で 0 |
| 最大の段では通常攻撃のたびに月影が 30 + 攻撃力 25% の物理ダメージ（Fandom 25% / gameboost 30%: 25% を採用） | △ | `shapeBasicAttack` で `plan.extras` に追加ヒット。**70 + 攻撃力 40%** に調整（ミヤは攻撃力 115 に対し約 0.5 倍、ルミナは 138〜200 に対し約 0.9 倍。当初 54 + 30%）。会心にならず、命中時効果（吸血・段の加算）を持たない。構造物には働かない |
| 月影の「攻撃効果の継承 25% / 吸血 0%」 | × | 装備の効果層に依存（簡略化してよいと調査にある）。月影は固定のダメージのみ |
| ロールの「4 発毎の確定会心」 | – | キットのパッシブが置き換える（`forceCrit` は nil。会心は装備の確率のみ） |
| S1 Moon Arrow: 自己強化（照準なし）、通常攻撃に矢が 2 本加わる | ○ | `.selfAoE` + `aim: .none` + `.selfRing`（照準リングの半径は通常攻撃の射程と同じ 550。以前は 350。撃てる距離の目安 `reachOverride` は 600）。ボットの奥義の関門が数える周囲の半径（リング × 1.4）は 490 → 770 に広がる（連弾・奥義を始める判断は `botCast` が先に絞るので影響は小さい）。敵が居なくても発動できる（`resolveAim`）。効果中（`timers[1]`）の `shapeBasicAttack` で整形 |
| 主矢: 10〜35（+100% 攻撃力）、周囲の敵に 30% | △ | 主矢 = 通常攻撃（会心を含む）+ 追加ダメージ。追加ダメージ（発動時のランク・能力値で固定、`reals[0]`）は 1 本あたり 汎用 S1 の 1.28 倍 ÷ 標準 4 本。周囲の敵 = 主矢の対象から 300 以内で最も近い敵 2 体（主矢の対象・構造物を除く、術者の射程 + 150 以内）へ、主矢（追加ダメージ込み・会心の表示も引き継ぐ）の 30% の追尾弾。周囲に敵が居なければ飛ばない |
| 副矢の攻撃効果 20% / スペルヴァンプ 50% | × | 装備の効果層に依存。副矢は命中時効果を持たない（段も積まない） |
| S1 持続 4 秒（Fandom の表は 4〜9 秒: 4 秒を採用）、CD 11 秒（全ランク固定）、再使用は効果が終わるまで不可 | ○ | 4 秒。CD は 11 秒 × `cooldownScale`（0.5）= 5.5 秒（CD 短縮を反映、ランクで変わらない）。`canStart` が効果中は false（練習場でも） |
| S1 マナ 50〜75 | △ | マスターのコスト（50）のまま: 消費量は `SkillSystem.validate` がマスターから決めるのでキットでは変えられない |
| 構造物への月矢 | – | 調査に無い。構造物には追加ダメージも副矢も働かない（攻城の火力は汎用のまま。攻撃速度の段は積む） |
| S2 Arrow of Eclipse: 地点指定の円（遅延あり） | ○ | `.groundAoE` + `aim: .point`、射程 650、半径 170（パッチ履歴の 1.7）、遅延 0.35 秒（調査に秒数なし）。`ZoneSystem` のゾーンで着弾（予告の演出も出る） |
| S2 ダメージ 270〜420 + 45%、1.2 秒の移動不能（攻撃・スキルは可、ブリンク・突進は不可） | ○ | 汎用 S2 の元の値（`base ÷ empowerRatio`）の 0.66 倍 + `root` 1.2 秒。Velstria の `root` は移動と突進・跳躍だけを止め、攻撃・スキル（ブリンクは含む）は止めない。CC 無効には入らない |
| S2 のあと 6 本の小さな矢が散り、それぞれ最初の敵に 40〜105 + 20%、30% スロウ 2 秒 | △ | `Kit.fan` で着弾点から 6 本（中心 = 撃った向き、±30° / ±90° / ±150° の 60° おき）。幅 35、速度 1800、射程 420、貫通しない（最初に当たった敵だけ）。1 本 = 着弾の 0.15 倍（ミヤ 40/270）、`slow` 30% 2 秒。散る向き・射程は調査に無く、等間隔と仮定。矢は放たれた後なので術者がスタンしても散る（タイマーは非中断）。術者が死亡すると散らない（着弾は止まらない）。着弾点の近くの敵には複数本が当たり得る（1 本 1 回） |
| S2 CD 8 秒、マナ 80〜130 | △ | CD・コストはマスターのまま（CD 約 4.35 秒、コスト 55） |
| 奥義 Hidden Moonlight: 自己発動、全ての弱体を解除、姿を隠す、移動速度 +65%、2 秒 | ○ | `CombatSystem.cleanse`（スタン・ルート・スロウ・沈黙・燃焼・回復阻害・与ダメ低下）+ `armorShred` / `magicShred` を解除。`stealth` 2 秒 + `speedBoost` 0.65 を 2 秒。標準の隠密なので、敵の 250 以内・塔の真視・泉では見え、無敵ではない。**ボット**: 撤退中（敵が 500 以内）に HP 45% 以下、または減速・移動不能を受けていて HP 70% 以下なら `botEscape` の `.castNow` で使う（弱体の解除 + 隠密 + 加速で離脱）。交戦中でも HP 40% 以下なら `botCast` の `.castNow` で汎用の関門（倒せる / 2 体以上）を飛ばして使う。すでに隠れている間は使わない。隠密の描画（自分・味方に半透明で見せる）は App 側の `KitStatusVisuals` が済ませている |
| 隠密は攻撃（通常攻撃・奥義以外のスキル）で解ける | ○ | `KitTags.persistentStealth` は使わない（通常の隠密タグ）ので、`SkillPassives.breakStealth` が通常攻撃の発射・スキルの発動で外す。加速も一緒に終わる。奥義の発動では外れない（発動の後に付与） |
| 隠密が解けた瞬間に月環の導きが最大の段（25% AS・月影つき） | ○ | 時間切れ・攻撃・発動のいずれも `settleHidden` が拾う（`update`、通常攻撃の発射 = `forceCrit`、S1/S2 の発動）。攻撃で解けた場合はその攻撃から月影・月矢がのる（隠密からの最初の一撃が最大の火力）。「入った瞬間も最大の段」（シミュレーション注記）は効果文（解けたとき）に従い見送り |
| 奥義 CD 30/25/20 秒、マナ 120〜170、速度 35〜65%（gameboost）| △ | CD は 30 → 20 秒を 3 ランクで線形 × 0.5（15 / 12.5 / 10 秒）。コストはマスター（100）。速度は 65% 固定（Fandom） |
| 奥義にダメージは無い | ○ | ダメージ 0。「1 スロットの単体ダメージは汎用の 0.8〜1.3 倍」の予算は奥義には適用しない（自己強化のみ。価値は逃走・位置取りと、最大の段による通常攻撃の火力）。H001〜H006 との 1v1 の TTK は 2.5〜15 秒に収まる |
| 再使用の窓 | – | Miya には無いので使わない（窓は開かない） |

### ダメージの予算

- S1: 追加ダメージの合計（標準 4 本）= 汎用 S1 の 1.28 倍。CD が汎用（3.25 秒）より長い（5.5 秒）ぶんを上限近くまで使う。標準 = 基礎の攻撃速度で 4 秒に撃つ本数で、攻撃速度の段が積もると 6 本前後まで増える（持続火力は攻撃速度に比例する、が Miya の個性）。
- S2: 着弾 0.66 + 小さな矢 0.10 × 6 本 = 最悪（6 本すべてが 1 体に当たる）でも汎用 S2 の元の値の 1.26 倍、標準的な 2 本命中で 0.86 倍。
- 奥義: ダメージ 0（上記）。月影・月矢・攻撃速度が火力になる。
- バランス（計測ハーネス `KitBalanceTests`、同ロール汎用の中央値との差）: 見直し前は Lv1 -27 / Lv6 -25 / Lv12 -14 pt。攻撃速度 6% → 9% / 段と月影 54 + 30% → 70 + 40% で、下の「バランス調整」の表のとおり -15 pt 台以内に寄せた。
- 全員との 1v1（静止した撃ち合い・開幕の CC を受ける・kiting なし）では立ち上がりの遅い射手は不利: 総当たり勝率（自分を除く 33 体、`Kit_H025Tests.testRoundRobinWinRateIsReportedAndNotDominant`）は見直し前 Lv1 45% / Lv6 3% / Lv12 2%。同じ条件で汎用レンジャー H003 は Lv6 / 12 で 15〜20%、H030（ライナ）は 3〜15%。反撃しない H001 を倒す速さでは全 34 体の中央付近（Lv6 6.6 秒、中央 6.2 秒 / Lv12 6.8 秒、中央 7.4 秒）で、火力が低いのではなく、開幕の CC とバーストに立ち上がりを潰される。
  H001〜H006 との TTK: Lv1 9.8〜11.8 秒、Lv6 4.7〜7.7 秒、Lv12 4.4〜7.6 秒（`SkillBalanceTests` の 2.5〜15 秒に収まる）。

### 選んだ値（調査に無い・換算した値）

| 項目 | 値 | 理由 |
|---|---|---|
| 攻撃速度 / 段 | 9%（ミヤ 5%） | 立ち上がりを早めるための調整。勝率の見直しで 6% → 9% |
| 月影 | 70 + 攻撃力 40%（ミヤ 30 + 25%） | 同上。54 + 30% → 70 + 40% |
| S1 の追加ダメージ | 汎用 S1 の 1.28 倍 ÷ 4 本 | 上の予算 |
| 副矢の範囲 | 主矢の対象から 300、術者の射程 + 150 | 調査に無い（「周囲」）。ミニオンの列に 2 体まで届く広さ |
| S2 の遅延 / 半径 | 0.35 秒 / 170 | 遅延は調査に無い（パッチで 25% 短縮）。半径はパッチ履歴の 1.7 |
| 小さな矢 | 6 本、60° おき、幅 35、速度 1800、射程 420 | 散り方は調査に無い。着弾の半径 170 の外まで届く長さ |
| 説明文の数値 | パッシブ x0 = 1 段の攻撃速度、x1 = 持続、x2 = 月影の固定値、x3 = 月影の攻撃力比 / S1 x0 = 持続、x1 = 副矢の割合、x2 = 副矢の数、x3 = 範囲 / S2 x0 = 小さな矢のダメージ（整数）、x1 = 移動不能、x2 = スロウ %、x3 = スロウ秒 / 奥義 x0 = 持続、x1 = 速度 %、x2 = 最大の段 | `KitText` のトークンに sim の数値を入れる |

### 既知の差・リスク

- スキルのマナ（コスト）は再現できない（マスターデータ固定: S1 50、S2 55、奥義 100）。S2 の CD も汎用のまま。
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
