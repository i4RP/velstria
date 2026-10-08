# Effekseer（ヒーロー固有のスキル・通常攻撃の演出）

2026-10-07 導入。VELSIA の「ヒーロー固有の通常攻撃・スキル演出」を、RealityKit の自前の粒子（SkillFX）ではなく Effekseer で作る。
参照ヒーロー 12 体に割り当てたキャラ（docs/SKILL_REWORK.md）の通常攻撃 + S1 + S2 + ULT を作る。
作成済み: H001 H003 H007 H008 H009 H011 H012 H013 H016 H019 H020 H024（参照ヒーロー 12 体・150 効果）+ 追加ヒーロー第 1 段階 H025 H026 H027 H028 H029（64 効果）・第 2 段階 H030 H031 H032 H033 H034（64 効果。`docs/NEW_HEROES.md`）= 22 体・278 効果。sim の新しいスキル挙動（固有挙動）が入った段階で、段の追加・調整が要る。
段の組はロールで決まる（sim のアーキタイプが同じなので）: 遠隔レンジャー = H003 型 14 本（atk_travel・s1_travel・ult_travel あり）/ 遠隔アルカニスト = H016 型 14 本（ult_telegraph あり・ult_travel なし）/ 近接（デュエリスト・アサシン・ヴァンガード・近接サポート）= 12 本（atk_cast2 あり・travel なし）。
追加ヒーローの色: H025 ルミナ = 翠緑・白銀・月光の黄 / H026 エウリア = 紫・電光の白と水色 / H027 ジャルド = 銀青・白・赤の房 / H028 ザイル = 濃紺・シアン・白 / H029 ボルグ = 青・金・白 / H030 ライナ = 桃・白・金（星の砲弾・ビーム）/ H031 オーリア = 氷青・白・淡い紫 / H032 ディアス = 赤・黒・鉄の灰（熾火の橙）/ H033 ヴァルド = 深紅・黒・青白 / H034 ゴルム = 鉄の灰・錆びた赤・茶（鎖鉤）。

## 仕組み

```
tools/effekseer/*.py（Python の DSL）──→ Effects/Effekseer/<ヒーロー>_<段>.efk（コミットする）──→ アプリのバンドルへフォルダ参照で同梱
tools/effekseer/textures.py ──→ Effects/Effekseer/Texture/Fx_*.png（アルファ付きの白。色は効果側の頂点色）
```

- ランタイム: Effekseer の C++（Metal）を静的ライブラリとして同梱（ThirdParty/Effekseer/。MIT）。`tools/build_effekseer.sh` で作り直す（cmake・ninja が要る。CI は使わない）。
- 描画: `EfkRuntime`（Objective-C++。App/Battle/Effekseer/）が Metal のレイヤーを持ち、戦闘画面（ARView）の上に重ねて描く。カメラは RealityKit のカメラの行列をそのまま渡す。
  効果が何も出ていない間は描かない（GPU を使わない）。HUD・ダメージ数値・暗い縁取りより下。
- 再生: `EffekseerDirector` が sim のイベントを効果へ対応づける。効果を持つヒーローは旧来の演出（SkillFX・通常攻撃の演出・弾の見た目）を止める。
- 効果は右手系・Y 上・1 単位 = 1 m。**前 = -Z** で作る（再生時に yaw で前を合わせる）。時間はフレーム（60fps）。速度は DSL では「毎秒」で書く（Effekseer の内部は毎フレーム）。

## 効果の名前（`<heroID>_<段>`）

| 段 | 再生される時 | 位置 / 向き |
|---|---|---|
| `atk_cast` / `atk_cast2` | 通常攻撃の発射（遠隔）・打撃（近接）。cast2 があれば左右交互 | 弓・杖の発射位置 / 近接は術者。対象の方向が前 |
| `atk_travel` | 通常攻撃の投射物が飛んでいる間 | 投射物に追従（ループ効果） |
| `atk_hit` | 遠隔は投射物の命中、近接はダメージ | 命中位置 |
| `s1_*` `s2_*` `ult_*` の `cast` | スキルの発動 | 術者（ult / 自己中心は 12 秒追従） |
| 〃 `travel` | 投射物の飛翔 | 投射物に追従 |
| 〃 `telegraph` / `impact` | 地点スキルの予告 / 着弾・ゾーン発動・即時の着弾 | 地点 |
| 〃 `hit` | そのスキルの被弾者ごと（同じ相手へは 0.12 秒に 1 回） | 被弾者 |

効果は 1 つでも足りない段があってよい（その段は何も出ない）。ヒーローの効果が 1 つでもあれば、そのヒーローの旧演出は全部止まる。

