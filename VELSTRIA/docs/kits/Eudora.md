# Eudora (MLBB) - Kit Specification

> 2026-10-14: ヒーローの能力値（HP・物理攻撃・防御・魔防・攻撃速度・HP 回復・マナ・移動速度・射程・リソースの種類）と能力値の式（防御 120/(120+防御)・クリティカル 200%・攻撃速度の加算・移動速度の加算式など）を MLBB の値へ置き換えた（`docs/HERO_STATS.md`）。この文書の能力値の記述（「マスターの値」「射程 550」「Mana 600」など）は置き換え前のもの。
> 同日、スキルも **公式の表をそのまま使う（スキル1・2 = 6 段、アルティメット = 3 段）** ように移した（換算・スロット倍率・補間なし。下の「スキルの段階: 公式の表をそのまま使う」）。

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

## 公式（日本語クライアント）の数値

エウドラ(Eudora)、ロール「メイジ」、サブタグ「コントロール/爆発力」（リワーク後の現行版）。2026-10-10 に受け取った日本語クライアントの実機のスクリーンショット
（スキル詳細の画面）の転記（スキルのレベルは S1・S2 が Lv1〜6、アルティメットが Lv1〜3）。**下の Fandom の値と違うところはこちらを正とする**
（違い: S1 の CD 7.0 → 5.0 の補間 → **全 Lv 5.0**、S1 の MP 50 → 70 → **40 → 65**、S2 の MP 70 → 95 → **80 → 105**、炸裂 300 / 425 / 550 → **330 / 440 / 550**、
炸裂は「超電導の対象に」当たる）。

| スロット | 公式名 | タグ | CD | MP | 内容 |
|---|---|---|---|---|---|
| パッシブ | 超電導状態 | バフ | – | – | スキルがミニオン以外のユニットに命中すると、5秒間超電導を付与。超電導の影響を受けている敵に対しては追加効果が発動 |
| スキル1 | フォークライトニング | 範囲技 | 5.0（一定） | 40 / 45 / 50 / 55 / 60 / 65 | スキル吸収率 50%。扇状の範囲に 275 / 320 / 365 / 410 / 455 / 500(+100%魔法攻撃)の魔法ダメージ（ミニオンには 200%）。超電導の対象に命中すると、対象との間に雷の鎖を形成し、鎖が存在する間、移動速度 +40%（最大 1 秒）。雷の鎖は継続的に 10 / 12 / 14 / 16 / 18 / 20(+4%魔法攻撃)の魔法ダメージ、終了時に追加で 275 → 500(+100%魔法攻撃)の魔法ダメージ。この追加ダメージが命中した場合、このスキルの CD を 50% 短縮 |
| スキル2 | エレキアロー | 妨害・攻撃 | 11.0 / 10.5 / 10.0 / 9.5 / 9.0 / 8.5 | 80 / 85 / 90 / 95 / 100 / 105 | 対象の敵に雷のオーブを放ち、1.8 秒間魔法防御を 10 / 13 / 16 / 19 / 22 / 25 低下させ、300 / 320 / 340 / 360 / 380 / 400(+50%魔法攻撃)の魔法ダメージ、1 秒スタン。対象が超電導の場合、オーブは周囲の敵の魔法防御を低下させ、対象を中心に範囲ダメージを与え、周囲の敵をすべてスタン |
| アルティメット | サンダーストローク | 爆発力 | 32 / 29 / 26 | 130 / 160 / 190 | 指定範囲に稲妻を落とし、中心の対象に 600 / 800 / 1000(+160%魔法攻撃)の魔法ダメージ。その後、中心の外側にいる対象に雷が落ち 300 / 400 / 500(+100%魔法攻撃)。雷の怒りが超電導の対象に命中するたび、短い遅延の後、その対象を中心としたサンダーバーストが発動し、超電導の対象に 330 / 440 / 550(+110%魔法攻撃)の魔法ダメージ |

