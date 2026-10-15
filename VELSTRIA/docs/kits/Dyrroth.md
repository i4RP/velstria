# Dyrroth (MLBB) - Kit Specification

> 2026-10-14: ヒーローの能力値（HP・物理攻撃・防御・魔防・攻撃速度・HP 回復・マナ・移動速度・射程・リソースの種類）と能力値の式（防御 120/(120+防御)・クリティカル 200%・攻撃速度の加算・移動速度の加算式など）を MLBB の値へ置き換えた（`docs/HERO_STATS.md`）。続けてスキルの段階も移した: **公式の表をそのまま使う（6 / 6 / 3 段。換算・補間なし）**（下の「Velstria 実装対応表」と「スキルの段階の移行」）。下の英語の調査の節（Hero overview 〜 Sources）は移行の前に集めた二次資料で、正は「日本語クライアントの画面」の節。

Values come from Mobile Legends Fandom / Liquipedia search extracts and mlbb.tools / mlbb.io (direct fetch of Fandom and Liquipedia was blocked, so figures are second-hand from search excerpts). "unknown" = not found. "disputed" = sources disagree.

## Hero overview
- Role / lane: Fighter, EXP lane (also jungle). Melee.
- Resource: none for mana (0 mana). Uses Rage (a percentage bar; see passive).
- Basic attack: melee, single target. Every 2nd basic attack becomes a Circle Strike (AoE) once passive is active (see passive).
- Attack range: 1.7 (Circle Strike: 2) per Fandom extract. Units are the wiki's range units.
- Base stats at level 1 (Fandom extract): HP 2758, physical attack 117, physical defense 22, magic defense 15, movement speed 265, attack speed 1.14. Attack-speed ratio 100%.
- Growth per level (Fandom extract, level 1 to 15): HP +215, phys attack +10.64, phys defense +3.7857, magic defense +1.6429, attack speed +0.03.
- Disputed base stats: Liquipedia-style extract gives HP 2580, regen 8.2, phys defense 22, magic defense 15; mlbb.tools gives HP 2601, regen 7.6, phys attack 126, phys defense 21, magic defense 10, attack speed 0.88, move speed 260 (appears to be an older/different version or different measuring point). Prefer the Fandom level-1 figures above.
- Max skill levels: S1 6, S2 6, Ultimate 3.

## Passive - Wrath of the Abyss
- Cast type: passive (resource-driven state).
- Rage: Dyrroth recovers 2%-5% Rage per second (scales with hero level). Rage bar behavior beyond this (gain from damage dealt/taken) = unknown.
- At 50% Rage, Burst Strike and Spectre Step become "Abyss Enhanced" (see each skill). Sources describe two rage bars/segments (one per skill); exact consumption per use = unknown.
- Circle Strike: after every 2 basic attacks, Dyrroth releases a Circle Strike hitting enemies in a circle for 150%-180% Total Physical Attack (scales with level) as physical damage, and heals 7%-10% Max HP (scales with level; halved against minions and turrets). (Some sources say this needs the Rage threshold; one extract says "when Fury reaches 50%, every 2 basic attacks trigger Circle Attack".)
- Cooldown reduction: each time he damages an enemy hero, Burst Strike and Spectre Step cooldowns are reduced by 1 s (Circle Strike hit gives the reduction). (Old Fandom wording. The current JP client and Liquipedia say "each time he damages an enemy", with no hero-only clause.)

## Skill 1 - Burst Strike
- Cast type: directional skillshot (cone/line burst in the target direction).
- Effect: bursts in the target direction, each burst dealing 240 (+60% Total Physical Attack) physical damage and slowing hit enemies by 25% for 1.5 s. Damage decreases for repeated hits on the same target and against minions. Normal version hits 3 times; Abyss version hits 5 times (esports/oneesports guide).
- Abyss Enhanced: longer range, 140% of original damage, slow effect doubled (50%).
- Range / width / cast time: unknown.
- Cooldown by level: 6.0 / 5.6 / 5.2 / 4.8 / 4.4 / 4.0 s.
- Base damage by level: 240 at level 1 to 520 at level 6 (intermediate steps = unknown, likely linear +56). Scaling +60% Total Physical Attack.
- Cost: no mana.

## Skill 2 - Spectre Step (Specter Step)
- Cast type: dash in a chosen direction, then a recast (second cast) lock-on strike.
- Cast 1: dashes in the designated direction; stops at max distance or on hitting one enemy hero or creep (in MLBB English "creep" = jungle monster; the JP client says モンスター, so minions do not stop it). Deals 230 (+60% Extra Physical Attack) physical damage and slightly knocks the target back.
- Cast 2 ("Fatal Strike", used again): locks onto a target and strikes for 345 (+120% Extra Physical Attack) physical damage and reduces target physical defense by 40% for 4 s. Cannot target minions or the summoned Lord (oneesports). Recast window length = unknown.
- Abyss Enhanced: Fatal Strike reaches further, deals 150% of original damage, applies an extra slow and reduces physical defense by 60% for 4 s. (One extract says "slow the target by an extra 90%"; treat that figure as unverified.)
- Cooldown: 6.0 s at all levels.
- Base damage of cast 1 by level: 230 / 255 / 280 / 305 / 330 / 355. Cast 2 base per level = unknown (345 at level 1).
- Dash distance / speed: unknown. Cost: no mana.

