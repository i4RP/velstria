# Zilong (MLBB) - Kit Specification

> 2026-10-14: ヒーローの能力値（HP・物理攻撃・防御・魔防・攻撃速度・HP 回復・マナ・移動速度・射程・リソースの種類）と能力値の式（防御 120/(120+防御)・クリティカル 200%・攻撃速度の加算・移動速度の加算式など）を MLBB の値へ置き換えた（`docs/HERO_STATS.md`）。
> 同日、スキルも **公式の表をそのまま使う（スキル1・2 = 6 段、アルティメット = 3 段）** 形に移した。ランク = 公式の Lv。スロット倍率・物理係数の × 0.6・キットの換算（`flurryScale` など）・ランクの補間はすべて外した（下の「スキルの段階の移行（2026-10-14）」）。
> 2026-10-16（動画で測った値）: 公式の文に無い幾何と時間（スキル1・2 の射程、スキル1 の打ち上げの秒数・持ち上げ・放り投げの時間と着地の距離、
> スキル2 の突進の速さ、三連突きの間隔、奥義の秒数）を MLBB の画面収録で測った（下の「動画で測った値（2026-10-16）」）。変えたのはスキル1 の打ち上げ
> 0.8 → 1.0 秒・放り投げ（命中から 0.4 秒持ち上げてから 0.2 秒で背後 144。以前は命中の瞬間から 0.7 秒で背後 170）とスキル2 の突進 毎秒 2400 → 1520。
> 射程（300 / 450）・三連突きの間隔（4 tick）・奥義の 7.5 秒・+40% は測った値と合っていたのでそのまま。ダメージ・係数・CD・MP は変えていない。

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
- 2026-10-16 の画面収録で測った: 射程 3.0、打ち上げ 1.0 秒（命中から 0.4 秒は持ち上げたまま、0.2 秒で頭上を越えて背後 1.44 に着地）。下の「動画で測った値」。

## Skill 2 - Spear Strike
- Cast type: point-and-click dash/blink onto the target enemy (the dash passes through obstacles as a blink).
- Lunges at the target enemy, dealing 250-450 (+60% total physical attack) physical damage and reducing their physical defense by 15-30 for 2 s. Search-extract descriptions add that he then launches a basic attack on the same target (not stated on the Fandom page; treat as likely but unconfirmed).
- The cooldown resets each time Zilong kills an enemy. The reset also applies if a minion dies within 0.5 s after he damaged it (patch 1.8.08).
- Cooldown 12.0/11.4/10.8/10.2/9.6/9.0 s. Mana 40 at all levels. Base damage 250 to 450 over 6 levels (wiki template is a linear 6-step range, i.e. 250/290/330/370/410/450; per-level row not shown on the page). Physical defense reduction 15/18/21/24/27/30.
- Dash range and speed: unknown.（2026-10-16 の画面収録で測った: 射程 4.5、毎秒 15.2。下の「動画で測った値」）

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

## 日本語クライアントの画面（2026-10-11・無加工の原本）

2026-10-11 に受け取った日本語クライアントのスキル詳細の画面の無加工のスクリーンショット（IMG_4536〜4544。画像はコミットしない）。日本語版の名前は「子龍(Zilong)」、ファイター/アサシン。
**これが一次資料**で、Fandom・Liquipedia より優先する。数値は上の表（Fandom・Liquipedia）とすべて一致し、違いはタグの表記だけ。

| 枠 | 日本語版の名前 | タグ | CD | MP | 内容（原本の文の要約） |
|---|---|---|---|---|---|
| パッシブ | 狂龍乱舞 | バフ・ヒール | – | – | 攻撃エフェクト: 50%。通常攻撃またはスキルで 3 回ダメージを与えた後、次の通常攻撃で狂龍乱舞を発動し対象を 3 回攻撃。各攻撃は 80 (+30% 物理攻撃) の通常攻撃ダメージ、自身の HP を 50 (+20% 物理攻撃) 回復。**通常攻撃は 100 (+80% 物理攻撃) の物理ダメージを与える。** 対象の HP が 50% 未満なら、自身のスキルと通常攻撃が与えるすべてのダメージが 30 増加 |
| スキル1 | 千鈞担槍 | **妨害**・攻撃 | 12.0 / 11.5 / 11.0 / 10.5 / 10.0 / 9.5 | 80 / 85 / 90 / 95 / 100 / 105 | 対象の敵を頭上へ投げ飛ばし、250 / 270 / 290 / 310 / 330 / 350 (+80% 物理攻撃) の物理ダメージ |
| スキル2 | 破陣槍 | ブリンク・デバフ | 12.0 / 11.4 / 10.8 / 10.2 / 9.6 / 9.0 | 40（一定） | 対象の敵に突撃して 250 / 290 / 330 / 370 / 410 / 450 (+60% 物理攻撃) の物理ダメージ、物理防御を 2 秒間 15 / 18 / 21 / 24 / 27 / 30 低下。敵をキルするたびに破陣槍の CD がリセット |
| アルティメット | 武神降臨 | **加速**・バフ | 35 / 31 / 27 | 120 / 140 / 160 | 自身にかかったすべての減速効果を解除し、7.5 秒間 移動速度 +40%、攻撃速度 +35 / 45 / 55%、減速無効。効果中、狂龍乱舞は通常の 3 回ごとではなく 2 回の攻撃ごとに発動 |

