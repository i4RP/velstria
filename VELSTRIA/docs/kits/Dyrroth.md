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

## 公式（現行シーズン）の数値

2026-10 に MediaWiki API で取り直した（Liquipedia の `Dyrroth` = 現行の V2。Fandom の `Dyrroth` は古い版の表（スキル1 の CD 5 秒・基礎 200〜450、スキル2 の CD 8 → 4 秒、
円撃 160% + 回復 50 + 与ダメの 40%）のままなので、現行の値は Liquipedia を正とした。Liquipedia はティグラルで日本語クライアントの値と一致した）。
Liquipedia に数字の無い項目（スキル1 の同じ敵への減衰率・強化版の 5 連、致命の一撃の追加の鈍足の秒数）だけ Fandom の値を使った。

| スロット | 公式名 | タグ | 内容 |
|---|---|---|---|
| パッシブ | Wrath of the Abyss | バフ・回復 | レイジ 50% でスキル1・2 を強化。通常攻撃 2 回ごとに円撃: 円の中の敵に物理攻撃の 150% 〜 180%（レベルで増える）の物理ダメージ（強化ダメージはタワーには乗らない）、最大 HP の 7% 〜 10% 回復（レベルで増える。ミニオン・タワー相手は半分）。攻撃エフェクトは発動しない。敵にダメージを与えるたびにスキル1・2 の CD −1 秒。レイジは毎秒 2% 〜 5%（レベルで増える） |
| スキル1 | Burst Strike | 範囲技・減速 | CD 6.0 / 5.6 / 5.2 / 4.8 / 4.4 / 4.0、コストなし、基礎ダメージ 240 / 296 / 352 / 408 / 464 / 520（+60% 物理攻撃）。指定方向へ衝撃を放ち、各衝撃でダメージ + 25% 減速 1.5 秒。同じ敵へのダメージは減衰し、ミニオンには 75%。強化: 射程が伸び、元のダメージの 140%、減速 2 倍。減衰率（Fandom）: 通常 {100%, 30%, 30%}、強化 {140%, 42%, 42%, 42%, 42%}（= 通常 3 回・強化 5 回） |
| スキル2 | Spectre Step | 移動・ダメージ | CD 6.0（全 Lv）、コストなし。突進し、最大距離か敵ヒーロー・クリープに当たって止まり、230 / 255 / 280 / 305 / 330 / 355（+60% 追加物理攻撃）+ 軽いノックバック。再使用で対象をロックオンして致命の一撃 345 / 390 / 435 / 480 / 525 / 570（+120% 追加物理攻撃）、物理防御 −40%（4 秒）。強化: 致命の一撃の射程が伸び、ダメージ 150%、追加で 90% の減速（Fandom: 1 秒）、物理防御 −60%（4 秒） |
| アルティメット | Abysm Strike | バースト・減速 | CD 36 / 32 / 28、コストなし、基礎ダメージ 650 / 950 / 1250（+250% 追加物理攻撃）+ 対象の失った HP の 20%、55% 減速 0.8 秒。短い遅れのあと指定方向へ（制圧でのみ中断）。ヒーロー以外へのダメージの上限 1500 / 2000 / 2500 |

### 公式が置き換えた調査の値

| 項目 | 以前の調査・実装 | 公式 |
|---|---|---|
| コスト | 「なし」だがキットで変えられずマスターの Energy 40 / 50 / 85 × 0.6 | **なし**（`HeroKit.cost` で 0） |
| スキル1 の減衰 | 重み 1.0 / 0.7 / 0.5（強化 1.0 / 0.8 / 0.65 / 0.5 / 0.4）を合計で正規化。強化の 140% は合計に掛ける | 1 発目 100%・以降 30%（強化は 1 発目 140%・以降 42%）。140% は **1 発ごと** |
| スキル1 のミニオン | 60% | 75% |
| スキル2 の強化の追加の鈍足 | 「90%」は未確認として 50% 1.2 秒 | 90%（Liquipedia・Fandom とも）、1 秒（Fandom） |
| スキル2・アルティメットの攻撃力係数 | 汎用の式（物理攻撃の合計で伸びる） | **追加物理攻撃**（装備などで増えた分）だけで伸びる |
| アルティメットの失った HP | 20% と 25% で割れている → 22.5% | **20%**（Liquipedia・Fandom とも） |
| アルティメットのヒーロー以外 | 失った HP の加算はヒーローだけ | 加算はすべての敵、ヒーロー以外への合計に上限 1500 / 2000 / 2500 |
| 円撃のタワー | 倍率が掛かる | 強化ダメージはタワーに乗らない（通常攻撃のダメージ） |
| 円撃の回復・CD 短縮 | 3〜4%（MLBB の 0.4 倍）・0.6 / 0.1 秒 | 7〜10%・1 秒（Velstria の換算は下の対応表） |

