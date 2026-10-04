# VELSTRIA App Store 提出キット

App Store Connect（ASC）への v1.0 提出に必要なもの一式と手順。数値・ルールの正本は [DESIGN.md](DESIGN.md)。
メタデータは fastlane `deliver` 互換の配置（`docs/appstore/metadata/`）で管理し、手入力でも fastlane でも使える。

## 1. ファイル構成

| 用途 | ファイル |
|---|---|
| 本書（手順・全回答） | `docs/APPSTORE.md` |
| ストア掲載文（日本語 / 英語） | `docs/appstore/metadata/ja/*.txt`, `docs/appstore/metadata/en-US/*.txt` |
| カテゴリ・著作権 | `docs/appstore/metadata/primary_*.txt`, `copyright.txt` |
| 審査メモ・審査連絡先 | `docs/appstore/metadata/review_information/*.txt`、解説 [review_notes.md](appstore/review_notes.md) |
| App 内課金 | [in_app_purchases.md](appstore/in_app_purchases.md), `docs/appstore/iap_products.json` |
| 年齢制限の回答 | [age_rating.md](appstore/age_rating.md) |
| App のプライバシー（栄養ラベル） | [app_privacy.md](appstore/app_privacy.md) |
| 輸出コンプライアンス・コンテンツ権利 | [compliance.md](appstore/compliance.md) |
| スクリーンショット計画 | [screenshots.md](appstore/screenshots.md) |
| リリース判定チェックリスト | [release_checklist.md](appstore/release_checklist.md) |
| 法務文書（Web 公開用） | `docs/legal/`（プライバシーポリシー・利用規約 日英、特定商取引法に基づく表記、資金決済法に基づく表示） |
| アイコン・起動ロゴ生成 | `tools/make_icon.swift` |
| 英語オーバーレイ生成・検証 | `tools/gen_master_en.py` → `App/Resources/master_en.json` |
| 日本語表示名オーバーレイ（マスターの仮名の置き換え） | `tools/gen_master_ja.py` → `App/Resources/master_ja.json` |
| プライバシーマニフェスト | `App/Resources/PrivacyInfo.xcprivacy`、検査 `tools/privacy_audit.py` |
| メタデータ検証 | `tools/validate_appstore_metadata.py` |
| アーカイブ・書き出し | `tools/archive.sh`、`ExportOptions-AppStore.plist` |
| スクリーンショット撮影 | `tools/screenshots.sh` |

## 2. 記入が必要なプレースホルダ

リポジトリには実在の会社情報・連絡先・Team ID を置かない。提出前に以下を置き換え、
`python3 tools/validate_appstore_metadata.py --release` がエラー 0 になることを確認する。

| プレースホルダ | 内容 | 使用箇所 |
|---|---|---|
| `{{PUBLISHER_NAME}}` | 販売事業者の正式名称（法人名または個人名） | copyright.txt、法務文書、アプリ内の資金決済法表示（`App/Screens/Store/StoreLogic.swift` の `StoreLegalText`） |
| `{{REPRESENTATIVE_NAME}}` | 代表者 / 運営統括責任者 | 特定商取引法表記、資金決済法表示（アプリ内も同上） |
| `{{POSTAL_ADDRESS}}` | 所在地 | 法務文書、アプリ内の資金決済法表示 |
| `{{PHONE_NUMBER}}` | 電話番号（受付時間を併記） | 特定商取引法表記、資金決済法表示（アプリ内も同上） |
| `{{SUPPORT_EMAIL}}` | サポート窓口メールアドレス | 法務文書（アプリ内は `FeatureFlags.supportEmail`） |
| `{{EFFECTIVE_DATE}}` | 法務文書の施行日 | 法務文書 |
| `{{TERMS_URL}}` | 利用規約の公開 URL（`FeatureFlags.termsURL` と同じ） | 資金決済法に基づく表示 |
| `{{COURT}}` | 合意管轄裁判所（例: 東京地方裁判所） | 利用規約 |
| `{{REVIEW_CONTACT_*}}` | 審査担当からの連絡先（氏名・電話・メール） | review_information/*.txt |
| `https://velstria.example/...` | サポート / マーケティング / プライバシーポリシーの公開 URL | metadata/*/…_url.txt、`App/Core/FeatureFlags.swift` |
| `TEAM_ID` 環境変数 | Apple Developer Team ID（10 桁） | `tools/archive.sh`（リポジトリには書かない） |

