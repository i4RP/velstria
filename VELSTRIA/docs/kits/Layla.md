# Layla (MLBB) - Kit Specification

> 2026-10-14: ヒーローの能力値（HP・物理攻撃・防御・魔防・攻撃速度・HP 回復・マナ・移動速度・射程・リソースの種類）と能力値の式（防御 120/(120+防御)・クリティカル 200%・攻撃速度の加算・移動速度の加算式など）を MLBB の値へ置き換えた（`docs/HERO_STATS.md`。ライラの通常攻撃範囲は 4.3 = 430）。
> 同日、スキルも**公式の表をそのまま使う（6 / 6 / 3 段）**ようにした: スロット倍率・物理係数の × 0.6・キットの換算（`s1Scale` ほか）・ランクの線形補間を外し、ダメージは 公式の基礎[Lv] + 係数 × 合計の物理攻撃（下の「Velstria 実装対応表」）。

Primary source: Mobile Legends Fandom hero page (fetched via the MediaWiki API, page edited 2026-09-30; kit is the post-"third revamp" version from Project NEXT 2023). Cross-checked against Fandom patch history and web-search extracts of the same wiki (no independent second source with numbers was available; liquipedia and gameboost pages were blocked or 404). "unknown" = not found. Ranges are in wiki "units".

## Hero overview
- Role / lane: Marksman (Finisher/Damage), Gold Lane. Ranged, mana resource, physical damage. Ratings: durability 1, offense 8, control 1, difficulty 2.
- Basic attack: ranged single target, base attack range 4.3 (the longest in the game once upgraded: up to 7.1 with Destruction Rush level 3 plus the Malefic Bomb buff; the wiki also lists 6.785/7.245/7.705/8.165, exactly x1.15 of 5.9/6.3/6.7/7.1, for a "Malefic Gun equipped" variant whose meaning is unclear). Projectile speed: unknown.
- Level 1 stats: HP 2250, HP regen 5.4, mana 500, mana regen 4, physical attack 133, physical defense 15 (11.1% reduction), magic defense 15 (11.1%), attack speed 1.06, movement speed 240, crit damage 200%.
- Level 15 stats: HP 4378, regen 8.2, mana 1900, physical attack 252, physical defense 71, magic defense 50, attack speed 1.34.
- Growth per level: HP +152, regen +0.2, mana +100, mana regen +0.2, physical attack +8.5, physical defense +4, magic defense +2.5, attack speed +0.02.
- Max skill levels: S1 6, S2 6, Ultimate 3.

## Passive - Malefic Gun
- Cast type: passive damage modifier.
- Layla deals increased damage to enemies farther from her, from 100% (point blank) up to 130% at 6 units. Formula: total damage = initial damage x [100% + 5% x distance the projectile traveled]. Does not apply to turrets. Applies to basic attacks and skills (an old patch note: skills were added in 1.1.42).
- The cap of 130% means damage stops growing at 6 units distance.

## Skill 1 - Malefic Bomb
- Cast type: skillshot line, fired in the aimed direction, hits the first enemy.
- Deals 200-400 (+80% total physical attack) physical damage to the first enemy hit; it can critically strike.
- On hit: Layla's basic attacks and Void Projectile gain extra range for 3 s (+1.6 / 1.4 / 1.2 / 1.0 units at Destruction Rush level 0/1/2/3), and she gains 60% movement speed that decays over 1.2 s. The movement speed duration doubles if an enemy hero is hit.
- Cooldown 6.0/5.6/5.2/4.8/4.4/4.0 s. Mana 40/45/50/55/60/65. Base damage 200/240/280/320/360/400.
- Range/width: unknown (patch notes: bullet radius 0.35 at 1.1.96, range "slightly increased"). Bomb projectile speed: unknown.
- Total basic attack and Void Projectile range while buffed: 4.3 + 0.6 x (ult level) + [1.6 - 0.2 x (ult level)] = 5.9/6.3/6.7/7.1.

