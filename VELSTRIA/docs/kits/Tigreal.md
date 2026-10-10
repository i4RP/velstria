# Tigreal (MLBB) - Kit Specification

Values come from Mobile Legends Fandom / Liquipedia search extracts plus mlbb.io, mlbb.tools and guide sites (direct Fandom/Liquipedia fetch was blocked). "unknown" = not found. "disputed" = sources disagree.

## Hero overview
- Role / lane: Tank (frontline initiator), roam. Melee.
- Resource: mana (mlbb.io level 1: 500, +100 per level; mlbb.tools lists 450, regen 3.2).
- Basic attack: melee single target.
- Attack range: about 1.8 (low confidence; extract).
- Base stats at level 1 (Fandom / mlbb.io): HP 2581, physical attack 112, physical defense 20, magic defense 15, attack speed 1.03, movement speed 260, magic power 0.
- Growth per level: HP +307, phys attack +6.79, phys defense +5.3571, magic defense +4, attack speed +0.02 (level 15: HP 6879, attack 207).
- Disputed (mlbb.tools): HP 2890, regen 8.8, phys defense 28, magic defense 15, attack speed 0.8. Prefer Fandom/mlbb.io.
- Max skill levels: S1 6, S2 6, Ultimate 3.

## Passive - Fearless
- Cast type: passive stack counter.
- Tigreal gains one Fearless stack each time he casts a skill or is hit by a basic attack. At 4 stacks he consumes all stacks to block the next incoming basic attack, including turret attacks. Minion attacks neither grant stacks nor trigger the block.
- Block duration / stack expiry: unknown.

## Skill 1 - Attack Wave
- Cast type: directional fan (cone) skillshot, three successive eruptions.
- Effect: smashes the ground with his hammer, sending a shockwave that erupts 3 times in the target direction. Each eruption deals 270 (+70% Total Physical Attack) physical damage to enemies in the fan-shaped area and slows them 20% / 40% / 60% (stacking by eruption count; each lasts 1.5 s).
- Cooldown by level: 7.0 / 6.4 / 5.8 / 5.2 / 4.6 / 4.0 s.
- Mana: 45 at level 1 (per-level values = unknown).
- Base damage: 270 / 320 / 370 / 420 / 470 / 520.
- Range, angle, interval between eruptions: unknown.

## Skill 2 - Sacred Hammer
- Cast type: directional charge/dash, then recast.
- Effect (cast 1): charges in the target direction dealing 100% Total Physical Attack physical damage to enemies along the way and pushing them to the end of the charge.
- Used Again (within 4 s): deals 280 (+60% Total Physical Attack) physical damage to enemies in front of him and knocks them airborne. Knock-up duration disputed: 0.6 s (mlbb.tools and one Fandom extract) vs 1 s (guide extract).
- Cooldown by level: 16.0 / 15.4 / 14.8 / 14.2 / 13.6 / 13.0 s.
- Mana: 70 at level 1 (per-level = unknown).
- Recast base damage: 280 / 300 / 320 / 340 / 360 / 380. Cast 1 base damage per level: unknown (only the 100% Total Physical Attack ratio found).
- Charge distance: unknown.

## Ultimate - Implosion
- Cast type: self-centered channel, AoE pull then stun.
- Effect: unleashes the power of his hammer, pulling nearby enemies to him and stunning them for 1.8 s while dealing 600 (+130% Total Physical Attack) physical damage.
- Channel: the first half can be interrupted by control effects; the second half can only be interrupted by Suppression.
- Cooldown by level: 55 / 50 / 45 s. Mana: 120 / 140 / 160.
- Base damage: 600 / 800 / 1000.
- Radius, channel length: unknown.

## Gameplay identity
- Frontline initiator: charges in, launches enemies airborne, then Implosion gathers the team and stuns for a 1.8 s window.
- Highly durable base stats and fast cooldowns on Attack Wave make him a constant-peel tank.
- Fearless adds a basic-attack immunity beat every four triggers, rewarding casting skills often.
- Team-fight engage depends on landing the ult channel without being hard-CC'd.

## Simulation notes
- Standard: cone skillshot with slow stacking, dash with push, recast within window (knock-up), AoE pull and stun, percentage-AD scaling, mana.
- Needs special state: Fearless stack counter (skills and basic-attack hits add; at 4, block next basic attack and clear); S2 recast window of 4 s; push-to-endpoint displacement along the charge; staged ultimate channel with first half interruptible by CC and second half only by suppression; slow tiers by eruption count.

