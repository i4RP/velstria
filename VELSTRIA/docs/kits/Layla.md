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

## Velstria 実装対応表

H030 星砲のライナ（`Systems/Kits/Kit_H030.swift`、テスト `Tests/VelstriaCoreTests/Kits/Kit_H030Tests.swift`、演出 `App/Battle/SkillFX/Heroes/FX_H030.swift`）。
単位は Velstria（≈ 100 × MLBB の 1 マス）。数値はライナの汎用スキル（`base.damage`）の比で持ち、TTK を保つ。

### 数値の方針

- スキルのランクは S1/S2 が 4 段・奥義が 3 段（ライラは 6/6/3）。ランク差は汎用の +30%/ランクをそのまま使う。
- 1 スロットの単体ダメージ（距離補正を除く）は汎用の 0.8〜1.3 倍に収める: S1 = 0.92 倍、S2 = 爆発 0.70 + 刻印の炸裂 0.40 = 1.10 倍
  （汎用の遠隔 S2 は「ブリンク + 強化攻撃」で数値が半分なので、基準は元のスキル値 = base ÷ 0.5）、奥義 = 1.00 倍。
  これに距離補正（最大 +30%）が乗る。クールダウンはライラの秒数そのまま（下の表）、コストは汎用のまま（コストは `SkillSystem` が定義から引くので numbers では変えられない）。
- 通常攻撃の射程は 550（ライラの基本 4.3 に対し、遠隔の共通値）。射程延長の量（ライラ: +0.6/ランク、S1 の一時延長 1.6/1.4/1.2/1.0）は
  そのままの比で 100 倍した（+60/ランク、+160/140/120/100）。最大で 550 + 180 + 100 = 830（ライラ 7.1 ÷ 4.3 ≒ 1.65 倍に対し 1.51 倍）。

### 対応表