タグの対応（2026-10-11 に原本へ合わせた）: パッシブ = `buff` `heal`、スキル1 = **`disrupt` `damage`**（以前は Fandom の CC・ダメージ = `control` `damage`）、スキル2 = `mobility` `debuff`、アルティメット = **`haste` `buff`**（新しいキー `KitTag.haste`。UI の名前「加速」、バフと同じ青系。以前は `mobility` `buff`）。

**通常攻撃「100 (+80% 物理攻撃)」の判断**: 原本・Liquipedia（`Zilong's Basic Attack deals 100 (+80% Total Physical Attack) Physical Damage.`）・Fandom（`{{scale|base=100|total-pa=80|pd}}`）の
3 つが同じ文をパッシブの独立した段落として載せていて、三連突きの 1 撃（80 + 30% の「通常攻撃ダメージ」）とは別の数値・別の文になっている。三連突きでも +30 の説明でもないので、
**子龍の通常攻撃そのものの式**（汎用の「物理攻撃の 100%」を置き換える）と読んだ。sim の汎用の通常攻撃は `stats.attack × 会心倍率`（`CombatSystem.releaseAttack`）なので、
キットの `shapeBasicAttack` が三連突きでない通常攻撃のダメージを `× (100 + 0.8 × 物理攻撃) / 物理攻撃` にする（会心・会心軽減の倍率はそのまま掛かる。HP 50% 未満の +30 はその後に足す。構造物にも同じ式）。
2026-10-14 からは固定値 100 も公式のまま（以前は固定値だけ `basicFlatScale` 0.25 を掛けて 25 (+80%) にしていた）。

## 動画で測った値（2026-10-16）

オーナーが撮った MLBB の訓練場の画面収録（iPhone、横 1108×512・30fps・30.4 秒。Lv15 の子龍、スキルは S1 Lv6・S2 Lv6（的の物理防御が −30）・奥義 Lv3
（CD の表示 27）、的は物理防御・魔法防御 0 の人形（Stake、最大 HP 6100）数体と CPU（Lv4 のヒーロー、最大 HP 3162））から、公式の文に無い幾何と時間を測った。
動画・コマはリポジトリに入れていない（著作物）。道具: `tools/mlbb_video/measure.py`（手順は同じフォルダの README。今回 `panel` を足した）。
コマ n の時刻 = (n − 1) / 30 秒。29 秒から先は iOS のコントロールセンター（使わない）。

| 時刻（コマ） | 出来事 |
|---|---|
| 1.5〜2.3 秒（45〜70） | 止まったままスキル2 の照準（円と的への矢印）。撃たずに歩く |
| 4.27〜4.50 秒（129〜136） | スキル2（1 回目）: 突進して 963。続けて通常攻撃 495・1015（会心） |
| 6.47〜6.73 秒（195〜203） | 三連突き（CPU へ 157 × 3） |
| 7.27〜10.4 秒（219〜312） | 通常攻撃 355・355・388、三連突き（CPU へ。3 発目で CPU が倒れる）、388 |
| 11.6〜11.8 秒（349〜356） | スキル2（2 回目）: 1010。通常攻撃 542、三連突き 300 × 3（物理防御 −30 の間）、542、761（会心） |
| 15.27 秒（459） | スキル1: 672。的を持ち上げ、15.67〜15.87 秒に頭上を越えて背後へ、16.33 秒に打ち上げが解ける |
| 16.1 秒（484〜492） | 三連突き 215・215・405（会心） |
| 17.50〜25.03 秒（526〜751） | 奥義。三連突きが 2 回ごと（4 回）。24.10 秒（724）にスキル2（3 回目、短い突進）: 1010 |
| 25.0〜28.8 秒 | 奥義が解けて、通常攻撃と三連突き（215 × 3） |

### 手順と較正

1. **カメラ**: Tigreal の写像（u0 = 556.6、v0 = 295.0、c = 0.7096、q = 7.6×10⁻⁴ / px）をそのまま使った（同じ端末・同じ訓練場のカメラ）。スキル2 の照準の円は
   角度 236 点（的への矢印の向きを除く）で 278.7 ± 0.7 px と揃い、真上から見た図でも床の円は円に見える。
2. **縮尺**: Tigreal の **s = 62.3 px / 単位**。確かめ: 通常攻撃の射程の円（攻撃中に足元に出る）が **1.78**、三連突きの準備中は **2.48**（公式 1.8 / 2.5 の −1%）。
   床の点だけの歩き（3 回、`speed --floor`）は 1 コマ 5.688 / 5.638 / 5.596 ヒーロー px = 毎秒 2.74 / 2.71 / 2.69（子龍の 265 の +3.4 / +2.3 / +1.6%。
   エンブレムの移動速度と見た。Franco の動画の +5% より小さい）。射程の円が 1% 以内で合うので縮尺は変えていない。
   このほかに、奥義の無いときに歩きが 1.30 倍になる区間が 3 つある（5.9〜6.2 秒・17.1〜17.5 秒・26.5〜26.7 秒。どれも攻撃の直後。エンブレムの天賦と見た）。測定には使っていない。
