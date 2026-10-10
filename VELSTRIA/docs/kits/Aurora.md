# Aurora (MLBB) - Kit Specification

Primary source: Mobile Legends Fandom hero page (fetched via the MediaWiki API, page edited 2026-05-30) plus its patch history page. mlbb.io mirrors the same text. Search extracts of guide sites agree on descriptions but give no independent numbers. "unknown" = not found. "disputed" = sources disagree. Ranges are in wiki "units". Aurora was fully revamped in Patch 1.8.56.

## Hero overview
- Role / lane: Mage (Crowd Control/Poke), Mid Lane. Ranged, mana resource, magic damage. Ratings: durability 4, offense 7, control 10, difficulty 1.
- Basic attack: ranged single target, attack range 4.7, attack speed 1.00 base. Projectile speed: unknown.
- Level 1 stats: HP 2380, HP regen 6.8, mana 500, mana regen 4, physical attack 110, physical defense 17 (12.4% reduction), magic defense 15 (11.1%), attack speed 1.00, movement speed 250, crit damage 200%.
- Level 15 stats: HP 4496, regen 11.0, mana 1900, physical attack 225, physical defense 73, magic defense 50, attack speed 1.21.
- Growth per level: HP +151.14, regen +0.3, mana +100, mana regen +0.2, physical attack +8.21, physical defense +4, magic defense +2.5, attack speed +0.015.
- Max skill levels: S1 6, S2 6, Ultimate 3.

## Passive - Pride of Ice
- Cast type: passive, triggers on fatal damage.
- When taking fatal damage, Aurora freezes herself for 1.5 s, becoming invincible (untargetable-style invulnerability: benefits from allied abilities such as Luo Yi's Diversion or Floryn's Bloom) and gradually recovering 30% max HP. Cooldown 150 s.
- Her freeze effects can also affect turrets. Triggers before the Immortality item. The availability indicator is visible to everyone.
- Whether she can act (move/cast) during the 1.5 s: unknown (stated as frozen).

## Skill 1 - Hailstone Blast
- Cast type: ground-target circle (meteorite lands at the target location). Range, radius and fall delay: unknown.
- Deals 350-550 (+90% total magic power) magic damage and slows targets hit by 40% for 1 s. Afterwards 5 hailstones fall, each dealing 40-60 (+10% total magic power) magic damage.
- Cooldown 6.0/5.6/5.2/4.8/4.4/4.0 s. Mana 55/65/75/85/95/105. Base damage 350/390/430/470/510/550; hailstone damage 40/44/48/52/56/60.
- Disputed: Fandom patch history says Patch 1.8.92 raised base damage to 400-700 and set hailstone damage to 40 (flat), but the hero page still shows 350-550 / 40-60. Use the hero-page values unless confirmed in-game.

## Skill 2 - Frosty Breeze
- Cast type: cone (fan-shaped) in the aimed direction with a travelling delay; a frozen area is created at the far end.
- Deals 225-375 (+75% total magic power) magic damage to enemies hit and freezes them for 1 s. A frozen ground patch at the far end of the cone deals a total of 225-375 (+75% total magic power) to enemies in the area.
- The wiki note says enemies and turrets in a half cone 2-6 units from Aurora are frozen, with frozen enemies taking damage once more; there is a travel animation delay so the freeze is not instant. Patch 1.8.56 removed the freeze at close range (the near part of the cone only deals damage).
- Cooldown 13.0 s at all levels on the hero page; mana 110/110/120/130/140/150. Base damage 225/255/285/315/345/375; sustained (ground) damage 225/255/285/315/345/375.
- Disputed: patch history says Patch 1.8.92 changed the cooldown to 13-11 s; hero page shows 13 s flat. Use 13 s unless confirmed.
- Fan angle, speed of the wave, and ground-patch radius/duration: unknown.

## Ultimate - Frigid Glacier
- Cast type: skillshot line (frost path) that turns into an expanding ground area. Path length and width: unknown.
- Deals 100-200 (+40% total magic power) magic damage to enemies in the path and reduces their movement speed by 80% for 1.2 s. The frost path gradually becomes glaciers that spread to their maximum size (area 7.5 x 7 units) and shatter, dealing 600-1200 (+150% total magic power) magic damage to all enemies in the area and freezing them for 1 s. Each 100 magic power Aurora has adds 0.2 s to the freeze duration.
- Cooldown 50/45/40 s. Mana 150/175/200. Base damage 100/150/200; AoE damage 600/900/1200.
- Time between cast and shatter: unknown.

