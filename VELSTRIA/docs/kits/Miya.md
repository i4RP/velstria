# Miya (MLBB) - Kit Specification

> 2026-10-14: ヒーローの能力値（HP・物理攻撃・防御・魔防・攻撃速度・HP 回復・マナ・移動速度・射程・リソースの種類）と能力値の式（防御 120/(120+防御)・クリティカル 200%・攻撃速度の加算・移動速度の加算式など）を MLBB の値へ置き換えた（`docs/HERO_STATS.md`）。この文書の能力値の記述（「マスターの値」「射程 550」「最大マナ 500 でレベルで増えない」など）は置き換え前のもの。
> 2026-10-14（スキルの段階）: **公式の表をそのまま使う（スキル1・2 = 6 段、アルティメット = 3 段）**。ダメージは公式の基礎 + 公式の係数 × 合計の物理攻撃そのもの（スロット倍率・物理係数の × 0.6・キットの倍率 `shadowScale` / `s1Scale` / `s2Scale`・ランクの補間はすべて撤廃）。詳しくは末尾の「公式の表をそのまま使う（2026-10-14）」。換算の値を選んだ節（「ダメージの予算」「選んだ値」「バランス調整」）は消し、末尾の「経緯」に何を変えたかだけを残した。

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
- Attack-effect inheritance (25%/20%) is item-system dependent and can be simplified. (2026-10-14: implemented with the JP-client ratios, shadow 20% / split arrows 30%, via `HitPayload.attackEffect`. The immobilize is now a bind that also blocks blinks.)

## Sources
- https://mobile-legends.fandom.com/wiki/Miya
- https://mobile-legends.fandom.com/wiki/Miya/Patch_history
- https://gameboost.com/blog/mlbb-guide-miya
- https://www.oneesports.gg/mobile-legends/miya-guide-best-build-mlbb/ (descriptions only, no numbers)

## 公式（日本語クライアント）の数値

マイヤ(Miya)、ロール「ハンター」、サブタグ「追撃/ダメージ」。2026-10-10 に受け取った日本語クライアントの実機のスクリーンショット（スキル詳細の画面）の転記（スキルのレベルは S1・S2 が Lv1〜6、
アルティメットが Lv1〜3）。**下の Fandom の値と違うところはこちらを正とする**（違い: 月影 30(+25%) → 25(+20%)、S1 の MP 50 → 75 → 60 → 85）。
アイコンのタグは バフ / バフ / 妨害 / 隠れ身。S2 の MP はこの画面では吹き出しで隠れていて読めなかったので、Fandom の 80 → 130 にしていた
（2026-10-11 の無加工の原本で **90（全 Lv 一定）** と読めた。下の「日本語クライアントの画面（2026-10-11・無加工の原本）」）。

| スロット | 公式名 | タグ | 内容 |
|---|---|---|---|
| パッシブ | スイフト | バフ | 通常攻撃が対象に命中するたび、4秒間、攻撃速度が5%上昇する（最大5スタック）。最大スタック時、通常攻撃のたびにムーンライトシャドウを召喚して対象を攻撃し、25(+20%物理攻撃)の物理ダメージを与える。ムーンライトシャドウは攻撃効果の20%を引き継ぐ。 |
| スキル1 | スプリットショット | バフ・範囲技 | CD 11.0、MP 60 / 65 / 70 / 75 / 80 / 85、基礎ダメージ 10 / 15 / 20 / 25 / 30 / 35、持続時間 4 / 5 / 6 / 7 / 8 / 9 秒。通常攻撃時、追加で分裂の矢を2本放つ。各矢は攻撃効果の30%を引き継ぎ、メインターゲットに10(+100%物理攻撃)の物理ダメージ、その他の対象に30%のダメージを与える。この効果は4秒間持続する。 |
| スキル2 | レインアロー | 妨害・範囲技 | CD 8.0、基礎ダメージ 270 / 300 / 330 / 360 / 390 / 420、弓撃ダメージ 40 / 53 / 66 / 79 / 92 / 105。指定エリアに月蝕の力を呼び起こし、範囲内の敵に270(+45%物理攻撃)の物理ダメージを与え、1.2秒間バインド状態にする。その後、攻撃は6本の矢に分裂して様々な方向へ飛んでいく。各矢は40(+20%物理攻撃)の物理ダメージを与え、命中した敵の移動速度を2秒間30%低下させる。 |
| アルティメット | 隠月 | 隠れ身・コントロール解除 | CD 30 / 25 / 20、MP 120 / 145 / 170。すべてのデバフを解除し、隠蔽状態になる。最大2秒間、移動速度が65%上昇する（攻撃すると状態が早期終了する）。隠蔽状態が終了すると、最大スタックのスイフトを獲得する。 |