## Ultimate - Abysm Strike
- Cast type: directional delayed (charged) line strike; direction/range can be altered with Flicker during the charge.
- Effect: after a short delay, launches a destructive strike in the target direction dealing 650 (+250% Extra Physical Attack) plus a percentage of the target's lost HP as physical damage to enemies in its path, and slows them by 55% for 0.8 s.
- Lost-HP percentage: disputed. Fandom extract says 20%; mlbb.tools and esports.gg-based extract say 25%.
- Cannot be interrupted except by Suppression (stun/knock-up do not stop it).
- Cooldown by level: 36 / 32 / 28 s.
- Base damage by level: 650 / 950 / 1250.
- Range, width, charge delay (exact seconds): unknown. Cost: none.

## Gameplay identity
- Bruiser who snowballs through a rage meter and stays in melee with Circle Strike sustain.
- Cooldown-reset loop: basic attacks and hits shorten S1/S2 cooldown, rewarding constant aggression.
- Armor-shred burst: Fatal Strike's -40/-60% physical defense sets up the ultimate.
- Ultimate is a high-damage, uninterruptible (except suppression) execute-flavored line, scaling on enemy lost HP.
- Weak to kiting and CC applied before the ultimate begins.

## Simulation notes
- Standard: directional AoE skillshot with slow (S1), dash with collision stop (S2 cast 1), delayed line damage with slow (ult), melee basic attacks, percent-defense debuff, % lost-HP bonus damage.
- Needs special state: Rage resource (0-100%, passive regen 2-5%/s, 50% threshold toggling "Abyss Enhanced" variants of S1/S2); basic-attack counter (every 2nd attack -> Circle Strike AoE + percent-max-HP heal); per-hit cooldown reduction on S1/S2; S2 recast window and lock-on target selection; ultimate with "channel uninterruptible except suppress" flag; same-target diminishing hits for multi-hit S1.

## Sources
- https://mobile-legends.fandom.com/wiki/Dyrroth (via search extract)
- https://liquipedia.net/mobilelegends/Dyrroth (via search extract)
- https://mlbb.tools/heroes/dyrroth
- https://mlbb.io/en/hero/dyrroth
- https://www.oneesports.gg/mobile-legends/dyrroth-guide-best-build-emblem/
- https://alexandregames.com/mobile-legends/dyrroth-english.html

## 日本語クライアントの画面（2026-10-11 受領・実機）

MLBB の日本語クライアントのスキル詳細（ユーザーのスクショ。画像はコミットしない）。日本語版の名前は「ディアス(Dyrroth)」、ファイター「アサルト/爆発力」。
数値は下の Liquipedia の表と一致し、違いはアルティメットの失った HP の割合（**25%**。Liquipedia・Fandom は 20%）だけ。どのスキルもコストの表示が無い（コストなし）。
同じ日に受け取った無加工の原本（IMG_4526〜4535）とも照合した: 数値・タグ（バフ・ヒール / 範囲技・減速 / ブリンク・攻撃 / 爆発力・減速）・失った HP 25% はすべて一致（変更なし）。

| 枠 | 日本語版の名前 | タグ | CD | 内容（日本語版の文の要約） |
|---|---|---|---|---|
| パッシブ | アビスレイジ | バフ・ヒール | – | 怒り 50% でエクスプロードとシャドーステップを強化。通常攻撃 2 回ごとにサークルストライク: 範囲内の敵に (150%)〜(180%) 物理攻撃（レベルで増加）の物理ダメージ（タワーには強化ダメージ無効）、最大 HP の 7%〜10% を回復（レベルで増加、ミニオン・タワー相手は半減）。この攻撃では攻撃効果は発動しない。敵にダメージを与えるたびにエクスプロードとシャドーステップの CD −1 秒。毎秒 2%〜5% の怒りを回復（レベルで増加） |
| スキル1 | エクスプロード | 範囲技・減速 | 6.0 / 5.6 / 5.2 / 4.8 / 4.4 / 4.0 | 指定方向にエクスプロードを放つ。爆発ごとに 240 / 296 / 352 / 408 / 464 / 520 (+60% 物理攻撃) の物理ダメージ、1.5 秒 25% 減速。同じ対象に複数回命中するとダメージは減少、ミニオンには 75%。アビス強化: 射程が伸び、元のダメージの 140%、減速 2 倍 |
| スキル2 | シャドーステップ | ブリンク・攻撃 | 6.0（一定） | 指定方向へ突進。最大距離か敵ヒーロー・モンスターに命中で停止し、230 / 255 / 280 / 305 / 330 / 355 (+60% 追加物理攻撃) の物理ダメージ + わずかにノックバック。再発動: 対象をロックオンして一撃を放ち、345 / 390 / 435 / 480 / 525 / 570 (+120% 追加物理攻撃) の物理ダメージ、4 秒間物理防御 −40%。アビス強化: 射程が伸び、元のダメージの 150%、追加で 90% 減速、4 秒間物理防御 −60% |
| アルティメット | アビスストライク | 爆発力・減速 | 36 / 32 / 28 | 少し遅れて指定方向に強力な一撃を放ち、進路上の敵に 650 / 950 / 1250 (+250% 追加物理攻撃)(+対象の損失 HP の 25%) の物理ダメージ、0.8 秒 55% 減速。制圧によってのみ中断される。ヒーロー以外へのダメージは最大 1500 / 2000 / 2500 |

