# Layla (MLBB) - Kit Specification

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


## 公式（Fandom 現行）の数値

Fandom のヒーローのページ（MediaWiki API で 2026-10-10 に再取得。スキルの Lv は S1・S2 が 1〜6、アルティメットが 1〜3）。上の日本語クライアントの値と違うところは日本語クライアントを正とする。

| スロット | 公式名 | タグ | CD | MP | 内容（Lv1 → Lv6 / Lv3） |
|---|---|---|---|---|---|
| パッシブ | Malefic Gun | Buff | – | – | 遠くの敵ほど与ダメージが増える（100% から 6 マスで 130%。弾が飛んだ距離 1 マスにつき +5%）。タワーは含まない。通常攻撃とスキルのダメージに働く |
| スキル1 | Malefic Bomb | Burst・Buff | 6.0 / 5.6 / 5.2 / 4.8 / 4.4 / 4.0 | 40 / 45 / 50 / 55 / 60 / 65 | 指定方向へ撃ち、最初に当たった敵に 200 / 240 / 280 / 320 / 360 / 400(+80%物理攻撃)の物理ダメージ（会心あり）。敵に当たると 3 秒間 通常攻撃と Void Projectile の射程が伸び（1.6 − 0.2 × アルティメットの Lv マス）、移動速度 +60%（1.2 秒かけて減衰。敵ヒーローに当たると持続が倍） |
| スキル2 | Void Projectile | AoE・Slowed | 7.5 / 7.3 / 7.1 / 6.9 / 6.7 / 6.5 | 65 / 70 / 75 / 80 / 85 / 90 | 光球が命中で爆発し、範囲の敵に 170 / 200 / 230 / 260 / 290 / 320(+65%物理攻撃)の物理ダメージ + 3 秒の Magic Mark。刻印の敵に攻撃を当てると、周囲の敵に 100 / 120 / 140 / 160 / 180 / 200(+35%物理攻撃)の物理ダメージ + 0.25 秒のスタン。説明文に減速の数値は無い（タグだけ「Slowed」） |
| アルティメット | Destruction Rush | Burst・Buff | 37 / 32 / 27 | 130 / 150 / 170 | 指定方向へ撃ち、直線上の敵に 500 / 650 / 800(+150%物理攻撃)の物理ダメージ。パッシブ: Lv ごとに Void Projectile と通常攻撃の射程 +0.6 / 1.2 / 1.8 マス、視界も少し伸びる |

### 公式が置き換えた値

| 項目 | 以前の実装 | 公式 |
|---|---|---|
| S1 のダメージ | 汎用 S1 × 0.92 | **200 → 400(+80%)** の表（換算 `s1Scale`） |
| S2 のダメージ | 汎用 S2 の元の値 × 0.70、刻印の炸裂 × 0.40 | **170 → 320(+65%) / 100 → 200(+35%)** の表（換算 `s2Scale`） |
| アルティメットのダメージ | 汎用の奥義 × 1.0 | **500 / 650 / 800(+150%)** の表（換算 `ultScale`） |
| マナ | マスターの 45 / 50 / 100（キットで変えられなかった） | **40 → 65 / 65 → 90 / 130・150・170**（`HeroKit.cost`） |
| クールダウン | 公式の秒数（2026-10 に変更済み） | 同じ（確認） |

ランクの対応: Velstria のスキルのランクは S1/S2 が 4 段、アルティメットが 3 段（`SkillSlot.maxRank`）。表は線形補間で写す（ランク 1 = Lv1、最大ランク = Lv6。
ランク r → Lv `1 + (r − 1) × 5 / 3`）。公式の表はどれも等差なので、補間は「最初と最後の値を結ぶ直線」と同じ。

## Velstria 実装対応表