ランクの対応: スキル1・2 の 4 ランク = Lv1 → Lv6 の線形補間（ランク r → Lv `1 + (r − 1) × 5 / 3`）、アルティメットの 3 ランクは公式の Lv そのまま。

## Velstria 実装対応表

H032 赤拳のディアス（デュエリスト・近接 150・Energy）= Velstria 版の Dyrroth。実装: `Packages/VelstriaCore/Sources/VelstriaCore/Systems/Kits/Kit_H032.swift`
（専用の部品は `KitDias.swift`）、テスト: `Tests/VelstriaCoreTests/Kits/Kit_H032Tests.swift`、演出: `App/Battle/SkillFX/Heroes/FX_H032.swift`。
スロットは上の調査の順に割り当てる（Skill1 = Burst Strike、Skill2 = Spectre Step、Ultimate = Abysm Strike、Passive = Wrath of the Abyss）。
マスターデータ上の最終名は パッシブ「紅血の拳」/ スキル1「赤拳連斬」/ スキル2「紅蓮の踏込」/ アルティメット「奈落の一撃」（`tools/rename_kit_skills.mjs`）。説明文は UI の用語（スキル1・スキル2・アルティメット）で書く。キットは汎用のデュエリストのパッシブ
（通常攻撃の攻撃速度スタック）と汎用の奥義（3 連撃 + 被ダメ軽減）を **置き換える**。
距離は Velstria 単位（≈ MLBB × 100）。調査に無い値（射程・突進の距離と速度・再使用の窓・溜めの長さなど）は下の「選んだ値」に書いた。
ダメージ・クールダウンは上の「公式（現行シーズン）の数値」の表をランクで線形補間して使う（H029 ボルグと同じ方法）。ダメージは Velstria の通常の式（`(基礎 + 係数 × 攻撃力 × 0.6) × スロット倍率`）に換算（`Tune.burstScale / spectreScale / ultScale`）するので、絶対値は MLBB と同じではない。**追加物理攻撃**の係数（スキル2・奥義）は `物理攻撃 − Unit.baseStats.attack`（装備・バフで増えた分）に掛け、発動時に足す（`numbers` の値・説明文の基礎は装備なしの値）。コストは公式どおり無し（`HeroKit.cost` = 0）。クールダウンは公式の秒数そのまま（全体倍率 `cooldownScale` は 1.0）。

### 対応表（○ = 実装、△ = 簡略化、× = 見送り）