3. **誤差**: 縮尺 ±2.5%（Tigreal の較正）。時間は ±1 コマ（0.033 秒）。ダメージの数字・CC の表示は通信（60ms の表示）で 1〜2 コマ遅れうる。
4. **状態**: 竜気（パッシブ）は画面に数字で出ないので、命中の並び（通常攻撃とスキルのダメージで +1、三連突きで 0 に戻る。開始は 0 とした）から数え、
   通常攻撃の射程の円（竜気 0〜2 で 1.78、3 で 2.48）と三連突きの出たコマで確かめた（すべて合う）。奥義は自分の体力バーのバッジ（レベルの数字 15 が奥義の絵に
   替わる）、スキル2 の印は的の情報パネルの「物理防御 −30」で見た。下の表は状態ごとに分けて書き、違う状態の値は平均していない。
5. **時刻**: 突進・歩きは床の特徴点（`speed`・`move`）、的の動きは体力バーの位置（`bar`）、ダメージの時刻は的の情報パネルの「総ダメージ」の数字が変わるコマ（`panel`）。
   パネルの数字は、全部のダメージの数字の和と一致した（2473・3959・4969・6953・7714・8386・9221・9609・15665・16675・17217・18117・18659・19047）。

### 測った値（MLBB の単位。Velstria = × 100）

| 項目 | 状態（竜気 / 奥義 / 的の印） | 測った値 | 以前（Velstria） | 実装 |
|---|---|---|---|---|
| 通常攻撃の射程 | 竜気 2 / なし / なし（154〜163・245〜262 コマ） | 足元の円 **1.78**（8 方向） | 180 | そのまま 180 |
| 三連突きの準備中の射程 | 竜気 3 / なし / なし（174〜176・270〜284） | 円 **2.48**（7 方向） | 250 | そのまま 250（`flurryRangeBonus` 70） |
| スキル1 の射程 | 竜気 2 / なし / なし（455〜457、歩きながら） | 照準の円 **2.97**（6 方向） | 300（推測） | そのまま 300 |
| スキル1 の時刻 | 同上 | 照準が消えた次のコマ（459）で命中（672 の表示と的が浮く）。振りかぶりは無い | 即時 | そのまま |
| スキル1 の持ち上げ | 竜気 2 → 3 / なし / なし | 命中から **12 コマ（0.40 秒）**、的の体力バーがその場（浮いた高さ）で止まる。子龍も動かない | 0（命中の瞬間に投げる） | `flipHold` 0.4 |
| スキル1 の放り投げ | 同上 | **6 コマ（0.20 秒）**で頭上を越え、子龍の中心から **1.43〜1.44** の背後に着地（投げる前は前方 2.07〜2.23・向き 50〜56°、着地は −148〜−151°） | 0.7 秒で背後 170 | `flipFlight` 0.2、`flipLandingGap` 144 |
| スキル1 の打ち上げ | 同上 | 的の「ノックアップ」の表示と時間のバーが 459〜489 コマ（**31 コマ = 1.03 秒**）。バーの縮む速さ（2.9 px / コマ）からも満タンで 1.0〜1.07 秒 | 0.8 秒（推測） | `flipAirborne` 1.0（着地の後 0.4 秒は打ち上げのまま） |
| スキル2 の射程 | 竜気 0 / なし / なし（52〜68、止まって）・竜気 0 / 奥義中 / なし（719〜721） | 照準の円 **4.47**（236 点）・**4.46〜4.47**（7 方向）。奥義でも変わらない | 450（推測） | そのまま 450 |
| スキル2 の突進 | 竜気 0 / なし / なし・竜気 1 / なし / なし | 床の 1 コマの変位 **31.7 px = 毎秒 15.2**。3.40 を 6.7 コマ、3.66 を 7.25 コマ（速さは距離によらない）。3 回目（竜気 0 / 奥義中）は 0.7 ほどの短い突進 | 2400（推測） | `strikeSpeed` 1520 |
| スキル2 の開始 | 2・3 回目 | 照準が消えてから 2 コマで動き出す（通信の遅れ程度。振りかぶりは無い） | 即時 | そのまま |
| スキル2 の止まる位置 | 1 回目 | 的の中心から 0.95〜1.08 | 縁 + 5（中心間 115） | そのまま（差 0.1〜0.2 は足元の見当の誤差の内） |
| スキル2 のダメージ | 2・3 回目 | 突進の終わりのコマ（356・724）にパネルの総ダメージ +1010 と「物理防御 −30」が同時に出る | 到着の tick | そのまま |
| スキル2 の後の通常攻撃 | 3 回 | 到着から 9〜12 コマ（0.30〜0.40 秒）で次の通常攻撃が当たる | 到着で攻撃の間隔を 0 に（当たるのは攻撃の振りかぶりの後） | そのまま（記録だけ） |
| 物理防御ダウンの秒数 | 2・3 回目 | 「−30」が 356〜419・724〜787 コマ（**64 コマ = 2.1 秒**） | 2.0（公式） | そのまま（公式の 2 秒） |
| 三連突きの間隔 | 竜気 3 / なし（5 回。うち CPU 2 回・印あり 1 回）・竜気 2 / 奥義中 / なし（3 回）・奥義の終わりにまたがる / 印あり（1 回） | パネルの総ダメージ（CPU は体力の表示）が **1 発目から 4 / 8 コマ**（0.133 / 0.267 秒）で変わる。9 回すべて同じで、奥義の攻撃速度でも縮まない（ダメージの数字の出始めは 2・3 発目が 1 コマ遅れて見える） | 4 / 8 tick（0.14 / 0.28 秒の予約） | そのまま |
| 三連突きの回数 | 全部 | 3 発 | 3 | そのまま |
| 奥義の秒数 | 竜気 1 で発動 | 体力バーのバッジが奥義の絵の間 526〜751 コマ（**226 コマ = 7.53 秒**） | 7.5（公式） | そのまま |
| 奥義の移動速度 | 奥義中（天賦の 1.30 倍の無い区間） | 歩き 毎秒 4.05 ÷ 奥義の無い歩き 2.89（同じ方法 = 全部の特徴点）= **1.40 倍** | +40%（公式） | そのまま |
| 奥義中の三連突き | 竜気 1 で発動、奥義中 | 2 回のダメージごとに出る（550 で 2 つ → 566 に三連突き。以後 583・599 → 614、629・647 → 663、678・694 → 710、スキル2 の 724・通常攻撃 734 → 750。スキル2 も 1 回に数える） | 2 | そのまま |
| 攻撃の間隔 | 奥義なし / 奥義中（Lv3 +55%） | 24 コマ（0.80 秒。7 回のうち 5 回、ほかは 21・22）/ 16 コマ前後（14〜18、10 回）。三連突きは攻撃 1 回 | 公式の攻撃速度 1.33（0.75 秒）、+55%（0.48 秒） | 変えない（攻撃速度は公式の値。0.75 → 0.80、0.48 → 0.53 は 1/15 秒単位への切り上げと合う。推測） |
| 奥義のスロウ無効 | — | 動画にスロウが無く、確かめられない | 毎 tick 解除 | そのまま |

