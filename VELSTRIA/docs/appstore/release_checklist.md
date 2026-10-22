# リリース判定チェックリスト（v1.0）

仕様書（`VELSTRIA_要件定義書_復元版` §164「リリース判定チェックリスト」）の 3 項目を、
v1.0 の範囲（対 AI のモードと、オンライン対戦〈部屋コード・同じ Wi-Fi〉・フレンド。`FeatureFlags.lanMatch == true`）に対応付けて具体化したもの。
すべてにチェックが付くまで審査に提出しない。

> §164 原文
> 1. P0/P1 クラッシュ 0 件、課金二重付与 0 件、精算冪等性確認。
> 2. 主要端末 fps/メモリ/熱検証、再接続、通報、返金、ストア審査を完了。
> 3. 全 Must 要件と受入テストをトレーサビリティ表で確認。

## 1. 品質ゲート（§164-1）

### クラッシュ 0 件
- [ ] コア: `cd Packages/VelstriaCore && swift test` と `swift test -c release` が全件成功（決定論・長時間シミュレーション含む）。
- [ ] アプリ: `xcodebuild test`（VELSTRIATests / VELSTRIAUITests）が全件成功。`AppStoreAssetsTests` を含む。
- [ ] ヘッドレス AI 対戦を 100 試合以上（Easy/Normal/Hard・出している全 10 ヒーロー〈`HeroRoster.activeHeroIDs`〉）回してクラッシュ・無限ループ・試合が終わらない事象 0 件。
- [ ] TestFlight 内部テスト 7 日以上、ASC / Xcode Organizer のクラッシュ 0 件（P0 = 起動・対戦中・購入時、P1 = その他画面）。
- [ ] 中断耐性: 対戦中のバックグラウンド移行・着信・通知センター・低電力モード・画面ロックから復帰して継続できる。

### 課金二重付与 0 件・精算の冪等性
- [ ] 同一 `Transaction.id` の再配信（起動時 `Transaction.unfinished` / `Transaction.updates`）で二重付与しない（`purchaseLedger`）。
- [ ] 購入シート表示中のアプリ強制終了 → 再起動で 1 回だけ付与される。
- [ ] 検証失敗（`VerificationResult.unverified`）のトランザクションは付与しない。
- [ ] 有償ジェムより無償ジェムを先に消費する（DESIGN §13）。
- [ ] 試合報酬の精算（`RewardService.apply`）は 1 試合 1 回だけ（リザルト画面の再表示・アプリ再起動で重複しない）。
- [ ] 年齢区分別の月間上限（15 歳以下 5,000 円 / 16〜19 歳 10,000 円）を超える購入がブロックされる。
      設定 > プライバシー > すべてのデータを削除（または再インストール）の後も、同じ Apple Account の当月購入分が
      購入履歴（`Transaction.all`）から数えられ、上限が戻らないこと。
- [ ] 手順は [in_app_purchases.md](in_app_purchases.md)「Sandbox での確認手順」。

## 2. 端末・運用検証（§164-2）

### fps / メモリ / 熱
| 端末 | 目標 | 結果 |
|---|---|---|
| iPhone 17 Pro Max（最新・6.9"） | 60fps 維持、メモリ < 1.2GB | [ ] |
| iPhone 16e（6.1"・A18） | 60fps 維持 | [ ] |
| iOS 18 対応の最古クラス（iPhone XS / XR 相当・A12） | 低画質で 30fps 以上、クラッシュなし | [ ] |
- [ ] Instruments（Time Profiler / Allocations / Leaks）で 1 試合（15 分）通しの計測。シミュレーション 1 tick < 1ms（Release・ARCHITECTURE.md 性能予算）。
- [ ] 15 分連続プレイで熱状態が `.serious` に達しない、または達したら画質を自動で下げる。
- [ ] 戦闘中のシェーダーコンパイルによるカクつきがない（初回試合で確認）。

### 再接続・通報（v1.0 の扱い）
- [ ] 再接続（対 AI）: 「中断からの復帰」（上記）と「機内モードで対 AI の全機能が動く」ことを確認する。
- [ ] 再接続（オンライン）: 2 台で、参加者の回線の切り替え（Wi-Fi ⇄ モバイル）・バックグラウンド移行から同じ席に戻れる。ホストが切れた時は試合が終わり、
      参加者に分かる表示が出る。中継の配備（`wrangler deploy`）で接続が切れた時も同様。
- [ ] 通報: 下の「オンライン機能（ガイドライン 1.2）」をすべて満たす。