## Gameplay identity
- Control mage / poke: Hailstone Blast every 4-6 s for lane harassment and wave clear.
- Frosty Breeze is the pick tool: hit at mid range (not point blank) to freeze, then the ground patch finishes.
- Ultimate is a zone-control teamfight claim: slow lane through the enemies, then a large freeze, so allies can burst.
- Pride of Ice makes her tougher than other mages (durability 4) with a 150 s second life.
- Magic power increases the ultimate's freeze, rewarding late-game scaling.

## Simulation notes
- Standard: ranged basic attack, ground circle with delay, cone skillshot, slow, freeze (stun-equivalent hard CC), line skillshot with 80% slow, one-time death save.
- Needs special state: death-save passive (invulnerable + channel-like heal 30% max HP over 1.5 s, 150 s cooldown, before Immortality); Frosty Breeze's delayed freeze with a distance-based zone and persistent ground damage area at the far end; Hailstone Blast's 5 follow-up hits (timed spawns); Frigid Glacier two-phase effect (path slow, then expanding area that shatters later); freeze duration scaling with magic power; freeze applying to turrets.

## Sources
- https://mobile-legends.fandom.com/wiki/Aurora
- https://mobile-legends.fandom.com/wiki/Aurora/Patch_history
- https://mlbb.io/en/hero/aurora (mirrors Fandom text)
- https://mlbbhub.com/heroes/aurora (descriptions only)

## 公式（現行シーズン）の数値

2026-10 に MediaWiki API で取り直した（Fandom の `Aurora` / `Aurora/Patch_history`、Liquipedia の `Aurora`）。Fandom のヒーローページは
1.8.56（リワーク）の値のまま止まっていて、パッチ履歴の 1.8.92 の強化（スキル1 の基礎 350–550 → 400–700、雹 40–60 → 40 固定、スキル2 の CD 13 → 13–11 秒）が
反映されていない。Liquipedia はその強化を含み、さらに新しい値（スキル2 の CD 12 → 8 秒、凍結が先端の凍った地面に移り魔力で延びる、マナの表）を載せている。
同じ取り方で引いた Liquipedia のティグラルが日本語クライアントの値（H029 の「公式（日本語クライアント）の数値」）と完全に一致したので、**Liquipedia を現行の正**とした。
スキルのレベルは公式でスキル1・2 が Lv1〜6、アルティメットが Lv1〜3。

| スロット | 公式名 | タグ | 内容 |
|---|---|---|---|
| パッシブ | Pride of Ice | 死亡回避（Death Immunity） | 致命傷を受けると 1.5 秒間自身を凍結させ、その間は無敵で最大 HP の 30% を徐々に回復する。CD 150 秒。オーロラの凍結はタワーにも効く |
| スキル1 | Hailstone Blast | 範囲技・減速 | CD 6.0 / 5.6 / 5.2 / 4.8 / 4.4 / 4.0、MP 60 / 65 / 70 / 75 / 80 / 85、基礎ダメージ 400 / 460 / 520 / 580 / 640 / 700（+90% 魔法攻撃）。氷塊を指定地点に落とし、命中した敵を 1 秒間 40% 減速。その後 5 つの雹が降り、それぞれ 40（全 Lv 一定。+10% 魔法攻撃） |
| スキル2 | Frosty Breeze | 範囲技・CC | CD 12.0 / 11.2 / 10.4 / 9.6 / 8.8 / 8.0、MP 75 / 80 / 85 / 90 / 95 / 100、基礎ダメージ 225 / 255 / 285 / 315 / 345 / 375（+75% 魔法攻撃）。指定方向の扇形に霜風を吹き、命中した敵にダメージ。先端に凍った地面を作り、範囲の敵に合計 225 → 375（+75% 魔法攻撃）を与えて 1 秒間凍結。魔法攻撃 100 ごとに凍結 +0.06 秒。近距離は凍らない（1.8.56）、扇の 2〜6 マスの敵が凍る（Fandom の注記） |
| アルティメット | Frigid Glacier | CC・範囲技 | CD 50 / 45 / 40、MP 140 / 160 / 180、氷の道 100 / 150 / 200（+40% 魔法攻撃）+ 移動速度 −80%（1.2 秒）。道は氷河に育って最大（7.5 × 7 マス）まで広がって砕け、範囲の全員に 600 / 900 / 1200（+150% 魔法攻撃）+ 凍結 1 秒。魔法攻撃 100 ごとに凍結 +0.2 秒 |