注: 日本語版のヒーロー名「ディアス」は Velstria の H032（赤拳のディアス）と同じ。

## 公式（現行シーズン）の数値

2026-10 に MediaWiki API で取り直した（Liquipedia の `Dyrroth` = 現行の V2。Fandom の `Dyrroth` は古い版の表（スキル1 の CD 5 秒・基礎 200〜450、スキル2 の CD 8 → 4 秒、
円撃 160% + 回復 50 + 与ダメの 40%、CD 短縮は「敵ヒーローに当てるたび」）のままなので、現行の値は Liquipedia と日本語クライアントを正とした）。
Liquipedia に数字の無い項目（スキル1 の同じ敵への減衰率・強化版の 5 連、致命の一撃の追加の鈍足の秒数）だけ Fandom の値を使った。

| スロット | 公式名 | タグ | 内容 |
|---|---|---|---|
| パッシブ | Wrath of the Abyss | バフ・回復 | レイジ 50% でスキル1・2 を強化。通常攻撃 2 回ごとに円撃: 円の中の敵に物理攻撃の 150% 〜 180%（レベルで増える）の物理ダメージ（強化ダメージはタワーには乗らない）、最大 HP の 7% 〜 10% 回復（レベルで増える。ミニオン・タワー相手は半分）。攻撃エフェクトは発動しない。「Each time he damages an enemy」スキル1・2 の CD −1 秒。レイジは毎秒 2% 〜 5%（レベルで増える） |
| スキル1 | Burst Strike | 範囲技・減速 | CD 6.0 / 5.6 / 5.2 / 4.8 / 4.4 / 4.0、コストなし、基礎ダメージ 240 / 296 / 352 / 408 / 464 / 520（+60% 物理攻撃）。指定方向へ衝撃を放ち、各衝撃でダメージ + 25% 減速 1.5 秒。同じ敵へのダメージは減衰し、ミニオンには 75%。強化: 射程が伸び、元のダメージの 140%、減速 2 倍。減衰率（Fandom）: 通常 {100%, 30%, 30%}、強化 {140%, 42%, 42%, 42%, 42%}（= 通常 3 回・強化 5 回） |
| スキル2 | Spectre Step | 移動・ダメージ | CD 6.0（全 Lv）、コストなし。突進し、最大距離か敵ヒーロー・クリープ（MLBB の英語の「Creep」= ジャングルのモンスター。日本語版は「モンスター」）に当たって止まり、230 / 255 / 280 / 305 / 330 / 355（+60% 追加物理攻撃）+ 軽いノックバック。再使用で対象をロックオンして致命の一撃 345 / 390 / 435 / 480 / 525 / 570（+120% 追加物理攻撃）、物理防御 −40%（4 秒）。強化: 致命の一撃の射程が伸び、ダメージ 150%、追加で 90% の減速（Fandom: 1 秒）、物理防御 −60%（4 秒） |
| アルティメット | Abysm Strike | バースト・減速 | CD 36 / 32 / 28、コストなし、基礎ダメージ 650 / 950 / 1250（+250% 追加物理攻撃）+ 対象の失った HP の **25%**（日本語クライアント。Liquipedia・Fandom は 20%）、55% 減速 0.8 秒。短い遅れのあと指定方向へ（制圧でのみ中断）。ヒーロー以外へのダメージの上限 1500 / 2000 / 2500 |

S1・S2・アルティメットの表は日本語クライアントの原本（IMG_4528・4530・4532）に 6 / 6 / 3 段すべて載っている（補間した段は無い）。
パッシブの「レベルに応じて増加」（150%〜180%・7%〜10%・2%〜5%）だけは両端しか無い。

## Velstria 実装対応表

