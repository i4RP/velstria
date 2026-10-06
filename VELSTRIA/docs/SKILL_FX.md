# スキル演出（SkillFX）— 24 ヒーロー × 5 スキル の固有 VFX と詠唱モーション

目標: モバイル・レジェンド / Vainglory 級の「光る」スキル演出を、全 120 スキル（パッシブ 24 + アクティブ 96）に固有で付ける。
各スキルは (1) 固有の VFX（SkillFXRecipe）と (2) 固有の詠唱モーション（MotionBuilder）を持つ。パッシブはモーションなし。

## 構成

| 場所 | 役割 |
| --- | --- |
| `App/Battle/Render/SkillFX/FXSpec.swift` | 記述の型: FXCue（合図）・FXEmit（粒子）・FXMesh（メッシュ層）・FXTint・FXAnchor・SkillFXRecipe |
| `App/Battle/Render/SkillFX/FXKit.swift` | 部品（flare / sparks / wave / slash / pillar / dome …）。まずここから選ぶ |
| `App/Battle/Render/SkillFX/FXTextures.swift` | 手続きテクスチャ（FXTex の全 37 種。`docs` 下ではなくコードのコメント参照） |
| `App/Battle/Render/SkillFX/SkillFXPlayer.swift` | 再生器（プール・予定表・追従）。プレイ中は何も作らない |
| `App/Battle/Render/SkillFX/SkillFXDirector.swift` | sim イベント → 段の再生、パッシブ発動の推定、DEBUG の実演（-skillDemo） |
| `App/Battle/Heroes/SkillMotion.swift` | 詠唱モーション（MotionClip・MotionBuilder・技の部品） |
| `App/Battle/SkillFX/SkillFXCatalog.swift` | 目録（ヒーロー → FX_H0xx） |
| `App/Battle/SkillFX/FXGeneric.swift` | アーキタイプ別の既定演出（空の段を補う） |
| `App/Battle/SkillFX/Heroes/FX_H0xx.swift` | **ヒーロー 1 人 = 1 ファイル**（パレット・5 スキルの演出・4 スキルのモーション） |

手本は `FX_H001.swift`（城門の誓衛アルデン）。書き方・密度・重ね方をこれに合わせる。

## 段（phase）とアーキタイプ

演出は段ごとの FXCue の配列。原点・前方は段ごとに決まる（位置は局所座標 x = 右・y = 上・z = 前）。

| 段 | いつ | 原点 | `.follow` の主体 |
| --- | --- | --- | --- |
| `cast` | 発動の瞬間 | 術者の足元 | 術者 |
| `telegraph` | 予告ゾーンが置かれた時（着地点・地点 AoE） | ゾーンの中心 | — |
| `travel` | 投射物が飛んでいる間 | 投射物（地面の高さ） | 投射物（継続放出 `rate > 0` は着弾で止まる） |
| `impact` | 発動・着弾・着地 | 中心 | 術者 |
| `hit` | スキルで傷を負った相手ごと（0.15 秒に 1 回） | 被弾者の足元 | 被弾者 |

`impact` がいつ・どこで出るかはアーキタイプで決まる（SkillFXDirector）:

| アーキタイプ | 使うロール/スロット | impact の時と場所 | 使う段 |
| --- | --- | --- | --- |
| cone（扇） | 近接の S1 | 発動と同時・術者の位置（前方へ扇） | cast, impact, hit |
| lineSkillshot | 遠隔の S1 | 最初の命中・命中点 | cast, travel, impact, hit |
| dashStrike（突進） | 近接の S2 | 着地の瞬間・着地点 | cast（追従の軌跡）, telegraph, impact, hit |
| blinkEmpower | 遠隔の S2 | 発動と同時・転移先 | cast（転移元）, impact（転移先） |
| groundAoE | S3（Vanguard/Support 以外）・Arcanist の奥義 | 予告 0.5 秒（奥義 1.0 秒）後・地点 | cast, telegraph, impact, hit |
| healZone | Support の S3 | 予告 0.5 秒後・地点（味方回復） | cast, telegraph, impact |
| selfAoE | Vanguard の S3 | 発動と同時・術者（自分にシールド） | cast, impact, hit |
| leapSlam（跳躍） | Vanguard の奥義 | 着地の瞬間・着地点 | cast, telegraph, impact, hit |
| multiStrike（3 連撃） | Duelist の奥義 | 0 / 0.3 / 0.6 秒・術者の位置（回ごとに左右反転） | cast, impact ×3, hit |
| piercingLine（貫通） | Ranger の奥義 | 最初の命中 | cast, travel, impact, hit |
| teamHeal | Support の奥義 | 発動と同時・術者（範囲 15 m の味方を回復 + シールド） | cast, impact |
| targetedBlink | Assassin の奥義 | 発動と同時・対象の位置（背後へ瞬間移動） | cast（転移元）, impact（対象） |
| passive | — | ロールの合図で推定（下記） | cast のみ（`.follow` で本人に追従） |

