# Eudora (MLBB) - Kit Specification

This is the revamped Eudora (Patch 2.1.47, main server 2026-01-28). Primary source: Mobile Legends Fandom hero page (fetched via the MediaWiki API, page edited 2026-10-01). Cross-checked against mlbbhub.com (patch 2.1.47 notes and revamp guide, descriptions only) and search extracts. "unknown" = not found. "disputed" = sources disagree. Ranges are in wiki "units".

## Hero overview
- Role / lane: Mage (Control/Burst), Mid Lane. Ranged, mana resource, magic damage. Ratings: durability 1, offense 8, control 8, difficulty 2.
- Basic attack: ranged single target, attack range 4.5, attack speed 1.00 base (very low growth). Projectile speed: unknown. (The pre-revamp passive "Electric Arrow" and its basic-attack stun are gone.)
- Level 1 stats: HP 2403, HP regen 7.6, mana 500, mana regen 4, physical attack 112, physical defense 19 (13.7% reduction), magic defense 15 (11.1%), attack speed 1.00, movement speed 250, crit damage 200%.
- Level 15 stats: HP 4771, regen 12.0, mana 1900, physical attack 193, physical defense 77, magic defense 50, attack speed 1.14.
- Growth per level: HP +169.14, regen +0.3143, mana +100, mana regen +0.2, physical attack +5.79, physical defense +4.1429, magic defense +2.5, attack speed +0.01.
- Max skill levels: S1 6, S2 6, Ultimate 3.

## Passive - Superconductor
- Cast type: passive on-hit mark.
- Eudora's skills inflict Superconductor on non-minion units they hit (heroes and, per mlbbhub, creeps/jungle monsters; not lane minions) and can trigger extra effects against units already marked.
- Duration: disputed. Fandom says 5 s; mlbbhub's guide says marks last 3 s. Refresh/consume rules: unknown.

## Skill 1 - Forked Lightning
- Cast type: cone (fan-shaped area) in the aimed direction.
- Deals 275-500 (+100% total magic power) magic damage to enemies in the fan, increased to 200% against minions. Applies Superconductor.
- If it hits a Superconductor target, Eudora forms a lightning chain with that target and gains 40% movement speed during the chain for up to 1 s. The chain deals 10-20 (+4% total magic power) damage over time and an extra 275-500 (+100% total magic power) when it ends. If this end hit lands, the skill's cooldown is reduced.
- Cooldown reduction: disputed. Fandom says 50%; mlbbhub says 1.5 s (level 6 cooldown 5 s drops to 3.5 s). Use a fixed 1.5 s pending in-game confirmation.
- Cooldown 7.0/6.6/6.2/5.8/5.4/5.0 s. Mana 50/54/58/62/66/70. Spell vamp ratio 50%. Base damage 275/320/365/410/455/500; trigger (DoT) damage 10/12/14/16/18/20; delayed damage 275/320/365/410/455/500.
- Fan angle, range, chain length and whether the chain breaks when the target leaves range: unknown.

## Skill 2 - Ball Lightning
- Cast type: point-and-click on the target enemy (an orb is hurled at the target).
- Reduces the target's magic defense by 10-25 for 1.8 s, deals 300-400 (+50% total magic power) magic damage, and stuns for 1 s. Applies Superconductor.
- If the target already has Superconductor, the orb also reduces the magic defense of nearby enemies, deals AoE damage centered on the target, and stuns all nearby enemies.
- Disputed wording: Fandom says AoE centered on the target; the official patch description (via mlbbhub) says the orb bounces to nearby enemies. Radius or bounce count: unknown.
- Cooldown 11.0/10.5/10.0/9.5/9.0/8.5 s. Mana 70/75/80/85/90/95. Magic defense reduction 10/13/16/19/22/25. Base damage 300/320/340/360/380/400.
- Stun is "basic level" CC per the wiki glossary: prevents movement, basic attacks and skills, and can interrupt some skills.

## Ultimate - Thunder's Wrath
- Cast type: ground target (area) skill, called down at the target area. Cast range and delay: unknown.
- Deals 600-1000 (+160% total magic power) magic damage to targets at the center, then 300-500 (+100% total magic power) to targets outside the center (outer ring).
- Each time it hits a Superconductor target, a Thunderburst triggers centered on that target after a short delay (delay value unknown), dealing 300-550 (+110% total magic power) magic damage. Multiple marked targets each cause their own burst (overlapping).
- Cooldown 32/29/26 s. Mana 130/160/190. Base damage 600/800/1000; delayed (outer ring) damage 300/400/500; diffusion (Thunderburst) 300/425/550.
- Center and outer radius: unknown.

