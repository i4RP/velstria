# VELSTRIA（ヴェルストリア）- 星環の戦場

iPhone 向けの 5v5・3 レーン MOBA（v1.0 はオフライン対 AI）。ネイティブ Swift で実装しています。

- **VelstriaCore** — 30Hz 固定 tick の決定論シミュレーション（Swift Package、macOS で `swift test` 可能）
- **アプリ** — SwiftUI（メタ画面）+ RealityKit（3D 戦闘）+ StoreKit 2、iOS 18+、iPhone のみ・横画面
- ヒーロー 24 / スキル 120 / 装備 72 / バトルスペル 10 / ルーン 30（仕様: `VELSTRIA_復元版パッケージ/`）

## 構成

| パス | 内容 |
|---|---|
| `VELSTRIA/Packages/VelstriaCore/` | シミュレーション（戦闘・マップ・経済・スキル・AI・リプレイ） |
| `VELSTRIA/App/` | iOS アプリ（画面・戦闘描画・HUD・サービス） |
| `VELSTRIA/docs/DESIGN.md` | ゲームルール・数値の正本 |
| `VELSTRIA/docs/ARCHITECTURE.md` | 設計・担当範囲・決定論ルール・ビルド手順 |
| `VELSTRIA/docs/APPSTORE.md` | App Store 提出キット |
| `VELSTRIA/tools/` | アーカイブ・TestFlight アップロード・App Store Connect API・各種検証 |
| `VELSTRIA/tools/portraits/` | ヒーロー / スキンのポートレート画像の生成仕様と取り込み |
| `VELSTRIA_復元版パッケージ/` | 仕様パッケージ（要件定義書・コンテンツマスター） |
| `AGENTS.md` / `CLAUDE.md` | エージェント向けの作業ルール（TestFlight への配信は必ず GitHub 経由） |

## ビルド

```sh
brew install xcodegen
cd VELSTRIA
xcodegen generate
xcodebuild -project VELSTRIA.xcodeproj -scheme VELSTRIA \
  -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO

# コアのテスト
cd Packages/VelstriaCore && swift test -c release
```

## 自動配信（TestFlight / App Store）

| push 先 | ワークフロー | 行き先 |
|---|---|---|
| `production` 以外のすべてのブランチ | `.github/workflows/testflight.yml` | TestFlight 内部テスト（全ビルド自動配信のグループ「In」） |
| `production` | `.github/workflows/production.yml` | App Store の審査に提出 → 承認されたら自動で公開 |

TestFlight は `VELSTRIA/` か `.github/workflows/` に変更があるときだけ、production は push のたびに動きます（手動実行は Actions の「Run workflow」）。
中身は共通の `build-upload.yml`: コアのテスト → チュートリアルのテスト → アーカイブ（手動署名）→ アップロード → 処理完了待ち →
TestFlight の「テスト内容」にブランチ名・コミットを記入 →（production のみ）メタデータを同期して審査に提出。

- ビルド番号は「2026-01-01 UTC からの経過秒」（並行して走っても重複せず増え続ける。手元からアップロードするときもこれより大きくする）。
- **本番に出す**: `git push origin main:production`（main の内容を production に反映）。
  - 提出前チェックで、ストア情報・法定表示・アプリ内表示に仮値（`{{PUBLISHER_NAME}}`、`velstria.example` 等）が 1 つでも残っていれば止まります
    （`python3 VELSTRIA/tools/validate_appstore_metadata.py --release` がエラー 0 になるまで本番には出ません）。
  - 同じ提出前チェック（Linux・数十秒、ビルドより前）で、次の不足もまとめて挙げて止まります。
    - 公開 URL（プライバシーポリシー・サポート・マーケティング・利用規約）が https の HTTP 200 で開けない（`validate_appstore_metadata.py --check-urls`）
    - App Store Connect の設定（`node VELSTRIA/tools/asc.mjs release-check <版>`。読み取りのみ）: 主言語の iPhone スクリーンショット、
      App 内課金の登録と状態、年齢制限の回答、価格（無料も明示）、配信する国と地域（Apple の提出検査では止まらないが、
      配信方針どおりに明示させる）、2 回目以降の `release_notes.txt`
    - 未承認の App 内課金がある間は `iap-attach` で止まります。バージョンへの追加は API で確認できないため、Web のバージョンページで
      追加を確かめてから `RELEASE_CHECK_ALLOW` に `iap-attach` を入れて再実行します（すべて承認されたら外す）。
    - 警告だけ出す項目: コンテンツの権利が未回答（submit が「第三者のコンテンツなし」で自動申告する）、初回リリースのみ
      API で確認できない App のプライバシーと Mac / Vision Pro での配信。警告・エラーは実行画面の注釈と Summary にも出ます。
    - 判定が誤っていて提出できる状態なら、リポジトリの Variables に `RELEASE_CHECK_ALLOW`（検査 ID をカンマ区切り:
      `screenshots` `iap` `iap-attach` `age-rating` `price` `availability` `release-notes` `urls`）を設定して再実行すると、
      その検査は警告として続行します。
  - 審査中に再度 push すると、その提出を取り下げて新しいビルドで出し直します。
  - 公開済みのバージョン番号では出せないので、2 回目以降は `VELSTRIA/project.yml` の `MARKETING_VERSION` を上げ、
    `VELSTRIA/docs/appstore/metadata/<言語>/release_notes.txt`（このバージョンの新機能）を用意してから push します。
  - 承認されたバージョン番号には TestFlight 用のビルドも追加できなくなります。承認されたらすぐ `main` の `MARKETING_VERSION` を上げてください
    （上げるまで TestFlight へのアップロードは「MARKETING_VERSION を上げてください」で止まります）。
  - 初回だけ App Store Connect の Web で、スクリーンショット・App のプライバシー・価格と配信状況・年齢制限・App 内課金を設定しておく
    必要があります（API で扱えない、または判断が必要な項目。詳細は `VELSTRIA/docs/APPSTORE.md`「production ブランチからの自動提出」）。
  - 承認後すぐ公開せず手動で公開したい場合は、リポジトリの Variables に `ASC_RELEASE_TYPE=MANUAL` を設定します。

必要な Secrets（リポジトリ設定 → Secrets and variables → Actions）:
`ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_P8`（App Store Connect API キー）、
`CI_DIST_P12_BASE64` / `CI_DIST_P12_PASSWORD`（CI 専用の配布証明書）、`CI_PROFILE_BASE64`（App Store プロファイル「VELSTRIA AppStore CI」）。

## 権利

本リポジトリのソースコード・データ・画像はすべて権利者に帰属します（オープンソースライセンスは付与していません）。
