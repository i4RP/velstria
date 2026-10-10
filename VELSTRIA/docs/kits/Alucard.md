# Alucard (MLBB) - Kit Specification

**正は下の「公式（MLBB Fandom 現行）の数値」**（2026-10 に MediaWiki API で取得した Fandom の現行のスキル表）。それより上のウェブ調査と食い違う値は公式が優先する。

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

ランクの対応: S1/S2 は 4 段、アルティメットは 3 段へ線形補間（ランク 1 = Lv1、最大ランク = 公式の最終レベル）。「追加物理攻撃」の係数は総攻撃力に掛ける（H029 と同じ式）。

## Velstria 実装対応表

H033 紅牙のヴァルド（アサシン・近接 150・Energy）= Velstria 版の Alucard。実装: `Packages/VelstriaCore/Sources/VelstriaCore/Systems/Kits/Kit_H033.swift`、
テスト: `Tests/VelstriaCoreTests/Kits/Kit_H033Tests.swift`、演出: `App/Battle/SkillFX/Heroes/FX_H033.swift`。
スロットは上の調査の順に割り当てる（Skill1 = Groundsplitter、Skill2 = Whirling Smash、Ultimate = Fission Wave、Passive = Pursuit）。
マスターデータ上の最終名は パッシブ「吸血の渇き」/ スキル1「裂地撃」/ スキル2「旋回斬」/ アルティメット「核分裂波」（`tools/rename_kit_skills.mjs`）。説明文は UI の用語（スキル1・スキル2・アルティメット）で書く。マスターの `cc`（S1 = Slow、S2 = なし、奥義 = Slow）は調査と一致する。
キットは汎用のアサシンのパッシブ（草むら/ステルス解除後の奇襲 +30% とキル/アシストの全 CD −30%）を **置き換える**（調査に Alucard のどちらも無いので移植しない）。
距離は Velstria 単位（≈ MLBB × 100）。調査に無い値（射程・半径・窓・持続など）は下の「選んだ値」に書いた。
ダメージは汎用のアサシンの式（`SkillCatalog.genericNumbers`）に対する倍率で、MLBB の 270 / 345 / 400 などの数値そのままではない。クールダウンは MLBB の秒数そのまま（6 段のランクを 4 段・奥義 3 段へ線形補間。全体倍率 `cooldownScale` は 1.0）。

### 対応表（○ = 実装、△ = 簡略化、× = 見送り）