### オンライン機能（ガイドライン 1.2・5.1）
- [ ] オンラインを初めて開くと「オンラインのルール」（コミュニティガイドラインと利用規約への同意）が出て、同意するまでフレンドの受信箱へ繋がない。
- [ ] 13 歳未満の年齢区分ではオンライン機能を使えない（ホームの「オンライン」から先へ進めず、受信箱へ繋がない）。
- [ ] 表示名の入力で不適切な語・連絡先を弾く。改変したクライアントからの名前・部屋名を受け取った側でも隠す。
- [ ] 通報: パーティの枠・参加者の一覧・フレンド・申請・招待・試合結果から、相手（表示名・フレンドコード・プレイヤー ID・部屋コード）を指定して通報できる。
- [ ] ブロック: 申請・招待が届かず、自分がホストの部屋に入れない。設定 > プライバシー で解除できる。ホストは参加者を部屋から外せる。
- [ ] 設定 > プライバシー の「オンライン機能をやめる」で受信箱への接続が止まる。
- [ ] 設定 > プライバシー の「フレンドサーバーのデータを削除」と「全データを削除」で、中継の受信箱が消える（`POST /v1/inbox/<コード>/erase`。
      以後そのコードは 4014 で繋げず、アプリは新しいフレンドコードを作る）。通信できない時は「全データを削除」が端末だけ消すかを聞く。
- [ ] 通報の受付体制: info@btcpay.jp の担当者と代わりの担当者を決め、/safety と review_notes.md に書いた目安（受付から 2 営業日以内に確認を始める）で回せる。
- [ ] 措置の手段: 違反を確かめたフレンドコードを中継の秘密 `SUSPENDED_FRIEND_CODES` に足して `wrangler secret put` で反映できる（relay/README.md「受信箱」）。
      止めたコード・理由・日時・通報の記録を社内で管理する場所を決めた。不適切語の表（`ContentFilter`）の更新はアプリの更新で配る。
- [ ] 中継（relay/）の受信箱の消去・1 年の自動消去・利用停止の版を配備した（`npm run test:deployed` が通る）。配備前のアプリ・サイトの文言と食い違わない。
- [ ] 公開版に開発中の文言が残っていない（OnlineLobbyView「開発中の機能です」「開発中は未所持のヒーローも選べます」等。ガイドライン 2.2）。
- [ ] `NSLocalNetworkUsageDescription` に英語版がある（InfoPlist.strings）。
- [ ] `PrivacyInfo.xcprivacy` の `NSPrivacyCollectedDataTypes` が [app_privacy.md](app_privacy.md) の申告（ユーザ ID）と一致する。

### 中継サーバー（relay/）
- [ ] 配備済みの中継（`OnlineRelayConfig.defaultBaseURL`）の `/v1/health` が 200 `{"ok":true,"relay":1}`、受信箱（`/v1/inbox/…`）が 426 を返す。
- [ ] アプリの `rv` と中継の `RELAY_VERSION` が一致する（`npm run test:deployed` が通る）。
- [ ] Workers の料金プランと 1 日の上限（Free は 10 万リクエスト。10 人の対戦は全部屋の合計 1 日 1 時間前後で届く見込み）。公開時は Paid にするか、上限の監視を用意する。
- [ ] Cloudflare のアカウントの名義（現状は個人アカウントの workers.dev のサブドメイン）と、ホスト名に内部名（velstria）が出ることの扱いを決める。
- [ ] 審査期間中は配備しない（配備すると接続中の WebSocket が全部切れる）。

### 返金
- [ ] Xcode の StoreKit テストで返金 → `Transaction.updates` の `revocationDate` を検知し、有償ジェムを減算（不足時はマイナス残高または購入制限）する。
- [ ] 非消耗型（スターパス プレミアム）の返金でプレミアム報酬の受け取り権が失効する。
- [ ] 利用者向けの返金案内（Apple の「問題を報告する」）がサポート画面・利用規約にある。

### ストア審査
- [ ] `python3 tools/validate_appstore_metadata.py --release` がエラー 0（プレースホルダ・仮 URL なし。アプリ内の `StoreLegalText`・`FeatureFlags` も対象）。
- [ ] `python3 tools/gen_master_en.py --check` / `python3 tools/gen_master_ja.py --check` / `python3 tools/privacy_audit.py` が成功。
- [ ] プライバシーポリシー・利用規約・サポートの URL を公開し、アプリ内リンク（`FeatureFlags`）と ASC の URL が一致して開ける。
- [ ] 公開サイト（site/）を `onlineMatch: true` でビルド・配備し、/legal（一覧）、/community、/safety、/privacy-choices、/external-transmission、/licenses、/parents と
      各 /en/… が開ける（アプリの `FeatureFlags` が開く /community・/safety・/privacy-choices・/external-transmission・/legal・/licenses を含む。
      `node build.mjs` が内部リンクと `FeatureFlags.swift` の URL を照合する）。
