# Alucard (MLBB) - Kit Specification

> 2026-10-14: ヒーローの能力値（HP・物理攻撃・防御・魔防・攻撃速度・HP 回復・マナ・移動速度・射程・リソースの種類）と能力値の式（防御 120/(120+防御)・クリティカル 200%・攻撃速度の加算・移動速度の加算式など）を MLBB の値へ置き換えた（`docs/HERO_STATS.md`）。
> 同日、スキルも**公式の表をそのまま使う（6 / 6 / 3 段）**ようにした（下の「Velstria 実装対応表」と「公式の表へ（2026-10-14）」）。スロット倍率・物理係数の × 0.6・キットの換算（`s1Scale` など）・補間は無い。

**正は下の「日本語クライアントの画面（2026-10-11・無加工の原本）」**、次に「公式（MLBB Fandom 現行）の数値」（2026-10 に MediaWiki API で取得した Fandom の現行のスキル表）。それより上のウェブ調査と食い違う値は公式が優先する。

Values come from Mobile Legends Fandom / Liquipedia search extracts plus mlbb.io, mlbb.tools and guide sites (direct Fandom/Liquipedia fetch was blocked). "unknown" = not found. "disputed" = sources disagree.

## Hero overview
- Role / lane: Fighter / Assassin, jungle (EXP lane also common). Melee.
- Resource: none (0 mana); skills have no mana cost.
- Basic attack: melee single target. After any skill cast, the next basic attack becomes a dash (Pursuit).
- Attack range: disputed. Search extracts gave 1.8 for most melee heroes; one extract listed a stray value of 4 (likely the Malefic Gun passive range bonus, not a base value). Treat as 1.8 (low confidence).
- Base stats at level 1 (Fandom / mlbb.io): HP 2443, regen 7.8, physical attack 123, physical defense 21, magic defense 15, attack speed 1.13, movement speed 260.
- Growth per level: HP +225, regen +0.44, phys attack +8.64, phys defense +4.6429, magic defense +2.5, attack speed +0.0293 (level 15: HP 5593, attack 244, phys def 86, attack speed 1.54).
- Disputed (mlbb.tools): HP 2621, regen 7.8, phys attack 126, phys defense 20, magic defense 10, attack speed 0.88. Prefer Fandom/mlbb.io.
- Max skill levels: S1 6, S2 6, Ultimate 3.

## Passive - Pursuit
- Cast type: passive, enhances next basic attack.
- After each skill cast, Alucard's next basic attack dashes to the target's location and deals physical damage equal to 140% Total Physical Attack (mlbb.io, oneesports-style). Disputed: mlbb.tools lists 125% (older value). Deals 110% damage to creeps (mlbb.tools only).
- Window for using the empowered attack, dash range, passive cooldown: unknown.

## Skill 1 - Groundsplitter
- Cast type: ground-targeted leap/roll (dash to target area) with AoE slam.
- Effect: rolls to the target location and slams his blade, dealing 270 (+85% Extra Physical Attack) physical damage to enemies hit and slowing them by 40% for 2 s. Scaling coefficient disputed: +80% in one extract, +85% in the Fandom text.
- Cooldown by level: 8.5 s at level 1 down to 6.5 s at level 6 (intermediate steps = unknown).
- Base damage: 270 at level 1 up to 370 at level 6.
- Cast range, radius: unknown. Cost: none.

## Skill 2 - Whirling Smash
- Cast type: self-centered AoE spin/slash (no aim).
- Effect: launches a whirling slash dealing 345 (+120% Extra Physical Attack) physical damage to nearby enemies.
- Cooldown: 6.0 s at level 1 down to 4.0 s at level 6.
- Base damage: 345 at level 1 up to 570 at level 6.
- Radius: unknown. Cost: none.

## Ultimate - Fission Wave
- Cast type: ground-targeted AoE (absorb) then recast directional skillshot.
- Passive part: permanent Hybrid Lifesteal. Level values disputed: 10% (all levels) per Fandom-style text vs 10% / 20% / 30% by level in another extract.
- Active: absorbs the energy of enemies in the target area, reducing their movement speed by 30% and Hybrid Defense by 10. Alucard gains Hybrid Defense (10) for each enemy hero hit, and reduces the cooldown of his other skills to 50% for 6 s.
- Recast (Use Again): releases a shockwave in the target direction dealing 400 (+200% Extra Physical Attack) physical damage to enemies hit. Recast window length, shockwave range/width: unknown.
- Cooldown by level: 40 / 35 / 30 s (level 2 = 35 from one extract; endpoints 40 and 30 agreed).
- Base damage: 400 / 550 / 700. Cost: none.
- Slow/defense-debuff duration: unknown.

