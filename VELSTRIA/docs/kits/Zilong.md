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

## 公式（現行シーズン）の数値

2026-10 に MediaWiki API で取り直した（Fandom の `Zilong`、Liquipedia の `Zilong`。両方とも同じ値。Liquipedia はティグラルで日本語クライアントの値と一致した）。
スキルのレベルは公式でスキル1・2 が Lv1〜6、アルティメットが Lv1〜3。

| スロット | 公式名 | タグ | 内容 |
|---|---|---|---|
| パッシブ | Dragon Flurry | バフ・回復 | 通常攻撃かスキルでダメージを 3 回与えると、次の通常攻撃で Dragon Flurry が発動し、対象を 3 回攻撃する。1 回ごとに 80（+30% 物理攻撃）の通常攻撃ダメージを与え、50（+20% 物理攻撃）HP を回復。対象の HP が 50% 未満なら、スキルと通常攻撃のダメージが 30 増える |
| スキル1 | Spear Flip | CC・ダメージ | CD 12.0 / 11.5 / 11.0 / 10.5 / 10.0 / 9.5、MP 80 / 85 / 90 / 95 / 100 / 105、基礎ダメージ 250 / 270 / 290 / 310 / 330 / 350（+80% 物理攻撃）。対象の敵を頭上へ放り投げる（打ち上げ。秒数の記載なし） |
| スキル2 | Spear Strike | 移動（ブリンク）・デバフ | CD 12.0 / 11.4 / 10.8 / 10.2 / 9.6 / 9.0、MP 40（一定）、基礎ダメージ 250 / 290 / 330 / 370 / 410 / 450（+60% 物理攻撃）、物理防御 −15 / 18 / 21 / 24 / 27 / 30（2 秒）。敵を倒すたびに CD リセット（1.8.08: ダメージの 0.5 秒以内に倒れたミニオンも） |
| アルティメット | Supreme Warrior | 加速・バフ | CD 35 / 31 / 27、MP 120 / 140 / 160、攻撃速度 +35 / 45 / 55%。スロウを解除し、7.5 秒間 移動速度 +40%・攻撃速度・スロウ無効。この間 Dragon Flurry は 2 回ごとに発動 |

### 公式が置き換えた調査の値

| 項目 | 以前の実装 | 公式 |
|---|---|---|
| ダメージ | 汎用のスキル値の倍率（S1 1.08 / S2 1.10。基礎はマスターの 120 / 144 を +30%/ランク） | 公式の表（250 → 350 +80% / 250 → 450 +60%）をランクで補間し、Velstria の式に換算 |
| マナ（Energy） | マスターの 40 / 50 / 84（× 0.6 = 24 / 30 / 50.4） | 80 → 105 / 40 / 120・140・160（Energy のヒーローなので × 0.6 = 48 → 63 / 24 / 72・84・96） |
| CD・CC・パッシブ | 同じ（確認） | 同じ |

ランクの対応: スキル1・2 の 4 ランク = Lv1 → Lv6 の線形補間（ランク r → Lv `1 + (r − 1) × 5 / 3`）、アルティメットの 3 ランクは公式の Lv そのまま。マナは補間した値を整数に丸めてから Energy の倍率を掛ける（スキル1 80 / 88 / 97 / 105）。

## Velstria 実装対応表

H027 竜槍のジャルド（デュエリスト・近接 150・Energy）= Velstria 版の Zilong。実装: `Packages/VelstriaCore/Sources/VelstriaCore/Systems/Kits/Kit_H027.swift`、
テスト: `Tests/VelstriaCoreTests/Kits/Kit_H027Tests.swift`、演出: `App/Battle/SkillFX/Heroes/FX_H027.swift`。
スロットは上の調査の順に割り当てる（Skill1 = Spear Flip、Skill2 = Spear Strike、Ultimate = Supreme Warrior、Passive = Dragon Flurry）。
マスターデータ上の最終名は パッシブ「竜の三連突き」/ スキル1「跳槍撃」/ スキル2「竜牙突き」/ アルティメット「至高の武人」（`tools/rename_kit_skills.mjs`）。説明文は UI の用語（スキル1・スキル2・アルティメット）で書く。
距離は Velstria 単位（≈ MLBB × 100）。調査に無い値（射程・打ち上げ時間・突進速度）は下の「選んだ値」に書いた。
ダメージ・クールダウン・マナ消費は上の「公式（現行シーズン）の数値」の表をランクで線形補間して使う（H029 ボルグと同じ方法）。ダメージは Velstria の通常の式（`(基礎 + 係数 × 攻撃力 × 0.6) × スロット倍率`）に換算（`Tune.flipScale / strikeScale`）するので、絶対値は MLBB と同じではない（説明文の `{base}(+{atkPct}%物理攻撃)` は換算後の値）。クールダウンは公式の秒数そのまま（全体倍率 `cooldownScale` は 1.0）。

