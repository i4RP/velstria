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
| S1 印の敵に当たる → 雷の鎖（最大 1 秒）: 移動速度 +40%、継続ダメージ 10〜20 + 4%、終わりに 275〜500 + 100% | ○ | `Kit.schedule`（中断可）で継続ダメージ 4 回（0.2 秒おき・1 撃の 4%）と 1 秒後の終わりの一撃（初撃と同じ）。術者に `speedBoost` 0.40（1 秒）。複数の印済みの敵には鎖がそれぞれ張られる。**同じ相手へは前の鎖から 3 秒（`chainLockout`）経つまで結び直さない**（相手ごとのロックアウト。`KitState.ids[0...3]` + `timers[1...4]`、4 体まで）。印は消費しないので、制限が無いと S1 が当たるたびに鎖が繋がり、終わりの一撃のクールダウン短縮で回り続ける。総当たり勝率（アルカニスト中央値との差）は制限なし Lv1 +40 / Lv6 +15 / Lv12 +41 pt → 3 秒で Lv1 +4 / Lv6 +12 / Lv12 +28 pt（6 秒でもほぼ同じ）。印を消費する案は、印の付与と追加効果の順序をスキルごとに変える必要があり、制限だけで足りたので採らなかった |
| S1 終わりの一撃が当たるとクールダウン短縮（50% / 1.5 秒で資料が割れている） | △ | 固定 1.5 秒（`HitEffect.refundCooldown`。全体の CD が半分だったころは × 0.5 = 0.75 秒）。当たらなければ（対象が倒れた・離れた・見えない・対象不可・術者がスタン）縮まない。練習場の `noCooldowns` を尊重 |
| 鎖の長さ・対象が離れたら切れるか（不明） | △ | 術者と対象の中心間 800 を超える、対象が倒れる・視界外・対象不可になる、術者がハード CC を受けると切れる（加速も終わる） |
| S1 ダメージ 275〜500 + 100% / 継続 10〜20 / 追加 275〜500 | △ | 鎖が結ばれたときの合計（2 撃 + 継続 4 回）= 汎用 S1 の約 1.19 倍（予算 0.8〜1.3 内）。印の無い単発は 0.55 倍。ランクは 4 段（元は 6 段） |
| S1 クールダウン 7.0 → 5.0 秒、マナ 50 → 70 | △ | MLBB と同じ 7 → 5 秒（ランクで線形補間。以前は × 0.5 = 3.5 → 2.5 秒）。コストはマスターのまま（62）: `SkillSystem.validate` がマスターから決めるのでキットでは変えられない |
| S2 Ball Lightning: 対象指定、魔防ダウン 10〜25（1.8 秒）、300〜400 + 50%、スタン 1 秒 | ○ | 対象指定（`.lineSkillshot` + `aim: .unit` + `requiresTarget`、射程 650）。追尾する雷球（速度 1800）。ダメージ後に `stun` 1.0 秒と `magicShred`（固定値 10 → 25 を 4 ランクで線形・1.8 秒）。射程内に敵が居なければコスト・CD を消費せず失敗 |
| S2 印済みなら周囲の敵にも魔防ダウン・範囲ダメージ・スタン（Fandom: 対象中心の範囲 / 公式文: 跳ねる） | △ | Fandom の「対象中心の範囲」を採用。半径 260 の敵（ミニオン含む。構造物除く）に同じダメージ。スタン 1 秒・魔防ダウンは**ヒーローとモンスターだけ**（ミニオンにはダメージのみ）。主対象は 1 度だけ。広がった先の非ミニオンにも印が付く |
| S2 魔防ダウンがダメージに掛かるか | △ | ダメージの後に付くので、その一撃には掛からない（以降のスキル・通常攻撃に効く） |
| S2 ダメージ・クールダウン、マナ 70 → 95 | △ | 元のスキル値（汎用 S2 ÷ `empowerRatio`）の 0.81 倍（0.85 から調整）（汎用の遠隔 S2 は「ブリンク + 強化攻撃」で半分になっている。転移は持たない）。CD は MLBB と同じ 11 → 8.5 秒（線形補間）。コストはマスターのまま（74） |
| 奥義 Thunder's Wrath: 地点指定、中心 600〜1000 + 160%、外側 300〜500 + 100% | ○ | `groundAoE`（射程 770）。0.8 秒の予告（`ZoneSystem` の delay）後、中心（半径 150）の敵に汎用の奥義の 0.82 倍（0.85 から調整）、外側（半径 300）の敵に中心の 0.5 倍（`DamageScaling.distance` を段差にして 1 回のヒットで切り替え）。CC は無い（調査どおり） |
| 奥義 印の敵に当たるたび、その敵を中心に少し遅れて Thunderburst（300〜550 + 110%）。複数なら重なる | ○ | 印済みの敵 1 体につき、敵に追従する炸裂のゾーン（`followsTargetID`、半径 190・0.5 秒後）を 1 つ。ダメージは中心の 0.40 倍（0.47 から調整）で、範囲内の全ての敵に当たる（複数の炸裂は重なって各自に当たる）。炸裂の前に対象が倒れれば不発。炸裂のゾーンの演出 ID はパッシブ（大雷とは別の演出） |
| 奥義の遅れ・半径（不明） | △ | 予告 0.8 秒・中心の半径 150・外側の半径 300・炸裂の遅れ 0.5 秒・炸裂の半径 190（下の「選んだ値」） |
| 奥義 CD 32/29/26 秒、マナ 130 → 190 | △ | MLBB と同じ 32 / 29 / 26 秒。コストはマスター（118） |
| 奥義のダメージ（予算） | △ | 中心だけで汎用の 0.82 倍、印済みの単体（中心 + 炸裂）で約 1.15 倍 |
| スペルヴァンプ 50% | × | 汎用のスペルヴァンプ（装備）のままで、スキル専用の比率は無い |
| 再使用（recast） | – | Eudora には無いので使わない（窓は開かない） |