| 元の仕様 | 状態 | Velstria での実装・理由 |
|---|---|---|
| 近接・単体の通常攻撃、射程 1.7 | ○ | 射程 150（マスターの値）。ステータスはマスターデータ（HP 2900 +195/Lv、攻撃 130 +4.9、防御 25、魔防 17、Energy 500）で、Fandom の値ではない |
| パッシブ: レイジ（0〜100%）が毎秒 2〜5%（レベルで増える）たまる | ○ | `reals[0]`。毎秒 2% → 5% を Lv1 → 最大レベル（15）で線形補間（MLBB と同じ。全体の CD が半分だったころは「CD 1 回あたりにたまるレイジ」を合わせるため ×2 していた）。死亡で 0。開始時も 0。ダメージを与える・受けるでのレイジ増加は調査に無いので持たない |
| レイジ 50% で S1・S2 が「アビス強化」になる | ○ | 50 以上で発動した S1 / S2 の **2 回目（致命の一撃）** がアビス強化になり、レイジを **50 消費** する（消費量は調査に「不明」とあるので選んだ値）。ちょうど 50 でも強化。HUD のバッジはパッシブに **50 ごとの段（`Int(レイジ / 50)`、0〜2、最大 2）**、スキル1・スキル2 に「強化可能（form）」。パッシブのバッジを毎秒増えるレイジそのもの（0〜100）にすると、バッジが増えるたびにパッシブの演出を出す Director（`observeKitPassives`）が毎秒鳴り続けるので、閾値（50・100）を通ったときだけ増える形にした。演出が出るのはレイジが 50・100 に届いた瞬間だけ |
| 「2 本のレイジゲージ（スキルごとに 1 本）」という資料もある | △ | ゲージは 1 本（0〜100）で、50 ずつ S1 / S2 のどちらにでも使える。100 たまれば連続で両方を強化できる（2 本でも合計の挙動はほぼ同じ） |
| Circle Strike: 通常攻撃 2 回ごとに周囲の円攻撃（攻撃力 150〜180%、レベルで増える、物理） | ○ | `shapeBasicAttack` で 2 回に 1 回を円撃にする（`ints[0]` で数える。死亡でリセット）。主対象は通常攻撃の命中（会心・命中時効果・吸血はそのまま）で攻撃力 × 1.5（Lv1）→ 1.8（Lv15）、周囲の敵（半径 190 + 対象の半径。ヒーロー・ミニオン・モンスター。構造物は除く）にも同じダメージを別に与える（命中時効果・吸血・クールダウン短縮は主対象だけ）。専用の演出イベントは無い（通常攻撃の演出のまま） |
| 「レイジ 50% のときだけ円撃」という資料もある | × | 無条件に 2 回に 1 回を採用（調査の主な記述。レイジの閾値でアビス強化と円撃が同じ資源を取り合うのを避ける） |
| Circle Strike の回復: 最大 HP の 7〜10%（ミニオン・タワー相手は半分） | △ | 最大 HP の **1.4% → 2%**（公式の 0.2 倍。伸び方は公式と同じでレベルで線形。以前は 3% → 4%、その前は 4.2〜6%）。Velstria の 1v1 は MLBB より短い（TTK 2.5〜22 秒）ので、全量だと持続戦で偏るため（下の「バランス」）。敵ヒーローが円の中に 1 体でも居れば全量、ミニオン・モンスター・タワーだけなら半分。1 回の円撃で 1 度（対象ごとではない） |
| 敵ヒーローにダメージを与えるたびに S1・S2 のクールダウンが 1 秒縮む（円撃の命中を含む） | △ | 通常攻撃・円撃の敵ヒーローへの命中で **0.55 秒**、スキルの敵ヒーローへの命中で **0.05 秒（1 回の発動につき 1 度。S1 の連撃は 1 発目だけ）**（公式の 1 秒の 55% / 5%。以前は 0.6 / 0.1 秒）。MLBB の 1 秒のままだとスキルの稼働率が上がりすぎて 1v1 の勝率が汎用の Duelist より上へ偏る。全体の CD が半分だったころは 0.3 / 0.05 秒（素直な換算 0.5 秒の 60% / 10%。最初の版は 0.5 / 0.5、その次が 0.4 / 0.1）で、CD に対する割合は同じ。説明文（パッシブ）に 0.55 秒（通常攻撃・円撃）と 0.05 秒（スキル）の両方を書く。ミニオンへの命中・奥義のクールダウンには効かない。練習場の `noCooldowns` は尊重 |
| S1 Burst Strike（赤拳連斬）: 指定方向へ衝撃を 3 回（アビス強化は 5 回）、ダメージ 240 → 520 + 60% | ○ | 前方の扇（射程 300・半角 0.65 rad ≈ 37°）へ 0.1 / 0.24 / 0.38 秒に 3 発（スタンされると残りは取り消し）。1 発目 = 公式の表（240 → 520 をランク 4 段へ補間、+60% 物理攻撃）× スロット倍率 4.0 × 換算 `burstScale`。向きは発動時に固定 |
| S1 同じ敵への連続ヒットは減衰、ミニオンには 75% | ○ | 2 発目以降は 1 発目の 30%（Fandom の減衰率 {100%, 30%, 30%}。発の順番で掛けるので、途中から扇に入った敵も 30%）。ミニオンへは 75%（モンスターは通常どおり）。以前は重み 1.0 / 0.7 / 0.5 を合計で正規化、ミニオン 60% |
| S1 鈍足 25% 1.5 秒 | ○ | `slow` 0.25 を 1.5 秒（毎発付け直す。同じタグなので重ならない） |
| S1 アビス強化: 射程が伸び、ダメージ 140%、鈍足 2 倍、5 回 | ○ | レイジ 50 を消費して、射程 400・5 発（0.1 秒 + 0.11 秒間隔）・鈍足 50%。「140%」は **1 発ごと**（Fandom の減衰率 {140%, 42%, 42%, 42%, 42%}）。単体の合計は 1 発目の 3.08 倍 = 通常版（1.6 倍）の 1.925 倍。以前は合計に掛ける解釈（1.4 倍）。強化した発動は `SkillCastEvent.count = 5` |
| S1 クールダウン 6.0 → 4.0 秒、コスト無し | ○ | 公式と同じ 6.0 → 4.0 秒（ランクで線形補間）。コストは 0（`HeroKit.cost`。以前はマスターの Energy 40 × 0.6） |
| S2 Spectre Step（紅蓮の踏込）1 回目: 指定方向へ突進、最初に当たった敵ヒーロー・ミニオンで止まる | ○ | `dashStrike` として宣言（射程 400・速度 2400 ≈ 0.17 秒、経路の当たり半幅 110 + 対象の半径）。発動時に進路で最初に当たる敵（ヒーロー・ミニオン・モンスター。構造物・対象不可は除く）を探し、その縁（中心間 = 半径の和 + 5）まで進む（`Kit.firstBlocker`）。敵が居なければ最大距離まで。壁の手前では止まる |
| S2 1 回目のダメージ 230 → 355 + 60% 追加物理攻撃、わずかに押し出す | ○ | 公式の表（230 → 355、2 回目 345 → 570）× スロット倍率 3.0 × 換算 `spectreScale`、+ 追加物理攻撃 × 60% / 120%（× 0.6 × 倍率 × 換算）。以前は合計 = 汎用 S2 の 0.82 倍を 0.4 : 0.6 で分けていた。到着した tick に止まった先の敵へ 1 度だけ（離れすぎ・死亡・対象不可なら外れる）。押し出し = `HitEffect.pushAway` 130 を 0.18 秒（CC 無効の相手は動かない） |
| S2 2 回目（再使用）: 対象を捕捉して一撃、物理防御 −40% 4 秒。ミニオンは対象にできない | ○ | 同じ `castSkill`（`openRecast`、3 秒・1 回。CD・コストは使わない）。敵 **ヒーローだけ**（指定ユニット → 指定地点に近い敵 → 向き → HP + シールド最小）。対象の縁まで飛びかかり（速度 2600）、到着した tick にダメージ + `armorShred` 0.4（4 秒）。防御ダウンは自分の一撃には掛からない。射程 350。溜め中・ルート中・敵ヒーローが射程に居なければ拒否（窓は残る） |
| S2 2 回目の窓の長さ（不明） | △ | 選んだ値: 3 秒（全体の CD が半分だったころの S2 のクールダウンと同じ長さ）。CD は 1 回目の発動で消費され、2 回目では変わらない |
| S2 アビス強化の 2 回目: 射程が伸び、ダメージ 150%、追加の鈍足 90%、防御ダウン −60% | ○ | レイジ 50 を消費して、射程 500・ダメージ 1.5 倍・`armorShred` 0.6・`slow` 0.9 を 1 秒（公式の 90%、秒数は Fandom。以前は未確認として 50% 1.2 秒）。突進を止められた（スタンなど）ときは消費したレイジを返す。強化した発動は `count = 2` |
| S2 クールダウン 6.0 秒、コスト無し | ○ | 公式と同じ 6.0 秒（全ランク）。コストは 0 |
| 奥義 Abysm Strike（奈落の一撃）: 方向指定の溜め直線、650 / 950 / 1250 + 250% 追加物理攻撃 + 対象の失った HP の 20% | ○ | 溜め 0.5 秒（調査に「短い遅れ」とだけある）のあと、発動時に固定した向きの直線（**射程 650・半幅 140**。命中は線分から「半幅 + 対象の半径」までなので、線分の長さは 650 − 140 = 510 にして、丸い端を含めてちょうど射程 650 に収まる。HUD の帯・FX の線の長さ・ボットの射程と同じ値）の敵にダメージ。基礎ダメージ = 公式の 650 / 950 / 1250 × スロット倍率 2.6 × 換算 `ultScale` + 追加物理攻撃 × 250%（× 0.6 × 倍率 × 換算）。**失った HP の割合を加算**: `(最大 HP − 現在 HP) × 20%`（公式。シールドは数えない。以前は資料の割れの中間 22.5%、敵ヒーローだけ）を基礎ダメージに足してから防御で軽減する。ヒーロー以外（ミニオン・モンスター）にも加算し、合計は公式の上限 1500 / 2000 / 2500 を基礎と同じに換算した値まで（`Kit_H032.ultHitDamage`）。`DamageScaling.missingHealth` は「ダメージ × (1 + 係数 × 失った割合)」で加算にならないので使わず、命中ごとに計算する（`KitDias.hitAreaEach`） |
| 奥義のダメージ予算 | △ | 基礎部分は汎用の 0.57〜0.80 倍（換算 `ultScale` 0.40。予算の下限 0.8 を割る理由は「バランス」）。失った HP の 20% は換算せずに足す（最大 HP の 4,000〜5,000 の相手が HP 5% のとき +760〜950）: 公式の「実行型」の特徴。テスト（`testAbysmDamageGrowsWithTheTargetsLostHealth`）が満タンで予算内・HP 5% で基礎の 2 倍を超えることを確認 |
| 奥義 鈍足 55% 0.8 秒 | ○ | 命中した敵（ミニオン・モンスターを含む）に `slow` 0.55 を 0.8 秒 |
| 奥義は制圧（suppress）以外では中断されない（スタン・打ち上げでは止まらない） | ○ | 溜めのタイマーは `interruptible: false`（ハード CC で取り消されない）。`update` が suppress を見たら溜め・予約を取り消す。溜めの間は自分に `root` + 表示用の `channeling`（その場から動けず、攻撃・ほかのスキル・再使用を始められない）。スタン・打ち上げを受けても一撃は出る。死亡で全部リセット |
| 奥義 Flicker で向き・射程を変えられる | × | 向きは発動時に固定。Flicker（バトルスペル）との連動は無い（溜めの間は動けないので、Flicker で位置が変わってもその位置から固定の向きに撃つ） |
| 奥義 クールダウン 36 / 32 / 28 秒、コスト無し | ○ | 公式と同じ 36 / 32 / 28 秒。コストは 0 |
| パッシブのバッジと演出の合図 | ○ | パッシブのバッジは `.stacks`（値 = `Int(レイジ / 50)`、最大 2）。Director はバッジが増えた瞬間（レイジ 50・100）にだけパッシブの演出を出す。アビス強化を放ってバッジが 1 → 0 に戻ったとき（スキルの発動の直後）は `HeroFXSet.passiveRelease`（赤い気が拳へ抜ける）。レイジ 100 から放って 2 → 1 のときは解放の合図は出ない（フレームワークの合図は 1 以上 → 0 のときだけ） |
| 円撃の専用の演出 | × | フレームワークにイベントを足さない方針なので専用の合図は無い。円撃は通常攻撃の命中（`atk_hit`）が周囲の各対象に出るだけ（`passiveRelease` は「スキルの発動の直後にスタックが尽きた」ときだけなので、円撃の合図には使えない）。パッシブのバッジを円撃の合図に使うとレイジの段と混ざる（バッジの種類を行き来すると演出が誤って鳴る）ため見送り |
| ボット: 奥義 | ○ | `botCast`: 交戦中の敵ヒーローが射程の手前（現在の距離 540 以内）に居れば `.castNow(.direction)`（汎用の関門 = 倒せる・2 体以上 を待たない）。溜め 0.5 秒の間の動きを、直前の tick の動き（`prevPos → pos`）が続くものとして読み（敵の移動速度の 0.5 秒分まで）、その向きに固定して撃つ。溜め中は新たに撃たない。ミニオン・遠い敵・交戦中でないときは従来どおり |
| ボット: ファーム | ○ | `botFarm` で紅蓮の踏込（スキル2 の 1 回目）だけミニオン・ジャングルにも使う。HP が半分以上で、集団の位置が敵のタワー・コアの射程（750 + 半径 + 120）に入らないときだけ。赤拳連斬（スキル1）は扇なので従来どおりの経路 |
| 説明文 | ○ | 公式の文の構造（段落・語順。「再発動：」「アビス強化：」）に合わせ、UI の用語（スキル1・スキル2・アルティメット）で書く。`{base}(+{atkPct}%物理攻撃)` / `(+{pct}%追加物理攻撃)` は換算後の値。パッシブは 0.55 秒（通常攻撃・円撃）と 0.05 秒（スキル）の両方を書く（`Tune` から展開するので数値が sim とずれない）。タグは公式（パッシブ = バフ・回復、S1 = 範囲技・減速、S2 = 移動・ダメージ → `mobility` `burst`、ULT = バースト・減速） |
| 武器の「ゲーム的な体感」: 連続の殴り合いと CD リセットのループ | ○ | 通常攻撃・円撃 → CD 短縮 → S1 / S2 → …の回転。アビス強化は S1（5 連）→ S2 の 2 回目（防御ダウン −60%）→ 奥義の順に火力が高まる |
| 弱点: カイティング、奥義の前の CC | ○ | 溜め 0.5 秒の間は動けず（root）、制圧以外は止まらないが、溜めに入る前の CC・距離取りで不発にできる。S1 の連撃は途中のスタンで取り消される |