## Skill 2 - Void Projectile
- Cast type: skillshot (orb projectile) that explodes on hit; ground area explosion.
- Deals 170-320 (+65% total physical attack) physical damage to targets in the area and applies a Magic Mark to them for 3 s.
- When Layla hits an enemy that has a Magic Mark (which of her attacks/skills trigger it, and whether the mark is consumed: unknown), she deals 100-200 (+35% total physical attack) physical damage to nearby enemies and stuns them for 0.25 s.
- Cooldown 7.5/7.3/7.1/6.9/6.7/6.5 s. Mana 65/70/75/80/85/90. Base damage 170/200/230/260/290/320; extra damage 100/120/140/160/180/200.
- Range grows with the ultimate level (passive of Destruction Rush) and with the Malefic Bomb buff; base range and blast radius: unknown. The wiki tags the skill "AOE / Slow" but the description contains no slow value (older patch notes had a 55-60% slow before the rework), so treat slow as unknown/likely removed.

## Ultimate - Destruction Rush
- Cast type: skillshot line (long beam), fired in the aimed direction.
- Deals 500-800 (+150% total physical attack) physical damage to all enemies in the line. Wiki note: actual range is slightly wider than the indicator (verification needed).
- Passive upgrade: each ultimate level adds +0.6/1.2/1.8 range to basic attacks and Void Projectile, and slightly increases her sight range.
- Cooldown 37/32/27 s. Mana 130/150/170. Base damage 500/650/800.
- Beam range and width: unknown. Cast time: unknown.

## Gameplay identity
- Stationary glass-cannon sniper: survives by outranging, hence the extra range from Malefic Bomb and the ultimate passive.
- Distance rewards damage (up to +30%), so she wants to hit from the edge of her range.
- Void Projectile is the burst opener: mark, then basic attack to trigger the 0.25 s stun and bonus damage.
- Malefic Bomb is a crit-capable poke and a mini speed boost to reposition; the ultimate is a long-range line finisher/siege tool (attacks turrets from outside their range).

## Simulation notes
- Standard: ranged basic attack, line skillshot (first-hit), line piercing skill, circle explosion projectile, short stun, timed movement-speed buff with decay.
- Needs special state: distance-based damage multiplier (compute from projectile traveled distance, cap 6 units); skill-level-dependent attack range formula with a 3 s temporary range bonus; Magic Mark (3 s debuff on target; consume rules unknown) that triggers a delayed AoE stun; skills able to crit; movement speed bonus that linearly decays over 1.2 s and doubles in duration on hero hit; sight range scaling with ult level.

## Sources
- https://mobile-legends.fandom.com/wiki/Layla
- https://mobile-legends.fandom.com/wiki/Layla/Patch_history
- https://mobile-legends.fandom.com/wiki/Layla/Guide (search extract only)

## 公式（日本語クライアント）の数値

ライラ(Layla)、ロール「ハンター」、サブタグ「追撃/ダメージ」。2026-10-10 に受け取った日本語クライアントの実機のスクリーンショット（スキル詳細の画面）の転記（スキルのレベルは S1・S2 が Lv1〜6、
アルティメットが Lv1〜3）。**下の Fandom の値と違うところはこちらを正とする**（違い: パッシブの最大 130% → 115%、S1 の MP、S2 の MP とタグ、S2 に減速の記載が無い）。
アイコンのタグは バフ / 爆発力 / 範囲技 / 爆発力。