### 選んだ値（調査に無い・換算した値）

| 項目 | 値 | 理由 |
|---|---|---|
| S1 扇 | 射程 650・半角 30° | 遠隔スキルの標準射程。調査に角度は無い |
| 鎖が切れる距離 | 術者と対象の中心間 800 | S1 の射程に余裕を足した値。加速で追えば保てる |
| 継続ダメージ | 0.2 秒おき 4 回・1 撃の 4% | 調査の 10〜20 + 4% 対 275〜500 + 100% の比 |
| 雷球の速度 | 1800 | 対象指定の追尾弾。約 0.3 秒で届く |
| S2 広がりの半径 | 260 | 調査に無い。ヒーロー数体を巻き込める広さ |
| 奥義 予告・半径 | 0.8 秒・中心 150 / 外側 300 | 汎用のアルカニストの奥義（1.0 秒・半径 279）より少し短く速い |
| 炸裂 | 0.5 秒後・半径 190・中心の 0.40 倍 | 調査の 300〜550 対 600〜1000 の比（約 0.5）より低く、勝率の調整で下げた |
| ダメージ倍率 | S1 0.55 ×2 / S2 0.81 / 奥義 0.82（炸裂 +0.40） | 上の表。1v1 の勝率で決めた |
| 鎖のロックアウト | 同じ相手に 3 秒 | 上の S1 の行。勝率の差が 6 秒でもほぼ同じだったので、当時の S1 の CD（約 3.5 秒）に近い短い値にした。CD が MLBB の秒数（7 → 5 秒、終わりの一撃で −1.5 秒）になった今は、CD 短縮を積まないかぎり効かない |
| 説明文の数値 | パッシブ x0 = 印の秒 / S1 x0 = 鎖の秒、x1 = 加速 %、x2 = 短縮秒、x3 = 継続ダメージ、`{lockout}` = 同じ相手への鎖の間隔 / S2 x0 = 魔防ダウン、x1 = その秒、x2 = 広がりの半径、x3 = スタン秒 / 奥義 x0 = 外側ダメージ、x1 = 炸裂ダメージ、x2 = 予告の秒、x3 = 中心の半径 | `KitText` のトークンに sim の数値を入れる |

