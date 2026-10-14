# Saber (MLBB) - Kit Specification

> 2026-10-14: ヒーローの能力値（HP・物理攻撃・防御・魔防・攻撃速度・HP 回復・マナ・移動速度・射程・リソースの種類）と能力値の式（防御 120/(120+防御)・クリティカル 200%・攻撃速度の加算・移動速度の加算式など）を MLBB の値へ置き換えた（`docs/HERO_STATS.md`）。同じ日に、スキルの数値も**公式の表をそのまま使う（6 / 6 / 3 段）**ようにした（スロット倍率・物理係数の × 0.6・キットの換算・ランクの補間を外した。下の「公式の表へ（2026-10-14、スキルの段階）」）。

**正は下の「公式（日本語クライアント）の数値」**（2026-10-10 受領の実機のスクリーンショット。2026-10-11 の無加工の原本 IMG_4504〜4511 と照合済み）。「公式（MLBB Fandom 現行）の数値」は、日本語クライアントに無いパッシブのレベル別の表だけに使う。それより上のウェブ調査（Hero overview 〜 Sources）は参考で、数値の正ではない。

Values come from Mobile Legends Fandom / Liquipedia search extracts plus mlbb.io, mlbb.tools and guide sites (direct Fandom/Liquipedia fetch was blocked). "unknown" = not found. "disputed" = sources disagree.

## Hero overview
- Role / lane: Assassin, jungle (roam secondary). Melee.
- Resource: mana (Fandom/mlbb.io level 1: 500 mana, +100 per level; mlbb.tools lists 468 mana, regen 3.6).
- Basic attack: melee single target; empowered by Charge (enhanced next attack) and by Orbiting Swords (swords fire on hit).
- Attack range: 2.5 in one search extract (unverified, low confidence).
- Base stats at level 1 (Fandom / mlbb.io): HP 2440, physical attack 118, physical defense 20, magic defense 15, attack speed 1.08, movement speed 260.
- Growth per level: HP +180, phys attack +9.71, phys defense +4.0714, magic defense +2.5, attack speed +0.02 (level 15: HP 4960, attack 254, phys def 77, magic def 50).
- Disputed (mlbb.tools): HP 2459, regen 7.2, phys attack 125, phys defense 19, magic defense 10, attack speed 0.9. Prefer Fandom/mlbb.io values.
- Max skill levels: S1 6, S2 6, Ultimate 3.

## Passive - Enemy's Bane
- Cast type: passive on-hit debuff.
- Each damage instance (attacks and skills) from Saber reduces the target's physical defense; stacks up to 5 times, each stack lasts 5 s (refresh behavior = unknown).
- Reduction per stack scales with level: 3-8 (mlbb.io: level 1 about 3 per stack, 15 about 8 per stack; total at 5 stacks 15 to 40). One guide says 7 per stack (older/unverified).

## Skill 1 - Orbiting Swords
- Cast type: self-centered buff/aura (no aim).
- Effect: shoots out 5 swords that orbit Saber, damaging enemies on contact for 80-105 (+30% Extra Physical Attack) physical damage. After about 5 s of orbiting they fly back to Saber. Repeat hits by multiple swords on the same enemy deal reduced damage.
- While active: when Saber damages with basic attacks or skills, an orbiting sword is sent at the target dealing 210-260 (+60% Extra Physical Attack) physical damage to the main target and 50% to other targets it passes through, and reduces Charge cooldown by 1 s (some sources: each sword strike 0.5 s). Triple Sweep's first two strikes use swords for bonus damage (guide extract).
- Cooldown: disputed. Fandom extract 9.0 s; another extract 10.0 s (constant, no per-level scaling); mlbb.tools 10 s.
- Mana: disputed. 75 / 85 / 95 / 105 / 115 / 125 (Fandom extract) vs 60 (mlbb.tools).
- Damage: contact base 80/85/90/95/100/105 (or 75/85/95/105/115/125 in another extract). Sword strike extra 210/220/230/240/250/260 (or 200/220/.../300). Treat per-level figures as disputed.
- Range, sword speed, exact duration: duration about 5 s; others unknown.

## Skill 2 - Charge
- Cast type: dash in a chosen direction.
- Effect: dashes forward dealing 75 (+50% Extra Physical Attack) physical damage to enemies along the path; the next basic attack becomes enhanced: 75 (+120% Total Physical Attack) physical damage and a 60% slow for 1 s (enhancement window length = unknown). Dash range reported 4.2 (reduced from 4.5 in a patch; wiki units).
- Cooldown: 7.0 s at all levels. Reduced by Orbiting Swords strikes.
- Mana: 40 / 44 / 48 / 52 / 56 / 60.
- Damage by level: dash 75 / 90 / 105 / 120 / 135 / 150; enhanced attack base same progression (75 to 150).