### 公式が置き換えた調査の値

| 項目 | 以前の調査・実装 | 現行（Liquipedia） |
|---|---|---|
| スキル1 の基礎ダメージ・雹 | ヒーローページの 350–550 / 雹 40–60（1.8.92 は「確認できるまで不採用」） | 400 → 700 / 雹 40 固定（1.8.92 の強化どおり） |
| スキル1 のマナ | 55 → 105（実装はマスターの 60 一定） | 60 / 65 / 70 / 75 / 80 / 85 |
| スキル2 の CD | 13 秒固定（実装も 13 秒） | 12.0 → 8.0 秒 |
| スキル2 のマナ | 110 / 110 / 120 / 130 / 140 / 150（実装はマスターの 72 一定） | 75 / 80 / 85 / 90 / 95 / 100 |
| スキル2 の凍結の魔力ボーナス | 記載なし | 魔法攻撃 100 ごとに +0.06 秒 |
| スキル2 の霜風 : 凍った地面 | 1 : 1（実装は 0.46 : 0.36 で地面を弱く） | 1 : 1（同じ表） |
| アルティメットのマナ | 150 / 175 / 200（実装はマスターの 120 一定） | 140 / 160 / 180 |
| アルティメットの凍結 | 1 秒 + 魔力 100 ごとに 0.2 秒（実装は上限 +0.6 秒を足していた） | 1 秒 + 0.2 秒 / 100（上限の記載なし） |

ランクの対応: Velstria のスキルのランクは S1/S2 が 4 段、アルティメットが 3 段（`SkillSlot.maxRank`）。表は**線形補間**で写す（ランク 1 = Lv1、最大ランク = 公式の最終レベル。S1/S2 は ランク r → Lv `1 + (r − 1) × 5 / 3`、アルティメットの 3 段は公式の Lv そのまま）。マナは補間した値を整数に丸める（例: スキル1 60 / 68 / 77 / 85）。

## Velstria 実装対応表

H031 氷嵐のオーリア（`Systems/Kits/Kit_H031.swift`、テスト `Tests/VelstriaCoreTests/Kits/Kit_H031Tests.swift`、演出 `App/Battle/SkillFX/Heroes/FX_H031.swift`）。
単位は Velstria（≈ 100 × MLBB の 1 マス）。ダメージ・クールダウン・マナ消費は上の「公式（現行シーズン）の数値」の表をランクで線形補間して使う（H029 ボルグと同じ方法）。
オーリアのキットは汎用アルカニストのパッシブ（スキル命中で他スキルの CD 短縮）を置き換える。

### 数値の方針

- ダメージの換算: `(公式の基礎（ランクで補間）+ 係数 × 魔力) × スロット倍率（S1 4.0 / S2 3.0 / 奥義 2.6）× 換算`。魔力の係数は公式の「+N% 魔法攻撃」そのまま
  （氷塊 90%・雹 10%・霜風と凍った地面 75%・氷の道 40%・砕け 150%）。**物理攻撃では伸びない**（公式どおり。以前は汎用のスキル値の比で、汎用の式の
  「攻撃力 × 0.45 × 0.6」がレベルで乗っていた）。装備なしの 1v1（`BalanceHarness`）では、ランクの表だけで伸びる。
- 換算（`OriaTuning.s1Scale` / `s2Scale` / `ultScale`）は下の「バランス」の値。1 スロットの単体ダメージ（全部が 1 体に当たったとき）は汎用の 0.8〜1.3 倍に収まる
  （S1 = 氷塊 + 雹 5 発、S2 = 霜風 + 凍った地面（汎用の遠隔 S2 は「ブリンク + 強化攻撃」で半分なので、基準は元のスキル値 = base ÷ 0.5）、奥義 = 氷の道 + 砕け。
  `testSingleTargetDamageStaysNearGenericBudget`）。説明文の `{xBase}(+{xPct}%魔法攻撃)` は換算後の値。
