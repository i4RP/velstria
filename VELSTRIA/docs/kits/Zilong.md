# Zilong (MLBB) - Kit Specification

Primary source: Mobile Legends Fandom hero page (fetched via the MediaWiki API, page edited 2026-10-08, includes the 2.1.40 passive buff) plus its patch history page. mlbbhub.com confirms the structure but gives no numbers. "unknown" = not found. "disputed" = sources disagree. Ranges are in wiki "units".

## Hero overview
- Role / lane: Fighter/Assassin (Chase/Damage), EXP Lane. Melee, mana resource, physical damage. Ratings: durability 2, offense 5, control 6, difficulty 1 (on a 1-10 scale).
- Basic attack: melee single target, range 1.8 normally and 2.5 while the passive's Dragon Flurry attack is empowered. Attack speed 1.05 base.
- Level 1 stats: HP 2511, HP regen 7.0, mana 500, mana regen 4, physical attack 123, physical defense 25 (17.2% reduction), magic defense 15 (11.1%), attack speed 1.05, movement speed 265, crit damage 200%.
- Level 15 stats: HP 5549, regen 12.6, mana 1900, physical attack 249, physical defense 90, magic defense 50, attack speed 1.33.
- Growth per level: HP +217, regen +0.4, mana +100, mana regen +0.2, physical attack +9, physical defense +4.6429, magic defense +2.5, attack speed +0.02.
- Team buff "The Oriental Fighters": more Oriental Fighters in the match gives the team extra fixed movement speed (1/2/3 per fighter present).
- Max skill levels: S1 6, S2 6, Ultimate 3.

## Passive - Dragon Flurry
- Cast type: passive, counter-based empowered basic attack.
- After dealing damage 3 times with basic attacks or skills (skills count since 2.1.40, e.g. Spear Strike is one of the three), his next basic attack triggers Dragon Flurry, hitting the target 3 times. Each hit deals 80 (+30% total physical attack) basic-attack damage and heals him 50 (+20% total physical attack) HP. Enhanced basic attack range 2.5.
- The page also lists "Zilong's basic attack deals 100 (+80% total physical attack) physical damage" (its meaning in the new version is unclear; probably the display of the normal-attack value). Unknown whether the 100+80% is per hit or a tooltip.
- Execute bonus: if the target's HP is below 50%, all damage dealt by his skills and basic attacks increases by 30 (flat).
- Disputed: older patch history (1.8.08) shows the passive as damage 30 + 40% total physical attack and heal 30 + 20% total physical attack, 3 times. The current page is newer; use 80 + 30% / 50 + 20%.

## Skill 1 - Spear Flip
- Cast type: point-and-click on a target enemy, short range (range: unknown).
- Flings the target enemy over his head (airborne with a displacement behind him), dealing 250-350 (+80% total physical attack) physical damage. The wiki classes it as an airborne (high-level CC: prevents moving, attacking and skills, interrupts many skills and blink/charge effects). Airborne duration: unknown.
- Cooldown 12.0/11.5/11.0/10.5/10.0/9.5 s. Mana 80/85/90/95/100/105. Base damage 250/270/290/310/330/350.
- The wiki notes it is a variation of airborne that lifts the enemy over Zilong's back (the target ends up behind him). Landing distance: unknown.

## Skill 2 - Spear Strike
- Cast type: point-and-click dash/blink onto the target enemy (the dash passes through obstacles as a blink).
- Lunges at the target enemy, dealing 250-450 (+60% total physical attack) physical damage and reducing their physical defense by 15-30 for 2 s. Search-extract descriptions add that he then launches a basic attack on the same target (not stated on the Fandom page; treat as likely but unconfirmed).
- The cooldown resets each time Zilong kills an enemy. The reset also applies if a minion dies within 0.5 s after he damaged it (patch 1.8.08).
- Cooldown 12.0/11.4/10.8/10.2/9.6/9.0 s. Mana 40 at all levels. Base damage 250 to 450 over 6 levels (wiki template is a linear 6-step range, i.e. 250/290/330/370/410/450; per-level row not shown on the page). Physical defense reduction 15/18/21/24/27/30.
- Dash range and speed: unknown.