H030 星砲のライナ（`Systems/Kits/Kit_H030.swift`、テスト `Tests/VelstriaCoreTests/Kits/Kit_H030Tests.swift`、演出 `App/Battle/SkillFX/Heroes/FX_H030.swift`）。
単位は Velstria（≈ 100 × MLBB の 1 マス）。数値は上の「公式（Fandom 現行）の数値」の表をランクで線形補間して持つ（2026-10 から。以前は汎用スキルの比）。

### 数値の方針

- スキルのランクは S1/S2 が 4 段・奥義が 3 段（ライラは 6/6/3）。公式の表（ダメージ・クールダウン・マナ）をランクへ線形補間する。
- ダメージは sim の通常の式 `(公式の基礎 + 係数 × 攻撃力 × 0.6) × スロット倍率` に、スキルごとの換算（`RainaTuning.s1Scale / s2Scale / ultScale`）を掛けた値。
  換算は「公式の形のまま、Velstria の火力の尺度（汎用スキルとほぼ同じ大きさ）」になるように選んだ（下の「公式の数値に合わせる」）。これに距離補正（最大 +15%。会心の一撃にも乗る）が乗る。
  説明文の `{base}(+{atkPct}%物理攻撃)` は換算後の値。マナは `HeroKit.cost` で公式の表。
- 通常攻撃の射程は 550（ライラの基本 4.3 に対し、遠隔の共通値）。射程延長の量（ライラ: +0.6/ランク、S1 の一時延長 1.6/1.4/1.2/1.0）は
  そのままの比で 100 倍した（+60/ランク、+160/140/120/100）。最大で 550 + 180 + 100 = 830（ライラ 7.1 ÷ 4.3 ≒ 1.65 倍に対し 1.51 倍）。

### 対応表