- マナ消費: 公式の表（`HeroKit.cost`。補間した値を整数に丸める）。以前のマスターデータの 60 / 72 / 120 は使わない。
- クールダウン: 公式の秒数そのまま（S1 6.0 → 4.0 秒、S2 12.0 → 8.0 秒、奥義 50 / 45 / 40 秒。CD 短縮は掛ける）。
- 凍結: スキル2 は 1 秒 + 魔法攻撃 100 ごとに 0.06 秒（撃った時点の魔力）、奥義は 1 秒 + 100 ごとに 0.2 秒（発動時の魔力）。どちらも公式に上限が無いので上限を外した（以前は奥義に +0.6 秒の上限）。
- 以前の食い違い（ヒーローページ vs パッチ履歴）は、Liquipedia の現行値（パッチ 1.8.92 の強化を含む）で解消した（上の「公式が置き換えた調査の値」）。

### 対応表

| 元の仕様 | Velstria での実装 | 区分 |
|---|---|---|
| パッシブ 氷の誇り（Pride of Ice）: 致命傷を受けると 1.5 秒凍りつき、無敵で最大 HP の 30% を少しずつ回復、CD 150 秒 | `modifyIncomingDamage`（防御・軽減の後、シールドの前）で、ダメージがシールドを除いた HP 以上のとき 0 にして発動。HP を 1 にしてシールドを失い、`suppress`（行動不能・移動不能、解除不可）+ `invulnerable` を 1.5 秒、45 tick に分けて最大 HP の割合を回復（回復阻害は受け、回復強化・回復量スコアには数えない）。**回復の割合は英雄のレベルで伸びる: Lv1 は 0%（無敵の 1.5 秒のみ）→ 最大レベル 15 で 30%（公式と同じ）、間は線形（Lv12 は 23.6%。以前は Lv12 で 30%）**（`prideHealLv1` / `prideHealFullLevel`）。再発動まで 150 秒（`KitState.timers`）。総当たり勝率が Lv1 で中央値 +59 pt と突出したための調整（回復を 5% にしても Lv1 は +45 pt 台に残り、無敵の猶予が効いている） | 調整（Lv1 の回復を削った） |
| 「不死」の装備より先に働く | 致命傷を 0 にするので倒れず、装備のイモータル（倒された後にその場で復活する。`ItemEffects.onHeroDeath`）には到達しない。氷の誇りが待機中のときだけ装備が働く（テストで確認） | 忠実 |
| 凍結中に動けるかは不明 | 動けない（`suppress`）。無敵のあいだは弱体も受けない | 簡略（不明のため） |
| 無敵は味方のスキル（洛依の転移、フローリンの花）の恩恵を受ける | 対象外（これらのスキルは Velstria に無い） | 省略 |
| 凍結の効果はタワーにも効く（扇の 2〜6 マスの敵とタワーが凍る） | 霜風（撃った位置から 200 以上）と氷河の砕けの範囲の**敵のタワー・Core を、ヒーローと同じ秒数だけ凍結**（`stun`、タグは同じ）。凍ったタワーは索敵も攻撃もしない（`TowerSystem.update` と `CombatSystem.stepAttacker` が `canAct` を見る。前隙も取り消す）。タワーへのダメージは無い（公式に記載なし）。仕組み: 霜風・砕けのゾーンの payload に `kitHitsStructures`（`ZoneSystem` が範囲内の敵の構造物にキットの `onHit` だけを呼ぶ）→ `freezeTurret` → `Kit.freezeStructure`（構造物に弱体を付けられる唯一の入口。`addStatus(allowStructure:)`）。無敵の構造物（前段のタワーが残る内側のタワー・Core）は凍らない。ほかのヒーローの CC・弱体はこれまでどおり構造物に付かない | 忠実（無敵の構造物を除くのは Velstria の保護の規則） |
| 再発動の表示は全員に見える | HUD のバッジ（凍結中・待機中の残り秒 / 準備完了）は自分の HUD のみ。敵側への表示はない | 簡略 |
| 練習場（CD なし） | 氷の誇りも再発動待ちにならない（`noCooldowns`） | 追加 |
| 死亡 | 死亡で全リセット。ただし氷の誇りの再発動までの残り秒と、遅れて当たる霜風の起点は残す（撃った後の氷は術者が倒れても消えない） | 追加 |
| S1 氷塊と雹: 地点指定の円。氷塊が落ち 400–700 (+90%) の魔法 + 40% の減速 1 秒、続けて 5 つの雹が 40 固定 (+10%) | 地点指定（射程 650・半径 170）。0.5 秒の予告のあと氷塊が着弾して魔法ダメージ（公式の表の換算）+ 40% の減速（1 秒）。続けて 0.7〜1.1 秒に 0.1 秒おきに半径 85 の雹 5 つ（向きから決まる 72° ずつ、氷塊の半径の 0.9 倍（偶数番）/ 1.2 倍（奇数番）の輪に交互、乱数なし = 中心から 153 / 204）。**雹は中心を外れた位置に降る**ので、氷塊の中心に立つ相手には当たらず（旧: 内側 0.45 / 外側 0.65 で 5 発とも当たった）、輪の近くに立つ相手は 1〜2 発受ける。雹はゾーンで出すので術者が倒れても降る | 忠実（半径・遅れは調査資料で不明のため選んだ値、雹の位置は推測） |
| S1 の射程・半径・落下の遅れは不明 | 射程 650、半径 170（スキル定義の 155 より少し広く）、遅れ 0.5 秒（地点 AoE の標準） | 簡略 |
| S2 霜風: 扇形（進む遅れあり）。225–375 (+75%) の魔法 + 1 秒の凍結（魔法攻撃 100 ごとに +0.06 秒）。2〜6 マスの敵が凍り、近距離は凍らない（パッチ 1.8.56）。現行の文では凍結は先端の凍った地面の側に書かれている | 扇形のゾーン（射程 650・半角 0.65 rad ≒ 37°。0.5 から広げた。総当たりの勝率は変わらない）を 0.3 秒の遅れで発動。魔法ダメージ + 術者（撃った位置）から 200 以上離れた敵を 1 秒 + 魔法攻撃 100 ごとに 0.06 秒凍結（`stun`、タグ付き。撃った時点の魔力）。200 未満はダメージのみ。凍結は `onHit` で距離を見て付与し、`ccApplied` を出す。遅い 0.3 秒の間に避けられる | 忠実（扇の角度・速度は不明のため選んだ値。凍結の最大距離は扇の端 650 まで = 600 より少し長い） |
| S2 扇の先の凍った地面: 合計 225–375 (+75%) | 扇の先（術者から 540、半径 190 = スキル定義の radius）に円ゾーン。0.3 秒の遅れで発動、持続 1.8 秒、0.5 秒おき = 4 回に合計ダメージ（公式の表 = 霜風と同量）を均等に分ける。扇の外（射程の先）でも地面には入る | 簡略（半径・持続は不明のため選んだ値） |
| S2 CD 12.0 → 8.0 秒（現行。ヒーローページの 13 秒・パッチの 13→11 は古い） | 12.0 → 8.0 秒をランクで線形補間（以前はヒーローページの 13 秒固定） | 忠実 |
| 奥義 氷河: 直線の氷の道（100–200 (+40%) の魔法 + 80% の減速 1.2 秒） | 貫通する弾（長さ 770・半幅 120・速度 2200）。魔法ダメージ（公式の 100 / 150 / 200 の換算。砕けとの比は公式どおり 1 : 6）+ 80% の減速 1.2 秒（`slow`、他の減速と最大値で重なる） | 忠実（長さ・幅は不明のため選んだ値） |
| 奥義 氷河: 道が氷河に育って最大 7.5 × 7 マスに広がり砕ける。600–1200 (+150%) + 凍結 1 秒、魔力 100 ごとに +0.2 秒 | 術者から前へ 450 の位置に半径 360（直径 720 ≒ 7.5 × 7）の円ゾーンを撃った時点で置き、1.2 秒後に砕けて範囲の全員に魔法ダメージ + 凍結。凍結は 1.0 秒 + 魔法攻撃 100 ごとに 0.2 秒（発動時の魔力で決める。公式どおり上限なし。以前は +0.6 秒の上限を足していた）。氷の道（0〜770）をほぼ覆うので、道で鈍足になった敵は砕けに巻き込まれる。道の横の敵は避けられる（1.2 秒の予告）。CC 無効・無敵の相手は凍らない | 簡略（「育つ」は演出だけで、当たり判定は最初から最大。砕けるまでの時間は不明のため 1.2 秒） |
| 奥義 CD 50/45/40 秒 | 50 / 45 / 40 秒（MLBB と同じ。以前は試合時間に合わせて 40 → 32 秒に縮め、× 0.5 = 20 → 16 秒） | 忠実 |
| 基本ステータス（HP 2380 など） | `master_runtime.json` の H031 のまま | 対象外 |