## Ultimate - Supreme Warrior
- Cast type: self-cast, instant buff.
- Removes all slow effects from himself and gains 40% movement speed, 35%/45%/55% attack speed and slow immunity for 7.5 s. During it Dragon Flurry triggers after every 2 damaging hits (instead of 3). A search extract claims "after every basic attack" for the older wording; use the Fandom value of 2.
- Cooldown 35/31/27 s. Mana 120/140/160. Attack speed bonus 35/45/55%.
- Slow immunity covers enemy slows only; whether it also counters other CC: unknown (wiki lists it as "exceptional status").

## Gameplay identity
- Dive-and-chain: Spear Strike (dash + defense shred) into Spear Flip or ultimate to stay on a target.
- Reset sustain: kills reset Spear Strike, so he snowballs by chaining kills or minion last hits to rush across the lane.
- Dragon Flurry gives a built-in triple hit with self-heal, so his sustained fights are strong even without items; the ultimate speeds it up to every 2 hits.
- Execute-style damage under 50% HP, with the 2.5-range empowered attack for chasing.
- Control comes from Spear Flip only (single-target airborne); the rest is raw chase.

## Simulation notes
- Standard: melee basic attack, point-and-click dash (blink), point-and-click airborne, defense-shred debuff, self buff with slow immunity and cleanse, movement-speed and attack-speed buffs.
- Needs special state: hit counter for Dragon Flurry (counts attack and skill damage instances, resets after trigger, counter threshold changes from 3 to 2 under the ultimate); enhanced basic attack with larger range and a 3-hit sequence that heals; Spear Strike cooldown reset on kill or on minion death within 0.5 s after damage; execute bonus (+30 flat damage below 50% target HP); displacement of the thrown target to Zilong's back; team-level Oriental Fighters passive (low priority).

## Sources
- https://mobile-legends.fandom.com/wiki/Zilong
- https://mobile-legends.fandom.com/wiki/Zilong/Patch_history
- https://mlbbhub.com/heroes/zilong (confirms skills now feed Dragon Flurry after 2.1.40)
- Search extracts of guide sites (afkgaming.com, oneesports.com Zilong guides) for the post-dash basic attack.

## Velstria 実装対応表

H027 竜槍のジャルド（デュエリスト・近接 150・Energy）= Velstria 版の Zilong。実装: `Packages/VelstriaCore/Sources/VelstriaCore/Systems/Kits/Kit_H027.swift`、
テスト: `Tests/VelstriaCoreTests/Kits/Kit_H027Tests.swift`、演出: `App/Battle/SkillFX/Heroes/FX_H027.swift`。
スロットは上の調査の順に割り当てる（Skill1 = Spear Flip、Skill2 = Spear Strike、Ultimate = Supreme Warrior、Passive = Dragon Flurry）。
距離は Velstria 単位（≈ MLBB × 100）。調査に無い値（射程・打ち上げ時間・突進速度）は下の「選んだ値」に書いた。
ダメージ・クールダウンは Velstria 全体の係数（`Balance.Skills`）に合わせた換算で、MLBB の数値そのままではない。

### 対応表（○ = 実装、△ = 簡略化、× = 見送り）

