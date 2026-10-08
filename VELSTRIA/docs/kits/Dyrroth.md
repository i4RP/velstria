# Dyrroth (MLBB) - Kit Specification

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
- Cooldown reduction: each time he damages an enemy hero, Burst Strike and Spectre Step cooldowns are reduced by 1 s (Circle Strike hit gives the reduction).

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
- Cast 1: dashes in the designated direction; stops at max distance or on hitting one enemy hero or creep. Deals 230 (+60% Extra Physical Attack) physical damage and slightly knocks the target back.
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

## Velstria 実装対応表

H032 赤拳のディアス（デュエリスト・近接 150・Energy）= Velstria 版の Dyrroth。実装: `Packages/VelstriaCore/Sources/VelstriaCore/Systems/Kits/Kit_H032.swift`
（専用の部品は `KitDias.swift`）、テスト: `Tests/VelstriaCoreTests/Kits/Kit_H032Tests.swift`、演出: `App/Battle/SkillFX/Heroes/FX_H032.swift`。
スロットは上の調査の順に割り当てる（Skill1 = Burst Strike、Skill2 = Spectre Step、Ultimate = Abysm Strike、Passive = Wrath of the Abyss）。
マスターデータ上のスキル名（「Dias式・一閃」「星環シフト32」「煉獄連拳」「紅血の拳」）はそのまま。キットは汎用のデュエリストのパッシブ
（通常攻撃の攻撃速度スタック）と汎用の奥義（3 連撃 + 被ダメ軽減）を **置き換える**。
距離は Velstria 単位（≈ MLBB × 100）。調査に無い値（射程・突進の距離と速度・再使用の窓・溜めの長さなど）は下の「選んだ値」に書いた。
ダメージ・クールダウンは Velstria 全体の係数（`Balance.Skills`）に合わせた換算で、MLBB の数値そのままではない。

### 対応表（○ = 実装、△ = 簡略化、× = 見送り）

