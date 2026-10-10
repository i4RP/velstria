# Saber (MLBB) - Kit Specification

**正は下の「公式（MLBB Fandom 現行）の数値」**（2026-10 に MediaWiki API で取得した Fandom の現行のスキル表）。それより上のウェブ調査と食い違う値は公式が優先する。

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

## 公式（MLBB Fandom 現行）の数値

`https://mobile-legends.fandom.com/api.php?action=parse&page=Saber&prop=wikitext&format=json` の `{{Ability}}` をそのまま転記（スキルのレベルは S1・S2 が Lv1〜6、アルティメットが Lv1〜3）。
Liquipedia（`liquipedia.net/mobilelegends/api.php`）の表は S1 CD 10 秒・マナ 60〜85・剣撃 200〜300（+50%）・突進の短縮 0.5 秒・奥義 +80% / +160% で、古い版の値（Fandom の現行と食い違うところは Fandom を採る）。

| スロット | 公式名 | タグ | 内容 |
|---|---|---|---|
| パッシブ | Enemy's Bane | Debuff | 攻撃が命中した敵の物理防御を 5 秒間 3〜8 下げる。最大 5 回まで重複。レベル別（式ではなく段階）: 3 / 3 / 3 / 4 / 4 / 4 / 5 / 5 / 5 / 6 / 6 / 7 / 7 / 7 / 8（Lv1〜15）。通常攻撃とスキルのダメージだけ、ミニオン以外が対象、最初の 1 撃から効く |
| スキル1 | Orbiting Swords | AOE・Buff | CD 9.0（一定）、マナ 75 / 85 / 95 / 105 / 115 / 125。5 本の剣が周回し、触れた敵に 80〜105（+30% 追加物理攻撃）。約 5 秒で戻る。効果中に通常攻撃・スキルでダメージを与えると剣を対象へ放ち、主目標に 210〜260（+60% 追加物理攻撃）、通り抜けた他の敵に 50%、Charge の CD −1 秒。ミニオン・クリープなどヒーロー以外には 50% のダメージ。接触 80 / 85 / 90 / 95 / 100 / 105、剣撃 210 / 220 / 230 / 240 / 250 / 260 |
| スキル2 | Charge | Blink・AOE | CD 7.0（一定）、マナ 70 / 65 / 60 / 55 / 50 / 45（レベルが上がるほど安い）。指定方向へ突進し、進路の敵に 75〜150（+50% 追加物理攻撃）、次の通常攻撃を強化。強化通常攻撃は 75〜150（+120% 総物理攻撃）+ 60% 減速 1 秒、射程 2.5。基礎 75 / 90 / 105 / 120 / 135 / 150（突進・強化とも） |
| アルティメット | Triple Sweep | Burst・CC | CD 44 / 40 / 36、マナ 100 / 120 / 140。対象の敵ヒーローへ突撃して 1.2 秒ノックアップ、その間に 3 回斬る。1・2 撃目 120 / 150 / 180（+100% 追加物理攻撃）、3 撃目 240 / 300 / 360（+200%）。打ち上げたあとは制圧（suppress）でのみ中断、最初の突撃（ブリンク扱い）はノックバック・打ち上げで止まる。Saber が倒れると打ち上げは残り、残りのダメージは出ない |

