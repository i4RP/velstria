#!/usr/bin/env python3
"""正本マスター(velstria_master.json)からアプリ実行時に必要なテーブルだけを抽出する。

usage: python3 tools/gen_runtime_data.py
出力: Packages/VelstriaCore/Sources/VelstriaCore/Resources/master_runtime.json
"""
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = ROOT.parent / "VELSTRIA_復元版パッケージ" / "data" / "json" / "velstria_master.json"
DST = ROOT / "Packages" / "VelstriaCore" / "Sources" / "VelstriaCore" / "Resources" / "master_runtime.json"

ITEM_SPEC = ROOT / "tools" / "portraits" / "item_icons.json"

RUNTIME_TABLES = [
    "meta", "game_rules", "heroes", "skills", "equipment", "battle_spells",
    "runes", "effects", "cosmetics", "store",
]
DROP_FIELDS = {
    "effects": {"engine_notes", "meshy_prompt"},
}


def main() -> None:
    master = json.loads(SRC.read_text(encoding="utf-8"))
    out = {}
    for table in RUNTIME_TABLES:
        rows = master[table]
        drop = DROP_FIELDS.get(table, set())
        if isinstance(rows, list):
            rows = [{k: v for k, v in r.items() if k not in drop} for r in rows]
        if table == "equipment":
            # 装備名は item_icons.json の ja を正本とする（正本マスターは番号付きの仮名のため）
            names = {it["id"]: it["ja"] for it in json.loads(ITEM_SPEC.read_text(encoding="utf-8"))["items"]}
            rows = [{**r, "name_ja": names[r["item_id"]]} for r in rows]
        out[table] = rows
    DST.parent.mkdir(parents=True, exist_ok=True)
    DST.write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"wrote {DST.relative_to(ROOT)} ({DST.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
