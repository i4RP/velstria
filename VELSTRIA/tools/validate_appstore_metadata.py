#!/usr/bin/env python3
"""App Store Connect 提出用メタデータ（docs/appstore/）の文字数・整合性を検証する。

usage（リポジトリの VELSTRIA/ で）:
    python3 tools/validate_appstore_metadata.py            # 形式・文字数・課金 ID の整合（プレースホルダは警告）
    python3 tools/validate_appstore_metadata.py --release  # 提出直前: プレースホルダ・仮 URL が残っていればエラー

検査内容:
  - docs/appstore/metadata/<locale>/*.txt（fastlane deliver 互換の配置）の文字数上限
  - キーワードの重複・区切り、名前/サブタイトルとの重複（警告）
  - 他プラットフォーム名など審査で問題になる語の混入
  - URL が https であること
  - docs/appstore/iap_products.json と DESIGN.md §13・StoreKitService.swift・Velstria.storekit の商品 ID/価格の一致
  - App 内課金の表示名・説明の文字数
  - review_information/notes.txt の文字数
  - docs/legal/・docs/appstore/ に残ったプレースホルダ {{...}}
"""
from __future__ import annotations

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
APPSTORE = ROOT / "docs" / "appstore"
META = APPSTORE / "metadata"
LEGAL = ROOT / "docs" / "legal"
IAP_JSON = APPSTORE / "iap_products.json"
DESIGN = ROOT / "docs" / "DESIGN.md"
STOREKIT_SERVICE = ROOT / "App" / "Services" / "StoreKitService.swift"
STOREKIT_CONFIG = ROOT / "App" / "Resources" / "Velstria.storekit"

LOCALES = ["ja", "en-US"]
# App Store Connect の上限（文字数）
LIMITS = {
    "name.txt": 30,
    "subtitle.txt": 30,
    "promotional_text.txt": 170,
    "description.txt": 4000,
    "keywords.txt": 100,
    "release_notes.txt": 4000,
}
REQUIRED = ["name.txt", "subtitle.txt", "promotional_text.txt", "description.txt", "keywords.txt",
            "support_url.txt", "marketing_url.txt", "privacy_url.txt"]
URL_FILES = ["support_url.txt", "marketing_url.txt", "privacy_url.txt"]
# 審査で却下されやすい語（他プラットフォーム・価格の断定・根拠のない最上級）
FORBIDDEN = [
    (re.compile(r"android|google play|アンドロイド|グーグルプレイ", re.I), "他プラットフォームへの言及"),
    (re.compile(r"\b(free gems|無料ジェム配布)\b", re.I), "誤認を招く無料訴求"),
    (re.compile(r"(No\.?\s?1|ナンバーワン|世界一|最高傑作)", re.I), "根拠のない最上級表現"),
]
VALID_CATEGORIES = {"GAMES"}
VALID_GAME_SUBCATEGORIES = {
    "GAMES_ACTION", "GAMES_ADVENTURE", "GAMES_BOARD", "GAMES_CARD", "GAMES_CASINO", "GAMES_CASUAL",
    "GAMES_FAMILY", "GAMES_MUSIC", "GAMES_PUZZLE", "GAMES_RACING", "GAMES_ROLE_PLAYING",
    "GAMES_SIMULATION", "GAMES_SPORTS", "GAMES_STRATEGY", "GAMES_TRIVIA", "GAMES_WORD",
}
# 課金商品の表示名・説明（App Store Connect の上限より保守的な値）
IAP_NAME_MAX = 30
IAP_DESC_MAX = 45
REVIEW_NOTES_MAX = 4000
PLACEHOLDER = re.compile(r"\{\{[A-Z0-9_]+\}\}")
PLACEHOLDER_URL = re.compile(r"\.example(/|$)")


class Report:
    def __init__(self, release: bool) -> None:
        self.release = release
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def error(self, msg: str) -> None:
        self.errors.append(msg)

    def warn(self, msg: str) -> None:
        self.warnings.append(msg)

    def placeholder(self, msg: str) -> None:
        (self.error if self.release else self.warn)(msg)


def read(path: pathlib.Path) -> str:
    return path.read_text(encoding="utf-8").rstrip("\n")