タグの対応: バフ = `buff`、範囲技 = `aoe`、妨害・攻撃 = `disrupt` `damage`、爆発力 = `burst`。
印の持続は 5 秒（Liquipedia・mlbbhub の 3 秒は古い）。

2026-10-11 に受け取った無加工の原本（日本語クライアントのスキル詳細の画面 IMG_4512〜4521。画像はコミットしない）と照合した: 上の表の数値（S1 の CD 5.0 一定・MP・基礎 / 発動 / 遅延ダメージ、
S2 の CD・MP・魔法防御減少 10〜25・1.8 秒・スタン 1 秒、アルティメットの CD・MP・基礎 / 遅延 / 拡散ダメージ 330 / 440 / 550）・タグ（バフ / 範囲技 / 妨害・攻撃 / 爆発力）・文の構造は一致した（変更なし）。
原本の表記は「超**電**導」で、Velstria の名前（マスター・HUD・説明文）は「超伝導」のまま（同じ語の表記の違い）。

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
| S1 のダメージ | 1 撃 = 汎用 S1 × 0.55、継続ダメージ = 1 撃の 4% | **275 → 500(+100%) / 継続 10 → 20(+4%)** の表 |
| S2 のダメージ | 汎用 S2 の元の値 × 0.81（ランクで +30% ずつ） | **300 → 400(+50%)** の表 |
| アルティメットのダメージ | 中心 = 汎用の奥義 × 0.82、外側 = 中心の 0.5 倍、炸裂 = 中心の 0.40 倍 | **中心 600 / 800 / 1000(+160%)・外側 300 / 400 / 500(+100%)・炸裂 300 / 425 / 550(+110%)** の表（炸裂は日本語クライアントで 330 / 440 / 550） |
| マナ | マスターの 62 / 74 / 118（キットで変えられなかった） | **50 → 70 / 70 → 95 / 130・160・190**（`HeroKit.cost`。日本語クライアントで 40 → 65 / 80 → 105） |
| ダメージの係数 | 汎用の式（攻撃力 45% × 0.6 + 魔力 80%） | 公式どおり**魔法攻撃（魔力）だけ**で伸びる（物理攻撃の係数は無い） |

この節の値のうち日本語クライアントと違うもの（S1 の CD・マナ、S2 のマナ、炸裂）は、上の「公式（日本語クライアント）の数値」を正とする。

## Velstria 実装対応表

H026 紫電のエウリア（アルカニスト・遠隔 550・Mana）= Velstria 版の Eudora。実装: `Packages/VelstriaCore/Sources/VelstriaCore/Systems/Kits/Kit_H026.swift`、
テスト: `Tests/VelstriaCoreTests/Kits/Kit_H026Tests.swift`、演出: `App/Battle/SkillFX/Heroes/FX_H026.swift`。
スロットは上の調査の順に割り当てる（スキル1 = Forked Lightning「分岐雷」、スキル2 = Ball Lightning「雷球」、
アルティメット = Thunder's Wrath「九天雷鳴」、パッシブ = Superconductor「超伝導」。名前は master の最終名。アプリ内の説明文は UI の用語を使う）。キットはロールの汎用パッシブ（スキル命中で他スキルの CD −0.6 秒）を **置き換える**。
距離は Velstria 単位（≈ MLBB × 100）。調査に無い値（扇の角度・鎖の切れる距離・炸裂の半径など）は下の「推測の値」に書いた。
**公式の表をそのまま使う（6 / 6 / 3 段）**: スキル1・2 は Lv1〜6、アルティメットは Lv1〜3 の日本語クライアントの表をランクでそのまま引く（`Kit.level`。補間なし）。
ダメージ = 公式の基礎 + 公式の係数 × 魔法攻撃（`Kit.official(…, .magicPower, …)`。換算・スロット倍率なし）。クールダウン = 公式の秒数 × (1 − CD 短縮)（`Kit.cooldown`）。

