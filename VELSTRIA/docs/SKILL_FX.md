# スキル演出（SkillFX）— 34 ヒーロー × 4 スロット の固有 VFX と詠唱モーション

目標: モバイル・レジェンド / Vainglory 級の「光る」スキル演出を、全 136 スキル（パッシブ 34 + アクティブ 102）に固有で付ける。
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

- 1 スキルの全段で メッシュの合図 ≤ 20（`repeated`/`ringed` の数を含む）、粒子の合図 ≤ 13。奥義は メッシュ ≤ 28・粒子 ≤ 16
  （`SkillFXTests.testRecipesRespectBudgets` が正。2026-10-17 に本文の古い値 16 / 10・24 / 12 を直した）。
- 1 つの粒子の数 ≤ 60（画質で自動的に減る）。継続放出（`rate`）は `duration` を付けるか travel だけで使う。
- 低画質で省いてよい余韻には `quality: 1`（中以上）/ `quality: 2`（高のみ）を付ける。
- 新しいテクスチャ・形を足すときは FXTex / FXShape に足す（プレイ中に作らない規律: AssetLedger の live = 0、
  RenderWarmupTests が検査する）。

### 予算の観測（打ち切り・破棄の集計）

再生器（`SkillFXPlayer`）は全員で共有する枠と合図の上限を持ち、超えると演出を打ち切る・捨てる。どれだけ起きたかを
`SkillFXPlayer.stats` に数え、`budgetSnapshot()` の写しを性能記録 `perf-report.json` の `skillFXBudget` に出す
（`-perfRun <秒>` で書き出す時点の値。`tools/perf_run.sh --out <file>` で保存した JSON に入る。スクリプトの画面の要約には出さない）。
数えるだけで、選ぶ順・捨てる動作・容量は変えない。

| 経路 | 容量（2026-10-17 のコード） | 集計 |
|---|---|---|
| 粒子放出体 | 低 10・中 22・高 34（`emitterCapacity`、試合開始時の画質。全員で共有） | `emitters` |
| メッシュ（形ごと） | 円板 28・弧 12・板 12・円柱 10・球 10・壁 8・帯 8・ドーム 5・尖塔 5・漏斗 5 = 103（低はそれぞれ半分・最低 2 = 50） | `meshShapes`・合計 `meshes` |
| 1 回の再生の合図 | 64（`BattleWorkBudget.cuesPerPlay`） | `cues.overPerPlay` |
| 遅延予約（全員の合計） | 512（`BattleWorkBudget.pendingCues`） | `cues.overPending`・`pending`・`peakPending` |

枠の集計（`emitters` / `meshShapes`）の `counts`。1 回の要求は次のどれか 1 つ:

- `requests`: 取得要求（spawn の回数。読み込み幕の裏の準備 `prewarm`・陳列 `fireWarmup` は含まない）。
- 空き（寿命を終えて update で戻った枠）からの受理: 数えない（`requests` だけ増える）。
- `cut`: 空きが無く、**寿命の途中の**演出を打ち切って受理（粒子は最も早く終わる一斉放出、メッシュは同じ形の最も古いもの）。
  打ち切った 1 回を取得の側だけで数える（返却の側では数えない）。
- `reclaimed`: 空きが無く、寿命を過ぎて回収（update）を待っていた枠をそのまま使った（予定の合図は同じ update の回収より先に出るため）。
  正常終了なので打ち切りではない。
- `rejected`: 空きも打ち切れる演出も無く、要求を捨てた（粒子: 使用中が全て止まらない継続放出のとき）。
  メッシュは容量 ≥ 2 で空きが無ければ同じ形の使用中が必ずあるため、今のコードでは起きない（経路として数えるだけ）。
- `grown`: `prewarm` の前でプールに無く、新しく作った（試合中は 0。作れば AssetLedger の live にも出る）。
- `peakInUse`: 使用中の枠の数の最大（受理の直後に測る）。`pooled` = 作ってある枠（使用中 + 空き）、`inUse` = 写しの時点の使用中。
  粒子放出体は ParticleEmitterComponent 1 つの枠で、**生きている粒子の数ではない**（止めた継続放出の消えるまでの余韻も枠を使う）。

