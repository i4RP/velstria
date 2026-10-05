#!/usr/bin/env python3
"""マスターデータの日本語表示名オーバーレイ（App/Resources/master_ja.json）を生成・検証する。

usage（リポジトリの VELSTRIA/ で）:
    python3 tools/gen_master_ja.py           # 生成してから検証
    python3 tools/gen_master_ja.py --check   # 検証のみ（ファイルが最新か・対象 ID を網羅しているか）

入力: Packages/VelstriaCore/Sources/VelstriaCore/Resources/master_runtime.json
出力: App/Resources/master_ja.json（フラットな {id: 日本語表示名}）

master_runtime.json の name_ja の一部は開発用の仮名（「城門の誓衛アルデン HeroSkin 1」
「Alden式・一閃」「星環シフト2」など）のまま。マスター（仕様パッケージ由来・英語オーバーレイの翻訳キー）は
変えずに、日本語表示のときだけこのオーバーレイで置き換える（App/Core/Localization.swift の MasterText）。

キー:
    <cosmetic_id>   コスメ名（「星鍛のアルデン」「星弦の帰還 I」）
    <sku>           ストア商品名（コスメ商品のみ。付与コスメと同じ名前）
    <skill_id>      Skill1〜3 の共通名（「アルデン式・一閃」「星環シフト」「境界制圧」）

英語オーバーレイ（tools/gen_master_en.py）と同じ規則で名付ける（汎用コスメはヒーローの二つ名をテーマにする）。
想定外の文型が現れたら生成を失敗させる（仮名のまま出荷しないため）。
"""
from __future__ import annotations

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = ROOT / "Packages" / "VelstriaCore" / "Sources" / "VelstriaCore" / "Resources" / "master_runtime.json"
DST = ROOT / "App" / "Resources" / "master_ja.json"

MAX_NAME_LEN = 16

# ヒーロー: hero_id → (短い名前, コスメのテーマ語)。テーマ語は表示名の二つ名部分（英語オーバーレイのテーマと対応）。
HEROES: dict[str, tuple[str, str]] = {
    "H001": ("アルデン", "誓衛"),
    "H002": ("リラ", "星弦"),
    "H003": ("フィリエル", "月弓"),
    "H004": ("ミレア", "潮祈"),
    "H005": ("ヴォス", "黒雷"),
    "H006": ("セレン", "月灯"),
    "H007": ("ガルク", "岩脈"),
    "H008": ("ニア", "風標"),
    "H009": ("オリン", "機巧"),
    "H010": ("テッサ", "焔冠"),
    "H011": ("ルーク", "鉄翼"),
    "H012": ("エリネ", "玻璃歌"),
    "H013": ("ダガン", "獣刻"),
    "H014": ("シオ", "霧歩"),
    "H015": ("ヴァルカ", "戦鐘"),
    "H016": ("イリス", "白環"),
    "H017": ("モルド", "深淵鎖"),
    "H018": ("セリア", "花星"),
    "H019": ("ブラム", "砦砕"),
    "H020": ("ユナ", "光矢"),
    "H021": ("キロス", "時砂"),
    "H022": ("レア", "蒼爪"),
    "H023": ("トレン", "雷槍"),
    "H024": ("ノア", "夢織"),
}

# ヒーロー専用スキン（hero_id, 番号）→ スキン名（英語オーバーレイの HERO_SKINS と対応）
HERO_SKINS = {
    ("H001", 1): "星鍛のアルデン",          # Starforged Alden
    ("H001", 2): "蝕の哨兵アルデン",        # Eclipse Sentinel Alden
    ("H001", 3): "極光の城塞アルデン",      # Aurora Bastion Alden
    ("H007", 1): "黒曜の巨人ガルク",        # Obsidian Titan Garruk
    ("H007", 2): "溶岩脈のガルク",          # Magma Vein Garruk
    ("H007", 3): "水晶の巨像ガルク",        # Crystal Colossus Garruk
    ("H013", 1): "霜牙のダガン",            # Frostfang Dagan
    ("H013", 2): "熾火纏いのダガン",        # Emberhide Dagan
    ("H013", 3): "天獣のダガン",            # Celestial Beast Dagan
    ("H019", 1): "鉄の攻城兵ブラム",        # Iron Siege Bram
    ("H019", 2): "雷の破城槌ブラム",        # Thunder Ram Bram
    ("H019", 3): "星墜の破砕者ブラム",      # Starfall Breaker Bram
}
# 汎用コスメの種類（英語: Recall / Arrival / Emote / Frame / Takedown。
# アプリの種別名 CollectionStyle.cosmeticTypeName「帰還演出・出現演出・エモート・アバターフレーム・キル演出」に合わせる）
COSMETIC_TYPES = {
    "Recall": "帰還",
    "Spawn": "出現",
    "Emote": "エモート",
    "AvatarFrame": "フレーム",
    "KillEffect": "キル演出",
}
ROMAN = {1: "I", 2: "II", 3: "III", 4: "IV", 5: "V", 6: "VI", 7: "VII", 8: "VIII", 9: "IX", 10: "X"}