### 対応表（○ = 実装、△ = 簡略化、× = 見送り）

| 元の仕様 | 状態 | Velstria での実装・理由 |
|---|---|---|
| 通常攻撃: 近接単体、射程 1.8（Dragon Flurry 準備中は 2.5） | ○ | 射程 150。竜気が満タンの間だけ `attackRangeBoost` +58（150 → 約 208、MLBB の 2.5 / 1.8 の比）。撃つと即座に外す |
| パッシブ: ダメージを 3 回与えると次の通常攻撃が三連撃（スキルも数える） | ○ | 竜気（`ints[0]`）。通常攻撃の命中とスキルの「ダメージ > 0 の命中」で +1（CC のみの命中・奥義は数えない）。3 で満タン。死亡で 0 |
| 三連撃: 1 撃 80 + 攻撃力 30%、命中ごとに 50 + 攻撃力 20% 回復 | △ | 1 撃のダメージは公式の 80 + 30% × 換算 `flurryScale` 0.6（= 48 + 18%。下の「公式の表へ置き換え」）、回復は公式のまま。`shapeBasicAttack` で 1 発目（通常攻撃と同じ tick）に整形し、2・3 発目は `Kit.schedule`（`onTimer`）で **4 / 8 tick 後（約 0.13 / 0.27 秒）**（予約は 0.14 / 0.28 秒。撃った tick を 1 回目に数えて減るので 4 / 8 tick 後に当たる）。各発に `HitEffect.healOwner`。会心は 3 発で 1 回の判定を共有（`param` = 会心倍率、`point.x` = 会心か）。三連撃自体の命中は竜気を増やさない（`ints[1]` を命中の瞬間だけ立てる） |
| 三連撃の間隔（アニメーション上の連続） | ○ | 3 発は別の tick に当たる。間隔 約 0.133 秒（0.13 だと 3 tick = 0.1 秒おきになってしまう）は被弾演出の間引き（Effekseer の近接ヒットは同じ相手へ 0.12 秒に 1 回）に潰されない長さ。ヒット演出は 1 発ごとに出る（通常攻撃のダメージごと）。遅れて当たる発は、対象が倒れた・射程（三連突きの伸びを含む + 30）の外へ出た・対象不可なら出ない。ハード CC で残りは取り消される（interruptible）。**HP 50% 未満の +30 と回復の倍率は、1 発ごとに当たる瞬間の対象で決める** |
| 三連撃の回復（ヒーロー以外） | △ | ミニオン・モンスター・タワーが相手なら回復は **半分**（ディアスの円撃と同じ。ジャングルの周回で回復が過大にならないように）。人形はヒーローと同じ扱い |
| 「通常攻撃 100 + 80%」の表記 | × | 意味が不明（調査にも「表示用の可能性」とある）。通常攻撃は汎用の攻撃力どおり |
| 旧版（1.8.08）の 30 + 40% / 30 + 20% | × | 現行（80 + 30% / 50 + 20%）を採用（調査の指示どおり） |
| HP 50% 未満の相手へ通常攻撃・スキルのダメージ +30（固定） | ○ | 固定値を `HitPayload.damage` に足す（発動・攻撃開始の時点の HP で判定。三連撃は 1 発ごとに当たる瞬間の HP で判定）。`outgoingDamageBonus` は割合しか返せないので使わない。構造物には付かない |
| S1 Spear Flip（跳槍撃）: 対象指定、敵を頭上へ跳ね上げ背後へ飛ばす、打ち上げ | ○ | 射程 300（対象の縁まで）。ダメージ後 `knockUp` 0.8 秒 + `MovementSystem.knockback` で術者の背後 170 に 0.7 秒で着地。CC 無効の相手はダメージのみ（動かさない）。照準は `requiresTarget`（居なければコスト・CD を消費せず失敗）。ヒーロー優先 → HP + シールド最小、指定ユニット・地点・向きも対応 |
| S1 ダメージ 250〜350 + 80% | ○ | 公式の表（250 → 350 をランク 4 段へ補間、+80% 物理攻撃）× スロット倍率 4.0 × 換算 `flipScale`（下の「バランス」）。以前は汎用 S1 の 1.08 倍 |
| S1 クールダウン 12 → 9.5 秒、マナ 80 → 105 | ○ | クールダウンは公式と同じ 12 → 9.5 秒（ランクで線形補間）。S2 も公式の 12 → 9 秒。マナは公式の表を `HeroKit.cost` で（80 / 88 / 97 / 105。Energy のヒーローなので × 0.6 = 48 → 63）。以前はマスターの 40 × 0.6 |
| S2 Spear Strike（竜牙突き）: 対象指定の突進（障害物を越えるブリンク） | △ | `.targetedBlink` + `requiresTarget`、`Kit.dashSweeping`（経路上の敵には当てない carrier）で突進。速度 2400、射程 450。壁は越えられず手前で止まる（`MovementSystem.dash` の仕様）。ハード CC で突進と一撃が取り消される |
| S2 ダメージ 250 → 450 + 60% | ○ | 公式の表（+60% 物理攻撃）× スロット倍率 3.0 × 換算 `strikeScale`（以前は汎用 S2 の 1.10 倍）。マナ 40 一定（× 0.6 = 24）。到着した tick に 1 度だけ。対象が突進中に倒れる・260 以上離れる・対象不可になると外れる（追尾はしない） |
| S2 物理防御 −15 → −30（2 秒） | ○ | `armorShred`（割合）へ換算: 到着時の対象の防御に対する 固定値 / 防御（上限 0.9）。固定値は 15〜30 をランクで線形。ダメージの後に付くので、その一撃には掛からない |
| S2 のあとに通常攻撃（調査では未確認） | ○ | 到着後に `attackTargetID` を対象にして攻撃間隔を 0 に（そのまま殴る） |
| S2 は敵を倒すたびにクールダウンリセット（倒す直前 0.5 秒以内にダメージを与えたミニオンも） | ○ | 直前に傷つけた敵（通常攻撃・スキル、構造物以外）を覚えて 0.5 秒（`timers[1]`）。その敵が倒れたら S2 のクールダウンを 0 に。ヒーローの撃破は `onKillOrAssist`（止めが自分のときだけ、アシストは除く）でも戻す。練習場の `noCooldowns` を尊重（`Kit.setCooldown`） |
| 奥義 Supreme Warrior（至高の武人）: スロウ解除、移動速度 +40%、攻撃速度 +35/45/55%、スロウ無効、7.5 秒 | ○ | 発動で `slow` を全部外し、`speedBoost` 0.40 と `attackSpeedBoost`（ランク別）を 7.5 秒。スロウ無効は専用の status が無いため、`update` で毎 tick `slow` を取り除く（掛かった同じ tick のうちに消える。他の CC は防がない） |
| 奥義中は 2 回で Dragon Flurry | ○ | 奥義の残り（`timers[0]`）> 0 の間、竜気の必要数 3 → 2 |
| 奥義 CD 35/31/27、マナ 120〜160 | ○ | CD は公式と同じ 35 / 31 / 27 秒。マナは公式の 120 / 140 / 160（× 0.6 = 72 / 84 / 96） |
| 奥義にダメージ・CC は無い | ○ | ダメージ 0。「スロット 1 つの単体ダメージは汎用の 0.8〜1.3 倍」の予算は奥義には適用しない（自己強化のみ。代わりにパッシブと攻撃速度の強化が火力になる。H001〜H006 との 1v1 の TTK は 2.5〜22 秒（CD が半分だったころの帯は 2.5〜15 秒）に収まる） |
| ボット: アルティメット | ○ | 交戦中の敵ヒーローに踏み込みの射程（450 + 半径）で届くなら `.castNow(.none)`（汎用の関門 = 倒せる・2 体以上 を待たない。自己強化なので殴り合いの頭に撃つ）。強化中は撃たない。ミニオン・遠い敵は従来どおり（関門を通ったとき） |
| ボット: ファーム | ○ | `botFarm` で竜牙突き（スキル2）だけミニオン・ジャングルにも使う（倒すたびにリセットされるので周回が速くなる）。HP が半分以上で、集団の位置が敵のタワー・コアの射程（750 + 半径 + 120）に入らないときだけ。跳槍撃（スキル1）は従来どおりの経路 |
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
| ダメージの換算 | `flipScale` / `strikeScale`（値は下の「バランス」） | 公式の表（ランクで補間 + 攻撃力係数）を sim の通常の式 × スロット倍率に通したあとに掛ける。汎用の 0.8〜1.3 倍に収まる値の中から勝率で選んだ |
| 説明文の数値 | パッシブ `{charge}` `{hits}` `{flurryFlat}` `{flurryPct}` `{healFlat}` `{healPct}`（公式の値）と `{flurryDamage}` `{flurryHeal}`（今の攻撃力での値）、`{executeFlat}` / スキル1・2 `{base}` `{atkPct}`（換算後）と `{damage}` / アルティメット `{moveSpeed}` `{attackSpeed}` `{duration}` `{charge}` | `KitText` のトークンに sim の数値を入れる。文は公式の構造（段落・語順）に合わせた。タグは公式（パッシブ = バフ・回復、S1 = CC・ダメージ → `control` `burst`、S2 = 移動・デバフ → `mobility` `disrupt`、ULT = 加速・バフ → `mobility` `buff`） |

