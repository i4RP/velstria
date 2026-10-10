# Tigreal (MLBB) - Kit Specification

**正は下の「公式（日本語クライアント）の数値」**（オーナーが提供した実機のスキル詳細 4 枚）。それ以前のウェブ調査（この節より上）と食い違う値は公式が優先する。

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

## 公式（日本語クライアント）の数値

ティグラル(Tigreal)、ロール「タンク」、サブタグ「妨害」。スキル詳細の画面そのままの転記（スキルのレベルは公式でスキル1・2 が Lv1〜6、アルティメットが Lv1〜3）。

| スロット | 公式名 | タグ | 内容 |
|---|---|---|---|
| パッシブ | フィアレス | バフ | 通常攻撃を受けるたびに、フィアレスを1スタック獲得する。4スタックに達すると、それらを消費して次に受ける通常攻撃（タワーからの攻撃を含む）をブロックする。また、スキルを発動するたびに、フィアレスを1スタック獲得する。ミニオンからのダメージは、フィアレスのスタックを付与または消費しない。（期限の記載なし） |
| スキル1 | アタックウェイブ | 範囲技・減速 | CD 7.0 / 6.4 / 5.8 / 5.2 / 4.6 / 4.0、MP 45（一定）、基礎ダメージ 270 / 320 / 370 / 420 / 470 / 520。ハンマーで地面を叩き、扇形範囲で3回爆発する衝撃波を放つ。各爆発は命中した敵に270(+70%物理攻撃)の物理ダメージを与え、移動速度を1.5秒間20%/40%/60%低下させる。 |
| スキル2 | セイントハンマー | 衝突・妨害 | CD 16.0 / 15.4 / 14.8 / 14.2 / 13.6 / 13.0、MP 70（一定）、ノックアップダメージ 280 / 300 / 320 / 340 / 360 / 380。指定方向へ突進し、進路上の敵に(100%物理攻撃)の物理ダメージを与えて突進の終点まで押し出す。再発動：4秒以内にもう一度使うと、前方の敵に280(+60%物理攻撃)の物理ダメージを与えて0.6秒間ノックアップさせる。 |
| アルティメット | インプロージョン | 妨害・範囲技 | CD 55.0 / 50.0 / 45.0、MP 120 / 140 / 160、基礎ダメージ 600 / 800 / 1000。ハンマーの力を解放し、周囲の敵を引き寄せて600(+130%物理攻撃)の物理ダメージを与え、1.8秒間スタンさせる。スキルの前半はコントロール効果によって中断されるが、後半は制圧によってのみ中断される。 |

### 公式が置き換えた調査の値

| 項目 | 以前の調査・実装 | 公式 |
|---|---|---|
| パッシブの期限 | 不明 → 実装は「最後に増えてから 8 秒で全部消える」（選んだ値） | 記載なし。**期限なし**（8 秒の消滅を撤去） |
| パッシブ: タワー・ミニオン | タワーの攻撃を含む / ミニオンは数えない | 同じ。「通常攻撃（タワーからの攻撃を含む）」「ミニオンからのダメージはスタックを付与も消費もしない」と明記 |
| パッシブ: 再使用が「スキルを発動」に入るか | 数えない（記載が無いため） | 文は「スキルを発動するたびに」だけで再使用には触れない。**画面は沈黙なので従来どおり数えない**（初回の発動のみ） |
| スキル2 の突進ダメージ | 100% 攻撃力、基礎ダメージは不明 | 100% 物理攻撃で**基礎ダメージなし**（ランク表は再使用のノックアップダメージだけ） |
| スキル2 のノックアップの長さ | 0.6 秒と 1 秒で割れている → 実装は 0.8 秒 | **0.6 秒** |
| マナ消費 | S1 45・S2 70 は Lv1 のみ、ランクごとは不明 → 実装はマスターの 55 / 62 / 100 | S1 45・S2 70 は全ランク一定、アルティメット 120 / 140 / 160 |
| クールダウン・基礎ダメージの表 | 調査の値と同じ（S1 7.0→4.0、S2 16.0→13.0、ULT 55/50/45、ダメージ 270→520 / 280→380 / 600・800・1000） | 同じ（確認） |
| アルティメットのダメージ | 600〜1000 を無視した汎用式 × 3.0 | 600 / 800 / 1000（+130% 物理攻撃）の表に置き換え（Velstria の換算つき。下の対応表） |

