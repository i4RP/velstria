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
スロットは上の調査の順に割り当てる（Skill1 = Attack Wave「Borg式・一閃」、Skill2 = Sacred Hammer「聖槌の踏み込み」、
Ultimate = Implosion「崩落聖域」、Passive = Fearless「聖鎚の誓い」）。サポートのロールだが、キットは汎用のサポートのパッシブ
（スキル使用で味方回復）と汎用の奥義（味方全体回復 + シールド）を **置き換える**（Tigreal は回復を持たない）。
距離は Velstria 単位（≈ MLBB × 100）。調査に無い値（射程・角度・詠唱の長さ・突進の距離など）は下の「選んだ値」に書いた。
ダメージ・クールダウンは Velstria 全体の係数（`Balance.Skills`）に合わせた換算で、MLBB の数値そのままではない。

### 対応表（○ = 実装、△ = 簡略化、× = 見送り）

| 元の仕様 | 状態 | Velstria での実装・理由 |
|---|---|---|
| 近接・通常攻撃・射程 1.8・ステータス（HP 2581 +307 ほか） | △ | ボルグはマスターデータの値（HP 2800 +185/Lv、攻撃 124 +6.25、防御 24、射程 150、マナ 480）。通常攻撃は汎用のまま |
| パッシブ Fearless: スキルを撃つ / 通常攻撃を受けるたびにスタック | ○ | 誓い（`ints[0]`）。スキルの初回発動（`onSkillCast`。奥義を含む）と、`modifyIncomingDamage` で見た通常攻撃（ヒーロー・タワー・ジャングルの敵 = `.basicAttack/.tower/.monster`）で +1 |
| 4 スタックで次に受ける通常攻撃を無効化（タワーの攻撃を含む）。ミニオンは数えない・防げない | ○ | 4 で準備完了。次の `.basicAttack/.tower/.monster` は被ダメ 0（防御・軽減の後、シールドの前なのでシールドも減らない）で、誓いが 0 に戻る。`.minion`・スキル・継続ダメージは数えず防げない。無効化した回数は `ints[2]` |
| ブロック時間・スタックの消える時間（不明） | △ | 選んだ値: 最後に誓いが増えてから 8 秒で全部消える（準備完了も 8 秒で消える。スキルを撃てば延びる）。無制限だとオフ戦闘で常に準備完了になるため |
| 無効化は通常攻撃のダメージだけ | △ | 攻撃に付いた CC・命中時効果は残る（ダメージを 0 にするだけ）。無効化の専用イベント・演出は無い（被ダメが出ない + 誓いのバッジが 0 に戻る） |
| 再使用（S2 の 2 段目）も「スキルを撃つ」か | △ | 数えない（`SkillSystem.cast` の再使用経路は `onSkillCast` を呼ばない）。調査に明記が無いため初回の発動のみ |
| S1 Attack Wave: 前方の扇に衝撃波が 3 回、1 回ごとにダメージ + 鈍足 20 / 40 / 60%（各 1.5 秒） | ○ | 発動の瞬間の向き・原点に固定した扇（射程 300・半角 45°）へ 0.12 / 0.32 / 0.52 秒に 3 回（`strikeSequence`）。3 回とも同じ扇に当たる。鈍足は **対象ごとに** 命中で深まる: `HitEffect.addMark`（最大 3 層・1.5 秒）→ `onHit` で `slow` 20% × 層（同じタグで大きい方に上書き）。続けて撃つと前回の層が残っていれば重なる |
| S1 ダメージ 270 → 520 + 70%（1 回ごと） | △ | 3 回ぶんの合計 = 汎用 S1 の 1.28 倍（1 回 = その 1/3。ランクは 4 段、元は 6 段）。サポートの基礎ダメージは全ロールで最低で、汎用の奥義（回復）もキットで置き換えるため、予算（0.8〜1.3 倍）の上限寄りにした |
| S1 クールダウン 7.0 → 4.0 秒、マナ 45 | △ | 7 → 4 秒をランクで線形補間 × `cooldownScale`（0.5）= 3.5 → 2.0 秒。コストはマスターのまま（55）: `SkillSystem.validate` がマスターから決めるのでキットでは変えられない |
| S1 の射程・角度・間隔（不明） | △ | 選んだ値: 射程 300（近接スキルの標準）・半角 45°（汎用の近接 S1 と同じ）・間隔 0.2 秒。撃ったあとにスタンされても衝撃波は止まらない（すでに地に走ったもの） |
| S2 Sacred Hammer 1 回目: 指定方向へ突進、通り道の敵に 100% 攻撃力のダメージ、突進の終点まで押す | ○ | `Kit.dashSweeping`（`dashStrike` として宣言、射程 420・速度 1700 = 約 0.25 秒・経路の当たり半径 100）。経路上の敵に 1 度だけダメージ（`kitEvent`）し、`onHit` で突進の向きに「終点の先 + 半径の和 + 20」まで、突進が着くまでに間に合う時間で `knockback` して押し運ぶ。CC 無効・無敵の相手は動かない（ダメージだけ）。壁の手前で止まる。突進の途中でスタンされると突進と押し出しは止まる（窓は残る） |
| S2 再使用（4 秒以内）: 前方の敵に 280 → 380 + 60% のダメージ + 打ち上げ | ○ | 同じ `castSkill`。窓（`openRecast`、4 秒・1 回）の間はコスト・CD を無視。0.2 秒の振りかぶり（`schedule`。スタンされると取り消し）の後、今いる位置から前方の扇（射程 320・半角 0.8 rad）へダメージ + `knockUp`。敵が居なくても撃てる。奥義の詠唱中は再使用できない |
| S2 打ち上げ 0.6 秒 / 1 秒（資料が割れている） | △ | 中間の 0.8 秒を採用 |
| S2 ダメージ（突進 = 攻撃力 100%、再使用 = 280 + 60%） | △ | 合計 = 汎用 S2 の 1.28 倍（理由は S1 と同じ）。突進が 30%・再使用が 70%（調査の比に近い）。1 発ごとの値は `numbers(stage:)` と説明文の `{x0}` `{x1}` |
| S2 クールダウン 16 → 13 秒、マナ 70 | △ | 16 → 13 秒をランクで線形補間 × 0.5 = 8 → 6.5 秒。**窓が閉じてから**数える（`cooldownOnClose`。1 回目の発動で CD は出るが、再使用か 4 秒の経過で閉じた瞬間に全量に戻す）。資料に開始時点の記載が無いので、再使用の窓の標準的な扱いを採用。コストはマスターのまま |
| 奥義 Implosion: 自身中心の詠唱、周囲の敵を引き寄せて 1.8 秒スタン + 600 〜 1000 + 130% | ○ | `selfAoE`・半径 420。詠唱が始まると 0.7 秒間その場から動けず（自分に `root` + 表示用の `channeling`）、攻撃も新しいスキルも始められない。0.2 秒で周囲の敵（ヒーロー・ミニオン・ジャングルの敵。構造物は除く）を術者の元へ `pull`（0.4 秒かけて集める）、0.7 秒で半径 420 の敵にダメージ + スタン 1.8 秒。引き寄せの距離が足りない相手・CC 無効（引き寄せもスタンも効かない）でも範囲内ならダメージ。爆発の瞬間に範囲の外へ出ていれば当たらない |
| 詠唱の前半は CC で中断、後半は制圧（suppress）だけで中断 | △ | 前半を「最初の 0.2 秒（溜め）」、後半を「それ以降」にした（調査に詠唱の長さは無い）。溜めの間はスタン・打ち上げ・suppress で詠唱ごと取り消し（引き寄せも爆発も起きない。クールダウンは戻らない）。それ以降はスタンでは止まらず、suppress だけが止める（`update` と爆発の `onTimer` で確認）。スロウ・沈黙では止まらない |
| 奥義 クールダウン 55 / 50 / 45 秒、マナ 120 → 160 | △ | 55 → 45 秒を 3 ランクで線形 × 0.5 = 27.5 → 22.5 秒。コストはマスター（100）のまま |
| 奥義のダメージ（600 / 800 / 1000 + 130%） | △ | 汎用のサポートの奥義はダメージ 0（回復）で比べる相手が居ないため、他ロールの奥義と同じ式（基礎 × ランク + 攻撃力 × 0.6 × 係数、× 奥義のスロット倍率）に **1.8 倍** を掛けた。クールダウンが汎用より長い（約 17 → 22〜27 秒）ぶんと、味方回復を失うぶんを補い、1v1 の勝率（下）を整える値。「単体総ダメージは汎用の 0.8〜1.3 倍」の予算は奥義には適用しない |
| 奥義の詠唱は CC に弱い（ゲームの駆け引き） | ○ | 同時に撃ち合う 1v1 では溜めの 0.2 秒に相手のスタン・ノックバックが入ると不発になる。ボットは複数の敵ヒーローを巻き込めるとき（または傷ついた相手 1 体）にだけ撃つ |