> URL を確定したら `App/Core/FeatureFlags.swift`（統合担当の契約ファイル）の `supportEmail` / `privacyPolicyURL` / `termsURL` も同じ値に更新すること。
> 審査ではアプリ内のリンク先と ASC のプライバシーポリシー URL が実際に開けることを確認される。
>
> アプリに埋め込まれる値（`App/` 内の `{{…}}` と `*.example`）は TestFlight のテスターにも見えるため、
> `tools/archive.sh` は既定でエラーにして止める（`validate_appstore_metadata.py --archive`）。
> 社内確認用に限り `ALLOW_APP_PLACEHOLDERS=1` で警告に下げられるが、外部テスト・審査に出すビルドでは使わないこと。

## 3. App 情報（App Information）

| 項目 | 日本語 | English (U.S.) |
|---|---|---|
| 名前（30 文字以内） | VELSTRIA - 星環の戦場 | VELSTRIA: Star Ring Arena |
| サブタイトル（30 文字以内） | オフラインで遊べる5対5のMOBA | Offline 5v5 MOBA vs Smart AI |
| プライマリ言語 | 日本語 | |
| バンドル ID | `com.bitcoinpay.velstria` | |
| SKU（ASC 内部用） | `VELSTRIA-IOS-001` | |
| カテゴリ | プライマリ: ゲーム（サブカテゴリ: アクション、ストラテジー）／セカンダリ: なし | Primary: Games (Action, Strategy) |
| 著作権 | `2026 {{PUBLISHER_NAME}}` | |
| コンテンツ配信権 | 第三者コンテンツを含まない（[compliance.md](appstore/compliance.md)） | |
| 年齢制限 | **9+**（まれ/軽度なアニメまたはファンタジーの暴力）→ [age_rating.md](appstore/age_rating.md) | |
| Made for Kids | いいえ | No |

- 名前・サブタイトル・プロモーションテキスト・説明・キーワードは `docs/appstore/metadata/<locale>/` のファイルをそのまま貼る。
- **キーワード**（100 文字以内・カンマ区切り・空白なし）: 名前とサブタイトルに含まれる語（MOBA / 5v5 / オフライン 等）は既に検索対象なので重複させない。
- **プロモーションテキスト**（170 文字以内）は審査なしで随時更新できる。イベント告知に使う。
- **このバージョンの新機能**: v1.0 では入力欄が無い。1.0.1 以降は `metadata/<locale>/release_notes.txt` を追加する（上限 4,000 文字）。

## 4. 価格と配信状況

- 価格: **無料**（App 内課金あり）。
- 配信地域: 日本・米国ほか全地域を基本とし、以下を除外または個別判断する。
  - **中国本土**: ゲームには国家新聞出版署の版号（ISBN）が必要なため除外する。
  - 韓国・ベトナム等、ゲームの事前等級審査や登録を求める地域は、ASC の地域別要件の案内に従い対応できる場合のみ配信する。
- 事前予約: 任意（利用する場合は予約開始の 2 週間以上前にビルドを審査に出す）。
- 対応機種: iPhone のみ（`TARGETED_DEVICE_FAMILY = 1`）、iOS 18.0 以上、横画面固定。
  iPad では iPhone 互換モードで動作する（審査は iPad でも起動確認されるため、互換表示で崩れないことを確認）。
- Apple Silicon Mac / Apple Vision Pro での配信: **オフ**（`SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO` 等に合わせ、ASC の「価格および配信状況」でもチェックを外す）。

## 5. App のプライバシー

- プライバシーポリシー URL: `metadata/ja/privacy_url.txt`（日本語）、`metadata/en-US/privacy_url.txt`（英語）。本文は `docs/legal/privacy_policy_*.md`。
- データ収集: **「データを収集しない」（Data Not Collected）** → 詳細と根拠は [app_privacy.md](appstore/app_privacy.md)。
- トラッキング: なし（App Tracking Transparency のダイアログも出さない）。
- プライバシーマニフェスト `PrivacyInfo.xcprivacy`: トラッキングなし・収集データなし・Required Reason API は
  UserDefaults（CA92.1）、File timestamp（C617.1: リプレイファイルの更新日時）、System boot time（35F9.1: 効果音・触覚の再生間隔の計測に
  `ProcessInfo.systemUptime` を使用）。コードに API を追加したら `python3 tools/privacy_audit.py` で宣言漏れを確認する。