## Gameplay identity
- Burst-and-control mid mage: single-target kill combo S1 > S2 > Ultimate (mlbbhub cites about 3,290 raw damage at level 8 with starter items).
- Superconductor is applied before the heavy hitters land, so sequencing decides impact: apply with S1 first, then use S2/ult to get AoE.
- Teamfight opener variants: Ultimate > S2 > S1, or Flicker > S2 > Ultimate > S1 for a pick.
- Forked Lightning's cooldown refund and speed boost give her chase and wave-clear (double damage on minions).
- Squishy (durability 1) with the stun as her only peel.

## Simulation notes
- Standard: ranged basic attack, cone skillshot, point-and-click stun, ground-target AoE with delay, magic-defense shred debuff (timed), minion damage multiplier, move speed buff.
- Needs special state: Superconductor mark (per-unit debuff with timer, applied by every skill, not on lane minions) that changes the skill's behavior; chain link between Eudora and the target (1 s, DoT then delayed hit, cooldown refund only if the final hit lands); S2 conditional AoE/bounce stun depending on mark; ultimate spawning per-marked-target delayed Thunderburst events; skill-level-scaled magic defense reduction.

## Sources
- https://mobile-legends.fandom.com/wiki/Eudora
- https://mobile-legends.fandom.com/wiki/Eudora/Patch_history (older history only; revamp not listed)
- https://mlbbhub.com/patch-notes/2.1.47
- https://mlbbhub.com/news/eudora-revamp-guide-build-combos-mid-lane
- https://liquipedia.net/mobilelegends/Patch_2.1.47 (listed in search, not fetched)

## 公式（Fandom 現行）の数値

Fandom のヒーローのページ（MediaWiki API で 2026-10-10 に再取得。スキルの Lv は S1・S2 が 1〜6、アルティメットが 1〜3）。日本語クライアントの画面は手元に無いので、
Fandom の英語の説明文の構造を正とする（タグも Fandom の `skill-effect`）。上の調査で「割れている」とした値は、ここで Fandom の値を採った。

| スロット | 公式名 | タグ | CD | MP | 内容（Lv1 → Lv6 / Lv3） |
|---|---|---|---|---|---|
| パッシブ | Superconductor | Buff | – | – | スキルが命中したミニオン以外のユニットに 5 秒の Superconductor を付ける。Superconductor の敵には各スキルが追加効果を起こす |
| スキル1 | Forked Lightning | AOE | 7.0 / 6.6 / 6.2 / 5.8 / 5.4 / 5.0 | 50 / 54 / 58 / 62 / 66 / 70 | 扇形の範囲に 275 / 320 / 365 / 410 / 455 / 500(+100%魔法攻撃)の魔法ダメージ（ミニオンには 200%）。Superconductor の敵に当たるとその敵と雷の鎖を結び、鎖の間（最大 1 秒）移動速度 +40%。鎖は継続して 10 / 12 / 14 / 16 / 18 / 20(+4%魔法攻撃)、終わりに 275 → 500(+100%魔法攻撃)の魔法ダメージ。終わりの一撃が当たると、このスキルのクールダウンを **50%** 短縮。スペルヴァンプ 50% |
| スキル2 | Ball Lightning | CC・Damage | 11.0 / 10.5 / 10.0 / 9.5 / 9.0 / 8.5 | 70 / 75 / 80 / 85 / 90 / 95 | 対象の敵へ雷球を投げ、1.8 秒間 魔法防御 −10 / 13 / 16 / 19 / 22 / 25、300 / 320 / 340 / 360 / 380 / 400(+50%魔法攻撃)の魔法ダメージ + 1 秒のスタン。対象が Superconductor なら、周囲の敵にも魔防ダウン・対象中心の範囲ダメージ・スタン |
| アルティメット | Thunder's Wrath | Burst | 32 / 29 / 26 | 130 / 160 / 190 | 指定範囲に雷を落とし、中心の敵に 600 / 800 / 1000(+160%魔法攻撃)、続いて中心の外の敵に 300 / 400 / 500(+100%魔法攻撃)の魔法ダメージ。Superconductor の敵に当たるたび、その敵を中心に少し遅れて Thunderburst（300 / 425 / 550(+110%魔法攻撃)の魔法ダメージ） |