ランクの対応: Velstria のスキルのランクは S1/S2 が 4 段、アルティメットが 3 段。表は**線形補間**（ランク 1 = Lv1、最大ランク = 公式の最終レベル。ランク r → Lv `1 + (r − 1) × 5 / 3`）。公式の表はどれも等差なので「最初と最後を結ぶ直線」と同じ。
「追加物理攻撃（Extra Physical Attack）」の係数は Velstria では総攻撃力に掛ける（`numbers` は装備前の攻撃力を知らないため。H029 と同じ式）。

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
| 1 層あたり 3〜8（公式のレベル別の表 3 / 3 / 3 / 4 / 4 / 4 / 5 / 5 / 5 / 6 / 6 / 7 / 7 / 7 / 8） | ○（公式） | **公式の表をそのまま**引く（`Tune.baneByLevel`・`Kit_H028.baneFlat(level:)`）。以前は mlbb.io の 3 → 8 を線形にしていた（Lv8 で 5.5 → 5）。5 層で 15 → 40 |
| 持続 5 秒・更新の仕様は不明 | ○ | 命中のたびに全層の持続を 5 秒へ戻す（`Kit.addMark`）。層ごとの個別の期限は持たない |
| 防御ダウンの効き方 | △ | Velstria の `armorShred` は割合。「ダウン前の防御」を求め（ほかの防御ダウンを含む防御から逆算）、`層 × 固定値 / ダウン前の防御`（上限 0.9）の割合で付ける。同じ tick のあとのダメージから効くよう、付けた直後に能力値を再計算する。`armorShred` は複数あると最大の 1 つだけが効く（既存の仕様）ので、より大きい防御ダウンがある相手では実質効かない |
| 防御ダウンの対象 | △ | ヒーロー・モンスター・練習場の人形。ミニオンと構造物は対象外（ミニオンに状態を積み続けると sim の負荷が増えるため） |
| S1: 自己中心。5 本の剣が約 5 秒周囲を回り、触れた敵に接触ダメージ。5 秒で戻る | ○ | 自己中心（`.selfAoE`・照準なし・敵が居なくても撃てる）。周囲 230（対象の縁まで）に 0.5 秒ごと 9 回（0.5〜4.5 秒）の接触ダメージ（`strikeSequence`・CC では止まらない）。ミニオンにも当たる。構造物には当たらない。再発動は予約を作り直す |
| S1 接触ダメージ 80〜105（+30% 追加物理攻撃）。同じ敵に複数の剣が当たると減衰 | ○ / △ | **公式の表**: `(lerp(80, 105) + 0.3 × 攻撃力 × 0.6) × スキル1 の倍率 4.0 × swordsScale` を 0.5 秒ごとに 9 回（回数は選んだ値）。複数の剣の減衰は 9 回の接触に畳み込む。以前は汎用 S1 × 0.55 を 9 回に等分 |
| S1 剣撃: 周回中に通常攻撃/スキルでダメージを与えると剣が対象へ飛び、210〜260（+60% 追加物理攻撃）（主対象）、通り抜けた他の敵に 50%。ヒーロー以外の敵には 50% | ○ | 通常攻撃・S2・奥義の「ダメージ > 0 の命中」で 0.12 秒後に剣撃（`schedule`）。主対象に `(lerp(210, 260) + 0.6 × 攻撃力 × 0.6) × 4.0 × swordsScale`（接触と同じ換算）、術者→対象の線（対象の先へ 100 延長・幅 80 + 半径）上の他の敵に 50%。**ミニオン・モンスターには 50%**（公式。練習場の人形はヒーロー扱い、`Kit_H028.nonHeroScale`）。剣撃・接触（S1 自身のダメージ）は剣撃を呼ばない（連鎖しない）。剣撃どうしは **0.35 秒**以上空ける。届くのは術者の中心から対象の縁まで 450。飛んでいる間に対象が倒れる・遠ざかると外れる |
| S1 剣撃で Charge（S2）のクールダウンを 1 秒短縮（資料により 0.5 秒/本） | ○ | 1 本につき 1 回、`HitEffect.refundCooldown`。**1 秒**（MLBB と同じ。全体の CD が半分だったころは 0.5 秒）。貫通した敵の分では短縮しない。練習場の `noCooldowns` を尊重 |
| S1 クールダウン 9 秒（Fandom の現行）/ 10 秒（Liquipedia・mlbb.tools = 古い版） | ○（公式） | **9 秒**（ランクで変わらない）。持続 5 秒なので剣が回っているのは約 55%。以前は 10 秒 |
| S1 マナ 75 → 125 | ○（公式） | `HeroKit.cost` でランクごとに 75 / 91.7 / 108.3 / 125（Energy なので × 0.6 = 45 → 75）。以前はマスターの 45（× 0.6 = 27） |
| S2: 指定方向へ突進、通り道の敵に 75 + 50% | ○ | `.dashStrike`（方向）。`Kit.dashSweeping` で経路上の敵に 1 度ずつ当てる（幅 70 + 対象の半径）。射程 350（元の 4.2 ≈ 近接 150 の比で換算。マスターの S2 射程 350 と一致）、速度 1800（約 0.2 秒）。対象指定（`.unit`）のときは対象の縁で止まる。壁は越えられず手前で止まる |
| S2 ダメージ 75〜150（+50% 追加物理攻撃） | ○ / △ | **公式の表**: `(lerp(75, 150) + 0.5 × 攻撃力 × 0.6) × スキル2 の倍率 3.0 × chargeScale`。S2 の単体総ダメージの予算は突進 + 強化通常攻撃の上乗せ（物理攻撃 20% + 基礎）で数える。以前は汎用 S2 × 0.81 |
| S2: 次の通常攻撃が強化: 75〜150（+120% 総物理攻撃）+ 60% 鈍足 1 秒、射程 2.5 | ○ | 突進が**着いたとき**に強化の窓が開く（ハード CC で突進が止まれば開かない）。窓が開いている間の次の通常攻撃（`shapeBasicAttack`）を **通常攻撃のダメージ × 1.2 + 基礎（`lerp(75, 150) × 3.0 × chargeScale`）に置き換え**（会心は 1.2 倍の側に乗る）、鈍足 60%・1 秒。1 回で消える。**射程は公式の 2.5 = 250**（窓の間だけ通常攻撃の射程に +100 の `attackRangeBoost`、使うと消える）。以前は通常攻撃に汎用 S2 × 0.23 を足していた。HUD は S2 に残り時間のバッジ |
| S2 強化の持続（不明） | ○ | 4 秒（汎用の強化通常攻撃 `Balance.Skills.empowerDuration` と同じ） |
| S2 クールダウン 7 秒（全ランク） | ○ | MLBB と同じ 7 秒（以前は × 0.5 = 3.5 秒）。剣撃で縮む |
| S2 マナ 70 → 45（レベルが上がるほど安い。Liquipedia の 40〜60 は古い版） | ○（公式） | `HeroKit.cost` で 70 / 61.7 / 53.3 / 45（× 0.6）。以前はマスターの 55 |
| 奥義: 対象の敵ヒーローへ突進（ポイント＆クリック） | ○ | `.targetedBlink`（`requiresTarget`・`AimShape.lockOn`）。敵ヒーロー限定（ミニオンは選べず、居なければ消費せず失敗）。指定ユニット/地点/方向/自動の照準は汎用の対象指定ブリンクと同じ（`SkillAiming.blinkTarget`）。射程は術者の中心から対象の縁まで 500（調査の 4.6（旧 5.9）≈ 460 に突進のしやすさを足した。マスターは 600）。`Kit.dashSweeping`（経路の敵には当たらない）で速度 2600（約 0.2 秒）、対象の縁で止まる |
| 奥義: 1.2 秒打ち上げ（Resilience 無効） | △ | 到着時に `knockUp` 1.2 秒。Velstria に Resilience（CC 短縮）は無いので、CC 無効（`ccImmune`）・無敵の相手に**は掛からない**（その場合も三連撃は続ける） |
| 奥義: 打ち上げ中に 3 回撃つ。1・2 撃目 120 / 150 / 180（+100% 追加物理攻撃）、3 撃目 240 / 300 / 360（+200%） | ○ | 到着後 0.2 / 0.6 / 1.0 秒に 3 撃（`strikeSequence`）。1・2 撃目 = `(lerp(120, 180) + 1.0 × 攻撃力 × 0.6) × 奥義の倍率 2.6 × ultScale`、3 撃目はちょうどその 2 倍（公式も基礎・係数とも 2 倍）= 重み 0.75 : 0.75 : 1.5。各撃も防御ダウンの層を積む。以前は汎用奥義 × 0.85 を 1 : 1 : 2 に分けていた |
| 奥義の最初の 2 撃は剣撃を使う（3 撃目は使わない） | ○ | 通常の剣撃ルールに乗る（S1 の剣が回っているとき）。3 撃目だけは `ints[1]`（剣撃ロック）で剣撃を出さない。間隔 0.4 秒 > 剣撃の間隔 0.25 秒なので、1・2 撃目はそれぞれ 1 本を飛ばす |
| 奥義の中断: 打ち上げたあとは制圧（suppress）でのみ中断、最初の突撃はノックバック・打ち上げで止まる（公式の注記）。無敵/対象不可の記載なし | ○ / △ | 無敵/対象不可は**無し**。突進中はハード CC（スタン・打ち上げ・suppress）で中断（突撃が止まり外れる）。**三連撃（段 2）は CC では止まらず、suppress だけが止める**（連撃の予約は `interruptible: false`、`update` と各撃で suppress を見る）。以前はスタンでも残りの撃が消えた。三連撃の間は術者は動けず（root + channeling）、通常攻撃も始めず、ほかのスキルも使えない（`canStart`）。対象の打ち上げは時間まで残る・クールダウンは戻らない |
| 奥義 CD 44 / 40 / 36、マナ 100 / 120 / 140 | ○（公式） | CD は公式の 44 / 40 / 36 秒。**マナは `HeroKit.cost` で 100 / 120 / 140**（× 0.6 = 60 / 72 / 84。以前はマスターの 92 × 0.6） |
| 対象が途中で倒れる/離れる | ○ | 対象が倒れる・術者から（半径 + 260）以上離れる・対象不可になると、残りの撃を取り消して終える（突進の到着時も同じ判定）。術者が倒れると全リセット（予約・root も） |
| ボット: 奥義 | ○ | 交戦中の敵ヒーローが射程内（500 + 半径）で、HP が 60% 以下なら `.castNow`（汎用の関門を待たずに今撃つ）、それより多ければ `.cast`（汎用の関門 = 倒せる・2 体以上 を通ったとき）。以前の「HP 80% 未満か剣が回っている」は、剣がほぼ常に回っているので意味が無かったため外した |
| 通常攻撃: 近接単体。射程 2.5（公式では強化通常攻撃の射程） | △ | 通常の通常攻撃は汎用の近接 150。2.5 は強化通常攻撃の射程として S2 に入れた（上） |
| チーム/周辺ルール（再使用など） | – | Saber に再使用は無いので窓は使わない（HUD の `recastable` は false） |
| スキルのタグ（UI） | ○ / △ | パッシブ `disrupt`（公式 Debuff に当たるキーが無いので「妨害」で近似）、スキル1 `aoe buff`、スキル2 `mobility aoe`（Blink = 移動）、アルティメット `burst disrupt`（CC = 妨害）。`KitText.tags` / `HeroKits.tags` |