## 6. 審査に関する情報（App Review Information）

- サインイン: **不要**（アカウント機能なし。デモアカウント欄は空欄のまま「サインインは不要」にする）。
- 連絡先: `metadata/review_information/first_name.txt` などを記入。
- メモ: `metadata/review_information/notes.txt`（英語。審査担当は英語で読む）。日本語訳と各記載の根拠は [review_notes.md](appstore/review_notes.md)。
- 添付: 任意で 30 秒程度のプレイ動画（ホーム → 対戦開始 → ストア > Gem を購入 の購入まで）を添付すると質問の往復を減らせる。

## 7. 輸出コンプライアンス・コンテンツ権利

- `ITSAppUsesNonExemptEncryption = NO`（Info.plist に設定済み）。独自の暗号化は使わず、通信は StoreKit（OS 提供）のみ。
  → アップロード後に輸出コンプライアンスの質問は表示されない。詳細は [compliance.md](appstore/compliance.md)。
- コンテンツ権利: 第三者の著作物・商標・実在人物を含まない。すべてオリジナル（生成 AI を使った 3D 素材の扱いを含め [compliance.md](appstore/compliance.md) を参照）。

## 8. ビルドの作成とアップロード

```sh
cd VELSTRIA
# 1) 生成物を最新化（アイコン・英語オーバーレイ・日本語表示名オーバーレイ）
swift tools/make_icon.swift
python3 tools/gen_master_en.py
python3 tools/gen_master_ja.py
# 2) 検証（アーカイブ時にも自動実行される）
python3 tools/gen_master_en.py --check
python3 tools/gen_master_ja.py --check
python3 tools/privacy_audit.py
python3 tools/validate_appstore_metadata.py --release
# 3) アーカイブと .ipa 書き出し（アップロードはしない）
TEAM_ID=<10桁のTeamID> BUILD_NUMBER=<前回+1> STRICT=1 tools/archive.sh
```

- `tools/archive.sh` は `TEAM_ID` が無いと実行を拒否する。Team ID はリポジトリに書かない。
- 書き出し設定 `ExportOptions-AppStore.plist` は `method = app-store-connect`、`destination = export`（自動アップロードしない）、
  `uploadSymbols = YES`（dSYM を送ってクラッシュをシンボル化）、自動署名。`teamID` は `__TEAM_ID__` のプレースホルダで、
  スクリプトが `build/ExportOptions.plist` に置き換えたコピーを使う。
- アップロードは人が確認してから: Xcode > Organizer > Validate App → Distribute App、または Transporter.app に `build/export/VELSTRIA.ipa` を渡す。
- バージョン: `project.yml` の `MARKETING_VERSION`（表示バージョン）と `CURRENT_PROJECT_VERSION`（ビルド番号）。
  ビルド番号はアップロードごとに増やす（`BUILD_NUMBER` で上書き可）。

### Release ビルド設定（project.yml）

| 設定 | 値 | 理由 |
|---|---|---|
| `SWIFT_COMPILATION_MODE` | wholemodule | 全体最適化（シミュレーションの 1 tick 1ms 予算） |
| `SWIFT_OPTIMIZATION_LEVEL` | -O | 速度優先の最適化 |
| `DEBUG_INFORMATION_FORMAT` | dwarf-with-dsym | クラッシュログのシンボル化 |
| `VALIDATE_PRODUCT` | YES | アーカイブ時に製品検証 |
| `ENABLE_BITCODE` | NO | Bitcode は廃止済み |
| `ENABLE_TESTABILITY` | NO | 出荷ビルドから内部シンボルの公開を外す |
| `TARGETED_DEVICE_FAMILY` | 1 | iPhone 専用（xcodegen の既定 "1,2" をターゲット側で上書き） |
| `DEVELOPMENT_TEAM` | 空 | `tools/archive.sh` が `TEAM_ID` から注入 |