### 検証した 1v1 の目安

- `Kit_H026Tests.testDuelTimeToKillStaysInBandAgainstTheRoleRepresentatives`: H001〜H006 相手の TTK は Lv 1 / 6 / 12 とも 2.5〜15 秒（実測 4.3〜10.7 秒）。
- 計測ハーネス（`BalanceHarness` / `KitBalanceTests`、Release）の勝率（アルカニスト中央値との差、pt）: 調整前 Lv1 +40 / Lv6 +20 / Lv12 +41 → 調整後は下の「バランス調整」の表。
- `Kit_H026Tests.testRoundRobinWinRateAgainstTheWholeRosterIsNotExtreme`: 全 33 体との総当たり（`SkillBalanceTests.duel`）の勝率は Lv6 48.5%・Lv12 60.6%。
  この総当たりは「奥義 → S1 → S2」の固定順で撃つため、S1 で印を付けてから S2・奥義を使うエウリア本来の連携（ボットは `botCast` で守る）は含まない。

### 既知の差・リスク

- スキルのマナ（コスト）の相対関係（S1 50 → 70、S2 70 → 95、奥義 130 → 190）は再現できない（マスターデータ固定: 62 / 74 / 118）。
- 雷の鎖には専用のイベントが無い。App 側の演出は、継続ダメージの 1 回ごとと終わりの一撃のダメージ（`hit`、`hitPerHit`）に、術者 → 被弾者の線上へ走る短い稲妻の筋を出して鎖を表す（`.along` アンカー。扇の初撃にも同じ筋が出る。画質 1 以上）。鎖の残りはバッジの残り秒と移動速度でも分かる。
- S2 の広がりは Fandom の「範囲」解釈。公式文の「跳ねる」（バウンス）は再現していない。
- 印は消費しないので、5 秒の間は S2 の広がり・奥義の炸裂は何度でも起きる（調査に消費の記載が無い）。S1 の鎖だけは同じ相手に 3 秒に 1 回まで。
- `SkillFXDirector` は stage / count / duration を読まない。炸裂の演出はパッシブの telegraph / impact で表した。

### バランス調整とボット（2 回目の見直し）

- 総当たり勝率（アルカニスト中央値との差）が Lv1 +40 / Lv6 +20 / Lv12 +41 pt だったので、S1 の鎖のロックアウト（同じ相手に 3 秒）・S2 0.85 → 0.81・奥義 0.85 → 0.82・炸裂 0.47 → 0.40 で下げた。
  S2 の広がりのスタン・魔防ダウンはミニオンに広げない（ダメージは広げる）。
- ボット（`botCast`）: 印の無い敵には、S1 が**実際に撃てる**（CD 明け・マナあり・行動可能・敵が扇の射程 650 + 半径の内）あいだだけ、アルティメットを見送って S1 → 印 → 重い技の順にする。
  S1 が撃てないとき（CD・マナ不足・沈黙・射程の外）は待たない。S2 は近くに別のヒーローが居るとき（印が広がる）だけ印を待ち、居なければ先に撃つ（S2 自身が印を付ける）。
- 説明文は master の名前（分岐雷 / 雷球 / 九天雷鳴）と UI の用語（スキル1 / スキル2 / アルティメット）に統一した。
- Release の最終計測（アルカニスト中央値 25.0 / 28.8 / 27.0 %）: Lv1 19.2 (-5.8) / Lv6 39.6 (+10.9) / Lv12 46.5 (+19.4) pt（見直し前 +40.2 / +20.3 / +41.4）。開幕 3 秒の瞬間火力の比は Lv1 0.31 / Lv6 0.79 / Lv12 0.89（見直し前 0.31 / 0.84 / 0.95。Lv1 はスキル1 しか覚えていないため低い）。