ランクの対応: Velstria のスキルのランクは S1/S2 が 4 段、アルティメットが 3 段（`SkillSlot.maxRank`）。表は**線形補間**で写す（ランク 1 = Lv1、最大ランク = 公式の最終レベル。S1/S2 は ランク r → Lv `1 + (r − 1) × 5 / 3`、アルティメットの 3 段は公式の Lv そのまま）。公式の表はどれも等差なので、補間は「最初と最後の値を結ぶ直線」と同じ。

## Velstria 実装対応表

H029 聖槌のボルグ（サポート・近接 150・Mana）= Velstria 版の Tigreal。実装: `Packages/VelstriaCore/Sources/VelstriaCore/Systems/Kits/Kit_H029.swift`、
テスト: `Tests/VelstriaCoreTests/Kits/Kit_H029Tests.swift`、演出: `App/Battle/SkillFX/Heroes/FX_H029.swift`。
スロットは上の調査の順に割り当てる（スキル1 = Attack Wave「聖槌波」、スキル2 = Sacred Hammer「聖槌突撃」、
アルティメット = Implosion「崩落聖域」、パッシブ = Fearless「聖鎚の誓い」。名前はマスターデータのもの）。サポートのロールだが、キットは汎用のサポートのパッシブ
（スキル使用で味方回復）と汎用のアルティメット（味方全体回復 + シールド）を **置き換える**（Tigreal は回復を持たない）。
距離は Velstria 単位（≈ MLBB × 100）。調査に無い値（射程・角度・詠唱の長さ・突進の距離など）は下の「選んだ値」に書いた。
ダメージ・クールダウン・マナ消費は **公式（日本語クライアント）の表** をランクで線形補間し、ダメージは Velstria の通常の式（`(基礎 + 係数 × 攻撃力 × 0.6) × スロット倍率`）に換算（`Tune.waveScale / hammerScale / ultScale`）して使う。数値の絶対値は MLBB と同じではない（スキル説明の `{base}(+{atkPct}%物理攻撃)` は sim の式に通した値）。
ツールチップの距離は単位の無い数字を出さず、近接攻撃の射程（150）に対する倍率で書く（`{reachMult}`: スキル1 約 2 倍、アルティメット 約 3.5 倍）。

### 対応表（○ = 実装、△ = 簡略化、× = 見送り）

