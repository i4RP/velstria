# VELSTRIA iOS アーキテクチャ・開発ルール

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
    Resources/                     Assets.xcassets, Velstria.storekit, PrivacyInfo.xcprivacy, master_en.json
  AppTests/  AppUITests/
  docs/  DESIGN.md（ゲーム数値の正本） ARCHITECTURE.md（本書）
  tools/
```
- 最低 iOS 18.0、iPhone のみ、横画面固定、Swift 5 言語モード（Swift 6.2 コンパイラ）。
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
| appstore-assets | project.yml, App/Resources/Assets.xcassets, PrivacyInfo.xcprivacy, master_en.json, docs/APPSTORE*, docs/legal/*, tools/*（gen_runtime_data.py 以外） |
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
- ネットワーク通信なし（オフライン完結）。外部リンクは `Link` / `openURL`。

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
起動引数の一覧は `App/Core/DebugLaunch.swift`。