### 選んだ値（調査に無い・換算した値）

| 項目 | 値 | 理由 |
|---|---|---|
| レイジの時間倍率 | なし（MLBB の 2〜5%/s） | 全体の CD が半分だったころは ×2（1 回の CD あたりにたまる量を MLBB に合わせる）。CD が MLBB の秒数になったので外した |
| アビス強化の消費 | 50 | 調査に「不明」。閾値と同じ値にした（100 で 2 回ぶん） |
| 円撃の半径 | 190 | 通常攻撃の射程 150 より少し広い（MLBB の 1.7 → 2.0 の比） |
| S1 の射程・半角・間隔 | 300 / 400（アビス）・0.65 rad・0.14 秒 / 0.11 秒 | 近接スキルの標準。調査に無い |
| S1 の連続ヒットの減衰 | 1.0 / 0.3 / 0.3（アビス: 1.4 / 0.42 × 4） | Fandom の減衰率（Liquipedia は「減衰する」とだけ）。以前は 1.0 / 0.7 / 0.5 を選んでいた |
| S2 の突進 | 距離 400・速度 2400・幅 110・押し出し 130 / 0.18 秒 | 調査に「不明」。汎用の近接の突進（range 300 + 100）に合わせた |
| S2 の致命の一撃 | 射程 350 / 500（アビス）・速度 2600・窓 3 秒 | 調査に「不明」 |
| 防御ダウンの割合 | 40% / 60%（アビス）・4 秒 | 調査どおり（割合の `armorShred`） |
| 奥義の溜め・射程・幅 | 0.5 秒・650・半幅 140 | 調査に「短い遅れ」「不明」。溜めで向きが固定されるので、MLBB の「画面の半分ほど届く長い直線」に寄せて標準の 420 から伸ばした（ボットは敵の動きを読んで撃つ） |
| 失った HP の割合 | 20% | 公式（Liquipedia・Fandom とも 20%。以前は 25% の資料との中間 22.5%） |
| ダメージの換算 | `burstScale` 0.18 / `spectreScale` 0.33 / `ultScale` 0.40 | 公式の表（ランクで補間 + 攻撃力係数）を sim の通常の式 × スロット倍率に通したあとに掛ける。下の「バランス」 |
| 説明文の数値 | 名前付きトークン（`{base}` `{atkPct}` `{dashBase}` `{fatalBase}` `{abyssShown}` など）と、本文中の定数（`Tune` を文字列に展開） | 数値を sim とずらさない |