## Ultimate - Triple Sweep
- Cast type: point-and-click dash onto a target enemy hero.
- Effect: charges at the target hero, knocking it airborne for 1.2 s (not affected by Resilience) and striking 3 times during the airborne time. Strikes 1 and 2 deal 120 (+80% Extra Physical Attack) physical damage each at level 1; strike 3 deals 240 (+160% Extra Physical Attack) at level 1. (Another extract lists +100% / +200% for levels 1-3 scaling; disputed.)
- Cooldown: 44 / 40 / 36 s. Mana: 100 / 120 / 140.
- Base damage: strikes 1-2: 120 / 150 / 180; strike 3: 240 / 300 / 360.
- Range: 4.6 (reduced from 5.9 in a patch; wiki units; current = unknown).
- Invulnerability / untargetable during sweep, interruptibility: unknown (not stated in any found source).

## Gameplay identity
- Single-target assassin: chase a hero, lock it in the air for 1.2 s, and burst it.
- Defense-shred stacking passive favors sustained or combo damage (swords plus basic attacks).
- Sword-and-Charge loop: Orbiting Swords lowers Charge cooldown, enabling repeated dashes.
- Mana-hungry, low sustain; no inherent lifesteal.

## Simulation notes
- Standard: self-centered AoE, dash with line damage, point-and-click dash with knock-up and multi-hit damage, slows, mana costs.
- Needs special state: stacking defense-shred debuff (5 stacks, 5 s, per-stack value scaling with level); Orbiting Swords timed buff that converts hits into projectile swords and cooldown reduction on Charge; enhanced-next-attack flag after Charge; Triple Sweep as airborne lock with scripted three-hit sequence (Resilience-ignoring CC); cooldown reduction coupling between skills.

## Sources
- https://mobile-legends.fandom.com/wiki/Saber (via search extract)
- https://liquipedia.net/mobilelegends/Saber (via search extract)
- https://mlbb.io/en/hero/saber
- https://mlbb.tools/heroes/saber
- https://theriagames.com/guide/mobile-legends-saber/

## 公式（日本語クライアント）の数値

セイバー(Saber)、ロール「アサシン」、サブタグ「アサルト/追撃」。2026-10-10 に受け取った日本語クライアントの実機のスクリーンショット（スキル詳細の画面）の転記（スキルのレベルは S1・S2 が Lv1〜6、
アルティメットが Lv1〜3）。**下の Fandom の値と違うところはこちらを正とする**（違い: S1 の CD 9 → 10 秒・MP・接触 / 剣撃のダメージと係数・剣撃で S1 自身の CD も縮む、
S2 の MP、奥義のダメージと係数）。アイコンのタグは デバフ / 範囲技 / ブリンク / 爆発力。「追加物理攻撃」は装備・バフで増えた分の物理攻撃（レベルの基礎値を引いた分）。

| スロット | 公式名 | タグ | 内容 |
|---|---|---|---|
| パッシブ | エネミーベイン | デバフ | ダメージを与えるたびに、対象の物理防御を5秒間3-8低下させる（最大5スタック）。 |
| スキル1 | フライングソード | 範囲技・バフ | CD 10.0、MP 60 / 65 / 70 / 75 / 80 / 85、基礎ダメージ 75 / 85 / 95 / 105 / 115 / 125、追加ダメージ 200 / 220 / 240 / 260 / 280 / 300。自身の周囲を旋回する剣を5本放ち、命中した周囲の敵に75(+25%追加物理攻撃)の物理ダメージを与える。効果時間終了後、剣は自身のもとへ戻る。発動中、剣の攻撃は対象に200(+50%追加物理攻撃)の物理ダメージを与え、進路上の敵に50%のダメージを与える（ミニオンへのダメージは50%に低下）。剣の攻撃ごとに、フライングソードのCD時間が0.5秒、アサルトのCD時間が1秒短縮される。 |
| スキル2 | アサルト | ブリンク | CD 7.0、MP 40 / 44 / 48 / 52 / 56 / 60、基礎ダメージ 75 / 90 / 105 / 120 / 135 / 150、強化ダメージ 75 / 90 / 105 / 120 / 135 / 150。指定方向へ突撃し、進路上の敵に75(+50%追加物理攻撃)の物理ダメージを与える。突撃後、強化通常攻撃を獲得する。対象に向かって突撃し、75(+120%物理攻撃)の物理ダメージを与え、移動速度を1秒間60%低下させる。 |
| アルティメット | トリプルスラッシュ | 爆発力・妨害 | CD 44.0 / 40.0 / 36.0、MP 100 / 120 / 140、基礎ダメージ 120 / 170 / 220、追加ダメージ 240 / 340 / 440。対象の敵ヒーローへ突撃し、1.2秒間ノックアップさせる（強靭の影響を受けない）。突撃中に対象を3回攻撃し、最初の2回はそれぞれ120(+80%追加物理攻撃)の物理ダメージ、3回目は240(+160%追加物理攻撃)の物理ダメージを与える。 |

