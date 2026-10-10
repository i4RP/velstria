# Saber (MLBB) - Kit Specification

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

## Velstria 実装対応表

H028 断空のザイル（アサシン・近接 150・Energy）= Velstria 版の Saber。実装: `Packages/VelstriaCore/Sources/VelstriaCore/Systems/Kits/Kit_H028.swift`、
テスト: `Tests/VelstriaCoreTests/Kits/Kit_H028Tests.swift`、演出: `App/Battle/SkillFX/Heroes/FX_H028.swift`。
スロットは上の調査の順に割り当てる（Passive = Enemy's Bane、Skill1 = Orbiting Swords、Skill2 = Charge、Ultimate = Triple Sweep）。
マスターデータ上の最終名は パッシブ「空断の理」/ スキル1「環剣」/ スキル2「断空突進」/ アルティメット「三連断空」（`tools/rename_kit_skills.mjs`）。マスターの説明文は汎用のまま残し、アプリ内の説明文はキットのテンプレート（`KitText`）を使う。説明文は UI の用語（スキル1・スキル2・アルティメット）で書き、S1 の追撃の呼び方は「剣撃」にそろえた。
距離は Velstria 単位（≈ MLBB × 100 を近接 150 に合わせて調整）。ダメージは Velstria 全体の係数（`Balance.Skills`）に合わせた換算で、MLBB の数値そのままではない。クールダウンは MLBB の秒数そのまま（6 段のランクを Velstria の 4 段・奥義 3 段へ線形補間。全体倍率 `cooldownScale` は 1.0）。
キットは汎用アサシンのパッシブ（草むら/ステルス解除後の奇襲 +30%・キル/アシストで全 CD −30%）を**置き換える**。Saber の調査にそれらは無いので移植しない。

### 対応表（○ = 実装、△ = 簡略化、× = 見送り）