## 日本語クライアントの画面（2026-10-11・無加工の原本）

2026-10-11 に受け取った、日本語クライアントのスキル詳細の画面の無加工のスクリーンショット（IMG_4484〜4491。画像はコミットしない）。上の表（2026-10-10 の画面）と照合し、
数値・タグ・文はすべて一致した。違いは S2 レインアローの MP だけ: 画面の「スキンを切り替えると、各スキルのエフェクトを確認できます。」の吹き出しの**半透明の裏に「MP消費量：90」が読める**
（IMG_4488・4491。拡大して確認）。S2 の表に MP の行が無い（= 全 Lv で同じ）ので、MP は **全 Lv 90**。Fandom の 80 → 130 は古い値。

| 枠 | 日本語版の名前 | タグ | CD | MP | 内容（原本の文の要約） |
|---|---|---|---|---|---|
| パッシブ | スイフト | バフ | – | – | 通常攻撃が命中するたび 4 秒間 攻撃速度 +5%（最大 5 スタック）。最大スタック時、通常攻撃のたびにムーンライトシャドウが 25 (+20% 物理攻撃) の物理ダメージ（攻撃効果の 20% を引き継ぐ） |
| スキル1 | スプリットショット | バフ・範囲技 | 11.0（一定） | 60 / 65 / 70 / 75 / 80 / 85 | 通常攻撃時に分裂の矢を 2 本。メインターゲットに 10 / 15 / 20 / 25 / 30 / 35 (+100% 物理攻撃)、その他の対象に 30%。持続 4 / 5 / 6 / 7 / 8 / 9 秒 |
| スキル2 | レインアロー | 妨害・範囲技 | 8.0（一定） | **90（一定。吹き出しの裏）** | 範囲の敵に 270 / 300 / 330 / 360 / 390 / 420 (+45% 物理攻撃) + 1.2 秒バインド。その後 6 本の矢がそれぞれ 40 / 53 / 66 / 79 / 92 / 105 (+20% 物理攻撃) + 2 秒 30% 減速 |
| アルティメット | 隠月 | 隠れ身・コントロール解除 | 30 / 25 / 20 | 120 / 145 / 170 | すべてのデバフを解除し隠蔽状態。最大 2 秒 移動速度 +65%（攻撃で早期終了）。隠蔽状態が終わると最大スタックのスイフト |

置き換えた値（変更前 → 変更後）:

| 項目 | 変更前 | 変更後 |
|---|---|---|
| S2 の MP | Fandom の 80 / 90 / 100 / 110 / 120 / 130（当時のランク 1〜4: 80 / 96.7 / 113.3 / 130） | **90（全 Lv）**（`LuminaTuning.s2Cost` = [90]） |
| アルティメットの文 | 「隠密状態になる」「隠密状態が終了すると」 | 原本どおり「**隠蔽**状態になる」「隠蔽状態が終了すると」 |

ほかの数値・タグ（`buff` / `buff aoe` / `disrupt aoe` / `conceal cleanse`）は変えていない。バランスは下の「日本語クライアントの原本へ（2026-10-11）」。

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
| S1 の持続 | 4 秒（調査で「4 秒 / 4〜9 秒」と割れていたので 4 秒） | **4 / 5 / 6 / 7 / 8 / 9 秒**（Fandom の `level-scaling`。日本語クライアントも同じ） |
| S1 の追加ダメージ | 汎用 S1 の 1.28 倍 ÷ 4 本（1 本 約 200〜360） | **10 / 15 / 20 / 25 / 30 / 35**（+100% 物理攻撃 = 通常攻撃そのもの）。通常攻撃に足す |
| S2 のダメージ | 汎用 S2 の元の値 × 0.66、小さな矢 = その 0.15 倍 | **270〜420(+45%) / 40〜105(+20%)** の表 |
| 月影 | 70 + 攻撃力 40%（調整値） | **30(+25%物理攻撃)**（Fandom。日本語クライアントは 25(+20%)） |
| マナ | マスターの 50 / 55 / 100（キットで変えられなかった） | **50 → 75 / 80 → 130 / 120・145・170**（Fandom。日本語クライアントは 60 → 85 / 90 / 120・145・170） |

