# スクリーンショット計画

## 必要なサイズ（iPhone・横画面）

| ASC の枠 | 撮影デバイス | 解像度（横） | 必須 |
|---|---|---|---|
| 6.9 インチ | iPhone 17 Pro Max | 2868 × 1320 | **必須**（他サイズはここから自動縮小される） |
| 6.1 インチ | iPhone 16e | 2532 × 1170 | 任意（小さい画面での見え方を正確に見せたい場合） |

- 1 言語・1 サイズにつき最大 10 枚。日本語（ja）と英語（en-US）それぞれに、その言語の UI で撮影した画像を登録する。
- 検索結果には先頭 3 枚（横画面の場合は 1 枚目が大きく）表示されるため、1〜3 枚目に最も魅力的な画面を置く。
- ステータスバーはアプリが非表示にしている。Dynamic Island の切り欠きがフレームに写るのは実機と同じ表示のため問題ない。
- App プレビュー動画（任意）: 15〜30 秒、横 1920×886（6.9 インチ）。戦闘 → 集団戦 → 勝利 → ホームの流れを推奨。

## 撮影方法

```sh
cd VELSTRIA
tools/screenshots.sh                    # Release ビルド → 2 デバイス × 日英 × 10 画面
tools/screenshots.sh --skip-build --lang en --only 01_battle_teamfight   # 1 枚だけ撮り直す
WAIT_BATTLE_LATE=180 tools/screenshots.sh --skip-build --only 01_battle_teamfight
```

出力: `build/screenshots/<デバイス>/<言語>/NN_name.png`（`build/` は git 管理外）。
公開版は `FeatureFlags.lanMatch = false`（ホームに「オンライン」が出ない）で撮る。true のビルドで撮った画像は、掲載文にない機能が写るので使わない。

ASC の下書きへの登録は、審査に提出せずに行える（`node tools/asc.mjs upload-screenshots build/screenshots/iPhone-17-Pro-Max --dry-run` で
計画を確認し、問題なければ `--dry-run` を外す。枠に既に画像があるときは `--replace`。`--display-type` の既定は `APP_IPHONE_67`、6.9 インチの画像もこの枠に入る）。
App 内課金の審査用スクリーンショット（Gem 購入画面・スターパスのプレミアム欄）は同じ実行で
`build/screenshots/<デバイス>/<言語>/review/iap_*.png` に保存される（製品ページには載せない。[in_app_purchases.md](in_app_purchases.md)）。

新規シミュレータは起動直後にシステムの通知バナー（「Apple Intelligence の準備ができました」等）を表示するため、
スクリプトは撮影前にアプリを `WAIT_WARMUP` 秒（既定 45 秒）起動したまま待ってからバナーの無い状態で撮影する。
写り込んだ場合は `WAIT_WARMUP=90` などに増やして該当画面だけ撮り直す。
スクリプトは専用シミュレータ `vel-shots-*` を作成して終了時に削除する。起動引数は `App/Core/DebugLaunch.swift` のもので、
`-uiTesting` により毎回新しい一時プロフィールで起動する（実データに触れない）。
起動引数のフックは出荷ビルドから除外してあるため、スクリプトは `SWIFT_ACTIVE_COMPILATION_CONDITIONS` に `SCREENSHOTS` を足した
撮影専用の Release ビルドを作る（このビルドは提出に使わない。提出用は `tools/archive.sh`）。

## 構成（撮影順 = 掲載順）

| # | ファイル | 起動引数 | 見せたいこと | キャプション案（日本語 / English） |
|---|---|---|---|---|
| 1 | `01_battle_teamfight` | `-grant -battle standard -botControl -battleSpeed 4`（120 秒後） | 5v5 の集団戦・スキル演出（操作キャラを AI に任せ、4 倍速で中盤まで進める） | 5対5の本格MOBAを、いつでもどこでも / A true 5v5 MOBA, anywhere |
| 2 | `02_home` | なし | ホーム画面の世界観 | 星環が砕けた世界ベルシアへ / Enter the shattered world of Velsia |
| 3 | `03_heroes` | `-grant -route heroes` | 24 ヒーロー・6 ロール | 24人のヒーロー、6つのロール / 24 heroes, 6 roles |
| 4 | `04_battle_lanes` | `-grant -battle standard -botControl -battleSpeed 2`（60 秒後） | 3 レーンとミニオン、HUD | 3つのレーンとジャングルを制せ / Command three lanes and the jungle |
| 5 | `05_hero_detail` | `-grant -route heroDetail:H003 -heroTab skills` | スキル詳細 | パッシブ＋3スキル＋アルティメット / Passive, 3 skills and an ultimate |
| 6 | `06_build_editor` | `-grant -route buildEditor:H003` | 装備ビルド | 92種の装備で自分だけのビルドを / Craft your build from 92 items |
| 7 | `07_ranked` | `-route rankOverview` | 対 AI ランク | 隕鉄から星環王へ、ランク戦 / Climb the ranked ladder |
| 8 | `08_skin_store` | `-route skinStore` | 見た目のみの課金 | 課金は見た目が中心。ヒーローはコインで解放 / Mostly cosmetics. Heroes unlock with Coins. |
| 9 | `09_star_pass` | `-route starPass` | スターパス | ミッションとスターパスで報酬を / Earn rewards with missions and the Star Pass |
| 10 | `10_spectate` | `-battle spectate -spectateDirector on -spectateSpeed 4`（120 秒後） | 観戦・オフライン | 通信不要。AI同士の対戦も観戦できる / No connection needed. Watch AI battles too. |

キャプションを画像に重ねる場合は、撮影画像を背景にした 2868×1320 のテンプレート（左 1/3 にキャプション）を作り、
実際のゲーム画面が画像面積の過半を占めるようにする（ガイドライン 2.3.3: スクリーンショットは実際の使用画面を示すこと）。

## 確認事項

- [ ] デバッグ表示・プレースホルダ文言（「UI0xx — 画面名」など）が写っていない（UI 実装完了後に撮影する）。
- [ ] システムの通知バナー・Dynamic Island のアクティビティが写っていない。
- [ ] `-grant` で付与した大量の通貨がストア画面に写っていない（ストア系は `-grant` なしで撮影している）。
- [ ] 英語版の画像に日本語が残っていない（`-language en` と `-AppleLanguages (en)` で撮影）。
- [ ] 戦闘画面に流血・写実的な表現がない（年齢制限 9+ の前提）。
- [ ] 実際のビルドに無い機能（オンライン対戦・チャット等）が写っていない。