| 元の仕様 | Velstria での実装 | 区分 |
|---|---|---|
| パッシブ: 与ダメ 100% → 115%（6 マスで最大）、通常攻撃とスキルに適用、タワーには適用されない（日本語クライアント。Fandom の 130% は誤り） | `DamageScaling.distance(near: 0, far: 600, minMult: 1, maxMult: 1.15)`。通常攻撃は `shapeBasicAttack` で弾の発射位置を `originPos` にして付与（タワー相手には付けない）、スキルは各ペイロードに付与（直線弾・ゾーンは構造物に当たらない）。会心の一撃にも乗る（会心の倍率 × 距離の補正）。ロールの「4 発毎の確定会心」は置き換え | 忠実（距離だけ簡略） |
| 補正が最大になる距離 6 マス（= 600） | 600（MLBB の距離 × 100 そのまま。以前はライナの基本射程 550 に合わせて 770 に伸ばしていた）。基本射程の端で約 +14%、射程延長を重ねると +15% に届く | 忠実 |
| 「弾が飛んだ距離」で測る | 発射位置（通常攻撃・直線弾・ビームは発射時の術者位置、S2 の爆発は S2 を撃った位置）から命中時の対象までの直線距離 | 簡略（追尾で曲がる分の差は無視） |
| S1 マレフィック・ボム: 直線、最初の敵に 200–400 (+80%) の物理、会心あり | 汎用の遠隔直線弾（射程 650・幅は汎用）。最初の敵 1 体に物理ダメージ、距離補正つき（会心のときも乗る）。会心は発動時に通常攻撃と同じ判定（確率が 0 のときは乱数を引かない）で `critMultiplier` 倍 | 忠実 |
| S1 命中: 3 秒間、通常攻撃と S2 の射程 +1.6/1.4/1.2/1.0 マス（奥義ランク 0〜3） | `attackRangeBoost`（+160/140/120/100、3 秒）。奥義ランクが高いほど小さい点も同じ。HUD は S1 のバッジ（残り秒）に出す | 忠実 |
| S1 命中: 移動速度 +60% が 1.2 秒かけて減衰、敵ヒーロー命中で持続が倍 | `speedBoost`（+60%）。持続 1.2 秒（敵ヒーローなら 2.4 秒）、毎 tick に残り時間から倍率を決める（`min(1, 残り ÷ 1.2)`）。2.4 秒のときは最初の 1.2 秒は +60% のまま、その後に減衰 | 簡略（「持続が倍」の減衰の形は推測） |
| S2 ヴォイド・プロジェクタイル: 光球が飛び、命中で爆発して範囲に 170–320 (+65%) の物理 + 3 秒の魔法の刻印 | 直線弾（幅 60・速度 1500）が最初の敵（ミニオン含む）に当たった位置で、半径 190 の円に距離補正つきの物理ダメージ + 刻印（1 スタック、3 秒、更新で持続が戻る）。敵に当たらなければ射程の端（マップの端で止まるときはそこ）で爆発する: 発動時に「飛行時間 + 1 tick」の非中断タイマー（`Code.orbEnd`、弾の ID と終点を持つ）を積み、命中したら `onHit` が取り消すので爆発は 1 回だけ。術者がスタンされても爆発し、死亡すると状態ごと消える。弾の消滅の演出（`projectileHit`）が終点の爆発の位置で再生される | 忠実 |
| S2 の射程は奥義ランクと S1 命中で伸びる | 発動時の射程 = 650 + 奥義ランク × 60 + S1 の一時延長。照準の円（HUD）は基本の 650 のまま、イベント `SkillCastEvent.range` には実際の射程を出す | 簡略（HUD の円が実際より小さい） |
| S2 の減速（Fandom のタグ「Slowed」だけで数値は無い） | 日本語クライアントの文・タグ（範囲技・妨害）に減速は無いので**付けない**（以前は 30%・1 秒を足していた）。`numbers.cc` は刻印の弾けのスタン（0.25 秒） | 忠実 |
| 刻印: 刻印した敵に攻撃が当たると 100–200 (+35%) の物理を周囲に与え 0.25 秒スタン（どの攻撃で、消費するかは不明） | 通常攻撃・S1・奥義が刻印した敵に当たったら刻印を消費し、その敵を中心に半径 190 へ距離補正つきの物理（S2 の 0.40 倍）+ 0.25 秒のスタン。ゾーン（遅延 0）で出すので演出も出る。S2 自身の命中では弾けない（刻印の更新のみ）。所有者ごとに別（他のライナの刻印では弾けない）。炸裂どうしの連鎖はしない | 簡略（消費・トリガーは推測） |
| 奥義 デストラクション・ラッシュ: 直線の長いビーム、ライン上の全員に 500–800 (+150%) の物理 | 0.2 秒の溜め（ハード CC で途切れる。死亡でも消える）の後、発動時に固定した向きへ貫通する高速弾（速度 7000・幅は汎用の 120・射程 2000）。ライン上の全員（ミニオン含む）に距離補正つきの物理。CC なし。速度 7000 は 1 tick に約 233 進むが、直線弾は 1 tick の区間を線分で掃引して当てる（`ProjectileSystem.stepLinear`）のですり抜けない（テスト: 130〜1990 の 7 体全員に 1 度ずつ）。射程 2000 を約 0.29 秒で貫くので、溜めと合わせて 0.5 秒以内に端まで届く（旧: 溜め 0.3 + 速度 3600 で 0.86 秒） | 忠実（溜め・速さは推測。旧版は 0.3 秒・3600） |
| ボット: 奥義の狙い | `botCast` で動く相手を先読みする。到達までの時間 = 溜め 0.2 + 距離 ÷ 7000 に、観測した敵の速度（チームの視界記録 `BotTeamIntel.velocity`）と難易度の精度（Easy 0.55 / Normal 0.75 / Hard 0.92）を掛ける（乱数は引かない）。汎用の見積もり（0.1 + 距離 ÷ 1600）は新しいビームより長く遠距離で先読みしすぎるため使わない。撃つ判断は汎用の関門（倒せる / 2 体以上）のまま | 追加 |
| 説明文 | 日本語クライアントの文の構造（「距離が遠い対象ほど、与ダメージが増加する（最小100%、〜最大115%まで増加する）。タワーには適用されない。」「指定方向に〜を放ち、最初に命中した敵に {base}(+{atkPct}%物理攻撃)の物理ダメージを与える（クリティカル可能）」「さらに移動速度が追加で〜」「刻印の付いた敵を攻撃すると、その敵と周囲に〜」・アルティメットの「パッシブ：」「アクティブ：」の順）。UI の用語（スキル1 / スキル2 / アルティメット）、マスターの名前（遠星弾 / 星爆弾 / 刻印）、距離の単位（補正は基本射程 550 の端で約 114%、基本射程の約 1.1 倍 = 600 で最大 115%）、スキル1 の射程延長がアルティメットのランクで小さくなること（160 → 100）を書く。視界の拡大は sim に無いので書かない | 追加 |
| 奥義の溜めの間は動けない | 動ける（溜めはタイマーのみ）。向きだけ発動時に固定 | 簡略 |
| 奥義パッシブ: ランクごとに通常攻撃と S2 の射程 +0.6/1.2/1.8、視界も少し伸びる | 射程は +60/120/180 の常時延長（無期限の `attackRangeBoost` ステータスを毎 tick 同期。死亡で消え、復活後に戻る）。視界は伸ばさない | 射程は忠実、視界は省略（視界の仕組みに手を入れない） |
| 奥義でタワーを射程外から撃てる | 直線弾・ビームは構造物に当たらない（汎用の仕様）ので、攻城には使えない | 省略（汎用の仕様と衝突するため） |
| コスト 35–60 / 70（一定）/ 130–170、CD 6→4 / 7.5→6.5 / 37→27（日本語クライアント） | CD・マナともライラと同じ（S1 6 → 4 秒・35 → 60、S2 7.5 → 6.5 秒・70 一定をランク 4 段へ線形補間、奥義 37 / 32 / 27 秒・130 / 150 / 170。`RainaTuning.s1Cooldown` / `s1Cost` ほか、マナは `HeroKit.cost`）。以前は Fandom の 40 → 65 / 65 → 90、その前はコストが汎用（45 / 50 / 100）、さらに前は CD も汎用（6.5 / 7.6 / 33 秒 × 0.5）だった | 忠実 |
| ダメージ 200→400 (+80%) / 170→320 (+65%)・刻印 100→200 (+35%) / 500・650・800 (+150%) | 公式の基礎をランクで補間し、`(基礎 + 係数 × 攻撃力 × 0.6) × スロット倍率 × 換算`。以前は汎用の 0.92 / 0.70・0.40 / 1.00 倍 | 忠実（絶対値は Velstria の尺度） |
| スキルのタグ（UI） | パッシブ `buff`、スキル1 `burst buff`、スキル2 `aoe disrupt`、アルティメット `burst buff`（日本語クライアントの バフ / 爆発力・バフ / 範囲技・妨害 / 爆発力・バフ。以前は Fandom の S2「AoE・Slowed」で `aoe slow`） | 忠実 |
| 基本ステータス（HP 2250 など） | `master_runtime.json` の H030 のまま | 対象外 |

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

