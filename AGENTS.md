# エージェント向けの作業ルール（VELSTRIA）

Claude Code・Codex ほか、このリポジトリで作業するすべてのエージェントが従うこと。

## バトル・キャラ・ステージの追加時

- `VELSTRIA/docs/BATTLE_PERFORMANCE.md` の性能契約を読む。画面外の詳細更新、全コンテンツの一括ロード、
  上限のない装飾エフェクト予約を追加しない。ゲーム判定と描画の間引きを分離する。
- 既存のキャラ・ステージ・演出の予算テストを維持する。新コンテンツのために上限だけ引き上げない。
- 性能改善は計測環境を明記する。シミュレータの値から実機 FPS の改善を断定しない。

## 視界画面の品質更新

- 視界・ステージ・照明を更新するたびに、変更前後の実描画とユーザーの参考画像を比較する。
  空と森林の奥行き、石畳の凹凸、明暗・色、戦闘対象の見やすさ、HUD の占有を別々に総評し、残る差を次の更新に反映する。
- `VELSTRIA/tools/vision_review.sh` に明示したシミュレータ UUID・Debug/SCREENSHOTS アプリ・保存先を渡す。
  `-stageFull` を必須とし、同じ端末・キャラ・画質で撮影する。自動画質低下は perf-report の notes で確認する。
- 報告には実スクショと参考画像の両方を添え、改善した点と未達の点を明記する。
  見た目の主観評価を客観的な点数や実機 FPS の証明として扱わない。

## TestFlight への配信は必ず GitHub 経由で行う

- 配信は GitHub Actions（`.github/workflows/`）で行う。変更をコミットして GitHub へ push すると、CI が
  テスト → アーカイブ（CI 専用証明書で手動署名）→ App Store Connect へアップロード → 処理完了待ち まで実行する。
  内部テストグループ「In」は全ビルド自動配信なので、処理が終わればテスターに届く。
- 手元の Mac から直接アップロードしない（`tools/upload_testflight.sh` の手動実行、`xcodebuild -exportArchive` の
  upload、Transporter、Xcode Organizer など）。ビルド番号の衝突や、署名・設定の食い違いの原因になる。
  これらのスクリプトは CI の中で使うためのもの。
- 発火条件（対象ブランチ・パス）とビルド番号の決め方は変わることがある。ワークフローファイルと README の
  「自動配信（TestFlight / App Store）」節を正とする。コードを変えずに配信し直すときは Actions の「Run workflow」
  （`gh workflow run testflight.yml -R i4RP/velstria`）を使う。
- push した後は `gh run watch <run-id> -R i4RP/velstria --exit-status` で完了まで見届ける。失敗したら原因を直して
  push し直す。届いたかどうかは `node VELSTRIA/tools/asc.mjs status` / `testers` で確認できる
  （環境変数 `ASC_KEY_ID` / `ASC_ISSUER_ID` が必要）。
- App Store への審査提出・公開は行わない（ユーザー指示: 本番配信は不要）。`production` ブランチへの push も、他のブランチと
  同じく TestFlight の内部グループ「In」への配信になる（提出する仕組みは削除済み）。通常は `main` への push で配信する。
- リポジトリは公開。証明書・API キー・パスワードなどの秘密情報はコミットしない（CI は GitHub Secrets から読む）。
