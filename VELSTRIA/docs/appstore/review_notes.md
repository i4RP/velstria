# 審査メモ（App Review Notes）

ASC の「App Review に関する情報 > メモ」には英語版 [`metadata/review_information/notes.txt`](metadata/review_information/notes.txt)
をそのまま貼る（4,000 文字以内。`tools/validate_appstore_metadata.py` が検証）。以下は社内確認用の日本語訳と、各記載の根拠。

> 画面の導線（「ホーム > 対戦開始」「ホーム > オンライン」など）は UI 実装の最終版と照合してから提出すること（release_checklist.md「審査メモの導線確認」）。
> 導線が変わった場合は notes.txt と本書を同時に更新する。2026-10-12 の改訂は、App 側で作業中のオンラインの安全対策（App/Online/OnlineSafety.swift ほか）を前提にしている。

## 日本語訳

VELSIA - 星環の戦場 は iPhone 向けの 5 対 5 MOBA です。ひとりで遊ぶモード（AI の味方・敵との対戦、練習場、チュートリアル、観戦、リプレイ）は端末内で動き、通信は不要です。
任意でオンライン対戦もできます。1 人の iPhone が部屋をホストし、ほかの人は 6 文字の部屋コード（当方の中継サーバー〈Cloudflare Workers〉を経由）か、
同じ Wi-Fi の「近くの部屋」（ローカルネットワーク／Bonjour）から参加します。アカウント・ログイン、自由入力のチャット、ボイスチャットはありません。App 内課金は Apple の StoreKit を使います。

**初回起動**
1. タップしてスタートし、「20 歳以上」を選んでください。未成年の区分には月間購入上限があり、テスト購入がブロックされる場合があります。13 歳未満はオンライン機能を使えません。
2. 利用規約とプライバシーポリシーに同意します。
3. 任意のプレイヤー名を入力します（不適切な語・連絡先を含む名前は弾かれます）。チュートリアルはプレイしてもスキップしても構いません。

**各機能の場所**
- 対 AI の対戦: ホーム > 対戦開始 > 通常戦 > ヒーロー選択 > 決定 > 出撃。ランク戦: ホーム > 対戦開始 > ランク戦 > ドラフトへ。1 試合 10〜18 分。
- 短時間で確認: ホーム > 練習場。
- チュートリアル: ホーム > 対戦開始 > その他 > チュートリアル。
- 観戦: ホーム > 観戦。リプレイ: ホーム > リプレイ（.vreplay には試合の構成・入力・表示名だけが入り、共有シートで送った時だけ渡る）。
- データの削除、ブロックしたプレイヤー、オンライン機能をやめる: 設定 > プライバシー。サポートと規約: 設定 > サポート。

**オンライン対戦（試合には iPhone が 2 台必要）**
1. 端末 A: ホーム > オンライン。初回は「オンラインのルール」を読み、「コミュニティガイドラインと利用規約に同意します」にチェックして「同意してはじめる」。パーティが開いて部屋コードが出る。「友だちを招待」で共有できる。ここで iOS がローカルネットワークの許可を求める。
2. 端末 B: ホーム > オンライン > 同意 > 部屋コードで参加 > コードを入力 > 参加（同じ Wi-Fi なら「近くの部屋」から選ぶ）。
3. 端末 A: ゲーム開始。空いた席は AI が担当する。
4. フレンド: 各端末に「あなたのフレンドコード」が出る。B で「フレンドを追加」> A のコード > 申請。A で「フレンド申請」> 承認。以後、フレンド一覧から招待できる。
端末が 1 台でも、オンラインのルール、部屋コード、フレンドコード、安全の設定は確認できる。2 人目が必要なら審査の連絡先から知らせてもらえれば、当方の端末から参加する。

**安全対策（ガイドライン 1.2）**
- フィルタ: 表示名と部屋名は、入力時と受信時に端末内で判定する。
- 通報: プレイヤーの横の「…」（パーティの枠・参加者の一覧・フレンド・フレンド申請・招待）> 通報する > 理由 > info@btcpay.jp 宛てのメールの下書き（相手の名前・フレンドコード・プレイヤー ID 入り）。オンライン対戦の後は、結果画面 > 通報・不具合報告。
- ブロック: 同じメニュー > ブロックする。ブロックした相手の申請・招待は捨て、相手は自分がホストの部屋に入れない。解除は 設定 > プライバシー。
- ホストは「部屋から外す」ができる。パーティの招待はフレンドからだけ受け付ける。
- 通報は受付から 2 営業日以内に確認を始め、違反した相手のフレンドコードを停止できる。
- ルール: https://velsia.bitcessing.com/en/community

**App 内課金**
- 消耗型アストラルジェム 6 種: `com.bitcoinpay.velstria.gem.60` / `.gem.300` / `.gem.980` / `.gem.1980` / `.gem.3280` / `.gem.6480`
- 非消耗型 1 種: `com.bitcoinpay.velstria.pass.premium`（スターパス プレミアム シーズン 1）