### バランス計測（`KitBalanceTests`、Release）

- レンジャー汎用の中央値との差（勝率 %）: 見直し前 Lv1 -28.5 / Lv6 -11.6 / Lv12 -11.4（39.4 / 20.2 / 11.1 %）→ 見直し後 Lv1 -27.0 / Lv6 +0.5 / Lv12 -0.5（44.4 / 31.3 / 21.7 %、中央値 71.5 / 30.8 / 22.2 %）。
  勝率を狙った調整ではない（スキル2 の減速・射程の端の爆発・ビームの速さの変更の副産物）。Lv1 が低いのはレンジャー共通で（汎用レンジャーの中央値が Lv1 だけ高い）、帯 45 pt の内。
- 開幕 3 秒の瞬間火力（ダミー H001、同ロール汎用の中央値との比）: Lv1 0.95 / Lv6 1.33 / Lv12 1.43 倍。ビームの速さを上げても 3 秒の合計は変わらなかった（ビームは 1 回しか当たらない）。

### クールダウンを MLBB の秒数に（2026-10）

- 全体の CD 倍率 0.5 を廃止し、CD を汎用（マスター 6.5 / 7.6 / 33 秒）からライラの秒数（6 → 4 / 7.5 → 6.5 / 37・32・27 秒）にした。数値は変えていない。`KitBalanceTests`（レンジャー中央値との差）: 変更前 −29.8 / −0.3 / −1.5 → 変更後 −5.3 / −3.4 / +3.4 pt。