| 元の仕様 | 状態 | Velstria での実装・理由 |
|---|---|---|
| 通常攻撃: 近接単体、射程 1.8（Dragon Flurry 準備中は 2.5） | ○ | 射程 150。竜気が満タンの間だけ `attackRangeBoost` +58（150 → 約 208、MLBB の 2.5 / 1.8 の比）。撃つと即座に外す |
| パッシブ: ダメージを 3 回与えると次の通常攻撃が三連撃（スキルも数える） | ○ | 竜気（`ints[0]`）。通常攻撃の命中とスキルの「ダメージ > 0 の命中」で +1（CC のみの命中・奥義は数えない）。3 で満タン。死亡で 0 |
| 三連撃: 1 撃 80 + 攻撃力 30%、命中ごとに 50 + 攻撃力 20% 回復 | ○ | `shapeBasicAttack` で主攻撃 + 追加 2 発（同 tick）に整形。各発に `HitEffect.healOwner`。会心は 3 発で 1 回の判定を共有。三連撃自体の命中は竜気を増やさない（旧版の仕様どおりリセット） |
| 三連撃の間隔（アニメーション上の連続） | △ | 3 発は同じ tick に当たる（sim にヒット間隔の概念が無い）。演出側で連続して見せる |
| 「通常攻撃 100 + 80%」の表記 | × | 意味が不明（調査にも「表示用の可能性」とある）。通常攻撃は汎用の攻撃力どおり |
| 旧版（1.8.08）の 30 + 40% / 30 + 20% | × | 現行（80 + 30% / 50 + 20%）を採用（調査の指示どおり） |
| HP 50% 未満の相手へ通常攻撃・スキルのダメージ +30（固定） | ○ | 固定値を `HitPayload.damage` に足す（発動・攻撃開始の時点の HP で判定。三連撃は 3 発とも +30）。`outgoingDamageBonus` は割合しか返せないので使わない。構造物には付かない |
| S1 Spear Flip: 対象指定、敵を頭上へ跳ね上げ背後へ飛ばす、打ち上げ | ○ | 射程 300（対象の縁まで）。ダメージ後 `knockUp` 0.8 秒 + `MovementSystem.knockback` で術者の背後 170 に 0.7 秒で着地。CC 無効の相手はダメージのみ（動かさない）。照準は `requiresTarget`（居なければコスト・CD を消費せず失敗）。ヒーロー優先 → HP + シールド最小、指定ユニット・地点・向きも対応 |
| S1 ダメージ 250〜350 + 80% | △ | 汎用 S1 のダメージ（`base.damage`）の 1.05 倍。ランクは 4 段（元は 6 段） |
| S1 クールダウン 12 → 9.5 秒、マナ 80 → 105 | △ | クールダウンは 12 → 9.5 秒をランクで線形補間 × `cooldownScale`（0.5）。コストはマスターデータ（スキルの `cost`）のまま: 消費量は `SkillSystem.validate` がマスターから決めるのでキットでは変えられない（S1 より S2 が高いなど元の大小は再現できない） |
| S2 Spear Strike: 対象指定の突進（障害物を越えるブリンク） | △ | `.targetedBlink` + `requiresTarget`、`Kit.dashSweeping`（経路上の敵には当てない carrier）で突進。速度 2400、射程 450。壁は越えられず手前で止まる（`MovementSystem.dash` の仕様）。ハード CC で突進と一撃が取り消される |
| S2 ダメージ 250 → 450 + 60% | △ | 汎用 S2 の 1.10 倍。到着した tick に 1 度だけ。対象が突進中に倒れる・260 以上離れる・対象不可になると外れる（追尾はしない） |
| S2 物理防御 −15 → −30（2 秒） | ○ | `armorShred`（割合）へ換算: 到着時の対象の防御に対する 固定値 / 防御（上限 0.9）。固定値は 15〜30 をランクで線形。ダメージの後に付くので、その一撃には掛からない |
| S2 のあとに通常攻撃（調査では未確認） | ○ | 到着後に `attackTargetID` を対象にして攻撃間隔を 0 に（そのまま殴る） |
| S2 は敵を倒すたびにクールダウンリセット（倒す直前 0.5 秒以内にダメージを与えたミニオンも） | ○ | 直前に傷つけた敵（通常攻撃・スキル、構造物以外）を覚えて 0.5 秒（`timers[1]`）。その敵が倒れたら S2 のクールダウンを 0 に。ヒーローの撃破は `onKillOrAssist`（止めが自分のときだけ、アシストは除く）でも戻す。練習場の `noCooldowns` を尊重（`Kit.setCooldown`） |
| 奥義 Supreme Warrior: スロウ解除、移動速度 +40%、攻撃速度 +35/45/55%、スロウ無効、7.5 秒 | ○ | 発動で `slow` を全部外し、`speedBoost` 0.40 と `attackSpeedBoost`（ランク別）を 7.5 秒。スロウ無効は専用の status が無いため、`update` で毎 tick `slow` を取り除く（掛かった同じ tick のうちに消える。他の CC は防がない） |
| 奥義中は 2 回で Dragon Flurry | ○ | 奥義の残り（`timers[0]`）> 0 の間、竜気の必要数 3 → 2 |
| 奥義 CD 35/31/27、マナ 120〜160 | △ | CD は 35 → 27 を 3 ランクで線形 × 0.5。コストはマスターのまま |
| 奥義にダメージ・CC は無い | ○ | ダメージ 0。「スロット 1 つの単体ダメージは汎用の 0.8〜1.3 倍」の予算は奥義には適用しない（自己強化のみ。代わりにパッシブと攻撃速度の強化が火力になる。H001〜H006 との 1v1 の TTK は 2.5〜15 秒に収まる） |
| チームパッシブ「The Oriental Fighters」（東洋の戦士が居ると移動速度 +1/2/3） | × | 調査でも低優先。チーム構成のシナジー層が無い |
| 再使用（recast） | – | Zilong には無いので使わない（HUD の `recastable` は false、窓は開かない） |