| 元の仕様 | 状態 | Velstria での実装・理由 |
|---|---|---|
| 近接・単体の通常攻撃、射程は 1.8（「4」の値は Malefic Gun の射程ボーナスと見て採らない） | ○ | 射程 150（マスターの値）。ステータスはマスター（HP 2780 +186/Lv、攻撃 120 +4.2、防御 24、魔防 15、Energy 480）で、Fandom の値ではない |
| リソース無し（コスト 0） | ○（公式） | **`HeroKit.cost` で全スキル 0**。Energy のバー（マスター 480）は残るが、どのスキルも消費しない。以前はマスターの S1 45 / S2 55 / 奥義 90 × 0.6 を消費していた |
| パッシブ Pursuit: スキルを発動するたび、次の通常攻撃が対象の位置へ踏み込み、**+125% 総物理攻撃**の物理ダメージ（Fandom・Liquipedia の現行。mlbb.io の 140% は採らない） | ○（公式） | `onSkillCast`（S1・S2・奥義の 1 回目）と奥義の再使用（衝撃波）で準備（`timers[0]`）。次の通常攻撃（`shapeBasicAttack`）が 1.25 倍（会心はそのまま掛かる）になり、敵の目の前まで `MovementSystem.dash`（速さ 2600）で踏み込む。1 回で使い切る。以前は 140% |
| Pursuit のクリープ相手 110%（mlbb.tools のみ） | × | 古い値と見て採らない。ミニオン・モンスターにも 140% |
| Pursuit の猶予・パッシブ CD（記載なし）、強化通常攻撃の射程 4 | ○ / △ | 猶予 5 秒（選んだ値）、**射程は公式の 4 = 400**（準備中は通常攻撃の射程が +250 伸びる `attackRangeBoost`、以前は +300 = 450）、CD は無し。猶予が切れる/使うと射程は戻る。HUD のバッジは残り秒 |
| 追撃は「対象の位置へ踏み込んでダメージ」 | △ | 命中（ダメージ・吸血）は通常攻撃が発射された tick に即時で、踏み込みはその直後（約 0.1 秒）。到着を待ってダメージを出すと、踏み込みが CC・対象の死亡で途切れたときの扱いが複雑になるため。ルート中は踏み込めない（ダメージは乗る）。構造物には 140% も踏み込みも乗らない（準備は消費される） |
| 奥義のパッシブ: 常時の複合吸血 10 / 20 / 30%（公式。Liquipedia の文は 10% だが表は 10 / 20 / 30%） | ○ / △ | 奥義ランク別の 10 / 20 / 30%。奥義を習得している間は常に `lifestealBoost`（通常攻撃の吸血）と `spellVampBoost`（スキルの吸血）を持つ（無期限のステータス。ランクが上がれば大きさだけ更新、未習得は 0）。**スキルの吸血は通常攻撃の 0.33 倍**（MLBB の複合吸血は範囲スキルが 1/3、単体は等倍。Velstria のスペルヴァンプは命中した対象ごとに全量なので、S1・S2 の両方が範囲である実態に合わせて 1/3） |
| S1 Groundsplitter: 指定エリアへ跳び込んで斬り、**270 → 370（+80% 追加物理攻撃）** の物理ダメージ、鈍足 40% 2 秒 | ○ / △ | 跳躍の archetype（`leapSlam`、地点指定）。`dashSweeping`（速さ 1800）で指定地点（最大 350）まで転がり、**転がり終えた tick に 1 度だけ**半径 190 の円へ叩きつける（経路の敵には当たらない）。対象を指定したときは対象の縁の手前で止まる。ダメージは**公式の表** `(lerp(270, 370) + 0.8 × 攻撃力 × 0.6) × スキル1 の倍率 4.0 × s1Scale`（以前は汎用 S1 × ランク別 0.88〜0.60）。鈍足 40% を 2 秒（ミニオン・モンスターにも）。転がり中のハード CC で叩きつけは取り消され、ルート中は転がれない |
| S1 クールダウン 8.5 → 6.5 秒（6 ランク）、コスト無し | ○（公式） | 公式の 8.5 → 6.5 秒を 4 ランクで線形補間（8.5 / 7.83 / 7.17 / 6.5 秒）。コスト 0 |
| S2 Whirling Smash: 照準なし、自分中心の回転斬りで **345 → 570（+120% 追加物理攻撃）** の物理ダメージ | ○ / △ | `selfAoE`、照準なし。発動した tick に半径 250（記載なし）の敵（ヒーロー・ミニオン・モンスター）へ。ダメージは**公式の表** `(lerp(345, 570) + 1.2 × 攻撃力 × 0.6) × 3.0 × s2Scale`（以前は汎用 S2 × 0.50）。CD が汎用の約半分なので 1 発は汎用の予算を割る。CC なし |
| S2 クールダウン 6.0 → 4.0 秒、コスト無し | ○（公式） | 公式の 6.0 → 4.0 秒を 4 ランクで線形補間。コスト 0 |
| 奥義 Fission Wave（地点指定）: 範囲の敵のエネルギーを吸収、移動速度 −30%・**複合防御 −10 / 15 / 20** | ○ | `groundAoE` の 1 回目（`aim: .point`）。指定地点（最大 450）の周囲 300 の敵（ヒーロー・ミニオン・モンスター）に、`slow` 0.30 と **`flatDefenseMod` −10 / 15 / 20（物理防御・魔法防御の固定値。公式の複合防御そのまま）** を 4 秒（持続は記載なし）。以前は防御を割合の `armorShred`（10 ÷ 防御）+ 魔防 `magicShred` 10 で、ランクで伸びなかった。吸収そのものにダメージは無い。無敵の相手には入らない |
| 奥義: 吸収した敵ヒーロー 1 体につき自分に複合防御 **+10 / 15 / 20** | ○（公式） | **`flatDefenseMod` +10 / 15 / 20 × 敵ヒーローの数**を 6 秒（物理防御と魔法防御に固定値で足す）。以前は防御を上げる状態が無く、被ダメ軽減 5%/体で近似していた。ミニオン・モンスター・無敵の相手は数えない。`ints[2]` に捉えた数を残す |
| 奥義: 他のスキルのクールダウンが **50%** になる（6 秒間） | ○（公式） | `timers[1]` = **6 秒**（公式。以前は Lv6/12 が強すぎたので 5 秒にしていた）の間、毎 tick に S1・S2 のクールダウンをもう 1 tick ぶん進める（= 通常の 2 倍の速さ）。奥義自身は半減しない。スタン中も進む。練習場の `noCooldowns` を尊重（`Kit.refundCooldown`） |
| 奥義の再使用: 向きへ衝撃波、**400 / 550 / 700（+200% 追加物理攻撃）** の物理ダメージ。窓・射程・幅は記載なし | ○ / △ | 同じ `castSkill`（`openRecast`、**6 秒**・1 回。CD・コストは使わない）。向き（`.direction` / `.unit` / `.none` は最寄りの敵ヒーロー → 向き）へ **貫通する直線弾**（長さ 900・半幅 130・速さ 2200）で、当たった全員（ヒーロー・ミニオン・モンスター）に 1 度ずつ。ダメージは**公式の表** `(lerp(400, 700) + 2.0 × 攻撃力 × 0.6) × 奥義の倍率 2.6 × waveScale`（以前は汎用の奥義 × 0.81）。窓が切れる・死亡で衝撃波は出ない。スタン中は撃てないが窓は残る |
| 奥義 クールダウン 40 / 35 / 30 秒、コスト無し | ○（公式） | 公式の 40 / 35 / 30 秒（最初の発動で消費。再使用では変わらない）。コスト 0 |
| ボット: 衝撃波の再使用 | ○ | 共有部分（`BotCombat.castSkills`）が、再使用の窓が開いている奥義を汎用の関門（倒せる・2 体以上）に通さず `botCast` の判断だけで撃つ。`Kit_H033Tests.testBotRecastsTheShockwaveEvenWhenTheGateWouldBlockTheAbsorb` が、倒せない 1 体の相手でも窓の間は衝撃波を撃つこと（窓が無ければ吸収は関門で止まること）を確認している |
| ボット: ファーム | ○ | `botFarm` で裂地撃（スキル1。跳躍系）だけミニオン・ジャングルにも使う。Lv1〜3 はスキル1 しか無く、通常攻撃だけではキャンプが遅いため。HP が半分以上で、集団の位置が敵のタワー・コアの射程（750 + 半径 + 120）に入らないときだけ。旋回斬（スキル2）は自分中心の範囲なので従来どおりの経路 |
| S1 の命中をダメージの到着に合わせる（追撃） | × | 追撃は発射した tick にダメージを出し、踏み込みはその直後のまま。到着まで待つには、通常攻撃の主ヒットを止めて到着時に出し直す必要があり（会心・吸血・命中時効果・踏み込みが途切れたときの扱い）、リスクが大きい割に得るものが小さいので見送り |
| 説明文・タグ | ○ | 公式の文の構造（パッシブ = 追撃の 1 文、アルティメット = パッシブ（吸血）/ アクティブ（吸収・半減）/ 再発動（衝撃波）の 3 段落）に合わせ、数値は `{base}(+{atkPct}%物理攻撃)` などのトークンで sim から。タグは公式どおり パッシブ `buff`、スキル1 `mobility aoe`（Blink = 移動）、スキル2 `aoe`、アルティメット `buff burst` |
| 武器の「ゲーム的な体感」: スキル → 追撃の連鎖、奥義の半減中のスキル連打、吸血で持続 | ○ | S1（転がり）→ 追撃、S2 → 追撃、奥義の吸収 → 衝撃波 → 半減中の S1/S2 連打。複合吸血は奥義を習得してから |
| 弱点: 奥義の 1 回目だけでは火力が無い、転がり中の CC | ○ | 吸収はダメージ無し（衝撃波が本体）。転がり・衝撃波の再使用はスタンで止まる。ボットは吸収と衝撃波の間に条件が崩れると衝撃波を逃すことがある（下のリスク） |

