#!/bin/bash
# CI 用: アーカイブして App Store Connect へアップロードする（tools/archive.sh → tools/upload_testflight.sh）。
#
# ビルド番号は「2026-01-01 UTC からの経過秒」（2026-10 時点で約 2,400 万）。複数ブランチと production が
# 並行して走っても重複せず、時間とともに増える。Apple は同じバージョン内で「前回アップロードより大きい番号」を
# 要求するため、後から始まったビルドが先にアップロードされると後着側が拒否される。その場合だけ新しい番号で
# アーカイブからやり直す（最大 3 回）。手元からアップロードするときも BUILD_NUMBER はこれより大きくすること。
#
# 環境変数（archive.sh / upload_testflight.sh と共通）: TEAM_ID / SIGNING / PROFILE_NAME / ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH
#   LANE=beta        内部テスト用。アプリ内の仮値（法定表示・サポート URL）は警告に留める（ALLOW_APP_PLACEHOLDERS=1）
#   （App Store への審査提出は行わないため、production レーンは廃止した）
# 出力: 成功したビルド番号を GITHUB_ENV（あれば）に BUILD_NUMBER として書く。
set -euo pipefail

cd "$(dirname "$0")/.."

LANE="${LANE:-beta}"
case "$LANE" in
    beta)       export ALLOW_APP_PLACEHOLDERS=1 TESTER_TOOLS=1; unset STRICT ;;
    *) echo "error: LANE は beta だけ指定できます（App Store への審査提出は行わない）: $LANE" >&2; exit 1 ;;
esac

EPOCH_2026=1767225600  # 2026-01-01T00:00:00Z
MAX_ATTEMPTS=3
for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
    BUILD_NUMBER=$(( $(date -u +%s) - EPOCH_2026 ))
    export BUILD_NUMBER
    printf '\n==> ビルド番号 %s（LANE=%s、試行 %d/%d）\n' "$BUILD_NUMBER" "$LANE" "$attempt" "$MAX_ATTEMPTS"
    tools/archive.sh

    LOG="$(mktemp)"
    if tools/upload_testflight.sh 2>&1 | tee "$LOG"; then
        rm -f "$LOG"
        [[ -n "${GITHUB_ENV:-}" ]] && echo "BUILD_NUMBER=$BUILD_NUMBER" >> "$GITHUB_ENV"
        echo "==> アップロード完了: ビルド $BUILD_NUMBER"
        exit 0
    fi
    # 表示バージョンが承認済み・受付終了（ITMS-90062 等）なら、番号を変えても通らない
    if grep -qiE 'previously approved version|CFBundleShortVersionString|closed for new build' "$LOG"; then
        rm -f "$LOG"
        echo "error: MARKETING_VERSION が App Store で承認済みのバージョンと同じです。VELSTRIA/project.yml の MARKETING_VERSION を上げてください" >&2
        exit 1
    fi
    # 番号の逆転・重複（並行ビルドが先に大きい番号を上げた）だけ再試行する。その他の失敗は即終了。
    # upload_testflight.sh 自身の案内文（"already been uploaded" の場合…）には一致しない語で判定すること。
    if grep -qiE 'previously uploaded version|Redundant Binary Upload' "$LOG" \
            && (( attempt < MAX_ATTEMPTS )); then
        rm -f "$LOG"
        echo "warning: ビルド番号 $BUILD_NUMBER より大きい番号が先にアップロードされました。新しい番号で作り直します" >&2
        continue
    fi
    rm -f "$LOG"
    exit 1
done
exit 1