### 公式が置き換えた値

| 項目 | 以前の実装 | 公式 |
|---|---|---|
| 印の持続 | 5 秒（Fandom 5 秒 / mlbbhub 3 秒で割れていた） | 5 秒（確認） |
| S1 の終わりの一撃のクールダウン短縮 | 固定 1.5 秒（mlbbhub の値） | **50%**（Fandom の説明文） |
| S1 のダメージ | 1 撃 = 汎用 S1 × 0.55、継続ダメージ = 1 撃の 4% | **275 → 500(+100%) / 継続 10 → 20(+4%)** の表（換算 `s1Scale`） |
| S2 のダメージ | 汎用 S2 の元の値 × 0.81（ランクで +30% ずつ） | **300 → 400(+50%)** の表（ランクの伸びは小さい。換算 `s2Scale`） |
| アルティメットのダメージ | 中心 = 汎用の奥義 × 0.82、外側 = 中心の 0.5 倍、炸裂 = 中心の 0.40 倍 | **中心 600 / 800 / 1000(+160%)・外側 300 / 400 / 500(+100%)・炸裂 300 / 425 / 550(+110%)** の表（換算 `ultScale`） |
| マナ | マスターの 62 / 74 / 118（キットで変えられなかった） | **50 → 70 / 70 → 95 / 130・160・190**（`HeroKit.cost`） |
| ダメージの係数 | 汎用の式（攻撃力 45% × 0.6 + 魔力 80%） | 公式どおり**魔法攻撃（魔力）だけ**で伸びる（物理攻撃の係数は無い） |

ランクの対応: Velstria のスキルのランクは S1/S2 が 4 段、アルティメットが 3 段（`SkillSlot.maxRank`）。表は線形補間で写す（ランク 1 = Lv1、最大ランク = Lv6。
ランク r → Lv `1 + (r − 1) × 5 / 3`）。公式の表はどれも等差なので、補間は「最初と最後の値を結ぶ直線」と同じ。

## Velstria 実装対応表

H026 紫電のエウリア（アルカニスト・遠隔 550・Mana）= Velstria 版の Eudora。実装: `Packages/VelstriaCore/Sources/VelstriaCore/Systems/Kits/Kit_H026.swift`、
テスト: `Tests/VelstriaCoreTests/Kits/Kit_H026Tests.swift`、演出: `App/Battle/SkillFX/Heroes/FX_H026.swift`。
スロットは上の調査の順に割り当てる（スキル1 = Forked Lightning「分岐雷」、スキル2 = Ball Lightning「雷球」、
アルティメット = Thunder's Wrath「九天雷鳴」、パッシブ = Superconductor「超伝導」。名前は master の最終名。アプリ内の説明文は UI の用語を使う）。キットはロールの汎用パッシブ（スキル命中で他スキルの CD −0.6 秒）を **置き換える**。
距離は Velstria 単位（≈ MLBB × 100）。調査に無い値（扇の角度・鎖の切れる距離・炸裂の半径など）は下の「選んだ値」に書いた。
ダメージは Velstria 全体の係数（`Balance.Skills`）に合わせた換算で、MLBB の数値そのままではない。クールダウンは MLBB の秒数そのまま（6 段のランクを Velstria の 4 段・奥義 3 段へ線形補間。全体倍率 `cooldownScale` は 1.0）。

### 対応表（○ = 実装、△ = 簡略化、× = 見送り）