### バランス（`KitBalanceTests`、Release、全員総当たり。同ロール（Duelist）の汎用ヒーローの中央値との差）

| | Lv1 | Lv6 | Lv12 | 開幕 3 秒の火力（汎用の中央値比 Lv1 / 6 / 12） |
|---|---|---|---|---|
| 三連突きを 3 発同 tick にしていた版 | 80.3% (+7.3) | 69.2% (−6.8) | 76.8% (+9.6) | 1.32 / 1.06 / 0.91 |
| 公式の表の前（3 発を 0.13 秒おきに、ヒーロー以外への回復は半分、倍率 S1 1.08 / S2 1.10） | 82.3% (+6.1) | 72.7% (−3.5) | 78.8% (+9.1) | 1.32 / 1.04 / 0.91 |

三連突きを遅らせて回復を半分にしただけだと Lv6 が −10.3 まで下がった（1.05 / 1.10）ので、S1 の倍率を 1.05 → 1.08 に戻した（S2 は 1.10 のまま）。
Lv1 は竜気がたまらず三連突きがまだ出ないので、開幕 3 秒の火力は通常攻撃だけ（汎用の Duelist の中央値の 1.3 倍）。

### 既知の差・リスク

- マナ（コスト）は公式の表（S1 80〜105、S2 40、奥義 120〜160）× Energy の倍率 0.6。Energy の最大値・回復はマスターデータのまま。
- ダメージの絶対値は公式と同じではない（換算つき）。スキル1 の基礎の伸び（250 → 350 = 1.4 倍）は汎用（+30%/ランク = 1.9 倍）より緩いので、高ランクほど以前の倍率より相対的に弱い。
- 三連撃の 2・3 発目は 約 0.13 / 0.27 秒後に、当たる瞬間の対象で +30・回復を決める（以前は 3 発とも 1 発目の判定で、境目で最大 +60 の誤差があった）。そのかわり、1 発目のあとの 0.27 秒の間に対象が射程の外へ出る・倒れる・対象不可になると残りは出ない（回復も出ない）。
- スロウ無効は status ではなく毎 tick の除去。奥義中に SpellSystem など `SkillSystem.update` より後で掛かったスロウは 1 tick だけ移動速度に効く。
- 「S2 の突進で壁を越える」は未対応。壁際ではブリンクにならず手前で止まり、`strikeSlack` を超えると外れる。

