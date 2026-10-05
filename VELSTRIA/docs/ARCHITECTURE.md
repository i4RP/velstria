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
  例外はオンライン対戦（下記。同一 LAN の端末間通信のみ、外部サーバーなし）。

## オンライン対戦（リッスンサーバー方式、開発期間用）
`FeatureFlags.lanMatch` で有効。参加者の 1 台が **ホスト**（権威シミュレーション）になり、他は **クライアント**として入力を送る。
外部サーバーは無い。同一 LAN の部屋を Bonjour（`_velstria._tcp`）で探すか、ホストの IP:ポート（既定 47814）を入力して TCP で繋ぐ。
Info.plist に `NSLocalNetworkUsageDescription` / `NSBonjourServices` が必要（project.yml に定義）。

```
App/Online/
  OnlineProtocol.swift   メッセージ（OnlineMessage）・部屋モデル（OnlineRoom / OnlineSeat / OnlineLoadout）・長さ区切り JSON の符号化（OnlineFramer）
  OnlineTransport.swift  接続の抽象（OnlineConnection）。LoopbackConnection（テスト）、NWOnlineConnection / NWOnlineListener / NWOnlineBrowser（Network.framework）
  OnlineSession.swift    部屋への参加状態（ホスト or クライアント）。ロビー操作、戦闘中の入力中継、ハッシュ照合、再同期、切断 → AI 引き継ぎ、再接続
App/Screens/Online/OnlineLobbyView.swift  入口（部屋を作る / 探す / アドレス入力）と部屋（座席・ピック・準備完了・開始）
Packages/VelstriaCore/Sources/VelstriaCore/Sim/MatchFactoryOnline.swift  複数人間の 5v5 構成（`MatchFactory.onlineMatch`、座席番号 = players の添字）
```

同期の仕組み（決定論シミュレーションの入力同期。AI は両側で同じ計算をするので送らない）:
1. ロビー: ホストが `OnlineRoom` の正本を持ち、変化のたびに全体を配る。座席（Blue 5 / Red 5）に着いた人間がピックして準備完了、ホストが開始。
   `OnlineRoom.makeConfig` が `MatchFactory.onlineMatch` で `MatchConfig`（`mode: .online`）を作り、全員に同じ構成が届く。
   自分の座席番号は `BattleLaunch.onlineSeat`（= `config.players` の添字）。`BattleController.localHeroID` はそこから決まり、
   `humanHeroID` / `localTeam` / `viewerTeam`（霧の視点）は自分の座席のもの（Red 側のこともある。カメラは回転しない）。
2. 読み込み: 各クライアントは戦闘画面で `OnlineSession.attach` → `.loaded` を送る。ホストは座っている全員の `loaded`（または 90 秒）を待ってから進め始める。
3. 戦闘: ホストは `自分の入力 + 届いたクライアント入力（+ 操作者切り替え）` で `Simulation.step` し、その tick に適用した入力列を
   `ReplayFrame` として全員へ配る（空の tick も送る。クライアントの時計になる）。描画フレームの終わりにまとめて 1 メッセージで送る。
   クライアントは入力をホストへ送るだけで自分では適用せず、届いた tick の入力で step する（遅れて再生。届かなければ補間係数 1 で待ち、
   `onlineJitterBuffer` tick より溜まれば時計を待たずに進め、`onlineCatchUpThreshold` より溜まれば早送りで追いつく）。
   クライアントは他人のヒーローを操作できない（ホストが座席のヒーロー ID で検証し、`setController` は捨てる）。
4. 検証と再同期: クライアントは `OnlineProtocol.hashInterval`（30 tick）毎に `SimState.stateHash()` を報告し、ホストは自分の記録と比べる。
   食い違えばホストの `SimState` スナップショット（Codable、約 200KB）を送り、クライアントは `Simulation.restore(from:)` で置き換えて
   それ以前の配信を捨てる。
5. 切断: 試合中にクライアントが落ちるとホストは `PlayerCommand.setController(.bot)` を発行して AI に引き継ぐ（座席は保つ）。
   同じ playerID で再接続すると構成 → 読み込み → スナップショット → `setController(.human)` で戻る。ホストが落ちるとクライアントの試合は中断終了。
6. 一時停止・バックグラウンド: オンライン中は `isPaused` で世界を止めない（メニューを開くだけ）。
   `MatchMode.online` は報酬・ランク・戦績の対象外（`RewardService`）。降参投票は有効。

検証用の起動引数（Debug のみ）: `-onlineHost [port]`、`-onlineJoin <host:port>`、`-onlineAuto`（自動で着席・ピック・準備完了、ホストは揃えば開始）。
2 台のシミュレータで `-onlineHost -onlineAuto` と `-onlineJoin 127.0.0.1:47814 -onlineAuto` を起動すると対戦が始まる。
テスト: `OnlineCoreTests`（コア）、`OnlineProtocolTests` / `OnlineSessionTests`（ループバックでロビー → 同期 → 再同期 → 切断 → 再接続）/
`OnlineTransportTests`（localhost の TCP）。

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