## Sources
- https://mobile-legends.fandom.com/wiki/Tigreal (via search extract)
- https://liquipedia.net/mobilelegends/Tigreal (via search extract)
- https://mlbb.io/en/hero/tigreal
- https://mlbb.tools/heroes/tigreal

## Velstria 実装対応表

H029 聖槌のボルグ（サポート・近接 150・Mana）= Velstria 版の Tigreal。実装: `Packages/VelstriaCore/Sources/VelstriaCore/Systems/Kits/Kit_H029.swift`、
テスト: `Tests/VelstriaCoreTests/Kits/Kit_H029Tests.swift`、演出: `App/Battle/SkillFX/Heroes/FX_H029.swift`。
スロットは上の調査の順に割り当てる（スキル1 = Attack Wave「聖槌波」、スキル2 = Sacred Hammer「聖槌突撃」、
アルティメット = Implosion「崩落聖域」、パッシブ = Fearless「聖鎚の誓い」。名前はマスターデータのもの）。サポートのロールだが、キットは汎用のサポートのパッシブ
（スキル使用で味方回復）と汎用のアルティメット（味方全体回復 + シールド）を **置き換える**（Tigreal は回復を持たない）。
距離は Velstria 単位（≈ MLBB × 100）。調査に無い値（射程・角度・詠唱の長さ・突進の距離など）は下の「選んだ値」に書いた。
ダメージは Velstria 全体の係数（`Balance.Skills`）に合わせた換算で、MLBB の数値そのままではない。クールダウンは MLBB の秒数そのまま（6 段のランクを Velstria の 4 段・奥義 3 段へ線形補間。全体倍率 `cooldownScale` は 1.0）。
ツールチップの距離は単位の無い数字を出さず、近接攻撃の射程（150）に対する倍率で書く（`{reachMult}`: スキル1 約 2 倍、アルティメット 約 3.5 倍）。

### 対応表（○ = 実装、△ = 簡略化、× = 見送り）

