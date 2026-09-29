#!/usr/bin/env python3
"""Required Reason API の使用箇所を走査し、PrivacyInfo.xcprivacy の宣言漏れを検出する。

usage（リポジトリの VELSTRIA/ で）:
    python3 tools/privacy_audit.py          # 使用箇所と宣言を突き合わせ、漏れがあれば exit 1

App Store Connect はアップロード時にバイナリを静的解析し、宣言の無い Required Reason API を
使っていると ITMS-91053 で警告・却下する。提出前（tools/archive.sh が自動実行）と
コード追加時に実行すること。宣言済みだが未使用のカテゴリは情報として表示するだけ（エラーにしない）。

対象 API は Apple「Describing use of required reason API」の一覧に基づく。
"""
from __future__ import annotations

import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "App" / "Resources" / "PrivacyInfo.xcprivacy"
SCAN_DIRS = [ROOT / "App", ROOT / "Packages"]
SKIP_PARTS = {".build", "DerivedData", ".swiftpm", "Tests"}

# カテゴリ → (検出パターン, このアプリで許容する理由コード, 理由の説明)
CATEGORIES: dict[str, tuple[re.Pattern, set[str], str]] = {
    "NSPrivacyAccessedAPICategoryUserDefaults": (
        re.compile(r"\bUserDefaults\b|@AppStorage\b|\bNSUserDefaults\b"),
        {"CA92.1"},
        "CA92.1: アプリ自身の設定値のみを読み書き",
    ),
    "NSPrivacyAccessedAPICategoryFileTimestamp": (
        re.compile(r"\b(creationDate|modificationDate|contentModificationDate|contentAccessDate|"
                   r"attributeModificationDate|addedToDirectoryDate|fileModificationDate|creationDateKey|"
                   r"contentModificationDateKey|contentAccessDateKey|attributesOfItem|getattrlist|"
                   r"getattrlistbulk|fgetattrlist|getattrlistat|fstatat|fstat|lstat|NSFileCreationDate|"
                   r"NSFileModificationDate)\b|\bstat\s*\("),
        {"C617.1", "3B52.1", "0A2A.1", "DDA9.1"},
        "C617.1: アプリコンテナ内ファイルの日時・サイズ参照",
    ),
    "NSPrivacyAccessedAPICategorySystemBootTime": (
        re.compile(r"\bsystemUptime\b|\bmach_absolute_time\b"),
        {"35F9.1", "8FFB.1", "3D61.1"},
        "35F9.1: 経過時間の計測（効果音・触覚の再生間隔などアプリ内のイベント間隔）",
    ),
    "NSPrivacyAccessedAPICategoryDiskSpace": (
        re.compile(r"\b(volumeAvailableCapacity\w*|volumeTotalCapacity\w*|systemFreeSize|systemSize|"
                   r"NSFileSystemFreeSize|NSFileSystemSize|statfs|statvfs|fstatfs|fstatvfs)\b"),
        {"85F4.1", "E174.1", "7D9E.1", "B728.1"},
        "E174.1: 書き込み前の空き容量確認",
    ),
    "NSPrivacyAccessedAPICategoryActiveKeyboards": (
        re.compile(r"\bactiveInputModes\b"),
        {"3EC4.1", "54BD.1"},
        "3EC4.1: カスタムキーボードのみ",
    ),
}


def strip_comments(line: str) -> str:
    """行コメントを除いた部分（文字列中の // は考慮しない簡易版。誤検出側に倒れるので安全）。"""
    i = line.find("//")
    return line if i < 0 else line[:i]


def scan() -> dict[str, list[str]]:
    hits: dict[str, list[str]] = {k: [] for k in CATEGORIES}
    for base in SCAN_DIRS:
        for path in sorted(base.rglob("*")):
            if path.suffix not in {".swift", ".m", ".mm", ".c", ".cpp", ".h"}:
                continue
            if SKIP_PARTS.intersection(path.relative_to(ROOT).parts):
                continue
            in_block = False
            for no, raw in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
                line = raw
                # ブロックコメントの簡易除去
                if in_block:
                    if "*/" not in line:
                        continue
                    line = line.split("*/", 1)[1]
                    in_block = False
                if "/*" in line and "*/" not in line.split("/*", 1)[1]:
                    line = line.split("/*", 1)[0]
                    in_block = True
                code = strip_comments(line)
                for cat, (pattern, _, _) in CATEGORIES.items():
                    if pattern.search(code):
                        hits[cat].append(f"{path.relative_to(ROOT)}:{no}: {raw.strip()}")
    return hits


def load_plist(path: pathlib.Path) -> dict:
    """plist を読む。Python の expat が壊れている環境もあるので macOS 標準の plutil を優先する。"""
    try:
        out = subprocess.run(["plutil", "-convert", "json", "-o", "-", str(path)],
                             check=True, capture_output=True, text=True).stdout
        return json.loads(out)
    except (OSError, subprocess.CalledProcessError):
        import plistlib
        with path.open("rb") as f:
            return plistlib.load(f)


def declared() -> dict[str, list[str]]:
    plist = load_plist(MANIFEST)
    errors = []
    if plist.get("NSPrivacyTracking") is not False:
        errors.append("NSPrivacyTracking が false ではありません")
    if plist.get("NSPrivacyTrackingDomains", []) != []:
        errors.append("NSPrivacyTrackingDomains が空ではありません（トラッキングしない方針）")
    if plist.get("NSPrivacyCollectedDataTypes", []) != []:
        errors.append("NSPrivacyCollectedDataTypes が空ではありません（App Store の「データの収集なし」と矛盾）")
    if errors:
        for e in errors:
            print(f"error: {e}", file=sys.stderr)
        sys.exit(1)
    out: dict[str, list[str]] = {}
    for entry in plist.get("NSPrivacyAccessedAPITypes", []):
        out[entry["NSPrivacyAccessedAPIType"]] = list(entry.get("NSPrivacyAccessedAPITypeReasons", []))
    return out


def main() -> int:
    hits = scan()
    decl = declared()
    failed = False
    for cat, (_, allowed, hint) in CATEGORIES.items():
        used = hits[cat]
        reasons = decl.get(cat)
        short = cat.replace("NSPrivacyAccessedAPICategory", "")
        if used and reasons is None:
            failed = True
            print(f"error: {short} を使用していますが PrivacyInfo.xcprivacy に宣言がありません（{hint}）", file=sys.stderr)
            for h in used[:20]:
                print(f"  {h}", file=sys.stderr)
        elif reasons is not None:
            bad = [r for r in reasons if r not in allowed]
            if not reasons or bad:
                failed = True
                print(f"error: {short} の理由コードが不正です: {reasons}（許容: {sorted(allowed)}）", file=sys.stderr)
            state = f"{len(used)} 箇所で使用" if used else "コード上は未使用（依存 API・将来の使用に備えた宣言）"
            print(f"ok: {short} {reasons} — {state}")
        else:
            print(f"ok: {short} — 未使用・未宣言")
    unknown = sorted(set(decl) - set(CATEGORIES))
    for cat in unknown:
        print(f"warning: 走査対象外のカテゴリが宣言されています: {cat}")
    if failed:
        return 1
    print("privacy manifest: 宣言漏れなし")
    return 0


if __name__ == "__main__":
    sys.exit(main())