### バランス（`KitBalanceTests`、Release、全員総当たり。同ロール（Duelist）の汎用ヒーローの中央値との差）

全 34 ヒーローとの 1v1（`BalanceHarness`: 両陣営 × 開始距離 300/450/600 × 種 2 の 12 戦の平均、Lv 1/6/12、スキル自動習得、引き分けは半分）の勝率を、同ロールの汎用ヒーローの中央値と比べる。
値は離散的（1 戦 ≈ 0.25pt）で、ほかのキットの調整で相手が変わると ±2pt 程度動く。

| | Lv1 | Lv6 | Lv12 | 開幕 3 秒の火力（汎用の中央値比 Lv1 / 6 / 12） |
|---|---|---|---|---|
| 前の版（S1 0.82・S2 0.82・奥義 0.90・短縮 0.4 / 0.1・円撃の回復 4.2〜6%） | 95.5% (+22.5) | 79.8% (+3.8) | 89.4% (+22.2) | 4.94 / 2.28 / 2.13 |
| 公式の表の前（S1 0.70・S2 0.82・奥義 0.90・短縮 0.3 / 0.05・円撃の回復 3〜4%） | 83.8% (+7.6) | 70.7% (−5.6) | 77.3% (+7.6) | 4.21 / 1.93 / 1.82 |