| 元の仕様 | 状態 | Velstria での実装・理由 |
|---|---|---|
| 遠隔・通常攻撃射程 4.5・ステータス（HP 2403 ほか） | △ | マスターデータの値（HP 2700 +172/Lv、射程 550、マナ 600）。通常攻撃は汎用のまま（旧パッシブの通常攻撃スタンは調査どおり無い） |
| パッシブ Superconductor: スキルが当たった非ミニオンに印、印の付いた敵に当たると追加効果 | ○ | `.mark` status（`KitTags.mark("H026","sc",owner:)`、1 スタック）。S1・S2・奥義（と炸裂・S2 の広がり）の命中で付与。ヒーロー・モンスター・人形に付き、ミニオン・構造物には付かない。印そのものはダメージを増やさない（調査に無い）。追加効果は各スキルが「付ける前の印」で判定 |
| 印の持続（Fandom 5 秒 / mlbbhub 3 秒） | △ | 5 秒（Fandom に従う）。命中のたびに 5 秒へ戻す。消費はしない（調査に不明。無限に鎖が繋がらないための制限は S1 の行を参照） |
| S1 Forked Lightning: 前方の扇に 275〜500 + 100%、ミニオンに 200% | ○ | 即時の扇（`.cone`、射程 650・半角 30°）。1 撃 = 汎用 S1 の 0.55 倍。ミニオンへは `outgoingDamageBonus` で +100%（S1 のみ） |
| S1 印の敵に当たる → 雷の鎖（最大 1 秒）: 移動速度 +40%、継続ダメージ 10〜20 + 4%、終わりに 275〜500 + 100% | ○ | `Kit.schedule`（中断可）で継続ダメージ 4 回（0.2 秒おき・1 撃の 4%）と 1 秒後の終わりの一撃（初撃と同じ）。術者に `speedBoost` 0.40（1 秒）。複数の印済みの敵には鎖がそれぞれ張られる。**同じ相手へは前の鎖から 6 秒（`chainLockout`。CD が半分だったころは 3 秒）経つまで結び直さない**（相手ごとのロックアウト。`KitState.ids[0...3]` + `timers[1...4]`、4 体まで）。印は消費しないので、制限が無いと S1 が当たるたびに鎖が繋がり、終わりの一撃のクールダウン短縮で回り続ける。総当たり勝率（アルカニスト中央値との差）は制限なし Lv1 +40 / Lv6 +15 / Lv12 +41 pt → 3 秒で Lv1 +4 / Lv6 +12 / Lv12 +28 pt（6 秒でもほぼ同じ）。印を消費する案は、印の付与と追加効果の順序をスキルごとに変える必要があり、制限だけで足りたので採らなかった |
| S1 終わりの一撃が当たるとクールダウン短縮（50% / 1.5 秒で資料が割れている） | ○ | S1 のクールダウン（CD 短縮込み）の **50%**（Fandom の現行の説明文。`HitEffect.refundCooldown`、`EuriaTuning.chainRefundRatio`。以前は mlbbhub の固定 1.5 秒、全体の CD が半分だったころは 0.75 秒）。当たらなければ（対象が倒れた・離れた・見えない・対象不可・術者がスタン）縮まない。練習場の `noCooldowns` を尊重 |
| 鎖の長さ・対象が離れたら切れるか（不明） | △ | 術者と対象の中心間 800 を超える、対象が倒れる・視界外・対象不可になる、術者がハード CC を受けると切れる（加速も終わる） |
| S1 ダメージ 275〜500 + 100% / 継続 10〜20 / 追加 275〜500 | ○ | 公式の表 `(275 → 500 + 1.0 × 魔力) × 4.0 × s1Scale`（初撃と終わりの一撃）、継続 1 回 `(10 → 20 + 0.04 × 魔力) × 4.0 × s1Scale`。以前は 1 撃 = 汎用 S1 の 0.55 倍・継続 = 1 撃の 4%。ランクは 4 段（元は 6 段） |
| S1 クールダウン 7.0 → 5.0 秒、マナ 50 → 70 | ○ | MLBB と同じ 7 → 5 秒（ランクで線形補間。以前は × 0.5 = 3.5 → 2.5 秒）。マナは `HeroKit.cost` で 50 → 70（以前はマスターの 62） |
| S2 Ball Lightning: 対象指定、魔防ダウン 10〜25（1.8 秒）、300〜400 + 50%、スタン 1 秒 | ○ | 対象指定（`.lineSkillshot` + `aim: .unit` + `requiresTarget`、射程 650）。追尾する雷球（速度 1800）。ダメージ後に `stun` 1.0 秒と `magicShred`（固定値 10 → 25 を 4 ランクで線形・1.8 秒）。射程内に敵が居なければコスト・CD を消費せず失敗 |
| S2 印済みなら周囲の敵にも魔防ダウン・範囲ダメージ・スタン（Fandom: 対象中心の範囲 / 公式文: 跳ねる） | △ | Fandom の「対象中心の範囲」を採用。半径 260 の敵（ミニオン含む。構造物除く）に同じダメージ。スタン 1 秒・魔防ダウンは**ヒーローとモンスターだけ**（ミニオンにはダメージのみ）。主対象は 1 度だけ。広がった先の非ミニオンにも印が付く |
| S2 魔防ダウンがダメージに掛かるか | △ | ダメージの後に付くので、その一撃には掛からない（以降のスキル・通常攻撃に効く） |
| S2 ダメージ・クールダウン、マナ 70 → 95 | ○ | 公式の表 `(300 → 400 + 0.5 × 魔力) × 3.0 × s2Scale`（以前は元のスキル値の 0.81 倍）。CD は MLBB と同じ 11 → 8.5 秒（線形補間）。マナは `HeroKit.cost` で 70 → 95（以前はマスターの 74） |
| 奥義 Thunder's Wrath: 地点指定、中心 600〜1000 + 160%、外側 300〜500 + 100% | ○ | `groundAoE`（射程 770）。0.8 秒の予告（`ZoneSystem` の delay）後、中心（半径 150）の敵に公式の表 `(600 / 800 / 1000 + 1.6 × 魔力) × 2.6 × ultScale`、外側（半径 300）の敵に `(300 / 400 / 500 + 1.0 × 魔力) × 2.6 × ultScale`（`DamageScaling.distance` を段差にして 1 回のヒットで切り替え。段差の倍率 = 外側 ÷ 中心で、魔力 0 なら 0.5。以前は汎用の奥義の 0.82 倍と、その 0.5 倍）。CC は無い（調査どおり） |
| 奥義 印の敵に当たるたび、その敵を中心に少し遅れて Thunderburst（300〜550 + 110%）。複数なら重なる | ○ | 印済みの敵 1 体につき、敵に追従する炸裂のゾーン（`followsTargetID`、半径 190・0.5 秒後）を 1 つ。ダメージは公式の表 `(300 / 425 / 550 + 1.1 × 魔力) × 2.6 × ultScale`（以前は中心の 0.40 倍）で、範囲内の全ての敵に当たる（複数の炸裂は重なって各自に当たる）。炸裂の前に対象が倒れれば不発。炸裂のゾーンの演出 ID はパッシブ（大雷とは別の演出） |
| 奥義の遅れ・半径（不明） | △ | 予告 0.8 秒・中心の半径 150・外側の半径 300・炸裂の遅れ 0.5 秒・炸裂の半径 190（下の「選んだ値」） |
| 奥義 CD 32/29/26 秒、マナ 130 → 190 | ○ | MLBB と同じ 32 / 29 / 26 秒。マナは `HeroKit.cost` で 130 / 160 / 190（以前はマスターの 118） |
| スキルのタグ（UI） | △ | パッシブ `buff`、スキル1 `aoe`、スキル2 `disrupt burst`、アルティメット `burst`（Fandom の Buff / AOE / CC・Damage / Burst。「Damage」はタグの語彙 `KitTag` に無いので近い バースト にした） |
| 奥義のダメージ（予算） | △ | 公式の表 × `ultScale` 0.28（中心だけで汎用の約 0.5 倍、印済みの単体 = 中心 + 炸裂で約 0.75 倍）。以前は中心 0.82 倍・印済み約 1.15 倍。下の「公式の数値に合わせる」 |
| スペルヴァンプ 50% | × | 汎用のスペルヴァンプ（装備）のままで、スキル専用の比率は無い |
| 再使用（recast） | – | Eudora には無いので使わない（窓は開かない） |