## 作り方

```sh
python3 tools/effekseer/build_all.py         # 共通テクスチャ + 全ヒーローの効果を Effects/Effekseer/ へ書き出す（.efk）
python3 tools/effekseer/build_all.py h019    # 1 体だけ（テクスチャは作り直さない）
python3 tools/effekseer/check_export.py      # 純 Python の書き出し器（efkexport.py）が同梱済みの .efk とバイト一致するか（Mac なしの確認）
python3 tools/effekseer/check_efk.py H025    # 同梱の .efk をランタイムの読み込み順に最後まで読み切れるか（構造・テクスチャの実在・ノード数）
# 確認（シミュレータへ Debug ビルドをインストール済みで）
tools/effekseer/preview.sh H003_s1_cast,H003_atk_hit 8 4   # コマ送り → /tmp/efk-preview/sheet_<名前>.png
tools/effekseer/hero_sheet.sh H019 s1_impact,ult_impact 10 4  # 1 体の何本かを 1 枚にまとめる
tools/effekseer/live.sh H003 atk 10 8                       # 練習戦で人形へ撃ち続けて録画 → /tmp/efk-live/H003_atk/
```

DSL（tools/effekseer/efkgen.py）: `Node`（粒子の発生源。`tex` `blend` `life` `count` `loc` `rot` `scale` `color` `gen` `gravity` …）を `Effect` に積んで `build()` する。
部品は tools/effekseer/fxlib.py（閃光・輪・火花・魔法陣…）。ヒーローごとの色は `fade` / `morph` で付ける。
エディタ（Effekseer.app）で開き直したい時は `effekseer save` で .efkefc にできる。
`effekseer` の CLI が無い環境（Windows など）では、`efkgen.Effect.build()` が自動で純 Python の書き出し器（`tools/effekseer/efkexport.py`、Effekseer 1.8 のバイナリ）に切り替わる。
参照ヒーロー 12 体の 150 効果は、全て CLI の出力とバイト一致（角度のラジアン変換だけ float32 で最大 2 ulp ずれる 89 本）。H025〜H034 の 128 効果は CLI の無い環境でこの書き出し器から作った（`check_export.py` の「完全一致」は書き出し器どうしの再現性）。DSL が出す範囲（Fixed / PVA / Easing・球と円の生成・スプライト・フェード・入れ子）だけ対応。範囲外は例外にする。

### 落とし穴

- **XML は旧形式で書く**: DSL が出す .efkproj は `ToolVersion 1.53c` として読ませている（新しい値にすると `ColorAll_Easing` などの旧形式の項目が黙って無視される）。
- **速度・加速度は毎フレーム**: Effekseer の PVA は 1 フレームあたり。DSL は毎秒・毎秒²で受けて変換する（変換せずに 2.5 と書くと秒速 150 m で飛ぶ）。
- **加算合成は黒い四角になる**: 不透明な黒背景のテクスチャ＋加算は、重ねたレイヤーのアルファが 1 になって黒い四角が出る。テクスチャは白 + アルファの形（textures.py）で作る。
- **明るい地面で見えない**: 加算の光は白い地面で飛ぶ。`fxlib.under_glow`（通常合成の暗めの光）を下に敷く。
- **Ring（kind="ring" / kit の `arc_slash`）は形・色・半径が書き出されない**: 公式 CLI は XML の Ring を取り込まず、既定の Ring を書き出す（同梱の Ring 13 本はどれもバイト同一。位置・回転・寿命・合成だけが違う）。形や色が要る斬撃は Sprite（`Fx_Crescent` `Fx_Streak`）で作る（H025〜H034 はそうしている）。
- **単発の効果に `count="inf"` を置かない**: 無限に出し続ける発生源は、効果が自然には終わらない（ランタイムに自動停止は無い）。止めてくれるのは、投射物に追従する travel（命中・失効で停止）と、術者に追従する ult_cast（12 秒で停止）だけ。telegraph / impact / hit / cast（S1・S2）は有限の `count` にする。
- 手元の確認は `preview.sh`（コマ送りの再現性が高い）→ `live.sh`（実際の sim のイベントでの配線・向き）の順。

## 検証

`AppTests/EffekseerTests`: 同梱の全 .efk が読めること、名前が規則どおりであること（ヒーロー ID と段）、再生・描画が落ちないこと、全効果の読み込み時間（1 効果あたり 0.03 秒・最低 4 秒）、追加ヒーロー（H025〜H034）が役割ごとの段の組をそろえていること。
Mac が無い環境では `check_export.py` と `check_efk.py`（上記）が代わりになる。