| 元の仕様 | 状態 | Velstria での実装・理由 |
|---|---|---|
| パッシブ: ダメージを与えるたび（通常攻撃・スキル）に相手の物理防御を下げる。5 層・5 秒 | ○ | 通常攻撃の命中とスキルの「ダメージ > 0 の命中」（接触・剣撃・奥義の各撃を含む）で `.mark`（`kit.H028.bane.<所有者>`）を 1 層積む。CC のみの命中は数えない。層は最大 5。**パッシブのバッジ** = 直近に積んだ敵の層の数（`ints[4]`、最大 5）と残り時間（`timers[3]`、命中のたびに 5 秒へ戻る、`ids[1]` = その敵）。時間切れ・その敵が倒れると消える。層が増えるたびに演出のパッシブの合図が出る（バッジの数が増えた瞬間） |
| 1 層あたり 3（Lv1）→ 8（Lv15）。古い資料の「7」 | ○ | mlbb.io の 3 → 8 を採用（Velstria の最大レベルも 15）。レベルで線形 = `Kit_H028.baneFlat(level:)`。5 層で 15 → 40。古い 7 固定は採らない |
| 持続 5 秒・更新の仕様は不明 | ○ | 命中のたびに全層の持続を 5 秒へ戻す（`Kit.addMark`）。層ごとの個別の期限は持たない |
| 防御ダウンの効き方 | △ | Velstria の `armorShred` は割合。「ダウン前の防御」を求め（ほかの防御ダウンを含む防御から逆算）、`層 × 固定値 / ダウン前の防御`（上限 0.9）の割合で付ける。同じ tick のあとのダメージから効くよう、付けた直後に能力値を再計算する。`armorShred` は複数あると最大の 1 つだけが効く（既存の仕様）ので、より大きい防御ダウンがある相手では実質効かない |
| 防御ダウンの対象 | △ | ヒーロー・モンスター・練習場の人形。ミニオンと構造物は対象外（ミニオンに状態を積み続けると sim の負荷が増えるため） |
| S1: 自己中心。5 本の剣が約 5 秒周囲を回り、触れた敵に接触ダメージ。5 秒で戻る | ○ | 自己中心（`.selfAoE`・照準なし・敵が居なくても撃てる）。周囲 230（対象の縁まで）に 0.5 秒ごと 9 回（0.5〜4.5 秒）の接触ダメージ（`strikeSequence`・CC では止まらない）。ミニオンにも当たる。構造物には当たらない。再発動は予約を作り直す |
| S1 接触ダメージ 80〜105 + 30%。同じ敵に複数の剣が当たると減衰 | △ | 汎用 S1 のダメージ × **0.55** を 9 回に等分（剣撃が主なダメージ源なので接触は控えめにした。調査の接触 80〜105 + 30% に対し剣撃は 210〜260 + 60%）。S1 の単体総ダメージの予算（汎用の 0.8〜1.3 倍）は「接触 + 剣撃 3 本（5 秒に通常攻撃・スキルが 3 回当たる想定）」で数える = 0.55 + 3 × 0.19 = 1.12 倍。複数の剣の減衰は 1 回あたりの値に畳み込み、個別の減衰は持たない。ランクは 4 段（元は 6 段） |
| S1 剣撃: 周回中に通常攻撃/スキルでダメージを与えると剣が対象へ飛び、210〜260 + 60%（主対象）、貫通した他の敵に 50% | ○ | 通常攻撃・S2・奥義の「ダメージ > 0 の命中」で 0.12 秒後に剣撃（`schedule`）。主対象に汎用 S1 × **0.19**、術者→対象の線（対象の先へ 100 延長・幅 80 + 半径）上の他の敵に 50%。剣撃・接触（S1 自身のダメージ）は剣撃を呼ばない（連鎖しない）。剣撃どうしは **0.35 秒**以上空ける（多段ヒットのスキルで一度に何本も飛ばさない）。届くのは術者の中心から対象の縁まで 450。飛んでいる間に対象が倒れる・遠ざかると外れる |
| S1 剣撃で Charge（S2）のクールダウンを 1 秒短縮（資料により 0.5 秒/本） | ○ | 1 本につき 1 回、`HitEffect.refundCooldown`。**1 秒**（MLBB と同じ。全体の CD が半分だったころは 0.5 秒）。貫通した敵の分では短縮しない。練習場の `noCooldowns` を尊重 |
| S1 クールダウン 9 秒（Fandom）/ 10 秒（別の抜粋・mlbb.tools） | ○ | **10 秒**（2 つの資料が一致、ランクで変わらない。MLBB の秒数そのまま）。持続 5 秒なので剣が回っているのは約 50%（MLBB と同じ）。全体の CD が半分だったころは 5 秒（ほぼ常に回る）で、10 秒にすると Lv1（スキル1 だけ）の決闘が崩れた（下の「バランス」の旧表）。全員の CD が MLBB の秒数になった今は、ほかのヒーローとの相対的な間隔は当時の 5 秒と同じ |
| S1 マナ 75〜125（Fandom）/ 60（mlbb.tools） | × | コストはマスターデータ（`cost` 45。Energy は ×0.6）のまま。`SkillSystem.validate` がマスターから決めるのでキットでは変えられない |
| S2: 指定方向へ突進、通り道の敵に 75 + 50% | ○ | `.dashStrike`（方向）。`Kit.dashSweeping` で経路上の敵に 1 度ずつ当てる（幅 70 + 対象の半径）。射程 350（元の 4.2 ≈ 近接 150 の比で換算。マスターの S2 射程 350 と一致）、速度 1800（約 0.2 秒）。対象指定（`.unit`）のときは対象の縁で止まる。壁は越えられず手前で止まる |
| S2 ダメージ 75〜150 + 50% | △ | 汎用 S2 のダメージ × **0.81**（突進）。ランクは 4 段。S2 の単体総ダメージの予算は突進 + 強化通常攻撃の追加ダメージ（0.81 + 0.23 = 1.04 倍）で数える |
| S2: 次の通常攻撃が強化: 75 + 総攻撃力 120% + 60% 鈍足 1 秒 | △ | 突進が**着いたとき**に強化の窓が開く（ハード CC で突進が止まれば開かない）。窓が開いている間の次の通常攻撃（`shapeBasicAttack`）に追加ダメージ（汎用 S2 × **0.23**。MLBB は通常攻撃を 75 + 120% に置き換えるので、突進よりこちらのほうが大きい）と鈍足 60%・1 秒。1 回で消える。MLBB は通常攻撃を 75 + 120% に**置き換える**が、Velstria は通常攻撃に追加ダメージを足す形（置き換えは通常攻撃の攻撃力の差し引きが要る）。HUD は S2 に残り時間のバッジ |
| S2 強化の持続（不明） | ○ | 4 秒（汎用の強化通常攻撃 `Balance.Skills.empowerDuration` と同じ） |
| S2 クールダウン 7 秒（全ランク） | ○ | MLBB と同じ 7 秒（以前は × 0.5 = 3.5 秒）。剣撃で縮む |
| S2 マナ 40〜60 | × | マスターのまま（`cost` 55） |
| 奥義: 対象の敵ヒーローへ突進（ポイント＆クリック） | ○ | `.targetedBlink`（`requiresTarget`・`AimShape.lockOn`）。敵ヒーロー限定（ミニオンは選べず、居なければ消費せず失敗）。指定ユニット/地点/方向/自動の照準は汎用の対象指定ブリンクと同じ（`SkillAiming.blinkTarget`）。射程は術者の中心から対象の縁まで 500（調査の 4.6（旧 5.9）≈ 460 に突進のしやすさを足した。マスターは 600）。`Kit.dashSweeping`（経路の敵には当たらない）で速度 2600（約 0.2 秒）、対象の縁で止まる |
| 奥義: 1.2 秒打ち上げ（Resilience 無効） | △ | 到着時に `knockUp` 1.2 秒。Velstria に Resilience（CC 短縮）は無いので、CC 無効（`ccImmune`）・無敵の相手に**は掛からない**（その場合も三連撃は続ける） |
| 奥義: 打ち上げ中に 3 回撃つ（120 / 120 / 240 = 1 : 1 : 2。+80% / +160%、別資料は +100% / +200%） | ○ | 到着後 0.2 / 0.6 / 1.0 秒に 3 撃（`strikeSequence`）。重みは 0.75 : 0.75 : 1.5（= 1 : 1 : 2）。合計は汎用奥義のダメージ × **0.85**。攻撃力の係数は汎用の式に畳み込まれているので、+80%/+100% の資料の食い違いは 1 : 1 : 2 の比で吸収される。各撃も防御ダウンの層を積む（3 撃目は 2 撃分の防御ダウンの後に入る） |
| 奥義の最初の 2 撃は剣撃を使う（3 撃目は使わない） | ○ | 通常の剣撃ルールに乗る（S1 の剣が回っているとき）。3 撃目だけは `ints[1]`（剣撃ロック）で剣撃を出さない。間隔 0.4 秒 > 剣撃の間隔 0.25 秒なので、1・2 撃目はそれぞれ 1 本を飛ばす |
| 奥義の無敵/対象不可・中断（不明） | △ | 無敵/対象不可は**無し**（術者はそのまま被弾する）。突進中も三連撃中もハード CC（スタン・打ち上げ・suppress）で中断され、残りの撃は出ない（対象の打ち上げは時間まで残る・クールダウンは戻らない）。三連撃の間は術者は動けず（root + channeling）、通常攻撃も始めず、ほかのスキルも使えない（`canStart`） |
| 奥義 CD 44 / 40 / 36、マナ 100 / 120 / 140 | △ | CD は MLBB と同じ 44 / 40 / 36 秒（以前は × 0.5 = 22 / 20 / 18 秒）。マナはマスターのまま（`cost` 92） |
| 対象が途中で倒れる/離れる | ○ | 対象が倒れる・術者から（半径 + 260）以上離れる・対象不可になると、残りの撃を取り消して終える（突進の到着時も同じ判定）。術者が倒れると全リセット（予約・root も） |
| ボット: 奥義 | ○ | 交戦中の敵ヒーローが射程内（500 + 半径）で、HP が 60% 以下なら `.castNow`（汎用の関門を待たずに今撃つ）、それより多ければ `.cast`（汎用の関門 = 倒せる・2 体以上 を通ったとき）。以前の「HP 80% 未満か剣が回っている」は、剣がほぼ常に回っているので意味が無かったため外した |
| 通常攻撃: 近接単体。射程 2.5（1 つの抜粋・未確認） | × | 汎用の近接 150。Saber の通常攻撃は S1 の剣と S2 の強化で変わるだけ |
| チーム/周辺ルール（再使用など） | – | Saber に再使用は無いので窓は使わない（HUD の `recastable` は false） |