### 照準・ボット・説明

- HUD の照準: スキル1 は `.groundAoE`（地点・円）、スキル2 は `.cone`（`shape: .fan`・半角つき）、アルティメットは `.piercingLine`（`shape: .wideLine`）。アルティメットの帯の半幅（`targeting.radius`）は氷河の半径 360（砕けて凍らせる範囲）で、氷の道の弾の当たり幅（半幅 120、`ultPathWidth`）は別に持つ（`castGlacier` は `T.ultPathWidth` を使う）。ボットの奥義の関門が数える周囲の半径は max(radius × 1.4, 300) = 504（旧 300）に広がり、氷河の範囲（中心まで 450・半径 360）の外側の敵も数えるので少し撃ちやすい（撃つ判断は交戦中・710 以内に絞られたまま）。
- ボット: S2 は 220〜620 の距離にいる敵にだけ撃つ（近すぎると凍らないため）。奥義は交戦中で 710 以内のときだけ（汎用の「倒せる / 2 体巻き込む」の条件は先に効く）。
- 説明文は `KitText`（ja/en、数値は sim から。公式の文の構造に合わせる）。ダメージ類は説明用に整数へ丸めた値を extras に出し、実際のダメージはランクと能力値から丸めずに求める（`Kit_H031.hailDamage(rank:stats:)` など）。タグは公式（パッシブ = 死亡回避 → `buff`、スキル1 = 範囲技・減速 → `aoe` `slow`、スキル2 = 範囲技・CC → `aoe` `control`、アルティメット = CC・範囲技 → `control` `aoe`）。