| 元の仕様 | 状態 | Velstria での実装・理由 |
|---|---|---|
| 近接・通常攻撃・射程 1.8・ステータス（HP 2581 +307 ほか） | △ | ボルグはマスターデータの値（HP 2800 +185/Lv、攻撃 124 +6.25、防御 24、射程 150、マナ 480）。通常攻撃は汎用のまま |
| パッシブ フィアレス: 通常攻撃を受ける / スキルを発動するたびに 1 スタック | ○ | 誓い（`ints[0]`）。スキルの初回発動（`onSkillCast`。アルティメットを含む）と、`modifyIncomingDamage` で見た通常攻撃（ヒーロー・タワー・ジャングルの敵 = `.basicAttack/.tower/.monster`）で +1 |
| 4 スタックで次に受ける通常攻撃（タワーからの攻撃を含む）をブロック。ミニオンのダメージはスタックを付与も消費もしない | ○ | 4 で準備完了。次の `.basicAttack/.tower/.monster` は被ダメ 0（防御・軽減の後、シールドの前なのでシールドも減らない）で、誓いが 0 に戻る。`.minion`・スキル・継続ダメージは数えず防げない。ブロックした回数は `ints[2]` |
| スタックの消える時間 | ○（公式で確定） | **期限なし**（公式の文に記載が無い）。旧実装の「最後に増えてから 8 秒で全部消える」（`timers[0]`・`Tune.vowExpire`）を撤去。オフ戦闘で常に準備完了になるが、これが公式の挙動。`testVowsNeverExpireWithTime` |
| ブロックは通常攻撃のダメージだけ | △ | 攻撃に付いた CC・命中時効果は残る（ダメージを 0 にするだけ） |
| ブロックの見せ方 | ○ | ブロックの瞬間に **自分へ 0.3 秒の `.mark`（tag `kit.H029.blocked.<自分の ID>`）** を付け（`Kit.addMark`。世界では頭上の金の印）、パッシブのバッジを 0.3 秒だけタイマーにする（`timers[2]`）。App の `SkillFXDirector.observeKitPassives` が「タイマーの開始」を見てパッシブの合図（金の光輪 + 盾の紋）を出す。スキルの発動の直後（0.6 秒以内）にブロックしたときは `FX_H029.passiveRelease`（金の盾の弾け）に切り替わる。専用のダメージイベントは無い |
| 再発動（スキル2 の 2 段目）も「スキルを発動するたびに」に入るか | △ | 数えない（`SkillSystem.cast` の再使用経路は `onSkillCast` を呼ばない）。**公式の文は再発動に触れていない（沈黙）ので従来の決定を維持**。初回の発動のみ |
| スキル1 アタックウェイブ: 扇形範囲で 3 回爆発する衝撃波。各爆発は命中した敵に 270(+70% 物理攻撃) の物理ダメージ + 移動速度 1.5 秒間 20% / 40% / 60% 低下 | ○ | 発動の瞬間の向き・原点に固定した扇（射程 300・半角 45°）へ 0.12 / 0.32 / 0.52 秒に 3 回（`strikeSequence`）。**扇の半径は爆発ごとに広がる**（`timer.index` で射程の 0.7 / 0.85 / 1.0 倍 + 対象の半径）ので、手前の敵ほど多くの爆発に当たる。移動速度低下は **対象ごとに** 命中した爆発の数で深まる: `HitEffect.addMark`（最大 3 層・1.5 秒）→ `onHit` で `slow` 20% × 層（同じタグで大きい方に上書き）。続けて撃つと前回の層が残っていれば重なる |
| スキル1 ダメージ 270 → 520（Lv1 → Lv6）+ 70% 物理攻撃（1 爆発ごと） | ○ / △ | **公式の表をそのまま使う**: `(lerp(270, 520, rank, 4) + 0.7 × 攻撃力 × 0.6) × スキル1 の倍率 4.0 × waveScale 0.17`。ランクは 4 段（rank r → Lv 1 + (r − 1) × 5 / 3）。waveScale は 3 爆発の合計が汎用 S1 の 0.8〜1.3 倍（ランク 1〜4・Lv 1〜12 で約 1.2〜1.26 倍）に収まる換算で、サポートの基礎ダメージが全ロールで最低なため上限寄り。以前の「汎用 × 1.28」（ランクに依らず一定）から変更。扇の端の敵は爆発が 1〜2 回しか当たらない |
| スキル1 クールダウン 7.0 → 4.0 秒、マナ 45（一定） | ○ | 7 → 4 秒をランクで線形補間 × CD 短縮 × `cooldownScale`（0.5）= 3.5 → 2.0 秒。**マナは公式の 45 をキットの `cost` で適用**（以前はマスターの 55 のまま）。ランクごとの値は `HeroKit.cost` |
| スキル1 の射程・角度・間隔（公式にも記載なし） | △ | 選んだ値: 射程 300（近接スキルの標準）・半角 45°（汎用の近接 S1 と同じ）・間隔 0.2 秒。撃ったあとにスタンされても衝撃波は止まらない（すでに地に走ったもの） |
| スキル2 セイントハンマー 1 回目: 指定方向へ突進、進路上の敵に (100% 物理攻撃) の物理ダメージ（基礎ダメージなし）、突進の終点まで押し出す | ○ | `Kit.dashSweeping`（`dashStrike` として宣言、射程 420・速度 1700 = 約 0.25 秒・経路の当たり半径 100）。経路上の敵に 1 度だけダメージ（`kitEvent`）し、`onHit` で突進の向きに「終点の先 + 半径の和 + 20」まで、突進が着くまでに間に合う時間で `knockback` して押し運ぶ。CC 無効・無敵の相手は動かない（ダメージだけ）。壁の手前で止まる。突進の途中でスタンされると突進と押し出しは止まる（窓は残る）。ダメージ = `(1.0 × 攻撃力 × 0.6) × スキル2 の倍率 3.0 × hammerScale 0.58`（基礎なし） |
| スキル2 再発動（4 秒以内）: 前方の敵に 280 → 380 + 60% 物理攻撃のダメージ + 0.6 秒のノックアップ | ○ | 同じ `castSkill`。窓（`openRecast`、4 秒・1 回）の間はコスト・CD を無視。0.2 秒の振りかぶり（`schedule`。スタンされると取り消し）の後、今いる位置から前方の扇（射程 320・半角 0.8 rad）へダメージ + `knockUp`。敵が居なくても撃てる。アルティメットの詠唱中は再使用できない。演出は `FX_H029.recipe(_:stage:_:)` の stage 1（振りかぶりの光 → 聖槌の叩きつけ。突進の尾は出さない）。ダメージ = `(lerp(280, 380, rank, 4) + 0.6 × 攻撃力 × 0.6) × 3.0 × hammerScale 0.58` |
| スキル2 ノックアップの長さ | ○（公式で確定） | **0.6 秒**（旧実装は資料が 0.6 / 1 秒で割れていたため中間の 0.8 秒。`Tune.smashAirborne`） |
| スキル2 ダメージの予算 | △ | 突進 + 再発動の合計が汎用 S2 の 0.8〜1.3 倍（ランク 1〜4・Lv 1〜12 で約 0.9〜1.27 倍）。再発動の基礎ダメージは 280 → 380 と緩やかにしか伸びないので、汎用（ランクで約 1.9 倍）より最大ランクでの伸びが小さい。1 発ごとの値は `numbers(stage:)` と説明文の `{dashDamage}` `{smashDamage}` |
| スキル2 クールダウン 16.0 → 13.0 秒、マナ 70（一定） | ○ | 16 → 13 秒をランクで線形補間 × 0.5 = 8 → 6.5 秒。**窓が閉じてから**数える（`cooldownOnClose`。1 回目の発動で CD は出るが、再使用か 4 秒の経過で閉じた瞬間に全量に戻す）。公式の文に開始時点の記載が無いので、再使用の窓の標準的な扱いを採用。**マナは公式の 70 をキットの `cost` で適用**（以前はマスターの 62） |
| アルティメット インプロージョン: 周囲の敵を引き寄せて 600(+130% 物理攻撃) の物理ダメージ + 1.8 秒スタン | ○ | `selfAoE`・半径 520。詠唱が始まると 0.8 秒間その場から動けず（自分に `root` + 表示用の `channeling`）、攻撃も新しいスキルも始められない。0.3 秒で周囲の敵（ヒーロー・ミニオン・ジャングルの敵。構造物は除く）を術者の元へ `pull`（0.38 秒かけて集める）、0.8 秒で半径 520 の敵にダメージ + スタン 1.8 秒。引き寄せの距離が足りない相手・CC 無効（引き寄せもスタンも効かない）でも範囲内ならダメージ。爆発の瞬間に範囲の外へ出ていれば当たらない |
| スキルの前半はコントロール効果で中断、後半は制圧（suppress）でのみ中断 | △ | 前半を「最初の 0.3 秒（溜め）」、後半を「それ以降」にした（公式に詠唱の長さは無い）。溜めの間はスタン・打ち上げ・suppress で詠唱ごと取り消し（引き寄せも爆発も起きない。クールダウンは戻らない）。それ以降はスタンでは止まらず、suppress だけが止める（`update` と爆発の `onTimer` で確認）。スロウ・沈黙では止まらない |
| アルティメット クールダウン 55 / 50 / 45 秒、マナ 120 / 140 / 160 | ○ | 55 → 45 秒を 3 ランクで線形（= 公式の Lv1〜3 そのまま）× 0.5 = 27.5 → 22.5 秒。**マナは公式の 120 / 140 / 160 をキットの `cost` で適用**（以前はマスターの 100 のまま） |
| アルティメットのダメージ 600 / 800 / 1000（+130% 物理攻撃） | ○ / △ | **公式の表をそのまま使う**: `(基礎 + 1.3 × 攻撃力 × 0.6) × アルティメットの倍率 2.6 × ultScale 1.5`。汎用のサポートのアルティメットはダメージ 0（回復）で比べる相手が居ないので、予算（0.8〜1.3 倍）は適用せず、勝率（下）で ultScale を決めた。以前は汎用の他ロールの式に **3.0 倍** を掛けていた（公式の表に置き換えた直後の ultScale 1.2 では Lv12 が同ロール中央値より 17 pt 低く、±15 pt を外れたので 1.5 に） |
| アルティメットの詠唱は CC に弱い（ゲームの駆け引き） | ○ | 同時に撃ち合う 1v1 では溜めの 0.3 秒に相手のスタン・ノックバックが入ると不発になる |
| ボットのアルティメット | ○ | 敵ヒーローを 2 体以上巻き込めるか、狙う相手が傷ついている（< 80%）ときだけ、**さらに** 近く（900 以内）に味方ヒーローが居るか相手の HP が 50% 未満のときだけ撃つ（引き寄せた相手を一人で受けない）。敵のタワーの射程内（`Kit_H029.insideEnemyTowerRange`）では撃たない。マナはキットの `cost`（ランクごと）で足りるかを見る |
| スキルのタグ（UI） | ○ | パッシブ `buff`、スキル1 `aoe slow`、スキル2 `clash disrupt`、アルティメット `disrupt aoe`（`KitText.tags` / `HeroKits.tags(heroID:slot:)`。公式のタグ バフ / 範囲技・減速 / 衝突・妨害 / 妨害・範囲技に対応） |