### 選んだ値（調査に無い・割れていた・換算した値）

| 項目 | 値 | 理由 |
|---|---|---|
| 剣の周回半径 | 230（対象の縁まで） | 近接の通常攻撃（150 + 双方の半径）の外側まで届き、至近の敵を覆う。調査に無い |
| 接触の間隔/回数 | 0.5 秒 × 9 回 | 調査に無い。5 秒の周回を 0.5 秒刻みの接触として表現（複数の剣の接触を 1 回に畳み込む） |
| 剣撃の飛行時間・最短間隔 | 0.12 秒・0.35 秒 | 調査に無い。多段ヒット（突進の通り道・接触）で何本も飛ばさないための間隔（0.25 秒から延ばし、剣撃を「何度でも出る」から「おおむね通常攻撃 1 回に 1 本」にした） |
| 突進の速度 | S2 1800 / 奥義 2600 | 汎用の突進（1500）より鋭い。奥義は「対象指定の踏み込み」に見える速さ |
| 三連撃の間隔 | 0.2 / 0.4 秒 | 調査は「打ち上げの間に 3 回」のみ。1.2 秒の打ち上げに収まる（最後が 1.0 秒） |
| S1 のクールダウン | 10 秒 | 9 秒と 10 秒で割れていた。2 つの資料が 10 秒。ランクで変わらない（全体の CD が半分だったころは 5 秒） |
| Charge の短縮 | 1 秒/本 | 1 秒と 0.5 秒で割れていた。1 秒を採る（全体の CD が半分だったころは 0.5 秒） |
| ダメージ倍率 | S1 接触 0.55（9 回の合計）+ 剣撃 0.19/本、S2 0.81（+ 強化 0.23）、奥義 0.85 | S1 は接触 + 剣撃 3 本で 1.12 倍、S2 は突進 + 強化で 1.04 倍（テストで確認）。剣撃・強化・防御ダウンは条件付きの上乗せで、全員総当たりの勝率が汎用アサシンと同じ水準になるよう抑えた |

