# Tigreal (MLBB) - Kit Specification

> 2026-10-14: ヒーローの能力値（HP・物理攻撃・防御・魔防・攻撃速度・HP 回復・マナ・移動速度・射程・リソースの種類）と能力値の式（防御 120/(120+防御)・クリティカル 200%・攻撃速度の加算・移動速度の加算式など）を MLBB の値へ置き換えた（`docs/HERO_STATS.md`）。この文書の能力値の記述（「マスターの値」「近接 150」「Energy」、Energy のコストの × 0.6 など）は置き換え前のもの。
>
> 2026-10-14（スキルの段階）: **公式の表をそのまま使う（6 / 6 / 3 段）**。スキル1・2 は Lv1〜6、アルティメットは Lv1〜3 の表を rank = 公式の Lv で引く（補間なし）。ダメージは公式の式そのまま（基礎[段] + 係数 × 合計の物理攻撃）。スロット倍率・物理係数の × 0.6・キットの倍率（`Tune.waveScale` 0.16 / `hammerScale` 0.52 / `ultScale` 1.5）とランクの線形補間は撤去した。下の「Velstria 実装対応表」はこの段階の内容。

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
| アルティメットのダメージ | 600〜1000 を無視した汎用式 × 3.0 | 600 / 800 / 1000（+130% 物理攻撃）の表をそのまま（換算なし。下の対応表） |

段の対応: **公式の表をそのまま使う（6 / 6 / 3 段）**。Velstria のスキルのランクは S1/S2 が 6 段、アルティメットが 3 段（`SkillSlot.maxRank`）で、rank = 公式の Lv（`Kit.level`）。補間・換算はしない。

| 表（出典: Liquipedia の AbilityCard。日本語クライアントの転記と一致） | Lv1 | Lv2 | Lv3 | Lv4 | Lv5 | Lv6 |
|---|---|---|---|---|---|---|
| スキル1 基礎ダメージ（1 回の爆発。+70% 物理攻撃） | 270 | 320 | 370 | 420 | 470 | 520 |
| スキル1 CD（秒） | 7.0 | 6.4 | 5.8 | 5.2 | 4.6 | 4.0 |
| スキル1 MP | 45 | 45 | 45 | 45 | 45 | 45 |
| スキル2 突進ダメージ | (100% 物理攻撃)（基礎なし） | 同 | 同 | 同 | 同 | 同 |
| スキル2 再使用のノックアップダメージ（+60% 物理攻撃） | 280 | 300 | 320 | 340 | 360 | 380 |
| スキル2 CD（秒） | 16.0 | 15.4 | 14.8 | 14.2 | 13.6 | 13.0 |
| スキル2 MP | 70 | 70 | 70 | 70 | 70 | 70 |
| アルティメット 基礎ダメージ（+130% 物理攻撃） | 600 | 800 | 1000 | — | — | — |
| アルティメット CD（秒） | 55 | 50 | 45 | — | — | — |
| アルティメット MP | 120 | 140 | 160 | — | — | — |

一定の値: スキル1 の減速 20% / 40% / 60%・1.5 秒、スキル2 の再使用の窓 4 秒・ノックアップ 0.6 秒、アルティメットのスタン 1.8 秒（どれも段で変わらない）。
係数の「(+N%物理攻撃)」は合計の物理攻撃（`KitScaling.totalAttack`。「追加」の表記は無い）。
スキル吸収率・攻撃エフェクト・「ミニオンには ○%」「モンスターに ○%」の記載はどのスキルにも無い → 既定（スキル吸収率 100%、ミニオン・モンスターへの補正なし。以前の全体のミニオン × 0.2 は共通の土台で撤廃済み）。

## Velstria 実装対応表

