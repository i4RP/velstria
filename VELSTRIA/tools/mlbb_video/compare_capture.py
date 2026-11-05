"""fx-capture（ゲームの見下ろしのカメラ）の撮影と MLBB の画面収録の同じ時刻を上下に並べた比較の一覧を作る。

fx-capture の画は <名前>_<ミリ秒>.jpg（発動からの時刻。0, 66, 133, ...）。MLBB の段は --release（発動のコマ）から同じ秒数のコマ。
どちらもヒーローの周りを切り出して同じ高さへ拡大する（--crop-game / --crop-mlbb は x,y,w,h）。出力は %TEMP%\\mlbb_compare（MLBB のコマ入り。コミットしない）。

  py -3.12 tools/mlbb_video/compare_capture.py --capture <fxcapture>/mlbb/H032 --name s1 --video rec.mp4 --release 359 \
     --crop-game 470,180,170,150 --crop-mlbb 470,170,190,170 --out h032_game_s1.jpg
"""
import argparse
import os
import re
import tempfile

import cv2
import numpy as np


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--capture', required=True)
    p.add_argument('--name', required=True)
    p.add_argument('--video', required=True)
    p.add_argument('--release', type=int, required=True)
    p.add_argument('--crop-game', required=True)
    p.add_argument('--crop-mlbb', required=True)
    p.add_argument('--times', default='', help='使う時刻（ミリ秒、カンマ区切り。既定は撮影にあるもの全部）')
    p.add_argument('--tile', type=int, default=220)
    p.add_argument('--label', default='')
    p.add_argument('--out', required=True)
    a = p.parse_args()
    shots = {}
    for f in os.listdir(a.capture):
        m = re.fullmatch(re.escape(a.name) + r'_(\d+)\.jpg', f)
        if m:
            shots[int(m.group(1))] = os.path.join(a.capture, f)
    times = [int(t) for t in a.times.split(',')] if a.times else sorted(shots)
    gx, gy, gw, gh = [int(v) for v in a.crop_game.split(',')]
    mx, my, mw, mh = [int(v) for v in a.crop_mlbb.split(',')]
    th = int(a.tile*gh/gw)
    cap = cv2.VideoCapture(a.video)
    fps = cap.get(cv2.CAP_PROP_FPS) or 30
    top, bottom = [], []
    for t in times:
        im = cv2.imread(shots[t]) if t in shots else None
        g = im[gy:gy+gh, gx:gx+gw] if im is not None else np.zeros((gh, gw, 3), np.uint8)
        g = cv2.resize(g, (a.tile, th), interpolation=cv2.INTER_AREA)
        cv2.putText(g, f'Velstria {t/1000:.2f}s', (4, th-6), cv2.FONT_HERSHEY_SIMPLEX, .42, (0, 0, 0), 1, cv2.LINE_AA)
        n = a.release + int(round(t/1000*fps))
        cap.set(cv2.CAP_PROP_POS_FRAMES, n)
        ok, f = cap.read()
        m = f[my:my+mh, mx:mx+mw] if ok else np.zeros((mh, mw, 3), np.uint8)
        m = cv2.resize(m, (a.tile, int(a.tile*mh/mw)), interpolation=cv2.INTER_LANCZOS4)
        m = cv2.resize(m, (a.tile, th))
        cv2.putText(m, f'MLBB f{n} +{t/1000:.2f}s', (4, th-6), cv2.FONT_HERSHEY_SIMPLEX, .42, (255, 255, 255), 1, cv2.LINE_AA)
        top.append(m)
        bottom.append(g)
    per = 9
    rows = []
    for i in range(0, len(times), per):
        a_row, b_row = top[i:i+per], bottom[i:i+per]
        while len(a_row) < per:
            a_row.append(np.zeros_like(top[0]))
            b_row.append(np.zeros_like(top[0]))
        rows += [np.hstack(a_row), np.hstack(b_row)]
    sheet = np.vstack(rows)
    if a.label:
        bar = np.full((26, sheet.shape[1], 3), 32, np.uint8)
        cv2.putText(bar, a.label, (6, 18), cv2.FONT_HERSHEY_SIMPLEX, .55, (255, 255, 255), 1, cv2.LINE_AA)
        sheet = np.vstack([bar, sheet])
    out = a.out if os.path.isabs(a.out) else os.path.join(tempfile.gettempdir(), 'mlbb_compare', a.out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    cv2.imwrite(out, sheet, [cv2.IMWRITE_JPEG_QUALITY, 88])
    print(out)


if __name__ == '__main__':
    main()
