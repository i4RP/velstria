# VELSIA（ベルシア）- 星環の戦場

iPhone 向けの 5v5・3 レーン MOBA（v1.0 はオフライン対 AI）。ネイティブ Swift で実装しています。

- **VelstriaCore** — 30Hz 固定 tick の決定論シミュレーション（Swift Package、macOS で `swift test` 可能）
- **アプリ** — SwiftUI（メタ画面）+ RealityKit（3D 戦闘）+ StoreKit 2、iOS 18+、iPhone のみ・横画面
- ヒーロー 34 / スキル 136 / 装備 72 / バトルスペル 15 / ルーン 30（仕様: `VELSTRIA_復元版パッケージ/`）

## 構成

| パス | 内容 |
|---|---|
| `VELSTRIA/Packages/VelstriaCore/` | シミュレーション（戦闘・マップ・経済・スキル・AI・リプレイ） |
| `VELSTRIA/App/` | iOS アプリ（画面・戦闘描画・HUD・サービス） |
| `VELSTRIA/docs/DESIGN.md` | ゲームルール・数値の正本 |
| `VELSTRIA/docs/ARCHITECTURE.md` | 設計・担当範囲・決定論ルール・ビルド手順 |
| `VELSTRIA/docs/APPSTORE.md` | App Store 提出キット |
| `VELSTRIA/tools/` | アーカイブ・TestFlight アップロード・App Store Connect API・各種検証 |
| `VELSTRIA/tools/portraits/` | ヒーロー / スキンのポートレートと装備アイコンの画像の生成仕様と取り込み |
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

## 自動配信（TestFlight）

| push 先 | ワークフロー | 行き先 |
|---|---|---|
| `production` 以外のすべてのブランチ | `.github/workflows/testflight.yml` | TestFlight 内部テスト（全ビルド自動配信のグループ「In」） |
| `production` | `.github/workflows/production.yml` | 同じく TestFlight 内部テスト（グループ「In」） |

**App Store への審査提出・公開は行いません**（本番配信は不要という方針。以前あった提出前チェックと審査提出の流れは削除済み）。
どのブランチに push しても、届け先は TestFlight の内部グループだけです。

testflight.yml は `VELSTRIA/` か `.github/workflows/` に変更があるときだけ、production.yml は push のたびに動きます
（手動実行は Actions の「Run workflow」）。
中身は共通の `build-upload.yml`: 配信ツールのテスト → コアのテスト → HUD・チュートリアルのテスト → アーカイブ（手動署名）→
アップロード → 処理完了待ち → 内部テスターへの配信確認 → TestFlight の「テスト内容」にブランチ名・コミットを記入。

- ビルド番号は「2026-01-01 UTC からの経過秒」（並行して走っても重複せず増え続ける。手元からアップロードするときもこれより大きくする）。
- 最新の main を production にも反映するには `git push origin main:production`（同じ内容でもう 1 本ビルドが走り、内部グループに届く）。
- アプリ内の仮の事業者情報・URL（`{{PUBLISHER_NAME}}`、`velstria.example` 等）は、内部テストでは許可しています（`ALLOW_APP_PLACEHOLDERS=1`）。
  App Store に出すことにした場合は、`VELSTRIA/docs/APPSTORE.md` の手順で置き換えてから改めて仕組みを作り直します。

必要な Secrets（リポジトリ設定 → Secrets and variables → Actions）:
`ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_P8`（App Store Connect API キー）、
`CI_DIST_P12_BASE64` / `CI_DIST_P12_PASSWORD`（CI 専用の配布証明書）、`CI_PROFILE_BASE64`（App Store プロファイル「VELSTRIA AppStore CI」）。

## 権利

本リポジトリのソースコード・データ・画像はすべて権利者に帰属します（オープンソースライセンスは付与していません）。