### 選んだ値（調査に無い・換算した値）

| 項目 | 値 | 理由 |
|---|---|---|
| 追撃の猶予・射程・踏み込みの速さ | 5 秒・400（+250）・2600 | 猶予と速さは記載なし。射程は公式の強化通常攻撃の射程 4 |
| 追撃のダメージ | 物理攻撃の 125% | Fandom・Liquipedia の現行（公式） |
| 吸血 | 通常攻撃 10 / 20 / 30%（奥義ランク）・スキルはその 0.33 倍 | 上の表 |
| S1 の転がる距離・叩きつけの半径・速さ・隙間 | 350・190・1800・5 | 調査に「不明」。近接スキルの標準 ≈ 300 に半径を足した |
| S1 の鈍足 | 40% 2 秒 | 調査どおり |
| S2 の半径 | 250 | 調査に「不明」。通常攻撃の射程 150 + 余裕（Whirling Smash は近接の回転斬り） |
| 吸収の中心を置ける距離・半径・鈍足・防御ダウン・持続 | 450・300・30%・複合防御 −10 / 15 / 20（固定値）・4 秒 | 距離・半径・持続は記載なし。データ上の奥義の射程 600 に収まる（450 + 300 = 750 は届く最大の縁） |
| 吸収で得る複合防御 | 敵ヒーロー 1 体につき +10 / 15 / 20・6 秒 | 公式の値（`flatDefenseMod`） |
| クールダウン半減 | 6 秒・2 倍の速さ | 公式の 6 秒 |
| 再使用の窓 | 6 秒・1 回 | 調査に「不明」。半減と同じ長さにした |
| 衝撃波の長さ・半幅・速さ | 900・130・2200 | 調査に「不明」。データ上の奥義の射程 600・半径 120 を、長い貫通の波へ伸ばした（標準の貫通弾の速さ 2200） |
| ダメージの換算 | `s1Scale` / `s2Scale` / `waveScale` | 公式の表（ランクで補間 + 攻撃力係数）を sim の通常の式 × スロット倍率に通したあとに掛ける。値は下の「公式の数値へ（2026-10）」 |
| クールダウンの倍率 | なし（S1・S2・奥義とも MLBB の秒数） | 全体の CD が半分だったころは S1 0.55 / 0.59 / 0.64 / 0.70（ランク別）/ S2 1.2 / 奥義 0.5 だった（下の「バランス」の旧表） |
| 説明文の数値 | `{base}` `{atkPct}`（換算後の基礎・攻撃力に対する %）、`{pursuit}` `{window}` `{reachMult}`、奥義の `{lifesteal}` `{vampPct}` `{defense}` `{gain}` `{debuff}` `{haste}` `{slow}` | 数値を sim とずらさない |

