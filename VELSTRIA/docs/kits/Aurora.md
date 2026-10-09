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

## Velstria 実装対応表

H031 氷嵐のオーリア（`Systems/Kits/Kit_H031.swift`、テスト `Tests/VelstriaCoreTests/Kits/Kit_H031Tests.swift`、演出 `App/Battle/SkillFX/Heroes/FX_H031.swift`）。
単位は Velstria（≈ 100 × MLBB の 1 マス）。数値はオーリアの汎用スキル（`base.damage`）の比で持ち、TTK を保つ。
オーリアのキットは汎用アルカニストのパッシブ（スキル命中で他スキルの CD 短縮）を置き換える。

### 数値の方針

- スキルのランクは S1/S2 が 4 段・奥義が 3 段（オーロラは 6/6/3）。ランク差は汎用の +30%/ランクをそのまま使う。
- 1 スロットの単体ダメージ（全部が 1 体に当たったとき）は汎用の 0.8〜1.3 倍に収める: S1 = 氷塊 0.85 + 雹 5 × 0.06 = 1.15 倍（全部当たったとき。雹は氷塊の周りに散るので、中心に立つ相手は氷塊の 0.85 倍だけ。当初 0.64 + 5 × 0.056 = 0.92 倍）、
  S2 = 霜風 0.46 + 凍った地面 0.36 = 0.82 倍（汎用の遠隔 S2 は「ブリンク + 強化攻撃」で半分なので、基準は元のスキル値 = base ÷ 0.5）、
  奥義 = 氷の道 0.10 + 氷河の砕け 0.90 = 1.00 倍。調整の経緯: 最初は S1 1.15・S2 1.05・奥義 1.05（MLBB の CD のまま）で
  総当たり勝率が 80〜94%（汎用アルカニスト 6〜64%）だったため、氷の誇り（実質 +45% の耐久）の分、ダメージ・CD を汎用並みに寄せた。
- コストは汎用（マスターデータ: 60 / 72 / 120）のまま。`SkillSystem` が定義から引くので `numbers` では変えられない
  （MLBB は 55〜105 / 110〜150 / 150〜200）。
- クールダウン: S1 は 6.5 → 5.3 秒（汎用に揃える。MLBB の 6.0 → 4.0 のままだと汎用の S1 の 1.5 倍の DPS になる）、
  S2 は 13 秒固定（MLBB と同じ）、奥義は 40 → 32 秒。いずれも `Balance.Skills.cooldownScale`（0.5）と CD 短縮を掛けるので S1 3.25〜2.65 秒、
  S2 6.5 秒、奥義 20〜16 秒。
- 食い違う数値（ヒーローページ vs パッチ履歴）: S1 の基礎ダメージと雹は、ヒーローページ（350–550 / 雹 40–60 = ランクで伸びる）の構造を採った
  （ページは 2026-05-30 編集で、パッチ 1.8.92 の 400–700 / 雹 40 固定が反映されていない = 確認できた値はページ側）。
  氷塊と雹 1 発の比は 1 : 11（ページ 1 : 9、パッチ 1 : 10〜17 の間）。S2 の CD は 13 秒固定（ページ。パッチの 13→11 は不採用）。
  いずれも調査資料の「ゲーム内で確認できるまではヒーローページの値」に従った。

### 対応表