def check_metadata(r: Report) -> None:
    for locale in LOCALES:
        d = META / locale
        for name in REQUIRED:
            if not (d / name).exists():
                r.error(f"{d.relative_to(ROOT)}/{name} がありません")
        for name, limit in LIMITS.items():
            p = d / name
            if not p.exists():
                continue
            text = read(p)
            if not text.strip():
                r.error(f"{p.relative_to(ROOT)} が空です")
            if len(text) > limit:
                r.error(f"{p.relative_to(ROOT)}: {len(text)} 文字（上限 {limit}）")
            if name in {"name.txt", "subtitle.txt", "keywords.txt", "promotional_text.txt"} and "\n" in text:
                r.error(f"{p.relative_to(ROOT)}: 改行を含められません")
            for pattern, why in FORBIDDEN:
                if pattern.search(text):
                    r.error(f"{p.relative_to(ROOT)}: {why}（{pattern.search(text).group(0)}）")
        # キーワード
        kp = d / "keywords.txt"
        if kp.exists():
            words = read(kp).split(",")
            if any(w != w.strip() for w in words):
                r.warn(f"{kp.relative_to(ROOT)}: カンマ前後の空白は文字数の無駄です")
            lowered = [w.strip().lower() for w in words]
            dup = sorted({w for w in lowered if lowered.count(w) > 1})
            if dup:
                r.error(f"{kp.relative_to(ROOT)}: 重複キーワード {dup}")
            if any(not w for w in lowered):
                r.error(f"{kp.relative_to(ROOT)}: 空のキーワードがあります")
            title = (read(d / "name.txt") + " " + read(d / "subtitle.txt")).lower() if (d / "name.txt").exists() else ""
            in_title = [w for w in lowered if w and re.search(rf"(?<![\w]){re.escape(w)}(?![\w])", title)]
            if in_title:
                r.warn(f"{kp.relative_to(ROOT)}: 名前/サブタイトルと重複（検索対象に既に含まれる）: {in_title}")
        # URL
        for name in URL_FILES:
            p = d / name
            if not p.exists():
                continue
            url = read(p).strip()
            if not url.startswith("https://"):
                r.error(f"{p.relative_to(ROOT)}: https の URL を指定してください: {url}")
            if PLACEHOLDER_URL.search(url) or PLACEHOLDER.search(url):
                r.placeholder(f"{p.relative_to(ROOT)}: 仮の URL のままです: {url}")

    # カテゴリ
    cat = META / "primary_category.txt"
    if not cat.exists() or read(cat) not in VALID_CATEGORIES:
        r.error("metadata/primary_category.txt は GAMES であること")
    for name in ["primary_first_sub_category.txt", "primary_second_sub_category.txt"]:
        p = META / name
        if p.exists() and read(p) not in VALID_GAME_SUBCATEGORIES:
            r.error(f"metadata/{name}: 不正なサブカテゴリ {read(p)}")
    cp = META / "copyright.txt"
    if not cp.exists() or not re.match(r"^20\d\d ", read(cp)):
        r.error("metadata/copyright.txt は「<年> <権利者名>」の形式で記入すること")

    # 審査メモ
    notes = META / "review_information" / "notes.txt"
    if not notes.exists():
        r.error("metadata/review_information/notes.txt がありません")
    elif len(read(notes)) > REVIEW_NOTES_MAX:
        r.error(f"審査メモが {len(read(notes))} 文字（上限 {REVIEW_NOTES_MAX}）")


def design_products() -> dict[str, int]:
    """DESIGN.md §13 の表から Product ID → 価格(円)。"""
    out = {}
    for line in DESIGN.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^\|\s*(com\.velstria\.game\.[\w.]+)\s*\|.*\|\s*([\d,]+)\s*\|\s*$", line)
        if m:
            out[m.group(1)] = int(m.group(2).replace(",", ""))
    return out


def service_products() -> dict[str, int]:
    """StoreKitService.swift の gemProducts / premiumPassProductID。"""
    text = STOREKIT_SERVICE.read_text(encoding="utf-8")
    out = {}
    for m in re.finditer(r'productID:\s*"([^"]+)".*?referencePriceJPY:\s*(\d+)', text):
        out[m.group(1)] = int(m.group(2))
    m = re.search(r'premiumPassProductID\s*=\s*"([^"]+)"', text)
    if m:
        out[m.group(1)] = -1
    return out