- [ ] 公開後: トップ（/、/en）に App Store の製品ページへのリンクを置き、「App Store 公開準備中」の表示とプレスキットの「リリース状況」を直す。
- [ ] ASC の「ユーザーのプライバシー選択 URL」に `metadata/<locale>/privacy_choices_url.txt` を手入力した（`tools/asc.mjs` は送らない）。
- [ ] 特定商取引法に基づく表記・資金決済法に基づく表示を Web とアプリ内（ストア画面から 1 タップ）に掲載。
- [ ] 審査メモの導線（ホーム > 対戦開始、ホーム > ストア > Gem を購入 等）を最終ビルドで照合し、[review_notes.md](review_notes.md) と notes.txt を更新。
- [ ] 7 つの App 内課金を ASC に登録（審査用スクリーンショット付き）し、バージョンに追加。
- [ ] スクリーンショット 6.9 インチ × 日英（[screenshots.md](screenshots.md) の確認事項を満たす）。
- [ ] 年齢制限の回答（[age_rating.md](age_rating.md)。UGC・メッセージとチャットは「はい」、暴力の回答で 9+ か 13+）、栄養ラベル「ユーザ ID を収集」（[app_privacy.md](app_privacy.md)）。
- [ ] 米国の州の年齢確認法（テキサス州 SB 2420・ユタ州・ルイジアナ州の App Store Accountability Act など）への対応方針を決めた:
      Declared Age Range API・Significant Change API（PermissionKit）・StoreKit の `ageRatingCode`・App Store Server Notifications の
      `RESCIND_CONSENT` を実装するか、その州を配信地域から外すか、弁護士に確認する（[compliance.md](compliance.md)「要判断」）。
- [ ] iPad（iPhone 互換モード）でも起動・操作・購入ができる。
- [ ] 英語表示で日本語が残っていない（マスター名は `master_en.json`、UI 文言は `L("…", "…")`）。
- [ ] 日本語表示で有料コスメ・ストア商品がテンプレート名（「… Emote 1」「… HeroSkin 1」）で出ない（`master_ja.json`）。
- [ ] 戦闘描画に流血・写実的表現がない（年齢制限の前提）。
- [ ] `TEAM_ID=… STRICT=1 tools/archive.sh` → Organizer で Validate App 成功 → アップロード。

## 3. トレーサビリティ（§164-3）

仕様の Must 要件は 80 件（44 モジュール × Must 1〜2 件）、受入テストは 31 件（AT-001〜031）。
v1.0 は対 AI のモードに、オンライン対戦（リッスンサーバー: 部屋コード・同じ Wi-Fi）とフレンドを加えた範囲。
アカウント・サーバーでの照合などを前提にする要件は「対象外（Phase 2）」として明示的に除外し、残りを実装・テストに対応付ける。担当の列は ARCHITECTURE.md の担当範囲。