「強靭の影響を受けない」は英語版の「not affected by Resilience」（調査の Ultimate の節）にあたる = **ノックアップの長さがコントロール時間短縮（Velstria の `ccReduction`、タフブーツなど）で縮まない**と読んだ。
Velstria のふつうの打ち上げは強靭で縮む（日本語クライアントの「強靭」は制圧と強制ブリンクだけを除く）ので、奥義は `Kit.knockUp(ignoresResilience: true)`（強靭の対象外の tag）で付ける（テストで固定）。

2026-10-11 に受け取った無加工の原本（日本語クライアントのスキル詳細の画面 IMG_4504〜4511。画像はコミットしない）と照合した: 上の表の数値（CD・MP・基礎ダメージ・追加ダメージ・強化ダメージ・
係数（追加物理攻撃 / 物理攻撃の区別）・防御ダウン 3-8 の 5 スタック・ノックアップ 1.2 秒）・タグ（デバフ / 範囲技・バフ / ブリンク / 爆発力・妨害）・文の構造は一致した（変更なし）。
原本の剣撃の注記は「発動中、剣の攻撃は対象に200(+50%追加)の物理ダメージを与え、進路上の敵に50%のダメージを与える（ミニオンへのダメージは50%に低下）。」。
2026-10-14 から**ミニオンだけ 50%**（`HitPayload.minionMultiplier`。以前は Fandom の古い「ヒーロー以外」に合わせてモンスターにも 50% を掛けていた）。注記は主語が「剣の攻撃」の文の終わりにあるので、
主対象と進路上の敵の両方に掛かると読んだ（進路上のミニオンは 50% × 50% = 25%。「進路上の 50% のミニオン版が 50%」と読むと意味が通らない）。接触（周回の剣が触れたダメージ）は別の文なので掛けない。

## 公式（MLBB Fandom 現行）の数値

`https://mobile-legends.fandom.com/api.php?action=parse&page=Saber&prop=wikitext&format=json` の `{{Ability}}` をそのまま転記（スキルのレベルは S1・S2 が Lv1〜6、アルティメットが Lv1〜3）。
Liquipedia（`liquipedia.net/mobilelegends/api.php`）の表は S1 CD 10 秒・マナ 60〜85・剣撃 200〜300（+50%）・突進の短縮 0.5 秒・奥義 +80% / +160% で、古い版の値（Fandom の現行と食い違うところは Fandom を採る）。

| スロット | 公式名 | タグ | 内容 |
|---|---|---|---|
| パッシブ | Enemy's Bane | Debuff | 攻撃が命中した敵の物理防御を 5 秒間 3〜8 下げる。最大 5 回まで重複。レベル別（式ではなく段階）: 3 / 3 / 3 / 4 / 4 / 4 / 5 / 5 / 5 / 6 / 6 / 7 / 7 / 7 / 8（Lv1〜15）。通常攻撃とスキルのダメージだけ、ミニオン以外が対象、最初の 1 撃から効く |
| スキル1 | Orbiting Swords | AOE・Buff | CD 9.0（一定）、マナ 75 / 85 / 95 / 105 / 115 / 125。5 本の剣が周回し、触れた敵に 80〜105（+30% 追加物理攻撃）。約 5 秒で戻る。効果中に通常攻撃・スキルでダメージを与えると剣を対象へ放ち、主目標に 210〜260（+60% 追加物理攻撃）、通り抜けた他の敵に 50%、Charge の CD −1 秒。ミニオン・クリープなどヒーロー以外には 50% のダメージ。接触 80 / 85 / 90 / 95 / 100 / 105、剣撃 210 / 220 / 230 / 240 / 250 / 260 |
| スキル2 | Charge | Blink・AOE | CD 7.0（一定）、マナ 70 / 65 / 60 / 55 / 50 / 45（レベルが上がるほど安い）。指定方向へ突進し、進路の敵に 75〜150（+50% 追加物理攻撃）、次の通常攻撃を強化。強化通常攻撃は 75〜150（+120% 総物理攻撃）+ 60% 減速 1 秒、射程 2.5。基礎 75 / 90 / 105 / 120 / 135 / 150（突進・強化とも） |
| アルティメット | Triple Sweep | Burst・CC | CD 44 / 40 / 36、マナ 100 / 120 / 140。対象の敵ヒーローへ突撃して 1.2 秒ノックアップ、その間に 3 回斬る。1・2 撃目 120 / 150 / 180（+100% 追加物理攻撃）、3 撃目 240 / 300 / 360（+200%）。打ち上げたあとは制圧（suppress）でのみ中断、最初の突撃（ブリンク扱い）はノックバック・打ち上げで止まる。Saber が倒れると打ち上げは残り、残りのダメージは出ない |