開幕 3 秒の火力が Lv1 だけ 4 倍を超えるのは、ハーネスの都合: Lv1 の汎用 Duelist はスキル1 を撃たない（中央値 ≈ 280）のに対し、ディアスは赤拳連斬を 3 秒で撃つため。Lv6 / Lv12 は 2 倍を切った。

調整の経緯（上の表に至るまでに試した組み合わせ。Lv1 / Lv6 / Lv12 の「中央値との差」）:
- S1・S2 を 0.72、奥義 0.82（短縮 0.3 / 0.1・回復はそのまま）: +14.9 / −7.8 / +10.6。倍率が効く。
- さらに短縮を 0.15 / 0.05 にすると −0.3 / −17.7 / +5.5（スキル2 の稼働率が半分になり Lv6 が落ちすぎ）。
- 短縮 0.3 / 0.1、S1 0.72・S2 0.76・奥義 0.85: +14.9 / −4.8 / +14.6（上限ぎりぎり）。
- **S1 0.70・S2 0.82・奥義 0.90・短縮 0.3 / 0.05・回復 3〜4%**（採用。奥義 0.88 の試行が +10.8 / −6.3 / +10.1、最終の表は上）。
S1 の通常版が予算の下限 0.8 を割る（0.70）のは、アビス強化（合計の 1.4 倍 = 0.98）・クールダウン短縮・円撃の上乗せがあるため。テストは S1 の通常版の下限だけ 0.65 にして、理由を書いてある。
最初の版（短縮 0.5 / 0.5、倍率 0.90 / 0.90 / 0.95、回復 7〜10%）は 100% / 100% / 100% で支配的だった。効いたのは倍率とクールダウン短縮（スキルの稼働率）で、円撃の回復の影響は小さい。
TTK は H001〜H006 相手で 2.5〜22 秒（CD が半分だったころの帯は 2.5〜15 秒）の帯に収まる（`testDuelTimeToKillStaysInBandAgainstTheRoleRepresentatives`）。