H029 聖槌のボルグ（サポート・近接 150・Mana）= Velstria 版の Tigreal。実装: `Packages/VelstriaCore/Sources/VelstriaCore/Systems/Kits/Kit_H029.swift`、
テスト: `Tests/VelstriaCoreTests/Kits/Kit_H029Tests.swift`、演出: `App/Battle/SkillFX/Heroes/FX_H029.swift`。
スロットは上の調査の順に割り当てる（スキル1 = Attack Wave「聖槌波」、スキル2 = Sacred Hammer「聖槌突撃」、
アルティメット = Implosion「崩落聖域」、パッシブ = Fearless「聖鎚の誓い」。名前はマスターデータのもの）。サポートのロールだが、キットは汎用のサポートのパッシブ
（スキル使用で味方回復）と汎用のアルティメット（味方全体回復 + シールド）を **置き換える**（Tigreal は回復を持たない）。
距離は Velstria 単位（≈ MLBB × 100）。公式の文に無い値（射程・角度・詠唱の長さ・突進の距離など）は下の「推測の値」に書いた。
ダメージ・クールダウン・マナ消費は **公式の表をそのまま使う（6 / 6 / 3 段）**: ダメージ = 公式の基礎[段] + 公式の係数 × 合計の物理攻撃（`Kit.official`）、クールダウン = 公式の秒数[段] × (1 − CD 短縮)（`Kit.cooldown`）、マナ = 公式の表（`HeroKit.cost`）。スキル説明の `{base}(+{atkPct}%物理攻撃)` は公式の値そのもの（例: スキル1 Lv1 = 270(+70%物理攻撃)）。
ツールチップの距離は単位の無い数字を出さず、近接攻撃の射程（MLBB の 1.8 = 180）に対する倍率で書く（`{reachMult}`: スキル1 約 1.7 倍、アルティメット 約 2.9 倍）。

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
| スキル1 ダメージ 270 / 320 / 370 / 420 / 470 / 520（+70% 物理攻撃。1 爆発ごと） | ○ | **公式の表をそのまま使う**: `基礎[Lv] + 0.7 × 合計の物理攻撃`（`Kit.official`。換算なし）。扇の端の敵は爆発が 1〜2 回しか当たらない（扇の広がりは推測の幾何） |
| スキル1 クールダウン 7.0 / 6.4 / 5.8 / 5.2 / 4.6 / 4.0 秒、マナ 45（一定） | ○ | 公式の段の表 × (1 − CD 短縮)（`Kit.cooldown`）。**マナは公式の 45 をキットの `cost` で適用**（マスターの 55 は使わない） |
| スキル1 の射程・角度・間隔（公式にも記載なし） | △ | 選んだ値: 射程 300（近接スキルの標準）・半角 45°（汎用の近接 S1 と同じ）・間隔 0.2 秒。撃ったあとにスタンされても衝撃波は止まらない（すでに地に走ったもの） |
| スキル2 セイントハンマー 1 回目: 指定方向へ突進、進路上の敵に (100% 物理攻撃) の物理ダメージ（基礎ダメージなし）、突進の終点まで押し出す | ○ | `Kit.dashSweeping`（`dashStrike` として宣言、射程 420・速度 1700 = 約 0.25 秒・経路の当たり半径 100）。経路上の敵に 1 度だけダメージ（`kitEvent`）し、`onHit` で突進の向きに「終点の先 + 半径の和 + 20」まで、突進が着くまでに間に合う時間で `knockback` して押し運ぶ。CC 無効・無敵の相手は動かない（ダメージだけ）。壁の手前で止まる。ダメージ = `1.0 × 合計の物理攻撃`（基礎なし。`Kit.official`） |
| 突進と CC の段階・バインド | ○ | 突進（照準の型 `dashStrike`）は術者を動かすスキルなので、**バインド（敵の root）中は撃てない**（`SkillSystem.validate` / `Unit.isBound`。キットの `movesCaster` の上書きは不要）。進行中の突進は **スタン（基本のコントロール）では止まらない**（終点まで走って経路上の敵に当たり、押し運ぶ）。**ノックアップ（高レベル）と制圧（最上級）で止まる**（`Kit.hasDashInterruptingCC`。窓は残る）。MLBB の「状態説明」: スタン = 一部のスキルを中断、ノックアップ = 多くのスキルおよびブリンクやアサルトの効果を中断 |
| スキル2 再発動（4 秒以内）: 前方の敵に 280 / 300 / 320 / 340 / 360 / 380（+60% 物理攻撃）のダメージ + 0.6 秒のノックアップ | ○ | 同じ `castSkill`。窓（`openRecast`、4 秒・1 回）の間はコスト・CD を無視。0.2 秒の振りかぶり（`schedule`。スタン以上で取り消し、バインドでは取り消されない）の後、今いる位置から前方の扇（射程 320・半角 0.8 rad）へダメージ + `knockUp`。敵が居なくても撃てる。術者は動かないので**バインド中も撃てる**。アルティメットの詠唱中は再使用できない。演出は `FX_H029.recipe(_:stage:_:)` の stage 1（振りかぶりの光 → 聖槌の叩きつけ。突進の尾は出さない）。ダメージ = `基礎[Lv] + 0.6 × 合計の物理攻撃` |
| スキル2 ノックアップの長さ | ○（公式で確定） | **0.6 秒**（旧実装は資料が 0.6 / 1 秒で割れていたため中間の 0.8 秒。`Tune.smashAirborne`） |
| スキル2 クールダウン 16.0 / 15.4 / 14.8 / 14.2 / 13.6 / 13.0 秒、マナ 70（一定） | ○ | 公式の段の表 × (1 − CD 短縮)。**窓が閉じてから**数える（`cooldownOnClose`。1 回目の発動で CD は出るが、再使用か 4 秒の経過で閉じた瞬間に全量に戻す）。公式の文に開始時点の記載が無いので、再使用の窓の標準的な扱いを採用（推測）。**マナは公式の 70 をキットの `cost` で適用**（マスターの 62 は使わない） |
| アルティメット インプロージョン: 周囲の敵を引き寄せて 600(+130% 物理攻撃) の物理ダメージ + 1.8 秒スタン | ○ | `selfAoE`・半径 520。詠唱が始まると 0.8 秒間その場から動けず（自分に `root` + 表示用の `channeling`）、攻撃も新しいスキルも始められない。0.3 秒で周囲の敵（ヒーロー・ミニオン・ジャングルの敵。構造物は除く）を術者の元へ `pull`（0.38 秒かけて集める）、0.8 秒で半径 520 の敵にダメージ + スタン 1.8 秒。引き寄せの距離が足りない相手・CC 無効（引き寄せもスタンも効かない）でも範囲内ならダメージ。爆発の瞬間に範囲の外へ出ていれば当たらない |
| スキルの前半はコントロール効果で中断、後半は制圧（suppress）でのみ中断 | △ | 前半を「最初の 0.3 秒（溜め）」、後半を「それ以降」にした（公式に詠唱の長さは無い）。溜めの間はスタン・打ち上げ・suppress で詠唱ごと取り消し（引き寄せも爆発も起きない。クールダウンは戻らない）。それ以降はスタンでは止まらず、suppress だけが止める（`update` と爆発の `onTimer` で確認）。スロウ・沈黙・**バインド**（敵の root。低レベルのコントロールで「スキルを中断できない」）では止まらない。CC の段階の導入後も同じ: 溜めの取り消しはスタン以上（`Kit.hasHardCC`）、後半は制圧だけ |
| 詠唱中の自分の足止めと瞬歩 | ○ | 詠唱中の `root` は自分が付けたもの（sourceID = 自分）なので **バインドではない**（`Unit.isBound` は自分以外の root だけ）。詠唱中も瞬歩を使え、詠唱は続く。引き寄せ（0.3 秒）・爆発（0.8 秒）はその時点の術者の位置で起きるので、瞬歩の先で起きる（MLBB のインプロージョン + 瞬歩の連携）。敵にバインドされていれば瞬歩は使えない |
| アルティメット クールダウン 55 / 50 / 45 秒、マナ 120 / 140 / 160 | ○ | 公式の段の表 × (1 − CD 短縮)。**マナは公式の 120 / 140 / 160 をキットの `cost` で適用**（マスターの 100 は使わない） |
| アルティメットのダメージ 600 / 800 / 1000（+130% 物理攻撃） | ○ | **公式の表をそのまま使う**: `基礎[Lv] + 1.3 × 合計の物理攻撃`（換算なし）。以前は `(基礎 + 1.3 × 攻撃力 × 0.6) × 2.6 × ultScale 1.5`（MLBB の約 3.5 倍）で、その前は汎用の他ロールの式 × 3.0 |
| スキル吸収率・攻撃エフェクト・ミニオン / モンスターへの補正 | ○ | 公式の文（AbilityCard・日本語クライアントの転記）に記載が無い → どのスキルも既定（`HitPayload` の既定: スキル吸収率 100%、`minionMultiplier` / `monsterMultiplier` 1）。攻撃エフェクトの対象（通常攻撃を変えるスキル）は無い。通常攻撃は汎用 |
| アルティメットの詠唱は CC に弱い（ゲームの駆け引き） | ○ | 同時に撃ち合う 1v1 では溜めの 0.3 秒に相手のスタン・ノックバックが入ると不発になる |
| ボットのアルティメット | ○ | 敵ヒーローを 2 体以上巻き込めるか、狙う相手が傷ついている（< 80%）ときだけ、**さらに** 近く（900 以内）に味方ヒーローが居るか相手の HP が 50% 未満のときだけ撃つ（引き寄せた相手を一人で受けない）。敵のタワーの射程内（`Kit_H029.insideEnemyTowerRange`）では撃たない。マナはキットの `cost`（ランクごと）で足りるかを見る |
| スキルのタグ（UI） | ○ | パッシブ `buff`、スキル1 `aoe slow`、スキル2 `clash disrupt`、アルティメット `disrupt aoe`（`KitText.tags` / `HeroKits.tags(heroID:slot:)`。公式のタグ バフ / 範囲技・減速 / 衝突・妨害 / 妨害・範囲技に対応） |