### ダメージの表示（観察のみ。キットのダメージ・係数・会心・防御の式は変えていない）

的は物理防御 0（パネルの表示）。「印」= スキル2 の物理防御 −30 が付いている間。数字は 1 撃の値（パネルの総ダメージの差で検算した）。

| 出来事 | 的の HP / 印 | 数字 |
|---|---|---|
| 通常攻撃 | 50% 以上 / なし | **355**（2 回） |
| 通常攻撃 | 50% 未満 / なし | **388**（多数） |
| 通常攻撃 | 50% 以上 / あり | **495** |
| 通常攻撃 | 50% 未満 / あり | **542**（4 回） |
| 通常攻撃・会心（橙の印） | 50% 以上 / あり | **1015** |
| 通常攻撃・会心 | 50% 未満 / なし | **761** |
| 三連突き 1 撃 | 50% 未満 / なし | **215**（多数） |
| 三連突き 1 撃・会心 | 50% 未満 / なし | **405**（4 回） |
| 三連突き 1 撃 | 50% 未満 / あり | **300**（6 回） |
| 三連突き 1 撃（CPU Lv4。防御は不明） | 50% 未満 | **157** |
| スキル2 Lv6（命中の前は印なし） | 50% 以上 / 59% | **963** |
| スキル2 Lv6（命中の前は印なし） | 50% 未満 | **1010**（2 回） |
| スキル1 Lv6 | 50% 未満 / なし | **672** |

- **印の倍率は ×1.396**（495 / 355 = 1.394、542 / 388 = 1.397、300 / 215 = 1.395）。sim の防御の式 120 / (120 + 防御) では物理防御 −30 で ×1.333。**合わない**（報告のみ）。
- **HP 50% 未満の +30 が +33 に見える**（355 → 388）。すべてのダメージに ×1.10 前後が掛かっている（出どころは不明。エンブレムか訓練場の設定）。
- ×1.10 として式から物理攻撃 A を戻すと、通常攻撃（100 + 0.8A）で 278、三連突き（80 + 0.3A + 30）で 285、スキル1（350 + 0.8A + 30）で 289、
  スキル2（450 + 0.6A、印の ×1.396 も掛ける）で 295〜296。Lv15 の物理攻撃 249（公式）より 30〜47 大きく、式どうしでも ±3% ずれる。ステータス画面が無いので決め切れない。
- **スキル2 の一撃に、自分の物理防御ダウンが掛かっている**。印の ×1.396 を掛けないと 963 は A ≈ 710 になり（ありえない）、パネルの「−30」もダメージと同じコマに出る。
  MLBB は防御ダウンを先に付けてから当てている。sim は一撃の後に付ける（この一撃には掛からない）。**合わない**（ダメージに関わるので変えていない）。
- 会心（橙の印の数字）は ×2.05（1015 / 495、(761 − 33) / 355、(405 − 33) / (215 − 33)）で、+30（×1.1）は会心の後に足されている（sim と同じ順）。倍率は sim の 200% と 5% 違う（エンブレムか）。
- スキル2 の 963 → 1010 の差 47 = 30 × 1.1 × 1.396。+30 は防御の前に足されている（sim と同じ）。

### 単位の扱い

Tigreal・Franco と同じ: Velstria の距離は MLBB × 100（通常攻撃の射程 1.8 → 180）。**スキルの幾何も MLBB × 100 のまま入れる**（`Balance.mapScale` は掛けない）。
突進の速さは測った距離 ÷ 測った時間（毎秒 15.2 → 1520）。時間は MLBB と同じ。

### 測れなかった・推測のまま

- 奥義中の射程の円（竜気 1 / 2）と、奥義中に竜気 2 で射程が伸びるか（sim は伸ばす）。スロウ無効（動画にスロウが無い）。
- スキル2 を射程の端（4.5）・壁越しに撃ったとき。突進の止まる位置（動画 1.0、sim 1.15）。
- スキル1 の着地の距離が投げる前の距離で変わるか（1 回だけ。sim は術者の背後 144 で一定）、着地の向きが真後ろから 20〜25° ずれた理由（的は歩いていた）。
- 持ち上げの間に子龍がスタンされたとき（sim は投げる）・的が浄化したとき（sim は投げない）。動画には無い。
- 縮尺の 2.5%（上の「縮尺」）、ダメージの ×1.10・印の ×1.396・会心の ×2.05 の出どころ（上の「ダメージの表示」）。