### 既知の差・リスク

- コストは公式どおり 0（`HeroKit.cost`）。Energy のゲージはマスターデータのまま残る（使わない）。
- スキル2・奥義の「追加物理攻撃」の分は発動時に足すので、HUD・スキル詳細の数値（`numbers`）は装備なしの値。
- 円撃の「攻撃エフェクトは発動しない」は未対応（主対象の命中時効果・吸血はそのまま。Fandom は吸血が乗ると注記）。強化ダメージはタワーに乗らない（主対象が構造物なら通常攻撃のダメージ）。
- S1 のアビス強化の射程（400）と S2 の 2 回目のアビス強化の射程（500）は、HUD の照準情報（`targeting`）には出ない（状態＝レイジが要るため）。
  実際の発動（`resolveAim` / `cast`）が見る。照準円は通常版の大きさ（300 / 350）。
- S1 の連撃は発動時の向きに固定するが、中心は **撃った瞬間の自分の位置**（S2 で動けば追従する）。
- 円撃に専用の演出イベントは無い（`attackReleased` + ダメージのイベントのみ）。S1 / S2 のアビス強化と S2 の 2 回目は `SkillCastEvent.count / stage` で
  見分けられるが、現在の `SkillFXDirector` はレシピを共通で再生する。
- 奥義の失った HP の加算はすべての敵。ヒーロー以外は上限（換算後の 1500 / 2000 / 2500）で止まる。
- 奥義の溜め中に Flicker 等で位置が変わっても、固定の向きのまま新しい位置から撃つ（Flicker で向き・射程を変える仕様は未対応）。
- ボットの奥義: 交戦中の敵ヒーローが現在 540 以内に居れば `.castNow` で、溜めの間の動きを読んだ向きに撃つ（`botCast`）。直前の tick の動きが続くと仮定するので、溜めの 0.5 秒の間に曲がる・止まる相手には外れる（敵の移動速度の 0.5 秒分までしか先読みしない）。それ以外（遠い・ミニオン）は汎用の判断（倒せる・2 体以上）のまま。
- 奥義の射程を 420 → 650 にしたので、溜めの間に向きが固定された直線は MLBB に近い長さになった一方、敵から見ると避ける余裕（0.5 秒 + 見える `wideLine` の帯）が増える。照準の帯・FX の線の長さ・ボットの射程は同じ値（`HeroKits.targeting` の `range` / `radius`）を見る。
- 円撃に専用の演出の合図は無い（フレームワークにイベントを足さない方針）。レイジの段のバッジ（0〜2）はパッシブ全体の合図に使い、円撃の合図には使わない。アビス強化を放ったときだけ `passiveRelease` の演出が出る（レイジ 100 から放って 2 → 1 になるときは出ない）。

### クールダウンを MLBB の秒数に（2026-10）

- 全体の CD 倍率 0.5 を廃止（S1 6 → 4 秒、S2 6 秒、奥義 36 / 32 / 28 秒）。レイジの ×2 を外して MLBB の 2〜5%/s、CD 短縮は CD に対する割合を保って 0.3 / 0.05 → 0.6 / 0.1 秒。
- `KitBalanceTests`（デュエリスト中央値との差）: 変更前 +7.6 / −5.6 / +4.5 → 変更後 +21.7 / +18.2 / +28.0 pt（帯の内。円撃の回復が長い 1v1 で効く）。

### 公式の表へ置き換え（2026-10）

上の「公式（現行シーズン）の数値」に合わせて、ダメージ・コスト・CC・減衰・タグ・説明文を作り直した（H029 ボルグと同じ方法）。

