#!/usr/bin/env python3
"""App Store Connect 提出用メタデータ（docs/appstore/）の文字数・整合性を検証する。

usage（リポジトリの VELSTRIA/ で）:
    python3 tools/validate_appstore_metadata.py            # 形式・文字数・課金 ID の整合（プレースホルダは警告）
    python3 tools/validate_appstore_metadata.py --archive  # アーカイブ時: アプリに埋め込まれるプレースホルダ・仮 URL はエラー
    python3 tools/validate_appstore_metadata.py --release  # 提出直前: プレースホルダ・仮 URL が残っていればすべてエラー
    python3 tools/validate_appstore_metadata.py --release --check-urls
        # 上に加えて公開 URL を実際に取得する（ネットワークが必要。production の提出前チェック専用。
        #   アーカイブ・TestFlight では使わない）

--check-urls:
  metadata/<locale>/ の privacy_url / support_url / marketing_url と FeatureFlags.swift のプライバシーポリシー・利用規約 URL を
  GET し、リダイレクト（308 を含む）をたどった最終応答が https の HTTP 200 であることを確認する（タイムアウト 15 秒、
  通信エラー・5xx・429 は Retry-After か 5 秒・10 秒待って計 3 回まで試行、失敗はまとめて報告）。日本語のパス・ドメインは
  %xx・xn-- に変換して取得する。仮の URL（*.example・{{...}}）は取得せずエラーにする。
  プライバシーポリシーが開けないと審査で 5.1.1 の却下になる。到達確認だけが誤判定で提出を止めるときは、
  環境変数 RELEASE_CHECK_ALLOW に urls を含めると（asc.mjs release-check と共通）エラーを警告に格下げする。

検査内容:
  - docs/appstore/metadata/<locale>/*.txt（fastlane deliver 互換の配置）の文字数上限
  - キーワードの重複・区切り、名前/サブタイトルとの重複（警告）
  - 他プラットフォーム名など審査で問題になる語の混入
  - URL が https であること
  - docs/appstore/iap_products.json と DESIGN.md §13・StoreKitService.swift・Velstria.storekit の商品 ID/価格の一致
  - App 内課金の表示名・説明の文字数
  - review_information/notes.txt の文字数
  - docs/legal/・docs/appstore/ に残ったプレースホルダ {{...}}
  - App/ のソース・リソースに残ったプレースホルダ {{...}} と仮ドメイン（*.example）
    （法定表示の事業者情報・サポート窓口・規約 URL。TestFlight を含むビルドに入るため --archive でもエラー）
"""
from __future__ import annotations

import http.client
import json
import os
import pathlib
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

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
    (re.compile(r"magic\s?chess|マジックチェス|auto\s?chess|mobile\s?legends|モバイルレジェンド|honor of kings|league of legends|wild rift|arena of valor|pok[eé]mon|ポケモン", re.I),
     "他社のゲーム名・商標（ガイドライン 5.2）"),
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
# アプリのソース中の仮ドメイン（support@velstria.example / https://velstria.example/...）
PLACEHOLDER_DOMAIN = re.compile(r"[A-Za-z0-9-]+\.example\b")
APP = ROOT / "App"
FEATURE_FLAGS = APP / "Core" / "FeatureFlags.swift"
APP_SUFFIXES = {".swift", ".plist", ".json", ".strings", ".xcprivacy"}
# アプリ内から開く公開 URL（FeatureFlags.swift の定数名）
FEATURE_FLAG_URLS = ["privacyPolicyURLJa", "privacyPolicyURLEn", "termsURLJa", "termsURLEn"]
URL_TIMEOUT = 15
# 通信エラー・5xx・429 の試行回数と待ち時間（秒。Retry-After があればそれに従い、上限 URL_RETRY_WAIT_MAX）
URL_ATTEMPTS = 3
URL_RETRY_WAIT = 5
URL_RETRY_WAIT_MAX = 30
URL_USER_AGENT = "Mozilla/5.0 (compatible; VELSTRIA-metadata-check/1.0)"


class Report:
    def __init__(self, release: bool, archive: bool = False) -> None:
        self.release = release
        self.archive = archive or release
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def error(self, msg: str) -> None:
        self.errors.append(msg)

    def warn(self, msg: str) -> None:
        self.warnings.append(msg)

    def placeholder(self, msg: str) -> None:
        (self.error if self.release else self.warn)(msg)

    def app_placeholder(self, msg: str) -> None:
        """アプリに埋め込まれる値（テスターや審査員が目にする）。"""
        (self.error if self.archive else self.warn)(msg)


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
        m = re.match(r"^\|\s*(com\.bitcoinpay\.velstria\.[\w.]+)\s*\|.*\|\s*([\d,]+)\s*\|\s*$", line)
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