| スロット | 公式名 | タグ | 内容 |
|---|---|---|---|
| パッシブ | マジックガン | バフ | 距離が遠い対象ほど、与ダメージが増加する（最小100%、6離れると最大115%まで増加する）。タワーには適用されない。 |
| スキル1 | マジックボム | 爆発力・バフ | CD 6.0 / 5.6 / 5.2 / 4.8 / 4.4 / 4.0、MP 35 / 40 / 45 / 50 / 55 / 60、基礎ダメージ 200 / 240 / 280 / 320 / 360 / 400。指定方向にマジックボムを放ち、最初に命中した敵に200(+80%物理攻撃)の物理ダメージを与える（クリティカル可能）。敵に命中すると、通常攻撃とボイドショットの射程が3秒間伸びる。さらに移動速度が追加で60%上昇し、この移動速度上昇効果は1.2秒かけて徐々に減少する。敵ヒーローに命中した場合、移動速度上昇効果の持続時間が2倍になる。 |
| スキル2 | ボイドショット | 範囲技・妨害 | CD 7.5 / 7.3 / 7.1 / 6.9 / 6.7 / 6.5、MP 70（一定）、基礎ダメージ 170 / 200 / 230 / 260 / 290 / 320、追加ダメージ 100 / 120 / 140 / 160 / 180 / 200。マジックエネルギー弾を放ち、命中した敵とその周囲に170(+65%物理攻撃)の物理ダメージを与え、3秒間マジックマークを付与する。マジックマークの付いた敵を攻撃すると、その敵と周囲に100(+35%物理攻撃)の物理ダメージを与え、0.25秒間スタンさせる。 |
| アルティメット | ディストラクトキャノン | 爆発力・バフ | CD 37.0 / 32.0 / 27.0、MP 130 / 150 / 170、射程上昇 0.6 / 1.2 / 1.8、基礎ダメージ 500 / 650 / 800。パッシブ：ボイドショットと通常攻撃の射程が0.6ユニット広がる。このスキルをアップグレードするたびに、視界範囲がわずかに拡大する。アクティブ：指定方向にマジックエネルギーの弾を放ち、直線上の敵に500(+150%物理攻撃)の物理ダメージを与える。 |

2026-10-11 に受け取った無加工の原本（日本語クライアントのスキル詳細の画面 IMG_4493〜4501。画像はコミットしない）と照合した: 上の表の数値（CD・MP・基礎ダメージ・追加ダメージ・係数・
距離 6 で最大 115%・射程 +0.6 / 1.2 / 1.8・スタン 0.25 秒）・タグ（バフ / 爆発力・バフ / 範囲技・妨害 / 爆発力・バフ）・文の構造はすべて一致した（変更なし）。
アルティメットのパッシブの「アップグレードのたびに視界範囲がわずかに拡大する」は、sim に視界を伸ばす仕組みが無く量も不明なので、実装も説明文の記載もしていない（下の「まだ MLBB と違うところ」）。

## 公式（Fandom 現行）の数値

Fandom のヒーローのページ（MediaWiki API で 2026-10-10 に再取得。スキルの Lv は S1・S2 が 1〜6、アルティメットが 1〜3）。上の日本語クライアントの値と違うところは日本語クライアントを正とする。

| スロット | 公式名 | タグ | CD | MP | 内容（Lv1 → Lv6 / Lv3） |
|---|---|---|---|---|---|
| パッシブ | Malefic Gun | Buff | – | – | 遠くの敵ほど与ダメージが増える（100% から 6 マスで 130%。弾が飛んだ距離 1 マスにつき +5%）。タワーは含まない。通常攻撃とスキルのダメージに働く |
| スキル1 | Malefic Bomb | Burst・Buff | 6.0 / 5.6 / 5.2 / 4.8 / 4.4 / 4.0 | 40 / 45 / 50 / 55 / 60 / 65 | 指定方向へ撃ち、最初に当たった敵に 200 / 240 / 280 / 320 / 360 / 400(+80%物理攻撃)の物理ダメージ（会心あり）。敵に当たると 3 秒間 通常攻撃と Void Projectile の射程が伸び（1.6 − 0.2 × アルティメットの Lv マス）、移動速度 +60%（1.2 秒かけて減衰。敵ヒーローに当たると持続が倍） |
| スキル2 | Void Projectile | AoE・Slowed | 7.5 / 7.3 / 7.1 / 6.9 / 6.7 / 6.5 | 65 / 70 / 75 / 80 / 85 / 90 | 光球が命中で爆発し、範囲の敵に 170 / 200 / 230 / 260 / 290 / 320(+65%物理攻撃)の物理ダメージ + 3 秒の Magic Mark。刻印の敵に攻撃を当てると、周囲の敵に 100 / 120 / 140 / 160 / 180 / 200(+35%物理攻撃)の物理ダメージ + 0.25 秒のスタン。説明文に減速の数値は無い（タグだけ「Slowed」） |
| アルティメット | Destruction Rush | Burst・Buff | 37 / 32 / 27 | 130 / 150 / 170 | 指定方向へ撃ち、直線上の敵に 500 / 650 / 800(+150%物理攻撃)の物理ダメージ。パッシブ: Lv ごとに Void Projectile と通常攻撃の射程 +0.6 / 1.2 / 1.8 マス、視界も少し伸びる |