段の対応: **公式の表をそのまま使う（スキル1・2 = 6 段、アルティメット = 3 段）**。Velstria のスキルのランクは公式の Lv そのもの（ランク 1 = Lv1 … ランク 6 = Lv6、奥義はランク 1〜3 = Lv1〜3。`Balance.basicSkillMaxRank = 6`）で、補間はしない（`Kit.level`）。
ダメージ = 基礎[Lv] + 係数 × 能力値（`Kit.official`）。「追加物理攻撃（Extra Physical Attack）」の係数は `Stats.extraAttack`（物理攻撃 − レベルの基礎値。装備・エンブレム・バフで増えた分。StatCalculator が入れる）に掛け、発動の時点で足す。
「物理攻撃」（強化通常攻撃の 120%）は合計の物理攻撃。`numbers`（HUD・説明文）も渡された能力値の追加物理攻撃を使う（装備なしなら 0 なので、説明文の `{base}` は公式の表の値そのもの）。

## Velstria 実装対応表

H028 断空のザイル（アサシン・近接・Mana）= Velstria 版の Saber。実装: `Packages/VelstriaCore/Sources/VelstriaCore/Systems/Kits/Kit_H028.swift`、
テスト: `Tests/VelstriaCoreTests/Kits/Kit_H028Tests.swift`、演出: `App/Battle/SkillFX/Heroes/FX_H028.swift`。
スロットは上の調査の順に割り当てる（Passive = Enemy's Bane、Skill1 = Orbiting Swords、Skill2 = Charge、Ultimate = Triple Sweep）。
マスターデータ上の最終名は パッシブ「空断の理」/ スキル1「環剣」/ スキル2「断空突進」/ アルティメット「三連断空」（`tools/rename_kit_skills.mjs`）。マスターの説明文は汎用のまま残し、アプリ内の説明文はキットのテンプレート（`KitText`）を使う。説明文は UI の用語（スキル1・スキル2・アルティメット）で書き、S1 の追撃の呼び方は「剣撃」にそろえた。
距離は Velstria 単位（≈ MLBB × 100 を近接の射程に合わせて調整。下の「推測の値」）。**ダメージ・クールダウン・コストは公式の表そのまま**（スロット倍率・物理係数の × 0.6・キットの換算・ランクの補間は 2026-10-14 に外した）。
キットは汎用アサシンのパッシブ（草むら/ステルス解除後の奇襲 +30%・キル/アシストで全 CD −30%）を**置き換える**。Saber の調査にそれらは無いので移植しない。

### 対応表（○ = 実装、△ = 簡略化、× = 見送り）