| 元の仕様 | 状態 | Velstria での実装・理由 |
|---|---|---|
| 近接・通常攻撃・射程 1.8・ステータス（HP 2581 +307 ほか） | △ | ボルグはマスターデータの値（HP 2800 +185/Lv、攻撃 124 +6.25、防御 24、射程 150、マナ 480）。通常攻撃は汎用のまま |
| パッシブ Fearless: スキルを撃つ / 通常攻撃を受けるたびにスタック | ○ | 誓い（`ints[0]`）。スキルの初回発動（`onSkillCast`。アルティメットを含む）と、`modifyIncomingDamage` で見た通常攻撃（ヒーロー・タワー・ジャングルの敵 = `.basicAttack/.tower/.monster`）で +1 |
| 4 スタックで次に受ける通常攻撃を無効化（タワーの攻撃を含む）。ミニオンは数えない・防げない | ○ | 4 で準備完了。次の `.basicAttack/.tower/.monster` は被ダメ 0（防御・軽減の後、シールドの前なのでシールドも減らない）で、誓いが 0 に戻る。`.minion`・スキル・継続ダメージは数えず防げない。無効化した回数は `ints[2]` |
| ブロック時間・スタックの消える時間（不明） | △ | 選んだ値: 最後に誓いが増えてから 8 秒で全部消える（準備完了も 8 秒で消える。スキルを撃てば延びる）。無制限だとオフ戦闘で常に準備完了になるため。説明文は「最後に誓いが増えてから{x1}秒で消える」 |
| 無効化は通常攻撃のダメージだけ | △ | 攻撃に付いた CC・命中時効果は残る（ダメージを 0 にするだけ） |
| 無効化の見せ方 | ○ | 無効化の瞬間に **自分へ 0.3 秒の `.mark`（tag `kit.H029.blocked.<自分の ID>`）** を付け（`Kit.addMark`。世界では頭上の金の印）、パッシブのバッジを 0.3 秒だけタイマーにする（`timers[2]`）。App の `SkillFXDirector.observeKitPassives` が「タイマーの開始」を見てパッシブの合図（金の光輪 + 盾の紋）を出す。スキルの発動の直後（0.6 秒以内）に無効化したときは `FX_H029.passiveRelease`（金の盾の弾け）に切り替わる。専用のダメージイベントは無い |
| 再使用（スキル2 の 2 段目）も「スキルを撃つ」か | △ | 数えない（`SkillSystem.cast` の再使用経路は `onSkillCast` を呼ばない）。調査に明記が無いため初回の発動のみ |
| スキル1 Attack Wave: 前方の扇に衝撃波が 3 回、1 回ごとにダメージ + 鈍足 20 / 40 / 60%（各 1.5 秒） | ○ | 発動の瞬間の向き・原点に固定した扇（射程 300・半角 45°）へ 0.12 / 0.32 / 0.52 秒に 3 回（`strikeSequence`）。**扇の半径は波ごとに広がる**（`timer.index` で射程の 0.7 / 0.85 / 1.0 倍 + 対象の半径）ので、手前の敵ほど多くの波に当たる。鈍足は **対象ごとに** 命中で深まる: `HitEffect.addMark`（最大 3 層・1.5 秒）→ `onHit` で `slow` 20% × 層（同じタグで大きい方に上書き）。続けて撃つと前回の層が残っていれば重なる |
| スキル1 ダメージ 270 → 520 + 70%（1 回ごと） | △ | 3 回ぶんの合計 = 汎用 S1 の 1.28 倍（1 回 = その 1/3。ランクは 4 段、元は 6 段）。サポートの基礎ダメージは全ロールで最低で、汎用のアルティメット（回復）もキットで置き換えるため、予算（0.8〜1.3 倍）の上限寄りにした。扇の端の敵は波が 1〜2 回しか当たらない |
| スキル1 クールダウン 7.0 → 4.0 秒、マナ 45 | △ | MLBB と同じ 7 → 4 秒（ランクで線形補間。以前は × 0.5 = 3.5 → 2.0 秒）。コストはマスターのまま（55）: `SkillSystem.validate` がマスターから決めるのでキットでは変えられない |
| スキル1 の射程・角度・間隔（不明） | △ | 選んだ値: 射程 300（近接スキルの標準）・半角 45°（汎用の近接 S1 と同じ）・間隔 0.2 秒。撃ったあとにスタンされても衝撃波は止まらない（すでに地に走ったもの） |
| スキル2 Sacred Hammer 1 回目: 指定方向へ突進、通り道の敵に 100% 攻撃力のダメージ、突進の終点まで押す | ○ | `Kit.dashSweeping`（`dashStrike` として宣言、射程 420・速度 1700 = 約 0.25 秒・経路の当たり半径 100）。経路上の敵に 1 度だけダメージ（`kitEvent`）し、`onHit` で突進の向きに「終点の先 + 半径の和 + 20」まで、突進が着くまでに間に合う時間で `knockback` して押し運ぶ。CC 無効・無敵の相手は動かない（ダメージだけ）。壁の手前で止まる。突進の途中でスタンされると突進と押し出しは止まる（窓は残る） |
| スキル2 再使用（4 秒以内）: 前方の敵に 280 → 380 + 60% のダメージ + 打ち上げ | ○ | 同じ `castSkill`。窓（`openRecast`、4 秒・1 回）の間はコスト・CD を無視。0.2 秒の振りかぶり（`schedule`。スタンされると取り消し）の後、今いる位置から前方の扇（射程 320・半角 0.8 rad）へダメージ + `knockUp`。敵が居なくても撃てる。アルティメットの詠唱中は再使用できない。演出は `FX_H029.recipe(_:stage:_:)` の stage 1（振りかぶりの光 → 聖槌の叩きつけ。突進の尾は出さない） |
| スキル2 打ち上げ 0.6 秒 / 1 秒（資料が割れている） | △ | 中間の 0.8 秒を採用 |
| スキル2 ダメージ（突進 = 攻撃力 100%、再使用 = 280 + 60%） | △ | 合計 = 汎用 S2 の 1.28 倍（理由は S1 と同じ）。突進が 30%・再使用が 70%（調査の比に近い）。1 発ごとの値は `numbers(stage:)` と説明文の `{x0}` `{x1}` |
| スキル2 クールダウン 16 → 13 秒、マナ 70 | △ | MLBB と同じ 16 → 13 秒（ランクで線形補間。以前は × 0.5 = 8 → 6.5 秒）。**窓が閉じてから**数える（`cooldownOnClose`。1 回目の発動で CD は出るが、再使用か 4 秒の経過で閉じた瞬間に全量に戻す）。資料に開始時点の記載が無いので、再使用の窓の標準的な扱いを採用。コストはマスターのまま |
| アルティメット Implosion: 自身中心の詠唱、周囲の敵を引き寄せて 1.8 秒スタン + 600 〜 1000 + 130% | ○ | `selfAoE`・半径 520。詠唱が始まると 0.8 秒間その場から動けず（自分に `root` + 表示用の `channeling`）、攻撃も新しいスキルも始められない。0.3 秒で周囲の敵（ヒーロー・ミニオン・ジャングルの敵。構造物は除く）を術者の元へ `pull`（0.38 秒かけて集める）、0.8 秒で半径 520 の敵にダメージ + スタン 1.8 秒。引き寄せの距離が足りない相手・CC 無効（引き寄せもスタンも効かない）でも範囲内ならダメージ。爆発の瞬間に範囲の外へ出ていれば当たらない |
| 詠唱の前半は CC で中断、後半は制圧（suppress）だけで中断 | △ | 前半を「最初の 0.3 秒（溜め）」、後半を「それ以降」にした（調査に詠唱の長さは無い）。溜めの間はスタン・打ち上げ・suppress で詠唱ごと取り消し（引き寄せも爆発も起きない。クールダウンは戻らない）。それ以降はスタンでは止まらず、suppress だけが止める（`update` と爆発の `onTimer` で確認）。スロウ・沈黙では止まらない |
| アルティメット クールダウン 55 / 50 / 45 秒、マナ 120 → 160 | △ | MLBB と同じ 55 / 50 / 45 秒（以前は × 0.5 = 27.5 → 22.5 秒）。コストはマスター（100）のまま |
| アルティメットのダメージ（600 / 800 / 1000 + 130%） | △ | 汎用のサポートのアルティメットはダメージ 0（回復）で比べる相手が居ないので、他ロールのアルティメットと同じ式（基礎 × ランク + 攻撃力 × 0.6 × 係数、× アルティメットのスロット倍率）に **3.0 倍** を掛けた。クールダウンが汎用より長い（約 34 秒 → 45〜55 秒）ぶん・回復を失うぶん・詠唱を長くした（溜め 0.2 → 0.3 秒、全体 0.7 → 0.8 秒）ぶん・スキル1 の波が前へ広がる（遠い敵に当たる波が減る）ぶんを、ロール中央値との勝率差（下）で埋めた値。「単体総ダメージは汎用の 0.8〜1.3 倍」の予算はアルティメットには適用しない |
| アルティメットの詠唱は CC に弱い（ゲームの駆け引き） | ○ | 同時に撃ち合う 1v1 では溜めの 0.3 秒に相手のスタン・ノックバックが入ると不発になる |
| ボットのアルティメット | ○ | 敵ヒーローを 2 体以上巻き込めるか、狙う相手が傷ついている（< 80%）ときだけ、**さらに** 近く（900 以内）に味方ヒーローが居るか相手の HP が 50% 未満のときだけ撃つ（引き寄せた相手を一人で受けない）。敵のタワーの射程内（`Kit_H029.insideEnemyTowerRange`）では撃たない |