### 検証（Release）

- 総当たり 1v1 の勝率（双方向、全 33 体との平均）: Lv1 / Lv6 / Lv12 で H031 = 78.8% / 59.1% / 47.0%（調整前。調整後は下の「バランス調整」）。同じ場の汎用アルカニスト
  H004 = 51.5 / 56.1 / 63.6%、H022 = 33.3 / 37.9 / 31.8%、H010 = 6.1 / 21.2 / 19.7%、H016 = 7.6 / 10.6 / 13.6%。
  Lv1 は氷の誇り（HP の約 +45%）が効く 1v1 の特性で高め。ロール代表 H001–H006 との TTK は Lv1/6/12 とも 2.5〜22 秒（CD が半分だったころの帯は 2.5〜15 秒）に収まる（H031 の鏡像戦 Lv1 は 15.07 秒で、H011/H016/H034 の鏡像戦と同じ 15 秒すれすれ）。

### 演出（`FX_H031.swift`）

- パッシブ: cast は身の周りの氷の結晶（アルカニストの合図で出る）。telegraph / impact は S1 の雹ゾーン（パッシブの演出 ID を借りる）の小さな予告・着弾。
- S1: telegraph で着弾点に氷が凝り（氷塊が落ちる 0.5 秒）、impact で氷塊が砕けて氷柱（4 本）が咲く。
- S2: 霜風は cast の扇（slash・fan・wave）で見せる。impact は cast 時（扇のアーキタイプ）と凍った地面の発動で再生されるので、固定寸法の小さな霜の炸裂にした。telegraph が凍った地面。
- 奥義: cast で氷の道、travel で道を走る氷、telegraph で氷河が育ち（氷柱 5 本）、砕けは telegraph の `at: 1.2`（ゾーンの遅れと同じ）に置いた（道の最初の命中と氷河の発動で再生される impact は小さな閃き）。氷柱のプールは高画質で 5 本なので、1 つの合図は 5 本以内。
- パッシブ（氷の誇り）の発動に専用のイベントは無いため、凍結の演出は `SkillFXDirector.observe` のアルカニストの合図（スキル命中）に乗る。App 側の仕上げ（Phase 4）で扱う。