### 選んだ値（調査に無い・割れていた・換算した値）

| 項目 | 値 | 理由 |
|---|---|---|
| 剣の周回半径 | 230（対象の縁まで） | 近接の通常攻撃（150 + 双方の半径）の外側まで届き、至近の敵を覆う。調査に無い |
| 接触の間隔/回数 | 0.5 秒 × 9 回 | 調査に無い。5 秒の周回を 0.5 秒刻みの接触として表現（複数の剣の接触を 1 回に畳み込む） |
| 剣撃の飛行時間・最短間隔 | 0.12 秒・0.35 秒 | 調査に無い。多段ヒット（突進の通り道・接触）で何本も飛ばさないための間隔（0.25 秒から延ばし、剣撃を「何度でも出る」から「おおむね通常攻撃 1 回に 1 本」にした） |
| 突進の速度 | S2 1800 / 奥義 2600 | 汎用の突進（1500）より鋭い。奥義は「対象指定の踏み込み」に見える速さ |
| 三連撃の間隔 | 0.2 / 0.4 秒 | 調査は「打ち上げの間に 3 回」のみ。1.2 秒の打ち上げに収まる（最後が 1.0 秒） |
| S1 のクールダウン | 9 秒 | Fandom の現行（公式）。Liquipedia・mlbb.tools の 10 秒は古い版 |
| Charge の短縮 | 1 秒/本 | 1 秒と 0.5 秒で割れていた。1 秒を採る（全体の CD が半分だったころは 0.5 秒） |
| ダメージの換算 | `swordsScale`（接触・剣撃）/ `chargeScale`（突進・強化の基礎）/ `ultScale`（三連撃） | 公式の表（ランクで補間 + 攻撃力係数）を sim の通常の式 × スロット倍率に通したあとに掛ける。値は下の「公式の数値へ（2026-10）」 |

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