| 元の仕様 | Velstria での実装 | 区分 |
|---|---|---|
| パッシブ 氷の誇り（Pride of Ice）: 致命傷を受けると 1.5 秒凍りつき、無敵で最大 HP の 30% を少しずつ回復、CD 150 秒 | `modifyIncomingDamage`（防御・軽減の後、シールドの前）で、ダメージがシールドを除いた HP 以上のとき 0 にして発動。HP を 1 にしてシールドを失い、`suppress`（行動不能・移動不能、解除不可）+ `invulnerable` を 1.5 秒、45 tick に分けて最大 HP の割合を回復（回復阻害は受け、回復強化・回復量スコアには数えない）。**回復の割合は英雄のレベルで伸びる: Lv1 は 0%（無敵の 1.5 秒のみ）→ Lv12 以降は 30%（MLBB と同じ）、間は線形**（`prideHealLv1` / `prideHealFullLevel`）。再発動まで 150 秒（`KitState.timers`）。総当たり勝率が Lv1 で中央値 +59 pt と突出したための調整（回復を 5% にしても Lv1 は +45 pt 台に残り、無敵の猶予が効いている） | 調整（Lv1 の回復を削った） |
| 「不死」の装備より先に働く | 致命傷を 0 にするので、死亡直前の装備の踏みとどまり（`ItemEffects.preventDeath`）には到達しない。氷の誇りが待機中のときだけ装備が働く（テストで確認） | 忠実 |
| 凍結中に動けるかは不明 | 動けない（`suppress`）。無敵のあいだは弱体も受けない | 簡略（不明のため） |
| 無敵は味方のスキル（洛依の転移、フローリンの花）の恩恵を受ける | 対象外（これらのスキルは Velstria に無い） | 省略 |
| 凍結の効果はタワーにも効く | 効かない。ゾーン・弾は構造物に当たらない（汎用の仕様）、`addStatus` も構造物の弱体を拒否し、`TowerSystem` は状態を見ないため。タワー側を変えるには共有ファイルの変更が要る | 省略 |
| 再発動の表示は全員に見える | HUD のバッジ（凍結中・待機中の残り秒 / 準備完了）は自分の HUD のみ。敵側への表示はない | 簡略 |
| 練習場（CD なし） | 氷の誇りも再発動待ちにならない（`noCooldowns`） | 追加 |
| 死亡 | 死亡で全リセット。ただし氷の誇りの再発動までの残り秒と、遅れて当たる霜風の起点は残す（撃った後の氷は術者が倒れても消えない） | 追加 |
| S1 氷塊と雹: 地点指定の円。氷塊が落ち 350–550 (+90%) の魔法 + 40% の減速 1 秒、続けて 5 つの雹が 40–60 (+10%) | 地点指定（射程 650・半径 170）。0.5 秒の予告のあと氷塊が着弾して魔法ダメージ + 40% の減速（1 秒）。続けて 0.7〜1.1 秒に 0.1 秒おきに半径 85 の雹 5 つ（向きから決まる 72° ずつ、氷塊の半径の 0.9 倍（偶数番）/ 1.2 倍（奇数番）の輪に交互、乱数なし = 中心から 153 / 204）。**雹は中心を外れた位置に降る**ので、氷塊の中心に立つ相手には当たらず（旧: 内側 0.45 / 外側 0.65 で 5 発とも当たった）、輪の近くに立つ相手は 1〜2 発受ける。雹はゾーンで出すので術者が倒れても降る | 忠実（半径・遅れは調査資料で不明のため選んだ値、雹の位置は推測） |
| S1 の射程・半径・落下の遅れは不明 | 射程 650、半径 170（スキル定義の 155 より少し広く）、遅れ 0.5 秒（地点 AoE の標準） | 簡略 |
| S2 霜風: 扇形（進む遅れあり）。225–375 (+75%) の魔法 + 1 秒の凍結。2〜6 マスの敵が凍り、近距離は凍らない（パッチ 1.8.56） | 扇形のゾーン（射程 650・半角 0.65 rad ≒ 37°。0.5 から広げた。総当たりの勝率は変わらない）を 0.3 秒の遅れで発動。魔法ダメージ + 術者（撃った位置）から 200 以上離れた敵を 1 秒凍結（`stun`、タグ付き）。200 未満はダメージのみ。凍結は `onHit` で距離を見て付与し、`ccApplied` を出す。遅い 0.3 秒の間に避けられる | 忠実（扇の角度・速度は不明のため選んだ値。凍結の最大距離は扇の端 650 まで = 600 より少し長い） |
| S2 扇の先の凍った地面: 合計 225–375 (+75%) | 扇の先（術者から 540、半径 190 = スキル定義の radius）に円ゾーン。0.3 秒の遅れで発動、持続 1.8 秒、0.5 秒おき = 4 回に合計ダメージを均等に分ける（霜風の 0.36 倍の合計。MLBB は霜風と同量だが、予算のため低く）。扇の外（射程の先）でも地面には入る | 簡略（半径・持続は不明のため選んだ値、合計は MLBB の 1 : 1 より低い） |
| S2 CD 13 秒（ヒーローページ）/ 13→11（パッチ） | 13 秒固定 × 調整係数 = 6.5 秒（ヒーローページを採用） | 忠実 |
| 奥義 氷河: 直線の氷の道（100–200 (+40%) の魔法 + 80% の減速 1.2 秒） | 貫通する弾（長さ 770・半幅 120・速度 2200）。魔法ダメージ（氷河の 0.10/0.90 倍。MLBB は約 1 : 6 → ここは 1 : 9 で道を弱く）+ 80% の減速 1.2 秒（`slow`、他の減速と最大値で重なる） | 忠実（長さ・幅は不明のため選んだ値） |
| 奥義 氷河: 道が氷河に育って最大 7.5 × 7 マスに広がり砕ける。600–1200 (+150%) + 凍結 1 秒、魔力 100 ごとに +0.2 秒 | 術者から前へ 450 の位置に半径 360（直径 720 ≒ 7.5 × 7）の円ゾーンを撃った時点で置き、1.2 秒後に砕けて範囲の全員に魔法ダメージ + 凍結。凍結は 1.0 秒 + 魔力 100 ごとに 0.2 秒（発動時の魔力で決める。上限 +0.6 秒 = 1.6 秒）。氷の道（0〜770）をほぼ覆うので、道で鈍足になった敵は砕けに巻き込まれる。道の横の敵は避けられる（1.2 秒の予告）。CC 無効・無敵の相手は凍らない | 簡略（「育つ」は演出だけで、当たり判定は最初から最大。砕けるまでの時間は不明のため 1.2 秒。凍結の上限は連続スタンの防止で追加） |
| 奥義 CD 50/45/40 秒 | 40 → 32 秒 × 調整係数 = 20 → 16 秒（Velstria の試合時間に合わせて短縮） | 簡略 |
| 基本ステータス（HP 2380 など） | `master_runtime.json` の H031 のまま | 対象外 |