### もっと良く測るには

- 試合中のステータス画面（物理攻撃・会心ダメージ・移動速度・攻撃速度）を撮る。エンブレムを外して撮る（×1.10・会心 205%・歩きの +2.5% と 1.30 倍の区間が決まる）。
- スキル2 を射程の端の的と近い的へ 1 回ずつ。スキル1 を距離 1 と 3 の的へ 1 回ずつ（着地の距離）、壁際で 1 回。
- 奥義中に床をまっすぐ歩く・竜気 1 / 2 で殴る（射程の円）・スロウを受ける。
- 60fps の画面収録（時間の誤差が半分）。

### 動画の値に変えた後のバランス（2026-10-16、sim 30、Windows の Release）

`KitBalanceTests` のデュエリストの中央値との差 +15.4 / +23.0 / +21.6 → **+15.4 / +24.0 / +23.6**（Lv1 / 6 / 12。帯 35 の中）、ゲームに出す 10 体の総当たり
77.8 / 85.2 / 72.2 → 77.8 / 88.9 / 79.6%、開幕 3 秒のダメージ 645 / 1430 / 1571 → 645 / 1430 / 1578、ロール代表との TTK 7.3〜13.3 → 6.7〜14.1 秒（18 / 18 勝のまま）。
打ち上げが 0.8 → 1.0 秒に延び、投げた相手が 0.6 秒で背後に落ちる（以前は 0.7 秒）ぶん少し上がった。突進は遅くなった（最長 0.2 → 0.3 秒）が勝率にはほとんど効かない。
`Kit_H029Tests` のボットの煙テスト（シード 31 の試合に子龍が居る）は S2 の再使用が 0 回になったので、シードを 32 にした（29〜40 のうち 0 回は 31 だけ）。

## Velstria 実装対応表

H027 竜槍のジャルド（デュエリスト・近接 180・Mana）= Velstria 版の Zilong。実装: `Packages/VelstriaCore/Sources/VelstriaCore/Systems/Kits/Kit_H027.swift`、
テスト: `Tests/VelstriaCoreTests/Kits/Kit_H027Tests.swift`、演出: `App/Battle/SkillFX/Heroes/FX_H027.swift`。
スロットは上の調査の順に割り当てる（Skill1 = Spear Flip、Skill2 = Spear Strike、Ultimate = Supreme Warrior、Passive = Dragon Flurry）。
マスターデータ上の最終名は パッシブ「竜の三連突き」/ スキル1「跳槍撃」/ スキル2「竜牙突き」/ アルティメット「至高の武人」（`tools/rename_kit_skills.mjs`）。説明文は UI の用語（スキル1・スキル2・アルティメット）で書く。
距離は Velstria 単位（= MLBB × 100）。

**数値は公式の表をそのまま使う（スキル1・2 = 6 段、アルティメット = 3 段）。** ランク r = 公式の Lv r。ダメージ = 公式の基礎[Lv] + 公式の係数 × 合計の物理攻撃（`Kit.official(…, .totalAttack, …)`）、
CD = 公式の秒数[Lv] × (1 − CD 短縮)（`Kit.cooldown`）、マナ = 公式の MP[Lv]（`HeroKits.resourceCost`。Mana のヒーローなのでそのまま）。説明文の `{base}(+{atkPct}%物理攻撃)` は公式の値そのもの。

| 項目 | Lv1 | Lv2 | Lv3 | Lv4 | Lv5 | Lv6 | 係数 |
|---|---|---|---|---|---|---|---|
| スキル1 ダメージ | 250 | 270 | 290 | 310 | 330 | 350 | +80% 物理攻撃 |
| スキル1 CD（秒） | 12.0 | 11.5 | 11.0 | 10.5 | 10.0 | 9.5 | |
| スキル1 MP | 80 | 85 | 90 | 95 | 100 | 105 | |
| スキル2 ダメージ | 250 | 290 | 330 | 370 | 410 | 450 | +60% 物理攻撃 |
| スキル2 物理防御ダウン（固定値・2 秒） | 15 | 18 | 21 | 24 | 27 | 30 | |
| スキル2 CD（秒） | 12.0 | 11.4 | 10.8 | 10.2 | 9.6 | 9.0 | |
| スキル2 MP | 40 | 40 | 40 | 40 | 40 | 40 | |

| 項目 | Lv1 | Lv2 | Lv3 |
|---|---|---|---|
| アルティメット CD（秒） | 35 | 31 | 27 |
| アルティメット MP | 120 | 140 | 160 |
| 攻撃速度 | +35% | +45% | +55% |
| 移動速度 / 秒数 | +40% / 7.5 秒 | 同じ | 同じ |

| パッシブ・通常攻撃 | 値 |
|---|---|
| 通常攻撃（三連突きでないとき） | 100 (+80% 物理攻撃)。会心倍率はそのまま掛かる |
| 三連突き 1 撃 × 3 | 80 (+30% 物理攻撃) の通常攻撃ダメージ、命中ごとに 50 (+20% 物理攻撃) 回復、**攻撃エフェクト 50%** |
| 竜気 | 3 回（奥義中は 2 回）のダメージで満タン |
| HP 50% 未満の相手 | 通常攻撃・スキルのダメージ +30（固定値、防御の前） |