### バランス（`KitBalanceTests`、Release、全員総当たり。同ロール（Assassin）の汎用ヒーローの中央値との差）

全 34 ヒーローとの 1v1（`BalanceHarness`: 両陣営 × 開始距離 300/450/600 × 種 2 の 12 戦の平均、Lv 1/6/12、スキル自動習得、引き分けは半分）の勝率を、同ロールの汎用ヒーローの中央値と比べる。

| | Lv1 | Lv6 | Lv12 | 開幕 3 秒の火力（汎用の中央値比 Lv1 / 6 / 12） |
|---|---|---|---|---|
| 前の版（S1 0.85・S1 の倍率 0.8 固定・S2 0.82 / ×1.0・半減 6 秒・吸血 1/2） | 1.0% (−28.4) | 68.2% (+12.5) | 74.7% (+25.0) | 3.61 / 2.67 / 2.49 |
| 現在（下の設定） | 17.2% (−11.0) | 54.0% (−2.9) | 49.0% (−1.3) | 3.69 / 2.42 / 2.13 |

現在の設定: S1 の倍率 0.88 / 0.78 / 0.70 / 0.64（ランク別）、S1 のクールダウン倍率 0.55 / 0.59 / 0.64 / 0.70（ランク別）、S2 0.81・クールダウン ×1.2、衝撃波 0.81、半減 5 秒、スキルの吸血は通常攻撃の 0.33 倍。
追撃 140%・吸血 10 / 20 / 30%・防御ダウン 10・半減の 2 倍は調査の値のまま。

