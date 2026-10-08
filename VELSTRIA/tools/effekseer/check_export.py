#!/usr/bin/env python3
"""efkexport.py（純 Python の .efk 書き出し器）が、同梱済みの .efk とバイト一致するか確かめる。
usage: python3 tools/effekseer/check_export.py [hero…]    （既定は build_all.HEROES 全部）
各ヒーローの生成スクリプトを走らせ、build() の代わりに XML を捕まえて export_efk に通し、Effects/Effekseer/ の同名の .efk と比べる。
"""
import importlib
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "heroes"))
import efkgen  # noqa: E402
import efkexport  # noqa: E402
from build_all import HEROES  # noqa: E402


def classify(got, ref):
    """'exact' = 完全一致 / 'ulp' = 角度の float32 が最大 2 ulp ずれただけ（構造・長さ・他の値は一致）/ 'diff'。"""
    if got == ref:
        return "exact", 0
    if len(got) != len(ref):
        return "diff", first_diff(got, ref)
    # 4 バイト境界は不明なので、差のあるバイトを含む 4 バイト窓のどれかが「float として 2 ulp 以内」なら許す
    diffs = [i for i in range(len(got)) if got[i] != ref[i]]
    j = 0
    while j < len(diffs):
        i = diffs[j]
        ok = False
        for start in range(i - 3, i + 1):
            if start < 0 or start + 4 > len(got):
                continue
            a = struct.unpack_from("<I", got, start)[0]
            b = struct.unpack_from("<I", ref, start)[0]
            if abs(a - b) <= 2 and (a ^ b) & 0x80000000 == 0 and 1e-9 < abs(struct.unpack_from("<f", ref, start)[0]) < 1e4:
                ok = True
                # この窓に入る差分バイトを読み飛ばす
                while j < len(diffs) and diffs[j] < start + 4:
                    j += 1
                break
        if not ok:
            return "diff", i
    return "ulp", 0


def first_diff(a, b):
    for i in range(min(len(a), len(b))):
        if a[i] != b[i]:
            return i
    return min(len(a), len(b))


def main():
    want = [a.lower() for a in sys.argv[1:]] or HEROES
    captured = {}

    def fake_build(self, out_dir=None, keep_project=False):
        captured[self.name] = self.xml()
        return self.name + ".efk"

    efkgen.Effect.build = fake_build
    import io, contextlib
    for h in want:
        m = importlib.import_module(h)
        with contextlib.redirect_stdout(io.StringIO()):
            if hasattr(m, "build"):
                for fx in m.build():
                    fx.build()
            else:
                m.build_all()
    ok = near = bad = missing = 0
    for name, xml in sorted(captured.items()):
        path = os.path.join(efkgen.OUT, name + ".efk")
        got = efkexport.export_efk(xml)
        if not os.path.exists(path):
            missing += 1
            continue
        ref = open(path, "rb").read()
        kind, d = classify(got, ref)
        if kind == "exact":
            ok += 1
        elif kind == "ulp":
            near += 1
        else:
            bad += 1
            print(f"MISMATCH {name}: 出力 {len(got)} B / 同梱 {len(ref)} B / 最初の差 {d:#x}")
    print(f"完全一致 {ok} / 角度の丸め誤差のみ（最大 2 ulp） {near} / 不一致 {bad} / 同梱なし {missing}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