### 対応表（○ = 実装、△ = 簡略化、× = 見送り）

| 元の仕様 | 状態 | Velstria での実装・理由 |
|---|---|---|
| 遠隔・通常攻撃射程 4.5・ステータス（HP 2403 ほか） | ○ | 2026-10-14 から MLBB の値（`docs/HERO_STATS.md`: HP 2440 → 4890、射程 470、マナ 500 → 1900）。通常攻撃は汎用のまま（旧パッシブの通常攻撃スタンは調査どおり無い） |
| パッシブ Superconductor: スキルが当たった非ミニオンに印、印の付いた敵に当たると追加効果 | ○ | `.mark` status（`KitTags.mark("H026","sc",owner:)`、1 スタック）。S1・S2・奥義（と炸裂・S2 の広がり）の命中で付与。ヒーロー・モンスター・人形に付き、ミニオン・構造物には付かない。印そのものはダメージを増やさない（調査に無い）。追加効果は各スキルが「付ける前の印」で判定 |
| 印の持続（日本語クライアント 5 秒。Liquipedia・mlbbhub は 3 秒） | ○ | 5 秒（日本語クライアントに従う）。命中のたびに 5 秒へ戻す。消費はしない（調査に不明） |
| S1 フォークライトニング: 前方の扇に 275〜500 + 100%、ミニオンに 200%、スキル吸収率 50% | ○ | 即時の扇（`.cone`、射程 650・半角 30°）。1 撃 = 公式の 275 / 320 / 365 / 410 / 455 / 500(+100% 魔法攻撃)。ミニオンには `HitPayload.minionMultiplier` = 2.0（200%。扇の一撃。鎖は超伝導の対象だけなのでミニオンには結ばれない。以前は与ダメ補正 +100% を他の補正と足し算し、さらに全体の × 0.2 で 0.4 倍だった）。スキル吸収率 50%（`spellVampRatio` = 0.5。扇・鎖の継続ダメージ・終わりの一撃のすべて） |
| S1 印の敵に当たる → 雷の鎖（最大 1 秒）: 移動速度 +40%、継続ダメージ 10〜20 + 4%、終わりに 275〜500 + 100% | ○ | `Kit.schedule`（中断可）で継続ダメージ 4 回（0.2 秒おき・1 回 = 公式の 10 / 12 / 14 / 16 / 18 / 20(+4%)）と 1 秒後の終わりの一撃（初撃と同じ）。術者に `speedBoost` 0.40（1 秒）。複数の印済みの敵には鎖がそれぞれ張られる。**同じ相手にも詠唱のたびに結ぶ**（以前の「同じ相手には 6 秒に 1 回」のロックアウト `chainLockout` はバランスのための独自の制限で、外した。下の「外した独自の制限」） |
| S1 終わりの一撃が当たるとクールダウン 50% 短縮 | ○ | S1 のクールダウン（CD 短縮込み）の **50%**（日本語クライアント・Fandom の説明文。`EuriaTuning.chainRefundRatio`）。**1 回の詠唱につき 1 回**（複数の鎖の終わりの一撃が当たっても 50% のまま。`KitState.ints[5]` = 詠唱の通し番号、`ints[6]` = 短縮を済ませた番号）。当たらなければ（対象が倒れた・離れた・見えない・対象不可・術者がスタン）縮まない。練習場の `noCooldowns` を尊重 |
| 鎖の長さ・対象が離れたら切れるか（不明） | △ | 術者と対象の中心間 800 を超える、対象が倒れる・視界外・対象不可になる、術者がスタン以上の CC を受けると切れる（加速も終わる） |
| S1 クールダウン 5.0 秒（全 Lv。日本語クライアント）、マナ 40 → 65 | ○ | 全ランク 5 秒。マナは `HeroKit.cost` で 40 / 45 / 50 / 55 / 60 / 65 |
| S2 エレキアロー: 対象指定、魔防ダウン 10〜25（1.8 秒）、300〜400 + 50%、スタン 1 秒 | ○ | 対象指定（`.lineSkillshot` + `aim: .unit` + `requiresTarget`、射程 650）。追尾する雷球（速度 1800）。ダメージ後に `stun` 1.0 秒（基本の CC）と `magicShred`（固定値 10 / 13 / 16 / 19 / 22 / 25・1.8 秒）。ダメージは公式の 300 / 320 / 340 / 360 / 380 / 400(+50%)。射程内に敵が居なければコスト・CD を消費せず失敗 |
| S2 印済みなら周囲の敵にも魔防ダウン・範囲ダメージ・スタン（Fandom: 対象中心の範囲 / 公式文: 跳ねる） | △ | Fandom・日本語クライアントの「対象を中心に範囲ダメージ」を採用。半径 260 の敵（**ミニオン含む**。構造物除く）に同じダメージ・スタン 1 秒・魔防ダウン（公式「周囲の敵をすべてスタン」。以前の「ミニオンにはダメージのみ」は外した）。主対象は 1 度だけ。広がった先の非ミニオンにも印が付く |
| S2 魔防ダウンがダメージに掛かるか | △ | ダメージの後に付くので、その一撃には掛からない（以降のスキル・通常攻撃に効く。公式の文は魔防ダウンを先に書くが、掛かるかは未確認） |
| S2 クールダウン・マナ（日本語クライアント） | ○ | CD 11.0 / 10.5 / 10.0 / 9.5 / 9.0 / 8.5 秒。マナは `HeroKit.cost` で 80 / 85 / 90 / 95 / 100 / 105 |
| 奥義 サンダーストローク: 地点指定、中心 600〜1000 + 160%、外側 300〜500 + 100% | ○ | `groundAoE`（射程 770）。0.8 秒の予告（`ZoneSystem` の delay）後、中心（半径 150）の敵に公式の 600 / 800 / 1000(+160%)、外側（半径 300）の敵に 300 / 400 / 500(+100%)（`DamageScaling.distance` を段差にして 1 回のヒットで切り替え。段差の倍率 = 外側 ÷ 中心で、魔力 0 なら 0.5）。CC は無い（調査どおり） |
| 奥義 印の敵に当たるたび、その敵を中心に少し遅れてサンダーバースト（330 / 440 / 550 + 110%）が**超電導の対象に**当たる。複数なら重なる | ○ | 印済みの敵 1 体につき、敵に追従する炸裂の見た目のゾーン（`followsTargetID`、半径 190・0.5 秒後。敵には当たらない）と、同じ 0.5 秒後の予約（`Code.burst`、非中断）を 1 つずつ。予約が発動すると、その時点の対象の位置から半径 190 の**超伝導（この術者の印）が付いた敵だけ**に公式の 330 / 440 / 550(+110%)（印の付かないミニオンには当たらない）。複数の炸裂は重なって各自に当たる。炸裂の前に対象が倒れれば不発、術者が倒れると予約ごと消える。演出 ID はパッシブ（大雷とは別の演出） |
| 奥義の遅れ・半径（不明） | △ | 予告 0.8 秒・中心の半径 150・外側の半径 300・炸裂の遅れ 0.5 秒・炸裂の半径 190（下の「推測の値」） |
| 奥義 CD 32/29/26 秒、マナ 130 → 190 | ○ | 32 / 29 / 26 秒。マナは `HeroKit.cost` で 130 / 160 / 190 |
| スキルのタグ（UI） | ○ | パッシブ `buff`、スキル1 `aoe`、スキル2 `disrupt damage`、アルティメット `burst`（日本語クライアントの バフ / 範囲技 / 妨害・攻撃 / 爆発力） |
| スキル吸収率（S1 50%） | ○ | `HitPayload.spellVampRatio` = 0.5（S1 の全ての命中）。S2・奥義は公式に記載が無いので既定の 100% |
| 再使用（recast） | – | Eudora には無いので使わない（窓は開かない） |