### 対応表（○ = 実装、△ = 簡略化、× = 見送り）

| 元の仕様 | 状態 | Velstria での実装・理由 |
|---|---|---|
| 通常攻撃: 近接単体、射程 1.8（Dragon Flurry 準備中は 2.5） | ○ | 射程 180（MLBB 1.8 × 100）。竜気が満タンの間だけ `attackRangeBoost` +70（180 → 250 = MLBB の 2.5。2026-10-14 までは 150 → 208 の比の +58）。撃つと即座に外す |
| 通常攻撃「100 (+80% 物理攻撃)」 | ○ | 三連突きでない通常攻撃を `100 + 0.8 × 物理攻撃` にする（`shapeBasicAttack`。会心倍率はそのまま、HP 50% 未満の +30 はその後） |
| パッシブ: ダメージを 3 回与えると次の通常攻撃が三連撃（スキルも数える） | ○ | 竜気（`ints[0]`）。三連突きでない通常攻撃の命中とスキルの「ダメージ > 0 の命中」で +1（CC のみの命中・奥義は数えない）。3 で満タン。死亡で 0 |
| 三連撃: 1 撃 80 + 物理攻撃 30%、命中ごとに 50 + 物理攻撃 20% 回復 | ○ | 公式の値そのまま（2026-10-14 までダメージに換算 `flurryScale` 0.6）。`shapeBasicAttack` で 1 発目（通常攻撃と同じ tick）に整形し、2・3 発目は `Kit.schedule`（`onTimer`）で **4 / 8 tick 後（約 0.13 / 0.27 秒）**（予約は 0.14 / 0.28 秒。MLBB の画面収録の 4 / 8 コマと同じ）。各発に `HitEffect.healOwner`。会心は 3 発で 1 回の判定を共有（倍率は通常攻撃と同じ `CombatSystem.critMultiplier`: 対象の会心ダメージ軽減を引く） |
| 三連撃の「攻撃エフェクト: 50%」 | ○（2026-10-14） | 3 発とも `HitPayload.attackEffect = 0.5`・`appliesOnHit = false`: 装備の命中時効果（追加ダメージ・回復・減速）と通常攻撃吸収が 50%（`ItemEffects.onPartialAttackEffect`）。命中数（`basicAttackCount`）・通常攻撃の命中フック（`onBasicAttackHit`）・CD 型の装備効果には数えない。竜気にもならない（以前の `ints[1]` の「命中で竜気にしない」印は要らなくなった）。S2 リセットの窓は `kitEvent` → `onHit` で開く |
| 三連撃の回復（ヒーロー以外） | ○（2026-10-14） | 公式の文どおり、相手によらず 50 (+20%)。以前の「ミニオン・モンスター・タワーが相手なら半分」（`flurryHealNonHero` 0.5。MLBB の文に無い）は外した |
| 三連撃の間隔（アニメーション上の連続） | ○（2026-10-16 に動画で確かめた） | 3 発は別の tick に当たる。間隔 0.133 秒（4 tick）は MLBB の画面収録の 4 コマおき（9 回すべて。奥義の攻撃速度でも縮まない）と同じで、被弾演出の間引き（Effekseer の近接ヒットは同じ相手へ 0.12 秒に 1 回）にも潰されない（0.13 だと 3 tick = 0.1 秒おきになってしまう）。遅れて当たる発は、対象が倒れた・射程（三連突きの伸びを含む + 30）の外へ出た・対象不可なら出ない。スタン以上の CC で残りは取り消される（interruptible）。**HP 50% 未満の +30 は、1 発ごとに当たる瞬間の対象で決める** |
| 旧版（1.8.08）の 30 + 40% / 30 + 20% | × | 現行（80 + 30% / 50 + 20%）を採用（調査の指示どおり） |
| HP 50% 未満の相手へ通常攻撃・スキルのダメージ +30（固定） | ○ | 固定値を `HitPayload.damage` に足す（発動・攻撃開始の時点の HP で判定。三連撃は 1 発ごとに当たる瞬間の HP で判定）。`outgoingDamageBonus` は割合しか返せないので使わない。構造物には付かない。防御の前に足すか後に足すかは資料が無い（前に足している） |
| S1 Spear Flip（跳槍撃）: 対象指定、敵を頭上へ跳ね上げ背後へ飛ばす、打ち上げ | ○ | 射程 300（対象の縁まで。動画の照準の円 2.97）。ダメージと同時に `knockUp` 1.0 秒。命中から 0.4 秒（`flipHold`）は持ち上げたまま動かさず、そこから `MovementSystem.knockback` で術者の頭上を越えて背後 144 に 0.2 秒（`flipFlight`）で着地（2026-10-16 に動画で測った値。以前の推測は命中の瞬間から 0.7 秒で背後 170、打ち上げ 0.8 秒）。投げるのは対象に入った打ち上げの続きなので、持ち上げの間に術者がスタンされても投げる（予約は中断されない。打ち上げが先に解けた・術者が倒れた・CC 無効になったら投げない）。打ち上げ = ノックアップ（高レベル: 受けた側の突進・跳躍も止める）。CC 無効の相手はダメージのみ（動かさない）。照準は `requiresTarget`（居なければコスト・CD を消費せず失敗）。ヒーロー優先 → HP + シールド最小、指定ユニット・地点・向きも対応。術者は動かないのでバインド中も撃てる |
| S1 ダメージ・CD・MP | ○ | 公式の表（250〜350 (+80% 物理攻撃)、CD 12.0〜9.5、MP 80〜105）そのまま |
| S2 Spear Strike（竜牙突き）: 対象指定の突進（障害物を越えるブリンク） | △ | `.targetedBlink` + `requiresTarget`、`Kit.dashSweeping`（経路上の敵には当てない carrier）で突進。速度 1520、射程 450（2026-10-16 に動画で測った値: 毎秒 15.2、照準の円 4.47。以前の推測は 2400）。壁は越えられず手前で止まる（`MovementSystem.dash` の仕様）。突進はノックアップ・制圧で取り消される（スタンでは止まらない: 共通の CC の段階）。バインド中は撃てない（ブリンク） |
| S2 ダメージ・CD・MP | ○ | 公式の表（250〜450 (+60% 物理攻撃)、CD 12.0〜9.0、MP 40）そのまま。到着した tick に 1 度だけ。対象が突進中に倒れる・260 以上離れる・対象不可になると外れる（追尾はしない） |
| S2 物理防御 −15〜−30（2 秒） | ○ | 物理防御だけの固定値の `flatArmorMod`（負の値、公式の表 15 / 18 / 21 / 24 / 27 / 30。魔法防御は変えない）。以前は到着時の防御に対する割合の `armorShred` に換算していた。ダメージの後に付くので、その一撃には掛からない |
| S2 のあとに通常攻撃（調査では未確認） | ○ | 到着後に `attackTargetID` を対象にして攻撃間隔を 0 に（そのまま殴る） |
| S2 は敵を倒すたびにクールダウンリセット | ○（2026-10-14 に整理） | ヒーロー: 止めを刺したとき（`onKillOrAssist`、`lastAttackerID` が自分。アシストでは戻らない）。ミニオン・モンスター・人形: 直前に傷つけた敵（通常攻撃・三連突き・スキル）が 0.5 秒以内（`timers[1]`）に倒れたら（1.8.08 の更新の「ダメージの 0.5 秒以内に倒れたミニオン」。非ヒーローの撃破のフックが無いので、自分の止めもこれで拾う）。以前は窓がヒーローにも掛かっていて、0.5 秒以内に味方が倒したヒーロー（アシスト）でも戻っていた。練習場の `noCooldowns` を尊重（`Kit.setCooldown`） |
| 奥義 Supreme Warrior（至高の武人）: スロウ解除、移動速度 +40%、攻撃速度 +35/45/55%、スロウ無効、7.5 秒 | ○ | 発動で `slow` を全部外し、`speedBoost` 0.40 と `attackSpeedBoost`（公式の表）を 7.5 秒。スロウ無効は専用の status が無いため、`update` で毎 tick `slow` を取り除く（掛かった同じ tick のうちに消える。他の CC は防がない） |
| 奥義中は 2 回で Dragon Flurry | ○ | 奥義の残り（`timers[0]`）> 0 の間、竜気の必要数 3 → 2 |
| 奥義 CD・MP | ○ | 公式の表（CD 35 / 31 / 27、MP 120 / 140 / 160）そのまま |
| 奥義にダメージ・CC は無い | ○ | ダメージ 0（自己強化のみ。代わりにパッシブと攻撃速度の強化が火力になる） |
| ボット: アルティメット | ○ | 交戦中の敵ヒーローに踏み込みの射程（450 + 半径）で届くなら `.castNow(.none)`（汎用の関門 = 倒せる・2 体以上 を待たない。自己強化なので殴り合いの頭に撃つ）。強化中は撃たない。ミニオン・遠い敵は従来どおり（関門を通ったとき） |
| ボット: ファーム | ○ | `botFarm` で竜牙突き（スキル2）だけミニオン・ジャングルにも使う（倒すたびにリセットされるので周回が速くなる）。HP が半分以上で、集団の位置が敵のタワー・コアの射程（750 + 半径 + 120）に入らないときだけ。跳槍撃（スキル1）は従来どおりの経路 |
| チームパッシブ「The Oriental Fighters」（東洋の戦士が居ると移動速度 +1/2/3） | × | 調査でも低優先。チーム構成のシナジー層が無い。日本語クライアントの現行の文にも無い |
| 再使用（recast） | – | Zilong には無いので使わない（HUD の `recastable` は false、窓は開かない） |