def site_filled_keys() -> set[str]:
    """公開サイト（site/config.json）が ja・en の両方で値を持つキー。docs/legal の {{KEY}} はサイトのビルドで差し込まれる。"""
    cfg = ROOT.parent / "site" / "config.json"
    if not cfg.exists():
        return set()
    import json
    d = json.loads(cfg.read_text(encoding="utf-8"))
    return {k for k, v in d.get("ja", {}).items() if v and d.get("en", {}).get(k)}


def check_placeholders(r: Report) -> None:
    filled = {"{{" + k + "}}" for k in site_filled_keys()}
    for base in [APPSTORE, LEGAL]:
        for p in sorted(base.rglob("*")):
            if p.is_dir() or p.suffix not in {".md", ".txt", ".json"}:
                continue
            found = sorted(set(PLACEHOLDER.findall(p.read_text(encoding="utf-8"))) - (filled if base == LEGAL else set()))
            if found:
                r.placeholder(f"{p.relative_to(ROOT)}: 未記入のプレースホルダ {', '.join(found)}")


def check_app_placeholders(r: Report) -> None:
    """App/ に残った {{...}} と仮ドメイン。事業者情報・連絡先・URL は人が確定値を入れる（ここでは一覧を出すだけ）。"""
    for p in sorted(APP.rglob("*")):
        if p.is_dir() or p.suffix not in APP_SUFFIXES:
            continue
        for no, line in enumerate(p.read_text(encoding="utf-8", errors="replace").splitlines(), start=1):
            found = sorted(set(PLACEHOLDER.findall(line)) | set(m.group(0) for m in PLACEHOLDER_DOMAIN.finditer(line)))
            if found:
                r.app_placeholder(f"{p.relative_to(ROOT)}:{no}: アプリに未確定の値 {', '.join(found)}")


def feature_flag_url(text: str, name: str) -> str | None:
    """FeatureFlags.swift の `static let <name> = URL(string: "...")!` の文字列。"""
    m = re.search(rf'\b{name}\s*=\s*URL\(string:\s*"([^"]+)"\)', text)
    return m.group(1) if m else None


def check_privacy_urls(r: Report) -> None:
    """ASC に登録するプライバシーポリシー URL とアプリ内リンク（言語別）の一致。"""
    if not FEATURE_FLAGS.exists():
        r.error(f"{FEATURE_FLAGS.relative_to(ROOT)} がありません")
        return
    text = FEATURE_FLAGS.read_text(encoding="utf-8")
    for locale, name in [("ja", "privacyPolicyURLJa"), ("en-US", "privacyPolicyURLEn")]:
        url = feature_flag_url(text, name)
        if not url:
            r.error(f"{FEATURE_FLAGS.relative_to(ROOT)}: {name} が見つかりません")
            continue
        meta = META / locale / "privacy_url.txt"
        if meta.exists() and read(meta).strip() != url:
            r.error(f"{meta.relative_to(ROOT)}（{read(meta).strip()}）と FeatureFlags.{name}（{url}）が一致しません")


def public_urls() -> dict[str, list[str]]:
    """到達確認する URL → 記載箇所（同じ URL は 1 回だけ取得する）。"""
    out: dict[str, list[str]] = {}
    for locale in LOCALES:
        for name in URL_FILES:
            p = META / locale / name
            if p.exists() and read(p).strip():
                out.setdefault(read(p).strip(), []).append(str(p.relative_to(ROOT)))
    if FEATURE_FLAGS.exists():
        text = FEATURE_FLAGS.read_text(encoding="utf-8")
        for name in FEATURE_FLAG_URLS:
            url = feature_flag_url(text, name)
            if url:
                out.setdefault(url, []).append(f"FeatureFlags.{name}")
    return out


class _FollowRedirects(urllib.request.HTTPRedirectHandler):
    """308 もたどる（urllib が 308 に対応したのは Python 3.11 から。macOS 標準の 3.9 で手元実行したとき、
    .html の除去・末尾スラッシュの正規化を 308 で返すホスティングを誤ってエラーにしないため）。"""

    http_error_308 = urllib.request.HTTPRedirectHandler.http_error_302

    def redirect_request(self, req, fp, code, msg, headers, newurl):  # noqa: ANN001
        # 308 は 307 と同じくメソッドを変えないリダイレクト（ここでは GET だけを送る）
        return super().redirect_request(req, fp, 307 if code == 308 else code, msg, headers, newurl)


_URL_OPENER = urllib.request.build_opener(_FollowRedirects)


def ascii_url(url: str) -> str:
    """日本語のホスト名・パスや空白を含む URL を、送信できる ASCII の形にする（%xx 済みの部分はそのまま）。"""
    parts = urllib.parse.urlsplit(url)
    netloc = parts.netloc
    if not netloc.isascii():  # 日本語ドメインは IDNA（xn--）に変換する
        host = (parts.hostname or "").encode("idna").decode("ascii")
        netloc = host + (f":{parts.port}" if parts.port else "")
    path = urllib.parse.quote(parts.path, safe="/%:@!$&'()*+,;=~")
    query = urllib.parse.quote(parts.query, safe="/%:@!$&'()*+,;=?~")
    return urllib.parse.urlunsplit((parts.scheme, netloc, path, query, ""))