### 選んだ値（調査に無い・換算した値）

| 項目 | 値 | 理由 |
|---|---|---|
| S1 扇 | 射程 650・半角 30° | 遠隔スキルの標準射程。調査に角度は無い |
| 鎖が切れる距離 | 術者と対象の中心間 800 | S1 の射程に余裕を足した値。加速で追えば保てる |
| 継続ダメージ | 0.2 秒おき 4 回・1 回 = 公式の 10 → 20(+4%) の換算 | 「継続して」の回数・間隔は公式に無い（1 回あたりの値と読んだ） |
| 雷球の速度 | 1800 | 対象指定の追尾弾。約 0.3 秒で届く |
| S2 広がりの半径 | 260 | 調査に無い。ヒーロー数体を巻き込める広さ |
| 奥義 予告・半径 | 0.8 秒・中心 150 / 外側 300 | 汎用のアルカニストの奥義（1.0 秒・半径 279）より少し短く速い |
| 炸裂 | 0.5 秒後・半径 190・公式の 300 / 425 / 550(+110%) | 遅れと半径は調査に無い。ダメージは 2026-10 から公式の表（以前は中心の 0.40 倍） |
| ダメージの換算 | S1 0.343（× 4.0）/ S2 0.644（× 3.0）/ 奥義 0.28（× 2.6） | 公式の表に掛ける。1v1 の勝率で決めた（下の「公式の数値に合わせる」。以前は汎用の S1 0.55 ×2 / S2 0.81 / 奥義 0.82 倍） |
| 鎖のロックアウト | 同じ相手に 6 秒 | 上の S1 の行。全体の CD が半分だったころは、勝率の差が 6 秒でもほぼ同じだったので当時の S1 の CD（約 3.5 秒）に近い 3 秒にした。CD が MLBB の秒数（7 → 5 秒、終わりの一撃で −1.5 秒）になって 3 秒では CD 短縮なしに一度も効かないので、CD に対する割合を保って 6 秒にした |
| 説明文の数値 | 名前で引くトークン: `{base}` / `{mpPct}`（換算後の基礎と魔力の割合）、S1 `{dotBase}` `{dotPct}` `{refund}`（%）`{lockout}`、S2 `{shred}` `{stun}` `{splashRadius}`、奥義 `{outerBase}` `{outerPct}` `{burstBase}` `{burstPct}` `{delay}` `{centerRadius}` | `KitText` のトークンに sim の数値を入れる。文は公式（Fandom）の説明文の構造 |