## Velstria 実装対応表

H030 星砲のライナ（`Systems/Kits/Kit_H030.swift`、テスト `Tests/VelstriaCoreTests/Kits/Kit_H030Tests.swift`、演出 `App/Battle/SkillFX/Heroes/FX_H030.swift`）。
単位は Velstria（MLBB の 1 ユニット = 100）。数値は上の「公式（日本語クライアント）の数値」の表そのもの（2026-10-14 から）。

### 数値の方針

- **公式の表をそのまま使う（スキル1・2 = 6 段、アルティメット = 3 段）**。スキルのランク = 公式の Lv で、表を `Kit.level` で引く（補間しない。表の外のランクは端に丸める）。
- ダメージ = 公式の基礎[Lv] + 公式の係数 × **合計の物理攻撃**（`Kit.official(…, .totalAttack, …)`。日本語クライアントの (+N%) は合計、(+N%追加) ではない）。
  スロット倍率・物理係数の × 0.6・キットの換算は掛けない。これに距離補正（最大 +15%。会心の一撃にも乗る）が乗る。
- CD = 公式の秒数 × (1 − CD 短縮)（`Kit.cooldown`。上限は能力値の `cooldownReductionCap`）。マナ = 公式の表（`HeroKit.cost`）。
- 説明文の `{base}(+{atkPct}%物理攻撃)` は公式の値そのもの（例: Lv1 の S1 は「200(+80%物理攻撃)」、刻印は「100(+35%物理攻撃)」）。
- 通常攻撃の射程は 430（ライラの通常攻撃範囲 4.3。`docs/HERO_STATS.md`）。アルティメットのパッシブの射程上昇は公式の +0.6 / 1.2 / 1.8 ユニット（+60 / 120 / 180）、
  S1 命中の一時延長は Fandom の +1.6 / 1.4 / 1.2 / 1.0 ユニット（+160 / 140 / 120 / 100。日本語クライアントの文には量が無い）。最大で 430 + 180 + 100 = 710（ライラの 7.1 と同じ）。

### 公式の表（そのまま使う値）

| 項目 | Lv1 | Lv2 | Lv3 | Lv4 | Lv5 | Lv6 |
|---|---|---|---|---|---|---|
| S1 ダメージ（+80% 物理攻撃） | 200 | 240 | 280 | 320 | 360 | 400 |
| S1 CD（秒） | 6.0 | 5.6 | 5.2 | 4.8 | 4.4 | 4.0 |
| S1 MP | 35 | 40 | 45 | 50 | 55 | 60 |
| S2 爆発（+65% 物理攻撃） | 170 | 200 | 230 | 260 | 290 | 320 |
| S2 刻印への攻撃（+35% 物理攻撃）・スタン 0.25 秒 | 100 | 120 | 140 | 160 | 180 | 200 |
| S2 CD（秒） | 7.5 | 7.3 | 7.1 | 6.9 | 6.7 | 6.5 |
| S2 MP | 70 | 70 | 70 | 70 | 70 | 70 |

