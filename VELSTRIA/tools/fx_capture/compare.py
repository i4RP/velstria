"""スキル演出の比較の一覧画像（MLBB の画面収録のコマ と Velstria の撮影 FXCapture を、発動からの時刻でそろえて並べる）。

usage:
  python compare.py --out sheet.png --mlbb <コマのフォルダ> --t0 <発動のコマ番号> \
      --col 変更前=<撮影のフォルダ>/<ヒーロー> --col 変更後=<撮影のフォルダ>/<ヒーロー> --slot ult [--times 0.1,0.2,0.33,0.5,0.75,1,1.4]

- MLBB のコマ n の時刻 = (n − 1) / 30 秒。発動のコマ（指を離したコマ）から offset 秒のコマを使う（30fps なので ±1 コマ = 33 ms）。
- Velstria の画は manifest.json の requested（要求の時刻）でそろえる。実際の時刻（actual）を画の隅に書く。
- 出力は手元だけに置く（MLBB の画面収録は著作物。リポジトリに入れない）。
"""
import argparse
import json
import os

from PIL import Image, ImageDraw


def label(im, text):
    d = ImageDraw.Draw(im)
    w = 8 + 7 * len(text)
    d.rectangle((0, 0, w, 20), fill=(0, 0, 0))
    d.text((4, 4), text, fill=(255, 255, 0))
    return im


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--mlbb", help="MLBB のコマのフォルダ（NNNN.png）")
    ap.add_argument("--t0", type=int, help="MLBB の発動のコマ番号")
    ap.add_argument("--col", action="append", default=[], help="名前=撮影のフォルダ（manifest.json のある所）")
    ap.add_argument("--slot", required=True, help="s1 / s2 / ult / s2r（再使用）")
    ap.add_argument("--times", default="0.1,0.2,0.33,0.5,0.75,1.0,1.4")
    ap.add_argument("--width", type=int, default=554, help="1 枚の幅（px）")
    a = ap.parse_args()
    times = [float(x) for x in a.times.split(",")]
    cols = []
    if a.mlbb and a.t0:
        cols.append(("MLBB", None))
    for c in a.col:
        name, path = c.split("=", 1)
        cols.append((name, path))
    W = a.width
    H = int(W * 512 / 1108)
    sheet = Image.new("RGB", (W * len(cols), (H + 2) * len(times)), (20, 20, 20))
    for ci, (name, path) in enumerate(cols):
        manifest = None
        if path:
            mp = os.path.join(path, "manifest.json")
            if os.path.exists(mp):
                with open(mp, encoding="utf-8") as f:
                    manifest = json.load(f)
        for ri, t in enumerate(times):
            im = None
            text = f"{name} t={t:.2f}"
            if path is None:
                n = a.t0 + round(t * 30)
                fp = os.path.join(a.mlbb, f"{n:04d}.png")
                if os.path.exists(fp):
                    im = Image.open(fp).convert("RGB")
                    text = f"MLBB f{n} +{(n - a.t0) / 30:.2f}s"
            elif manifest:
                recast = a.slot.endswith("r")
                slot = a.slot[:-1] if recast else a.slot
                best = None
                for s in manifest["shots"]:
                    if s["slot"] != slot or s["cast"] != (1 if recast else 0):
                        continue
                    if best is None or abs(s["requested"] - t) < abs(best["requested"] - t):
                        best = s
                if best and abs(best["requested"] - t) < 0.06:
                    fp = os.path.join(path, best["file"])
                    if os.path.exists(fp):
                        im = Image.open(fp).convert("RGB")
                        text = f"{name} +{best['actual']:.2f}s"
            if im is None:
                im = Image.new("RGB", (1108, 512), (40, 0, 0))
                text += " (なし)"
            im = im.resize((W, int(W * im.height / im.width)))
            im = im.crop((0, 0, W, min(H, im.height)))
            label(im, text)
            sheet.paste(im, (ci * W, ri * (H + 2)))
    sheet.save(a.out)
    print(a.out, sheet.size)


if __name__ == "__main__":
    main()