### バランス（`KitBalanceTests`、Release、全員総当たり。同ロール（Assassin）の汎用ヒーローの中央値との差）

全 34 ヒーローとの 1v1（`BalanceHarness`: 両陣営 × 開始距離 300/450/600 × 種 2 の 12 戦の平均、Lv 1/6/12、スキル自動習得、引き分けは半分）の勝率を、同ロールの汎用ヒーローの中央値と比べる。

| | Lv1 | Lv6 | Lv12 | 開幕 3 秒の火力（汎用の中央値比 Lv1 / 6 / 12） |
|---|---|---|---|---|
| 前の版（接触 0.85・剣撃 0.11・間隔 0.25・強化 0.08・突進 0.82・奥義 0.90） | 26.3% (−3.2) | 47.5% (−8.2) | 39.4% (−10.4) | 3.26 / 2.24 / 2.18 |
| 現在（接触 0.55・剣撃 0.19・間隔 0.35・強化 0.23・突進 0.81・奥義 0.85） | 32.3% (+4.2) | 47.0% (−10.0) | 47.5% (−2.8) | 3.36 / 2.25 / 2.31 |

絶対値の火力は 3% ほど下がった（Lv6 2280 → 2207、Lv12 2851 → 2757）が、同ロールの汎用の中央値も下がったので比は下がっていない。
開幕 3 秒の火力を 2 倍に収めるには奥義を 0.80 まで削る必要があり、そうすると Lv6 の勝率が −15 まで落ちた（奥義 0.9 → 0.8・剣撃 0.20 → 0.18・強化 0.25 → 0.22 で Lv6 −11pt）ので、0.85 / 0.19 / 0.23 で止めた。
奥義の 3 秒の火力は打ち上げ中の確定コンボで、勝率に直結する。