H032 赤拳のディアス（デュエリスト・近接）= Velstria 版の Dyrroth。実装: `Packages/VelstriaCore/Sources/VelstriaCore/Systems/Kits/Kit_H032.swift`
（専用の部品は `KitDias.swift`）、テスト: `Tests/VelstriaCoreTests/Kits/Kit_H032Tests.swift`、演出: `App/Battle/SkillFX/Heroes/FX_H032.swift`。
スロットは上の調査の順に割り当てる（Skill1 = Burst Strike、Skill2 = Spectre Step、Ultimate = Abysm Strike、Passive = Wrath of the Abyss）。
マスターデータ上の最終名は パッシブ「紅血の拳」/ スキル1「赤拳連斬」/ スキル2「紅蓮の踏込」/ アルティメット「奈落の一撃」（`tools/rename_kit_skills.mjs`）。説明文は UI の用語（スキル1・スキル2・アルティメット）で書く。キットは汎用のデュエリストのパッシブ
（通常攻撃の攻撃速度スタック）と汎用の奥義（3 連撃 + 被ダメ軽減）を **置き換える**。

**公式の表をそのまま使う（6 / 6 / 3 段）。** スキル1・2 は Lv1〜6、アルティメットは Lv1〜3 の表を `rank`（= 公式の Lv）で `Kit.level` で引く（補間・換算・スロット倍率なし）。
ダメージ = 基礎[段] + 係数 × 能力値（`Kit.official`）。スキル1 の (+60%) は合計の物理攻撃、スキル2・アルティメットの (+N%追加) は追加物理攻撃（`Stats.extraAttack` =
装備・エンブレム・スキルで増えた分。HUD・説明文の数値も発動時と同じ式で、装備なしなら基礎だけ）。CD = 表の秒数 × (1 − CD 短縮)（`Kit.cooldown`）。コストは公式どおり無し（`HeroKit.cost` = 0）。
パッシブの「レベルに応じて増加」はヒーローのレベル 1 → 15 で線形（画面は両端だけ。間は推測）。距離は Velstria 単位（≈ MLBB × 100）。画面に無い値（射程・突進の距離と速度・再使用の窓・溜めの長さなど）は下の「画面に無い値」に書いた。

### 対応表（○ = 実装、△ = 簡略化・推測、× = 見送り）