Lv1（V1）: Lv1〜3 はスキル1 だけなので、S1 の強さがそのまま Lv1 の勝率になる。Lv1 の決闘は S1 の倍率にとても敏感で（1v1 は 10 秒前後で決まる）、
S1 の倍率が 0.70 だと 3.5%、0.85 だと 10〜15%、0.90 だと 28%、1.0 だと 37%、1.15 だと 57%。ランク 1 の S1 の倍率を 0.88 にして Lv1 を 15% 以上にした。
クールダウンだけを 0.8 → 0.55 に縮めても Lv1 は 3% → 13〜15% 程度にしか戻らなかった（以前の表は 0.8 固定で 1%）。

Lv6 / Lv12（以前 +12.5 / +25.0）を下げた手順（中央値との差）:
- 半減 6 秒 → 5 秒だけ: +19.6 / +23.5。吸血を 8 / 15 / 20% に下げるだけ: +18.0 / +21.0。効きは小さい。
- S2 のクールダウンを ×1.25 にするだけ: +14.5 / +11.4。S2 の連打が主因（半減中に 1.2 秒おきに飛んだ）。
- S2 ×1.3 + S1 の倍率をランクで下げる（0.78 / 0.72 / 0.66）+ 半減 5 秒: +4.9 / +7.9。現在はほぼ同じ設定で S2 を ×1.2 にしてほぼ中央値（−2.9 / −1.3）。
S1 の倍率を一律に 0.70 へ下げると Lv1 が 3.5% に崩れるので、ランク別にした。ランクが上がるほど倍率が下がるが、汎用の +30%/ランクが勝つので S1 のダメージの絶対値はランクで増える（テストで確認）。
開幕 3 秒の火力は Lv6 の 2.67 倍 → 2.42 倍、Lv12 の 2.49 倍 → 2.13 倍（Lv1 はハーネスの都合: Lv1 の汎用アサシンはスキル1 を撃たず中央値が小さい）。
ほかに Lv6 の火力を下げるには S1 の倍率を下げるしかなく、これ以上は Lv6 / Lv12 の勝率が中央値を下回る（−3 付近からさらに下がる）ので止めた。

以前の調整の経緯（ここがこのキットの肝）:
- 最初の版（S1 / S2 / 衝撃波 = 汎用の 1.0 / 1.15 / 1.15 倍、S1・S2 の CD は全体倍率 0.5、吸収の半減は 2 倍）は Lv6 / Lv12 で **100% / 100%**、TTK 1.6 秒まで（支配的）。
- 倍率を下限の 0.82 まで下げても 100% / 100%。効いていたのは **クールダウン半減**（半減中に S2 が 1.2 秒おき、S1 が 1.8 秒おきに飛ぶ）と **S2 の CD**（調査の 6 → 4 秒は汎用 S2 のデータ値 9.8 秒よりずっと短く、× 0.5 で 3 → 2 秒）。
- 追撃・吸血・防御ダウンを外す分解でも各効果が数十 pt ずつ足されて 100% になっていた。
TTK は H001〜H006 相手で全員総当たり（`SkillBalanceTests.testFullRosterStaysNearBand`）の範囲内。

### 既知の差・リスク

