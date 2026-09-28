# App 内課金（In-App Purchases）登録シート

正本は [`iap_products.json`](iap_products.json)（`tools/validate_appstore_metadata.py` が DESIGN.md §13・
`App/Services/StoreKitService.swift`・`App/Resources/Velstria.storekit` との一致を検証する）。
この表は App Store Connect の「App 内課金」画面へ転記するためのもの。

## 一覧

| # | Product ID | 種別 | 参照名 (Reference Name) | 付与 | 基準価格 (JPY) | 目安 (USD) |
|---|---|---|---|---|---|---|
| 1 | `com.velstria.game.gem.60` | 消耗型 Consumable | Astral Gem 60 | 有償 60 | ¥160 | $0.99 |
| 2 | `com.velstria.game.gem.300` | 消耗型 Consumable | Astral Gem 300 (+30) | 有償 300 + 無償 30 | ¥800 | $4.99 |
| 3 | `com.velstria.game.gem.980` | 消耗型 Consumable | Astral Gem 980 (+110) | 有償 980 + 無償 110 | ¥2,500 | $14.99 |
| 4 | `com.velstria.game.gem.1980` | 消耗型 Consumable | Astral Gem 1980 (+260) | 有償 1,980 + 無償 260 | ¥4,900 | $29.99 |
| 5 | `com.velstria.game.gem.3280` | 消耗型 Consumable | Astral Gem 3280 (+600) | 有償 3,280 + 無償 600 | ¥8,000 | $49.99 |
| 6 | `com.velstria.game.gem.6480` | 消耗型 Consumable | Astral Gem 6480 (+1600) | 有償 6,480 + 無償 1,600 | ¥15,800 | $99.99 |
| 7 | `com.velstria.game.pass.premium` | 非消耗型 Non-Consumable | Star Pass Premium Season 1 | スターパス S1 プレミアムトラック | ¥980 | $5.99 |

- ボーナス分（+30 等）は**無償ジェム**として付与し、有償ジェムと分けて保持・表示する（資金決済法の表示・未使用残高の算定対象は有償分のみ）。
- 価格は「価格設定」で**日本を基準ストア**にして JPY の価格ポイントを選び、他ストアは App Store Connect の自動換算に任せる。
  指定額ちょうどの価格ポイントが無い場合は最も近いものを選び、DESIGN.md §13 と `StoreKitService.gemProducts.referencePriceJPY` を同じ値に更新する（検証スクリプトが不一致を検出する）。
- 自動更新サブスクリプションは v1.0 では使わない。

## ローカライズ（表示名 / 説明）

| Product ID | 日本語 表示名 | 日本語 説明 | English Display Name | English Description |
|---|---|---|---|---|
| gem.60 | アストラルジェム 60個 | 見た目アイテムの購入に使える有償ジェム60個 | 60 Astral Gems | 60 paid Astral Gems for cosmetic items. |
| gem.300 | アストラルジェム 300個（+30） | 有償ジェム300個＋無償ボーナス30個 | 300 Astral Gems (+30 Bonus) | 300 paid Astral Gems plus 30 bonus gems. |
| gem.980 | アストラルジェム 980個（+110） | 有償ジェム980個＋無償ボーナス110個 | 980 Astral Gems (+110 Bonus) | 980 paid Astral Gems plus 110 bonus gems. |
| gem.1980 | アストラルジェム 1980個（+260） | 有償ジェム1980個＋無償ボーナス260個 | 1980 Astral Gems (+260 Bonus) | 1980 paid Astral Gems plus 260 bonus gems. |
| gem.3280 | アストラルジェム 3280個（+600） | 有償ジェム3280個＋無償ボーナス600個 | 3280 Astral Gems (+600 Bonus) | 3280 paid Astral Gems plus 600 bonus gems. |
| gem.6480 | アストラルジェム 6480個（+1600） | 有償ジェム6480個＋無償ボーナス1600個 | 6480 Astral Gems (+1600 Bonus) | 6480 paid Astral Gems plus 1600 bonus gems. |
| pass.premium | スターパス プレミアム S1 | シーズン1のプレミアム報酬トラックを解放 | Star Pass Premium: Season 1 | Unlocks the Season 1 premium reward track. |

## 審査用情報（各商品に必須）

- **審査用スクリーンショット**: 購入画面（通貨ストア / スターパス）を 1 枚ずつ。`tools/screenshots.sh` の `08_skin_store` / `09_star_pass` を流用するか、
  `xcrun simctl launch <UDID> com.velstria.game -uiTesting -skipOnboarding -route currencyStore` で撮影する（640×920 以上）。
- **審査メモ**（全商品共通でよい）:
  > Consumable Astral Gems are spent only on cosmetic items and never affect gameplay. Paid and bonus gems are tracked separately; bonus gems are spent first. Purchases are granted once per verified transaction (idempotent by transaction ID) and finished immediately. Star Pass Premium (non-consumable) unlocks the Season 1 premium reward track and can be restored with Restore Purchases.
- 初回提出時は、アプリのバージョンページ「App 内課金」セクションで 7 商品すべてを**このバージョンに追加**してから審査に出す（追加し忘れると商品が審査されず、アプリが却下される）。

## スターパスの商品設計についての注意

`com.velstria.game.pass.premium` は非消耗型なので、一度購入すると**恒久的に所有**扱いになる。
v1.0 ではシーズン 1 専用として販売し（表示名・説明にシーズン 1 と明記）、シーズン 2 以降は新しい Product ID
（例 `com.velstria.game.pass.premium.s2`）を追加するか、非更新サブスクリプションに切り替える。
既存購入者の S1 プレミアム報酬は復元で常に受け取れるようにする。

## Sandbox での確認手順（社内テスト）

1. App Store Connect > ユーザとアクセス > Sandbox でテスター（未使用のメールアドレス）を作成する。
2. テスト端末の 設定 > App Store > Sandbox アカウント でサインインする（本番の Apple Account とは別）。
3. TestFlight または Xcode から実機にインストールし、オンボーディングで年齢区分「20 歳以上」を選ぶ。
4. ストア > 通貨ストア で各ジェムパックを購入 → 有償/無償ジェムの残高が表示どおり増えることを確認。
5. アプリを購入シート表示中に強制終了 → 再起動後、未完了トランザクションが 1 回だけ付与されることを確認（二重付与 0 件）。
6. スターパス > プレミアム解放 → アプリ削除 → 再インストール → ストア > 購入の復元 でプレミアムが戻ることを確認。
7. 年齢区分「15 歳以下」で 5,000 円、「16〜19 歳」で 10,000 円を超える購入がブロックされることを確認。
8. 返金: Xcode の StoreKit テスト（Debug > StoreKit > Manage Transactions）で返金 → 有償ジェムが減算されることを確認。
9. 「承認と購入のリクエスト（Ask to Buy）」を有効にした Sandbox テスターで、保留（pending）表示になり承認後に付与されることを確認。

Xcode 上の単体確認は scheme の StoreKit Configuration（`App/Resources/Velstria.storekit`）で行える（ネットワーク・Sandbox アカウント不要）。