### 公式の数値に合わせる（2026-10）

上の「公式（Fandom 現行）の数値」を正として、マナ・ダメージの表をランクへ線形補間した（クールダウンは変更済み。方法は H029 ボルグ = Tigreal と同じ）。
ダメージは sim の通常の式 `(公式の基礎 + 係数 × 攻撃力 × 0.6) × スロット倍率` にスキルごとの換算（`RainaTuning.s1Scale` ほか）を掛ける。数値は距離補正の前、素の能力値（Lv1 / Lv12、奥義は Lv6 / Lv12）。

| 項目 | 公式 | 以前 | 今 |
|---|---|---|---|
| パッシブ | 距離で 100% → 130% | 同じ（770 で頭打ち） | 同じ |
| S1 CD / マナ | 6.0 → 4.0 秒・40 → 65 | 6.0 → 4.0 秒・45（マスター） | 6.0 / 5.33 / 4.67 / 4.0 秒・40 / 48.3 / 56.7 / 65 |
| S1 ダメージ | 200 → 400(+80%)、会心あり | 汎用 S1 × 0.92（Lv1 565 / Lv12 989） | (200 → 400 + 0.8 × 攻撃力 × 0.6) × 4.0 × 0.53（Lv1 569 / Lv12 1054） |
| S1 命中の効果 | 射程 +1.6 − 0.2 × 奥義 Lv（3 秒）、移動速度 +60%（1.2 秒で減衰、ヒーローで倍） | 同じ | 同じ |
| S2 CD / マナ | 7.5 → 6.5 秒・65 → 90 | 7.5 → 6.5 秒・50（マスター） | 7.5 / 7.17 / 6.83 / 6.5 秒・65 / 73.3 / 81.7 / 90 |
| S2 爆発 | 170 → 320(+65%) | 元のスキル値 × 0.70（Lv1 371 / Lv12 647） | (170 → 320 + 0.65 × 攻撃力 × 0.6) × 3.0 × 0.54（Lv1 365 / Lv12 646） |
| S2 刻印の炸裂 | 100 → 200(+35%)・スタン 0.25 秒 | 元のスキル値 × 0.40（Lv1 212 / Lv12 370） | (100 → 200 + 0.35 × 攻撃力 × 0.6) × 3.0 × 0.54（Lv1 210 / Lv12 393）・0.25 秒 |
| 奥義 CD / マナ | 37 / 32 / 27 秒・130 / 150 / 170 | 37 / 32 / 27 秒・100（マスター） | 37 / 32 / 27 秒・130 / 150 / 170 |
| 奥義 ダメージ | 500 / 650 / 800(+150%) | 汎用の奥義 × 1.0（Lv6 1000 / Lv12 1500） | (500 / 650 / 800 + 1.5 × 攻撃力 × 0.6) × 2.6 × 0.56（Lv6 950 / Lv12 1430） |
| 奥義のパッシブ | 射程 +0.6 / 1.2 / 1.8 マス | +60 / 120 / 180 | 同じ |
| タグ | Buff / Burst・Buff / AoE・Slowed / Burst・Buff | なし | `buff` / `burst buff` / `aoe slow` / `burst buff` |