段の対応: 2026-10-14 から Velstria のスキルの段は MLBB と同じ（S1/S2 = 6 段、アルティメット = 3 段。`SkillSlot.maxRank`）。rank = 公式の Lv で、表をそのまま引く（`Kit.level`。補間しない）。
それより前は S1/S2 が 4 段で、表を線形補間していた（ランク r → Lv `1 + (r − 1) × 5 / 3`）。

## Velstria 実装対応表

H025 月弦のルミナ（レンジャー・遠隔 550・Mana）= Velstria 版の Miya。実装: `Packages/VelstriaCore/Sources/VelstriaCore/Systems/Kits/Kit_H025.swift`、
テスト: `Tests/VelstriaCoreTests/Kits/Kit_H025Tests.swift`、演出: `App/Battle/SkillFX/Heroes/FX_H025.swift`。
スロットは上の調査の順に割り当てる（パッシブ = Moon Blessing「月環の導き」、スキル1 = Moon Arrow「月弦分矢」、スキル2 = Arrow of Eclipse「月蝕の矢」、アルティメット = Hidden Moonlight「隠れ月光」。名前は master の最終名）。
マスターデータの説明文（`.desc`）は共通のまま変えず、アプリ内の説明は `KitText`（ja/en。UI の用語のスキル1 / スキル2 / アルティメット）が持つ。
距離は Velstria 単位（≈ MLBB × 100）。**数値は公式の表をそのまま使う（6 / 6 / 3 段）**: ダメージは公式の基礎[Lv] + 公式の係数 × 合計の物理攻撃（`Kit.official`。換算なし）、クールダウン・マナ・S1 の持続も公式の表（`Kit.level` / `Kit.cooldown`。CD 短縮だけを掛ける）。
このキットは通常攻撃を整形する（月矢・月影）ので、ロールの「4 発毎の確定会心」は置き換える。

### 対応表（○ = 実装、△ = 簡略化・調整、× = 見送り）