### 選んだ値（調査に無い・換算した値）

| 項目 | 値 | 理由 |
|---|---|---|
| S1 射程・半角・間隔・最初の遅れ | 300・45°・0.2 秒・0.12 秒 | 近接スキルの標準 / 汎用の近接 S1 と同じ / 衝撃波が次々に走って見える / 槌を振り下ろす前隙 |
| S2 突進 | 距離 420・速度 1700（約 0.25 秒）・経路の幅 100（半径） | 汎用の近接の突進（400・1500）より少し長く速い、盾を構えた突撃 |
| S2 押し運び | 終点の先 + 半径の和 + 20 | 押された敵が突進の終点で術者の目の前に止まる |
| S2 再使用の窓・振りかぶり・範囲 | 4 秒・0.2 秒・射程 320 / 半角 0.8 rad | 調査（4 秒）+ 突進で押し運んだ敵が確実に扇に入る広さ |
| 打ち上げ | 0.8 秒 | 資料の 0.6 秒と 1 秒の中間 |
| 奥義 詠唱 | 溜め 0.2 秒（CC で中断）、引き寄せは 0.2 秒に始まり 0.4 秒かけて集める、爆発は 0.7 秒 | 調査に長さが無い。1v1 の検証（下）で、溜めを 0.5 秒にすると同時に撃ち合う相手の最初のスタンで常に潰れ、ボルグが総当たりでほぼ勝てなくなるため短くした |
| 奥義 引き寄せ半径・止まる隙間 | 420・術者との間 20 | 近接の奥義の標準（マスターの射程 420） |
| 誓いが消える時間 | 8 秒 | 調査に不明とある |
| ダメージ倍率 | S1 1.28 / S2 1.28（合計）/ 奥義 1.8 | 上の表。サポートのマスターの基礎ダメージが最低で、汎用の味方回復の奥義を置き換えるため |
| 説明文の数値 | パッシブ x0 = 4、x1 = 8 / S1 x0..x2 = 鈍足 20・40・60、x3 = 1.5 / S2 x0 = 突進、x1 = 再使用（整数）、x2 = 打ち上げ、x3 = 窓 / 奥義 x0 = スタン 1.8、x1 = 詠唱、x2 = 溜め | `KitText` のトークン（`{x0}`〜`{x3}`）に sim の数値を入れる |