### 外した独自ルール・換算（2026-10-14 スキルの段階）

| 外したもの | 旧 | 新しい扱い |
|---|---|---|
| スキル1 の換算 `Tune.waveScale` | 0.16（3 爆発の合計を汎用 S1 の 0.8〜1.3 倍に合わせる値） | なし。公式の 270〜520（+70%） |
| スキル2 の換算 `Tune.hammerScale` | 0.52（突進と再使用で共通） | なし。突進 (100%)、再使用 280〜380（+60%） |
| アルティメットの換算 `Tune.ultScale` | 1.5（勝率で決めた値） | なし。公式の 600 / 800 / 1000（+130%） |
| スロット倍率 `Balance.Skills.damageScale`・物理係数 `Balance.skillAttackScalingFactor` | 4.0 / 3.0 / 2.6、× 0.6 | なし（キットから参照を全部外した） |
| ランクの線形補間（`lerp`。4 段 → Lv1〜6） | rank r → Lv `1 + (r − 1) × 5 / 3` | なし。6 / 6 / 3 段の表を `Kit.level` で引く |
| CD の全体倍率 `Balance.Skills.cooldownScale` | 1.0 | 参照を外した（`Kit.cooldown`） |
| ダメージの予算テスト（汎用の 0.8〜1.3 倍） | `testNumbersStayWithinDamageBudget…` | 削除。公式の表と等しいことのテストに置き換え（`testNumbersEqualTheOfficialTables`） |