def retry_wait(e: Exception | None, attempt: int) -> float:
    """再試行までの秒数。Retry-After（秒）があればそれに従い（上限 URL_RETRY_WAIT_MAX）、無ければ回数に応じて延ばす。"""
    after = e.headers.get("Retry-After") if isinstance(e, urllib.error.HTTPError) and e.headers else None
    if after and after.strip().isdigit():
        return min(float(after.strip()), URL_RETRY_WAIT_MAX)
    return URL_RETRY_WAIT * attempt


def fetch_url(url: str) -> str | None:
    """URL を取得し、問題があれば理由を返す（正常なら None。例外は外に出さない）。
    通信エラー・5xx・429 は待ってから再試行する（計 URL_ATTEMPTS 回）。"""
    if PLACEHOLDER_URL.search(url) or PLACEHOLDER.search(url):
        return "仮の URL のままです（取得しない）"
    if not url.startswith("https://"):
        return "https の URL ではありません"
    try:
        req = urllib.request.Request(ascii_url(url), headers={"User-Agent": URL_USER_AGENT, "Accept": "text/html,*/*"})
    except (ValueError, UnicodeError) as e:  # ポート番号やホスト名が不正
        return f"URL の形式が不正です: {type(e).__name__}: {e}"
    problem = ""
    for attempt in range(1, URL_ATTEMPTS + 1):
        retryable: Exception | None = None
        try:
            # リダイレクト（301/302/303/307/308）をたどり、最終的な URL と状態を見る
            with _URL_OPENER.open(req, timeout=URL_TIMEOUT) as res:
                final = res.geturl()
                if res.status != 200:
                    return f"HTTP {res.status}（最終 URL {final}）"
                if not final.startswith("https://"):
                    return f"リダイレクト先が https ではありません: {final}"
                return None
        except urllib.error.HTTPError as e:
            problem = f"HTTP {e.code}（最終 URL {e.geturl()}）"
            if e.code < 500 and e.code != 429:
                return problem
            retryable = e
        except http.client.InvalidURL as e:  # 再試行しても変わらない
            return f"URL の形式が不正です: {e}"
        except (OSError, http.client.HTTPException) as e:  # URLError（DNS・TLS・接続拒否）・タイムアウト・途中で切れた応答
            problem = f"接続できません: {str(getattr(e, 'reason', None) or e) or type(e).__name__}"
        except Exception as e:  # noqa: BLE001 想定外の例外も理由として返す（他の URL の確認・まとめての報告・urls の格下げを続ける）
            return f"取得できません: {type(e).__name__}: {e}"
        if attempt < URL_ATTEMPTS:
            time.sleep(retry_wait(retryable, attempt))
    return f"{problem}（{URL_ATTEMPTS} 回試行）"


def check_url_reachability(r: Report) -> None:
    """公開 URL が実際に開けること（--check-urls）。失敗はまとめて報告する。"""
    allowed = "urls" in {s.strip() for s in os.environ.get("RELEASE_CHECK_ALLOW", "").split(",")}
    urls = public_urls()
    with ThreadPoolExecutor(max_workers=8) as pool:
        results = dict(zip(urls, pool.map(fetch_url, urls)))
    for url, problem in results.items():
        if problem is None:
            continue
        msg = f"URL を開けません: {url} — {problem}（{', '.join(urls[url])}）"
        if allowed:
            r.warn(f"{msg}（RELEASE_CHECK_ALLOW=urls のため続行）")
        else:
            r.error(msg)
    ok = sum(1 for p in results.values() if p is None)
    print(f"URL の到達確認: {ok} / {len(results)} 件が HTTP 200")


def main() -> int:
    release = "--release" in sys.argv[1:]
    archive = "--archive" in sys.argv[1:]
    check_urls = "--check-urls" in sys.argv[1:]
    r = Report(release, archive)
    check_metadata(r)
    check_iap(r)
    check_placeholders(r)
    check_app_placeholders(r)
    check_privacy_urls(r)
    if check_urls:
        check_url_reachability(r)
    for w in r.warnings:
        print(f"warning: {w}")
    for e in r.errors:
        print(f"error: {e}", file=sys.stderr)
    if r.errors:
        print(f"{len(r.errors)} 件のエラー", file=sys.stderr)
        return 1
    if release:
        mode = "提出直前モード"
    elif archive:
        mode = "アーカイブモード（アプリ内のプレースホルダはエラー、メタデータ・法務文書は警告）"
    else:
        mode = "通常モード（プレースホルダは警告のみ。提出前に --release で確認）"
    if check_urls:
        mode += "・URL の到達確認あり"
    print(f"ok: App Store メタデータの検証に合格（{mode}、警告 {len(r.warnings)} 件）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