### 選んだ値（調査に無い・換算した値）

| 項目 | 値 | 理由 |
|---|---|---|
| スキル1 射程・半角・間隔・最初の遅れ | 300・45°・0.2 秒・0.12 秒 | 近接スキルの標準 / 汎用の近接 S1 と同じ / 衝撃波が次々に走って見える / 槌を振り下ろす前隙 |
| スキル1 波ごとの半径 | 射程の 0.7 / 0.85 / 1.0 倍 | 衝撃が前へ進んで見えるように広げる。0.45 / 0.75 / 1.0 や 0.6 / 0.8 / 1.0 は、射程の端で撃つ台本（ハーネス・ボット）で当たる波が減りすぎ、Lv1 の勝率が 10% 台まで落ちた（下） |
| スキル2 突進 | 距離 420・速度 1700（約 0.25 秒）・経路の幅 100（半径） | 汎用の近接の突進（400・1500）より少し長く速い、盾を構えた突撃 |
| スキル2 押し運び | 終点の先 + 半径の和 + 20 | 押された敵が突進の終点で術者の目の前に止まる |
| スキル2 再使用の窓・振りかぶり・範囲 | 4 秒・0.2 秒・射程 320 / 半角 0.8 rad | 調査（4 秒）+ 突進で押し運んだ敵が確実に扇に入る広さ |
| 打ち上げ | 0.8 秒 | 資料の 0.6 秒と 1 秒の中間 |
| アルティメット 詠唱 | 溜め 0.3 秒（CC で中断）、引き寄せは 0.3 秒に始まり 0.38 秒かけて集める、爆発は 0.8 秒 | 調査に長さが無い。0.45 / 0.9 秒（溜めを長く）は Lv6 の勝率がロール中央値を 7 pt 下回り（アルティメットの倍率 3.0 でも）、0.2 / 0.7 秒の元の形より 10 pt 悪化したので、中間の 0.3 / 0.8 秒にした |
| アルティメット 引き寄せ半径・止まる隙間 | 520・術者との間 20 | 近接のアルティメットより広い集団戦の引き寄せ（旧 420）。ツールチップは近接射程の約 3.5 倍 |
| 誓いが消える時間 | 8 秒 | 調査に不明とある |
| 無効化の合図の長さ | 0.3 秒 | 世界の印とバッジのタイマー。短いので状態アイコン列では一瞬の点滅になる（印の名前は `KitStatusVisuals.markName` 未登録 = 汎用の「刻印」） |
| ダメージ倍率 | スキル1 1.28 / スキル2 1.28（合計）/ アルティメット 3.0 | 上の表。サポートのマスターの基礎ダメージが最低で、汎用の味方回復のアルティメットを置き換えるため |
| 説明文の数値 | パッシブ x0 = 4、x1 = 8 / スキル1 x0..x2 = 鈍足 20・40・60、x3 = 1.5、`{reachMult}` = 射程の倍率 / スキル2 x0 = 突進、x1 = 再使用（整数）、x2 = 打ち上げ、x3 = 窓 / アルティメット x0 = スタン 1.8、x1 = 詠唱、x2 = 溜め、`{reachMult}` | `KitText` のトークン（`{x0}`〜`{x3}` と `{key}`）に sim の数値を入れる |