## Gameplay identity
- Skirmisher/lifesteal brawler: skill, then dash-basic-attack, chaining mobility and damage.
- Gap-closer via Groundsplitter plus Pursuit dash gives constant re-engagement.
- Ultimate halves other cooldowns for 6 s, enabling skill-spam burst windows; lifesteal is permanent.
- Rewards multi-skill rotations instead of waiting on cooldowns; no mana to manage.

## Simulation notes
- Standard: ground-target leap with slow, self AoE, skillshot recast, flat/percent lifesteal, defense debuff, movement slow.
- Needs special state: "next basic attack dashes" flag set by any skill cast (with dash); ultimate recast window and timed cooldown-rate modifier (other skills at 50% cooldown for 6 s); per-hit hero-count scaling of gained defense; permanent hybrid lifesteal attribute scaling with ult level.

## Sources
- https://mobile-legends.fandom.com/wiki/Alucard (via search extract)
- https://liquipedia.net/mobilelegends/Alucard (via search extract)
- https://mlbb.io/en/hero/alucard
- https://mlbb.tools/heroes/alucard
- https://www.oneesports.gg/mobile-legends/alucard-best-build-guide/
- https://mobile-legends.fandom.com/wiki/Hybrid_Lifesteal

## 公式（MLBB Fandom 現行）の数値

`https://mobile-legends.fandom.com/api.php?action=parse&page=Alucard&prop=wikitext&format=json` の `{{Ability}}` をそのまま転記（Liquipedia の表とも一致。違いは S1 の係数 +85% と奥義の吸血の書き方だけ）。スキルのレベルは S1・S2 が Lv1〜6、アルティメットが Lv1〜3。

| スロット | 公式名 | タグ | 内容 |
|---|---|---|---|
| パッシブ | Pursuit | Buff | スキルを発動するたびに、次の通常攻撃で対象の位置へ踏み込み（+125% 総物理攻撃）の物理ダメージ。強化通常攻撃の射程 4 |
| スキル1 | Groundsplitter | Blink・AOE | CD 8.5 / 8.1 / 7.7 / 7.3 / 6.9 / 6.5、コストなし。指定エリアへ跳び込んで斬り、命中した敵に 270〜370（+80% 追加物理攻撃。Liquipedia は +85%）+ 40% 減速 2 秒。基礎 270 / 290 / 310 / 330 / 350 / 370 |
| スキル2 | Whirling Smash | AOE | CD 6.0 / 5.6 / 5.2 / 4.8 / 4.4 / 4.0、コストなし。回転斬りで周囲の敵に 345〜570（+120% 追加物理攻撃）。基礎 345 / 390 / 435 / 480 / 525 / 570 |
| アルティメット | Fission Wave | Buff・Burst | CD 40 / 35 / 30、コストなし（最初の発動で CD に入る）。パッシブ: 常に複合吸血 10 / 20 / 30%。アクティブ: 指定エリアの敵のエネルギーを吸収し、移動速度 −30%・複合防御 −10 / 15 / 20。命中した敵ヒーロー 1 体につき複合防御 +10 / 15 / 20、6 秒間ほかのスキルの CD を 50% に（持続 6.0）。再使用: 指定方向へ衝撃波、400 / 550 / 700（+200% 追加物理攻撃）。敵が居なくても強化は得る |

段の対応: 公式の表をそのまま使う（S1・S2 = Lv1〜6、アルティメット = Lv1〜3。rank = 公式の Lv。補間なし）。「追加物理攻撃」の係数は追加物理攻撃（`Stats.extraAttack`）に掛ける。

## 日本語クライアントの画面（2026-10-11・無加工の原本）

2026-10-11 に受け取った日本語クライアントのスキル詳細の画面の無加工のスクリーンショット（IMG_4546〜4555。画像はコミットしない）。日本語版の名前は「アルカード(Alucard)」。
**これが一次資料**で、Fandom・Liquipedia より優先する。どのスキルもコストの表示が無い（コストなし）。

