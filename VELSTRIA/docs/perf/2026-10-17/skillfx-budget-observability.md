# 2026-10-17 スキル演出の予算の観測（調査と実装の記録）

スキル演出の不足が、素材・描画方式によるものか、共通の予算による打ち切り・破棄によるものかを判断できるようにする。
今回は観測だけ。見た目・容量・寿命・大きさ・生成数・被弾演出の間隔・打ち切りの順・予約の順・再生の順は変えていない。
カウンターの定義と取得方法は `docs/SKILL_FX.md`「予算の観測」が正。

## 作業の前提

- ブランチ `vfx/skillfx-budget-observability`（`origin/main` = `94bb340` から分岐）。一時の worktree で作業し、主の作業ツリー
  （`main` = `fa55242`、ほかの作業の未コミットの変更 32 件）には触れていない。
- 対象: `SkillFXPlayer` の粒子放出体のプール・メッシュのプール、`BattleWorkBudget.cuesPerPlay`・`BattleWorkBudget.pendingCues`。

## 現行コードで確かめた容量（調査の値と一致。差異なし）

| 経路 | 値 | 定義 |
|---|---|---|
| 粒子放出体 | 低 10・中 22・高 34（試合開始時の画質 `poolQuality`。全員で共有） | `SkillFXPlayer.emitterCapacity` |
| メッシュ | 円板 28・弧 12・板 12・円柱 10・球 10・壁 8・帯 8・ドーム 5・尖塔 5・漏斗 5 = 103。低は `max(2, base / 2)` = 50 | `SkillFXPlayer.meshCapacity` |
| 1 回の再生の合図 | 64 | `BattleWorkBudget.cuesPerPlay` |
| 遅延予約 | 512（全員の合計） | `BattleWorkBudget.pendingCues` |

## 経路（静的に確認）

粒子放出体（`spawnEmit`）:
1. 取得: 空き（`freeEmitters.popLast`）→ 無ければ `prewarm` 済みなら、止まらない継続放出（`looping`）以外で `until` が最も早いものを
   取り上げる → それも無ければ `return`（要求を捨てる）。`prewarm` の前は `makeEmitter` で作る。
2. 正常終了: `update` で `until` を過ぎたら `release`（空きへ）。継続放出は `stopAt`・`stop(follow:)`（着弾・追従の主体の消滅）で
   止め、余韻 0.8 秒の後に同じく `release`。
3. 返却: `release`（寿命）・`clear()`（全て）。

メッシュ（`spawnMesh`）:
1. 取得: 同じ形の空き → 無ければ `prewarm` 済みなら同じ形で `start` が最も古いものを取り上げる → 無ければ `return`。
   `prewarm` の前は `makeMesh`。容量は最低 2 なので、空きが無ければ同じ形の使用中が必ずあり、`return` には今のコードでは到達しない。
2. 正常終了: `update` で寿命に達したら空きへ。`cut(follow:group:)` は寿命を縮めるだけで、その後は同じく寿命で戻る。
3. 返却: 寿命・`clear()`。

合図（`play`）: 先頭から `cuesPerPlay` 個の合図まで、画質で出さない合図（`minQuality`）を飛ばし、繰り返しを 1 回ずつ数えて 64 回分まで受け付ける。
遅れ 0 はその場で発火、遅れのあるものは予約が 512 未満なら予約し、満杯なら捨てる。予約は `update` で発火する。
`stop(follow:)`（追従の合図）・`cut`（同じ組）・`clear()` で予約を取り消す。

確認できた点:
- `update` は予定の合図を回収より先に発火する。このため寿命を過ぎて回収を待っている枠が「取り上げ」に使われることがあり、
  従来の `stats.stolenEmitters` / `stolenMeshes` はこれも打ち切りとして数えていた。今回 `cut`（寿命の途中）と `reclaimed`（寿命の後）に分け、
  `stolenEmitters` / `stolenMeshes` は `cut` だけを返すようにした（ほかに読む箇所は無い）。
- 従来の `stats.droppedCues` は 1 回の上限と予約の上限を混ぜ、上限に達した後の合図を 1 つしか数えない。そのまま残し、別に
  `cuesOverPerPlay` / `cuesOverPending` を足した。