| 元の仕様 | 状態 | Velstria での実装 |
|---|---|---|
| 近接・単体の通常攻撃 | ○ | 能力値は MLBB の値（`docs/HERO_STATS.md`）。リソースは無し（怒り） |
| パッシブ: レイジ（0〜100%）が毎秒 2〜5%（レベルで増える） | ○ | `reals[0]`。毎秒 2% → 5% を Lv1 → 最大レベル（15）で線形（間は推測）。死亡で 0。開始時も 0。ダメージを与える・受けるでのレイジ増加は日本語版の文に無いので持たない（Fandom の古い版の「スキル1 の命中ごとに +10」も入れない） |
| レイジ 50% で S1・S2 が「アビス強化」になる | ○ | 50 以上で発動した S1 / S2 の **2 回目（致命の一撃）** がアビス強化になり、レイジを **50 消費** する（消費量は Fandom の注記「Abyss Enhanced costs 50 Rage」）。ちょうど 50 でも強化。HUD のバッジはパッシブに **50 ごとの段（`Int(レイジ / 50)`、0〜2、最大 2）**、スキル1・スキル2 に「強化可能（form）」。パッシブのバッジを毎秒増えるレイジそのもの（0〜100）にすると、バッジが増えるたびにパッシブの演出を出す Director（`observeKitPassives`）が毎秒鳴り続けるので、閾値（50・100）を通ったときだけ増える形にした |
| 「2 本のレイジゲージ（スキルごとに 1 本）」という資料もある | △ | ゲージは 1 本（0〜100）で、50 ずつ S1 / S2 のどちらにでも使える |
| Circle Strike: 通常攻撃 2 回ごとに周囲の円攻撃（物理攻撃の 150〜180%、レベルで増える） | ○ | `shapeBasicAttack` で 2 回に 1 回を円撃にする（`ints[0]` で数える。死亡でリセット）。主対象は通常攻撃の命中（会心・通常攻撃吸収はそのまま）で攻撃力 × 1.5（Lv1）→ 1.8（Lv15）、周囲の敵（半径 190 + 対象の半径。ヒーロー・ミニオン・モンスター。構造物は除く）にも同じダメージを別に与える（吸収は主対象だけ）。強化ダメージはタワーに乗らない（主対象が構造物なら通常攻撃のダメージ） |
| 円撃は攻撃エフェクトを発動しない | ○ | 主対象の payload に `skipsItemOnHit`（装備・エンブレムの命中時効果を外す）。`attackEffect: 0` にはしない: HitPayload の攻撃エフェクトの割合は通常攻撃吸収にも掛かるが、Fandom の用語は「物理通常攻撃は攻撃エフェクトと通常攻撃吸収を発動する」で両者は別、Fandom の注記も「円撃は通常攻撃吸収が乗る」。命中のフック（CD 短縮）は主対象に乗ったまま |
| 円撃の回復: 最大 HP の 7〜10%（ミニオン・タワー相手は半減） | ○ | **公式どおり 7% → 10%**（Lv1 → Lv15 の線形。以前は公式の 0.2 倍 = 1.4〜2%）。1 回の円撃で 1 度。当たったのがミニオン・タワーだけなら半分、ヒーロー・モンスター（・練習場の人形）が 1 体でも含まれていれば全量（公式の文の半減は「ミニオンやタワー」だけ。以前はモンスターも半分にしていた） |
| 「レイジ 50% のときだけ円撃」という資料もある | × | 無条件に 2 回に 1 回（日本語版の文どおり） |
| 敵にダメージを与えるたびに S1・S2 の CD −1 秒 | ○ / △ | **公式どおり 1 秒、相手は敵ならどれでも**（ヒーロー・ミニオン・モンスター・タワー。以前は「敵ヒーローだけ」・通常攻撃 0.55 秒・スキル 0.05 秒）。数え方は下の「CD 短縮の数え方」: 通常攻撃（円撃を含む）1 回で 1 度、スキルは 1 回の発動（S1 の連撃・S2 の 1 回目・S2 の 2 回目・奥義）で 1 度。奥義の CD には効かない。練習場の `noCooldowns` は尊重 |
| S1 Burst Strike（赤拳連斬）: 指定方向へ衝撃を 3 回（アビス強化は 5 回）、1 発 240〜520 + 60% 物理攻撃 | ○ | 前方の扇（射程 300・半角 0.65 rad ≈ 37°）へ 0.1 / 0.24 / 0.38 秒に 3 発（スタンされると残りは取り消し）。1 発目 = 公式の表 + 0.6 × 合計の物理攻撃。向きは発動時に固定 |
| S1 同じ敵への連続ヒットは減衰、ミニオンには 75% | ○ / △ | 2 発目以降は 1 発目の 30%（Fandom の減衰率 {100%, 30%, 30%}）。発の順番で掛けるので、途中から扇に入った敵も 30%（△: 公式は「同じ対象に複数回命中した場合」）。ミニオンへは `HitPayload.minionMultiplier = 0.75`（以前は全体のミニオン倍率 × 0.2 と重なって実質 0.15 倍）。モンスターは 100% |
| S1 鈍足 25% 1.5 秒 | ○ | `slow` 0.25 を 1.5 秒（毎発付け直す。同じタグなので重ならない） |
| S1 アビス強化: 射程が伸び、ダメージ 140%、鈍足 2 倍、5 回 | ○ | レイジ 50 を消費して、射程 400・5 発（0.1 秒 + 0.11 秒間隔）・鈍足 50%。「140%」は **1 発ごと**（Fandom の減衰率 {140%, 42%, 42%, 42%, 42%}）。単体の合計は 1 発目の 3.08 倍。強化した発動は `SkillCastEvent.count = 5` |
| S1 クールダウン 6.0 → 4.0 秒、コスト無し | ○ | 公式の 6 段の表そのまま |
| S2 Spectre Step（紅蓮の踏込）1 回目: 指定方向へ突進、最大距離か **敵ヒーロー・モンスター** に当たると止まる | ○ | `dashStrike` として宣言（射程 400・速度 2400 ≈ 0.17 秒、経路の当たり半幅 110 + 対象の半径）。発動時に進路で最初に当たる敵ヒーロー・モンスター（構造物・対象不可は除く）を探し、その縁（中心間 = 半径の和 + 5）まで進む（`Kit.firstBlocker(stopsAt:)`）。**ミニオンでは止まらず通り抜け、通り抜けたミニオンには当てない**（以前はミニオンでも止まっていた。英語版の「Creep」をミニオンと読み違えていた）。敵が居なければ最大距離まで。壁の手前では止まる |
| S2 1 回目のダメージ 230〜355 + 60% 追加物理攻撃、わずかに押し出す | ○ | 公式の表 + 0.6 × 追加物理攻撃（`Kit.official(.extraAttack)`）。到着した tick に止まった先の敵へ 1 度だけ（離れすぎ・死亡・対象不可なら外れる）。押し出し = `HitEffect.pushAway` 130 を 0.18 秒（CC 無効の相手は動かない） |
| S2 2 回目（再発動）: 対象を捕捉して一撃、物理防御 −40% 4 秒 | ○ | 同じ `castSkill`（`openRecast`、3 秒・1 回。CD・コストは使わない）。対象は **敵ヒーロー・モンスター**（ミニオンは選べない。Fandom「Enemy heroes or creeps hit by Fatal Strike」・oneesports「ミニオンは選べない」）。指定ユニット → 指定地点に近い敵 → 向き → 自動（ヒーローを優先し、HP + シールド最小）。対象の縁まで飛びかかり（速度 2600）、到着した tick にダメージ（345〜570 + 120% 追加物理攻撃）+ `armorShred` 0.4（4 秒）。防御ダウンは自分の一撃には掛からない。射程 350。溜め中・敵が射程に居なければ拒否（窓は残る） |
| S2 2 回目の窓の長さ（不明） | △ | 選んだ値: 3 秒。CD は 1 回目の発動で消費され、2 回目では変わらない |
| S2 アビス強化の 2 回目: 射程が伸び、ダメージ 150%、追加の鈍足 90%、防御ダウン −60% | ○ | レイジ 50 を消費して、射程 500・ダメージ 1.5 倍・`armorShred` 0.6・`slow` 0.9 を 1 秒（公式の 90%、秒数は Fandom）。飛びかかりを止められた（ノックアップ・制圧）ときは消費したレイジを返す。強化した発動は `count = 2` |
| S2 クールダウン 6.0 秒、コスト無し | ○ | 公式と同じ 6.0 秒（全段） |
| 奥義 Abysm Strike（奈落の一撃）: 方向指定の溜め直線、650 / 950 / 1250 + 250% 追加物理攻撃 + 対象の失った HP の **25%** | ○ | 溜め 0.5 秒（調査に「短い遅れ」とだけある）のあと、発動時に固定した向きの直線（射程 650・半幅 140。命中は線分から「半幅 + 対象の半径」までなので、線分の長さは 650 − 140 = 510）の敵にダメージ。基礎 = 公式の表 + 2.5 × 追加物理攻撃（発動時に確定）。**失った HP の 25%**（`(最大 HP − 現在 HP) × 25%`。シールドは数えない。日本語クライアント。Liquipedia・Fandom の 20% は古い）を基礎に足してから防御で軽減する。ヒーロー以外（ミニオン・モンスター）にも加算し、合計（軽減の前）は公式の上限 1500 / 2000 / 2500 まで（`Kit_H032.ultHitDamage`） |
| 奥義 鈍足 55% 0.8 秒 | ○ | 命中した敵（ミニオン・モンスターを含む）に `slow` 0.55 を 0.8 秒 |
| 奥義は制圧以外では中断されない | ○ | 溜めのタイマーは `interruptible: false`（スタン・ノックアップで取り消されない）。`update` が suppress を見たら溜め・予約を取り消す。溜めの間は自分に `root`（sourceID = 自分 = バインドではない）+ 表示用の `channeling`（その場から動けず、攻撃・ほかのスキル・再発動を始められない）。死亡で全部リセット |
| 奥義 Flicker で向き・射程を変えられる | × | 向きは発動時に固定 |
| 奥義 クールダウン 36 / 32 / 28 秒、コスト無し | ○ | 公式の 3 段の表 |
| バインド（敵の root） | ○ | 共通の規則（`SkillSystem.validate` + `Unit.isBound`）: 術者が動くスキル（S2 の突進 = `dashStrike`、致命の一撃 = `targetedBlink`）はバインド中に撃てない。S1（扇）・奥義（直線）は撃てる。以前のキット側の「root 中は致命の一撃を拒否」（自分の root も含んでいた）は外した。自分の root は奥義の溜めだけで、溜め中は別に拒否している |
| CC の段階と突進 | ○ | 共通の規則（`CrowdControlTier`）: スタン（基本）は進行中の突進・飛びかかりを止めない（S1 の連撃の残りは取り消す）。ノックアップ・制圧は止める（突進も一撃も取り消し、アビス強化のレイジは返す。窓と CD は残る）。`onInterrupted` は突進が実際に止められた（`sweep` が外れた）ときだけ突進の記録を捨てる |
| パッシブのバッジと演出の合図 | ○ | パッシブのバッジは `.stacks`（値 = `Int(レイジ / 50)`、最大 2）。Director はバッジが増えた瞬間（レイジ 50・100）にだけパッシブの演出を出す。アビス強化を放ってバッジが 1 → 0 に戻ったとき（スキルの発動の直後）は `HeroFXSet.passiveRelease` |
| 円撃の専用の演出 | × | フレームワークにイベントを足さない方針なので専用の合図は無い（通常攻撃の命中 `atk_hit` が周囲の各対象に出るだけ） |
| ボット: 奥義 | ○ | `botCast`: 交戦中の敵ヒーローが射程の手前（現在の距離 540 以内）に居れば `.castNow(.direction)`。溜め 0.5 秒の間の動きを、直前の tick の動きが続くものとして読む（敵の移動速度の 0.5 秒分まで） |
| ボット: ファーム | ○ | `botFarm` で紅蓮の踏込（スキル2 の 1 回目）を **ジャングル（集団の 300 以内にモンスター）にだけ** 使う（突進はミニオンを通り抜けて当たらないので、ミニオンの集団には使わない）。HP が半分以上で、集団の位置が敵のタワー・コアの射程（750 + 半径 + 120）に入らないときだけ |
| 説明文 | ○ | 公式の文の構造・語順（「アビス強化：」「再発動：」）に合わせ、UI の用語（スキル1・スキル2・アルティメット）で書く。`{base}(+{atkPct}%物理攻撃)` / `(+{dashPct}%追加物理攻撃)` などは公式の値そのもの（240(+60%)・230(+60%追加)・345(+120%追加)・650(+250%追加)・最大 1500）。外した独自ルールの但し書き（「敵ヒーローに」「0.55 秒 / 0.05 秒」「1 回の発動につき 1 度」）は消した。タグは公式（パッシブ = バフ・ヒール、S1 = 範囲技・減速、S2 = ブリンク・攻撃 → `mobility` `damage`、ULT = 爆発力・減速 → `burst` `slow`） |