### モジュール別（Must 要件）
| モジュール | Must 要件 | v1.0 | 担当 / 検証 |
|---|---|---|---|
| MOD01 認証 / MOD02 アカウント | FR-001,045 / FR-002,046 | 端末内プロフィール + バックアップ書き出し（アカウント連携は Phase 2） | ui-flow・app-services / バックアップ復元テスト |
| MOD03 パッチ配信 / MOD04 アセットDL | FR-003,047 / FR-004,048 | 対象外（全アセット同梱。更新は App Store 経由） | — |
| MOD05 ホーム / MOD06 通知 | FR-005,049 / FR-006,050 | ホーム・お知らせ（端末内） | ui-flow・ui-liveops |
| MOD07 フレンド / MOD09 パーティ | FR-007,051 / FR-009,053 | フレンドコードの受信箱（中継）・申請・在席・招待、パーティ（`FeatureFlags.lanMatch`） | online / FriendTests・OnlineSessionTests、relay の結合テスト、2 台の実機 |
| MOD08 チャット | FR-008,052 | 対象外（自由入力のチャットは無い。シグナル・定型文は自分の端末に表示するだけ） | — |
| MOD10 マッチメイク / MOD12 ドラフト | FR-010,054 / FR-012,056 | 対 AI マッチ生成（MatchFactory）・ピックのドラフト（BAN は 2026-10-12 に廃止） | core-bots・ui-flow |
| MOD11 ランク | FR-011,055 | ローカルラダー（隕鉄〜星環王） | app-services（RankService） |
| MOD13〜MOD16 ヒーロー/装備/エンブレム（旧ルーン）/スペル | FR-013〜016, 057〜060 | 10（H025〜H034。データは 34 体分を残す）/ 92 / 7 セット・天賦 26 / 15 | ui-collection・core-* / `AppStoreAssetsTests`（英語網羅） |
| MOD17〜MOD30 戦闘系 | FR-017〜030, 061〜074 | 決定論シミュレーション | core-combat・core-world・core-economy・core-skills・battle / VelstriaCore テスト |
| MOD31 スコア / MOD34 リザルト | FR-031,075 / FR-034,078 | MVP スコア・評価・報酬精算 | core-economy・app-services |
| MOD32 降参 | FR-032,076 | AI 投票（DESIGN §3） | core-economy |
| MOD33 切断再接続 | FR-033,077 | 対 AI は中断からの復帰。オンラインは同じプレイヤー ID で同じ席へ戻る（ホストの離脱は試合終了） | battle・online / 中断耐性テスト、OnlineSessionTests、2 台の実機 |
| MOD35 リプレイ / MOD36 観戦 | FR-035,079 / FR-036,080 | 入力記録リプレイ・AI 同士観戦 | core-economy・battle |
| MOD37 ストア / MOD38 課金照合 | FR-037 / FR-038 | StoreKit 2 端末内検証・冪等台帳 | app-services・ui-collection / Sandbox テスト |
| MOD39 イベント / MOD40 ミッション | FR-039 / FR-040 | 端末内スケジュール・デイリー | ui-liveops・app-services |
| MOD41 通報 | FR-041 | 相手を指定した通報（運営宛てのメールの下書き）・ブロック・部屋から外す・名前のフィルタ | online / OnlineSafetyTests、運営の受付体制（上の「オンライン機能」） |
| MOD42 不正対策 | FR-042 | 端末内（課金は StoreKit の署名検証、決定論リプレイで結果再現） | app-services |
| MOD43 分析 | FR-043 | 対象外（解析のためのデータは収集しない方針。栄養ラベルの収集はフレンド機能のユーザ ID だけ） | — |
| MOD44 運営管理 | FR-044 | 対象外（サーバーなし） | — |

### 受入テスト（AT-001〜031）
| 区分 | テスト ID（領域） | v1.0 での確認方法 |
|---|---|---|
| 対象（戦闘） | AT-003 視界, AT-004 リスポーン, AT-009 スキル, AT-010 ゴールド, AT-015 移動, AT-016 タワー, AT-017 降参, AT-021 スペル, AT-022 ミニオン, AT-023 ショップ戦闘, AT-027 装備, AT-028 当たり判定, AT-029 経験値 | VelstriaCore の単体・長時間テスト + 実機プレイ。「通信断/復帰」は「バックグラウンド移行/復帰」に読み替える |
| 対象（メタ） | AT-002 エンブレム（旧ルーン）, AT-008 ヒーロー, AT-011 リザルト, AT-014 ランク, AT-018 イベント, AT-024 ストア, AT-030 リプレイ, AT-005 観戦, AT-019 アカウント（端末内・バックアップ） | アプリの単体/UI テスト + 実機。二重付与・不整合がないこと |
| 対象（通知） | AT-007 通知 | ローカル通知のみ（許可ダイアログ拒否時も動作） |
| 対象（オンライン） | AT-012 通報, AT-020 パーティ, AT-026 フレンド | 2 台の実機（部屋コード・同じ Wi-Fi）と単体テスト。通報はメールの下書きの内容、ブロック・部屋から外すの効果を確認 |
| 対象外（Phase 2） | AT-001 チャット, AT-006 分析, AT-013 アセットDL, AT-025 運営管理, AT-031 不正対策（サーバー検証） | v1.0 に機能が無いことを UI テストで確認（導線非表示） |

- [ ] 上表の「対象」がすべて合格、「対象外」は機能が露出していないことを確認した。
- [ ] Should / Could 要件（30 件）の未実装分をリリースノートの既知の制限または次期計画に記録した。

## 4. 公開後

- [ ] 段階的リリース（7 日）で公開し、クラッシュ率・評価を毎日確認（問題があれば一時停止）。
- [ ] 返金・問い合わせの窓口（`FeatureFlags.supportEmail`）の受付体制。
- [ ] 資金決済法: 基準日（3/31・9/30）の有償ジェム未使用残高を算定し、1,000 万円を超えたら 2 か月以内に届出（[payment_services_act_ja.md](../legal/payment_services_act_ja.md)）。
