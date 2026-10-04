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
| `VELSTRIA_復元版パッケージ/` | 仕様パッケージ（要件定義書・コンテンツマスター） |

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

## TestFlight への自動配信

`main` に push すると GitHub Actions（`.github/workflows/testflight.yml`）が
コアのテスト → アーカイブ（手動署名）→ App Store Connect へのアップロード → 処理完了待ちを行います。
内部テストグループは全ビルド自動配信の設定なので、処理完了後に TestFlight へ届きます。
ビルド番号は `100 + 実行番号` です。手動実行は Actions の「Run workflow」から。

必要な Secrets（リポジトリ設定 → Secrets and variables → Actions）:
`ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_P8`（App Store Connect API キー）、
`CI_DIST_P12_BASE64` / `CI_DIST_P12_PASSWORD`（CI 専用の配布証明書）、`CI_PROFILE_BASE64`（App Store プロファイル「VELSTRIA AppStore CI」）。

## 権利

本リポジトリのソースコード・データ・画像はすべて権利者に帰属します（オープンソースライセンスは付与していません）。