- スキルのコストは公式どおり 0（Energy のバーは表示上残る）。
- 追撃の「到着してからダメージ」ではなく、発射した tick にダメージ（踏み込みは直後）。踏み込み中に対象が死んでも、ダメージは出ている。
- 複合防御の増減は `flatDefenseMod`（物理防御・魔法防御に固定値）。同じ印の重ね掛けは大きい方の値（敵への −値は小さい方 = 弱い方が残る）なので、ランクの違う吸収が重なると弱い方の値になることがある。
- 奥義の吸収の円と衝撃波の方向は別々に狙う（MLBB と同じ）。ボットは吸収を `BotCombat.castSkills` の奥義の条件（倒せる、または 2 体以上を巻き込める）と「交戦中・敵に届く」で撃つ。
  衝撃波は、窓が開いている間は共有部分が関門を通さず `botCast` の判断（敵ヒーローが届く距離に居れば撃つ）だけで撃つ。そのため、吸収さえ撃てば衝撃波は逃さない（以前は条件が崩れると撃たず窓が切れた）。吸収そのものの条件は共有部分なので変えていない（ボットの 10 人戦の煙テストでは、試合によっては 1800 秒の間に一度も奥義の条件を満たさず、種を変えて撃つまで回す）。
- 演出: 現在の `SkillFXDirector` は `stage` を見ないので、衝撃波（stage 1）でも cast の「着地点の紋」が波の終点（target）に出る。吸収の円の演出は cast の target 側（この archetype は着弾の合図を出さない）に置いた。
  転がり + 叩きつけも同様に cast の target 側に 0.2 秒遅らせて出す。
- 吸血はスペルヴァンプが命中ごとに全量のため、範囲スキルで大勢に当てると回復が大きい（ジャングルの周回で効く）。1/2 に抑えたが、ミニオンの群れへの S2 の回復は MLBB より多い可能性がある。
- 汎用アサシンの奇襲（草むら/ステルス解除後 +30%）とキル/アシストの全 CD −30% を持たない（調査に無い）。

### クールダウンを MLBB の秒数に（2026-10）

- 全体の CD 倍率 0.5 と、S1 のランク別の倍率（0.55〜0.70）・S2 の × 1.2 を廃止し、S1 8.5 → 6.5 秒・S2 6 → 4 秒・奥義 40 / 35 / 30 秒（MLBB の秒数）にした。S2 の CD が汎用の S2（9.8 秒から）の約半分になり、そのままだと Lv6 / Lv12 が +39 / +42 pt（帯の外）だったので、S2 0.81 → 0.50、S1 のランク 2〜4 を 0.78 / 0.70 / 0.64 → 0.76 / 0.67 / 0.60（ダメージの絶対値はランクで増えたまま）にした。
- `KitBalanceTests`（アサシン中央値との差）: 変更前 −11.0 / −0.9 / −0.3 → 変更後 −12.2 / +4.9 / +22.3 pt。

### 公式の数値へ（2026-10）

Fandom の現行のスキル表（上の「公式（MLBB Fandom 現行）の数値」）に、クールダウン・コスト・ダメージの表・CC・挙動を合わせた（H029 ボルグと同じ方法）。