| 元の仕様 | 状態 | Velstria での実装・理由 |
|---|---|---|
| 通常攻撃: 遠隔単体、射程 4.8、攻撃速度上限 3/s | ○ | 射程 550（マスター）。攻撃速度の上限は Velstria 共通の 2.5（`Balance.maxAttackSpeed`） |
| パッシブ: 通常攻撃が命中するたび攻撃速度 +5%、4 秒、最大 5 段 | ○ | `onBasicAttackHit` で 1 段（`ints[0]`）+ `attackSpeedBoost`（段 × 5%、持続 4 秒。最大 25%）。MLBB と同じ（CD が半分だったころは 9%、2026-10 に 5% へ戻した） |
| 段の更新（命中で全段の持続が戻るか: 不明） | △ | 命中のたびに 4 秒へ戻す（`timers[0]`）。持続が切れる（またはステータスが外れる）と全段が消える。死亡で 0 |
| 最大の段では通常攻撃のたびに月影が 25 + 攻撃力 20% の物理ダメージ（日本語クライアント。Fandom の 30 + 25% は古い値） | ○ | `shapeBasicAttack` で `plan.extras` に追加ヒット。公式 25(+20% 合計の物理攻撃) そのまま（2026-10-14 に換算 `shadowScale` 2.6 を撤廃）。会心にならない（公式の文に会心の記述が無い。未検証）。通常攻撃そのものではない（段・命中数・パッシブの命中フックに数えない）。構造物には働かない（推測） |
| 月影の「攻撃効果の20%を引き継ぐ」 | ○ | `HitPayload.attackEffect` = 0.2（source `.basicAttack`、`appliesOnHit` = false）: 装備の命中時効果（追加ダメージ・回復・減速）と通常攻撃吸収を 20% だけ与える。説明文にも「「月影」は攻撃効果の20%を引き継ぐ」と書く |
| ロールの「4 発毎の確定会心」 | – | キットのパッシブが置き換える（`forceCrit` は nil。会心は装備の確率のみ） |
| S1 Moon Arrow: 自己強化（照準なし）、通常攻撃に矢が 2 本加わる | ○ | `.selfAoE` + `aim: .none` + `.selfRing`（照準リングの半径は通常攻撃の射程と同じ 550。以前は 350。撃てる距離の目安 `reachOverride` は 600）。ボットの奥義の関門が数える周囲の半径（リング × 1.4）は 490 → 770 に広がる（連弾・奥義を始める判断は `botCast` が先に絞るので影響は小さい）。敵が居なくても発動できる（`resolveAim`）。効果中（`timers[1]`）の `shapeBasicAttack` で整形 |
| 主矢: 10〜35（+100% 攻撃力）、周囲の敵に 30% | ○ | 主矢 = 通常攻撃（会心を含む。= 公式の +100% 物理攻撃）+ 追加ダメージ。追加ダメージ（発動時のランクで固定、`reals[0]`）は公式の基礎 10 / 15 / 20 / 25 / 30 / 35 そのまま（2026-10-14 に × スロット倍率 4.0 × `s1Scale` 1.8 を撤廃）。会心の後に足す（基礎が会心で増えるかは未検証）。周囲の敵 = 主矢の対象から 300 以内で最も近い敵 2 体（主矢の対象・構造物を除く、術者の射程 + 150 以内。推測）へ、主矢（追加ダメージ込み・会心の表示も引き継ぐ）の 30% の追尾弾。周囲に敵が居なければ飛ばない |
| 副矢の「各矢は攻撃効果の30%を引き継ぎ」（日本語クライアント） | ○ | 副矢の `HitPayload.attackEffect` = 0.3（source `.basicAttack`、`appliesOnHit` = false）: 装備の命中時効果と通常攻撃吸収を 30% だけ与える。段・命中数には数えない。説明文にも書く。主矢は通常攻撃そのもの（100%） |
| 副矢のスペルヴァンプ 50% / 通常攻撃吸収 0%（Fandom の `spell-vamp-ratio` / `lifesteal-ratio`） | × | 日本語クライアントの文に無い。副矢・月影は通常攻撃のダメージなのでスキル吸収は掛からない。通常攻撃吸収は共通の `attackEffect` が攻撃エフェクトと同じ割合（20% / 30%）で掛ける（Fandom の 0% と違う。下の「まだ MLBB と違うところ」） |
| S1 持続 4 / 5 / 6 / 7 / 8 / 9 秒、CD 11 秒（全 Lv 一定）、再使用は効果が終わるまで不可 | ○ | 持続は公式の表をそのまま（`Kit.level`。2026-10-14 まではランクへ補間）。CD は MLBB と同じ 11 秒（CD 短縮を反映、ランクで変わらない）。`canStart` が効果中は false（練習場でも） |
| S1 マナ 60 / 65 / 70 / 75 / 80 / 85（日本語クライアント。Fandom の 50〜75 は古い値） | ○ | `HeroKit.cost` で公式の表をそのまま（以前は補間、その前は Fandom の 50 → 75、その前はマスターの 50） |
| 構造物への月矢 | △ | 調査に無い（推測・未検証）。構造物には追加ダメージも副矢も働かない（攻城の火力は汎用のまま。攻撃速度の段は積む） |
| S2 Arrow of Eclipse: 地点指定の円（遅延あり） | ○ | `.groundAoE` + `aim: .point`、射程 650、半径 170（パッチ履歴の 1.7）、遅延 0.35 秒（調査に秒数なし）。`ZoneSystem` のゾーンで着弾（予告の演出も出る） |
| S2 ダメージ 270〜420 + 45%、1.2 秒のバインド（移動・ブリンク・アサルトスキル不可、スキルは中断されない） | ○ | 公式の表そのまま `270 / 300 / 330 / 360 / 390 / 420 + 0.45 × 合計の物理攻撃`（2026-10-14 に × 0.6 × 3.0 × `s2Scale` 0.30 を撤廃）+ 敵に付ける `root` 1.2 秒 = バインド（`Unit.isBound`: 移動・術者を動かすスキル（突進・跳躍・ブリンク）・瞬歩を封じる。攻撃と移動しないスキルは使える。低レベルのコントロールなので中断しない）。以前は共通の `root` がブリンクを止めなかった（既知の差だった）が、2026-10-14 の共通の土台で直った。説明文も「移動できないが、攻撃とスキルは使える」→「移動・ブリンク・アサルトスキルが使えない。スキルは中断されない」。CC 無効には入らない |
| S2 のあと 6 本の小さな矢が散り、それぞれ最初の敵に 40〜105 + 20%、30% スロウ 2 秒 | △ | `Kit.fan` で着弾点から 6 本（中心 = 撃った向き、±30° / ±90° / ±150° の 60° おき）。幅 35、速度 1800、射程 420、貫通しない（最初に当たった敵だけ）。1 本 = 公式の表そのまま `40 / 53 / 66 / 79 / 92 / 105 + 0.20 × 合計の物理攻撃`（2026-10-14 に換算を撤廃）、`slow` 30% 2 秒。散る向き・射程は調査に無く、等間隔と仮定。矢は放たれた後なので術者がスタンしても散る（タイマーは非中断）。術者が死亡すると散らない（着弾は止まらない）。着弾点の近くの敵には複数本が当たり得る（1 本 1 回） |
| S2 CD 8 秒、マナ 90（全 Lv。日本語クライアントの原本） | ○ | CD は MLBB と同じ 8 秒（全 Lv 一定、`LuminaTuning.s2Cooldown` = [8]）。マナは `HeroKit.cost` で全 Lv 90（2026-10-11 に原本の吹き出しの裏から読んだ値。以前は Fandom の 80 → 130、その前はマスターの 55） |
| 奥義 Hidden Moonlight: 自己発動、全ての弱体を解除、姿を隠す、移動速度 +65%、2 秒 | ○ | `CombatSystem.cleanse`（スタン・ルート・スロウ・沈黙・燃焼・回復阻害・与ダメ低下）+ `armorShred` / `magicShred` を解除。`stealth` 2 秒 + `speedBoost` 0.65 を 2 秒。標準の隠密なので、敵の 250 以内・塔の真視・泉では見え、無敵ではない。**ボット**: 撤退中（敵が 500 以内）に HP 45% 以下、または減速・移動不能を受けていて HP 70% 以下なら `botEscape` の `.castNow` で使う（弱体の解除 + 隠密 + 加速で離脱）。交戦中でも HP 40% 以下なら `botCast` の `.castNow` で汎用の関門（倒せる / 2 体以上）を飛ばして使う。すでに隠れている間は使わない。隠密の描画（自分・味方に半透明で見せる）は App 側の `KitStatusVisuals` が済ませている |
| 隠密は攻撃（通常攻撃・奥義以外のスキル）で解ける | ○ | `KitTags.persistentStealth` は使わない（通常の隠密タグ）ので、`SkillPassives.breakStealth` が通常攻撃の発射・スキルの発動で外す。加速も一緒に終わる。奥義の発動では外れない（発動の後に付与） |
| 隠密が解けた瞬間に月環の導きが最大の段（25% AS・月影つき） | ○ | 時間切れ・攻撃・発動のいずれも `settleHidden` が拾う（`update`、通常攻撃の発射 = `forceCrit`、S1/S2 の発動）。攻撃で解けた場合はその攻撃から月影・月矢がのる（隠密からの最初の一撃が最大の火力）。「入った瞬間も最大の段」（シミュレーション注記）は効果文（解けたとき）に従い見送り |
| 奥義 CD 30/25/20 秒、マナ 120〜170、速度 35〜65%（gameboost）| ○ | CD は MLBB と同じ 30 / 25 / 20 秒（以前は × 0.5 で 15 / 12.5 / 10 秒）。マナは `HeroKit.cost` で 120 / 145 / 170（以前はマスターの 100）。速度は 65% 固定（Fandom・日本語クライアント） |
| スキルのタグ（UI） | ○ | パッシブ `buff`、スキル1 `buff aoe`、スキル2 `disrupt aoe`、アルティメット `conceal cleanse`（日本語クライアントの バフ / バフ・範囲技 / 妨害・範囲技 / 隠れ身・コントロール解除 = Fandom の Buff / Buff・AOE / CC・AOE / Conceal・Remove CC。以前は隠密・CC 解除のキーが無く バフ・移動 で近似していた） |
| 奥義にダメージは無い | ○ | ダメージ 0（自己強化のみ。価値は逃走・位置取りと、最大の段による通常攻撃の火力） |
| 再使用の窓 | – | Miya には無いので使わない（窓は開かない） |