パッシブの発動の合図: Vanguard = 瀕死の自己シールド / Duelist = 攻撃速度スタック / Ranger = 通常攻撃のクリティカル /
Arcanist = スキルが敵ヒーローに当たった / Support = スキル後の味方回復（原点は回復された味方）/ Assassin = 奇襲の一撃（原点は被弾者）。

`FXSkillInfo` の `radius`（効果半径 m）・`range`（射程 m）で大きさを合わせる（`let R = s.radius`）。
同じスロットでもヒーローの遠近でアーキタイプが変わるので、迷ったら `s.archetype` で分岐してよい。

## 見た目の作法（AAA の重ね方）

1. **芯 → 主層 → 副層 → 余韻**。白い芯（`.core`・短命）、色の主層（`.primary`）、外側（`.secondary` / `.accent`）、
   余韻（`.embers` `.motes` `.smoke`・長め）。芯は短く、外側ほど長く残す。
2. **地面に必ず跡を残す**: `decal` / `shockRing` / `wave` / `groundGlow`。トップダウン視点では地面の模様が最も読める。
3. **主題の形を 1 つ以上**: そのヒーロー固有のテクスチャ（月 = `.moon`、時計 = `.clockFace`、花弁 = `.petal`、
   歯車 = `.techCircle`、鎖 = `.chain`、羽根 = `.feather`、硝子 = `.shard`、爪 = `.claw`、音 = `.soundWave` / `.note` …）。
4. **時間差**: 全部を at: 0 にしない。溜め（gather）→ 閃光（flare）→ 衝撃（wave/shockRing）→ 余韻 を 0.02〜0.15 秒ずつずらす。
   繰り返しは `.repeated(n, every:, yaw:, step:)`、円陣は `.ringed(n, radius:, every:)`。
5. **奥義は別格**: 画面を揺らす（`.shake(0.5〜0.8)`）、大きな地面の紋章、柱・ドーム・多段の衝撃波、粒子 30〜50。
   通常スキルの揺れは 0〜0.25。
6. **打撃の同期**: sim は発動の tick に効果を即時に解決する。モーションの打撃キー（slash / smash / thrust / push / release）は
   0.05〜0.15 秒に置き、演出の `at:` をそこへ合わせる（例: slash が 0.09 秒なら斬撃の三日月は `at: 0.09`）。
7. **明るい石畳の上でも読める色**: 主層は彩度の高い色（`.primary`）。白一色の大きな板は避ける（シミュレータでは
   ブルームが出ないため薄く見えるが、実機ではブルームで光る）。`flare` は 0.8〜2.5 m に収める（大きすぎると画面が白く飛ぶ）。
8. **加算と合成**: `FXEmit` の既定は加算（光）。煙・岩片・亀裂の影は `additive: false` + `.dark`。メッシュ（FXMesh）は
   常にアルファ合成（画像のアルファ × 色）。
9. **ヒーロー間の差**: 同じロール（同じアーキタイプ）のヒーロー同士でも、形・色・時間の使い方を変える
   （例: 同じ leapSlam でも アルデン = 黄金の紋章と 7 本の光柱、ガルク = 溶岩の亀裂と岩の隆起、ブラム = 砦を砕く衝撃波と土煙）。

## 予算（性能）

- 1 スキルの全段で メッシュの合図 ≤ 16（`repeated`/`ringed` の数を含む）、粒子の合図 ≤ 10。奥義は メッシュ ≤ 24・粒子 ≤ 12。
- 1 つの粒子の数 ≤ 60（画質で自動的に減る）。継続放出（`rate`）は `duration` を付けるか travel だけで使う。
- 低画質で省いてよい余韻には `quality: 1`（中以上）/ `quality: 2`（高のみ）を付ける。
- 新しいテクスチャ・形を足すときは FXTex / FXShape に足す（プレイ中に作らない規律: AssetLedger の live = 0、
  RenderWarmupTests が検査する）。

## 詠唱モーション

`static func motion(_ slot: SkillSlot, _ m: inout MotionBuilder)` に技を順に積む（各技は直前の姿勢から変える）。
技: `brace lunge backstep settle leap land spin stomp kneel dash windup slash crossSlash overhead smash thrust chamber
uppercut twirl shieldBash raise push gather throwCast plant command roar guardCross draw release aim recoil hold key`。
細部は `m.key(dt, .snap) { p in p.armR = ArmPose(...); p.glow = 1.6 }` で直接書ける（角度の規約は HeroAnimation.swift の冒頭）。