### バランス調整（2 回目の見直し）

- 計測は `BalanceHarness`（両陣営 × 開始距離 300/450/600 × 種 2）。アルカニスト汎用の中央値との差: 見直し前 Lv1 +59 / Lv6 +27 / Lv12 +19 pt（勝率 79.8 / 56.6 / 47.0 %）。
- 雹を中心の周りに広げる（0.9 / 1.2 倍）だけでは氷塊の中心の相手に雹が当たらなくなり、S1 が弱くなりすぎる（42.4 / 32.8 / 23.2 %）ので、氷塊 0.64 → 0.85・雹 0.056 → 0.06 で補った。
  氷塊の強さには段があり（0.78 で Lv1 56.6、0.85 で 66〜80、0.9 で 82.8）、Lv1（S1 だけ）と Lv12（全スキル）を同時に合わせるのは氷の誇りの回復で行う。
- 氷の誇りの回復: Lv1 の割合を 30% → 10% にしても Lv1 は 78.8%、5% で 66.2%、0% で 44.9%（無敵の 1.5 秒が効いている）。Lv1 を 0%、Lv12 を 30% の線形とした。
- 採用値（氷塊 0.85・雹 0.06・散らし 0.9 / 1.2・Lv1 の回復 0%）: Release の最終計測（アルカニスト中央値 25.0 / 28.8 / 27.0 %）で勝率 38.9 / 34.8 / 48.0 %（差 +13.9 / +6.1 / +21.0 pt）。開幕 3 秒の瞬間火力の比は Lv1 0.90 / Lv6 1.00 / Lv12 1.00（見直し前 0.95 / 1.02 / 1.02）。
- スキル2 の扇の半角 0.5 → 0.65（37°）は勝率に影響しない（1v1 の位置関係では扇に収まる）。ダメージは同じで、集団戦の当たりやすさだけが上がる。
- 説明文は UI の用語（スキル1 / スキル2 / アルティメット）で、パッシブは master の名前「氷の誇り」（Pride of Ice）を書き、回復量のレベル依存（Lv1 0% / Lv12 30%）を書く。

### クールダウンを MLBB の秒数に（2026-10）

- 全体の CD 倍率 0.5 を廃止し、S1 を MLBB の 6 → 4 秒（以前は汎用の 6.5 → 5.3 秒）、奥義を 50 / 45 / 40 秒（以前は 40 → 32 秒）にした。S1 の回数が増えたぶん氷塊 0.85 → 0.70・雹 0.06 → 0.05（上の「数値の方針」）。
- `KitBalanceTests`（アルカニスト中央値との差）: 変更前 +13.4 / +6.8 / +21.0 → 変更後 −5.1 / −3.4 / +30.2 pt（S1 を変えないと Lv12 +40 で帯の外）。Lv12 が高いのは氷の誇り（致命傷の無効化 + 30% 回復）で、1v1 が長くなったぶん効きが増えた。

### 公式の表へ置き換え（2026-10）

上の「公式（現行シーズン）の数値」に合わせて、ダメージ・クールダウン・マナ・凍結・タグ・説明文を作り直した（H029 ボルグと同じ方法）。

