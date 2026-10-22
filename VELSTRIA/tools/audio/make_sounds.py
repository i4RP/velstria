"""音を作り直す（出来た分から docs/audio/SOURCES.md とクレジットも書き直す）。

python tools/audio/make_sounds.py H029 H034            # ヒーロー固有の音（tools/audio/heroes/h0xx.py）
python tools/audio/make_sounds.py common weapons ui    # 共通の音・武器ごとの組・画面の音など（tools/audio/sets/<名前>.py）

各モジュールは build() で sfxlib.write を呼ぶ。書いた音の記録は records/<名前>.json（どの素材をどう加工したか）。
素材の置き場所は環境変数 SONNISS_CACHE（worktree どうしで共有できる）。
"""
import importlib
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import build_audio as B  # noqa: E402
import sfxlib as L  # noqa: E402


def module_name(n):
    return ("heroes." + n.lower()) if n.upper().startswith("H0") else ("sets." + n.lower())


def record_name(n):
    return n.upper() if n.upper().startswith("H0") else n.lower()


def main(names):
    for n in names:
        print(n)
        importlib.import_module(module_name(n)).build()
        if n.upper().startswith("H0"):
            hero = n.upper()
            # v1（skill_sounds.py）の同じヒーローの命中の音（揺らぎの番号なし）は消す（揺らぎと一緒に読まれないように）
            for f in os.listdir(L.OUT):
                if f.startswith(f"skill_{hero}_") and f.endswith("_hit.caf"):
                    os.remove(os.path.join(L.OUT, f))
        L.save(record_name(n))
    B.write_doc()


if __name__ == "__main__":
    main(sys.argv[1:])
