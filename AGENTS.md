# エージェント向けの作業ルール（VELSTRIA）

Claude Code・Codex ほか、このリポジトリで作業するすべてのエージェントが従うこと。

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
- `production` ブランチへの push は App Store の審査提出（承認後に自動で公開）になる。本番に出す指示が無い限り
  `production` には push しない。TestFlight 配信は `production` 以外のブランチ（通常は `main`）への push で行う。
- リポジトリは公開。証明書・API キー・パスワードなどの秘密情報はコミットしない（CI は GitHub Secrets から読む）。