- コストは公式のマナ（S1 75 → 125、S2 70 → 45、奥義 100 / 120 / 140）に `energyCostMultiplier`（0.6）を掛けた Energy で払う（ザイルはマスターデータで Energy のヒーロー）。
- 接触ダメージは 0.5 秒ごとの円（周回半径内の全員）で、剣が実際にどこを回っているかは見ない。剣の本数による減衰も無い。
- 防御ダウンは `armorShred`（割合）で、ほかの防御ダウン（装備の防御低下やほかのキットの防御ダウン）と重なると最大の 1 つだけが効く（既存の仕様）。防御が低い相手では割合の上限 0.9 で止まる。
- 強化通常攻撃は公式どおり「置き換え」（通常攻撃のダメージ × 1.2 + 基礎）。会心のときは 1.2 倍の側にだけ会心倍率が乗る（基礎には乗らない）。
- 剣撃は通常攻撃・S2・奥義の「ダメージを与えた」命中で呼ばれる。ミニオンへの攻撃でも飛ぶが、ヒーロー以外の敵へのダメージは公式どおり 50%。防御ダウンの層はミニオンに積まれない。
- S1 のクールダウンは公式（Fandom の現行）の 9 秒（持続 5 秒）なので、剣が回っているのは約 55%。剣撃の間隔 0.35 秒は、全体の CD が半分で剣が常に回っていたころに火力が過大にならないよう決めた値のまま。
- 奥義の中断は公式の注記どおり（突撃中は CC で止まる、打ち上げたあとは suppress だけ）。三連撃の最中にスタンされても撃ち切るので、以前（スタンで残りが消えた）より強い。
- 死亡で術者の状態は全リセットされるが、敵に付いた防御ダウンの層は期限（最大 5 秒）まで残る。