### CD 短縮の数え方（「ダメージを与えるたびに」）

日本語版の文は「敵にダメージを与えるたびに、エクスプロードとシャドーステップのCD時間が1秒短縮される」、Liquipedia は「Each time he damages an enemy」。
「たび」が対象ごとか命中ごとか発動ごとかを書いた資料は無い（Fandom の古い版は「敵ヒーローに当てるたびに」、攻略サイトも「敵ヒーローに当てるたび」と書く）。
Velstria は **1 回の行動につき 1 度** と数える: 通常攻撃（円撃を含む）は 1 回の攻撃で 1 秒（円撃が何体を巻き込んでも 1 秒。主対象への命中で数える）、
スキルは 1 回の発動で 1 秒（S1 の 3 / 5 連撃・巻き込んだ数によらない。S2 の 1 回目と 2 回目は別の発動なので 1 秒ずつ。奥義も 1 秒）。対象の種類は問わない。

対象ごと・連撃の 1 発ごとに数えない理由（MLBB の挙動として無いはずの無限ループになる）:
- 対象ごと: S1 を敵 2 体に当てるだけで 3 発 × 2 体 = 6 秒縮み、Lv1 の CD 6.0 秒が撃ち終わる前に消える。ウェーブ・集団戦で S1 を 0.4 秒ごとに撃ち続けられる。
- 1 発ごと（対象の数によらない）: 通常版で 1 回の発動につき 3 秒、強化版で 5 秒。Lv6 の CD 4.0 秒は CD 短縮 25% で 3.0 秒になり、S1 が自分の命中で自分の CD を消し続ける（上限 40% なら Lv4 から）。
  強化版は CD 短縮が無くても 1 回で次の S1 が撃てる。