### 推測の値（公式に無い距離・時間・回数）

| 項目 | 値 | 理由 |
|---|---|---|
| S1 扇 | 射程 650・半角 30° | 遠隔スキルの標準射程。調査に角度は無い |
| 鎖が切れる距離 | 術者と対象の中心間 800 | S1 の射程に余裕を足した値。加速で追えば保てる |
| 継続ダメージ | 0.2 秒おき 4 回・1 回 = 公式の 10 / 12 / 14 / 16 / 18 / 20(+4%) そのまま | 「継続的に」の回数・間隔は公式に無い（1 回あたりの値と読んだ） |
| 鎖と術者の CC | 術者がスタン以上の CC を受けると鎖が切れる（中断できる予約） | 公式に無い。鎖を詠唱の続きとみなした |
| 終わりの一撃の短縮 | S1 のクールダウン（CD 短縮込み）の 50% を、1 回の詠唱につき 1 回 | 公式の文は「この追加ダメージが命中した場合、このスキルの CD を 50% 短縮」。残りの 50% か全体の 50% か、複数の鎖で重なるかは書いていない。重ねると 2 体で 100% になりクールダウンが消えるので、詠唱ごとの 1 回と読んだ（下の「外した独自の制限」） |
| 雷球の速度 | 1800 | 対象指定の追尾弾。約 0.3 秒で届く |
| S2 広がりの半径 | 260 | 調査に無い。ヒーロー数体を巻き込める広さ |
| 奥義 予告・半径 | 0.8 秒・中心 150 / 外側 300 | 汎用のアルカニストの奥義（1.0 秒・半径 279）より少し短く速い |
| 炸裂 | 0.5 秒後・半径 190 | 遅れと半径は調査に無い |
| 説明文の数値 | 名前で引くトークン: `{base}` / `{mpPct}`（公式の基礎と魔法攻撃の係数そのもの）、S1 `{dotBase}` `{dotPct}` `{refund}`（%）`{minionPct}` `{spellVamp}`、S2 `{shred}` `{stun}` `{splashRadius}`、奥義 `{outerBase}` `{outerPct}` `{burstBase}` `{burstPct}` `{delay}` `{centerRadius}` | `KitText` のトークンに sim の数値を入れる。文は日本語クライアントの説明文の構造 |