COSMETIC_PATTERN = re.compile(r"^(?P<hero>.+) (?P<type>[A-Za-z]+) (?P<no>\d+)$")
SKILL1_PATTERN = re.compile(r"^(?P<code>[A-Za-z]+)式・一閃$")
SKILL2_PATTERN = re.compile(r"^星環シフト\d+$")
SKILL3_PATTERN = re.compile(r"^境界制圧\d+$")
SKILL1_JA = "{name}式・一閃"
SKILL2_JA = "星環シフト"
SKILL3_JA = "境界制圧"

# 日本語表示に残してはいけない開発用の語（コスメ種別の英語名・ラテン文字のコード名）
LATIN = re.compile(r"[A-Za-z]{2,}")


class GenerationError(Exception):
    pass


def build(master: dict) -> dict[str, str]:
    out: dict[str, str] = {}

    def put(key: str, value: str) -> None:
        if key in out:
            raise GenerationError(f"キーが重複しています: {key}")
        out[key] = value

    heroes = {h["hero_id"]: h for h in master["heroes"]}
    hero_by_display = {h["display_name_ja"]: hid for hid, h in heroes.items()}
    for hid, h in heroes.items():
        if hid not in HEROES:
            raise GenerationError(f"{hid}: 日本語名の表にありません: {h['display_name_ja']}")
        name, theme = HEROES[hid]
        if not h["display_name_ja"].endswith(name) or theme not in h["display_name_ja"]:
            raise GenerationError(f"{hid}: 表の名前 {name}/{theme} が表示名 {h['display_name_ja']} と一致しません")

    # スキル（共通アーキタイプ名の番号・コード名を外す。固有名はマスターのまま）
    for s in master["skills"]:
        sid = s["skill_id"]
        name_ja = s["name_ja"]
        short, _ = HEROES[s["hero_id"]]
        if (m := SKILL1_PATTERN.match(name_ja)):
            if m["code"] != heroes[s["hero_id"]]["code_name"]:
                raise GenerationError(f"{sid}: {name_ja} のヒーロー名が code_name と一致しません")
            put(sid, SKILL1_JA.format(name=short))
        elif SKILL2_PATTERN.match(name_ja):
            put(sid, SKILL2_JA)
        elif SKILL3_PATTERN.match(name_ja):
            put(sid, SKILL3_JA)
        elif LATIN.search(name_ja) or re.search(r"\d$", name_ja):
            raise GenerationError(f"{sid}: 想定外の仮名です: {name_ja}")

    # コスメ
    cosmetic_by_id: dict[str, str] = {}
    cosmetic_ja_by_id: dict[str, str] = {}
    for c in master["cosmetics"]:
        cid = c["cosmetic_id"]
        m = COSMETIC_PATTERN.match(c["name_ja"])
        if not m or m["type"] != c["type"]:
            raise GenerationError(f"{cid}: コスメ名の文型が想定外です: {c['name_ja']}")
        # ヒーロー専用スキン以外は hero_id が空なので、名前のヒーロー表示名からテーマを引く
        hid = hero_by_display.get(m["hero"])
        if hid is None or (c["hero_id"] and c["hero_id"] != hid):
            raise GenerationError(f"{cid}: コスメ名のヒーロー {m['hero']} が hero_id {c['hero_id']!r} と一致しません")
        no = int(m["no"])
        if c["type"] == "HeroSkin":
            key = (hid, no)
            if key not in HERO_SKINS:
                raise GenerationError(f"{cid}: スキン名の表にありません: {key}")
            name = HERO_SKINS[key]
        else:
            if c["type"] not in COSMETIC_TYPES:
                raise GenerationError(f"{cid}: 未対応のコスメ種別 {c['type']}")
            _, theme = HEROES[hid]
            name = f"{theme}の{COSMETIC_TYPES[c['type']]} {ROMAN[no]}"
        cosmetic_by_id[cid] = name
        cosmetic_ja_by_id[cid] = c["name_ja"]
        put(cid, name)

    # ストア商品（コスメ商品のみ。ヒーロー解放・バンドルはマスターの名前のまま）
    for st in master["store"]:
        if st["type"] != "Cosmetic":
            continue
        gid = st["grant_id"]
        if cosmetic_ja_by_id.get(gid) != st["name_ja"]:
            raise GenerationError(f"{st['sku']}: 商品名 {st['name_ja']} が付与コスメ {gid} の名前と一致しません")
        put(st["sku"], cosmetic_by_id[gid])

    return dict(sorted(out.items()))