| 項目 | 公式（現行） | 以前の実装 | 今回 |
|---|---|---|---|
| スキル1 CD / MP | 6.0 → 4.0 / 60 → 85 | 6.0 → 4.0 / 60（マスター） | 6.0 / 5.33 / 4.67 / 4.0、MP 60 / 68 / 77 / 85 |
| スキル1 ダメージ | 氷塊 400 → 700 (+90%)、雹 40 (+10%) × 5 | 汎用 S1 の 0.70 倍 + 雹 0.05 倍 × 5 | (表 + 係数 × 魔力) × 4.0 × `s1Scale` 0.29（ランク 1: 氷塊 464・雹 46） |
| スキル1 減速 | 40% 1 秒 | 同じ | 同じ |
| スキル2 CD / MP | 12.0 → 8.0 / 75 → 100 | 13 秒固定 / 72（マスター） | 12.0 / 10.67 / 9.33 / 8.0、MP 75 / 83 / 92 / 100 |
| スキル2 ダメージ | 霜風 225 → 375 (+75%)、凍った地面の合計も同じ | 元のスキル値の 0.46 倍 + 地面 0.36 倍 | (表 + 係数 × 魔力) × 3.0 × `s2Scale` 0.40（ランク 1: 霜風 270・地面 270） |
| スキル2 凍結 | 1 秒 + 魔法攻撃 100 ごとに 0.06 秒 | 1 秒 | 1 秒 + 0.06 秒 / 100（撃った時点の魔力） |
| アルティメット CD / MP | 50 / 45 / 40、140 / 160 / 180 | 50 / 45 / 40、120（マスター） | 公式どおり |
| アルティメット ダメージ | 道 100 / 150 / 200 (+40%)、砕け 600 / 900 / 1200 (+150%) | 汎用の奥義の 0.10 + 0.90 倍 | (表 + 係数 × 魔力) × 2.6 × `ultScale` 0.36（ランク 1: 道 94・砕け 562、ランク 3: 道 187・砕け 1123） |
| アルティメット CC | 鈍足 80% 1.2 秒、凍結 1 秒 + 0.2 秒 / 100 | 同じ（凍結に上限 +0.6 秒） | 公式どおり（上限を外した） |
| パッシブ | 1.5 秒凍結・無敵・最大 HP 30% 回復・CD 150 秒 | 回復は Lv1 0% → Lv12 30% | 回復は Lv1 0% → **Lv15 30%**（Lv12 は 23.6%） |
| タグ | 死亡回避 / 範囲技・減速 / 範囲技・CC / CC・範囲技 | なし | `buff` / `aoe` `slow` / `aoe` `control` / `control` `aoe` |

説明文は公式の文の構造（「指定地点に氷塊を落とし、…(+90%魔法攻撃)の魔法ダメージを与えて…」）に合わせ、`{meteorBase}(+{meteorPct}%魔法攻撃)` などに換算後の値を入れる。

バランス（`KitBalanceTests`、Release、アルカニスト汎用の中央値との差。換算を環境変数で振って総当たりを測った。汎用の中央値は置き換え前の計測 21.2 / 32.7 / 23.6 %）:

| 試した組み合わせ | Lv1 | Lv6 | Lv12 |
|---|---|---|---|
| 置き換え前（汎用の比） | −5.1 | −3.4 | +30.2 |
| 公式の表・`s1Scale` 0.29 / `s2Scale` 0.40 / `ultScale` 0.48・回復 Lv12 で 30% | −5.0 | −5.9 | +27.4 |
| 同 + 回復の最大を Lv15 に | −5.0 | −7.4 | +20.8 |
| `ultScale` 0.30（回復 Lv12） | −5.0 | −11.0 | +8.2 |
| `s1Scale` 0.32・`ultScale` 0.36（回復 Lv12） | +1.0 | −3.9 | +27.9 |
| `ultScale` 0.38・回復 Lv15 | −5.0 | −11.0 | +13.3 |
| **採用: `ultScale` 0.36・回復 Lv15**（最終の全体計測、中央値 21.2 / 33.0 / 24.6 %） | **16.2 (−5.1)** | **21.7 (−11.2)** | **32.8 (+8.2)** |

Lv1 は氷塊だけで決まり（`s1Scale` 0.29 → 0.32 で +6 pt）、Lv12 はスキル1（4 秒ごと）・アルティメット（ランク 3 で公式の表が 2 倍）・氷の誇りの回復で決まる。スキル2 の CD が 13 → 8 秒になったぶん Lv12 が強く出たので、
アルティメットの換算を予算の下限より低くし（ランク 1 は汎用の 0.66〜0.69 倍、ランク 3 は 0.87〜0.90 倍。テストは奥義の下限だけ 0.65）、氷の誇りの回復を最大レベルで公式の 30% に届く形にした。
開幕 3 秒の瞬間火力の比（同ロール中央値に対する倍率、報告のみ）: 0.79 / 0.92 / 1.01。全体の Release（978 テスト）は 0 failures。
魔力の係数は公式どおり魔力にだけ掛かる（物理攻撃では伸びない）ので、装備の無いハーネスではランクの表だけで伸びる。装備で魔力を積んだときの伸び（例: 魔法攻撃 100 で氷塊 +104）は汎用のアルカニスト（魔力 × 0.8 × 4.0 = +320）より緩い（既知の差）。