def check_iap(r: Report) -> None:
    data = json.loads(IAP_JSON.read_text(encoding="utf-8"))
    products = data["products"]
    ids = [p["product_id"] for p in products]
    if len(set(ids)) != len(ids):
        r.error("iap_products.json: product_id が重複しています")
    design = design_products()
    service = service_products()
    if set(ids) != set(design):
        r.error(f"iap_products.json と DESIGN.md §13 の商品が一致しません: "
                f"json のみ {sorted(set(ids) - set(design))} / DESIGN のみ {sorted(set(design) - set(ids))}")
    if set(ids) != set(service):
        r.error(f"iap_products.json と StoreKitService.swift の商品が一致しません: "
                f"json のみ {sorted(set(ids) - set(service))} / Swift のみ {sorted(set(service) - set(ids))}")
    ref_names = set()
    for p in products:
        pid = p["product_id"]
        if p["type"] not in {"consumable", "non_consumable"}:
            r.error(f"{pid}: type は consumable / non_consumable（v1.0 は自動更新サブスクなし）")
        if pid in design and design[pid] != p["price_jpy"]:
            r.error(f"{pid}: 価格 {p['price_jpy']} 円が DESIGN.md §13 の {design[pid]} 円と一致しません")
        if service.get(pid, -1) >= 0 and service[pid] != p["price_jpy"]:
            r.error(f"{pid}: 価格 {p['price_jpy']} 円が StoreKitService の参考価格 {service[pid]} 円と一致しません")
        if pid.startswith("com.bitcoinpay.velstria.gem."):
            expected = int(pid.rsplit(".", 1)[1])
            if p["paid_gems"] != expected or p["type"] != "consumable":
                r.error(f"{pid}: 有償ジェム数/種別が Product ID と一致しません")
        if len(p["reference_name"]) > 64 or p["reference_name"] in ref_names:
            r.error(f"{pid}: 参照名は 64 文字以内で一意にすること")
        ref_names.add(p["reference_name"])
        for locale in LOCALES:
            loc = p["localizations"].get(locale)
            if not loc:
                r.error(f"{pid}: {locale} のローカライズがありません")
                continue
            if not 2 <= len(loc["display_name"]) <= IAP_NAME_MAX:
                r.error(f"{pid} [{locale}] 表示名 {len(loc['display_name'])} 文字（2〜{IAP_NAME_MAX}）")
            if not 1 <= len(loc["description"]) <= IAP_DESC_MAX:
                r.error(f"{pid} [{locale}] 説明 {len(loc['description'])} 文字（1〜{IAP_DESC_MAX}）")
    doc = (APPSTORE / "in_app_purchases.md").read_text(encoding="utf-8")
    for pid in ids:
        if pid not in doc:
            r.error(f"docs/appstore/in_app_purchases.md に {pid} の記載がありません")

    # StoreKit 構成ファイル（app-services 担当）に商品があれば ID・種別を突き合わせる
    if STOREKIT_CONFIG.exists():
        try:
            sk = json.loads(STOREKIT_CONFIG.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            r.error(f"Velstria.storekit を読めません: {e}")
            return
        sk_types = {x.get("productID"): x.get("type") for x in sk.get("products", [])}
        if not sk_types:
            r.warn("Velstria.storekit に商品がまだ登録されていません（Xcode での課金テストに必要）")
        else:
            type_map = {"consumable": "Consumable", "non_consumable": "NonConsumable"}
            for p in products:
                got = sk_types.get(p["product_id"])
                if got is None:
                    r.error(f"Velstria.storekit に {p['product_id']} がありません")
                elif got != type_map[p["type"]]:
                    r.error(f"Velstria.storekit の {p['product_id']} の種別 {got} が {type_map[p['type']]} ではありません")


def check_placeholders(r: Report) -> None:
    for base in [APPSTORE, LEGAL]:
        for p in sorted(base.rglob("*")):
            if p.is_dir() or p.suffix not in {".md", ".txt", ".json"}:
                continue
            found = sorted(set(PLACEHOLDER.findall(p.read_text(encoding="utf-8"))))
            if found:
                r.placeholder(f"{p.relative_to(ROOT)}: 未記入のプレースホルダ {', '.join(found)}")


def main() -> int:
    release = "--release" in sys.argv[1:]
    r = Report(release)
    check_metadata(r)
    check_iap(r)
    check_placeholders(r)
    for w in r.warnings:
        print(f"warning: {w}")
    for e in r.errors:
        print(f"error: {e}", file=sys.stderr)
    if r.errors:
        print(f"{len(r.errors)} 件のエラー", file=sys.stderr)
        return 1
    mode = "提出直前モード" if release else "通常モード（プレースホルダは警告のみ。提出前に --release で確認）"
    print(f"ok: App Store メタデータの検証に合格（{mode}、警告 {len(r.warnings)} 件）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
