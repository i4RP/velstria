"""MLBB の画面収録のコマと Velstria のコンタクトシート（preview_clip.py の出力）を上下に並べた比較の一覧を作る。

MLBB の段: 動画の t0 秒から step コマおきに n コマ、--crop（x,y,w,h、1108×512 の画素）を切り出して各タイルの大きさへ拡大。
Velstria の段: --velstria の PNG（preview_clip.py のシート。複数なら段を重ねる）を同じ幅へ縮める。
出力は一時フォルダ（既定 %TEMP%\\mlbb_compare）。MLBB のコマを含むのでリポジトリに入れない・転載しない。

  py -3.12 tools/mlbb_video/compare_sheet.py --video rec.mp4 --t0 3.5 --n 8 --step 3 --crop 485,180,140,130 \
     --velstria sheet_side.png,sheet_top.png --label "run: MLBB vid7 3.5s / Velstria run_h032" --out run.jpg
"""
import argparse
import os
import tempfile

import cv2
import numpy as np


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--video', required=True)
    p.add_argument('--t0', type=float, default=0.0)
    p.add_argument('--n', type=int, default=8)
    p.add_argument('--step', type=int, default=3)
    p.add_argument('--frames', default='', help='MLBB のコマ番号の列（0 始まり。--t0/--step より優先）')
    p.add_argument('--crop', required=True)
    p.add_argument('--velstria', default='')
    p.add_argument('--label', default='')
    p.add_argument('--tile', type=int, default=240)
    p.add_argument('--out', required=True)
    a = p.parse_args()
    x, y, w, h = [int(v) for v in a.crop.split(',')]
    cap = cv2.VideoCapture(a.video)
    fps = cap.get(cv2.CAP_PROP_FPS) or 30
    idx = [int(v) for v in a.frames.split(',')] if a.frames else [int(round(a.t0*fps))+i*a.step for i in range(a.n)]
    th = int(a.tile*h/w)
    tiles = []
    for n in idx:
        cap.set(cv2.CAP_PROP_POS_FRAMES, n)
        ok, f = cap.read()
        t = f[y:y+h, x:x+w] if ok else np.zeros((h, w, 3), np.uint8)
        t = cv2.resize(t, (a.tile, th), interpolation=cv2.INTER_LANCZOS4)
        cv2.putText(t, f'MLBB f{n} {n/fps:.2f}s', (4, th-6), cv2.FONT_HERSHEY_SIMPLEX, .42, (255, 255, 255), 1, cv2.LINE_AA)
        tiles.append(t)
    rows = [np.hstack(tiles)]
    W = rows[0].shape[1]
    for path in [s for s in a.velstria.split(',') if s]:
        im = cv2.imread(path)
        if im is None:
            continue
        rows.append(cv2.resize(im, (W, int(im.shape[0]*W/im.shape[1])), interpolation=cv2.INTER_AREA))
    if a.label:
        bar = np.full((26, W, 3), 32, np.uint8)
        cv2.putText(bar, a.label, (6, 18), cv2.FONT_HERSHEY_SIMPLEX, .55, (255, 255, 255), 1, cv2.LINE_AA)
        rows.insert(0, bar)
    out = a.out if os.path.isabs(a.out) else os.path.join(tempfile.gettempdir(), 'mlbb_compare', a.out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    cv2.imwrite(out, np.vstack(rows), [cv2.IMWRITE_JPEG_QUALITY, 88])
    print(out)


if __name__ == '__main__':
    main()
