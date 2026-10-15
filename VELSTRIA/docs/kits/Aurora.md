# Aurora (MLBB) - Kit Specification

> 2026-10-14: ヒーローの能力値（HP・物理攻撃・防御・魔防・攻撃速度・HP 回復・マナ・移動速度・射程・リソースの種類）と能力値の式（防御 120/(120+防御)・クリティカル 200%・攻撃速度の加算・移動速度の加算式など）を MLBB の値へ置き換えた（`docs/HERO_STATS.md`）。この文書の能力値の記述（「マスターの値」「近接 150」「Energy」、Energy のコストの × 0.6 など）は置き換え前のもの。
>
> 2026-10-14（スキルの段階）: スキルの数値を**公式の表をそのまま使う（6 / 6 / 3 段）**形にした。スキル1・2 = Lv1〜6、アルティメット = Lv1〜3 で、rank = 公式の Lv。スロット倍率・キットの換算（`s1Scale` など）・段の補間は無い。パッシブの回復は全レベル 30%、スキル2 の凍結は原本の文どおり末端の凍結エリアの中の敵に掛かる。下の「Velstria 実装対応表」と「スキルの段階の移行（2026-10-14）」。

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
同じ取り方で引いた Liquipedia のティグラルが日本語クライアントの値（H029 の「公式（日本語クライアント）の数値」）と完全に一致したので、**Liquipedia を現行の正**とした
（その後、下の日本語クライアントの原本で置き換えた。CD の表だけが違った）。
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

## 日本語クライアントの画面（2026-10-11・無加工の原本）

2026-10-11 に受け取った日本語クライアントのスキル詳細の画面の無加工のスクリーンショット（IMG_4558〜4567。画像はコミットしない）。日本語版の名前は「オーロラ(Aurora)」、メイジ。
**これが一次資料**で、上の Liquipedia の表より優先する。スキル名の下の小さい斜体（永遠に続く氷河・北の吹雪・雪山を覆い尽くす霜・氷の底流）はスキンの別名。

| 枠 | 日本語版の名前 | タグ | CD | MP | 内容（原本の文の要約） |
|---|---|---|---|---|---|
| パッシブ | プライド・オブ・アイス | **死亡無効**（金の札） | – | – | 致命的なダメージを受けると、自身を 1.5 秒間フリーズ。この間は無敵状態になり、徐々に最大HPの 30% を回復。この効果には 150 秒の CD 時間がある。自身のフリーズ効果はタワーにも適用される |
| スキル1 | 雪華の烈風 | 範囲技・減速 | **5.0 / 4.8 / 4.6 / 4.4 / 4.2 / 4.0** | 60 / 65 / 70 / 75 / 80 / 85 | 指定地点に氷の隕石を落とし、400 / 460 / 520 / 580 / 640 / 700 (+90% 魔法攻撃) の魔法ダメージ、命中した対象を 1 秒間 移動速度 40% 低下。その後 5 個の雹が降り、それぞれ 40（全 Lv 一定）(+10% 魔法攻撃) |
| スキル2 | 氷花のそよ風 | **妨害**・範囲技 | **10.0 / 9.6 / 9.2 / 8.8 / 8.4 / 8.0** | 75 / 80 / 85 / 90 / 95 / 100 | 指定方向の扇状範囲に吹きつけ、225 / 255 / 285 / 315 / 345 / 375 (+75% 魔法攻撃) の魔法ダメージ、範囲の末端に凍結エリア。エリア内の敵に合計 225 → 375 (+75% 魔法攻撃)、1 秒間フリーズ（魔法攻撃 100 ごとに +0.06 秒） |
| アルティメット | 凍てつく氷結 | **妨害**・範囲技 | 50 / 45 / 40 | 140 / 160 / 180 | 指定方向に霜の道、経路上の敵に 100 / 150 / 200 (+40% 魔法攻撃)、1.2 秒間 移動速度 80% 低下。霜の道は徐々に広がる氷河となり、最大サイズで砕け散り、エリア内の全敵に 600 / 900 / 1200 (+150% 魔法攻撃)、1 秒間フリーズ（魔法攻撃 100 ごとに +0.2 秒） |

原本で置き換えた値（変更前 → 変更後）:

| 項目 | 変更前（Liquipedia） | 変更後（原本） |
|---|---|---|
| スキル1 の CD | 6.0 → 4.0（6.0 / 5.6 / 5.2 / 4.8 / 4.4 / 4.0） | **5.0 / 4.8 / 4.6 / 4.4 / 4.2 / 4.0** |
| スキル2 の CD | 12.0 → 8.0（12.0 / 11.2 / 10.4 / 9.6 / 8.8 / 8.0） | **10.0 / 9.6 / 9.2 / 8.8 / 8.4 / 8.0** |
| パッシブのタグ | `buff`（死亡回避の語彙が無かった） | **`deathimmunity`**（新しいキー。UI の名前「死亡無効」、金の札） |
| スキル2 のタグ | `aoe` `control`（範囲技・CC） | **`disrupt` `aoe`**（妨害・範囲技） |
| アルティメットのタグ | `control` `aoe`（CC・範囲技） | **`disrupt` `aoe`**（妨害・範囲技） |

凍結の魔力ボーナスは原本の文どおり、スキル2 = 魔法攻撃 100 ごとに +0.06 秒、アルティメット = +0.2 秒（どちらも上限なし）。マナ・ダメージの表・減速も Liquipedia と一致。
原本の文ではスキル2 のフリーズは**範囲の末端の凍結エリアの中の敵**に掛かる。以前の実装は扇の霜風が撃った位置から 200 以上離れた敵を凍らせ、凍結エリアはダメージだけだった
（Fandom の注記「扇の 2〜6 マスの敵が凍る」・パッチ 1.8.56 の仕様。既知の差として残していた）。2026-10-14 に原本の意味に直した（下の対応表）。

## Velstria 実装対応表

H031 氷嵐のオーリア（`Systems/Kits/Kit_H031.swift`、テスト `Tests/VelstriaCoreTests/Kits/Kit_H031Tests.swift`、演出 `App/Battle/SkillFX/Heroes/FX_H031.swift`）。
単位は Velstria（≈ 100 × MLBB の 1 マス）。オーリアのキットは汎用アルカニストのパッシブ（スキル命中で他スキルの CD 短縮）を置き換える。

### 数値: 公式の表をそのまま使う（6 / 6 / 3 段）

- 段: rank = 公式の Lv（スキル1・2 は rank 1〜6 = Lv1〜6、アルティメットは rank 1〜3 = Lv1〜3）。表は `Kit.level` でそのまま引く（補間なし。全 Lv 一定の雹は 1 要素の表）。
- ダメージ = 公式の基礎[段] + 公式の係数 × 魔法攻撃（`Kit.official(…, .magicPower, …)`）。スロット倍率・キットの換算は掛けない。**物理攻撃では伸びない**（公式の係数は魔法攻撃だけ）。
- CD = 公式の秒数 × (1 − CD 短縮)（`Kit.cooldown`。上限は能力値の CD 短縮の上限）。マナ = 公式の表（`HeroKit.cost` → `HeroKits.resourceCost`）。
- 説明文の `{xBase}(+{xPct}%魔法攻撃)` は公式の数値そのもの（例: スキル1 Lv1 = 400(+90%魔法攻撃)）。

| スキル1・2（公式の Lv） | Lv1 | Lv2 | Lv3 | Lv4 | Lv5 | Lv6 |
|---|---|---|---|---|---|---|
| スキル1 氷の隕石（+90% 魔法攻撃） | 400 | 460 | 520 | 580 | 640 | 700 |
| スキル1 雹 1 つ × 5（+10% 魔法攻撃） | 40 | 40 | 40 | 40 | 40 | 40 |
| スキル1 CD（秒） | 5.0 | 4.8 | 4.6 | 4.4 | 4.2 | 4.0 |
| スキル1 MP | 60 | 65 | 70 | 75 | 80 | 85 |
| スキル2 霜風（+75% 魔法攻撃） | 225 | 255 | 285 | 315 | 345 | 375 |
| スキル2 凍結エリアの合計（+75% 魔法攻撃） | 225 | 255 | 285 | 315 | 345 | 375 |
| スキル2 CD（秒） | 10.0 | 9.6 | 9.2 | 8.8 | 8.4 | 8.0 |
| スキル2 MP | 75 | 80 | 85 | 90 | 95 | 100 |