| 項目 | Lv1 | Lv2 | Lv3 |
|---|---|---|---|
| アルティメット ダメージ（+150% 物理攻撃） | 500 | 650 | 800 |
| アルティメット CD（秒） | 37 | 32 | 27 |
| アルティメット MP | 130 | 150 | 170 |
| パッシブの射程上昇（ボイドショットと通常攻撃） | +60（0.6） | +120（1.2） | +180（1.8） |

パッシブ（マジックガン）: 最小 100%、距離 600（6 ユニット）で最大 115%。タワーには適用されない。S2 の刻印は 3 秒。

### スキルごとの割合

- スキル吸収率: 日本語クライアントの文に記載が無いので、全スキル既定の 100%（`HitPayload.spellVampRatio` = 1）。テストで S1 の回復 = 与ダメージ × スキル吸収 を確かめる。
- 攻撃エフェクト: 通常攻撃は既定の 100%（距離補正を足すだけ）。スキルに攻撃エフェクトの記載は無い。
- ミニオン・モンスターへの補正: 記載が無いので 100%（`minionMultiplier` / `monsterMultiplier` = 1）。以前の全体の「ミニオンへのスキル × 0.2」は撤廃済み（CombatSystem）。
- クリティカル: S1 だけ（公式「クリティカル可能」）。発動時に通常攻撃と同じ確率で判定し（確率 0 なら乱数を引かない）、術者のクリティカルダメージ（既定 200%）を掛ける。
- CC: 刻印への攻撃のスタン 0.25 秒（CC の段階は「基本」。進行中の突進は止めない）。アルティメットの溜め（0.2 秒）はスタン以上で途切れる（中断できるタイマー。従来どおり）。
  どのスキルも術者を動かさないので、バインドで撃てなくなるスキルは無い。

### 対応表