### 推測の値（公式の文に無い幾何・時間。MLBB と違う可能性がある）

2026-10-16 に動画で測って置き換えたもの（上の「動画で測った値」）: スキル1 の射程（300 のまま）・打ち上げ（0.8 → 1.0 秒）と放り投げ（命中の瞬間から 0.7 秒で背後 170 → 0.4 秒持ち上げてから 0.2 秒で背後 144）、
スキル2 の射程（450 のまま）・突進の速さ（2400 → 1520）、三連突きの間隔（4 / 8 tick のまま）。

| 項目 | 値 | 理由 |
|---|---|---|
| 遅れて当たる発の余裕・突進の外れ | +30 / 260 | 相手が少し動いても外れない程度 |
| スキル1 の着地の距離 | 術者の背後 144 で一定 | 動画は 1 回だけ（投げる前の距離 2.1〜2.2）。距離で変わるかは未確認 |
| 説明文の数値 | パッシブ `{attackEffect}` `{charge}` `{hits}` `{flurryFlat}` `{flurryPct}` `{healFlat}` `{healPct}` `{basicFlat}` `{basicPct}`（公式の値）と `{flurryDamage}` `{flurryHeal}` `{basicDamage}`（今の物理攻撃での値）、`{executeFlat}` / スキル1・2 `{base}` `{atkPct}`（公式の値）と `{damage}` / アルティメット `{moveSpeed}` `{attackSpeed}` `{duration}` `{charge}` | `KitText` のトークンに sim の数値を入れる。文は公式の構造（段落・語順。パッシブの先頭の「攻撃エフェクト: 50%」）に合わせた |