1 回の発動につき 1 度なら、S1 自身の戻りは 1 秒 < CD の下限 2.4 秒（4.0 × (1 − 40%)）なので止まる。
確かめる材料: 練習場で S1 を 1 体・3 体に当てたときの S1 / S2 の CD の表示（動画）、ミニオンへの通常攻撃で CD が縮むか。

### 画面に無い値（推測の幾何・時間）

| 項目 | 値 | 理由 |
|---|---|---|
| アビス強化の消費 | 50 | Fandom の注記（「Abyss Enhanced costs 50 Rage」）。日本語版の画面に無い |
| パッシブのレベルの伸び | Lv1 → Lv15 で線形 | 画面は両端（150%〜180%・7%〜10%・2%〜5%）だけ |
| 円撃の半径 | 190 | 通常攻撃の射程より少し広い（MLBB 1.7 → 2.0 の比） |
| S1 の射程・半角・間隔 | 300 / 400（アビス）・0.65 rad・0.14 秒 / 0.11 秒 | 近接スキルの標準。調査に無い |
| S1 の連続ヒットの減衰 | 1.0 / 0.3 / 0.3（アビス: 1.4 / 0.42 × 4） | Fandom の減衰率（日本語版・Liquipedia は「減少する」とだけ） |
| S2 の突進 | 距離 400・速度 2400・幅 110・押し出し 130 / 0.18 秒 | 調査に「不明」 |
| S2 の致命の一撃 | 射程 350 / 500（アビス）・速度 2600・窓 3 秒 | 調査に「不明」 |
| S2 の強化の鈍足の秒数 | 1 秒 | Fandom（日本語版は「追加で 90% 減速」だけ） |
| 奥義の溜め・射程・幅 | 0.5 秒・650・半幅 140 | 調査に「短い遅れ」「不明」。MLBB の「画面の半分ほど届く長い直線」に寄せた |

### スキルの段階の移行（2026-10-14）

公式の表をそのまま使う形へ移した（共通の土台: 6 / 6 / 3 段、`Kit.level` / `Kit.official` / `Kit.cooldown`、`Stats.extraAttack`、HitPayload のスキルごとの割合、バインド、CC の段階）。