| 枠 | 日本語版の名前 | タグ | CD | MP | 内容（原本の文の要約） |
|---|---|---|---|---|---|
| パッシブ | チェイス | バフ | – | – | スキルを発動するたびに、次の通常攻撃で対象へダッシュし、(125% 物理攻撃) の物理ダメージ。**デビルハンター: モンスターに対して 110% のダメージを与える** |
| スキル1 | グランドスプリッター | ブリンク・範囲技 | 8.5 / 8.1 / 7.7 / 7.3 / 6.9 / 6.5 | なし | 指定エリアへ跳躍して斬りつけ、範囲内の敵に 270 / 290 / 310 / 330 / 350 / 370 (**+85% 追加物理攻撃**) の物理ダメージ、移動速度を 2 秒間 40% 低下 |
| スキル2 | サークルスマッシュ | 範囲技 | 6.0 / 5.6 / 5.2 / 4.8 / 4.4 / 4.0 | なし | 回転斬りで周囲の敵に 345 / 390 / 435 / 480 / 525 / 570 (+120% 追加物理攻撃) の物理ダメージ |
| アルティメット | フィッションウェーブ | バフ・爆発力 | 40 / 35 / 30 | なし | パッシブ: 混合吸収が永久に 10 / 20 / 30% 上昇。アクティブ: 指定範囲内の敵のエネルギーを吸収し、移動速度を 30%、混合防御を 10 / 15 / 20 低下。命中した敵ヒーロー 1 体につき自身の混合防御が 10 / 15 / 20 上昇し、6 秒間、他のスキルの CD 時間が 50% に短縮。再発動: 前方に強力な衝撃波、400 / 550 / 700 (+200% 追加物理攻撃) の物理ダメージ |

置き換えた値（変更前 → 変更後）:

| 項目 | 変更前 | 変更後 |
|---|---|---|
| スキル1 の係数 | +80%（Fandom） | **+85%**（原本。Liquipedia も 85%）。`Tune.s1AttackRatio` 0.8 → 0.85（2026-10-14 から `Tune.s1ExtraAttackRatio`。追加物理攻撃に掛ける） |
| デビルハンター | 無し（調査では mlbb.tools にだけあり「古い値」として採らなかった） | **モンスター（`UnitKind.monster` = ジャングル・バフ・亀・ロード）への通常攻撃・スキルのダメージ 110%**（当時は `outgoingDamageBonus` で +10% の加算。2026-10-14 に `HitPayload.monsterMultiplier` 1.1 の掛け算へ）。ミニオン・ヒーロー・構造物には掛からない |
| パッシブの文 | 追撃の 1 文 | 原本どおり「デビルハンター：モンスターに対して{devilHunter}%のダメージを与える。」を足した |

デビルハンターの範囲の判断: 原本の文は「モンスターに対して 110% のダメージを与える」で、追撃（チェイス）の文とは別の行にあり、追撃に限るとは書いていない。
そのため **ヴァルド自身の通常攻撃とスキルのすべてのダメージ**に掛けた（バトルスペル（`DamageSource.spell`）と装備の追加ダメージ（`.item`）は「ヴァルドの攻撃」ではないので除く）。
Liquipedia の英語の文は「Demon Hunter: Alucard deals 10% extra damage to Creeps」。日本語クライアントの「モンスター」に合わせ、ミニオンには掛けない。
2026-10-14 から、ヴァルドの命中（通常攻撃の `BasicAttackPlan.payload`・S1 の叩きつけ・S2・衝撃波）の `HitPayload.monsterMultiplier` = 1.1（防御の後の掛け算）。
ほかの与ダメ補正（装備のモンスター補正・懲罰の後の +30% など。`CombatSystem.dealDamage` の加算の `bonus`）とは**掛け算**で重なる（以前は足し算）。
MLBB でどちらなのかは未確認（監査 C6）。確かめるには、デビルハンターと別の与ダメ補正を両方持った状態の練習場の読み取りが要る。

アルティメットは原本の表（混合吸収 10 / 20 / 30%・混合防御減少 10 / 15 / 20・混合防御力増加 10 / 15 / 20・基礎ダメージ 400 / 550 / 700、CD 40 / 35 / 30）と実装が一致することを確かめた（変更なし）。
「6 秒間、他のスキルの CD 時間が 50% に短縮」は文の上では「敵ヒーロー 1 体につき」の続きにも読めるが、Fandom の注記（「敵が居なくても強化は得る」）に合わせて、
これまでどおり**吸収を撃てば敵ヒーローに当たらなくても得る**（複合防御の上昇だけが敵ヒーローの数に比例する）。タグ（`buff` / `mobility aoe` / `aoe` / `buff burst`）も原本と一致。