Info.plist（project.yml の `info.properties` から生成）: `UILaunchScreen`（背景色 `LaunchBackground` + 画像 `LaunchLogo`）、
`UIUserInterfaceStyle = Dark`、`NSHumanReadableCopyright = © 2026 VELSTRIA`、横画面のみ、`ITSAppUsesNonExemptEncryption = NO`。
scheme の Run には StoreKit 構成ファイル `App/Resources/Velstria.storekit` を設定済み（Xcode 実行時の課金テスト用）。

## 9. アイコンと起動画面

- `swift tools/make_icon.swift` が CoreGraphics で描画（外部依存なし・固定シードで毎回同じ画像）。
  - `AppIcon-1024.png`: 1024×1024、**不透明（アルファなし）・角丸なし**（角丸は iOS が付ける）。藍→紫の放射グラデーション、金の星環、4 芒星、双刃の「V」、シアンの星屑。
  - `AppIcon-Dark-1024.png`（ダーク外観・透過）/ `AppIcon-Tinted-1024.png`（色付き外観・グレースケール）。
  - `LaunchLogo.imageset`: 紋章のみの透過 PNG（240pt、@1x/@2x/@3x）。
- 確認用プレビュー: `swift tools/make_icon.swift --preview /tmp/icon-preview`（角丸マスク・60px 縮小・ダーク/色付き合成・起動画面合成を出力）。
- App Store の製品ページのアイコンはビルド内の `AppIcon` から自動で使われる（別途アップロード不要）。

## 10. 提出手順（チェック順）

1. [release_checklist.md](appstore/release_checklist.md) の「ビルド前」項目を満たす。
2. `tools/archive.sh` でアーカイブ → Organizer で Validate → アップロード。
3. ASC でビルドの処理完了を待ち、TestFlight 内部テストで起動・対戦・課金（Sandbox）・復元を確認。
4. App 情報・価格・プライバシー・年齢制限・App 内課金（7 商品をバージョンに追加）を本書どおり入力。
5. スクリーンショット（6.9 インチ必須、6.1 インチ任意）を日英でアップロード（[screenshots.md](appstore/screenshots.md)）。
6. 審査メモ・連絡先を入力し、「審査へ提出」。リリース方法は「手動でリリース」を推奨（承認後に公開タイミングを選べる）。
7. 承認後、段階的リリース（7 日間）を有効にして公開し、クラッシュ率とレビューを監視する。

### 10.1 production ブランチからの自動提出

`production` ブランチに push すると GitHub Actions（`.github/workflows/production.yml`）が上の 2〜6 を自動で行う。
公開方法の既定は「承認されたら自動で公開」（`AFTER_APPROVAL`）。承認後に公開タイミングを選びたい場合は、
リポジトリの Variables に `ASC_RELEASE_TYPE=MANUAL` を設定する。

| 段階 | 内容 | 止まる条件 |
|---|---|---|
| 提出前チェック（Linux） | `gen_master_*.py --check`・`privacy_audit.py`・`validate_appstore_metadata.py --release --check-urls`、`asc.mjs release-check <MARKETING_VERSION>`（読み取りのみ） | 仮値・プレースホルダが残っている／公開 URL が https の HTTP 200 で開けない／そのバージョン番号が承認済み・公開済み／下の Web 設定が足りない |
| ビルド（macOS） | コア・チュートリアルのテスト → `STRICT=1` でアーカイブ → アップロード → 処理完了待ち | テスト失敗・署名失敗・Apple 側の処理失敗 |
| 提出（`asc.mjs submit`） | `docs/appstore/metadata/` の掲載文・名前・サブタイトル・URL・カテゴリ・著作権・審査連絡先とメモを同期 → 輸出コンプライアンス・コンテンツの権利（未回答時のみ「第三者のコンテンツなし」）→ ビルドを紐付け → 審査に提出 | Web でしか設定できない項目が未設定（Apple のエラーに不足項目が列挙される） |

- **初回だけ Web で設定が必要**（API で扱えない、または判断が必要な項目）: スクリーンショット（§ [screenshots.md](appstore/screenshots.md)）、
  App のプライバシー（§5）、価格と配信状況（§4）、年齢制限（[age_rating.md](appstore/age_rating.md)）、App 内課金の登録とバージョンへの追加。
  次のバージョンからは ASC が前のバージョンの値を引き継ぐ。