def validate(master: dict, overlay: dict[str, str]) -> list[str]:
    errors: list[str] = []
    expected = {c["cosmetic_id"] for c in master["cosmetics"]}
    expected |= {s["sku"] for s in master["store"] if s["type"] == "Cosmetic"}
    expected |= {s["skill_id"] for s in master["skills"]
                 if SKILL1_PATTERN.match(s["name_ja"]) or SKILL2_PATTERN.match(s["name_ja"])
                 or SKILL3_PATTERN.match(s["name_ja"])}
    for key in sorted(expected - overlay.keys()):
        errors.append(f"未記入: {key}")
    for key in sorted(overlay.keys() - expected):
        errors.append(f"対象外のキー: {key}")
    seen: dict[str, str] = {}
    for c in master["cosmetics"]:
        name = overlay.get(c["cosmetic_id"])
        if name is None:
            continue
        if name in seen:
            errors.append(f"コスメ名が重複: {c['cosmetic_id']} と {seen[name]} → {name!r}")
        seen[name] = c["cosmetic_id"]
    for key, value in overlay.items():
        if not value.strip() or value != value.strip() or "  " in value:
            errors.append(f"空・余分な空白: {key} → {value!r}")
        if len(value) > MAX_NAME_LEN:
            errors.append(f"名前が長すぎます（{len(value)} > {MAX_NAME_LEN}）: {key} → {value!r}")
        # ローマ数字（I/II/III）以外のラテン文字は開発用の仮名の残り
        if LATIN.search(re.sub(r" [IVX]+$", "", value)):
            errors.append(f"ラテン文字が残っています: {key} → {value!r}")
    return errors


def render(overlay: dict[str, str]) -> str:
    return json.dumps(overlay, ensure_ascii=False, indent=2) + "\n"


def main() -> int:
    check_only = "--check" in sys.argv[1:]
    master = json.loads(SRC.read_text(encoding="utf-8"))
    try:
        overlay = build(master)
    except GenerationError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    text = render(overlay)
    if check_only:
        if not DST.exists():
            print(f"error: {DST.relative_to(ROOT)} がありません。python3 tools/gen_master_ja.py を実行してください",
                  file=sys.stderr)
            return 1
        errors = validate(master, json.loads(DST.read_text(encoding="utf-8")))
        if DST.read_text(encoding="utf-8") != text:
            errors.append(f"{DST.relative_to(ROOT)} が表・マスターと一致しません（再生成が必要）")
    else:
        DST.write_text(text, encoding="utf-8")
        print(f"wrote {DST.relative_to(ROOT)} ({len(overlay)} keys)")
        errors = validate(master, overlay)
    if errors:
        for e in errors:
            print(f"error: {e}", file=sys.stderr)
        print(f"{len(errors)} 件のエラー", file=sys.stderr)
        return 1
    print(f"ok: 日本語表示名オーバーレイ {len(overlay)} キー（コスメ・コスメ商品・共通スキル名）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