原本の文（2026-10-14 に画像 IMG_4546〜4554 から読み直した。説明文はこれに合わせた）:
- パッシブ: 「スキルを発動するたびに、次の通常攻撃で対象へダッシュし、(125%物理攻撃)の物理ダメージを与える。」「デビルハンター：モンスターに対して110%のダメージを与える。」（125% に「+」は付かない = 合計の物理攻撃）
- スキル1: 「指定エリアへ跳躍して斬りつけ、範囲内の敵に270(+85%追加物理攻撃)の物理ダメージを与え、移動速度を2秒間40%低下させる。」
- スキル2: 「回転斬りを放ち、周囲の敵に345(+120%追加物理攻撃)の物理ダメージを与える。」
- アルティメット: 「パッシブ：混合吸収が永久に10%上昇する。」「アクティブ：指定範囲内の敵のエネルギーを吸収し、移動速度を30%、混合防御を10低下させる。命中した敵ヒーロー1体につき自身の混合防御が10上昇し、6秒間、他のスキルのCD時間が50%に短縮される。」「再発動：前方に強力な衝撃波を放ち、400(+200%追加物理攻撃)の物理ダメージを与える。」
- どのスキルの画面にも「スキル吸収率」「攻撃エフェクト」の行は無い（アイコンガイドの「物理スキル: このダメージにはスキル吸収が適用される」「物理通常攻撃: 攻撃効果と通常攻撃吸収が発動する」だけ）。

## Velstria 実装対応表

H033 紅牙のヴァルド（アサシン・近接・リソースなし）= Velstria 版の Alucard。実装: `Packages/VelstriaCore/Sources/VelstriaCore/Systems/Kits/Kit_H033.swift`、
テスト: `Tests/VelstriaCoreTests/Kits/Kit_H033Tests.swift`、演出: `App/Battle/SkillFX/Heroes/FX_H033.swift`。
スロットは上の調査の順に割り当てる（Skill1 = Groundsplitter、Skill2 = Whirling Smash、Ultimate = Fission Wave、Passive = Pursuit）。
マスターデータ上の最終名は パッシブ「吸血の渇き」/ スキル1「裂地撃」/ スキル2「旋回斬」/ アルティメット「核分裂波」（`tools/rename_kit_skills.mjs`）。説明文は UI の用語（スキル1・スキル2・アルティメット）で書く。マスターの `cc`（S1 = Slow、S2 = なし、奥義 = Slow）は調査と一致する。
名前の注記（監査 §6-4）: パッシブの名前「吸血の渇き」は中身（チェイス = 追撃）と合わない。吸血（混合吸収）は奥義のパッシブにある。名前は Velstria のローカライズの選択なので、このキットでは変えていない（説明文の仕組みは正しい）。
キットは汎用のアサシンのパッシブ（草むら/ステルス解除後の奇襲 +30% とキル/アシストの全 CD −30%）を **置き換える**（Alucard にどちらも無いので移植しない）。
距離は Velstria 単位（≈ MLBB × 100）。公式に無い値（射程・半径・窓・持続など）は下の「選んだ値」に書いた。

**公式の表をそのまま使う（S1・S2 = 6 段、アルティメット = 3 段）。** rank = 公式の Lv（rank 1 = Lv1 … rank 6 = Lv6、奥義 rank 1〜3 = Lv1〜3）で、`Kit.level` で表を引く（補間なし）。
ダメージ = 公式の基礎[Lv] + 公式の係数 × 能力値（`Kit.official`）。「(+N%追加)」は**追加物理攻撃**（`Stats.extraAttack` = 装備・エンブレム・バフで増えた分。装備なしは 0）、
追撃の「(125%)」は合計の物理攻撃。スロット倍率・物理係数の × 0.6・キットの換算は無い。CD = 表の秒数 × (1 − CD 短縮)（`Kit.cooldown`）。

### 公式の表（日本語クライアント = REAL_DATA.md。Liquipedia の表とも一致）