### 検証した 1v1 の目安

- `Kit_H026Tests.testDuelTimeToKillStaysInBandAgainstTheRoleRepresentatives`: H001〜H006 相手の TTK は Lv 1 / 6 / 12 とも 2.5〜22 秒（CD が半分だったころの帯は 2.5〜15 秒）（実測 4.3〜10.7 秒）。
- 計測ハーネス（`BalanceHarness` / `KitBalanceTests`、Release）の勝率（アルカニスト中央値との差、pt）: 調整前 Lv1 +40 / Lv6 +20 / Lv12 +41 → 調整後は下の「バランス調整」の表。
- `Kit_H026Tests.testRoundRobinWinRateAgainstTheWholeRosterIsNotExtreme`: 全 33 体との総当たり（`SkillBalanceTests.duel`）の勝率は Lv6 48.5%・Lv12 60.6%。
  この総当たりは「奥義 → S1 → S2」の固定順で撃つため、S1 で印を付けてから S2・奥義を使うエウリア本来の連携（ボットは `botCast` で守る）は含まない。

### 既知の差・リスク

- スキルのマナ（コスト）は 2026-10 から公式の表（S1 50 → 70、S2 70 → 95、奥義 130 / 160 / 190。`HeroKit.cost`）。Velstria の最大マナは 600 でレベルで増えないので、MLBB より早くマナが尽きる。
- 雷の鎖には専用のイベントが無い。App 側の演出は、継続ダメージの 1 回ごとと終わりの一撃のダメージ（`hit`、`hitPerHit`）に、術者 → 被弾者の線上へ走る短い稲妻の筋を出して鎖を表す（`.along` アンカー。扇の初撃にも同じ筋が出る。画質 1 以上）。鎖の残りはバッジの残り秒と移動速度でも分かる。
- S2 の広がりは Fandom の「範囲」解釈。公式文の「跳ねる」（バウンス）は再現していない。
- 印は消費しないので、5 秒の間は S2 の広がり・奥義の炸裂は何度でも起きる（調査に消費の記載が無い）。S1 の鎖だけは同じ相手に 6 秒に 1 回まで。
- `SkillFXDirector` は stage / count / duration を読まない。炸裂の演出はパッシブの telegraph / impact で表した。

### バランス調整とボット（2 回目の見直し）

- 総当たり勝率（アルカニスト中央値との差）が Lv1 +40 / Lv6 +20 / Lv12 +41 pt だったので、S1 の鎖のロックアウト（同じ相手に 3 秒）・S2 0.85 → 0.81・奥義 0.85 → 0.82・炸裂 0.47 → 0.40 で下げた。
  S2 の広がりのスタン・魔防ダウンはミニオンに広げない（ダメージは広げる）。
