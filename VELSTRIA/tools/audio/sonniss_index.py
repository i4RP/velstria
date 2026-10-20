"""Sonniss の写し（archive.org の sonniss-gdc-<年>-game-audio-bundle-normalized）の全ファイルの目録を作る。

python tools/audio/sonniss_index.py        # <置き場所>/index_all.tsv（年 \t 大きさ \t 年の下の相対パス。flac と wav があれば flac）
目録はファイル名だけ（素材は落とさない）。sonniss_lib.find が、手元に無い素材をここから 1 ファイルずつ落とす。
ライセンス: https://sonniss.com/gdc-bundle-license/（無料・商用可・帰属不要。素材のまま再配布しない。AI の学習に使わない）
"""
import json
import os
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(__file__))
import sonniss_lib as S  # noqa: E402

YEARS = ["2015", "2016", "2017", "2018", "2019", "2020", "2023", "2024", "2026"]


def main():
    os.makedirs(S.ROOT, exist_ok=True)
    n = 0
    with open(S.INDEX, "w", encoding="utf-8", newline="\n") as out:
        for year in YEARS:
            meta = json.load(urllib.request.urlopen(f"https://archive.org/metadata/{S.item(year)}", timeout=300))
            stems = {}
            for f in meta.get("files", []):
                name = f["name"]
                if "/" not in name or not name.lower().endswith((".flac", ".wav")):
                    continue
                stem = name.rsplit(".", 1)[0]
                if stem not in stems or name.lower().endswith(".flac"):
                    stems[stem] = f
            for stem in sorted(stems):
                f = stems[stem]
                out.write(f"{year}\t{int(f.get('size', 0))}\t{f['name']}\n")
                n += 1
            print(year, len(stems))
    print("total", n, "->", S.INDEX)


if __name__ == "__main__":
    main()