| アルティメット（公式の Lv） | Lv1 | Lv2 | Lv3 |
|---|---|---|---|
| 霜の道（+40% 魔法攻撃） | 100 | 150 | 200 |
| 氷河の砕け（+150% 魔法攻撃） | 600 | 900 | 1200 |
| CD（秒） | 50 | 45 | 40 |
| MP | 140 | 160 | 180 |

- CC（全 Lv 一定）: スキル1 減速 40% 1 秒、スキル2 凍結 1 秒 + 魔法攻撃 100 ごとに 0.06 秒（撃った時点の魔力）、アルティメット 減速 80% 1.2 秒・凍結 1 秒 + 100 ごとに 0.2 秒（発動時の魔力）。どちらの凍結も上限なし（公式に記載なし）。
- 凍結は `stun`（タグ `H031.freeze`）で表す。MLBB のフリーズは「高レベル」のコントロール（多くのスキルを中断）だが、Velstria の CC の段階ではスタン（基本）と同じ扱い（中断できるタイマーを取り消す。進行中の突進は止めない）。コアの決定で、キットは変えない。
- パッシブ: 最大 HP の 30% を 1.5 秒かけて回復（**全レベル一定**。公式の文に段の表は無い）、CD 150 秒。
- スキルごとの割合: 公式の文（日本語クライアント）にスキル吸収率・攻撃エフェクト・「ミニオンには ○%」「モンスターに ○%」の記載が無いので、すべて既定（スキル吸収率 100%、通常攻撃由来の命中なし、ミニオン・モンスターへ等倍）。ミニオンへのスキルダメージの全体の × 0.2 はコアで撤廃済みなので、ミニオンにも公式のダメージがそのまま入る。
- バインド: オーリアのスキルは術者を動かさない（地点 AoE・扇・貫通弾）ので、敵のバインド中も撃てる（`movesCaster` は既定のまま）。

### 対応表