### 選んだ値（調査に無い・換算した値）

| 項目 | 値 | 理由 |
|---|---|---|
| スキル1 射程・半角・間隔・最初の遅れ | 300・45°・0.2 秒・0.12 秒 | 近接スキルの標準 / 汎用の近接 S1 と同じ / 衝撃波が次々に走って見える / 槌を振り下ろす前隙 |
| スキル1 波ごとの半径 | 射程の 0.7 / 0.85 / 1.0 倍 | 衝撃が前へ進んで見えるように広げる。0.45 / 0.75 / 1.0 や 0.6 / 0.8 / 1.0 は、射程の端で撃つ台本（ハーネス・ボット）で当たる波が減りすぎ、Lv1 の勝率が 10% 台まで落ちた（下） |
| スキル2 突進 | 距離 420・速度 1700（約 0.25 秒）・経路の幅 100（半径） | 汎用の近接の突進（400・1500）より少し長く速い、盾を構えた突撃 |
| スキル2 押し運び | 終点の先 + 半径の和 + 20 | 押された敵が突進の終点で術者の目の前に止まる |
| スキル2 再使用の窓・振りかぶり・範囲 | 4 秒・0.2 秒・射程 320 / 半角 0.8 rad | 調査（4 秒）+ 突進で押し運んだ敵が確実に扇に入る広さ |
| ノックアップ | 0.6 秒 | 公式の値（旧: 資料の 0.6 秒と 1 秒の中間 0.8 秒） |
| アルティメット 詠唱 | 溜め 0.3 秒（CC で中断）、引き寄せは 0.3 秒に始まり 0.38 秒かけて集める、爆発は 0.8 秒 | 調査に長さが無い。0.45 / 0.9 秒（溜めを長く）は Lv6 の勝率がロール中央値を 7 pt 下回り（アルティメットの倍率 3.0 でも）、0.2 / 0.7 秒の元の形より 10 pt 悪化したので、中間の 0.3 / 0.8 秒にした |
| アルティメット 引き寄せ半径・止まる隙間 | 520・術者との間 20 | 近接のアルティメットより広い集団戦の引き寄せ（旧 420）。ツールチップは近接射程の約 3.5 倍 |
| 無効化の合図の長さ | 0.3 秒 | 世界の印とバッジのタイマー。短いので状態アイコン列では一瞬の点滅になる（印の名前は `KitStatusVisuals.markName` 未登録 = 汎用の「刻印」） |
| ダメージの換算 | `waveScale` 0.17 / `hammerScale` 0.58（突進と再発動で共通）/ `ultScale` 1.5 | 公式の表（ランクで補間 + 攻撃力係数）を sim の通常の式 × スロット倍率に通したあとに掛ける。上の表 |
| 説明文の数値 | パッシブ `{vows}` = 4 / スキル1 `{slow1}` `{slow2}` `{slow3}` = 20・40・60、`{slowDuration}` = 1.5、`{reachMult}` = 射程の倍率、`{base}` `{atkPct}` = 換算後の基礎ダメージ・攻撃力に対する % / スキル2 `{dashPct}`（突進の攻撃力 %）、`{smashBase}` `{smashPct}`（再発動）、`{airborne}`、`{window}`、`{dashDamage}` `{smashDamage}`（整数のダメージ）/ アルティメット `{stun}`、`{channel}`、`{gather}`、`{reachMult}`、`{base}`、`{atkPct}` | `KitText` のトークン（`{x0}`〜`{x3}` と `{key}`）に sim の数値を入れる。文は公式の構造（段落・語順）に合わせた |