| 元の仕様 | 状態 | Velstria での実装・理由 |
|---|---|---|
| パッシブ: ダメージを与えるたび（通常攻撃・スキル）に相手の物理防御を下げる。5 層・5 秒 | ○ | 通常攻撃の命中とスキルの「ダメージ > 0 の命中」（接触・剣撃・奥義の各撃を含む）で `.mark`（`kit.H028.bane.<所有者>`）を 1 層積む。CC のみの命中は数えない。層は最大 5。**パッシブのバッジ** = 直近に積んだ敵の層の数（`ints[4]`、最大 5）と残り時間（`timers[3]`、命中のたびに 5 秒へ戻る、`ids[1]` = その敵）。時間切れ・その敵が倒れると消える。層が増えるたびに演出のパッシブの合図が出る（バッジの数が増えた瞬間） |
| 1 層あたり 3〜8（レベル別） | ○ / △ | 日本語クライアントの文は「3-8」（範囲）だけ。**レベル別の表は Fandom の現行の `{{Ability}}`**（2026-10 取得: 3 / 3 / 3 / 4 / 4 / 4 / 5 / 5 / 5 / 6 / 6 / 7 / 7 / 7 / 8、Lv1〜15）をそのまま引く（`Tune.baneByLevel`・`Kit_H028.baneFlat(level:)`）。5 層で 15 → 40。日本語クライアントのレベル別の表はまだ無い |
| 持続 5 秒・更新の仕様は不明 | ○ | 命中のたびに全層の持続を 5 秒へ戻す（`Kit.addMark`）。層ごとの個別の期限は持たない |
| 防御ダウンは固定値 | ○ | **固定値**（2026-10-14 から。以前は割合 `armorShred` に「層 × 固定値 ÷ ダウン前の防御」で換算し、上限 0.9、ほかの割合の防御ダウンとは最大の 1 つだけ）。層 × 1 層あたり（術者のレベル）を 1 つの状態（`Tune.baneStatus` = 物理防御だけの `flatArmorMod`、magnitude は負、tag `Tune.baneTag`）で持ち、命中のたびに置き換える。ほかの防御ダウン（固定値・割合）と足し合わせて効き、防御は 0 を下回ってよい（実効の下限 −60 は CombatSystem）。付けた直後に能力値を再計算し、同じ tick のあとのダメージから効く。魔法防御は変えない（公式どおり物理防御だけ） |
| 防御ダウンの対象 | △ | ヒーロー・モンスター・練習場の人形。ミニオンと構造物は対象外（Fandom の注記「ミニオン以外が対象」と、ミニオンに状態を積み続ける sim の負荷。日本語クライアントの文には除外の記載が無い） |
| S1: 自己中心。5 本の剣が約 5 秒周囲を回り、触れた敵に接触ダメージ。5 秒で戻る | ○ | 自己中心（`.selfAoE`・照準なし・敵が居なくても撃てる）。周囲 230（対象の縁まで）に 0.5 秒ごと 9 回（0.5〜4.5 秒）の接触ダメージ（`strikeSequence`・CC では止まらない）。ミニオンにも当たる（ミニオンの 50% は剣撃だけ）。構造物には当たらない。再発動は予約を作り直す |
| S1 接触ダメージ 75 / 85 / 95 / 105 / 115 / 125（+25% 追加物理攻撃） | ○（公式） | `接触[Lv] + 0.25 × 追加物理攻撃` を 0.5 秒ごとに 9 回（回数・間隔は推測）。Fandom の古い「同じ敵に複数の剣が当たると減衰」は無い（9 回の接触に畳み込む） |
| S1 剣撃: 周回中に通常攻撃/スキルでダメージを与えると剣が対象へ飛ぶ。200 / 220 / 240 / 260 / 280 / 300（+50% 追加物理攻撃）、進路上の敵に 50%、ミニオンへは 50% | ○ | 通常攻撃・S2・奥義の「ダメージ > 0 の命中」で 0.12 秒後に剣撃（`schedule`）。主対象に `剣撃[Lv] + 0.5 × 追加物理攻撃`、術者→対象の線（対象の先へ 100 延長・幅 80 + 半径）上の他の敵に 50%。**ミニオンへは 50%**（`HitPayload.minionMultiplier = Tune.strikeMinionRatio`。主対象・進路上の両方に掛ける = 進路上のミニオンは 25%。上の「公式（日本語クライアント）の数値」の読み方）。モンスター・練習場の人形・ヒーローは 100%（以前はモンスターにも 50%）。剣撃・接触（S1 自身のダメージ）は剣撃を呼ばない（連鎖しない）。剣撃どうしは **0.35 秒**以上空ける（推測）。届くのは術者の中心から対象の縁まで 450。飛んでいる間に対象が倒れる・遠ざかると外れる |
| S1 剣撃で 環剣（S1）のクールダウンを 0.5 秒・断空突進（S2）のクールダウンを 1 秒短縮 | ○（公式） | 1 本につき 1 回、`HitEffect.refundCooldown` を 2 つ（S2 −1 秒、S1 自身 −0.5 秒）。貫通した敵の分では短縮しない。練習場の `noCooldowns` を尊重 |
| S1 クールダウン 10 秒（全 Lv 一定） | ○（公式） | `Kit.cooldown([10])` = 10 × (1 − CD 短縮)。持続 5 秒。剣撃 1 本ごとに 0.5 秒縮む |
| S1 MP 60 / 65 / 70 / 75 / 80 / 85 | ○（公式） | `HeroKit.cost` で公式の表そのまま（Mana のヒーローなので倍率なし） |
| S2: 指定方向へ突進、通り道の敵にダメージ | ○ | `.dashStrike`（方向）。`Kit.dashSweeping` で経路上の敵に 1 度ずつ当てる（幅 70 + 対象の半径）。射程 350、速度 1800（約 0.2 秒）。対象指定（`.unit`）のときは対象の縁で止まる。壁は越えられず手前で止まる。**突進はノックアップ・制圧でだけ止まる**（スタンでは止まらない: CC の段階。2026-10-14 から）。バインド（敵の root）の間は撃てない |
| S2 ダメージ 75 / 90 / 105 / 120 / 135 / 150（+50% 追加物理攻撃） | ○（公式） | `突撃[Lv] + 0.5 × 追加物理攻撃` |
| S2: 次の通常攻撃が強化: 75 / 90 / 105 / 120 / 135 / 150（+120% 物理攻撃）+ 60% 鈍足 1 秒、射程 2.5 | ○ | 突進が**着いたとき**に強化の窓が開く（ノックアップ・制圧で突進が止まれば開かない）。窓が開いている間の次の通常攻撃（`shapeBasicAttack`）を **通常攻撃のダメージ × 1.2 + 基礎[Lv]**（合計の物理攻撃の 120%。会心は 1.2 倍の側に乗る）に置き換え、鈍足 60%・1 秒。1 回で消える。**射程は公式の 2.5 = 250**（窓の間だけ通常攻撃の射程を 250 まで延ばす `attackRangeBoost`、使うと消える）。HUD は S2 に残り時間のバッジ |
| S2 強化の持続（不明） | △ | 4 秒（推測。汎用の強化通常攻撃 `Balance.Skills.empowerDuration` と同じ） |
| S2 クールダウン 7 秒（全 Lv 一定） | ○（公式） | `Kit.cooldown([7])`。剣撃で縮む |
| S2 MP 40 / 44 / 48 / 52 / 56 / 60 | ○（公式） | `HeroKit.cost` で公式の表そのまま |
| 奥義: 対象の敵ヒーローへ突進（ポイント＆クリック） | ○ | `.targetedBlink`（`requiresTarget`・`AimShape.lockOn`）。敵ヒーロー限定（ミニオンは選べず、居なければ消費せず失敗）。射程は術者の中心から対象の縁まで 500（推測）。`Kit.dashSweeping`（経路の敵には当たらない）で速度 2600（約 0.2 秒）、対象の縁で止まる。バインドの間は撃てない |
| 奥義: 1.2 秒ノックアップ（強靭の影響を受けない） | ○（公式） | 到着時に `Kit.knockUp(ignoresResilience: true)` 1.2 秒（`testUltimateKnockUpIsNotReducedByCrowdControlReduction`）。CC 無効（`ccImmune`）・無敵の相手には**掛からない**（その場合も三連撃は続ける） |
| 奥義: 打ち上げ中に 3 回撃つ。1・2 撃目 120 / 170 / 220（+80% 追加物理攻撃）、3 撃目 240 / 340 / 440（+160% 追加物理攻撃） | ○（公式） | 到着後 0.2 / 0.6 / 1.0 秒に 3 撃（`strikeSequence`。時刻は推測）。1・2 撃目 = `120 / 170 / 220 + 0.8 × 追加物理攻撃`（`reals[3]`）、3 撃目 = `240 / 340 / 440 + 1.6 × 追加物理攻撃`（`reals[4]`）。どちらも発動の時点の追加物理攻撃。各撃も防御ダウンの層を積む |
| 奥義の最初の 2 撃は剣撃を使う（3 撃目は使わない） | ○ | 通常の剣撃ルールに乗る（S1 の剣が回っているとき）。3 撃目だけは `ints[1]`（剣撃ロック）で剣撃を出さない。間隔 0.4 秒 > 剣撃の最短間隔 0.35 秒なので、1・2 撃目はそれぞれ 1 本を飛ばす（ガイドの記述。日本語クライアントの文には無い） |
| 奥義の中断: 打ち上げたあとは制圧（suppress）でのみ中断、最初の突撃はノックバック・打ち上げで止まる（Fandom の注記）。無敵/対象不可の記載なし | ○ / △ | 無敵/対象不可は**無し**。突進中はノックアップ・制圧で中断（突撃が止まり外れる）。**スタンでは止まらない**（CC の段階: スタンは基本、突進を止めるのは高レベルのノックアップと最上級の制圧。以前はスタンでも外れた）。**三連撃（段 2）は CC では止まらず、suppress だけが止める**（連撃の予約は `interruptible: false`、`update` と各撃で suppress を見る）。三連撃の間は術者は動けず（自分の root + channeling。自分で付けた root なのでバインドではない）、通常攻撃も始めず、ほかのスキルも使えない（`canStart`）。対象の打ち上げは時間まで残る・クールダウンは戻らない |
| 奥義 CD 44 / 40 / 36、MP 100 / 120 / 140 | ○（公式） | `Kit.cooldown([44, 40, 36])`、`HeroKit.cost` で公式の表そのまま |
| 対象が途中で倒れる/離れる | ○ | 対象が倒れる・術者から（半径 + 260）以上離れる・対象不可になると、残りの撃を取り消して終える（突進の到着時も同じ判定）。術者が倒れると全リセット（予約・root も） |
| ボット: 奥義 | ○ | 交戦中の敵ヒーローが射程内（500 + 半径）で、HP が 60% 以下なら `.castNow`（汎用の関門を待たずに今撃つ）、それより多ければ `.cast`（汎用の関門 = 倒せる・2 体以上 を通ったとき） |
| 通常攻撃: 近接単体。射程 2.5（公式では強化通常攻撃の射程） | △ | 通常の通常攻撃は汎用の近接（能力値の射程）。2.5 は強化通常攻撃の射程として S2 に入れた（上） |
| スキル吸収率・攻撃エフェクト・モンスターへの補正 | ○ | 日本語クライアントのセイバーの文に「スキル吸収率」「攻撃エフェクト」「モンスターに ○%」の記載は無いので既定（スキル吸収率 100%、強化通常攻撃は通常の通常攻撃と同じ扱い、モンスター 100%）。ミニオンへの補正は剣撃の 50% だけ（上） |
| チーム/周辺ルール（再使用など） | – | Saber に再使用は無いので窓は使わない（HUD の `recastable` は false） |
| スキルのタグ（UI） | ○ | パッシブ `debuff`（デバフ）、スキル1 `aoe buff`（範囲技・バフ）、スキル2 `mobility`（日本語クライアントはブリンクの 1 つだけ）、アルティメット `burst disrupt`（爆発力・妨害）。`KitText.tags` / `HeroKits.tags` |