| 元の仕様 | 状態 | Velstria での実装・理由 |
|---|---|---|
| 近接・単体の通常攻撃、射程 1.7 | ○ | 射程 150（マスターの値）。ステータスはマスターデータ（HP 2900 +195/Lv、攻撃 130 +4.9、防御 25、魔防 17、Energy 500）で、Fandom の値ではない |
| パッシブ: レイジ（0〜100%）が毎秒 2〜5%（レベルで増える）たまる | ○ | `reals[0]`。毎秒 2% → 5% を Lv1 → 最大レベル（15）で線形補間し、**×2**（= 1 / `cooldownScale`）。Velstria はスキルの CD が MLBB の半分なので、「CD 1 回あたりにたまるレイジ」を MLBB と合わせた（Lv1 = 4%/s、Lv15 = 10%/s）。死亡で 0。開始時も 0。ダメージを与える・受けるでのレイジ増加は調査に無いので持たない |
| レイジ 50% で S1・S2 が「アビス強化」になる | ○ | 50 以上で発動した S1 / S2 の **2 回目（致命の一撃）** がアビス強化になり、レイジを **50 消費** する（消費量は調査に「不明」とあるので選んだ値）。ちょうど 50 でも強化。HUD のバッジはパッシブに「レイジ（スタック表示）」、S1・S2 に「強化可能（form）」 |
| 「2 本のレイジゲージ（スキルごとに 1 本）」という資料もある | △ | ゲージは 1 本（0〜100）で、50 ずつ S1 / S2 のどちらにでも使える。100 たまれば連続で両方を強化できる（2 本でも合計の挙動はほぼ同じ） |
| Circle Strike: 通常攻撃 2 回ごとに周囲の円攻撃（攻撃力 150〜180%、レベルで増える、物理） | ○ | `shapeBasicAttack` で 2 回に 1 回を円撃にする（`ints[0]` で数える。死亡でリセット）。主対象は通常攻撃の命中（会心・命中時効果・吸血はそのまま）で攻撃力 × 1.5（Lv1）→ 1.8（Lv15）、周囲の敵（半径 190 + 対象の半径。ヒーロー・ミニオン・モンスター。構造物は除く）にも同じダメージを別に与える（命中時効果・吸血・クールダウン短縮は主対象だけ）。専用の演出イベントは無い（通常攻撃の演出のまま） |
| 「レイジ 50% のときだけ円撃」という資料もある | × | 無条件に 2 回に 1 回を採用（調査の主な記述。レイジの閾値でアビス強化と円撃が同じ資源を取り合うのを避ける） |
| Circle Strike の回復: 最大 HP の 7〜10%（ミニオン・タワー相手は半分） | △ | 最大 HP の **4.2% → 6%**（MLBB の 0.6 倍。レベルで線形）。Velstria の 1v1 は MLBB より短い（TTK 2.5〜15 秒）ので、全量だと持続戦で偏るため（下の「バランス」）。敵ヒーローが円の中に 1 体でも居れば全量、ミニオン・モンスター・タワーだけなら半分。1 回の円撃で 1 度（対象ごとではない） |
| 敵ヒーローにダメージを与えるたびに S1・S2 のクールダウンが 1 秒縮む（円撃の命中を含む） | △ | 通常攻撃・円撃の敵ヒーローへの命中で **0.4 秒**、スキルの敵ヒーローへの命中で **0.1 秒（1 回の発動につき 1 度。S1 の連撃は 1 発目だけ）**。素直な換算は 0.5 秒（1 秒 × `cooldownScale`）だが、スキルの稼働率が上がりすぎて 1v1 の勝率が汎用の Duelist より上へ偏ったので抑えた。ミニオンへの命中・奥義のクールダウンには効かない。練習場の `noCooldowns` は尊重 |
| S1 Burst Strike: 指定方向へ衝撃を 3 回（アビス強化は 5 回）、ダメージ 240 → 520 + 60% | △ | 前方の扇（射程 300・半角 0.65 rad ≈ 37°）へ 0.1 / 0.24 / 0.38 秒に 3 発（`strikeSequence`、スタンされると残りは取り消し）。ダメージは汎用 S1 の **0.82 倍** を 3 発で配る（ランクは 4 段、元は 6 段）。向きは発動時に固定 |
| S1 同じ敵への連続ヒットは減衰、ミニオンには減衰 | ○ | 3 発の重み 1.0 / 0.7 / 0.5（合計で正規化）。ミニオンへは 60%（モンスターは通常どおり）。調査に減衰率が無いので選んだ値 |
| S1 鈍足 25% 1.5 秒 | ○ | `slow` 0.25 を 1.5 秒（毎発付け直す。同じタグなので重ならない） |
| S1 アビス強化: 射程が伸び、ダメージ 140%、鈍足 2 倍、5 回 | ○ | レイジ 50 を消費して、射程 400・5 発（0.1 秒 + 0.11 秒間隔、重み 1.0 / 0.8 / 0.65 / 0.5 / 0.4）・鈍足 50%。「140%」は **合計** に掛ける解釈（通常版の 1.4 倍 = 汎用 S1 の 1.15 倍。1 発ごとに 140% の解釈だと 5 発で約 2.4 倍になり予算を超える）。強化した発動は `SkillCastEvent.count = 5` |
| S1 クールダウン 6.0 → 4.0 秒、コスト無し | △ | 6.0 → 4.0 秒をランクで線形補間 × `cooldownScale`（0.5）。コストはマスター（Energy 40 × 0.6）のまま: `SkillSystem.validate` がマスターから決めるのでキットでは変えられない（MLBB は 0） |
| S2 Spectre Step 1 回目: 指定方向へ突進、最初に当たった敵ヒーロー・ミニオンで止まる | ○ | `dashStrike` として宣言（射程 400・速度 2400 ≈ 0.17 秒、経路の当たり半幅 110 + 対象の半径）。発動時に進路で最初に当たる敵（ヒーロー・ミニオン・モンスター。構造物・対象不可は除く）を探し、その縁（中心間 = 半径の和 + 5）まで進む（`Kit.firstBlocker`）。敵が居なければ最大距離まで。壁の手前では止まる |
| S2 1 回目のダメージ 230 → 355 + 60%、わずかに押し出す | △ | 合計（1 回目 + 2 回目）= 汎用 S2 の **0.82 倍**、1 回目 : 2 回目 = 0.4 : 0.6（調査の 230 : 345）。到着した tick に止まった先の敵へ 1 度だけ（離れすぎ・死亡・対象不可なら外れる）。押し出し = `HitEffect.pushAway` 130 を 0.18 秒（CC 無効の相手は動かない） |
| S2 2 回目（再使用）: 対象を捕捉して一撃、物理防御 −40% 4 秒。ミニオンは対象にできない | ○ | 同じ `castSkill`（`openRecast`、3 秒・1 回。CD・コストは使わない）。敵 **ヒーローだけ**（指定ユニット → 指定地点に近い敵 → 向き → HP + シールド最小）。対象の縁まで飛びかかり（速度 2600）、到着した tick にダメージ + `armorShred` 0.4（4 秒）。防御ダウンは自分の一撃には掛からない。射程 350。溜め中・ルート中・敵ヒーローが射程に居なければ拒否（窓は残る） |
| S2 2 回目の窓の長さ（不明） | △ | 選んだ値: 3 秒（S2 のクールダウンと同じ長さ）。CD は 1 回目の発動で消費され、2 回目では変わらない |
| S2 アビス強化の 2 回目: 射程が伸び、ダメージ 150%、追加の鈍足、防御ダウン −60% | ○ | レイジ 50 を消費して、射程 500・ダメージ 1.5 倍・`armorShred` 0.6・`slow` 0.5 を 1.2 秒。「追加の鈍足 90%」は未確認と調査にあるので、控えめに 50% を選んだ。突進を止められた（スタンなど）ときは消費したレイジを返す。強化した発動は `count = 2` |
| S2 クールダウン 6.0 秒、コスト無し | △ | 6.0 秒（全ランク）× 0.5 = 3.0 秒。コストはマスター（Energy 50 × 0.6）のまま |
| 奥義 Abysm Strike: 方向指定の溜め直線、650 / 950 / 1250 + 250% + 対象の失った HP の 20〜25% | △ | 溜め 0.5 秒（調査に「短い遅れ」とだけある）のあと、発動時に固定した向きの直線（長さ 420・半幅 120 + 対象の半径）の敵にダメージ。基礎ダメージ = 汎用の奥義（3 連撃）の合計 × 0.9 × ランク係数（0.9 / 1.0 / 1.1）= 汎用の 0.81 / 0.90 / 0.99 倍。**失った HP の割合を加算**: 敵ヒーローに限り、`(最大 HP − 現在 HP) × 22.5%`（資料が 20% と 25% で割れているので中間。シールドは数えない）を基礎ダメージに足してから防御で軽減する。`DamageScaling.missingHealth` は「ダメージ × (1 + 係数 × 失った割合)」で加算にならないので使わず、命中ごとに計算する（`KitDias.hitAreaEach`） |
| 奥義のダメージ予算 | △ | 「単体総ダメージは汎用の 0.8〜1.3 倍」は基礎部分にだけ適用（0.81〜0.99 倍）。失った HP の加算は **意図的に予算を超える**（最大 HP の 4,000〜5,000 の相手が HP 5% のとき +900 以上）: 調査の「実行型」の特徴。テスト（`testAbysmDamageGrowsWithTheTargetsLostHealth`）が満タンで予算内・低 HP で超えることを確認 |
| 奥義 鈍足 55% 0.8 秒 | ○ | 命中した敵（ミニオン・モンスターを含む）に `slow` 0.55 を 0.8 秒 |
| 奥義は制圧（suppress）以外では中断されない（スタン・打ち上げでは止まらない） | ○ | 溜めのタイマーは `interruptible: false`（ハード CC で取り消されない）。`update` が suppress を見たら溜め・予約を取り消す。溜めの間は自分に `root` + 表示用の `channeling`（その場から動けず、攻撃・ほかのスキル・再使用を始められない）。スタン・打ち上げを受けても一撃は出る。死亡で全部リセット |
| 奥義 Flicker で向き・射程を変えられる | × | 向きは発動時に固定。Flicker（バトルスペル）との連動は無い（溜めの間は動けないので、Flicker で位置が変わってもその位置から固定の向きに撃つ） |
| 奥義 クールダウン 36 / 32 / 28 秒、コスト無し | △ | 36 → 28 秒を 3 ランクで線形補間 × 0.5 = 18 → 14 秒。コストはマスター（Energy 85 × 0.6）のまま |
| 武器の「ゲーム的な体感」: 連続の殴り合いと CD リセットのループ | ○ | 通常攻撃・円撃 → CD 短縮 → S1 / S2 → …の回転。アビス強化は S1（5 連）→ S2 の 2 回目（防御ダウン −60%）→ 奥義の順に火力が高まる |
| 弱点: カイティング、奥義の前の CC | ○ | 溜め 0.5 秒の間は動けず（root）、制圧以外は止まらないが、溜めに入る前の CC・距離取りで不発にできる。S1 の連撃は途中のスタンで取り消される |