| 元の仕様 | Velstria での実装 | 区分 |
|---|---|---|
| パッシブ 氷の誇り（Pride of Ice）: 致命傷を受けると 1.5 秒凍りつき、無敵で最大 HP の 30% を少しずつ回復、CD 150 秒 | `modifyIncomingDamage`（防御・軽減の後、シールドの前）で、ダメージがシールドを除いた HP 以上のとき 0 にして発動。HP を 1 にしてシールドを失い、`suppress`（行動不能・移動不能、解除不可）+ `invulnerable` を 1.5 秒、45 tick に分けて**最大 HP の 30%（全レベル一定）**を回復（回復阻害は受け、回復強化・回復量スコアには数えない）。再発動まで 150 秒（`KitState.timers`）。以前のレベルで伸びる回復（Lv1 0% → Lv15 30%）は 2026-10-14 に外した | 忠実 |
| 「不死」の装備より先に働く | 致命傷を 0 にするので倒れず、装備のイモータル（倒された後にその場で復活する。`ItemEffects.onHeroDeath`）には到達しない。氷の誇りが待機中のときだけ装備が働く（テストで確認） | 忠実 |
| 凍結中に動けるかは不明 | 動けない（`suppress`）。無敵のあいだは弱体も受けない | 簡略（不明のため） |
| 無敵は味方のスキル（洛依の転移、フローリンの花）の恩恵を受ける | 対象外（これらのスキルは Velstria に無い） | 省略 |
| 凍結の効果はタワーにも効く | スキル2 の凍結エリア（できた瞬間のエリア内）と氷河の砕けの範囲の**敵のタワー・Core を、ヒーローと同じ秒数だけ凍結**（`stun`、タグは同じ）。凍ったタワーは索敵も攻撃もしない（`TowerSystem.update` と `CombatSystem.stepAttacker` が `canAct` を見る。前隙も取り消す）。タワーへのダメージは無い（公式に記載なし）。仕組み: 凍結エリア・砕けのゾーンの payload に `kitHitsStructures`（`ZoneSystem` が範囲内の敵の構造物にキットの `onHit` だけを呼ぶ）→ `freezeTurret` → `Kit.freezeStructure`（構造物に弱体を付けられる唯一の入口。`addStatus(allowStructure:)`）。無敵の構造物（前段のタワーが残る内側のタワー・Core）は凍らない。ほかのヒーローの CC・弱体はこれまでどおり構造物に付かない | 忠実（無敵の構造物を除くのは Velstria の保護の規則） |
| 再発動の表示は全員に見える | HUD のバッジ（凍結中・待機中の残り秒 / 準備完了）は自分の HUD のみ。敵側への表示はない | 簡略 |
| 練習場（CD なし） | 氷の誇りも再発動待ちにならない（`noCooldowns`） | 追加 |
| 死亡 | 死亡で全リセット。ただし氷の誇りの再発動までの残り秒と、遅れて働く凍結エリア・氷河の凍結秒は残す（撃った後の氷は術者が倒れても消えない） | 追加 |
| S1 雪華の烈風: 指定地点に氷の隕石。400–700 (+90%) の魔法 + 40% の減速 1 秒、続けて 5 つの雹が 40 固定 (+10%) | 地点指定（射程 650・半径 170）。0.5 秒の予告のあと隕石が着弾して公式の表の魔法ダメージ + 40% の減速（1 秒）。続けて 0.7〜1.1 秒に 0.1 秒おきに半径 85 の雹 5 つ（向きから決まる 72° ずつ、隕石の半径の 0.9 倍（偶数番）/ 1.2 倍（奇数番）の輪に交互、乱数なし = 中心から 153 / 204）。**雹は中心を外れた位置に降る**ので、隕石の中心に立つ相手には当たらず、輪の近くに立つ相手は 1〜2 発受ける。雹はゾーンで出すので術者が倒れても降る | 忠実（射程・半径・遅れ・雹の位置は推測） |
| S2 氷花のそよ風: 扇状に吹きつけ 225–375 (+75%) の魔法。範囲の末端に凍結エリア、エリア内の敵に合計 225–375 (+75%) と 1 秒のフリーズ（魔法攻撃 100 ごとに +0.06 秒） | 扇形のゾーン（射程 650・半角 0.65 rad ≒ 37°）を 0.3 秒の遅れで発動し、範囲の敵に公式の表の魔法ダメージ（**扇の霜風はダメージだけ**）。扇の末端（術者から 540、半径 190 = スキル定義の radius）に凍結エリア（円ゾーン）を同じ 0.3 秒で発動: **エリアができた瞬間（最初の適用）にエリア内にいる敵とタワーを 1 秒 + 魔法攻撃 100 ごとに 0.06 秒凍結**（`stun`、タグ付き。撃った時点の魔力。`onHit` で付与し `ccApplied` を出す）。エリアは 1.8 秒残り、0.5 秒おき = 4 回に公式の合計（霜風と同じ表）を均等に分けて与える。後から入ってきた敵はダメージだけ（凍結を掛け直さない）。エリアは扇の端（650）より先まで届くので、扇の外でもエリアに入れば凍る。扇の手前（術者のすぐ近く〜約 300）の敵はエリアの外なので凍らない（ダメージのみ） | 忠実（扇の角度・遅れ、エリアの位置・半径・持続・回数は推測。凍結を「できた瞬間」に限るのも推測） |
| S2 CD 10.0 → 8.0 秒（原本） | 公式の 6 段の表（10.0 / 9.6 / 9.2 / 8.8 / 8.4 / 8.0） | 忠実 |
| 奥義 凍てつく氷結: 直線の霜の道（100–200 (+40%) の魔法 + 80% の減速 1.2 秒） | 貫通する弾（長さ 770・半幅 120・速度 2200）。公式の表の魔法ダメージ + 80% の減速 1.2 秒（`slow`、他の減速と最大値で重なる） | 忠実（長さ・幅は推測） |
| 奥義: 道が氷河に育って最大（Fandom の 7.5 × 7 マス）に広がり砕ける。600–1200 (+150%) + 凍結 1 秒、魔力 100 ごとに +0.2 秒 | 術者から前へ 450 の位置に半径 360（直径 720 ≒ 7.5 × 7）の円ゾーンを撃った時点で置き、1.2 秒後に砕けて範囲の全員に公式の表の魔法ダメージ + 凍結。凍結は 1.0 秒 + 魔法攻撃 100 ごとに 0.2 秒（発動時の魔力で決める。公式どおり上限なし）。霜の道（0〜770）をほぼ覆うので、道で鈍足になった敵は砕けに巻き込まれる。道の横の敵は避けられる（1.2 秒の予告）。CC 無効・無敵の相手は凍らない | 簡略（「育つ」は演出だけで、当たり判定は最初から最大。砕けるまでの時間は推測） |
| 奥義 CD 50/45/40 秒 | 公式の 3 段の表（50 / 45 / 40） | 忠実 |
| 基本ステータス（HP 2380 など） | `docs/HERO_STATS.md`（MLBB の値へ移行済み） | 対象外 |