### 推測の値（公式に記載が無い幾何・時間。プレビューのスクショ・練習場の動画で直す）

| 項目 | 値 | 理由 |
|---|---|---|
| 剣の周回半径 | 230（対象の縁まで） | 近接の通常攻撃の外側まで届き、至近の敵を覆う |
| 接触の間隔/回数 | 0.5 秒 × 9 回 | 5 秒の周回を 0.5 秒刻みの接触として表現（複数の剣の接触を 1 回に畳み込む） |
| 剣撃の飛行時間・最短間隔 | 0.12 秒・0.35 秒 | 多段ヒット（突進の通り道・接触）で何本も飛ばさないための間隔。0.35 秒は以前の換算のころに 0.25 秒から延ばした値のまま（MLBB の実際の上限は不明。5 本の剣を使い切るのかも未確認） |
| 剣撃の届く距離・進路の幅 | 450・80（対象の先へ 100） | 近接の踏み込みの距離に合わせた |
| S2 の射程・速度・幅 | 350・1800・70 | 調査の 4.2 を近接の比で換算。汎用の突進（1500）より鋭い |
| S2 強化の窓・射程 | 4 秒・250 | 窓は汎用の強化通常攻撃と同じ。射程は Fandom の 2.5 |
| 奥義の射程・速度・外れの距離 | 500・2600・半径 + 260 | 調査の 4.6（旧 5.9）≈ 460 に突進のしやすさを足した |
| 三連撃の時刻 | 到着後 0.2 / 0.6 / 1.0 秒 | 「打ち上げの間に 3 回」だけ。1.2 秒の打ち上げに収まる |