- 提出前チェック（`asc.mjs release-check`）は、submit が使うバージョン・App 情報について次を確認し、提出・公開の前に足りないものを
  まとめて挙げてビルド前に止める（検査 ID）: 主言語の iPhone スクリーンショット 6.9 か 6.5 インチ（`screenshots`）、
  `iap_products.json` の課金の登録・種別・提出できる状態（`iap`。`FeatureFlags.inAppPurchases = true` のとき）、
  未承認の課金のバージョンへの追加（`iap-attach`）、年齢制限の回答（`age-rating`）、価格（`price`）、配信する国と地域（`availability`）、
  2 回目以降の `release_notes.txt`（`release-notes`）。公開 URL の到達確認は `urls`。
  - `availability` は Apple の提出検査では止まらない（`appAvailabilityV2` が 404 = 未設定のまま審査に提出できた実例がある）。
    未設定のまま承認されると配信先が §4 の方針（中国本土は除外・日本で配信）どおりにならないため、明示的な設定を必須にしている。
  - `iap-attach` は未承認の課金がある間は必ず止まる。初めての課金をバージョンに追加したかは API で追加も確認もできず、
    追加し忘れても submit は App だけを提出して成功し、ガイドライン 2.1 で却下されるため。Web のバージョンページ
    「App 内課金とサブスクリプション」で追加を確かめてから `RELEASE_CHECK_ALLOW` に `iap-attach` を入れる（すべて承認されたら外す）。
  - 警告だけ出す項目: コンテンツの権利が未回答（submit が「第三者のコンテンツなし」で自動申告する。回答済みなら確認済みとして表示）、
    初回リリースのみ API で確認できない App のプライバシー（§5）と Mac / Vision Pro での配信（§4）。
  - GitHub Actions では警告・エラーを実行画面の注釈と手順のまとめ（Summary）にも出す（注釈は 10 件までなので全件は Summary で見る）。
- 判定が誤っていて実際には提出できる場合は、リポジトリの Variables に `RELEASE_CHECK_ALLOW=<ID>,...` を設定して再実行すると、
  その検査のエラーを警告に格下げして続行する（手元では `node tools/asc.mjs release-check 1.0.0 --allow=<ID>,...`）。直ったら外す。
- 審査中（審査待ちを含む）に再び push すると、その提出を取り下げて新しいビルドで出し直す（審査の順番は最後尾に戻る）。
- 2 回目以降のリリース: `project.yml` の `MARKETING_VERSION` を上げ、`metadata/<言語>/release_notes.txt`（このバージョンの新機能）を
  追加してから push する。無ければ提出段階で止まる。
- 承認されたバージョン番号には TestFlight 用のビルドも追加できなくなるため、承認されたらすぐ `main` の `MARKETING_VERSION` を上げる。
- 手元で確認するとき: `node tools/asc.mjs submit <ビルド番号> --dry-run`（読み取りだけで、行う変更を表示する）。

## 11. よくある却下理由と対策

| ガイドライン | 想定リスク | 対策 |
|---|---|---|
| 2.1 App の完成度 | 課金商品がバージョンに追加されていない / 購入が失敗する | 7 商品を追加、Sandbox で全商品購入を確認、審査メモに手順を記載 |
| 2.3 正確なメタデータ | スクリーンショットが実機能と異なる / プレースホルダ文言 | `tools/screenshots.sh` で実ビルドから撮影、`--release` 検証 |
| 3.1.1 App 内課金 | 外部決済への誘導、ランダム型有料アイテムの確率非表示 | 外部リンクで課金しない、有料ガチャなし（内容確定型のみ） |
| 3.1.1 復元 | 非消耗型の復元手段がない | ストア > 購入の復元（`Route.restorePurchases`） |
| 5.1.1 プライバシー | プライバシーポリシー URL が開けない / データ削除手段がない | URL を公開、設定 > プライバシーで全データ削除 |
| 5.1.2 | 収集していないと申告したのに SDK が収集 | 解析・広告 SDK を入れない。入れる場合は栄養ラベルとマニフェストを更新 |
| 4.0 デザイン | iPad 互換モードで UI が崩れる | iPad シミュレータで互換表示を確認 |