| 項目 | 公式（現行） | 以前の実装 | 今回 |
|---|---|---|---|
| コスト | 無し | マスターの Energy 40 / 50 / 85 × 0.6 | **0**（`HeroKit.cost`） |
| スキル1 CD | 6.0 → 4.0 | 同じ | 同じ |
| スキル1 ダメージ | 1 発 240 → 520 (+60%)、同じ敵へ 30% に減衰（Fandom）、ミニオン 75% | 汎用 S1 の 0.70 倍を重み 1.0 / 0.7 / 0.5 で配る、ミニオン 60% | 1 発目 = (表 + 0.6 × 攻撃力 × 0.6) × 4.0 × `burstScale` 0.18（ランク 1 の基礎 173、+26%）、2・3 発目 30%、ミニオン 75% |
| スキル1 強化 | 射程が伸びる・1 発ごとに 140%・減速 2 倍（5 回） | 合計の 140% を 5 発へ | 1 発目 140%・以降 42%（単体の合計は通常版の 1.925 倍）、減速 50% |
| スキル2 CD | 6.0 | 同じ | 同じ |
| スキル2 ダメージ | 1 回目 230 → 355 (+60% 追加物理攻撃)、2 回目 345 → 570 (+120% 追加物理攻撃) | 汎用 S2 の 0.82 倍を 0.4 : 0.6 | 表 × 3.0 × `spectreScale` 0.33（ランク 1: 228 / 342）+ 追加物理攻撃の分（発動時） |
| スキル2 CC | 防御 −40% 4 秒、強化は −60% + 追加の鈍足 90%（1 秒） | 強化の鈍足 50% 1.2 秒 | 公式どおり（90% 1 秒） |
| アルティメット | 650 / 950 / 1250 (+250% 追加物理攻撃) + 失った HP の 20%、減速 55% 0.8 秒、ヒーロー以外へ上限 1500 / 2000 / 2500 | 汎用の奥義の 0.81〜0.99 倍 + 失った HP の 22.5%（ヒーローだけ） | 表 × 2.6 × `ultScale` 0.40（676 / 988 / 1300）+ 追加物理攻撃の分 + 失った HP の 20%（すべての敵）、ヒーロー以外は上限 1560 / 2080 / 2600（換算後） |
| 円撃 | 150〜180%（タワーには強化が乗らない）、回復 7〜10% | 150〜180%（タワーにも）、回復 3〜4% | 150〜180%（タワーには通常攻撃のダメージ）、回復 1.4〜2%（公式の 0.2 倍・同じ伸び方） |
| CD 短縮 | 敵にダメージを与えるたび 1 秒 | 通常攻撃・円撃 0.6 秒 / スキル 0.1 秒 | 0.55 秒 / 0.05 秒 |
| タグ | バフ・回復 / 範囲技・減速 / 移動・ダメージ / バースト・減速 | なし | `buff` `heal` / `aoe` `slow` / `mobility` `burst` / `burst` `slow` |

説明文は公式の文の構造（「指定方向へ突進し、…止まり、…わずかにノックバックさせる。」「再発動：…」「アビス強化：…」）に合わせ、換算後の `{base}(+{atkPct}%物理攻撃)`・`(+{pct}%追加物理攻撃)` を入れる。

バランス（`KitBalanceTests`、Release、デュエリスト汎用の中央値との差。換算を環境変数で振って総当たりを測った。汎用の中央値は置き換え前の計測 73.7 / 75.8 / 69.0 %）:

| 試した組み合わせ | Lv1 | Lv6 | Lv12 |
|---|---|---|---|
| 置き換え前 | +21.7 | +18.2 | +28.0 |
| 公式の表・S1 0.22 / S2 0.33 / ULT 0.60・回復 3〜4%・短縮 0.6 / 0.1 | +12.2 | +14.2 | +28.0 |
| 同（S1 0.20・ULT 0.57）+ 短縮 0.3 / 0.05 | +5.6 | +5.6 | +15.9 |
| 短縮 0.6 / 0.1 のまま回復だけ 2.5% | +10.1 | +9.7 | +23.0 |
| 短縮 0.3 / 0.05・回復 2.1〜3%（全体計測で +2.0 / +2.0 / +10.6） | +0.5 | +3.6 | +10.4 |
| **採用: S1 0.18・S2 0.33・ULT 0.40・短縮 0.55 / 0.05・回復 1.4〜2%**（最終の全体計測、中央値 75.3 / 77.5 / 72.0 %） | **67.7 (−7.6)** | **72.2 (−5.3)** | **85.9 (+13.9)** |

勝率が一番よく揃ったのは短縮 0.3 秒の組み合わせだが、旧式の台本（`SkillBalanceTests.duel`）の 1v1 で Lv6 の H028（ザイル）に負けるようになり、
H028 の総当たりの上限（`Kit_H028Tests.testRoundRobinWinRateStaysNearTheGenericAssassins`、85% 未満）を 87.9% で超えた（他のキットの調整の外なので、こちらで合わせた）。
H028 に勝てるのは短縮 0.55 秒以上のときだけで、そのとき Lv12 が +16〜18 に上がるので、Lv12 に効く奥義の換算（0.57 → 0.40）・円撃の回復（0.3 → 0.2 倍）・スキル1（0.20 → 0.18）を下げた。
その結果、予算の下限 0.8 を割る項目がある: スキル1 の通常版 0.41〜0.54 倍（強化版 0.79〜1.05 倍）、奥義の基礎 0.57〜0.80 倍。テストは S1 の通常版 0.40・強化版 0.75・奥義 0.55 を下限にした。
開幕 3 秒の瞬間火力の比（報告のみ）: 2.19 / 1.17 / 1.19（Lv1 は汎用の Duelist がスキル1 を撃たないハーネスの都合で高い）。全体の Release（978 テスト）は 0 failures。