### 推測の値（公式の文に無い値）

数値（ダメージ・CD・マナ・持続・割合）は公式の表そのまま（末尾の「公式の表をそのまま使う（2026-10-14）」）。換算の値（以前の `shadowScale` / `s1Scale` / `s2Scale`）は無い。下は公式の文に無く、Velstria が決めた値。

| 項目 | 値 | 理由 |
|---|---|---|
| 副矢の範囲 | 主矢の対象から 300 以内で近い 2 体、術者の射程 + 150 以内 | 調査に無い（「その他の対象」）。ミニオンの列に 2 体まで届く広さ。説明文の「周囲300以内で近い2体」は Velstria の但し書き |
| S2 の遅延 / 半径 / 射程 | 0.35 秒 / 170 / 650 | 遅延は調査に無い（パッチで 25% 短縮）。半径はパッチ履歴の 1.7。射程はマスター |
| 小さな矢 | 6 本、60° おき、幅 35、速度 1800、射程 420 | 散り方は調査に無い。着弾の半径 170 の外まで届く長さ |
| 説明文の数値 | 名前で引くトークン: パッシブ `{attackSpeedPerStack}` `{stackDuration}` `{maxSpeed}` `{shadowFlat}` `{shadowRatio}` `{shadowEffect}` / S1 `{base}` `{duration}` `{splashPercent}` `{splashEffect}` `{splashCount}` `{splashRadius}` / S2 `{base}` `{atkPct}` `{minorBase}` `{minorPct}` `{root}` `{slowPercent}` `{slowDuration}` / 奥義 `{duration}` `{speedPercent}` `{stacks}` | `KitText` のトークンに sim の数値（= 公式の値）を入れる。文は日本語クライアントの説明文の構造 |