MLBB に無い、バランスのためだけの独自ルールはこのキットには無かった（監査 B の §2 / §8 で挙がったのは上の換算だけ）。

### 推測の値（公式の文に無い幾何・時間。まだ MLBB と違う可能性がある）

| 項目 | 値 | 理由 |
|---|---|---|
| スキル1 射程・半角・間隔・最初の遅れ | 300・45°・0.2 秒・0.12 秒 | 近接スキルの標準 / 汎用の近接 S1 と同じ / 衝撃波が次々に走って見える / 槌を振り下ろす前隙 |
| スキル1 波ごとの半径 | 射程の 0.7 / 0.85 / 1.0 倍 | 衝撃が前へ進んで見えるように広げる（公式の文は「扇形範囲で3回爆発」だけ） |
| スキル2 突進 | 距離 420・速度 1700（約 0.25 秒）・経路の幅 100（半径） | 汎用の近接の突進（400・1500）より少し長く速い、盾を構えた突撃 |
| スキル2 押し運び | 終点の先 + 半径の和 + 20 | 押された敵が突進の終点で術者の目の前に止まる |
| スキル2 振りかぶり・範囲 | 0.2 秒・射程 320 / 半角 0.8 rad | 突進で押し運んだ敵が確実に扇に入る広さ（窓の 4 秒は公式） |
| スキル2 の CD の開始 | 再使用の窓が閉じてから | 公式の文に記載なし。再使用の窓の標準的な扱い |
| アルティメット 詠唱 | 溜め 0.3 秒（CC で中断）、引き寄せは 0.3 秒に始まり 0.38 秒かけて集める、爆発は 0.8 秒 | 公式は「前半 / 後半」だけで長さが無い |
| アルティメット 引き寄せ半径・止まる隙間 | 520・術者との間 20 | 近接のアルティメットより広い集団戦の引き寄せ。ツールチップは近接射程の約 2.9 倍 |
| 無効化の合図の長さ | 0.3 秒 | 世界の印とバッジのタイマー。短いので状態アイコン列では一瞬の点滅になる（印の名前は `KitStatusVisuals.markName` 未登録 = 汎用の「刻印」） |
| 説明文の数値 | パッシブ `{vows}` = 4 / スキル1 `{slow1}` `{slow2}` `{slow3}` = 20・40・60、`{slowDuration}` = 1.5、`{reachMult}` = 射程の倍率、`{base}` `{atkPct}` = 公式の基礎ダメージ・係数の % / スキル2 `{dashPct}`（突進の 100%）、`{smashBase}` `{smashPct}`（再発動）、`{airborne}`、`{window}`、`{dashDamage}` `{smashDamage}`（整数のダメージ）/ アルティメット `{stun}`、`{channel}`、`{gather}`、`{reachMult}`、`{base}`、`{atkPct}` | `KitText` のトークン（`{x0}`〜`{x3}` と `{key}`）に公式の値を入れる。文は公式の構造（段落・語順）に合わせた（突進は公式と同じ「(100%物理攻撃)」） |