S1 のクールダウン（Z3）の検討: 秒数そのまま（倍率 1.0、稼働率 約 50%）に近づけるほど Lv1 の勝率が崩れた。

| S1 の倍率（クールダウン） | Lv1 | Lv6 | Lv12 |
|---|---|---|---|
| 0.5（5 秒、現在） | 34.3% (+4.9) | 52.0% (−3.7) | 51.0% (+1.3) |
| 0.6（6 秒） | 22.2% (−7.2) | 49.5% (−6.2) | 45.5% (−4.2) |
| 0.65（6.5 秒） | 13.1% (−16.3) | 46.0% (−9.7) | 42.9% (−6.8) |
| 0.75（7.5 秒） | 3.0% (−26.4) | 44.4% (−11.3) | 40.9% (−8.8) |
| 1.0（10 秒、接触 0.75・剣撃 0.28 に上乗せ） | 3.0% (−26.4) | 59.1% (+3.4) | 60.1% (+10.4) |

（上の 5 行は同じ条件で測った別の回で、ほかのキットの調整前の相手との勝率。）Lv1 の決闘は 10 秒前後で決着し、2 回目の剣が間に合うか（クールダウン 5 秒 → 6〜7.5 秒）で勝敗が決まるため。
ダメージを 3 割上乗せしても Lv1 は戻らず、Lv6 / Lv12 だけが強くなる（開幕 3 秒の火力も上がる）。そのため S1 のクールダウンは全体倍率（0.5）のままにし、`Tune.swordsCooldownScale` に残した。
（`SkillBalanceTests` の TTK は H001〜H006 相手で Lv1 が約 10 秒、Lv6/12 が 5〜8.5 秒。）

### 既知の差・リスク

- スキルのマナ（コスト）の相対関係と、元の S1 マナ 60〜125 / S2 40〜60 / 奥義 100〜140 は再現できない（マスターデータ固定）。
- 接触ダメージは 0.5 秒ごとの円（周回半径内の全員）で、剣が実際にどこを回っているかは見ない。剣の本数による減衰も無い。
- 防御ダウンは `armorShred`（割合）で、ほかの防御ダウン（装備の防御低下やほかのキットの防御ダウン）と重なると最大の 1 つだけが効く（既存の仕様）。防御が低い相手では割合の上限 0.9 で止まる。
- 強化通常攻撃は「置き換え」ではなく「追加ダメージ」。会心のときの扱いは追加ぶんに掛からない（通常攻撃のダメージにだけ会心倍率）。
- 剣撃は通常攻撃・S2・奥義の「ダメージを与えた」命中で呼ばれる。ミニオンへの攻撃でも飛ぶ（ウェーブ処理が速くなる）が、防御ダウンの層はミニオンに積まれない。
- S1 のクールダウンは MLBB と同じ 10 秒（持続 5 秒）なので、剣が回っているのは約 50%（MLBB と同じ）。剣撃の間隔 0.35 秒・接触 0.55 は、全体の CD が半分で剣が常に回っていたころに火力が過大にならないよう決めた値のまま。
- 奥義の無敵/中断の仕様は調査に無いので、中断される（スタンで取り消し）側に倒した。実際の Saber と違う場合は `Kit_H028.update` / `ultStrike` の判定を変える。
- 死亡で術者の状態は全リセットされるが、敵に付いた防御ダウンの層は期限（最大 5 秒）まで残る。