- 説明文（`KitText` ja/en）は公式の文の構造（「指定方向へ遠星弾を放ち、最初に命中した敵に{base}(+{atkPct}%物理攻撃)の物理ダメージを与える（クリティカルが発生する）。」、アルティメットの「パッシブ：」の段落など）に合わせた。名前は master（遠星の照準 / 遠星弾 / 星爆弾 / 星砕の大砲）。
- 換算は、まずランク 1 が以前の値と同じになる値（0.53 / 0.55 / 0.59）にし、`KitBalanceTests` で Lv12 を中央値へ寄せて S2 0.54・奥義 0.56 にした（0.48 / 0.50 / 0.53 は Lv1 −13 / Lv6 −14 / Lv12 −7、0.58 / 0.60 / 0.65 は +5 / +12 / +20）。
- `KitBalanceTests`（Release、レンジャー中央値 63.9 / 38.8 / 28.9 %）: 変更前 −5.3 / −3.4 / +3.4 → 変更後 57.6 / 38.4 / 35.9 % = **−6.3 / −0.4 / +6.9 pt**（Lv1 / 6 / 12）。開幕 3 秒の瞬間火力の比 0.95 / 1.23 / 1.25。

### 日本語クライアントの数値へ（2026-10）

上の「公式（日本語クライアント）の数値」（2026-10-10 受領の実機のスクリーンショット）に合わせた。

| 項目 | 日本語クライアント | 変更前（Fandom） | 変更後 |
|---|---|---|---|
| パッシブの最大 | 6 マスで 115%（タワーには適用されない） | 6 マス → 770 で 130% | **600 で 115%**（`farDistance` 600・`maxDistanceBonus` 0.15。基本射程 550 の端で約 114%）。会心の一撃にも乗る |
| S1 マナ | 35 → 60 | 40 → 65 | 35 / 43.3 / 51.7 / 60 |
| S2 マナ | 70（一定） | 65 → 90 | 70 |
| S2 の減速 | 記載なし（タグは 範囲技・妨害） | 30%・1 秒（Fandom のタグ「Slowed」から推測） | **なし**（`numbers.cc` は刻印の弾けのスタン 0.25 秒） |
| タグ | バフ / 爆発力・バフ / 範囲技・妨害 / 爆発力・バフ | `buff` / `burst buff` / `aoe slow` / `burst buff` | `buff` / `burst buff` / `aoe disrupt` / `burst buff` |
| 説明文 | 上の表の文 | Fandom の英語の構造 | 日本語クライアントの文の構造（パッシブの「最小100%、〜最大115%まで増加する。タワーには適用されない。」、S1 の「（クリティカル可能）」「さらに移動速度が追加で〜」、S2 の「刻印の付いた敵を攻撃すると、その敵と周囲に〜」、アルティメットの「パッシブ：」「アクティブ：」） |
| パッシブのバッジ | — | なし（App のパッシブの演出が出なかった） | 遠距離命中の合図（上の「演出」の節。補正 +10% 以上の命中で 1.5 秒のタイマー、value = 補正 %） |

- 距離補正が半分（+30% → +15%）になって、1 体ぶんの総当たりでレンジャー中央値との差が −20 / −3 / +4 pt（Lv1 / 6 / 12）になった。CD・マナ・CC は公式のまま、
  換算だけを S1 0.53 → **0.58**、奥義 0.56 → **0.52** にした（S2 0.54 は同じ）。比べた値: S1 0.57 → −12 / +2 / +7、**S1 0.58 + 奥義 0.52 → −10 / +3 / +7**、
  S1 0.60 → −4 / +9 / +14、S1 0.60 + 奥義 0.50 → −4 / +6 / +9、S1 0.65 → +1 / +14 / +23 pt。
- `KitBalanceTests`（Release）の最終（レンジャー中央値 67.9 / 39.8 / 28.9 %）: 59.6 / 42.4 / 36.9 % = **−8.3 / +2.7 / +8.0 pt**（Lv1 / 6 / 12）。