| スキル1・スキル2 | Lv1 | Lv2 | Lv3 | Lv4 | Lv5 | Lv6 | 係数 |
|---|---|---|---|---|---|---|---|
| スキル1 基礎ダメージ | 270 | 290 | 310 | 330 | 350 | 370 | +85% 追加物理攻撃 |
| スキル1 CD（秒） | 8.5 | 8.1 | 7.7 | 7.3 | 6.9 | 6.5 | |
| スキル2 基礎ダメージ | 345 | 390 | 435 | 480 | 525 | 570 | +120% 追加物理攻撃 |
| スキル2 CD（秒） | 6.0 | 5.6 | 5.2 | 4.8 | 4.4 | 4.0 | |

| アルティメット | Lv1 | Lv2 | Lv3 | 係数 |
|---|---|---|---|---|
| CD（秒） | 40 | 35 | 30 | |
| 混合吸収 | 10% | 20% | 30% | |
| 混合防御減少 | 10 | 15 | 20 | |
| 混合防御力増加（敵ヒーロー 1 体につき） | 10 | 15 | 20 | |
| 衝撃波 基礎ダメージ | 400 | 550 | 700 | +200% 追加物理攻撃 |

全段で一定: 追撃 (125% 物理攻撃)、デビルハンター（モンスターに 110%）、スキル1 の減速 40% 2 秒、吸収の減速 30%、他のスキルの CD 50%（6 秒）。どのスキルもコスト無し。

### 対応表（○ = 実装、△ = 簡略化、× = 見送り）