### 選んだ値（調査に無い・換算した値）

| 項目 | 値 | 理由 |
|---|---|---|
| S1 射程 | 300（対象の縁まで） | 近接スキルの標準（マスターの S1 射程 300） |
| S2 射程 | 450 | 近接の突進（標準 400）より少し長い追撃手段。Zilong の突進は届く範囲が広い |
| 打ち上げ | 0.8 秒、背後 170 に 0.7 秒で着地 | 調査に無い。汎用ノックバック（0.25 + 0.25 秒）より長い「放り投げ」 |
| 突進速度 | 2400（約 0.2 秒） | 汎用の突進（1500）より鋭い。「対象指定の踏み込み」に見える速さ |
| 防御ダウンの換算 | 固定値 / 対象の防御 | Velstria の `armorShred` は割合。到着時の防御で換算すれば元の「−15〜30」と同じ効果になる |
| ダメージ倍率 | S1 1.05 / S2 1.10 | CD が汎用より長い（S1 6 → 4.75 秒、S2 6 → 4.5 秒。汎用は 3.25 / 4.35）ぶんを補い、1v1 の勝率が全ヒーローの上位に偏らないように抑えた |
| 説明文の数値 | パッシブ x0 = 三連撃の 1 撃（整数）、x1 = 回復、x2 = +30、x3 = 竜気の必要数 | `KitText` のトークン（`{x0}`〜`{x3}`）に sim の数値を入れる |

### 既知の差・リスク

- スキルのマナ（コスト）の相対関係（S1 80〜105、S2 40、奥義 120〜160）は再現できない（マスターデータ固定）。
- 三連撃の 3 発が同 tick のため、HP 50% の境目をまたぐ 2・3 発目も 1 発目の判定どおり +30 になる（最大 +60 の誤差）。
- スロウ無効は status ではなく毎 tick の除去。奥義中に SpellSystem など `SkillSystem.update` より後で掛かったスロウは 1 tick だけ移動速度に効く。
- 「S2 の突進で壁を越える」は未対応。壁際ではブリンクにならず手前で止まり、`strikeSlack` を超えると外れる。