### スキルの段階の移行（2026-10-14）

公式の表をそのまま使う形に移した（共通の土台: 6 / 6 / 3 段、`Kit.level` / `Kit.official` / `Kit.cooldown`、`HitPayload.attackEffect`、ミニオンへのスキルダメージ × 0.2 の撤廃、バインド、CC の段階）。

| 外したもの | 旧値 | 今 |
|---|---|---|
| ランクの補間（`lerp`。4 ランク → Lv 1 / 2.67 / 4.33 / 6） | `(Lv1, Lv6)` のタプル | 公式の 6 段 / 3 段の表を `Kit.level` で引く |
| スロット倍率（`Balance.Skills.damageScale`）・物理係数の × 0.6（`Balance.skillAttackScalingFactor`）・`cooldownScale` | S1 × 4.0、S2 × 3.0、係数 × 0.6 | なし |
| `Tune.flipScale` / `strikeScale` | 0.50 / 0.85（S1 の Lv1 = 基礎 500 (+96%)、S2 = 638 (+92%)） | なし（250 (+80%) / 250 (+60%)） |
| `Tune.flurryScale` | 0.6（三連突き 1 撃 48 (+18%)） | なし（80 (+30%)） |
| `Tune.basicFlatScale` | 0.25（通常攻撃 25 (+80%)） | なし（100 (+80%)） |
| `Tune.flurryHealNonHero` | ヒーロー以外への回復 × 0.5 | なし（相手によらず 50 (+20%)） |
| S2 の防御ダウンの割合への換算（`armorShred` = 固定値 / 到着時の防御、上限 0.9） | 割合 | 物理防御だけの固定値の `flatArmorMod` |
| S2 リセットの 0.5 秒の窓（ヒーローにも） | 全ての非構造物 | ミニオン・モンスター・人形だけ（ヒーローはキルのとき） |
| 三連突きの「命中で竜気にしない」印（`ints[1]`） | 命中フックで 1 つ消費 | 不要（攻撃エフェクトの割合の命中は命中フックを通らない） |
| 三連突き中の射程の伸び | +58（150 → 208 の比） | +70（MLBB の 1.8 → 2.5） |

入れた割合: 三連突きの攻撃エフェクト 50%（日本語クライアントの「攻撃エフェクト: 50%」）。スキル吸収率・ミニオン / モンスターへの補正は公式の文に無いので既定（100%）のまま。

1v1・総当たりの勝率の帯（`KitBalanceTests`・`testDuelTimeToKillStaysInBandAgainstTheRoleRepresentatives`）は全キットを移した後に測り直す（換算を探した以前の計測の表は外した。値は git の履歴）。

### 既知の差・リスク

- 同じ相手に効いている間に S2 をもう一度当てると、`addStatus` の「大きい方を残す」で弱い方（負の値の大きい方 = 下げ幅の小さい方）が残る（ランクが上がった直後だけ起きる）。
- 「HP 50% 未満で +30」を防御の前に足すか後に足すかは資料が無い（前に足している）。2026-10-16 の画面収録では、+30 は会心の後・印（物理防御 −30）の倍率の前に足されていて、前に足すのと合う。
- **スキル2 の一撃に自分の物理防御ダウンが掛かるか**: 画面収録（2026-10-16）では掛かっている（MLBB は防御ダウンを先に付ける。上の「動画で測った値」の「ダメージの表示」）。sim は一撃の後に付ける（この一撃には掛からない）。ダメージに関わるので変えていない。
- 物理防御 −30 の的への倍率: 画面収録は ×1.396、sim の 120 / (120 + 防御) は ×1.333。ダメージの式なので変えていない。
- スキル2 の後の通常攻撃: sim は到着で攻撃の間隔を 0 にして、攻撃の振りかぶり（Lv15 で約 0.19 秒）の後に当たる。画面収録は到着から 0.30〜0.40 秒。
- 三連撃の 2・3 発目は 約 0.13 / 0.27 秒後に、当たる瞬間の対象で +30 を決める。そのかわり、1 発目のあとの 0.27 秒の間に対象が射程の外へ出る・倒れる・対象不可になると残りは出ない（回復も出ない）。
- スロウ無効は status ではなく毎 tick の除去。奥義中に SpellSystem など `SkillSystem.update` より後で掛かったスロウは 1 tick だけ移動速度に効く。
- 「S2 の突進で壁を越える」は未対応。壁際ではブリンクにならず手前で止まり、`strikeSlack` を超えると外れる。
- S2 リセットの 0.5 秒の窓はミニオン以外（モンスター・人形）にも掛かる（非ヒーローの撃破のフックが無いので、自分の止めもこの窓で拾っている）。モンスターを傷つけた直後に味方が倒しても戻る。