| 元の仕様 | 状態 | Velstria での実装・理由 |
|---|---|---|
| 近接・単体の通常攻撃 | ○ | 能力値は MLBB の値（`docs/HERO_STATS.md`） |
| リソース無し（コスト 0） | ○（公式） | **`HeroKit.cost` で全スキル 0** |
| パッシブ チェイス: スキルを発動するたび、次の通常攻撃で対象へダッシュし、**(125% 物理攻撃)** の物理ダメージ | ○（公式） | `onSkillCast`（S1・S2・奥義の 1 回目）と奥義の再使用（衝撃波）で準備（`timers[0]`）。次の通常攻撃（`shapeBasicAttack`）が 1.25 倍（会心はそのまま掛かる）になり、敵の目の前まで `MovementSystem.dash`（速さ 2600）で踏み込む。1 回で使い切る。攻撃エフェクトは通常攻撃そのもの（100%） |
| デビルハンター: モンスターに 110% | ○（日本語クライアント） | ヴァルドの命中（すべての通常攻撃・S1 の叩きつけ・S2・衝撃波）の **`HitPayload.monsterMultiplier` = 1.1**（防御の後の掛け算。以前は与ダメ補正の加算 +10%）。`UnitKind.monster` だけ（ミニオン・ヒーロー・構造物・バトルスペル・装備の追加ダメージには掛からない） |
| チェイスの猶予・パッシブ CD（記載なし）、強化通常攻撃の射程 4（Fandom） | ○ / △ | 猶予 5 秒（選んだ値）、射程 400（準備中は通常攻撃の射程が +250 伸びる `attackRangeBoost`）、CD は無し。猶予が切れる/使うと射程は戻る。HUD のバッジは残り秒 |
| チェイスは「対象へダッシュしてダメージ」 | △ | 命中（ダメージ・吸収）は通常攻撃が発射された tick に即時で、踏み込みはその直後（約 0.1 秒）。ルート（バインド・自分の足止め）中は踏み込めない（ダメージは乗る）。構造物には 125% も踏み込みも乗らない（準備は消費される） |
| 奥義のパッシブ: 混合吸収が永久に 10 / 20 / 30% 上昇 | ○（公式） | 奥義を習得している間は常に `lifestealBoost`（通常攻撃吸収）と `spellVampBoost`（スキル吸収）に**同じ値**（無期限のステータス。ランクが上がれば大きさだけ更新、未習得は 0）。スキル吸収率はどのスキルも既定の 100%（日本語クライアントに記載なし。下の「スキルごとの割合」）。以前のスキル吸収 × 0.33（`spellVampFactor`）は廃止 |
| S1 グランドスプリッター: 指定エリアへ跳躍して斬りつけ、**270〜370（+85% 追加物理攻撃）**、40% 減速 2 秒 | ○ / △ | 跳躍の archetype（`leapSlam`、地点指定）。`dashSweeping`（速さ 1800）で指定地点（最大 350）まで転がり、**転がり終えた tick に 1 度だけ**半径 190 の円へ叩きつける（経路の敵には当たらない）。対象を指定したときは対象の縁の手前で止まる。減速はミニオン・モンスターにも。転がりはノックアップ・制圧で止まり（叩きつけは出ない）、スタンでは止まらない。バインド・自分の足止め中は撃てない |
| S1 CD 8.5〜6.5 秒（6 段）、コスト無し | ○（公式） | 表のとおり。コスト 0 |
| S2 サークルスマッシュ: 照準なし、自分中心の回転斬りで **345〜570（+120% 追加物理攻撃）** | ○ / △ | `selfAoE`、照準なし。発動した tick に半径 250（記載なし）の敵（ヒーロー・ミニオン・モンスター）へ。ミニオンへの補正は無い（公式に記載なし。以前の全体の × 0.2 も撤廃済み）。CC なし |
| S2 CD 6.0〜4.0 秒（6 段）、コスト無し | ○（公式） | 表のとおり。コスト 0 |
| 奥義 フィッションウェーブ（地点指定）: 範囲の敵のエネルギーを吸収、移動速度 −30%・**混合防御 −10 / 15 / 20** | ○ | `groundAoE` の 1 回目（`aim: .point`）。指定地点（最大 450）の周囲 300 の敵（ヒーロー・ミニオン・モンスター）に、`slow` 0.30 と `flatDefenseMod` −10 / 15 / 20（物理防御・魔法防御の固定値）を 4 秒（持続は記載なし）。吸収そのものにダメージは無い。無敵の相手には入らない |
| 奥義: 命中した敵ヒーロー 1 体につき自分の混合防御 **+10 / 15 / 20** | ○（公式） | `flatDefenseMod` +10 / 15 / 20 × 敵ヒーローの数を 6 秒。ミニオン・モンスター・無敵の相手は数えない。`ints[2]` に捉えた数を残す |
| 奥義: 6 秒間、他のスキルの CD 時間が **50%** に短縮 | ○（公式） | `timers[1]` = 6 秒の間、毎 tick に S1・S2 のクールダウンをもう 1 tick ぶん進める（= 通常の 2 倍の速さ = 残りの CD が半分の時間で終わる）。奥義自身は半減しない。スタン中も進む。練習場の `noCooldowns` を尊重（`Kit.refundCooldown`）。敵ヒーローに当たらなくても得る（Fandom の注記） |
| 奥義の再発動: 前方に衝撃波、**400 / 550 / 700（+200% 追加物理攻撃）**。窓・射程・幅は記載なし | ○ / △ | 同じ `castSkill`（`openRecast`、6 秒・1 回。CD・コストは使わない）。向き（`.direction` / `.unit` / `.none` は最寄りの敵ヒーロー → 向き）へ**貫通する直線弾**（長さ 900・半幅 130・速さ 2200）で、当たった全員（ヒーロー・ミニオン・モンスター）に 1 度ずつ。窓が切れる・死亡で衝撃波は出ない。スタン中は撃てないが窓は残る。バインド中も撃てる（術者は動かない） |
| 奥義 CD 40 / 35 / 30 秒、コスト無し | ○（公式） | 表のとおり（最初の発動で消費。再使用では変わらない）。コスト 0 |
| ボット: 衝撃波の再使用 | ○ | 共有部分（`BotCombat.castSkills`）が、再使用の窓が開いている奥義を汎用の関門（倒せる・2 体以上）に通さず `botCast` の判断だけで撃つ。`Kit_H033Tests.testBotRecastsTheShockwaveEvenWhenTheGateWouldBlockTheAbsorb` |
| ボット: ファーム | ○ | `botFarm` で裂地撃（スキル1。跳躍系）だけミニオン・ジャングルにも使う。HP が半分以上で、集団の位置が敵のタワー・コアの射程（750 + 半径 + 120）に入らないときだけ |
| S1 の命中をダメージの到着に合わせる（チェイス） | × | チェイスは発射した tick にダメージを出し、踏み込みはその直後のまま（到着まで待つには通常攻撃の主ヒットを止めて出し直す必要があり、会心・吸収・命中時効果・踏み込みが途切れたときの扱いが複雑） |
| 説明文・タグ | ○ | 日本語クライアントの文（上の「原本の文」）に合わせた。数値は `{base}(+{atkPct}%追加物理攻撃)` などのトークンで sim から（公式の表の値そのもの）。公式の文に無いのは、選んだ値（チェイスの猶予・射程、吸収の持続、再使用の窓）の括弧・前置きだけ。タグは公式どおり パッシブ `buff`、スキル1 `mobility aoe`（ブリンク）、スキル2 `aoe`、アルティメット `buff burst` |