### 照準・ボット・説明

- HUD の照準: スキル1 は `.groundAoE`（地点・円）、スキル2 は `.cone`（`shape: .fan`・半角つき）、アルティメットは `.piercingLine`（`shape: .wideLine`）。アルティメットの帯の半幅（`targeting.radius`）は氷河の半径 360（砕けて凍らせる範囲）で、霜の道の弾の当たり幅（半幅 120、`ultPathWidth`）は別に持つ（`castGlacier` は `T.ultPathWidth` を使う）。ボットの奥義の関門が数える周囲の半径は max(radius × 1.4, 300) = 504 で、氷河の範囲（中心まで 450・半径 360）の外側の敵も数えるので少し撃ちやすい（撃つ判断は交戦中・710 以内に絞られたまま）。
- ボット: スキル2 は相手が凍結エリアに入る距離（術者から 350〜700 = エリアの中心 540 ± 半径 190、遠い側は 30 の余裕）のときだけ撃つ（扇の手前の敵はダメージだけで凍らないため。以前は「撃った位置から 200 以上は凍る」に合わせて 220〜620）。奥義は交戦中で 710 以内のときだけ（汎用の「倒せる / 2 体巻き込む」の条件は先に効く）。
- 説明文は `KitText`（ja/en、数値は sim から。公式の文の構造に合わせる）。ダメージ類は説明用に整数へ丸めた値を extras に出し、実際のダメージは段と能力値から丸めずに求める（`Kit_H031.hailDamage(rank:stats:)` など）。外したルールの但し書き（パッシブの「レベル1で0%…」、スキル2 の「自分のすぐ近くの敵は凍結しない」）は消した。
- タグは日本語クライアントの原本どおり: パッシブ = 死亡無効 → `deathimmunity`、スキル1 = 範囲技・減速 → `aoe` `slow`、スキル2 = 妨害・範囲技 → `disrupt` `aoe`、アルティメット = 妨害・範囲技 → `disrupt` `aoe`。

### 演出（`FX_H031.swift`）

- パッシブ: cast は身の周りの氷の結晶（アルカニストの合図で出る）。telegraph / impact は S1 の雹ゾーン（パッシブの演出 ID を借りる）の小さな予告・着弾。
- S1: telegraph で着弾点に氷が凝り（隕石が落ちる 0.5 秒）、impact で隕石が砕けて氷柱（4 本）が咲く。
- S2: 霜風は cast の扇（slash・fan・wave）で見せる。impact は cast 時（扇のアーキタイプ）と凍結エリアの発動で再生されるので、固定寸法の小さな霜の炸裂にした。telegraph が凍結エリア（演出の上では「凍った地面」）。ゾーンの数・位置・時刻は 2026-10-14 の変更でも同じ（凍結を付けるゾーンが扇から凍結エリアに移っただけ）なので、演出は変えていない。
- 奥義: cast で霜の道、travel で道を走る氷、telegraph で氷河が育ち（氷柱 5 本）、砕けは telegraph の `at: 1.2`（ゾーンの遅れと同じ）に置いた（道の最初の命中と氷河の発動で再生される impact は小さな閃き）。氷柱のプールは高画質で 5 本なので、1 つの合図は 5 本以内。
- パッシブ（氷の誇り）の発動に専用のイベントは無いため、凍結の演出は `SkillFXDirector.observe` のアルカニストの合図（スキル命中）に乗る。App 側の仕上げ（Phase 4）で扱う。

### スキルの段階の移行（2026-10-14）

外した定数・ルール（旧 → 今）:

| 旧 | 旧値 | 今 |
|---|---|---|
| `OriaTuning.s1Scale`（スキル1 の換算） | 0.27 | 削除（公式の値そのまま） |
| `OriaTuning.s2Scale`（スキル2 の換算） | 0.40 | 削除 |
| `OriaTuning.ultScale`（アルティメットの換算） | 0.36 | 削除 |
| スロット倍率 `Balance.Skills.damageScale` | 4.0 / 3.0 / 2.6 | 使わない |
| `Balance.Skills.cooldownScale` | 1.0 | 使わない（`Kit.cooldown`） |
| `(Lv1, Lv6)` のタプルと `lerp`（4 段への補間）、マナの整数への丸め | 例: スキル1 の MP 60 / 68 / 77 / 85 | 公式の 6 / 6 / 3 段の表（`Kit.level`） |
| `OriaTuning.prideHealLv1` / `prideHealFullLevel` / `Kit_H031.prideHealRatio(level:)`（回復がレベルで伸びる） | Lv1 0% → Lv15 30%（線形） | 削除。全レベル 30%（公式） |
| `OriaTuning.s2FreezeMin`（扇の霜風は撃った位置から 200 未満の敵を凍らせない）と `KitState.oriaBreezeOrigin` | 200 | 削除。凍結は扇の末端の凍結エリアの中の敵だけ（原本の文） |
| 説明文の換算後の値（`scaledBase` / `powerPercent`） | 例: 隕石 432(+97%) | 公式の値（400(+90%)） |

Lv1（rank 1）・魔法攻撃 0 の 1 発のダメージ（軽減前）: 隕石 432 → 400、雹 43 → 40、霜風 270 → 225、凍結エリアの合計 270 → 225、霜の道 94 → 100、砕け 562 → 600。
最大の段では 隕石 756 → 700（以前の最大ランク 4 = Lv6）、砕け（rank 3）1123 → 1200。CD は以前の 4 段の補間（スキル1 5.0 / 4.67 / 4.33 / 4.0）から公式の 6 段に。

入れた割合: なし（スキル吸収率・攻撃エフェクト・ミニオン / モンスターの補正は公式の文に無いので既定のまま）。CC の型（凍結 = `stun`）・バインドの扱いも変えていない。
変えた挙動: スキル2 の凍結を扇の霜風（撃った位置から 200 以上）から凍結エリア（できた瞬間のエリア内）へ移した。タワーの凍結も同じ。ボットのスキル2 の距離の条件もそれに合わせた。

バランス: 換算を外したあとの 1v1 の勝率・TTK は未計測（全キットを統合した後に測り直す）。以前の換算の調整（「バランス調整」「クールダウンを MLBB の秒数に」「公式の表へ置き換え」「日本語クライアントの原本へ」の各節にあった `s1Scale` などの選び方の表）は換算と一緒に消した（履歴は git のこのファイルの 2026-10-14 より前）。

### まだ MLBB と違うところ

- 幾何・時間は推測（公式の文に無い。スキルのプレビューと 60 fps の動画が要る）: スキル1 の射程 650・半径 170・落下 0.5 秒・雹の半径 85・雹の位置（0.9 / 1.2 倍の輪）と時刻（0.7〜1.1 秒）、スキル2 の扇の半角 0.65 rad・遅れ 0.3 秒・凍結エリアの位置（術者から 540）・半径 190・持続 1.8 秒・4 回、アルティメットの長さ 770・半幅 120・速度 2200・氷河の中心 450・半径 360・砕けるまで 1.2 秒。
- スキル2 の凍結エリアが残るのか（公式の「合計」を 1.8 秒・4 回に分けたのは推測）、凍結がエリアのできた瞬間だけか（後から入った敵も凍るのか）は資料が無い。
- 氷河の「徐々に広がる」は演出だけで、当たり判定は最初から最大。
- 氷の誇りの凍結中に行動できるか（`suppress` で不可にしている）は資料が無い。再発動の表示は自分の HUD だけ。
- フリーズは `stun`（MLBB は高レベルのコントロール）。
- スキル吸収率などの割合は「記載なし = 既定」とした（スキル詳細の画面を最後までスクロールした原本で確かめたい）。