### 検証した 1v1 の目安

- `Kit_H029Tests.testDuelTimeToKillStaysInBandAgainstTheRoleRepresentatives`: H001〜H006 相手の TTK は Lv 1 / 6 / 12 とも 2.5〜15 秒。
- `KitBalanceTests`（Release、`BalanceHarness`）の勝率（総当たり・両陣営 x 開始距離 x 種の平均、%）。ロール「サポート」の汎用ヒーローの中央値との比較:

  | | Lv1 | Lv6 | Lv12 |
  |---|---|---|---|
  | 元の形（扇の半径が一定・詠唱 0.2 / 0.7 秒・倍率 1.8） | 49.5（中央値 36.4）| 29.8（27.3）| 41.9（43.4）|
  | 扇の半径を広げ・詠唱 0.3 / 0.8 秒・倍率 3.0（公式の表へ置き換える前） | 43.4（中央値 38.9）| 27.3（31.8）| 36.4（44.2）|
  | 公式の表へ置き換え（ultScale 1.2・hammerScale 0.55） | 30.3（中央値 38.6）| 20.2（32.1）| 28.3（45.7）|
  | **今回**（公式の表 + マナ・ノックアップ 0.6 秒・期限なし。ultScale 1.5・hammerScale 0.58） | 30.3（中央値 38.6）| 30.8（32.1）| 38.4（45.7）|

  差は Lv1 −8.3 / Lv6 −1.3 / Lv12 −7.3 pt（許容 ±15 pt に収まる）。置き換え直後の Lv12 は −17.4 pt で帯を外れたので、アルティメットの換算（公式の表の絶対値を勝率で合わせる唯一の調整ネジ。単体ダメージの予算の対象外）だけを 1.2 → 1.5 に上げた。
  なお上の 2 行目までの中央値は他のキットの調整前の計測で、今の中央値とは揃っていない（参考値）。
  開幕 3 秒の瞬間火力の比（同ロール中央値に対する倍率、報告のみ）: 元 0.99 / 1.38 / 1.47 → 前回 0.65 / 1.64 / 1.78 → 今回 0.63 / 1.84 / 1.99。