手順: ホーム > ストア > Gem を購入 > パックを選ぶ > 購入確定。検証済みトランザクションの完了で有償ジェム残高（ボーナス込み）が増える。
スターパス プレミアム: ホーム > スターパス > プレミアム。購入の復元: ホーム > ストア > 復元。
有料アイテムは見た目のみ。ルートボックスは無い。ヒーローは全員が全員を使え、販売していない。

**プライバシー**
中継が保持するのはフレンドのデータだけ（フレンドコード、不在の相手宛てに預かる申請の表示名〈14 日〉、各受信箱の鍵のハッシュと最後に接続した日時）。
設定 > プライバシー の「フレンドサーバーのデータを削除」か「全データを削除」で消える。部屋の通信はリアルタイムに転送するだけで、保存・ログ出力しない。
解析・広告・トラッキングの SDK は無く、ATT のダイアログも出さない。中継の通信は iOS の TLS、同じ Wi-Fi の通信は暗号化しない TCP。独自の暗号化は無い。

**対応機種**
iPhone のみ、横画面、iOS 18 以降。

## 記載の根拠

| 記載 | 根拠 |
|---|---|
| ひとりで遊ぶモードは通信不要 | 対 AI の試合は端末内の決定論シミュレーション（VelstriaCore）。通信はオンライン機能（`FeatureFlags.lanMatch == true`）と StoreKit だけ |
| オンライン対戦の仕組み | ARCHITECTURE.md「オンライン対戦」、App/Online（`OnlineSession` のホスト権威の入力ロックステップ、`OnlineTransport` の LAN・Bonjour、`OnlineRelay` の中継）、relay/README.md |
| 13 歳未満・ルールへの同意 | `OnlineAccess`（App/Online/OnlineSafety.swift。.under13 と未申告は .ageRestricted、同意の版は `FeatureFlags.currentOnlineRulesVersion`） |
| 名前のフィルタ | `ContentFilter`・`PlayerNameRules.validate` / `sanitizedRemote` / `sanitizedRoomName` |
| 通報・ブロック・部屋から外す | `PlayerReportMail`、`FriendHub.block`、`OnlineSession.kick`、Screens/Online/OnlineSafetyViews.swift、PrivacySettingsView |
| 年齢区分と月間上限 | DESIGN.md §12、`AgeBracket.monthlySpendLimitJPY`（13 歳未満・13〜15 歳 5,000 円、16〜19 歳 10,000 円） |
| 初回起動の順序・導線 | `OnboardingFlowView`（年齢 → 規約 → 名前 → 初回準備 → チュートリアル）、`HomeView`、`MatchFlowView`、`StoreHomeView`、`SettingsView` / `SupportView` / `StarPassView` |
| ランク戦のドラフト（BAN なし） | fb7f05d（BAN の機能を削除） |
| ヒーローは全員が使え、販売しない | fb7f05d（`AppModel.owns` / `EconomyService.isOwned`、ストアでヒーロー解放を売らない） |
| 課金 7 商品 | DESIGN.md §13、`StoreKitService.gemProducts` / `premiumPassProductID`、[in_app_purchases.md](in_app_purchases.md) |
| 見た目のみ・戦闘力なし | マスターの `competitive_power = 0`、game_rules `monetization` |
| 中継の保存 | relay/src/index.ts（部屋: 採番だけ、10 分で削除）、relay/src/inbox.ts（鍵のハッシュ・最後に接続した日時、預かり最大 20 件・14 日、消去 `POST /v1/inbox/<コード>/erase`、1 年で自動の消去、利用停止 `SUSPENDED_FRIEND_CODES`）、wrangler.jsonc（observability 無効） |
| 通報への対応 | /safety 第 4 節（受付から 2 営業日以内に確認を始める）、措置は relay/README.md「受信箱」の利用停止 |
| 暗号 | `URLSessionWebSocketTask`（wss、OS の TLS）、LAN は `NWParameters(tls: nil)`、CryptoKit は TesterAccess の SHA-256 だけ（compliance.md） |

## 提出前に決めること

- **2 台目の用意**: 「審査の連絡先から知らせてもらえれば当方の端末から参加する」は運用の約束。審査期間中に応じられる担当と端末を用意できない場合は、この一文を消し、
  代わりに 2 台で操作したデモ動画の URL を載せる（App Review は動画のリンクを受け付ける）。
- **中継の稼働**: 審査中は中継（wss://velstria-relay…workers.dev）を止めない・配備しない（配備すると接続中の WebSocket が切れる）。Workers Free の上限も確認する。
- **安全対策の実装**: 上の「安全対策」は App 側で作業中の実装が前提。提出ビルドで照合する。
- **通報への対応の体制**: 「2 営業日以内に確認を始める」を回せる担当者と代わりの担当者を決める。違反を確かめたら、中継の秘密
  `SUSPENDED_FRIEND_CODES` にフレンドコードを足して `npx wrangler secret put SUSPENDED_FRIEND_CODES` で反映する（relay/README.md）。
- **中継の配備**: 受信箱の消去・1 年の自動消去・利用停止は relay/ の新しい版が前提。審査に出す前に配備し、`npm run test:deployed` を通す。