合図の集計（`cues`）: `overPerPlay` = この画質で出す合図（`repeated` の繰り返しは 1 回ずつ。`quality:` で出さない合図は含まない）のうち、
1 回の再生の上限で受け付けなかった数。`overPending` = 遅延予約が埋まっていて捨てた数。即時（`at` 0）の合図は予約を使わない。
`stats.droppedCues` は従来の粗い合計（両方の上限を混ぜて数える）で、原因の切り分けには使わない。

`bySource`: 演出を失った側の出所ごと（`ヒーロー.スキル.再使用の段`、例 `H029.skill1.0`）。打ち切りは打ち切られた側、
拒否・合図の破棄は要求した側に数える。出所は `SkillFXDirector.context` が渡す。cast / impact などの段（phase）は再生器に渡らないので持たない。
出所の無い再生は `unknown`（推定で割り当てない）。

数えないもの: `clear()`（幕が上がる直前・シーク / 再同期の作り直し・破棄）・`stop(follow:)`（投射物の着弾・術者の死亡）・
`cut(follow:group:)`（sim の数が減った刃）で消えた演出と予約。

集計の始まりと終わり: 全て `clear()` で 0 に戻る。幕が上がる直前（`finishWarmup`）に clear されるので、読み込み中の準備・陳列は入らない。
シーク・オンラインの再同期（`resetForPresentationEpoch`）でも 0 に戻る（その後の分だけになる）。試合ごとに `BattleWorld` と再生器を作り直すので、
前の試合の値は残らない。画質は `quality`（自動調整後のいまの画質）と `poolQuality`（枠の数を決めた試合開始時の画質）を添える。

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
- 全身のモーションの目録（`HeroSkillMotions`、App/Battle/Heroes/Motions。2026-10-18: H029・H034）にあるヒーローは、ここの
  `motion` を使わない（踏み込み・跳び・足の接地・再使用の段・命中の後・全身の通常攻撃。docs/HERO_MOTION.md「全身のモーション」）。
  演出の `at:` はそのモーションの打撃の時刻（docs/vfx/H0xx.md「モーション（打撃の時刻）」）に合わせる。

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
| H025 ルミナ | 月弦の矢（翠緑 × 白銀 × 月光の黄） | moon / arrow、扇状に分かれる矢の筋 |
| H026 エウリア | 紫電（紫 × 電光の水色） | bolt / strike、分岐する稲妻・降り注ぐ雷 |
| H027 ジャルド | 銀青の竜槍（銀青 × 赤の房） | streak / shard / swirl、連突きの線・竜牙・昇竜の渦 |
| H028 ザイル | 断空の光刃（シアン × 濃紺） | slashLine / slash / beam、斬線・薙ぎ払い・三連斬 |
| H029 ボルグ | 青金の聖槌（青 × 金） | crack / hexShield / pillar、叩きつけの衝撃波・聖域 |
| H030 ライナ | 星砲の砲弾と大ビーム（桃 × 白 × 金） | star / streak / ringDouble、星をまとう砲弾・極太の貫通ビーム・星の紋 |
| H031 オーリア | 氷嵐の結晶（氷青 × 白 × 淡紫） | shard / crack / ripple / hexShield、突き上がる氷柱・凍獄のドーム |
| H032 ディアス | 赤い気の拳剣（紅 × 朱 × 鉄の灰白） | slash / claw / crack、幅広の斬線・叩きつけの衝撃・連打 |
| H033 ヴァルド | 血月の大剣（深紅 × 黒 × 青白） | moon / feather / slashLine、叩き割りの斬線・蝙蝠の羽・血月の断裂 |
| H034 ゴルム | 鉄鎖と錆びた鉤（鉄の青灰 × 錆の赤 × 真鍮） | chain / shard / crack / hexShield、鎖の筋・突き上がる鉤・鎖獄 |