- ボット（`botCast`）: 印の無い敵には、S1 が**実際に撃てる**（CD 明け・マナあり・行動可能・敵が扇の射程 650 + 半径の内）あいだだけ、アルティメットを見送って S1 → 印 → 重い技の順にする。
  S1 が撃てないとき（CD・マナ不足・沈黙・射程の外）は待たない。S2 は近くに別のヒーローが居るとき（印が広がる）だけ印を待ち、居なければ先に撃つ（S2 自身が印を付ける）。
  クールダウンが MLBB の秒数になってからは、S1（7 → 5 秒）が印（5 秒）より長く、S1 → 印 → S1 では鎖が繋がらないので、近くに別のヒーローが居ない印の無い敵に S2 が撃てるなら **S1 も待つ**（S2 = 印 + スタン → S1 = 鎖。雷球が飛んでいる間も着弾を待つ）。
- 説明文は master の名前（分岐雷 / 雷球 / 九天雷鳴）と UI の用語（スキル1 / スキル2 / アルティメット）に統一した。
- Release の最終計測（アルカニスト中央値 25.0 / 28.8 / 27.0 %）: Lv1 19.2 (-5.8) / Lv6 39.6 (+10.9) / Lv12 46.5 (+19.4) pt（見直し前 +40.2 / +20.3 / +41.4）。開幕 3 秒の瞬間火力の比は Lv1 0.31 / Lv6 0.79 / Lv12 0.89（見直し前 0.31 / 0.84 / 0.95。Lv1 はスキル1 しか覚えていないため低い）。

### クールダウンを MLBB の秒数に（2026-10）

- 全体の CD 倍率 0.5 を廃止（S1 7 → 5 秒、S2 11 → 8.5 秒、奥義 32 / 29 / 26 秒）。終わりの一撃の短縮は MLBB の 1.5 秒、鎖のロックアウトは CD に対する割合を保って 3 → 6 秒。
- S1 の CD が印（5 秒）より長くなり、固定順の台本（奥義 → S1 → S2）では鎖がほとんど繋がらない。ボットは S2 → S1 の順に撃つ（上の「ボット」）。
- `KitBalanceTests`（アルカニスト中央値との差）: 変更前 −11.4 / +13.6 / +24.0 → 変更後 −21.2 / +1.6 / +24.1 pt。総当たりの下限の確認（`testRoundRobinWinRateAgainstTheWholeRosterIsNotExtreme`）は 25% → 20% にした（Lv6 21%）。

### 公式の数値に合わせる（2026-10）

上の「公式（Fandom 現行）の数値」を正として、マナ・ダメージの表をランクへ線形補間し、終わりの一撃の短縮を公式の 50% にした（クールダウンは変更済み。方法は H029 ボルグ = Tigreal と同じ）。
ダメージは `(公式の基礎 + 係数 × 魔力) × スロット倍率 × 換算`（`EuriaTuning.s1Scale` ほか）。公式どおり魔法攻撃（魔力）だけで伸び、以前の汎用の式にあった物理攻撃の係数（0.45 × 0.6）は持たない。数値は魔力 0（装備なし）。