| 元の仕様 | Velstria での実装 | 区分 |
|---|---|---|
| パッシブ: 与ダメ 100% → 115%（6 ユニットで最大）、通常攻撃とスキルに適用、タワーには適用されない（日本語クライアント。Fandom の 130% は誤り） | `DamageScaling.distance(near: 0, far: 600, minMult: 1, maxMult: 1.15)`。通常攻撃は `shapeBasicAttack` で弾の発射位置を `originPos` にして付与（タワー相手には付けない）、スキルは各ペイロードに付与（直線弾・ゾーンは構造物に当たらない）。会心の一撃にも乗る（会心の倍率 × 距離の補正）。ロールの「4 発毎の確定会心」は置き換え | 忠実（距離だけ簡略） |
| 補正が最大になる距離 6 ユニット（= 600）。補正が始まる距離は書かれていない | 600（MLBB の距離 × 100 そのまま）。始まりは 0 として 0 → 600 で線形（推測）。基本射程 430 の端で約 +11%、射程延長を重ねると +15% に届く | 忠実（始まりは推測） |
| 「弾が飛んだ距離」で測る（Fandom） | 発射位置（通常攻撃・直線弾・ビームは発射時の術者位置、S2 の爆発は S2 を撃った位置）から命中時の対象までの直線距離 | 簡略（追尾で曲がる分の差は無視） |
| S1 マジックボム: 直線、最初の敵に 200〜400 (+80%) の物理、クリティカル可能 | 汎用の遠隔直線弾（射程 650・幅は汎用）。最初の敵 1 体に物理ダメージ（公式の表）、距離補正つき（会心のときも乗る）。会心は発動時に通常攻撃と同じ判定で術者の `critMultiplier`（既定 2.0）倍 | 忠実（射程・幅は推測） |
| S1 命中: 3 秒間、通常攻撃と S2 の射程が伸びる（量は日本語クライアントに無い。Fandom: +1.6/1.4/1.2/1.0 ユニット、アルティメット Lv0〜3） | `attackRangeBoost`（+160/140/120/100、3 秒）。アルティメットの Lv が高いほど小さい点も同じ。HUD は S1 のバッジ（残り秒）に出す | 忠実（量は Fandom） |
| S1 命中: 移動速度 +60% が 1.2 秒かけて減衰、敵ヒーロー命中で持続が倍 | `speedBoost`（+60%）。持続 1.2 秒（敵ヒーローなら 2.4 秒）、毎 tick に残り時間から倍率を決める（`min(1, 残り ÷ 1.2)`）。2.4 秒のときは最初の 1.2 秒は +60% のまま、その後に減衰 | 簡略（「持続が倍」の減衰の形は推測） |
| S2 ボイドショット: 弾が命中した敵とその周囲に 170〜320 (+65%) の物理 + 3 秒のマジックマーク | 直線弾（幅 60・速度 1500）が最初の敵（ミニオン含む）に当たった位置で、半径 190 の円に距離補正つきの物理ダメージ（公式の表）+ 刻印（1 スタック、3 秒、更新で持続が戻る）。敵に当たらなければ射程の端（マップの端で止まるときはそこ）で爆発する: 発動時に「飛行時間 + 1 tick」の非中断タイマー（`Code.orbEnd`、弾の ID と終点を持つ）を積み、命中したら `onHit` が取り消すので爆発は 1 回だけ。術者がスタンされても爆発し、死亡すると状態ごと消える | 忠実（速さ・幅・半径・端の爆発は推測） |
| S2 の射程はアルティメットの Lv と S1 命中で伸びる | 発動時の射程 = 650 + アルティメットのパッシブ（+60/120/180）+ S1 の一時延長。照準の円（HUD）は基本の 650 のまま、イベント `SkillCastEvent.range` には実際の射程を出す | 簡略（HUD の円が実際より小さい） |
| S2 の減速（Fandom のタグ「Slowed」だけで数値は無い） | 日本語クライアントの文・タグ（範囲技・妨害）に減速は無いので**付けない**。`numbers.cc` は刻印の弾けのスタン（0.25 秒） | 忠実 |
| 刻印: 刻印した敵を攻撃すると、その敵と周囲に 100〜200 (+35%) の物理 + 0.25 秒スタン（どの攻撃で、消費するかは書かれていない） | 通常攻撃・S1・アルティメットが刻印した敵に当たったら刻印を消費し、その敵を中心に半径 190 へ距離補正つきの物理（**公式の 100 / 120 / 140 / 160 / 180 / 200 (+35%) の表**。以前の文書の「S2 × 0.40」は古い記述）+ 0.25 秒のスタン。ゾーン（遅延 0）で出すので演出も出る。S2 自身の命中では弾けない（刻印の更新のみ）。所有者ごとに別（他のライナの刻印では弾けない）。炸裂どうしの連鎖はしない | 簡略（消費・トリガーは推測） |
| アルティメット ディストラクトキャノン: 直線上の敵に 500 / 650 / 800 (+150%) の物理 | 0.2 秒の溜め（スタン以上で途切れる。死亡でも消える）の後、発動時に固定した向きへ貫通する高速弾（速度 7000・幅は汎用の 120・射程 2000）。ライン上の全員（ミニオン含む）に距離補正つきの物理（公式の表）。CC なし。直線弾は 1 tick の区間を線分で掃引して当てる（`ProjectileSystem.stepLinear`）のですり抜けない | 忠実（溜め・速さ・幅・射程は推測） |
| ボット: アルティメットの狙い | `botCast` で動く相手を先読みする。到達までの時間 = 溜め 0.2 + 距離 ÷ 7000 に、観測した敵の速度（`BotTeamIntel.velocity`）と難易度の精度を掛ける（乱数は引かない）。撃つ判断は汎用の関門（倒せる / 2 体以上）のまま | 追加 |
| 説明文 | 日本語クライアントの文の構造（パッシブの「最小100%、〜最大115%まで増加する。タワーには適用されない。」、S1 の「（クリティカル可能）」「さらに移動速度が追加で〜」、S2 の「刻印の付いた敵を攻撃すると、その敵と周囲に〜」、アルティメットの「パッシブ：」「アクティブ：」）。数値は公式の表そのもの。UI の用語（スキル1 / スキル2 / アルティメット）、マスターの名前（遠星弾 / 星爆弾 / 刻印）、距離の単位（補正は基本射程 430 の端で約 111%、基本射程の約 1.4 倍 = 600 で最大 115%）、S1 の射程延長がアルティメットの Lv で小さくなること（160 → 100）、アルティメットのパッシブの最大（180）を書く。視界の拡大は sim に無いので書かない | 追加 |
| アルティメットの溜めの間は動けない | 動ける（溜めはタイマーのみ）。向きだけ発動時に固定 | 簡略 |
| アルティメットのパッシブ: Lv ごとに通常攻撃と S2 の射程 +0.6 / 1.2 / 1.8 ユニット、視界も少し伸びる | 射程は公式の表の +60 / 120 / 180 の常時延長（無期限の `attackRangeBoost` ステータスを毎 tick 同期。死亡で消え、復活後に戻る）。視界は伸ばさない | 射程は忠実、視界は未実装 |
| アルティメットでタワーを射程外から撃てる | 直線弾・ビームは構造物に当たらない（汎用の仕様）ので、攻城には使えない | 省略（汎用の仕様と衝突するため） |
| CD・MP（日本語クライアントの表） | 公式の表そのまま（上の「公式の表」）。`RainaTuning.s1Cooldown` / `s1Cost` ほか。マナは `HeroKit.cost` | 忠実 |
| スキルのタグ（UI） | パッシブ `buff`、スキル1 `burst buff`、スキル2 `aoe disrupt`、アルティメット `burst buff`（日本語クライアントの バフ / 爆発力・バフ / 範囲技・妨害 / 爆発力・バフ） | 忠実 |
| 基本ステータス（HP 2320・物理攻撃 133・射程 4.3 など） | `docs/HERO_STATS.md`（MLBB の値へ移行済み） | 対象外 |