### クールダウンを MLBB の秒数に（2026-10）

- 全体の CD 倍率 0.5 を廃止（S1 12 → 9.5 秒、S2 12 → 9 秒、奥義 35 / 31 / 27 秒）。数値は変えていない。`KitBalanceTests`（デュエリスト中央値との差）: 変更前 +6.1 / −3.5 / +8.1 → 変更後 +24.7 / −1.5 / +13.4 pt。

### 公式の表へ置き換え（2026-10）

上の「公式（現行シーズン）の数値」に合わせて、ダメージ・マナ・タグ・説明文を作り直した（H029 ボルグと同じ方法。CD・CC・パッシブの仕組みは以前から公式どおり）。

| 項目 | 公式（現行） | 以前の実装 | 今回 |
|---|---|---|---|
| スキル1 CD / MP | 12.0 → 9.5 / 80 → 105 | 12.0 → 9.5 / マスター 40（× 0.6 = 24） | CD 同じ、MP 80 / 88 / 97 / 105（× 0.6 = 48 / 52.8 / 58.2 / 63） |
| スキル1 ダメージ | 250 → 350 (+80% 物理攻撃) | 汎用 S1 の 1.08 倍 | (表 + 0.8 × 攻撃力 × 0.6) × 4.0 × `flipScale` 0.50（ランク 1 の基礎 500、+96% 物理攻撃） |
| スキル1 打ち上げ | 秒数の記載なし | 0.8 秒（選んだ値） | 同じ |
| スキル2 CD / MP | 12.0 → 9.0 / 40 | 12.0 → 9.0 / マスター 50（× 0.6 = 30） | CD 同じ、MP 40（× 0.6 = 24） |
| スキル2 ダメージ・防御ダウン | 250 → 450 (+60%)、−15 → −30（2 秒） | 汎用 S2 の 1.10 倍、−15 → −30 | (表 + 0.6 × 攻撃力 × 0.6) × 3.0 × `strikeScale` 0.85（ランク 1 の基礎 638、+92%）、防御ダウンは同じ |
| アルティメット | CD 35 / 31 / 27、MP 120 / 140 / 160、移動 +40%・攻撃速度 +35 / 45 / 55%・7.5 秒 | MP はマスター 84（× 0.6） | MP 120 / 140 / 160（× 0.6 = 72 / 84 / 96）、ほかは同じ |
| パッシブ | 3 回で三連突き、1 撃 80 (+30%)・回復 50 (+20%)、HP 50% 未満で +30 | 公式の値そのまま | ダメージだけ換算 `flurryScale` 0.6（1 撃 48 (+18%)）。回復・+30・回数は公式のまま |
| タグ | バフ・回復 / CC・ダメージ / ブリンク（移動）・デバフ / 加速・バフ | なし | `buff` `heal` / `control` `burst` / `mobility` `disrupt` / `mobility` `buff` |