- `stats` は `clear()` で 0 に戻る。`clear()` は幕が上がる直前（`WorldWarmup.finishWarmup`）・シーク / 再同期（`BattleWorld.resetForPresentationEpoch`）・
  破棄（`teardown`）から呼ばれる。読み込み中の `prewarm`・陳列（`fireWarmup`）は spawn を通らないので要求に入らない。
- `BattleWorld`（と再生器）は `BattleRenderer.buildWorld` で戦闘画面ごとに 1 度だけ作る。前の試合の値は引き継がない。
- 出所（ヒーロー・スキル・再使用の段）は `SkillFXDirector.context` の 1 か所で `Context.source` に入れられる。cast / impact などの段（phase）は
  再生器に渡らないので集計しない。出所の無い再生は `unknown`。

## 変更

| ファイル | 変更 |
|---|---|
| `App/Battle/Render/SkillFX/SkillFXPlayer.swift` | `Stats` に枠の集計（`PoolStats`: requests / cut / reclaimed / rejected / grown / peakInUse。粒子放出体と形ごとのメッシュ）、合図の `cuesOverPerPlay` / `cuesOverPending`、出所ごとの `bySource` を追加。`Context.source`、`budgetSnapshot()` と `SkillFXBudgetSnapshot`（Codable）。分岐・順・容量は変えていない |
| `App/Battle/Render/SkillFX/SkillFXDirector.swift` | `context(...)` で `source` を渡す（1 行） |
| `App/Battle/Perf/PerfRun.swift` | `PerfReport.skillFXBudget`（任意の項目） |
| `App/Battle/Render/BattleRenderer.swift` | 性能記録の書き出し時に `budgetSnapshot()` を入れる |
| `AppTests/SkillFXTests.swift` | 予算の観測のテスト 7 件 |
| `docs/SKILL_FX.md` | 「予算の観測」。予算の本文の古い値（16 / 10・24 / 12）をテストの値（20 / 13・28 / 16）に直した |
| `docs/BATTLE_PERFORMANCE.md` | 予算と検査の表と、この記録への節 |

計測の負荷: 要求ごとに整数の加算、メッシュの取得ごとに使用中の同じ形の数え上げ（使用中は最大 103）、再生ごとに合図の数え上げ。
毎フレームの処理・文字列・ログは足していない。出所の名前の文字列は `budgetSnapshot()` の時だけ作る。`bySource` のキーは試合のヒーローのスキルの数まで。

## 検証（`AppTests/SkillFXTests`。容量は本番の低画質のプールをそのまま使い、実際の取得の経路で超過させる）

| テスト | 確かめること |
|---|---|
| `testBudgetCountsNoCutWithinCapacity` | 容量以内（粒子放出体 10・円板 14 を同時に使用）なら cut / rejected / reclaimed / 合図の破棄が 0 |
| `testPoolOverflowCutsInTheExistingOrderAndCountsEachCutOnce` | 超過で、従来どおり最も早く終わる一斉放出・同じ形の最も古いメッシュが取り上げられ（エンティティの位置で確認）、cut がちょうどその回数。打ち切られた側の出所に数える |
| `testRequestIsRejectedWhenOnlyLoopingEmittersAreLive` | 使用中が全て止まらない継続放出なら要求を捨て、rejected に数える（cut とは別） |
| `testReusingFinishedSlotsIsNotCountedAsCut` | 寿命を終えて空きに戻った枠の再利用・回収待ちの枠の引き取りは cut に数えない（後者は reclaimed） |
| `testPerPlayAndPendingDropsAreCountedSeparately` | 64 を超えた合図は `overPerPlay`、予約が満杯で捨てた合図は `overPending` に別々に入る。先頭の 64 個を受け付ける順は従来どおり |
| `testBudgetCountersExcludeWarmupAndResetOnClear` | 陳列は要求に数えない。`clear()` で全て 0、新しい再生器も 0 |
| `testBudgetSnapshotNamesUnknownSourceAndRoundTripsJSON` | 出所の無い再生は `unknown`。写しは JSON へ書いて読み戻せる |