### 検証した 1v1 の目安

- `Kit_H029Tests.testDuelTimeToKillStaysInBandAgainstTheRoleRepresentatives`: H001〜H006 相手の TTK は Lv 1 / 6 / 12 とも 2.5〜15 秒。
- `Kit_H029Tests.testRoundRobinWinRateAgainstTheWholeRosterIsNotExtreme`: 全 33 体との総当たり（`SkillBalanceTests.duel`）の勝率は Lv6 33.3%（11/33）・Lv12 48.5%（16/33）（Debug / Release とも同じ）
  （この総当たりは H007 / H013 / H019 が 100% 勝つなど、ロールの外れ値が大きい。サポートのボルグは中位）。
- 汎用のボルグ（味方回復の奥義）は Lv6 48%・Lv12 67%。キットは回復を失うかわりにダメージ・CC を得たので同水準になるように調整した。

### 既知の差・リスク

- スキルのマナ（コスト）の相対関係（S1 45・S2 70・奥義 120〜160）は再現できない（マスターデータ固定: 55 / 62 / 100）。
- 奥義の詠唱の「前半 / 後半」は等分ではなく、溜め 0.2 秒（CC で中断）+ 残り 0.5 秒（suppress だけで中断）。溜めのあとにボルグがスタンされても詠唱は続き、引き寄せ・爆発は起きる（調査どおり）。
- 詠唱中の自己ルートは `root` の status（浄化で外れることがある）。外れても `update` が毎 tick 移動・攻撃の意図を消すので、詠唱は続く。CC 無効の間は `root` が付かず、移動の指示だけが毎 tick 消される。
- S2 の再使用はクールダウンを「窓が閉じてから」数えるので、再使用しなければ 1 サイクルは最長で窓の 4 秒ぶん長くなる。
- 無効化（Fearless）の専用イベントが無いため、App 側は誓いのバッジ（4 → 0）とダメージが出ないことで見せる。
- `SkillFXDirector` は stage / count / duration を読まない。S2 の演出は「cast = 突進の構え / impact = 再使用の叩きつけ（扇のアーキタイプだけ impact を再生する）」、奥義の段は `at` で表した。