| 項目 | 公式 | 以前 | 今 |
|---|---|---|---|
| パッシブ 超伝導 | 5 秒 | 5 秒 | 5 秒（同じ） |
| S1 CD / マナ | 7.0 → 5.0 秒・50 → 70 | 7.0 → 5.0 秒・62（マスター） | 7.0 / 6.33 / 5.67 / 5.0 秒・50 / 56.7 / 63.3 / 70 |
| S1 1 撃（初撃・終わりの一撃） | 275 → 500(+100%魔法攻撃) | 汎用 S1 × 0.55（r1 377 / Lv12 r4 688） | (275 → 500 + 1.0 × 魔力) × 4.0 × 0.343（ランク 1〜4: 377 / 480 / 583 / 686） |
| S1 継続ダメージ（1 回 × 4） | 10 → 20(+4%) | 1 撃の 4%（15 / 28） | (10 → 20 + 0.04 × 魔力) × 4.0 × 0.343（14 / 27） |
| S1 終わりの一撃の短縮 | クールダウンの 50% | 固定 1.5 秒 | S1 のクールダウン（CD 短縮込み）の 50%（3.5 → 2.5 秒） |
| S1 鎖の加速 | +40%（最大 1 秒） | 同じ | 同じ |
| S2 CD / マナ | 11.0 → 8.5 秒・70 → 95 | 11.0 → 8.5 秒・74（マスター） | 11.0 / 10.17 / 9.33 / 8.5 秒・70 / 78.3 / 86.7 / 95 |
| S2 ダメージ | 300 → 400(+50%) | 元のスキル値 × 0.81（Lv6 r2 644 / Lv12 r4 917） | (300 → 400 + 0.5 × 魔力) × 3.0 × 0.644（580 / 644 / 708 / 773） |
| S2 CC・魔防ダウン | スタン 1 秒、魔防 −10 → 25（1.8 秒） | 同じ | 同じ |
| 奥義 CD / マナ | 32 / 29 / 26 秒・130 / 160 / 190 | 32 / 29 / 26 秒・118（マスター） | 32 / 29 / 26 秒・130 / 160 / 190 |
| 奥義 中心 | 600 / 800 / 1000(+160%) | 汎用の奥義 × 0.82（Lv6 r1 766 / Lv12 r3 1193） | (600 / 800 / 1000 + 1.6 × 魔力) × 2.6 × 0.28（437 / 582 / 728） |
| 奥義 外側 | 300 / 400 / 500(+100%) | 中心 × 0.5 | (300 / 400 / 500 + 1.0 × 魔力) × 2.6 × 0.28（218 / 291 / 364） |
| 奥義 Thunderburst | 300 / 425 / 550(+110%) | 中心 × 0.40（306 / 477） | (300 / 425 / 550 + 1.1 × 魔力) × 2.6 × 0.28（218 / 309 / 400） |
| タグ | Buff / AOE / CC・Damage / Burst | なし | `buff` / `aoe` / `disrupt burst` / `burst` |

- 説明文（`KitText` ja/en）は公式の文の構造（「扇形の範囲に分岐雷を放ち、範囲内の敵に{base}(+{mpPct}%魔法攻撃)の魔法ダメージを与える（ミニオンには200%）。」の 3 段落など）に合わせた。名前は master（超伝導 / 分岐雷 / 雷球 / 九天雷鳴）。
- ボットの「S1 が撃てるか」のマナの確認を、マスターのコストからキットのランク別のコスト（`SkillSystem.cost(for:hero:rank:)`）に直した。
- 換算の選び方（`KitBalanceTests` の総当たり、アルカニスト中央値との差）: ランク 1 が以前の値と同じになる換算（S1 0.343 / S2 0.644 / 奥義 0.49）では、公式の炸裂（中心の 0.5〜0.55 倍。以前は 0.40 倍）と
  50% の短縮（以前の 1.5 秒より長い）で Lv6 +25 / Lv12 +38 pt になった（短縮を 0 にしても Lv6 +9 / Lv12 +26）。S1 の鎖のロックアウト（6 / 9 / 12 秒）は勝率を変えなかった。
  S1・S2 はそのまま（S2 はランク 2 = Lv6 が以前と同じ）、奥義を 0.28 に下げて Lv6・Lv12 を中央値の近くにした（例: S2 0.55・奥義 0.32 は Lv6 −7 / Lv12 +7、S2 0.60・奥義 0.30 は Lv6 −7 / Lv12 +8、S2 0.50・奥義 0.38 は Lv6 −1 / Lv12 +14）。
- Lv1 は帯（−15 pt）の外のまま（以前も −21.2）。Lv1 は S1 しか覚えておらず、S1 の CD（7 秒）が印（5 秒）より長いので自分の S1 では鎖が繋がらない（公式どおり）。
  Lv1 を帯に入れるには S1 の換算 0.49 以上が要るが（0.45 で Lv1 5%、0.49 で 11%、0.50 で 18%）、そうすると鎖で Lv6 / 12 が +17〜+50 pt になる（奥義を 0.24 まで下げても Lv12 +27）。
- `KitBalanceTests`（Release、アルカニスト中央値 21.2 / 30.2 / 21.7 %）: 変更前 −21.2 / +1.6 / +24.1 → 変更後 0.0 / 28.8 / 31.1 % = **−21.2 / −1.4 / +9.3 pt**（Lv1 / 6 / 12）。開幕 3 秒の瞬間火力の比 0.31 / 0.69 / 0.77。全員との総当たり（`SkillBalanceTests.duel`、`testRoundRobinWinRateAgainstTheWholeRosterIsNotExtreme`）は Lv6 21.2% / Lv12 27.3%（下限 20%）。