| 元の仕様 | Velstria での実装 | 区分 |
|---|---|---|
| パッシブ: 与ダメ 100% → 130%（距離 5%/マス、6 マスで頭打ち）、通常攻撃とスキルに適用、タワーには効かない | `DamageScaling.distance(near: 0, far: 770, minMult: 1, maxMult: 1.3)`。通常攻撃は `shapeBasicAttack` で弾の発射位置を `originPos` にして付与（タワー相手には付けない）、スキルは各ペイロードに付与（直線弾・ゾーンは構造物に当たらない）。ロールの「4 発毎の確定会心」は置き換え | 忠実（距離だけ簡略） |
| 補正が最大になる距離 6 マス（= 600） | 770。ライラの基本射程 4.3 に対しライナは 550 なので、頭打ちの距離を 550/430 倍に伸ばした。基本射程の端で約 +25%（ライラ +21.5%）、射程延長を重ねて初めて +30% に届く | 調整 |
| 「弾が飛んだ距離」で測る | 発射位置（通常攻撃・直線弾・ビームは発射時の術者位置、S2 の爆発は S2 を撃った位置）から命中時の対象までの直線距離 | 簡略（追尾で曲がる分の差は無視） |
| S1 マレフィック・ボム: 直線、最初の敵に 200–400 (+80%) の物理、会心あり | 汎用の遠隔直線弾（射程 650・幅は汎用）。最初の敵 1 体に物理ダメージ、距離補正つき。会心は発動時に通常攻撃と同じ判定（確率が 0 のときは乱数を引かない）で `critMultiplier` 倍 | 忠実 |
| S1 命中: 3 秒間、通常攻撃と S2 の射程 +1.6/1.4/1.2/1.0 マス（奥義ランク 0〜3） | `attackRangeBoost`（+160/140/120/100、3 秒）。奥義ランクが高いほど小さい点も同じ。HUD は S1 のバッジ（残り秒）に出す | 忠実 |
| S1 命中: 移動速度 +60% が 1.2 秒かけて減衰、敵ヒーロー命中で持続が倍 | `speedBoost`（+60%）。持続 1.2 秒（敵ヒーローなら 2.4 秒）、毎 tick に残り時間から倍率を決める（`min(1, 残り ÷ 1.2)`）。2.4 秒のときは最初の 1.2 秒は +60% のまま、その後に減衰 | 簡略（「持続が倍」の減衰の形は推測） |
| S2 ヴォイド・プロジェクタイル: 光球が飛び、命中で爆発して範囲に 170–320 (+65%) の物理 + 3 秒の魔法の刻印 | 直線弾（幅 60・速度 1500）が最初の敵（ミニオン含む）に当たった位置で、半径 190 の円に距離補正つきの物理ダメージ + 刻印（1 スタック、3 秒、更新で持続が戻る）。敵に当たらなければ射程の端（マップの端で止まるときはそこ）で爆発する: 発動時に「飛行時間 + 1 tick」の非中断タイマー（`Code.orbEnd`、弾の ID と終点を持つ）を積み、命中したら `onHit` が取り消すので爆発は 1 回だけ。術者がスタンされても爆発し、死亡すると状態ごと消える。弾の消滅の演出（`projectileHit`）が終点の爆発の位置で再生される | 忠実 |
| S2 の射程は奥義ランクと S1 命中で伸びる | 発動時の射程 = 650 + 奥義ランク × 60 + S1 の一時延長。照準の円（HUD）は基本の 650 のまま、イベント `SkillCastEvent.range` には実際の射程を出す | 簡略（HUD の円が実際より小さい） |
| S2 の説明に「減速」の表記があるが数値は無い | 爆発に軽い減速（30%・1 秒、タグ付き）を付けた。ダメージと同じ範囲。説明文・`numbers.cc` にも出す（`slow` / `slowDuration`） | 調整（数値は推測。旧版は「減速なし」） |
| 刻印: 刻印した敵に攻撃が当たると 100–200 (+35%) の物理を周囲に与え 0.25 秒スタン（どの攻撃で、消費するかは不明） | 通常攻撃・S1・奥義が刻印した敵に当たったら刻印を消費し、その敵を中心に半径 190 へ距離補正つきの物理（S2 の 0.40 倍）+ 0.25 秒のスタン。ゾーン（遅延 0）で出すので演出も出る。S2 自身の命中では弾けない（刻印の更新のみ）。所有者ごとに別（他のライナの刻印では弾けない）。炸裂どうしの連鎖はしない | 簡略（消費・トリガーは推測） |
| 奥義 デストラクション・ラッシュ: 直線の長いビーム、ライン上の全員に 500–800 (+150%) の物理 | 0.2 秒の溜め（ハード CC で途切れる。死亡でも消える）の後、発動時に固定した向きへ貫通する高速弾（速度 7000・幅は汎用の 120・射程 2000）。ライン上の全員（ミニオン含む）に距離補正つきの物理。CC なし。速度 7000 は 1 tick に約 233 進むが、直線弾は 1 tick の区間を線分で掃引して当てる（`ProjectileSystem.stepLinear`）のですり抜けない（テスト: 130〜1990 の 7 体全員に 1 度ずつ）。射程 2000 を約 0.29 秒で貫くので、溜めと合わせて 0.5 秒以内に端まで届く（旧: 溜め 0.3 + 速度 3600 で 0.86 秒） | 忠実（溜め・速さは推測。旧版は 0.3 秒・3600） |
| ボット: 奥義の狙い | `botCast` で動く相手を先読みする。到達までの時間 = 溜め 0.2 + 距離 ÷ 7000 に、観測した敵の速度（チームの視界記録 `BotTeamIntel.velocity`）と難易度の精度（Easy 0.55 / Normal 0.75 / Hard 0.92）を掛ける（乱数は引かない）。汎用の見積もり（0.1 + 距離 ÷ 1600）は新しいビームより長く遠距離で先読みしすぎるため使わない。撃つ判断は汎用の関門（倒せる / 2 体以上）のまま | 追加 |
| 説明文 | UI の用語（スキル1 / スキル2 / アルティメット）、マスターの名前（星爆弾 = スキル2。以前は「星環弾」「星環シフト」）、距離の単位（補正は基本射程 550 の端で約 +21%、基本射程の 1.4 倍 = 770 で最大 +30%）、スキル1 の射程延長がアルティメットのランクで小さくなること（160 → 100）を書く | 追加 |
| 奥義の溜めの間は動けない | 動ける（溜めはタイマーのみ）。向きだけ発動時に固定 | 簡略 |
| 奥義パッシブ: ランクごとに通常攻撃と S2 の射程 +0.6/1.2/1.8、視界も少し伸びる | 射程は +60/120/180 の常時延長（無期限の `attackRangeBoost` ステータスを毎 tick 同期。死亡で消え、復活後に戻る）。視界は伸ばさない | 射程は忠実、視界は省略（視界の仕組みに手を入れない） |
| 奥義でタワーを射程外から撃てる | 直線弾・ビームは構造物に当たらない（汎用の仕様）ので、攻城には使えない | 省略（汎用の仕様と衝突するため） |
| コスト 40–65 / 65–90 / 130–170、CD 6→4 / 7.5→6.5 / 37→27 | CD はライラと同じ（S1 6 → 4 秒・S2 7.5 → 6.5 秒をランク 4 段へ線形補間、奥義 37 / 32 / 27 秒。`RainaTuning.s1Cooldown` ほか）。コストは汎用（45 / 50 / 100）のまま。以前は CD も汎用（6.5 / 7.6 / 33 秒 × 0.5）だった | CD は忠実、コストは簡略 |
| 基本ステータス（HP 2250 など） | `master_runtime.json` の H030 のまま | 対象外 |