| 項目 | 公式 | 変更前 | 変更後 |
|---|---|---|---|
| コスト | なし（全スキル） | マスター S1 45 / S2 55 / 奥義 90（× 0.6） | 0（`HeroKit.cost`） |
| 追撃（パッシブ） | +125% 総物理攻撃、射程 4 | 140%、射程 450（+300） | 125%、射程 400（+250） |
| S1 クールダウン | 8.5 → 6.5 | 8.5 → 6.5 | 同じ |
| S1 ダメージ | 270 → 370（+80%）、40% 減速 2 秒 | 汎用 S1 × 0.88 / 0.76 / 0.67 / 0.60（Lv1 693 / Lv12 815） | `(270 → 370 + 0.8 × 攻撃 × 0.6) × 4.0 × 0.66`（Lv1 865 / Lv12 1187）、減速同じ |
| S2 クールダウン | 6.0 → 4.0 | 6.0 → 4.0 | 同じ |
| S2 ダメージ | 345 → 570（+120%） | 汎用 S2 × 0.50（ランク 1 320 / Lv12 563） | `(345 → 570 + 1.2 × 攻撃 × 0.6) × 3.0 × 0.08`（ランク 1 104 / Lv12 166） |
| 奥義 クールダウン | 40 / 35 / 30 | 40 / 35 / 30 | 同じ |
| 奥義 吸血 | 10 / 20 / 30% | 10 / 20 / 30%（スキルは 0.33 倍） | 同じ |
| 吸収の防御ダウン | 複合防御 −10 / 15 / 20、移動速度 −30% | 防御 −10 を割合（`armorShred`）+ 魔防 −10（ランクで伸びない） | `flatDefenseMod` −10 / 15 / 20（4 秒）、移動速度 −30% |
| 吸収で得る防御 | 敵ヒーロー 1 体につき複合防御 +10 / 15 / 20 | 被ダメ軽減 5% / 体 | `flatDefenseMod` +10 / 15 / 20 / 体（6 秒） |
| クールダウン半減 | 6 秒 | 5 秒 | 6 秒 |
| 衝撃波 | 400 / 550 / 700（+200%） | 汎用奥義 × 0.81（ランク 1 720 / Lv12 1122） | `(400 → 700 + 2.0 × 攻撃 × 0.6) × 2.6 × 0.34`（ランク 1 481 / Lv12 795） |
| タグ | Buff / Blink・AOE / AOE / Buff・Burst | なし | `buff` / `mobility aoe` / `aoe` / `buff burst` |
| 説明文 | — | 独自の文（吸血はパッシブの文） | 公式の文の構造（吸血はアルティメットの「パッシブ：」、「アクティブ：」「再発動：」の 3 段落） |

（ダメージの例は Lv1 = ランク 1、Lv12 = S1/S2 ランク 4・奥義ランク 3。攻撃力は装備なしの値。S2・衝撃波の「ランク 1」は Lv1 の攻撃力での参考値。）
換算（`s1Scale` 0.66 / `s2Scale` 0.08 / `waveScale` 0.34）は勝率で決めた。予算（汎用の何倍か）は S1 0.87〜1.10、S2 約 0.15、衝撃波 約 0.55。
公式の値（コスト 0・半減 6 秒・複合防御 ±10〜20）だけで Lv12 が強くなる（置き換え直後 +31 pt）。いちばん効いたのは S2（クールダウン 4 秒、半減中は 2 秒で、撃つたびに追撃と吸血が乗る）で、S2 の換算 0.01 で Lv12 が約 3 pt、衝撃波の換算 0.01 で約 1 pt 動いた。そのため S2 と衝撃波を汎用の帯より下げた（テストの帯: S2 0.1〜1.3、衝撃波 0.5〜1.3）。Lv1 は S1 の換算だけで決まり、0.62 では 20%、0.66 で 35%（しきい値のように跳ねる）。

`KitBalanceTests`（Release。アサシン中央値との差、pt）:

| | Lv1 | Lv6 | Lv12 |
|---|---|---|---|
| 変更前（クールダウンを MLBB の秒数にした直後） | −12.2 | +4.9 | +22.3 |
| 公式の表へ置き換えた直後（換算 0.55 / 0.20 / 0.51） | −10.2 | +13.0 | +30.9 |
| **今回**（換算 0.66 / 0.08 / 0.34） | +5.2（34.8% / 中央値 29.7） | −2.7（43.9% / 46.6） | +10.2（58.1% / 47.9） |

開幕 3 秒の瞬間火力の比（同ロール中央値に対する倍率、報告のみ）: 置き換え直後 3.72 / 1.76 / 1.88 → 今回 4.20 / 1.70 / 1.75（Lv1 は S1 の換算を上げたぶん。Lv1 の汎用アサシンはスキル1 を撃たず中央値が小さい）。Release の全テスト 981 件・失敗 0（スキップ 6）。
