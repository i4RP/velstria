# VELSIA iOS アーキテクチャ・開発ルール

## 構成
```
VELSTRIA/
  project.yml                      xcodegen 定義（.xcodeproj は生成物・git 管理外）
  Packages/VelstriaCore/           決定論シミュレーション（純 Swift、macOS で swift test 可）
    Sources/VelstriaCore/
      Math/        Vec2, Rect2, SplitMix64
      Data/        MasterData（master_runtime.json の Codable モデル）
      Sim/         型・状態・イベント・コマンド・Simulation（tick 順序）・マップ・ナビ・リザルト・リプレイ
      Systems/     各システム（enum + static func (_ s: inout SimState, _ ctx: SimContext)）
      Resources/   master_runtime.json（tools/gen_runtime_data.py で生成）
    Tests/VelstriaCoreTests/
  App/                             iOS アプリ（SwiftUI + RealityKit + StoreKit 2）
    VelstriaApp.swift              エントリ・RootView・BattleSessionView（ロード→戦闘→リザルト）
    Core/                          契約: AppModel, Profile, Routing, Theme, Localization, FeatureFlags, DebugLaunch
    Services/                      永続化・報酬・経済・ライブオプス・ランク・StoreKit・音・触覚
    Battle/                        戦闘描画（RealityKit）+ HUD（Wave 2）
    Screens/<Area>/                画面実装
    Resources/                     Assets.xcassets, Velstria.storekit, PrivacyInfo.xcprivacy, master_en.json, master_ja.json
  AppTests/  AppUITests/
  docs/  DESIGN.md（ゲーム数値の正本） ARCHITECTURE.md（本書）
  tools/
    portraits/                     ヒーロー / スキンのポートレートと装備アイコンの画像の生成仕様と取り込み（下記）
```
- 最低 iOS 18.0、iPhone のみ、横画面固定、Swift 5 言語モード（Swift 6.2 コンパイラ）。
- ヒーロー（24）とヒーロースキン（12）のポートレートは描き下ろしの生成画像。仕様（画風・造形）は
  `tools/portraits/portraits.json`（造形は `HeroBlueprints.swift` の 3D モデルに合わせる）、生成と取り込みは
  `tools/portraits/portraits.py`（Codex CLI の画像生成 → `build/portraits/` に原寸 → `install` で 640px JPEG を
  `Assets.xcassets/HeroPortraits`・`SkinPortraits` へ）。表示は `HeroPortraitView` / `SkinPortraitView`（`PortraitArt`）。
  ヒーローやスキンを追加したら仕様に追記して生成・取り込みする（`AppStoreAssetsTests` が欠けを検出）。
- 装備（72）のアイコンも装備毎の描き下ろしの生成画像。仕様は `tools/portraits/item_icons.json`（画風、Tier 別の格、
  カテゴリ別の色、装備毎の造形。同名の装備も番号毎に別の造形）、`portraits.py install items` で 384px JPEG を
  `Assets.xcassets/ItemIcons` へ。表示は `ItemIconView`（絵柄の上に Tier の枠と印を重ねる。アートの無い ID は
  カテゴリの色と記号の手続き生成にフォールバック）。装備を追加したら仕様に追記して生成・取り込みする。
- 仕様パッケージ `../VELSTRIA_復元版パッケージ/` がコンテンツ正本。`docs/DESIGN.md` がルール・数値の正本。

## シミュレーション（VelstriaCore）
- `Simulation.step(commands:)` が 1 tick（1/30 秒）進める。システム呼び出し順は `Sim/Simulation.swift` を参照。
- 人間も AI も `HeroCommand` を発行し、同じ経路で処理される（将来のサーバー権威化の前提）。
- 描画・HUD・音は `SimEvent`（step の戻り値）と `SimState` の読み取りのみで動く。sim を直接書き換えない。
- 状態は値型 `SimState`。システムは `inout SimState` を受け取る。units の添字は tick 内で安定（除去は tick 末尾）。

### 決定論ルール（必須）
1. `Dictionary` / `Set` を **列挙しない**（lookup は可）。列挙は配列・ID 昇順で行う。
2. 乱数は `state.rng`（SplitMix64）のみ。`Double.random` / `Int.random` / `shuffled()` / `Date()` 禁止。
3. 並行処理でシミュレーションを分割しない。
4. `Simulation` の同一 config・同一入力は同一結果（`ContractSmokeTests` で検証）。

### 性能予算
- Release ビルドで 1 tick（10 ヒーロー + ミニオン 60 + モンスター 20）あたり 1ms 未満（M 系 Mac）を目安。
- O(n²) の全探索は tick あたり数回まで。多用する場合は空間ハッシュを導入する。

## 担当範囲（Wave 1）
他担当のファイルは **編集禁止**。必要な変更は `notes_for_integration` に書いて報告する。
新規ファイルは自分のフォルダ/接頭辞で作る（例: `Systems/CombatHelpers.swift`, `Tests/.../CombatTests.swift`）。