検証できない部分:
- メッシュの `rejected` は今のコードでは到達しないため、実際の経路のテストは無い（数える処理だけある）。
- 出所を入れる `SkillFXDirector.context` はテストから作れない（`UnitLayer` などが要る）ため、静的な確認のみ。テストは再生器へ `Context.source` を直接渡す。
- 既存の選択の順・破棄の動作は、上の位置の確認・受け付けの順の確認と、既存のテスト（`testCosmeticCueQueueIsBoundedAndRecoversAfterOverload` など）で確かめる。

未計測: 通常の試合・集団戦での発生頻度（`perf_run.sh` を回していない）、実機 FPS、発熱、ブルームの見え方。

## CI（GitHub Actions・macos-26・Xcode 26.6・iPhone 17 シミュレータ）

| 実行 | 対象 | 結果 |
|---|---|---|
| [38928375868](https://github.com/i4RP/velstria/actions/runs/38928375868)（push） | `2527504` | 成功。Release のアーカイブ（アプリのビルド）・TestFlight の内部配信 build 24940812 |
| [38928389819](https://github.com/i4RP/velstria/actions/runs/38928389819)（テストつき 1 回目） | `2527504` | テストの段で失敗。`SkillFXTests` 27 件（追加 7 件 + 既存 20 件）・`RenderLogicTests`・`PresentationResetTests` ほかは通過。失敗は 7 件（下） |
| [38939540998](https://github.com/i4RP/velstria/actions/runs/38939540998)（比較: 変更なしの `main`） | `94bb340` | テストの段で失敗。失敗は下の 6 件で、同じテストが同じように落ちる |

失敗したテスト（各 3 回の再試行すべて失敗）:

| テスト | このブランチ | 変更なしの main |
|---|---|---|
| `CoreFinaleTests.testShotsStayInsideTheMapClearOfStructuresAndFrameTheCore`（地図の外） | 失敗 | 失敗 |
| `FriendTests.testErasedInboxIsReplacedWithANewCodeAndReconnects` | 失敗 | 失敗 |
| `HUDShopTests.testShopStateMarksCurrentBlessingAndProgress`（2 / 5 ≠ 3 / 5） | 失敗 | 失敗 |
| `BattleHUDUITests.testRankedLeaveIsRecordedAsLoss` | 失敗 | 失敗 |
| `BattleHUDUITests.testTutorialMoveStepAdvancesWithJoystick` | 失敗 | 失敗 |
| `SpectatorHUDUITests.testSpectatorMenuPanelsSeekTacticalMapAndCinematic` | 失敗 | 失敗 |
| `ReplayLibraryUITests.testReplayListDetailAndPlayback` | **失敗** | 通過 |

`ReplayLibraryUITests` だけがこのブランチで落ちた。3 回のうち 2 回は戦闘の画面に入る前（リプレイ一覧でアプリが落ちた・起動直後に接続が切れた）で、
スキル演出の再生器は戦闘の画面（`BattleWorld`）にしか無いため、今回の変更の経路は通っていない。残る 1 回は再生を終えて退出する所で応答が止まった。
単体テストの側では、変更なしの main でもリプレイの計算（`LargeStackRunner` の `withoutActuallyEscaping`）で試験のアプリが落ちて再起動している
（このブランチ 1 回・main 3 回）。

同じコミットで同じジョブを再実行した結果（[38928389819 の 2 回目](https://github.com/i4RP/velstria/actions/runs/38928389819/attempts/2)）:
`ReplayLibraryUITests.testReplayListDetailAndPlayback` は 1 回目の試行で通過、`SkillFXTests` 27 件も再び全て通過。
`BattleHUDUITests.testTutorialMoveStepAdvancesWithJoystick` は 3 回目の試行で通過した。ほかの 5 件は変更なしの main と同じく失敗。
リプレイの UI テストの失敗は不安定な失敗（同じコードで通る）と判断した。残る失敗は今回の変更の前から main にあり、この作業では直していない。
テストの段が失敗するため、このワークフローは成功（緑）にならない。