### 既知の差・リスク

- スキルのマナ（コスト）・クールダウンは公式の表（`HeroKit.cost` / `Kit.cooldown`。11 / 8 / 30・25・20 秒）。
- S1 の持続は Lv で 4 → 9 秒に伸びるが、App の演出（`FX_H025.swift` の弓の月光、4 秒）は固定のまま（App はこの変更の範囲外）。
- S2 の名前は共通の「星環シフト25」のまま（ブリンクではなく地点指定の矢）。マスターデータを変えない方針のため。
- 月影・月矢は構造物に働かない（推測。攻城は汎用のレンジャー）。
- S2 を撃った術者が着弾までに死亡すると、着弾（ダメージ・バインド）は起きるが小さな矢は散らない。
- 副矢は追尾弾なので、飛行中に対象が視界から消える・倒れると消える（主矢と同じ）。
- 1v1 の総当たり勝率・TTK は公式の値にしてから測り直していない（全キットの移行の後に Release でまとめて測る）。
- 満タンの月環の導き（月影）が出た瞬間の専用の演出は無い。月影は通常攻撃の追加ヒット（`DamageSource.basicAttack`）で、演出の `hit` はスキル由来のダメージにしか再生されず、パッシブの演出（頭上の月）は段が増えたとき（5 段目まで）にしか出ない。月影を `.skill(.passive)` にすれば `hit` を出せるが、装備のスキル命中効果（減速・魔防ダウンなど）が通常攻撃のたびに乗るため見送った。ボット戦・ワールド戦・SkillBalanceTests（TTK の帯）は通る。

### 演出（`FX_H025.swift`）

- スキル1 は着弾の無い自己強化: 弓に月光が集まり、主矢（中央・長く太い）と左右の副矢の三条の筋が 0.03 秒ずつずれて前へ走り、矢先に光が灯る。効果中は弓の先に月の粒が流れ続ける（4 秒）。
- S2 は予告（telegraph）= 着弾点の月の輪、着弾（impact）= 六条の矢の筋、矢（travel）= 小さな光の筋、命中（hit）= スロウの月の輪。
- 奥義は月影に紛れる霞と月の輪、2 秒の疾風の筋。照準リングの半径（350）は演出の大きさに使わず、固定値で描く。
- `SkillFXDirector` は `stage / count / duration` をまだ読まないので、レシピの構成だけで機構に合わせた。

### 経緯（2026-10-14 の公式の表への移行より前）

換算の値の選び方（`KitBalanceTests` で `shadowScale` / `s1Scale` / `s2Scale` を比べた記録）は、公式の表をそのまま使うようになって意味が無くなったので消した（git の履歴に残る）。何を変えたかだけを残す。

- 見直し（2026-10 前半）: 攻撃速度 / 段・月影を調整値にしていた（6% → 9%、月影 54 + 30% → 70 + 40%）。
- クールダウンを MLBB の秒数に（2026-10）: 全体の CD 倍率 0.5 を廃止し、S1 11 秒・S2 8 秒・奥義 30 / 25 / 20 秒。攻撃速度 / 段を MLBB と同じ 5% に戻した。
- 公式の数値に合わせる（2026-10）: Fandom の表（月影 30(+25%)・S1 マナ 50 → 75・S2 マナ 80 → 130・S1 持続 4 → 9 秒）を、当時の 4 段のランクへ線形補間し、スロット倍率とキットの換算を掛けていた。タグを `buff` / `buff aoe` / `disrupt aoe` / `conceal cleanse` に。
- 日本語クライアントの数値へ（2026-10-10）: 月影 25(+20%)・S1 マナ 60 → 85。説明文を日本語クライアントの文の構造に。
- 日本語クライアントの原本へ（2026-10-11）: S2 マナ 90（全 Lv）、アルティメットの文を「隠蔽状態」に。マナの消費が変わったので、マイヤの入る AI 戦の展開は変わった
  （`ReplayTimelineTests.testTimelineIsDeterministicAndSampled` のシード 77 は最初のキルが 5.3 → 8.4 分になり、「6 分でキルが起きる」を満たさなくなったので、キットのヒーローが居ないシード 9 に替えた）。