### スキルごとの割合（HitPayload）

| 命中 | スキル吸収率 | 攻撃エフェクト | ミニオン | モンスター | 出典 |
|---|---|---|---|---|---|
| 通常攻撃・チェイス | —（通常攻撃吸収） | 100%（通常攻撃そのもの） | 100% | **110%** | デビルハンター = 日本語クライアントのパッシブ |
| スキル1 の叩きつけ | 100%（既定） | — | 100% | **110%** | スキル吸収率は記載なし |
| スキル2 | 100%（既定） | — | 100% | **110%** | 同上 |
| 衝撃波 | 100%（既定） | — | 100% | **110%** | 同上 |
| 吸収（ダメージ無し） | — | — | — | — | |

スキル吸収率: 日本語クライアントのスキル詳細（IMG_4546〜4554）にも Fandom・Liquipedia の表にも、Alucard のスキルの「スキル吸収率」は書かれていないので既定の 100%。
Fandom の用語の注記では、スキル吸収率は「ダメージ・範囲・持続によって通常 30〜120%」で、範囲スキルは低いことが多い。以前の実装は範囲スキルを 1/3 と見て
混合吸収のスキル吸収側を 0.33 倍にしていた（独自の値）が、出典が無いので外した。S1・S2・衝撃波はどれも範囲で、大勢に当てると回復は命中した人数ぶん（MLBB と同じく対象ごと）。

### 外した独自ルール・定数（2026-10-14）

| 定数・ルール | 旧値 | 新しい扱い |
|---|---|---|
| `Tune.s1Scale`（S1 の換算） | 0.66 | 廃止。公式の 270〜370 (+85% 追加) そのまま |
| `Tune.s2Scale`（S2 の換算） | 0.08 | 廃止。公式の 345〜570 (+120% 追加) そのまま |
| `Tune.waveScale`（衝撃波の換算） | 0.34 | 廃止。公式の 400 / 550 / 700 (+200% 追加) そのまま |
| スロット倍率 `Balance.Skills.damageScale`（S1 4.0 / S2 3.0 / 奥義 2.6）・物理係数 × `Balance.skillAttackScalingFactor`（0.6） | 掛けていた | 参照を削除 |
| 「追加物理攻撃」の係数を合計の物理攻撃に掛ける | 合計 | 追加物理攻撃（`KitScaling.extraAttack`）。装備なしの Lv1 の S1 は 865 → 270、S2 は 104 → 345、衝撃波は 481 → 400 |
| `Tune.spellVampFactor`（スキル吸収 = 混合吸収の 0.33 倍） | 0.33 | 廃止。スキル吸収も 10 / 20 / 30%、スキル吸収率は既定の 100% |
| `lerp`（6 段 → 4 段、奥義の (Lv1, Lv3) の補間）・CD の補間・`cooldownScale` | 補間 | `Kit.level` / `Kit.cooldown` で表を引く（6 / 6 / 3 段） |
| デビルハンターの与ダメ補正の加算（`outgoingDamageBonus` +0.10） | 加算 | `HitPayload.monsterMultiplier` 1.1（掛け算）。`outgoingDamageBonus` は実装しない |
| スタンで転がり（S1）が止まる | 止まる | 共通の CC の段階に合わせて、ノックアップ・制圧だけが止める（スタン中も着地して叩きつける） |

### 選んだ値（公式に記載が無い値）