### 1v1 の目安

- 公式の表に移したので、以前の換算での計測（TTK・総当たりの勝率・`KitBalanceTests` のアルカニスト中央値との差）は無効。
  帯（`testDuelTimeToKillStaysInBandAgainstTheRoleRepresentatives` の 2.5〜22 秒、`testRoundRobinWinRateAgainstTheWholeRosterIsNotExtreme` の 20〜75%）の数値は変えていない。全キットを公式の表に移した後にまとめて測り直す。
- 総当たりは「奥義 → S1 → S2」の固定順で撃つため、S1 で印を付けてから S2・奥義を使うエウリア本来の連携（ボットは `botCast` で守る）は含まない。

### 既知の差・リスク

- 雷の鎖には専用のイベントが無い。App 側の演出は、継続ダメージの 1 回ごとと終わりの一撃のダメージ（`hit`、`hitPerHit`）に、術者 → 被弾者の線上へ走る短い稲妻の筋を出して鎖を表す（`.along` アンカー。扇の初撃にも同じ筋が出る。画質 1 以上）。鎖の残りはバッジの残り秒と移動速度でも分かる。
- S2 の広がりは「対象を中心に範囲」の解釈。パッチの説明（mlbbhub）の「跳ねる」（バウンス）は再現していない。
- 印は消費しないので、5 秒の間は S2 の広がり・奥義の炸裂・S1 の鎖は何度でも起きる（調査に消費の記載が無い）。
- 印の付いた相手に S1 を当て続けると、鎖が詠唱のたびに繋がり、S1 は約 2.5 秒ごと（5 秒 − 50%）に撃てる。止めるのはクールダウンとマナ（MLBB と同じ）。
- `SkillFXDirector` は stage / count / duration を読まない。炸裂の演出はパッシブの telegraph / impact で表した。
- まだ MLBB と違う・未確認: 距離・角度・時間（上の「推測の値」）、詠唱の動作の時間（Velstria は即時）、鎖の継続ダメージの回数、短縮が重なるか、S2 の魔防ダウンがその一撃に掛かるか、印が消費されるか。