### 照準・ボット・説明

- HUD の照準: スキル1 は `.groundAoE`（地点・円）、スキル2 は `.cone`（`shape: .fan`・半角つき）、アルティメットは `.piercingLine`（`shape: .wideLine`）。アルティメットの帯の半幅（`targeting.radius`）は氷河の半径 360（砕けて凍らせる範囲）で、氷の道の弾の当たり幅（半幅 120、`ultPathWidth`）は別に持つ（`castGlacier` は `T.ultPathWidth` を使う）。ボットの奥義の関門が数える周囲の半径は max(radius × 1.4, 300) = 504（旧 300）に広がり、氷河の範囲（中心まで 450・半径 360）の外側の敵も数えるので少し撃ちやすい（撃つ判断は交戦中・710 以内に絞られたまま）。
- ボット: S2 は 220〜620 の距離にいる敵にだけ撃つ（近すぎると凍らないため）。奥義は交戦中で 710 以内のときだけ（汎用の「倒せる / 2 体巻き込む」の条件は先に効く）。
- 説明文は `KitText`（ja/en、数値は sim から）。ダメージ類は説明用に整数へ丸めた値を extras に出し、実際のダメージは丸めない値から比で求める。

### 検証（Release）

- 総当たり 1v1 の勝率（双方向、全 33 体との平均）: Lv1 / Lv6 / Lv12 で H031 = 78.8% / 59.1% / 47.0%（調整前。調整後は下の「バランス調整」）。同じ場の汎用アルカニスト
  H004 = 51.5 / 56.1 / 63.6%、H022 = 33.3 / 37.9 / 31.8%、H010 = 6.1 / 21.2 / 19.7%、H016 = 7.6 / 10.6 / 13.6%。
  Lv1 は氷の誇り（HP の約 +45%）が効く 1v1 の特性で高め。ロール代表 H001–H006 との TTK は Lv1/6/12 とも 2.5〜15 秒に収まる（H031 の鏡像戦 Lv1 は 15.07 秒で、H011/H016/H034 の鏡像戦と同じ 15 秒すれすれ）。

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