### 外した定数とルール（2026-10-14）

| 以前 | 今 |
|---|---|
| キットの換算 `RainaTuning.s1Scale` 0.58 / `s2Scale` 0.54（爆発と刻印に共通）/ `ultScale` 0.52 | 削除（公式の値をそのまま） |
| スロット倍率 `Balance.Skills.damageScale` 4.0 / 3.0 / 2.6、物理係数の × 0.6（`Balance.skillAttackScalingFactor`） | 使わない（`Kit.official` = 基礎 + 係数 × 合計の物理攻撃） |
| `(Lv1, Lv6)` のタプルと `lerp`（ランクへの線形補間）、`Balance.Skills.cooldownScale` | 公式の 6 / 6 / 3 段の表と `Kit.level` / `Kit.cooldown` |
| アルティメットのパッシブ `ultRangePerRank` 60 × ランク | 公式の表 `ultRange` = [60, 120, 180]（値は同じ） |
| 説明文の基本射程 550（基本射程の端で約 114%、約 1.1 倍） | 430（約 111%、約 1.4 倍） |
| 汎用スキルとの火力の比のテスト（0.7〜1.4 倍）、`lv = 1 + (rank − 1)·5/3` の式のテスト | 削除。公式の表と等しいことのテストに置き換え |

外したルールは数値の換算だけで、MLBB に無い独自の挙動（無限ループ止めなど）はライラには元から無い。

### まだ MLBB と違うところ

- パッシブ: 補正の始まる距離は書かれていないので 0 から線形（推測。3〜4 つの距離のダメージの読み取りで確かめる）。「弾が飛んだ距離」ではなく、発射位置から命中時の対象までの直線距離。
- S1: 射程延長の量は Fandom の値（日本語クライアントに量が無い）。加速の「持続 2 倍」の減衰の形は推測。射程 650・弾幅は汎用（推測）。
  会心は発動時に判定するので、対象のクリティカルダメージ軽減（`critDamageReduction`）が掛からない。