### 選んだ値（調査に無い・換算した値）

| 項目 | 値 | 理由 |
|---|---|---|
| レイジの時間倍率 | ×2（= 1 / `cooldownScale`） | CD が半分なので、1 回の CD あたりにたまる量を MLBB に合わせる |
| アビス強化の消費 | 50 | 調査に「不明」。閾値と同じ値にした（100 で 2 回ぶん） |
| 円撃の半径 | 190 | 通常攻撃の射程 150 より少し広い（MLBB の 1.7 → 2.0 の比） |
| S1 の射程・半角・間隔 | 300 / 400（アビス）・0.65 rad・0.14 秒 / 0.11 秒 | 近接スキルの標準。調査に無い |
| S1 の連続ヒットの重み | 1.0 / 0.7 / 0.5（アビス: 1.0 / 0.8 / 0.65 / 0.5 / 0.4） | 「減衰する」とだけある。5 連のほうが減衰は緩く |
| S2 の突進 | 距離 400・速度 2400・幅 110・押し出し 130 / 0.18 秒 | 調査に「不明」。汎用の近接の突進（range 300 + 100）に合わせた |
| S2 の致命の一撃 | 射程 350 / 500（アビス）・速度 2600・窓 3 秒 | 調査に「不明」 |
| 防御ダウンの割合 | 40% / 60%（アビス）・4 秒 | 調査どおり（割合の `armorShred`） |
| 奥義の溜め・長さ・幅 | 0.5 秒・420・半幅 120 | 調査に「短い遅れ」「不明」。ULT の標準射程 420 |
| 失った HP の割合 | 22.5% | 20%（Fandom）と 25%（mlbb.tools / esports.gg）の中間 |
| ダメージ倍率 | S1 0.82 / S2 0.82 / 奥義 0.9 × (0.9 / 1.0 / 1.1) | 下の「バランス」。S1 のアビス強化は 1.4 倍 = 1.15 倍、S2 のアビス強化の 2 回目は 1.5 倍 |
| 説明文の数値 | トークン `{x0}`〜`{x3}` と、本文中の定数（`Tune` を文字列に展開） | 数値を sim とずらさない |