### ボット

- ボット（`botCast`）: 印の無い敵には、S1 が**実際に撃てる**（CD 明け・マナあり・行動可能・敵が扇の射程 650 + 半径の内）あいだだけ、アルティメットを見送って S1 → 印 → 重い技の順にする。
  S1 が撃てないとき（CD・マナ不足・沈黙・射程の外）は待たない。S2 は近くに別のヒーローが居るとき（印が広がる）だけ印を待ち、居なければ先に撃つ（S2 自身が印を付ける）。
  S1 のクールダウン（5 秒）が印（5 秒）と同じで、S1 → 印 → S1 ではほとんど鎖が繋がらない（印が切れる tick と重なる）ので、近くに別のヒーローが居ない印の無い敵に S2 が撃てるなら **S1 も待つ**（S2 = 印 + スタン → S1 = 鎖。雷球が飛んでいる間も着弾を待つ）。
- 説明文は master の名前（分岐雷 / 雷球 / 九天雷鳴）と UI の用語（スキル1 / スキル2 / アルティメット）に統一した。
- ボットの「S1 が撃てるか」のマナの確認は、キットのランク別のコスト（`SkillSystem.cost(for:hero:rank:)`）で見る。

### 以前の段階（要約）

- 2026-10 まで: ダメージは `(公式の基礎 + 係数 × 魔力) × スロット倍率（4.0 / 3.0 / 2.6）× キットの換算（S1 0.343 / S2 0.644 / 奥義 0.28）`、
  S1・S2 の表は 4 段のランクへ線形補間（ランク r → Lv `1 + (r − 1) × 5 / 3`）していた。換算は 1v1 の総当たりの勝率（アルカニスト中央値との差）で選んだ値。
- 同じころ、バランスのために S1 の鎖のロックアウト（同じ相手に 3 秒 → 6 秒に 1 回）と、S2 の広がりのスタン・魔防ダウンをミニオンに広げない制限を足していた。
- 全体の CD 倍率 0.5 の廃止（MLBB の秒数へ）、日本語クライアントの数値（S1 の CD 5 秒一定・マナ・炸裂 330 / 440 / 550 が超電導の対象だけに当たる）への置き換えは済んでいた。

### スキルの段階: 公式の表をそのまま使う（2026-10-14）

公式の表をそのまま使う（スキル1・2 = 6 段、アルティメット = 3 段。`Balance.basicSkillMaxRank` = 6）。ランク = 公式の Lv。換算・スロット倍率・補間は使わない。
出典: 日本語クライアントのスキル詳細の画面（上の「公式（日本語クライアント）の数値」。REAL_DATA.md「H026 エウリア = エウドラ」）。

| 項目 | Lv1 | Lv2 | Lv3 | Lv4 | Lv5 | Lv6 | 係数 |
|---|---|---|---|---|---|---|---|
| S1 扇・終わりの一撃 | 275 | 320 | 365 | 410 | 455 | 500 | +100% 魔法攻撃 |
| S1 鎖の継続ダメージ（1 回） | 10 | 12 | 14 | 16 | 18 | 20 | +4% 魔法攻撃 |
| S1 CD（秒） | 5.0 | 5.0 | 5.0 | 5.0 | 5.0 | 5.0 | |
| S1 マナ | 40 | 45 | 50 | 55 | 60 | 65 | |
| S2 ダメージ | 300 | 320 | 340 | 360 | 380 | 400 | +50% 魔法攻撃 |
| S2 魔防ダウン（固定値・1.8 秒） | 10 | 13 | 16 | 19 | 22 | 25 | |
| S2 CD（秒） | 11.0 | 10.5 | 10.0 | 9.5 | 9.0 | 8.5 | |
| S2 マナ | 80 | 85 | 90 | 95 | 100 | 105 | |