### 公式の表へ（2026-10-14、スキルの段階）

公式の表をそのまま使うようにした（6 / 6 / 3 段。ランク = 公式の Lv）。外したもの:

| 外したもの | 旧 | 新しい扱い |
|---|---|---|
| `Tune.swordsScale`（接触・剣撃の換算） | 0.14（× スキル1 のスロット倍率 4.0、係数は × 0.6） | なし。`接触 / 剣撃[Lv] + 係数 × 追加物理攻撃` |
| `Tune.chargeScale`（突撃・強化の基礎の換算） | 1.2（× スキル2 のスロット倍率 3.0） | なし |
| `Tune.ultScale`（三連撃の換算） | 0.55（× 奥義のスロット倍率 2.6） | なし |
| `Tune.ultWeights`（3 撃の重み） | 0.75 : 0.75 : 1.5（平均 1 撃 × 重み） | 3 撃目は自分の表（240 / 340 / 440 + 160%） |
| `Tune.budgetStrikes`（予算テストの剣撃の本数） | 3 | なし（汎用の 0.8〜1.3 倍の予算テストを消した） |
| `Tune.strikeNonHeroRatio` | 0.5（ミニオンとモンスター。`nonHeroScale`） | `Tune.strikeMinionRatio` 0.5（ミニオンだけ。`HitPayload.minionMultiplier`） |
| 防御ダウンの割合への換算・`Tune.baneMaxRatio` | `armorShred` = 層 × 固定値 ÷ ダウン前の防御（上限 0.9） | 固定値（`Tune.baneStatus` = 物理防御だけの `flatArmorMod`） |
| `(Lv1, Lv6)` のタプル・`lerp`・`cooldown`・`scaledBase`・`attackPercent`・`bonusAttack` | 4 段への線形補間・換算・自前の追加物理攻撃 | `Kit.level` / `Kit.official` / `Kit.cooldown` / `Stats.extraAttack` |
| 全体の倍率（`Balance.Skills.damageScale`・`Balance.skillAttackScalingFactor`・`Balance.Skills.cooldownScale`） | 4.0 / 3.0 / 2.6・0.6・1.0 | 参照しない |