### 演出（`FX_H030.swift`）

- App の `SkillFXDirector` はまだ `stage / count / duration` を読まないので、レシピ（cast / telegraph / travel / impact / hit）の構成だけで機構に合わせた:
  S2 は光球の飛翔（travel）→ 着弾の大爆発（impact、半径 1.9m の固定寸法）、刻印の炸裂は同じ爆発を再び再生し、`telegraph` を刻印の閃きにした。
  奥義は 0.2 秒の溜め（cast の `at: 0.2` でビーム）に合わせて詠唱モーションの溜めを約 0.22 秒に揃えた（後の余韻は伸ばして全体 0.5 秒）。
- スキル1 の cast は砲口の大きな閃光を一つと、前へ走る光の筋（旧: 三連の小さな閃光）。ヘッダーの古い名前（Raina式・一閃 / 星環シフト）は master の名前（遠星弾 / 星爆弾）に直した。
- スキル2 の着弾は弾が消えた位置で再生される（射程の端の爆発と同じ場所）。
- パッシブの合図は `SkillFXDirector.observe` がレンジャーの会心で推定する（ライナは会心のパッシブを持たないため通常は出ない）。App 側の仕上げ（Phase 4）で扱う。

### バランス計測（`KitBalanceTests`、Release）

- レンジャー汎用の中央値との差（勝率 %）: 見直し前 Lv1 -28.5 / Lv6 -11.6 / Lv12 -11.4（39.4 / 20.2 / 11.1 %）→ 見直し後 Lv1 -27.0 / Lv6 +0.5 / Lv12 -0.5（44.4 / 31.3 / 21.7 %、中央値 71.5 / 30.8 / 22.2 %）。
  勝率を狙った調整ではない（スキル2 の減速・射程の端の爆発・ビームの速さの変更の副産物）。Lv1 が低いのはレンジャー共通で（汎用レンジャーの中央値が Lv1 だけ高い）、帯 45 pt の内。
- 開幕 3 秒の瞬間火力（ダミー H001、同ロール汎用の中央値との比）: Lv1 0.95 / Lv6 1.33 / Lv12 1.43 倍。ビームの速さを上げても 3 秒の合計は変わらなかった（ビームは 1 回しか当たらない）。

### クールダウンを MLBB の秒数に（2026-10）

- 全体の CD 倍率 0.5 を廃止し、CD を汎用（マスター 6.5 / 7.6 / 33 秒）からライラの秒数（6 → 4 / 7.5 → 6.5 / 37・32・27 秒）にした。数値は変えていない。`KitBalanceTests`（レンジャー中央値との差）: 変更前 −29.8 / −0.3 / −1.5 → 変更後 −5.3 / −3.4 / +3.4 pt。