- 長さ: 通常スキル 0.35〜0.7 秒、奥義 0.6〜1.2 秒（`build` が戻りの 0.25/0.35 秒を足す）。長すぎると移動が滑って見える。
- 武器に合わせる: 弓（`m.bow`）は draw → release、銃・弩（style `.gun`）は aim → recoil、杖・術は raise / push / plant /
  throwCast、双剣は crossSlash、盾持ち（`m.shield`）は左腕が自動で盾を構える。
- 4 スロットとも **違う動き** にする。同じロール内でもヒーローごとに変える（踏み込みの深さ・回転数・溜めの長さ）。
- `p.glow`（武器先の光）・`p.ring`（光輪）・`p.wings`（翼・外套）はモデルの発光演出を動かす。

## 確認のしかた

```
xcrun simctl create skillfx-me "iPhone 17 Pro"   # 自分専用のシミュレータ（UDID が出る）
xcrun simctl boot <UDID>
export SKILLFX_UDID=<UDID> SKILLFX_DD=/tmp/<自分の名前>-dd SKILLFX_OUT=/tmp/<自分の名前>-shots
export SKILLFX_PYTHON=~/gh2/velstria/VELSTRIA/build/stage/venv/bin/python   # Pillow 入り
tools/skillfx/build.sh                  # Debug ビルド
tools/skillfx/capture.sh H001 4         # H001 の奥義を実演・録画 → $SKILLFX_OUT/sheet_H001_4.png
```

`-skillDemo` は sim に書き込まずに、操作ヒーローのスキルを北（画面の上）へ向けて実演する（詠唱モーション + 全段）。
突進・跳躍の移動は再現しない（演出だけ）。シートは効果の山の前後 16 コマ。

## ヒーローの主題（演出の方向性）

| ヒーロー | 主題・色 | 形の手がかり |
| --- | --- | --- |
| H001 アルデン | 黄金の城門・誓いの光（金 × 蒼白） | 魔法陣・六角盾・光柱（手本） |
| H002 リラ | 星の弦・星座（シアン × 銀 × 金の星） | star / twinkle / thread（弦）/ note、細剣の突き |
| H003 フィリエル | 月光の矢（銀白 × 青緑） | moon / arrow / streak、三日月の弓 |
| H004 ミレア | 潮・水の祈り（水色 × 珊瑚） | ripple / bubble / swirl、波の壁 |
| H005 ヴォス | 黒雷（紫 × 黒 × 白い稲妻） | bolt、黒い煙、雷の光輪 |
| H006 セレン | 月灯籠と影（淡い金 × 紫の影） | moon / glowHard（灯）、影の斬撃 |
| H007 ガルク | 岩脈と溶岩（橙の溶岩 × 岩） | crack / rock / debris、拳の衝撃 |
| H008 ニア | 風の旗槍（青緑 × 白） | swirl / feather / streak、竜巻 |
| H009 オリン | 機巧・蒸気（真鍮 × 橙の火花） | techCircle / sparks / smoke、連弩 |
| H010 テッサ | 焔の冠（橙赤 × 金） | flame / embers、火球・隕石 |
| H011 ルーク | 鉄の翼・守りの灯（シアン × 鋼） | feather / hexShield、翼の盾 |
| H012 エリネ | 硝子の歌（氷青 × 虹） | shard / note / soundWave、砕ける硝子 |
| H013 ダガン | 獣の刻印（赤 × 骨白） | claw / crack、咆哮の衝撃波 |
| H014 シオ | 霧の剣士（青紫の霧 × 白刃） | smoke（霧）/ slashLine、残像の居合 |
| H015 ヴァルカ | 戦の鐘・大筒（青銅 × 金） | soundWave / ring、砲撃の衝撃 |
| H016 イリス | 白い光輪・聖光（白金） | ringDouble / runeCircle / beam、光の柱 |
| H017 モルド | 深淵の鎖（紫 × 黒） | chain / smoke、深淵の穴 |
| H018 セリア | 花と星（桃 × 金） | petal / star、花吹雪 |
| H019 ブラム | 攻城槌・砦を砕く（橙 × 鉄） | crack / debris / shockwave、土煙 |
| H020 ユナ | 光の矢と刃（金白 × 黄） | arrow / streak / slashLine、光の雨 |
| H021 キロス | 時の砂（琥珀 × 砂） | clockFace / sand、時の逆巻き |
| H022 レア | 蒼い爪・狐（蒼 × 氷） | claw / shard / moon、爪痕 |
| H023 トレン | 雷の騎槍（青 × 白い稲妻） | bolt / spire、落雷 |
| H024 ノア | 夢の糸・星雲（菫 × 桃） | thread / star / twinkle、夢の繭 |