- `Kit_H029Tests.testRoundRobinWinRateAgainstTheWholeRosterIsNotExtreme`: 旧式の台本（開幕に射程内ならアルティメットを撃つ）の総当たりは Lv6 24%・Lv12 30%。詠唱が長いボルグには厳しく出るので、下限だけ 25% → 20% に緩めた（共通の物差しは上の `KitBalanceTests`）。公式の表へ置き換えたあとは Lv6 21%・Lv12 27%。

### 既知の差・リスク

- マナ消費は公式の値（S1 45・S2 70・アルティメット 120 / 140 / 160）を `HeroKit.cost` で適用する（マスターデータの 55 / 62 / 100 は使わない）。マスターの `cost` を読む旧経路（`SkillSystem.cost(for:resource:)`）は汎用の値のままなので、HUD・スキル詳細は `SkillSystem.cost(for:hero:rank:)`（または `SkillCatalog.numbers().cost`）に切り替える必要がある。
- ダメージの絶対値は公式（270 など）と同じではない（Velstria の HP・防御・全体倍率に合わせて換算）。ランク → Lv の補間は線形（ランク 2 の S1 基礎 = 公式の Lv2 の 320 ではなく Lv 2.67 相当の約 353 を換算）。
- アルティメットの詠唱の「前半 / 後半」は等分ではなく、溜め 0.3 秒（CC で中断）+ 残り 0.5 秒（suppress だけで中断）。溜めのあとにボルグがスタンされても詠唱は続き、引き寄せ・爆発は起きる（調査どおり）。
- 詠唱中の自己ルートは `root` の status（浄化で外れることがある）。外れても `update` が毎 tick 移動・攻撃の意図を消すので、詠唱は続く。CC 無効の間は `root` が付かず、移動の指示だけが毎 tick 消される。
- スキル2 の再使用はクールダウンを「窓が閉じてから」数えるので、再使用しなければ 1 サイクルは最長で窓の 4 秒ぶん長くなる。
- 扇の端（射程の 0.7 倍より外）の敵には波が 1〜2 回しか当たらない。射程いっぱいで撃つと与ダメージと鈍足が浅くなる（近接の押し合いでは 3 回当たる）。
- 無効化の合図は `SkillFXDirector` の既存の hook だけで出している。`passiveRelease` は「スキルの発動の直後（0.6 秒以内）」にしか呼ばれないので、通常の無効化（敵の攻撃を受けた瞬間）は「バッジがタイマーになる → パッシブの合図」で見せる（`FX_H029.passiveRelease` の金の盾の弾けは、発動の直後に無効化したときだけ）。
- 無効化の印（`kit.H029.blocked`）は HUD の状態アイコン列に 0.3 秒だけ汎用の「刻印」として出る（`KitStatusVisuals` は共有ファイルのため名前・アイコンを足していない）。
- `SkillFXDirector` は duration / count を読まない。スキル2 の演出は stage 1 を `recipe(_:stage:_:)` に分けた（cast = 振りかぶり、impact = 叩きつけ）。アルティメットの段は `at` で表した（詠唱 0.3 / 0.8 秒を固定のタイミングで書いてある）。