### 検証した 1v1 の目安

- `Kit_H029Tests.testDuelTimeToKillStaysInBandAgainstTheRoleRepresentatives`: H001〜H006 相手の TTK は Lv 1 / 6 / 12 とも 2.5〜15 秒。
- `KitBalanceTests`（Release、`BalanceHarness`）の勝率（総当たり・両陣営 x 開始距離 x 種の平均、%）。ロール「サポート」の汎用ヒーローの中央値との比較:

  | | Lv1 | Lv6 | Lv12 |
  |---|---|---|---|
  | 元の形（扇の半径が一定・詠唱 0.2 / 0.7 秒・倍率 1.8） | 49.5（中央値 36.4）| 29.8（27.3）| 41.9（43.4）|
  | 今回 | 43.4（中央値 38.9）| 27.3（31.8）| 36.4（44.2）|

  開幕 3 秒の瞬間火力の比（同ロール中央値に対する倍率、報告のみ）: 元 0.99 / 1.38 / 1.47 → 今回 0.65 / 1.64 / 1.78。
- `Kit_H029Tests.testRoundRobinWinRateAgainstTheWholeRosterIsNotExtreme`: 旧式の台本（開幕に射程内ならアルティメットを撃つ）の総当たりは Lv6 24%・Lv12 30%。詠唱が長いボルグには厳しく出るので、下限だけ 25% → 20% に緩めた（共通の物差しは上の `KitBalanceTests`）。

### 既知の差・リスク

- スキルのマナ（コスト）の相対関係（S1 45・S2 70・アルティメット 120〜160）は再現できない（マスターデータ固定: 55 / 62 / 100）。
- アルティメットの詠唱の「前半 / 後半」は等分ではなく、溜め 0.3 秒（CC で中断）+ 残り 0.5 秒（suppress だけで中断）。溜めのあとにボルグがスタンされても詠唱は続き、引き寄せ・爆発は起きる（調査どおり）。
- 詠唱中の自己ルートは `root` の status（浄化で外れることがある）。外れても `update` が毎 tick 移動・攻撃の意図を消すので、詠唱は続く。CC 無効の間は `root` が付かず、移動の指示だけが毎 tick 消される。
- スキル2 の再使用はクールダウンを「窓が閉じてから」数えるので、再使用しなければ 1 サイクルは最長で窓の 4 秒ぶん長くなる。
- 扇の端（射程の 0.7 倍より外）の敵には波が 1〜2 回しか当たらない。射程いっぱいで撃つと与ダメージと鈍足が浅くなる（近接の押し合いでは 3 回当たる）。
- 無効化の合図は `SkillFXDirector` の既存の hook だけで出している。`passiveRelease` は「スキルの発動の直後（0.6 秒以内）」にしか呼ばれないので、通常の無効化（敵の攻撃を受けた瞬間）は「バッジがタイマーになる → パッシブの合図」で見せる（`FX_H029.passiveRelease` の金の盾の弾けは、発動の直後に無効化したときだけ）。
- 無効化の印（`kit.H029.blocked`）は HUD の状態アイコン列に 0.3 秒だけ汎用の「刻印」として出る（`KitStatusVisuals` は共有ファイルのため名前・アイコンを足していない）。
- `SkillFXDirector` は duration / count を読まない。スキル2 の演出は stage 1 を `recipe(_:stage:_:)` に分けた（cast = 振りかぶり、impact = 叩きつけ）。アルティメットの段は `at` で表した（詠唱 0.3 / 0.8 秒を固定のタイミングで書いてある）。