### バランス（1v1 の総当たり、`testRoundRobinWinRatesStayNearTheGenericDuelists`、Release）

全 34 ヒーローとの 1v1（`SkillBalanceTests.duel`、Lv 1 / 6 / 12、自動習得のランク、引き分けは半分）の勝率。値は離散的（1 戦 ≈ 3pt）なので ±6pt 程度はノイズ。

| ヒーロー | Lv1 | Lv6 | Lv12 |
|---|---|---|---|
| H032 ディアス | 94% | 82% | 91% |
| H002（汎用 Duelist） | 36% | 91% | 82% |
| H008（汎用 Duelist） | 94% | 85% | 91% |
| H014（汎用 Duelist） | 70% | 97% | 85% |
| H020（汎用 Duelist） | 79% | 88% | 67% |
| H027 ジャルド（キット） | 82% | 82% | 88% |

この総当たりは近接の Duelist 全般に高く出る（blue 側・近接の突っ込みが有利）。ディアスは汎用の Duelist の幅（36〜97%）の中で、H008 とほぼ同じ位置。
TTK は H001〜H006 相手で 3.7〜10.0 秒（Lv1 7〜10 秒、Lv6 3.8〜6.5 秒、Lv12 3.7〜7.2 秒）。
調整の経緯: 最初の版（クールダウン短縮 0.5 秒 / スキル命中でも 0.5 秒、S1・S2 の倍率 0.90、奥義 0.95、円撃の回復 7〜10%）は 100% / 100% / 100%（TTK 2.1 秒まで）で支配的だった。
効いたのはクールダウン短縮（スキルの稼働率）で、円撃の回復と威力の影響は小さかった。短縮を通常攻撃 0.4 秒・スキル 0.1 秒、倍率を 0.82 / 0.82 / 0.9、回復を 0.6 倍にして今の位置。

### 既知の差・リスク

- スキルのコスト（Energy）は MLBB の「無し」と違う。`SkillSystem.validate` がマスターデータから決めるのでキットでは変えられない。
- S1 のアビス強化の射程（400）と S2 の 2 回目のアビス強化の射程（500）は、HUD の照準情報（`targeting`）には出ない（状態＝レイジが要るため）。
  実際の発動（`resolveAim` / `cast`）が見る。照準円は通常版の大きさ（300 / 350）。
- S1 の連撃は発動時の向きに固定するが、中心は **撃った瞬間の自分の位置**（S2 で動けば追従する）。
- 円撃に専用の演出イベントは無い（`attackReleased` + ダメージのイベントのみ）。S1 / S2 のアビス強化と S2 の 2 回目は `SkillCastEvent.count / stage` で
  見分けられるが、現在の `SkillFXDirector` はレシピを共通で再生する。
- 奥義の失った HP の加算は敵ヒーローのみ（ミニオン・ジャングルの敵には付かない: ジャングルの周回が極端に速くなるのを避ける）。
- 奥義の溜め中に Flicker 等で位置が変わっても、固定の向きのまま新しい位置から撃つ（Flicker で向き・射程を変える仕様は未対応）。
- ボットの奥義は汎用の判断（倒せるか、2 体以上を巻き込めるか）で撃つので、1v1 の長い試合では撃つ回数が少ない。