- S2: 弾の速さ 1500・幅 60・爆発の半径 190・射程 650、射程の端の爆発、刻印を弾けさせる攻撃（通常攻撃・S1・アルティメット）と消費の規則は推測。
- アルティメット: 溜め 0.2 秒・速さ 7000・幅 120・射程 2000 は推測。溜め中に動ける。構造物に当たらない。
- アルティメットのパッシブの「アップグレードのたびに視界範囲がわずかに拡大する」は**未実装**（量が不明。キットから視界を伸ばす共通の仕組み、例えば視界を足す状態が要る）。
- 詠唱の時間（全スキル）は無い（共通）。

### 演出（`FX_H030.swift`）

- App の `SkillFXDirector` はまだ `stage / count / duration` を読まないので、レシピ（cast / telegraph / travel / impact / hit）の構成だけで機構に合わせた:
  S2 は光球の飛翔（travel）→ 着弾の大爆発（impact、半径 1.9m の固定寸法）、刻印の炸裂は同じ爆発を再び再生し、`telegraph` を刻印の閃きにした。
  奥義は 0.2 秒の溜め（cast の `at: 0.2` でビーム）に合わせて詠唱モーションの溜めを約 0.22 秒に揃えた（後の余韻は伸ばして全体 0.5 秒）。
- スキル1 の cast は砲口の大きな閃光を一つと、前へ走る光の筋（旧: 三連の小さな閃光）。ヘッダーの古い名前（Raina式・一閃 / 星環シフト）は master の名前（遠星弾 / 星爆弾）に直した。
- スキル2 の着弾は弾が消えた位置で再生される（射程の端の爆発と同じ場所）。
- パッシブの合図は**パッシブのバッジ**（2026-10 に追加）で出る: 敵ヒーローへの通常攻撃・スキルの命中の距離補正が +10% 以上（距離 400 以上 = 最大 +15% の 2/3）なら、
  バッジに 1.5 秒のタイマー（`KitBadge(kind: .timer, value: その命中の補正 %, maxValue: 15)`）が付く。命中のたびに付け直すので、射程の端から撃ち続けている間は
  点いたまま（`SkillFXDirector.observeKitPassives` はタイマーが点いた瞬間に 1 回だけ演出を出す）。補正はダメージと同じ式・同じ起点（通常攻撃 = 最後に放った弾の
  発射位置、S1 = 撃った位置、S2 の爆発 = S2 を撃った位置、ビーム = 放った位置）。ミニオン・モンスター・刻印の弾けは数えない。
  状態は `KitState`（`timers[1]` 残り秒、`ints[1]` 補正 %、`reals[2...7]` 起点）で、決定的（乱数を引かない）。

### バランス計測（`KitBalanceTests`・1v1 の TTK、Release）

- 公式の表へ移した（2026-10-14）ので、以前の旧尺度の計測（レンジャー汎用の中央値との差・開幕 3 秒の瞬間火力・換算の候補ごとの勝率）は意味を失った。
  全キットを統合した後に親が測り直す（帯の数値は変えていない）。

### 経緯

- 2026-10 以前: 汎用スキルの比（S1 × 0.92、S2 × 0.70・刻印 × 0.40、奥義 × 1.0）→ Fandom の表をランク 4 段へ線形補間 + キットの換算（`s1Scale` ほか）→
  日本語クライアントの値（パッシブ 130% → 115%、S1 MP 40 → 65 を 35 → 60、S2 MP 65 → 90 を 70 一定、S2 の減速を外す、タグ「範囲技・妨害」）。
  CD は全体の倍率 0.5 を外して、マスターの 6.5 / 7.6 / 33 秒からライラの秒数にした。
- 2026-10-14: 公式の表をそのまま使う（6 / 6 / 3 段、換算なし。上の「数値の方針」）。換算の値の選び方と旧尺度の勝率の記録は削除した（git の履歴に残る）。