### クールダウンを MLBB の秒数に（2026-10）

- 全体の CD 倍率 0.5 を廃止（S1 10 秒・S2 7 秒・奥義 44 / 40 / 36 秒）。剣撃の短縮は MLBB の 1 秒。S1 だけ全体倍率のまま（`Tune.swordsCooldownScale`）にしていた特例は不要になったので外した（ほかのヒーローとの相対的な間隔は以前と同じ）。数値は変えていない。
- `KitBalanceTests`（アサシン中央値との差）: 変更前 +4.2 / −9.5 / −1.8 → 変更後 +15.0 / +29.7 / +14.3 pt（汎用のアサシンの中央値が Lv6 で 54.9 → 45.6% に下がったぶん）。

### 公式の数値へ（2026-10）

Fandom の現行のスキル表（上の「公式（MLBB Fandom 現行）の数値」）に、クールダウン・コスト・ダメージの表・CC・挙動を合わせた（H029 ボルグと同じ方法）。

| 項目 | 公式 | 変更前 | 変更後 |
|---|---|---|---|
| パッシブ 1 層あたり | 3 / 3 / 3 / 4 / 4 / 4 / 5 / 5 / 5 / 6 / 6 / 7 / 7 / 7 / 8（Lv1〜15） | 3 → 8 の線形（Lv8 = 5.5） | 公式の表（Lv8 = 5） |
| S1 クールダウン | 9.0（一定） | 10 | 9 |
| S1 コスト | 75 → 125 | マスター 45（× 0.6 = 27） | 75 / 91.7 / 108.3 / 125（× 0.6 = 45〜75） |
| S1 接触 | 80 → 105（+30%） | 汎用 S1 × 0.55 ÷ 9（Lv1 49 / Lv12 85） | `(80 → 105 + 0.3 × 攻撃 × 0.6) × 4.0 × 0.12`（Lv1 48 / Lv12 64） |
| S1 剣撃 | 210 → 260（+60%）、他の敵 50%、ヒーロー以外 50%、突進 CD −1 秒 | 汎用 S1 × 0.19（Lv1 152 / Lv12 263）、ヒーロー以外も 100% | `(210 → 260 + 0.6 × 攻撃 × 0.6) × 4.0 × 0.12`（Lv1 121 / Lv12 152）、ヒーロー以外 50% |
| S2 クールダウン・コスト | 7.0・70 → 45 | 7・マスター 55（× 0.6） | 7・70 / 61.7 / 53.3 / 45（× 0.6） |
| S2 突進 | 75 → 150（+50%） | 汎用 S2 × 0.81（Lv1 506 / Lv12 891） | `(75 → 150 + 0.5 × 攻撃 × 0.6) × 3.0 × 1.05`（Lv1 346 / Lv12 624） |
| S2 強化通常攻撃 | 75 → 150（+120% 総物理攻撃）、60% 減速 1 秒、射程 2.5 | 通常攻撃 + 汎用 S2 × 0.23（Lv1 260 / Lv12 413）、射程 150 | 通常攻撃 × 1.2 + `(75 → 150) × 3.0 × 1.05`（Lv1 375 / Lv12 665）、射程 250 |
| 奥義 クールダウン・コスト | 44 / 40 / 36・100 / 120 / 140 | 44 / 40 / 36・マスター 92（× 0.6） | 44 / 40 / 36・100 / 120 / 140（× 0.6） |
| 奥義 三連撃 | 120 / 150 / 180（+100%）× 2 + 240 / 300 / 360（+200%）、1.2 秒打ち上げ | 汎用奥義 × 0.85 を 1 : 1 : 2（合計 Lv1 766 / Lv12 1194） | `(120 → 180 + 1.0 × 攻撃 × 0.6) × 2.6 × 0.44` × 2 + その 2 倍（合計 Lv1 868 / Lv12 1263）、打ち上げ 1.2 秒 |
| 奥義の中断 | 打ち上げたあとは suppress のみ、突撃は CC で止まる | 突撃・三連撃ともハード CC で中断 | 突撃は CC で中断、三連撃は suppress のみ |
| タグ | Debuff / AOE・Buff / Blink・AOE / Burst・CC | なし | `disrupt`（Debuff のキーが無いので近似）/ `aoe buff` / `mobility aoe` / `burst disrupt` |
| 説明文 | — | 独自の文 | 公式の文の構造（`{base}(+{atkPct}%物理攻撃)` は換算後の値） |