説明文は公式の文の構造（「通常攻撃かスキルでダメージを3回与えると、次の通常攻撃で…」「対象の敵を…放り投げ、…(+N%物理攻撃)の物理ダメージ」）に合わせ、換算後の `{base}(+{atkPct}%物理攻撃)` と今の値（`{damage}`）の両方を書く。

バランス（`KitBalanceTests`、Release、デュエリスト汎用の中央値との差。換算を環境変数で振って総当たりを測った。汎用の中央値は置き換え前の計測 73.7 / 75.8 / 69.0 %）:

| 試した組み合わせ | Lv1 | Lv6 | Lv12 |
|---|---|---|---|
| 置き換え前（汎用の 1.08 / 1.10 倍） | +24.7 | −1.5 | +13.4 |
| 公式の表・`flipScale` 0.63 / `strikeScale` 0.73・三連突きは公式のまま | +26.3 | −4.0 | +9.4 |
| 三連突きのダメージと回復を 0.8 倍 | +23.3 | −7.5 | −3.6 |
| 三連突きのダメージと回復を 0.6 倍・S1 0.55・S2 0.85 | +10.1 | −21.8 | −14.5 |
| 回復だけ 0.5 倍 | +23.3 | −22.3 | −1.3 |
| ダメージだけ 0.6 倍・S1 0.45・S2 0.85 | +9.6 | −11.7 | −4.4 |
| **採用: ダメージだけ 0.6 倍・S1 0.50・S2 0.85**（最終の全体計測、中央値 75.3 / 77.5 / 72.0 %） | **86.4 (+11.1)** | **65.7 (−11.9)** | **69.7 (−2.3)** |

参考: スキル1 を実質 0 にすると 55.6 / 37.9 / 41.9 %、三連突きを 0 にすると 16.7 / 5.1 / 5.1 %。Lv1 の強さは公式の三連突き（3 撃で通常攻撃の約 2.8 倍 + 回復）とスキル1 の打ち上げで、
スキルの換算だけでは Lv1 が帯（±15）に入らなかった（スキル1 0.40 でも +17）。回復を削ると Lv6 が崩れる（持続戦の回復）ので、三連突きはダメージだけを換算した。
スキル1 の換算 0.50 は予算の下限 0.8 を一部割る（汎用 S1 の 0.69〜0.85 倍。テストはスキル1 だけ下限 0.65）。スキル2 は 1.22〜1.29 倍で予算の内。
開幕 3 秒の瞬間火力の比（報告のみ）: 1.10 / 0.90 / 0.84。全体の Release（978 テスト）は 0 failures。