| 項目 | 値 | 理由 |
|---|---|---|
| チェイスの猶予・射程・踏み込みの速さ | 5 秒・400（+250）・2600 | 猶予と速さは記載なし。射程は Fandom の強化通常攻撃の射程 4 |
| S1 の転がる距離・叩きつけの半径・速さ・隙間 | 350・190・1800・5 | 記載なし。近接スキルの標準 ≈ 300 に半径を足した |
| S2 の半径 | 250 | 記載なし。通常攻撃の射程 + 余裕（近接の回転斬り） |
| 吸収の中心を置ける距離・半径・鈍足と防御ダウンの持続 | 450・300・4 秒 | 記載なし。データ上の奥義の射程 600 に収まる（450 + 300 = 750 は届く最大の縁） |
| 再使用の窓 | 6 秒・1 回 | 記載なし。CD 50% と同じ長さにした |
| 衝撃波の長さ・半幅・速さ | 900・130・2200 | 記載なし。データ上の奥義の射程 600・半径 120 を、長い貫通の波へ伸ばした（標準の貫通弾の速さ 2200） |
| 説明文の数値 | `{base}` `{atkPct}`（公式の表の値）、`{pursuit}` `{window}` `{reachMult}` `{devilHunter}`、奥義の `{lifesteal}` `{defense}` `{gain}` `{debuff}` `{haste}` `{slow}` | 数値を sim とずらさない |

### まだ MLBB と違うところ・未確認

- 幾何と時間（上の「選んだ値」）はすべて推測。スキルのプレビューのスクショ（照準と通常攻撃の輪）と 60 fps の練習場の動画が要る（監査 §7）。
- スキル吸収率（S1・S2・衝撃波）は記載が無く既定の 100%。属性の吸収率の表示か、練習場で吸収の回復量の読み取りが要る。
- デビルハンターの範囲（ジャングル・バフ・亀・ロードのすべてか）とほかの与ダメ補正との重なり方（掛け算にした）は未確認（監査 C6）。読み取り: S2 と素の通常攻撃をジャングルのモンスター・ミニオン・亀に。
- 「6 秒間、他のスキルの CD 時間が 50% に短縮」は「残りの CD が 2 倍の速さで減る」で実装（6 秒の間に撃ったスキルの CD が半分になる、という読み方もありうる）。敵ヒーローに当たらなくても得る（Fandom の注記）。
- チェイスのダメージは発射した tick に即時（踏み込みはその直後）。スキルの発動の硬直（キャストの時間）は無い（全体の未実装、監査 C9）。
- 混合防御の増減は `flatDefenseMod`（物理防御・魔法防御に固定値）。同じ印の重ね掛けは大きい方の値（敵への −値は小さい方 = 弱い方が残る）なので、ランクの違う吸収が重なると弱い方の値になることがある。
- 汎用アサシンの奇襲（草むら/ステルス解除後 +30%）とキル/アシストの全 CD −30% を持たない（Alucard に無い）。

### バランス

公式の値そのままなので、キットの換算で勝率を合わせることはしない。Release の総当たり（`KitBalanceTests`、`testRoundRobinWinRatesStayNearTheGenericAssassins`）は、
全キットを統合した後に測り直す（帯の数値は変えていない）。以前の換算（`s1Scale` 0.66 / `s2Scale` 0.08 / `waveScale` 0.34）の版の記録: Lv1 / Lv6 / Lv12 のアサシン中央値との差は +3.7 / −5.3 / +7.2 pt（2026-10-11）。

### 既知の差・リスク

- スキルのコストは公式どおり 0。
- チェイスの「到着してからダメージ」ではなく、発射した tick にダメージ（踏み込みは直後）。踏み込み中に対象が死んでも、ダメージは出ている。
- 奥義の吸収の円と衝撃波の方向は別々に狙う（MLBB と同じ）。ボットは吸収を `BotCombat.castSkills` の奥義の条件（倒せる、または 2 体以上を巻き込める）と「交戦中・敵に届く」で撃つ。
  衝撃波は、窓が開いている間は共有部分が関門を通さず `botCast` の判断（敵ヒーローが届く距離に居れば撃つ）だけで撃つ。吸収そのものの条件は共有部分なので変えていない（ボットの 10 人戦の煙テストでは、試合によっては 1800 秒の間に一度も奥義の条件を満たさず、種を変えて撃つまで回す）。
- 演出: 現在の `SkillFXDirector` は `stage` を見ないので、衝撃波（stage 1）でも cast の「着地点の紋」が波の終点（target）に出る。吸収の円の演出は cast の target 側（この archetype は着弾の合図を出さない）に置いた。
  転がり + 叩きつけも同様に cast の target 側に 0.2 秒遅らせて出す。
- スキル吸収率が既定の 100% なので、範囲スキル（S1・S2・衝撃波）を大勢に当てたときの回復は、MLBB の実際の吸収率が 100% より低ければ多すぎる（ジャングルの周回・ミニオンの群れで効く）。