（ダメージの例は Lv1 = ランク 1、Lv12 = S1/S2 ランク 4・奥義ランク 3。攻撃力は装備なしの値。奥義の Lv1 の列は Lv1 の攻撃力・ランク 1 での参考値。）
換算（`swordsScale` 0.12 / `chargeScale` 1.05 / `ultScale` 0.44）は勝率で決めた。予算（汎用の何倍か）は S1 0.75〜1.0（公式の表がランクで緩やかにしか伸びないのでランク 4 で 0.8 を割る。テストの下限は 0.7）、S2 0.95〜1.04、奥義 0.85〜1.02。

`KitBalanceTests`（Release。アサシン中央値との差、pt）:

| | Lv1 | Lv6 | Lv12 |
|---|---|---|---|
| 変更前（クールダウンを MLBB の秒数にした直後） | +15.0 | +29.7 | +14.3 |
| 公式の表へ置き換えた直後（換算 0.14 / 1.0 / 0.42） | +27.1 | +9.0 | +2.1 |
| **今回**（換算 0.12 / 1.05 / 0.44） | +14.8（44.4% / 中央値 29.7） | +2.4（49.0% / 46.6） | −0.4（47.5% / 47.9） |

S1 のクールダウンが 10 → 9 秒になり、Lv1（スキル1 だけの決闘）が強くなった。S1 の換算は Lv1 にとても敏感（0.14 → 0.128 で −9 pt、0.12 でさらに −7 pt）で、0.128（予算の下限）では +18 pt と帯の外だった。S1 を下げたぶん Lv6 / Lv12 は突進と奥義で戻した（S2 1.15・奥義 0.50 では Lv6 / Lv12 が +19 / +16 pt まで上がりすぎた）。

Lv1 の +14.8 は帯（±15 pt）の端。開幕 3 秒の瞬間火力の比（同ロール中央値に対する倍率、報告のみ）: 変更前 3.36 / 2.25 / 2.39 → 今回 3.06 / 2.10 / 2.23。Release の全テスト 981 件・失敗 0（スキップ 6）。