装備なし（追加物理攻撃 0）の Lv1 の値（防御の前）: 接触 42 → **75**、剣撃 112 → **200**、突撃 270 → **75**、強化通常攻撃の基礎 270 → **75**（+ 物理攻撃の 120%）、
奥義 172 / 172 / 343 → **120 / 120 / 240**。CC の段階（2026-10-14 の共通の土台）で、S2 と奥義の突撃はスタンでは止まらなくなった（ノックアップ・制圧だけ）。

以前の換算の経緯（Fandom の表への置き換え・日本語クライアントの数値への置き換え・換算の値を決めた勝率の表）は、この文書の 2026-10-14 より前の版（git の履歴）にある。
`KitBalanceTests`・このキットの 1v1 の TTK と総当たりの勝率（Release）の帯は変えていない。全キットを公式の表へ移したあとに測り直す。

### 既知の差・リスク

- パッシブのレベル別の表は Fandom の値（日本語クライアントの文は「3-8」だけ）。防御ダウンはミニオンに積まない（Fandom の注記・負荷。日本語クライアントの文には除外が無い）。
- 「ミニオンへは 50%」を進路上の 50% にも掛ける（25%）のは文から読んだ解釈。練習場で主対象のミニオン・進路上のミニオン・モンスターへの剣撃の値を読むと確定する。
- 接触ダメージは 0.5 秒ごとの円（周回半径内の全員）で、剣が実際にどこを回っているかは見ない。剣の本数による減衰も無い。
- 剣撃の本数の上限（5 本の剣を使い切るか）と最短間隔 0.35 秒は資料が無い（推測）。剣撃は通常攻撃・S2・奥義の「ダメージを与えた」命中で呼ばれる（Fandom・ガイドの記述。日本語クライアントの文は「発動中、剣の攻撃は…」で、何で飛ぶかは書いていない）。
- 強化通常攻撃は公式どおり「置き換え」（通常攻撃のダメージ × 1.2 + 基礎）。会心のときは 1.2 倍の側にだけ会心倍率が乗る（基礎には乗らない）。MLBB で会心が乗るかは未確認。
- 奥義の中断は Fandom の注記どおり（突撃中はノックアップ・制圧で止まる、打ち上げたあとは suppress だけ）。スタンでは突撃も三連撃も止まらない。
- スキルの詠唱時間（キャストの硬直）は無い（全スキル即時。共通）。
- 死亡で術者の状態は全リセットされるが、敵に付いた防御ダウンの層は期限（最大 5 秒）まで残る。