### バランスの計測

- 換算を外したので、以前の勝率・TTK の記録（換算の値を決めた計測）は無効。全キットの移行を統合した後に、Release の `KitBalanceTests`・`Kit_H029Tests` の TTK / 総当たりの帯で測り直す（帯の数値は変えていない）。
- 目安（装備なし・防御の前）: 以前の換算と比べ、スキル1 の 1 回の爆発は約 1.7 倍（以前は公式の約 0.58 倍。監査 B §1.2 の比）、スキル2 は約 1.06 倍（以前は約 0.94 倍）、アルティメットは約 0.28 倍（以前は公式の約 3.5 倍）。
- ロールは Velstria ではサポートのまま（MLBB はタンク）。`KitBalanceTests` の外れ値として扱う（共通側）。

### 既知の差・リスク

- マナ消費は公式の値（S1 45・S2 70・アルティメット 120 / 140 / 160）を `HeroKit.cost` で適用する（マスターデータの 55 / 62 / 100 は使わない）。マスターの `cost` を読む旧経路（`SkillSystem.cost(for:resource:)`）は汎用の値のままなので、HUD・スキル詳細は `SkillSystem.cost(for:hero:rank:)`（または `SkillCatalog.numbers().cost`）に切り替える必要がある。
- 出典は Liquipedia の AbilityCard と以前のスクリーンショット（日本語クライアントと一致済み）。日本語クライアントのスキル詳細の生の撮り直し（4 枠と段の表）はまだ（監査 B の §7）。
- アルティメットの詠唱の「前半 / 後半」は等分ではなく、溜め 0.3 秒（CC で中断）+ 残り 0.5 秒（suppress だけで中断）。溜めのあとにボルグがスタンされても詠唱は続き、引き寄せ・爆発は起きる（調査どおり）。
- 前半を中断する「コントロール効果」は、共通の `Kit.hasHardCC`（スタン・ノックアップ・制圧）だけ。沈黙（基本の段階）・バインド（低レベル）では止まらない。バインドは公式の用語で「スキルを中断できない」なので正しいが、沈黙で MLBB の前半が止まるかは未確認。
- 詠唱中の自己ルートは `root` の status（浄化で外れることがある）。外れても `update` が毎 tick 移動・攻撃の意図を消すので、詠唱は続く。CC 無効の間は `root` が付かず、移動の指示だけが毎 tick 消される。
- スキル2 の再使用はクールダウンを「窓が閉じてから」数えるので、再使用しなければ 1 サイクルは最長で窓の 4 秒ぶん長くなる（推測の扱い）。
- パッシブの「スキルを発動するたびに」に再使用（スキル2 の 2 段目）を数えるかは公式の文が沈黙。初回の発動だけ数える。
- 扇の端（射程の 0.7 倍より外）の敵には波が 1〜2 回しか当たらない。射程いっぱいで撃つと与ダメージと鈍足が浅くなる（近接の押し合いでは 3 回当たる）。
- 無効化の合図は `SkillFXDirector` の既存の hook だけで出している。`passiveRelease` は「スキルの発動の直後（0.6 秒以内）」にしか呼ばれないので、通常の無効化（敵の攻撃を受けた瞬間）は「バッジがタイマーになる → パッシブの合図」で見せる（`FX_H029.passiveRelease` の金の盾の弾けは、発動の直後に無効化したときだけ）。
- 無効化の印（`kit.H029.blocked`）は HUD の状態アイコン列に 0.3 秒だけ汎用の「刻印」として出る（`KitStatusVisuals` は共有ファイルのため名前・アイコンを足していない）。
- `SkillFXDirector` は duration / count を読まない。スキル2 の演出は stage 1 を `recipe(_:stage:_:)` に分けた（cast = 振りかぶり、impact = 叩きつけ）。アルティメットの段は `at` で表した（詠唱 0.3 / 0.8 秒を固定のタイミングで書いてある）。