### 公式の表をそのまま使う（2026-10-14・6 / 6 / 3 段）

MLBB の数値を Velstria の尺度に換算しない。スキル1・2 = Lv1〜6、アルティメット = Lv1〜3 の公式の表（上の「公式（日本語クライアント）の数値」）を `[Double]` でそのまま持ち、
rank = 公式の Lv として `Kit.level` で引く（補間しない）。ダメージ = 公式の基礎[Lv] + 公式の係数 × 合計の物理攻撃（`Kit.official(…, .totalAttack, …)`。(+N%) の表記 = 合計の物理攻撃）。
CD = 公式の秒数 × (1 − CD 短縮)（`Kit.cooldown`）。マナ = 公式の表（`HeroKits.resourceCost(Kit.level(…))`）。

| 枠 | 項目 | 公式（日本語クライアント） | 実装（`LuminaTuning`） | 以前（換算） |
|---|---|---|---|---|
| パッシブ | 攻撃速度 / 段 | 5%（4 秒・最大 5 スタック） | 同じ | 同じ |
| パッシブ | 月影 | 25 (+20% 物理攻撃)、攻撃効果の 20% を引き継ぐ | `25 + 0.20 × 物理攻撃`、`attackEffect` 0.2 | 25(+20%) × `shadowScale` 2.6 = 65 + 52%、命中時効果なし |
| スキル1 | CD | 11.0（一定） | `[11]` | 同じ（補間） |
| スキル1 | MP | 60 / 65 / 70 / 75 / 80 / 85 | 同じ | 4 段へ補間 |
| スキル1 | 持続 | 4 / 5 / 6 / 7 / 8 / 9 秒 | 同じ | 4 段へ補間（4 / 5.67 / 7.33 / 9） |
| スキル1 | 主矢の追加 | 10 / 15 / 20 / 25 / 30 / 35 (+100% 物理攻撃 = 通常攻撃) | 通常攻撃 + 基礎そのまま | 基礎 × 4.0 × `s1Scale` 1.8（72 〜 252） |
| スキル1 | その他の対象 | 30% のダメージ、各矢は攻撃効果の 30% を引き継ぐ | 主矢の 30%、`attackEffect` 0.3 | 30%、命中時効果なし |
| スキル2 | CD / MP | 8.0（一定）/ 90（一定） | `[8]` / `[90]` | 同じ（補間） |
| スキル2 | 着弾 | 270 / 300 / 330 / 360 / 390 / 420 (+45% 物理攻撃)、1.2 秒バインド | 同じ。敵に付ける `root` = バインド | (基礎 + 0.45 × 0.6 × 攻撃力) × 3.0 × `s2Scale` 0.30 = 0.9 × 基礎 + 24.3%、ブリンクは止めない |
| スキル2 | 小さな矢 × 6 | 40 / 53 / 66 / 79 / 92 / 105 (+20% 物理攻撃)、30% 減速 2 秒 | 同じ | 0.9 × 基礎 + 10.8% |
| アルティメット | CD / MP | 30 / 25 / 20 秒 / 120 / 145 / 170 | 同じ | 同じ |
| アルティメット | 効果 | 全デバフ解除・隠蔽・最大 2 秒 移動速度 +65%・終了で最大スタック | 同じ | 同じ |

例（装備なし。物理攻撃 = ヒーロー Lv1 115 / Lv15 227）: 月影 48 / 70.4（同じ能力値で以前は 125 / 183）、月蝕の矢の着弾 = スキル Lv1・ヒーロー Lv1 で 321.8 / スキル Lv6・ヒーロー Lv15 で 522.2、
小さな矢 = 同じく 63 / 150.4。

**外した定数・ルール**