| 担当 | 所有ファイル |
|---|---|
| core-combat | Systems/CombatSystem, StatusSystem, MovementSystem, ProjectileSystem, ZoneSystem（+ `Combat*` 新規） |
| core-world | Sim/MapDefinition, Sim/NavGrid, Systems/SpawnSystem, MinionSystem, TowerSystem, MonsterSystem, VisionSystem（+ `World*` 新規） |
| core-economy | Systems/HeroGrowth, ItemSystem, EconomySystem, DeathSystem, RespawnSystem, RecallSystem, MatchFlowSystem, Sim/MatchSummary, Sim/Replay（+ `Economy*` 新規） |
| core-skills (Wave 2) | Systems/SkillSystem, SpellSystem（+ `Skill*` 新規） |
| core-bots (Wave 2) | Systems/BotAI（+ `Bot*` 新規）、MatchFactory の改善 |
| app-services | App/Services/*, App/Resources/Velstria.storekit, AppTests/Services* |
| ui-flow | App/Screens/Flow/* |
| ui-collection | App/Screens/Collection/*, App/Screens/Store/* |
| ui-liveops | App/Screens/LiveOps/*, App/Screens/Settings/* |
| appstore-assets | project.yml, App/Resources/Assets.xcassets, PrivacyInfo.xcprivacy, master_en.json, master_ja.json, docs/APPSTORE*, docs/legal/*, tools/*（gen_runtime_data.py 以外） |
| battle (Wave 2) | App/Battle/* |
| 統合（契約） | Sim/Types, Balance, Stats, Unit, Effects, Commands, Events, MatchConfig, SimState, SimContext, Simulation, MatchFactory, Systems/CommandSystem, StatCalculator, App/Core/*, App/VelstriaApp.swift |

- 契約ファイルの公開 API（型名・シグネチャ）は変更しない。フィールド追加が必要なら報告する。
- `Balance` の追加定数は自分のファイル内で `extension Balance { static let ... }`。
- `PassiveHooks`（SkillSystem.swift 内）は core-skills が実装するが、core-combat は所定の箇所から呼び出すこと。

## アプリ（UI）ルール
- 文字列は `L("日本語", "English")`。マスター名は `MasterText.hero(def)` 等。
- 背景 `StarfieldBackground`、push 画面は `ScreenScaffold(title:)`、ボタンは `PrimaryButtonStyle` / `SecondaryButtonStyle`、枠は `Panel`。
- 横画面（iPhone 16e〜17 Pro Max）で崩れないこと。Dynamic Island / ホームインジケータの safe area を尊重。
- タップ可能要素には `accessibilityIdentifier`（UI テスト用、例 `home_play`）と VoiceOver ラベル。
- 色だけに依存しない（ロールは `Theme.roleSymbol`、チームは形/ラベルでも区別）。
- 画面遷移: `app.router.push(.heroes)`、対戦フロー `app.router.isMatchFlowPresented = true`、戦闘 `app.startBattle(BattleLaunch(...))`。
- プロフィール変更は `app.profile.xxx = ...`（自動保存）。ロジックは Services 側の関数を使う。
- 通常プレイはネットワーク通信なし（オフライン完結）。外部リンクは `Link` / `openURL`。
  例外はオンライン対戦（下記。同一 LAN の端末間通信と、部屋コードで遊ぶ時だけ中継サーバー（Cloudflare Workers）経由の通信）。

## オンライン対戦（リッスンサーバー方式、開発期間用）
`FeatureFlags.lanMatch` で有効。参加者の 1 台が **ホスト**（権威シミュレーション）になり、他は **クライアント**として入力を送る。
同一 LAN の部屋を Bonjour（`_velstria._tcp`）で探すか、ホストの IP:ポート（既定 47814）を入力して TCP で繋ぐ。
違う場所・違う Wi-Fi / モバイル回線の相手とは **部屋コード**（中継サーバー経由。下の「インターネット対戦（中継）」）で繋ぐ。
どちらの経路でもホストの端末が権威シミュレーションを回すのは同じ（中継は中身を解釈しない土管）。
Info.plist に `NSLocalNetworkUsageDescription` / `NSBonjourServices` と、招待リンク用の URL スキーム `velstria` が必要（project.yml に定義）。

```
App/Online/
  OnlineProtocol.swift   メッセージ（OnlineMessage）・部屋モデル（OnlineRoom / OnlineSeat / OnlineLoadout）・長さ区切り JSON の符号化（OnlineFramer）
  OnlineTransport.swift  接続の抽象（OnlineConnection）。LoopbackConnection（テスト）、NWOnlineConnection / NWOnlineListener / NWOnlineBrowser（Network.framework）
  OnlineSession.swift    部屋への参加状態（ホスト or クライアント）。ロビー操作、戦闘中の入力中継、ハッシュ照合、再同期、切断 → AI 引き継ぎ、再接続
  OnlineRelay.swift      インターネット対戦の中継（部屋コード・招待リンク・中継の形式・WebSocket・RelayHostLink / RelayGuestEndpoint / RelayGuestConnection）
App/Screens/Online/OnlineLobbyView.swift  入口（部屋を作る / 部屋コードで参加 / 同じ Wi-Fi の部屋を探す / アドレス入力）と部屋（部屋コードの共有・座席・ピック・準備完了・開始）
relay/                   中継サーバー（Cloudflare Workers + Durable Objects、TypeScript。リポジトリ直下。relay/README.md）
Packages/VelstriaCore/Sources/VelstriaCore/Sim/MatchFactoryOnline.swift  複数人間の 5v5 構成（`MatchFactory.onlineMatch`、座席番号 = players の添字）
```

同期の仕組み（決定論シミュレーションの入力同期。AI は両側で同じ計算をするので送らない）:
1. ロビー: ホストが `OnlineRoom` の正本を持ち、変化のたびに全体を配る。座席（Blue 5 / Red 5）に着いた人間がピックして準備完了、ホストが開始。
   `OnlineRoom.makeConfig` が `MatchFactory.onlineMatch` で `MatchConfig`（`mode: .online`）を作り、全員に同じ構成が届く。
   自分の座席番号は `BattleLaunch.onlineSeat`（= `config.players` の添字）。`BattleController.localHeroID` はそこから決まり、
   `humanHeroID` / `localTeam` / `viewerTeam`（霧の視点）は自分の座席のもの（Red 側のこともある。カメラは回転しない）。
2. 読み込み: 各クライアントは戦闘画面で `OnlineSession.attach` → `.loaded` を送る。ホストは座っている全員の `loaded`（または 90 秒）を待ってから進め始める。
   一度進め始めたら以後は待たない。遅れて `loaded` が届いた参加者（時間切れ後の読み込み・再接続）には現在の `SimState` スナップショットを渡す。
3. 戦闘: ホストは `自分の入力 + 届いたクライアント入力（+ 操作者切り替え）` で `Simulation.step` し、その tick に適用した入力列を
   `ReplayFrame` として全員へ配る（空の tick も送る。クライアントの時計になる）。描画フレームの終わりにまとめて 1 メッセージで送る。
   クライアントは入力をホストへ送るだけで自分では適用せず、届いた tick の入力で step する（遅れて再生。届かなければ補間係数 1 で待ち、
   `onlineJitterBuffer` tick より溜まれば時計を待たずに進め、`onlineCatchUpThreshold` より溜まれば早送りで追いつく）。
   クライアントは他人のヒーローを操作できない（ホストが座席のヒーロー ID で検証し、`setController` は捨てる）。
4. 検証と再同期: クライアントは `OnlineProtocol.hashInterval`（30 tick）毎に `SimState.stateHash()` を報告し、ホストは自分の記録と比べる。
   食い違えばホストの `SimState` スナップショット（Codable、約 200KB）を送り、クライアントは `Simulation.restore(from:)` で置き換えて
   それ以前の配信を捨てる。置き換えたクライアントの記録は自分の入力列から再現できないので、同じ tick への置き換えでもリプレイを保存しない。
5. 切断・離脱: 試合中にクライアントが落ちるとホストは `PlayerCommand.setController(.bot)` を発行して AI に引き継ぐ（座席は保つ）。
   同じ playerID で再接続すると構成 → 読み込み → スナップショット → `setController(.human)` で戻る（古い接続が残っていても置き換える）。
   試合が終わっても戻らなかった参加者は席を空ける。クライアントが自分で退出すると `.abandonMatch` を送り、ホストは AI に引き継ぐ（部屋には残る）。
   ホストが退出・中断すると `.matchAborted` を配り、クライアントは届いていた配信を消化してから中断終了する。ホストが落ちた（切断）時も同様に中断終了。
   ホスト（席に着いた選手・実況とも）の退出ボタンと確認は「全員の試合を終了」と明示する（`HUDLeaveKind.endsMatchForEveryone`。引き継ぎは無い）。
   生存確認: 双方が 2 秒毎に ping し、20 秒（`livenessTimeout`）何も届かない相手は切断扱い。接続は 15 秒で確立しなければ失敗にする。
6. 一時停止・バックグラウンド: オンライン中は `BattleController.isPaused` が常に false（メニューを開くだけで世界は止まらない）。
   ホストがバックグラウンドに入ると iOS がアプリを止めるので全員が止まり、20 秒を超えると参加者側は切断扱いになる（復帰したホストは AI 相手に続行）。
   クライアントがバックグラウンドに入ると復帰後に溜まった配信を早送りで消化する（長ければ切断 → AI 引き継ぎ）。
   `MatchMode.online` は報酬・ランク・戦績の対象外（`RewardService`）。降参投票は有効。
   配信は、座っていて抜けていないプレイヤーには即時、観戦席には遅延付きで送る（下の「観戦」→「オンラインの観戦席」）。
   プロトコルは v2（観戦の役割・観戦席の配信を追加）。v1 の名乗りは版数違いとして断る。

検証用の起動引数（Debug のみ）: `-onlineHost [port]`、`-onlineJoin <host:port>`、`-onlineAuto`（自動で着席・ピック・準備完了、ホストは揃えば開始）、
`-relayCode <CODE>`（ホストの部屋コードを固定）、`-onlineJoinCode <CODE>`（部屋コードで参加）、`-relayURL <ws(s)://…>`（中継の差し替え）。
2 台のシミュレータで `-onlineHost -onlineAuto` と `-onlineJoin 127.0.0.1:47814 -onlineAuto` を起動すると対戦が始まる（LAN）。
中継経由は `-onlineHost 47931 -relayCode QZ7K4P -onlineAuto` と `-onlineJoinCode QZ7K4P -onlineAuto`（配備済みの中継に繋ぐ）。
テスト: `OnlineCoreTests`（コア）、`OnlineProtocolTests` / `OnlineSessionTests`（ループバックでロビー → 同期 → 遅延 → 再同期 → 切断 → 再接続 →
離脱 → 中断 → 生存確認）/ `OnlineTransportTests`（localhost の TCP、接続失敗の時間切れ）/ `OnlineRelayTests`（中継の代役 `InMemoryRelay` で
部屋コード・形式・分割・ホストの再接続・コードの作り直し・close コードの文言・招待リンク）。CI（build-upload.yml）でも実行する。
中継サーバーのテストは `relay/test/relay.test.mjs`（wrangler dev 相手。`.github/workflows/relay.yml` が relay/ の変更時に実行）。

### インターネット対戦（中継）
違う場所・違う Wi-Fi・モバイル回線（CGNAT）の端末同士は直接 TCP で繋がらないので、ホストも参加者も中継サーバーへ **外向きに** WebSocket で繋ぐ。
中継（`wss://velstria-relay.shoei0205.workers.dev`、`OnlineRelayConfig.defaultBaseURL`）は Cloudflare Workers + Durable Object（部屋コード 1 つ = 1 オブジェクト、
WebSocket Hibernation）で、**中身を解釈しない土管**。ゲームの手順（`OnlineMessage` の長さ区切り JSON）はそのまま流すので、ホスト権威・入力ロックステップ・
ハッシュ照合・再同期・観戦席は LAN と全く同じに動く。何も保存せず、payload をログに出さない。

- 部屋コード: 6 文字（`ABCDEFGHJKMNPQRSTUVWXYZ23456789`。紛らわしい I L O 0 1 を除く）。ホストの端末が作る（`RelayRoomCode.generate`）。
  入力は全角・小文字・空白・ハイフンを正規化し、貼り付けた招待リンクからもコードを取り出す。紛らわしい文字は弾いて理由を出す。
- 接続: `GET /v1/rooms/<CODE>?role=host|guest&rv=1`（WebSocket）。ホスト ↔ 中継はバイナリの先頭 5 バイト `[種類][guestId u32 BE]`
  （0x10 GUEST_OPEN / 0x11 GUEST_DATA / 0x12 GUEST_CLOSE / 0x21 SEND / 0x22 KICK）、参加者 ↔ 中継は payload そのまま。
  1 メッセージ 256 KiB まで（アプリは 64 KiB 毎に分割。OnlineFramer がストリームとして再結合）。
- ホスト: `OnlineSession.startRelay` が `RelayHostLink` を開き、参加者ごとの仮想接続 `RelayGuestEndpoint` を `accept` に渡す（LAN の接続と同列）。
  中継が切れたら全仮想接続を切断扱いにして（試合中なら AI 引き継ぎ）、同じコードで指数バックオフの再接続。再接続には部屋ごとの鍵（`hk`、128 ビットの乱数。
  参加者には渡らない）を付け、中継がまだ前の（もう死んでいる）ホストの接続を握っていても、同じ鍵なら即座に入れ替わる（前の接続の参加者は host_left で閉じ、
  同じコードで入り直す）。鍵の無い古い中継では 4009 になり、コードが使われていたら作り直す。
  15 秒毎にテキスト `ping`（中継が `pong` を自動応答。携帯回線の NAT 対策）、50 秒何も届かなければ繋ぎ直す。
- 名乗らない接続: 部屋コードだけで誰でも繋げるので、受け入れてから 10 秒（`OnlineProtocol.handshakeTimeout`）名乗り（hello）が無い接続は切る。
  ホスト側で参加者から受け取る 1 メッセージは 1 MiB まで（`guestToHostMaxMessageBytes`。名乗る前に 32 MiB を持たされないため）。
- 信頼の範囲（開発期間）: 部屋コードを知っている人は信頼する。名乗りの peerID は認証されず（部屋の状態で全員に見える UUID）、悪意のある参加者が他人の peerID で
  名乗ると席を奪える。ホストが参加者を追い出す操作も無い。公開の対戦に広げる時は、再入室の秘密（hello に載せる乱数）とホストの追放を足すこと。
- 参加者: `RelayGuestConnection`（`OnlineConnection` 準拠）。切れた後は同じコードで「もう一度参加」（同じ playerID なので試合中なら席に戻る）。
  中継の close コード（4001 host_left / 4002 closed_by_host / 4004 no_room / 4008 room_full / 4009 room_taken / 4010 relay_version）は利用者向けの文言にする。
- 招待: 部屋の上の帯に部屋コード（タップで詳細）・コピー・共有（文面 + `velstria://join?code=XXXXXX`）。リンクを開くと `AppModel.openOnlineJoinLink` が参加する
  （`&spectate=1` で観戦席。試合中・初回設定前・参加者のいる自分の部屋がある時は理由を出して入らない）。
- プライバシー: 部屋コードで遊ぶ時だけ、対戦データ（操作・表示名・ピック等）が中継経由で相手の端末へ届く（`OnlineRelayConfig.privacyNote`、
  オンボーディング・設定 > プライバシー・FAQ・docs/legal に記載）。保存しないので App のプライバシーの「収集」には当たらない（docs/appstore/app_privacy.md）。
- 中継の配備: `cd relay && npx wrangler deploy`（手元の Cloudflare ログインで。CI からは配備しない）。版数を変える時は `rv` と `RelayRoomCode`/形式の両方を上げる。

### フレンドとパーティ
友達と一緒にチームを組んで遊ぶ（モバレジェ型: フレンドをパーティへ招待 → 招待された側が 拒否 / 待って / 同意）。`FeatureFlags.lanMatch` が有効な時だけ動く
（公開版では受信箱へ繋がず、画面・リンクも出ない）。アカウントは作らない。

- 識別: 端末ごとに **フレンドコード**（8 文字。公開の ID）と **受信箱の鍵**（本人だけの秘密）を `Profile.friendCode` / `inboxKey` に持つ。
  中継（`relay/src/inbox.ts` の `FriendInbox`。仕様は relay/README.md「フレンドの受信箱」）は、コードごとに最初に繋いだ鍵で持ち主を決める。
- 受信箱: `FriendInboxClient`（`RelaySocket` 上のテキスト JSON。繋ぎ直しは指数バックオフ。4012 コードが他で使用中 / 4010 版違いは諦める）。
  アプリが前面にいる間だけ繋ぐ（`VelstriaApp` の scenePhase。オンボーディング完了でも繋ぐ）。
- 状態と手順: `FriendHub`（`AppModel.friends`）。メッセージ `InboxPayload` は `friendRequest` / `friendAccept` / `partyInvite` / `inviteReply`。
  - 申請: コードかリンク（`velstria://friend?code=…&name=…`。`AppModel.openFriendLink` が招待リンクより先に判定）で申請 → 相手が承認すると相互にフレンド。
    お互いに申請していればすぐ成立。不在の相手には中継が預かる（繋いだ時に届く。返事待ちは繋がるたびに送り直す）。承認していない相手の `friendAccept` は無視する。
  - 招待: フレンドの一覧から招待（自分の部屋が無ければ `AppModel.hostPartyRoom` が作って先に座る）。部屋コードを相手の受信箱へ送る（預けない）。
    フレンドでない相手の招待は無視。受けた側は `PartyInviteOverlay`: 拒否（「5 分間このプレイヤーの招待を拒否」）/ 待って（30 秒後に参加）/ 同意。
    試合中は「試合中」と返して出さない。返事は招待した側のトーストに出る。
  - 参加: 同意で `AppModel.joinPartyRoom` が部屋コードで入り、`OnlineSession.seatsWithHostTeam` により **ホストと同じチームの空席に自動で座る**
    （`OnlineSession.partySeat`。ホストが未着席なら Blue、チームが満席なら他チーム）。残りの席は従来どおり AI。ヒーロー選択と準備完了は各自、開始はホスト。
- 在席: 繋がっている間 20 秒ごとにフレンドの在席を問い合わせる。
- 保存: `Profile.friends` / `outgoingFriendRequests`（`PersistenceService` の elementTemplates と sanitize に対応）。
- テスト: `FriendTests`（コード・リンク・符号化・受信箱への接続・申請/承認/招待の手順・パーティの席・保存の互換）、中継は `relay/test/relay.test.mjs`。
- 公開前の課題: ブロック・通報、表示名の不適切語対策、プライバシーの文言（フレンドコードと表示名が中継を通ること）、年齢区分。

## 観戦（AI 同士の観戦・リプレイ・オンラインの観戦席・死亡中の味方追従）
観戦者 = 操作を送らず、霧は観戦者が選んだ視点で見る人。`BattleLaunch.isSpectating` は次のどれか:
AI 同士の観戦（`mode == .spectate`）、リプレイ（`replay != nil`）、オンラインの観戦席（`onlineSpectator`）、人間のいないオフライン構成（`isAllBotsOffline`）。
観戦は報酬・ランク・戦績の対象外。観戦者の状態（視界・カメラ・シーク・自動カメラ・HUD）は **SimState に入れない**。

```
App/Battle/BattleController.swift   観戦の契約: spectatorVision / spectatorDirectorEnabled / presentationEpoch / requestSeek / stepTicks /
                                     keyframes / 年表（timeline・knownTimeline・displayTimeline）/ cameraZoomOverride / presentationFocusID
App/Battle/ReplayBaker.swift         シークできる観戦のバックグラウンド事前計算（別 Simulation）と、シーク用ワーカー
App/Battle/Render/CameraDirector.swift  自動カメラ（見どころの採点と画の切り替え。描画専用の購読者）
App/Battle/Render/CameraRig.swift    観戦の倍率範囲・自由カメラの直接操作・複数対象の画角合わせ・切り替え（グライド / カット）
App/Battle/Render/FogOfWar.swift     観戦者の視界切り替え（全体 / Blue / Red）。観戦では常に作っておき、全体表示の時は無効
App/Battle/HUD/HUDSpectate.swift ほか 観戦ドック（HUDSpectate）・再生バー（HUDReplayTransport）・情報パネル（HUDSpectatorPanels / HUDGoldGraph）・
                                     画面操作（HUDSpectatorGestures）・観戦の UI 状態（HUDSpectatorState）
App/Services/ReplayArchiveService.swift  報酬の無い試合のリプレイ保存・取り込みの検証・共有
App/Online/OnlineSpectatorRelay.swift    オンラインの観戦席への遅延配信（ホスト側）
Packages/VelstriaCore/Sources/VelstriaCore/Sim/ReplayTimeline.swift     年表（キル・構造物・目標・全滅・終了、チームのゴールド/経験値サンプル）
Packages/VelstriaCore/Sources/VelstriaCore/Sim/MatchFactorySpectate.swift 観戦の構成（側ごとの難易度・枠ごとのヒーロー・標準 / 乱闘マップ）
```

### シークと事前計算
- シークできるのはオフラインの観戦とリプレイ（`BattleController.isSeekable`）。`requestSeek(toTick:)` は、目標以前で最も新しいキーフレーム
  （`keyframeInterval` = 900 tick = 30 秒毎、試合開始時を含む）から **イベントを配らずに** 再シミュレーションする。シーク中（`seekingToTick != nil`）は
  `frame(dt:)` で進めない。終わったら `presentationEpoch` を増やし、描画（`BattleWorld.resetForPresentationEpoch`）と HUD（`HUDModel` の不連続の節）は
  残像（死亡演出・投射物・ゾーン・VFX・戦闘テキスト・キルフィード・告知・ミニマップの残像）を捨てて状態から作り直す。瓦礫になった構造物も状態が生きていれば戻す。
  オンラインの再同期（`restore`）も同じ合図を使う。
- `ReplayBaker` は別の `Simulation`（同じ config・マップ・入力表）を低優先度のバックグラウンドで回し、キーフレーム（最大 96 個 ≒ 19MB）と
  再生位置付近の細かい輪（150 tick 毎・24 個 ≒ 5MB）、試合全体の年表を先に作って `adoptKeyframe` / `adoptFullTimeline` で渡す。
  熱・低電力モードでは控える。シークの再計算はメインスレッド外のワーカーで行い、結果の状態だけを `restore` する。
  手順は BattleController と同じ（step → 年表 → キーフレーム → リプレイの最終 tick での中断終了）なので、結果は通常の再生と一致する（テストで stateHash を比較）。
- リプレイは記録の最終 tick で止まる（途中で抜けた記録は中断終了）。途中で抜けても結果画面は記録時の結果を見せる。
  AI 同士の観戦は、一度最後まで見てから巻き戻して抜けても「最後まで見た」試合として扱う（自然な終わりの結果・保存・視聴の記録）。
  巻き戻してから抜けた時の結果とリプレイは、到達した最も先の時点（記録の先端）のものにする。
- シークバーの網掛けは「すぐにシークできる所」（キーフレーム・一度再生した所 = `seekReadyTick`）。年表が保存されていても状態の無い所は含めない。
  シークのワーカーは取り消されても進めた分（年表・キーフレーム・到達した状態）を残し、事前計算は再生・シークが先に作った状態へ飛んで続きから進める。
- 年表（`ReplayTimeline`）は step 毎に作り、リプレイに同梱する（`ReplayData.timeline`、古いファイルは nil で再生中に作り直す）。決定論なので、
  巻き戻しても記録済みの区間は捨てず、まだ記録していない tick だけ追記する。再生バーの印・ゴールド/経験値グラフ・イベント一覧・自動カメラが使う。

### 視点・カメラ
- 視界: `spectatorVision`（nil = 全体、.blue / .red = そのチームの視界）。`viewerTeam` は観戦者ならこれ、プレイヤーなら自分のチーム。
  霧・ユニットの見え方・ゾーンの色（観戦者にはチーム色）・帰還の演出（視界外では出さない）がこれに従う。
- 操作: 観戦者は画面のドラッグで自由カメラ、ピンチで倍率（`CameraRig.spectatorZoomRange` 0.7〜2.5。プレイヤーは 0.7〜1.4）、ダブルタップで追従に戻る。
  ヒーローのタップ・ミニマップでも追従先・注視点を変えられる。追従対象が消えた時は最後の位置に留まる。
- 自動カメラ（`CameraDirector`、`spectatorDirectorEnabled`）: キル・連続キル・全滅・構造物・目標・ボス戦・集団戦・逃走・必殺技を採点し、
  sim 時間で最短 4 秒の画を保ちながら `.followUnit` / `.framing` と倍率を出す。手動でカメラを動かすと 10 秒控え、操作が続けば延長する。
  ヒーローを選ぶ（自動カメラが映しているヒーローでも）のも手動の操作で、1 回目は追従の固定、もう一度選ぶと詳細。控える時間は再生している
  間だけ数え、一時停止・シーク中・終わった後は減らない（止めて眺めた後の再生・コマ送り・巻き戻しで奪い返さない）。オフにすると、自動カメラだけの画（`.framing`）は
  主役の追従に替える。
  倍率: 自動カメラ（1.2）は観戦者が倍率を決めていない間だけ書き、ピンチ・一時停止メニューの「カメラ距離」が優先する（画を変えても書き戻さない）。
  メニューで変えた倍率から自動カメラが倍率を取り戻すのは、オンにし直した時とダブルタップで戻した時（倍率も既定へ戻す操作）だけ。
  観戦者の視界がチームなら、そのチームに見えるものだけを追う。AI 同士の観戦と観戦席は既定でオン、リプレイは既定でオフ（持ち主を追う）。
- 死亡中の味方追従（プレイヤー）: 自分が死亡中だけ、味方のヒーローを追える（`HUDModel.follow` / `followableAllies`）。敵は追えない（霧の向こうが見えるため）。
  ミニマップで覗いて離すと味方へ戻り、復活すると自分の追従に戻る（オンラインの再同期で復活を飛び越えた時も、置き換えの後に戻す）。死亡カードに味方の一覧と「自動で戦っている味方を追う」切り替えがある。

### 画面
- 観戦ドック（下部）: 一時停止・速度（0.5/1/2/4/8 倍）・視界・自動カメラ・HUD を隠す（シネマ表示）・前後のヒーロー・10 人の追従ボタン。狭い画面は引き出しに収める。
  オンラインの観戦席は一時停止・速度・シークの代わりに LIVE と遅延秒数を出す。
- 再生バー（シークできる観戦・リプレイ）: ドラッグでシーク、±10/30 秒、最初から、一時停止中のコマ送り、次の見どころ、年表の印、計算済みの範囲。
- 情報パネル: 追従中のヒーロー（装備・スキルと残り時間・スペル・状態・ゴールド・K/D/A・与/被ダメージ・回復）、ゴールド/経験値の差のグラフ、
  目標のタイマー、イベント一覧（タップでシーク / カメラ移動）。スコアボードの行をタップすると追従する。リプレイでは持ち主を強調する。
- 観戦の準備: 側ごとの難易度・枠ごとのヒーロー・標準 / 乱闘マップ・シードの入力とコピー・速度 / 視界 / 自動カメラの既定（`Profile` の観戦設定に保存）。
- リザルト: 「リプレイを見る」「もう一度見る」、観戦では「次の AI 戦を見る」「同じシードでもう一度」。
- リプレイ一覧: 報酬の無い試合（AI 同士の観戦・全 AI のカスタム・オンラインのホスト）も保存（`ReplayArchiveService`、30 秒未満は保存しない）。
  お気に入り（上限の対象外、別枠 30 件。外してもその場では消さず、上限を超えていれば次の保存で古い順に消える）・名前の変更・
  詳細（成績表）・絞り込み・使用容量。上限（20 件）を超えたら、自動で保存した報酬の無い試合（AI 同士の観戦・カスタム・オンライン）を
  自分の対戦より先に、古い順に消す（戦績から開ける自分のリプレイが観戦に押し出されない）。重複の判定は構成の全体・長さ・入力で行う。`.vreplay` の共有と取り込み（UTType
  `com.bitcoinpay.velstria.replay`）。取り込んだファイルは信用せず、形式・大きさ・版数・入力の座標・成績の数値・年表を検証する。
  読み込みはメインスレッド外。版数の違うリプレイは押す前から灰色で示す。
- 観戦の記録: 観戦・リプレイを最後まで見た回数と時間を数え（同じ試合は 1 回）、通貨の付かない実績（観戦 1 / 10 回、リプレイ 5 回）にする。

### オンラインの観戦席
- 部屋に「観戦する」参加者を置ける（座席とは別。上限: プレイヤー 10・観戦 8）。試合中でも観戦として途中から入れる。
  席に着かないホストは実況（観戦の役割のまま権威シミュレーションを回す）として開始できる。実況も試合を tick 0 から遅延なしで回すので、
  選手のホストと同じくリプレイを記録・保存する（持ち主の座席なし）。観戦席は途中から遅延付きで見るので記録しない。
- ホストは観戦席へ **遅延付き** で配る（ゴースティング防止。部屋の設定で 0 / 15 / 30 / 60 秒、既定 30 秒、ロビーでだけ変更可）。
  `OnlineSpectatorRelay` が 300 tick 毎の状態と、空の tick も含む連続した入力列を持ち、0.1 秒毎の自前のタイマーで遅延の過ぎた分だけ配る
  （試合が終わった後も残りを配り切る。`matchFinished` で最終 tick を知らせる）。
- 観戦席の途中参加・再同期には **遅延した基準の状態** だけを送る（生の状態は送らない）。スナップショットの頻度は観戦席 5 秒・プレイヤー 2 秒まで。
  最初のキーフレームが公開される前のずれの再同期は、試合開始時（tick 0）の状態を送る。試合の終わりまで配り切った後の再同期でも、
  基準の先の残りと `matchFinished` を送り直す。観戦席からの入力は受け付けない。
- 観戦席は試合開始で観戦画面が開く。前の試合（遅延分の残り・リザルト）や読み込み中の戦闘を開いている間に案内が来たら、配信の状態を
  何も変えずに断り（`OnlineSession.isBattleOpen`）、観戦席の役割なら戦闘を閉じた後に自動で観戦を求め直す（`battleClosed`）。
  「観戦する」の返事を待つ間は「観戦する」「試合に戻る」を押せない。
- プレイヤーの画面には観戦者数と遅延を出す。ホストが中断・切断した時は、プレイヤー・観戦席とも「試合が中断されました」と退出ボタンを出す。
- Bonjour の TXT に部屋の段階と観戦の可否を載せる（キー p / w / np / ns）。

検証用の起動引数（Debug のみ）: `-battle spectate|replay`、`-spectateMap standard|brawl`、`-spectateSpeed`、`-spectateVision all|blue|red`、
`-spectateDirector on|off`、`-seekTo <秒>`、`-sampleReplays`、`-onlineSpectate`（`-onlineJoin` と併せて観戦席で入る）。
テスト: `SpectatorFoundationTests` / `SpectatorOptionsTests`（土台）、`ReplayBakerTests` / `PresentationResetTests` / `SpectatorAudioTests`、
`HUDSpectatorTests` / `HUDReplayTransportTests`、`CameraDirectorTests` / `SpectatorCameraTests` / `DeathSpectateTests`、
`ReplayLibraryTests` / `SpectateSetupTests`、`OnlineSpectatorTests`、UI テスト `SpectatorHUDUITests` / `ReplayLibraryUITests` / `OnlineSpectateLobbyUITests`、
コア `ReplayTimelineTests` / `MatchFactorySpectateTests`。

## ヒーローの 3D モデル（Tripo 生成アセット）
- 表示は `HeroModelLibrary.makeHero`（`HeroDisplayModel`）。同梱の `Hero_<heroID>.usdz` があればスキンメッシュ
  （`SkinnedHeroModel`）、無ければ手続き生成（`HeroModel`）。どちらも同じ `HeroAnimator` / `HeroPose` で動き、
  スキンメッシュは `HeroSkeletonRig` が姿勢を Mixamo 名の骨へリターゲットする（武器・浮遊物・足元表示は従来の部品を手の骨に付ける）。
- 読み込みは `LoadingScreenView` で `HeroModelLibrary.purge` → 1 人ずつ `preloadAsync`（USDZ はメインスレッド外）。
  戦闘中に USDZ を同期で読まない。
- アセットの生成・取り込み: `tools/tripo.mjs`（Tripo API v3。キーは `TRIPO_API_KEY` か `~/.config/tripo/api_key`、
  リポジトリに置かない）→ `tools/blender/normalize_*.py`（Blender ヘッドレスで USDZ へ正規化）→ `verify_usdz.swift` の検査に
  通ったものだけ `App/Resources/Heroes/` へ。規約・手順は `App/Resources/Heroes/README.md`、プロンプトは `tools/tripo/assets.json`。
  ```sh
  node tools/tripo.mjs balance                      # 残高（1 credit = $0.01）
  node tools/tripo.mjs estimate all                 # 必要クレジットの見積もり
  node tools/tripo.mjs run heroes H001 --until concept   # まずコンセプト画像だけ作って確認
  node tools/tripo.mjs run heroes H001 --max-credits 90  # モデル → リグ判定 → リグ
  node tools/tripo.mjs import heroes H001           # 正規化 → 検査 → App/Resources/Heroes/Hero_H001.usdz
  ```

## ビルド・テスト
```sh
# コア
cd Packages/VelstriaCore && swift build && swift test
# 長いシミュレーションテストは Release で
swift test -c release --filter <TestName>

# アプリ（リポジトリの VELSTRIA/ で）
xcodegen generate
xcodebuild -project VELSTRIA.xcodeproj -scheme VELSTRIA \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/DerivedData \
  build CODE_SIGNING_ALLOWED=NO -quiet

# 画面確認（自分専用シミュレータを作る・終わったら削除）
xcrun simctl create vel-<担当名> "iPhone 17 Pro"      # → UDID
xcrun simctl boot <UDID>
xcodebuild ... -destination 'id=<UDID>' build   # または generic ビルドの .app を install
xcrun simctl install <UDID> .build/DerivedData/Build/Products/Debug-iphonesimulator/VELSTRIA.app
xcrun simctl launch <UDID> com.bitcoinpay.velstria -uiTesting -skipOnboarding -grant -route heroes
xcrun simctl io <UDID> screenshot /tmp/<担当名>-heroes.png
xcrun simctl delete <UDID>
```
起動引数の一覧は `App/Core/DebugLaunch.swift`。起動引数は Debug ビルド（または `SCREENSHOTS` 条件付きの撮影用ビルド）でのみ有効で、
App Store 用の Release アーカイブでは読まれない（`-grant`・`-skipOnboarding`・`-heroGallery` 等は出荷バイナリに含まれない）。