| 項目 | Lv1 | Lv2 | Lv3 | 係数 |
|---|---|---|---|---|
| 奥義 中心 | 600 | 800 | 1000 | +160% 魔法攻撃 |
| 奥義 外側 | 300 | 400 | 500 | +100% 魔法攻撃 |
| サンダーバースト（超電導の対象） | 330 | 440 | 550 | +110% 魔法攻撃 |
| 奥義 CD（秒） | 32 | 29 | 26 | |
| 奥義 マナ | 130 | 160 | 190 | |

S2 のスタン 1 秒（基本の CC）、S1 の鎖の加速 +40%（最大 1 秒）、終わりの一撃のクールダウン 50% 短縮、超電導 5 秒は全 Lv で同じ。

**外した定数**: `EuriaTuning.s1Scale`（0.343）・`s2Scale`（0.644）・`ultScale`（0.28）、スロット倍率（`Balance.Skills.damageScale`）、`lerp`、
全体の CD 倍率（`Balance.Skills.cooldownScale`）、ミニオンへのスキルの全体の倍率（× 0.2。共通の土台で撤廃）。

**外した独自の制限**（MLBB に無い。バランスのためだけに足していたもの）:
- S1 の鎖のロックアウト（`chainLockout` 6 秒。同じ相手には 6 秒に 1 回しか鎖を結ばない）と、説明文の「同じ対象には{lockout}秒に1回まで」。
  外しても無限に回ることはない: 印の付いた相手に S1 を当てるたびに鎖が繋がり、終わりの一撃で CD が 50% 縮むので S1 は約 2.5 秒ごとに撃てるが、
  止めるのは MLBB と同じクールダウン（5 秒 − 2.5 秒）とマナ（40〜65 / 回）。sim の中で 0 秒で回る経路は無い（鎖は 1 秒、短縮は残りの CD を縮めるだけで撃ち直さない）。
  ただし短縮を鎖ごとに重ねると、2 体に鎖が繋がった詠唱で 50% × 2 = 100% になり CD が消え、S1 が鎖の長さ（1 秒）ごとに回り続ける。
  公式の文は「この追加ダメージが命中した場合、このスキルのクールダウンを 50% 短縮」で、重なるとは書いていないので、**1 回の詠唱につき 1 回**にした
  （ロックアウトの代わりではなく、文の読み。MLBB の実機で 2 体に鎖を繋げたときの CD を確かめたい）。
- S2 の広がりの「ミニオンにはダメージのみ」（スタン・魔防ダウンをミニオンに広げない）と、説明文の同じ但し書き。公式「周囲の敵をすべてスタン」に合わせ、ミニオンにも同じ効果。

**入れた割合**:
- スキル吸収率: S1 = 50%（`HitPayload.spellVampRatio` = 0.5。扇・鎖の継続ダメージ・終わりの一撃）。S2・奥義は公式に記載が無いので既定の 100%。説明文に「スキル吸収率50%。」を足した。
- ミニオンへの倍率: S1 の扇 = 200%（`HitPayload.minionMultiplier` = 2.0。以前は与ダメ補正 +100% を他の補正と足し算していた）。モンスターへの補正は無い。
- 攻撃エフェクト: 無い（エウドラの通常攻撃は汎用のまま）。

**CC・中断**: S2 のスタンは基本の CC（変更なし）。鎖の予約は従来どおり術者がスタン以上の CC を受けると取り消される（中断できる予約）。バインドで封じるスキルは無い（術者を動かすスキルが無い）。