| 定数・ルール | 旧値 | 新しい扱い |
|---|---|---|
| `LuminaTuning.shadowScale` | 2.6（月影 65 + 攻撃力 52%） | 削除。公式 25 (+20%) |
| `LuminaTuning.s1Scale` × `Balance.Skills.damageScale(.skill1)` | 1.8 × 4.0（主矢の追加 72〜252） | 削除。公式 10〜35 |
| `LuminaTuning.s2Scale` × `damageScale(.skill2)` × `Balance.skillAttackScalingFactor` | 0.30 × 3.0 × 0.6 | 削除。公式 270〜420 (+45%) / 40〜105 (+20%) |
| `Kit_H025.lerp`・`(Lv1, Lv6)` のタプル | 4 段（スキル1・2）へ線形補間 | 削除。6 / 6 / 3 段の表を `Kit.level` で引く |
| `Kit_H025.cooldown`（`Balance.Skills.cooldownScale` 1.0） | 補間 × CD 短縮 × 1.0 | 削除。`Kit.cooldown` |
| `Kit_H025.scaledBase` / `attackPercent`（説明文の換算後の基礎・係数） | 換算した値を表示 | 削除。説明文は公式の基礎と係数そのもの |
| スキルのミニオンへの全体の × 0.2（共通） | 月蝕の矢・小さな矢がミニオンに 20% | 共通の土台で撤廃。マイヤのスキルの文にミニオンへの補正は無いので 100% |
| 共通の `root` がブリンクを止めない | 月蝕の矢のバインド中も瞬歩・ブリンクのスキルが使えた | 共通の土台でバインド（敵の root）が瞬歩・術者を動かすスキルを封じる。説明文も直した |

**入れた割合**（出典: 日本語クライアント = REAL_DATA.md の「H025 ルミナ = マイヤ」）

- 月影: 攻撃エフェクト 20%（「ムーンライトシャドウは攻撃効果の20%を引き継ぐ」）→ `HitPayload.attackEffect` = 0.2、source `.basicAttack`、`appliesOnHit` = false。
- 分裂の矢（副矢）: 攻撃エフェクト 30%（「各矢は攻撃効果の30%を引き継ぎ」）→ `attackEffect` = 0.3、同上。主矢は通常攻撃そのもの（100%）。
- スキル吸収率: 公式の文に無いので既定（100%）。月蝕の矢（着弾・小さな矢）だけがスキルのダメージ。
- ミニオン・モンスターへの補正: 公式の文に無いので無し（1.0）。

**CC・バインド・中断**

- 月蝕の矢の 1.2 秒は敵に付ける `root` = バインド（`Unit.isBound`。低レベルのコントロール: 移動・瞬歩・術者を動かすスキルを封じ、攻撃と移動しないスキルは使え、スキルは中断しない）。
- ルミナのスキルはどれも術者を動かさない（自己強化・地点指定。`movesCaster` は既定の false のまま）ので、ルミナ自身がバインドされても 3 つとも撃てる（瞬歩だけが封じられる）。隠れ月光はバインドも解除する。
- 月蝕の矢の小さな矢のタイマーは非中断のまま（矢は放たれた後なので、術者がスタンしても散る）。

**まだ MLBB と違うところ（推測・未検証・資料が無いもの）**

- 副矢の対象の選び方（主矢の対象から 300 以内で近い 2 体、術者の射程 + 150 以内）は推測。説明文の「周囲300以内で近い2体」は Velstria の但し書き。周囲に敵が居ないとき副矢は飛ばない（MLBB で別の向きに飛ぶかは未確認）。
- 構造物に月矢（追加ダメージ・副矢）と月影が働かないのは推測（調査に無い。未検証）。
- 月影は会心にならない（公式の文に会心の記述が無い。未検証。Fandom のパッシブの用語に「Crit Rate」が並ぶだけ）。
- 主矢の追加の基礎（10〜35）は会心の後に足す（基礎が会心で増えるかは未検証）。
- 月影・副矢の通常攻撃吸収: 共通の `attackEffect` は攻撃エフェクトと同じ割合（20% / 30%）で通常攻撃吸収を掛ける。Fandom は月影・分裂の矢とも `lifesteal-ratio` 0%、分裂の矢の `spell-vamp-ratio` 50% を載せている（日本語クライアントの文には無い）。MLBB の通常攻撃吸収率が攻撃エフェクトと別なら、共通の層に通常攻撃吸収率の項目が要る。
- 月蝕の矢の遅延 0.35 秒・半径 170・射程 650、小さな矢の散り方（6 本 60° おき）・速さ 1800・射程 420・幅 35 は推測。詠唱の動作（キャスト時間）は無い。
- 隠蔽は Velstria 共通の隠密（敵の 250 以内・塔の真視・泉では見える）。
- 1v1 の総当たり勝率・TTK（`testRoundRobinWinRateIsReportedAndNotDominant` / `testDuelTimeToKillAgainstRoleRepresentativesStaysInBand`）と `KitBalanceTests` は、全キットの移行の後に Release で測り直す（帯の数値は変えていない）。