| 外したもの | 以前 | 今 |
|---|---|---|
| ダメージの換算 | `Tune.burstScale` 0.18 / `spectreScale` 0.33 / `ultScale` 0.40 + スロット倍率（4.0 / 3.0 / 2.6）+ 物理係数 × 0.6（`Balance.skillAttackScalingFactor`） | なし（公式の基礎 + 公式の係数 × 能力値） |
| 段の補間 | `(Lv1, Lv6)` のタプルを 4 ランクへ線形補間（`rankLerp`）、CD も同じ | 公式の 6 / 6 / 3 段の表を `Kit.level` で引く |
| 追加物理攻撃 | `物理攻撃 − Unit.baseStats.attack` を発動時に足す（HUD は装備なし） | `Stats.extraAttack`（`numbers` の時点で入る） |
| 奥義のヒーロー以外の上限 | 1500 / 2000 / 2500 を基礎と同じに換算（1560 / 2080 / 2600） | 公式の 1500 / 2000 / 2500 |
| 円撃の回復 | 公式の 0.2 倍（1.4〜2%）、モンスター相手も半分 | 公式の 7〜10%、半分はミニオン・タワーだけ |
| CD 短縮 | 敵ヒーローだけ、通常攻撃・円撃 0.55 秒 / スキル 0.05 秒（1 回の発動につき 1 度） | 敵ならどれでも 1 秒（通常攻撃 1 回・スキルの発動 1 回につき 1 度。上の「数え方」） |
| S1 のミニオン | `burstMinionFactor` 0.75 を payload に掛け、さらに全体のミニオン倍率 × 0.2（実質 0.15） | `HitPayload.minionMultiplier` 0.75（全体の × 0.2 は共通の土台で撤廃） |
| S2 の突進を止める敵 | ヒーロー・ミニオン・モンスター | ヒーロー・モンスター（ミニオンは通り抜ける） |
| 致命の一撃の対象 | 敵ヒーローだけ | 敵ヒーロー・モンスター（ミニオンは選べない） |
| 致命の一撃とバインド | キットが `has(.root)`（自分の root も含む）で拒否 | 共通の `SkillSystem.validate`（敵の root = バインドだけ） |
| スタンと突進 | スタンで突進・飛びかかりが止まりレイジを返す | スタンは止めない。ノックアップ・制圧が止める（レイジを返す） |

入れたスキルごとの割合: S1 のミニオン 75%（`minionMultiplier`、日本語版「ミニオンに対しては75%」）。スキル吸収率は日本語版の画面に載っていないので既定の 100%。
円撃の攻撃エフェクト 0% は `skipsItemOnHit`（通常攻撃吸収は残す。上の対応表）。モンスターへの補正は無い（100%）。

バランスの数値（1v1 の TTK の帯・総当たりの勝率の帯）は変えていない。全キットの移行のあとにまとめて測り直す。

### 既知の差・リスク

- スキル吸収率: 日本語版の画面に「スキル吸収率」の行が無いので、どのスキルも既定の 100%。Fandom の古い注記「円撃はスキル扱いでスキルの効果を受ける」は入れていない（円撃は通常攻撃として通常攻撃吸収が乗る）。
- S1 の減衰は「発の順番」で掛ける（公式は「同じ対象への複数回の命中」。途中から扇に入った敵も 2 発目以降は 30%）。
- S2 の突進が通り抜けたミニオンにダメージを与えるかは公式の文に無い（「命中すると停止し、…与えて」）ので与えない。
- S2 の突進・致命の一撃・奥義が壁を越えるか: 用語の「ブリンク」（S2 のタグ・奥義の用語一覧）は「地形無視できる」だが、突進は壁の手前で止まる。奥義の用語一覧に「ブリンク」があるので、奥義で術者が前へ動く可能性もある（今は動かない）。動画が要る。
- 奥義のヒーロー以外への上限は軽減の前の量に掛ける（軽減の後か前かは資料に無い）。
- 円撃は装備の命中時効果を発動しない（`HitPayload.skipsItemOnHit`）。強化ダメージはタワーに乗らない（主対象が構造物なら通常攻撃のダメージ）。
- S1 のアビス強化の射程（400）と S2 の 2 回目のアビス強化の射程（500）は、HUD の照準情報（`targeting`）には出ない（状態＝レイジが要るため）。照準円は通常版の大きさ（300 / 350）。
- S1 の連撃は発動時の向きに固定するが、中心は **撃った瞬間の自分の位置**（S2 で動けば追従する）。
- 奥義の溜め中に Flicker 等で位置が変わっても、固定の向きのまま新しい位置から撃つ（Flicker で向き・射程を変える仕様は未対応）。
- ボットの奥義は直前の tick の動きが続くと仮定するので、溜めの 0.5 秒の間に曲がる・止まる相手には外れる。
