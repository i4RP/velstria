#!/usr/bin/env python3
"""MLBB のコマと Velstria のコマ（Blender の描画）を同じ時刻・同じ大きさで並べた比較の一覧を作る（ヒーローのモーション合わせ）。

指定（例: tools/motion/h029-mlbb-compare.json）:
  {"videos": {"a": "ScreenRecording_....mp4", ...}, "box": [477, 173, 160, 160], "scale": 2.0,
   "stages": {"<段>": [{"label": "...", "mlbb": ["a", 秒], "clip": "<クリップ>", "at": 秒, "heading": 画面での向き}, ...]}}
  - MLBB の切り出しは box（足元が (556.6, 295) のヒーローの周り）を scale 倍。Tigreal の縮尺 62.3 px / 単位 を 2 倍 = 1 m 124.6 px。
  - Velstria のコマは tools/blender/preview_h029_motion.py --shots で build/<hero>-motion/compare/<段>/NN_game.png・NN_side.png に描く
    （戦闘の見下ろし 45° を同じ縮尺、横からの拡大）。
  - 動画は既定で %TEMP%\\mlbb_ref（--videos で変える）。**出力の画像はリポジトリに入れない**（MLBB の著作物を含む。build/ は管理外）。
使い方（VELSTRIA/ で）:
  py -3.12 tools/mlbb_video/motion_compare.py tools/motion/h029-mlbb-compare.json gait --shots build/h029-motion/compare
"""
import argparse
import json
import os
from pathlib import Path

import cv2
import numpy as np


def text(img, s, org, scale=0.5):
    cv2.putText(img, s, org, cv2.FONT_HERSHEY_SIMPLEX, scale, (0, 0, 0), 3, cv2.LINE_AA)
    cv2.putText(img, s, org, cv2.FONT_HERSHEY_SIMPLEX, scale, (255, 255, 255), 1, cv2.LINE_AA)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('spec')
    ap.add_argument('stage')
    ap.add_argument('--shots', required=True, help='Velstria のコマの置き場（<shots>/<段>/NN_game.png）')
    ap.add_argument('--videos', default=os.path.join(os.environ.get('TEMP', '/tmp'), 'mlbb_ref'))
    ap.add_argument('--out')
    ap.add_argument('--cols', type=int, default=2, help='1 段に並べる行の数（1 行 = MLBB・Velstria 見下ろし・Velstria 横）')
    a = ap.parse_args()
    spec = json.loads(Path(a.spec).read_text(encoding='utf-8'))
    rows = spec['stages'][a.stage]
    x, y, w, h = spec.get('box', [477, 173, 160, 160])
    k = spec.get('scale', 2.0)
    tw, th = int(w * k), int(h * k)
    caps = {}
    cells = []
    for i, r in enumerate(rows):
        tiles = []
        key, t = r['mlbb']
        if key not in caps:
            caps[key] = cv2.VideoCapture(str(Path(a.videos) / spec['videos'][key]))
        cap = caps[key]
        fps = cap.get(cv2.CAP_PROP_FPS) or 30
        n = int(round(t * fps))
        cap.set(cv2.CAP_PROP_POS_FRAMES, n)
        ok, fr = cap.read()
        crop = fr[y:y + h, x:x + w] if ok else np.zeros((h, w, 3), np.uint8)
        crop = cv2.resize(crop, (tw, th), interpolation=cv2.INTER_CUBIC)
        text(crop, f"MLBB {key} {n / fps:.2f}s", (4, 16))
        tiles.append(crop)
        for view in ('game', 'side'):
            p = Path(a.shots) / a.stage / f'{i:02d}_{view}.png'
            im = cv2.imread(str(p)) if p.exists() else None
            if im is None:
                im = np.full((th, tw, 3), 40, np.uint8)
            im = cv2.resize(im, (int(im.shape[1] * th / im.shape[0]), th))
            if r.get('clip'):
                text(im, f"Velstria {r['clip']} {r.get('at', 0):.2f}s" if view == 'game' else 'side', (4, 16), 0.42)
            tiles.append(im)
        cell = np.concatenate(tiles, axis=1)
        bar = np.full((22, cell.shape[1], 3), 24, np.uint8)
        text(bar, f"{i:02d} {r.get('label', '')}", (4, 16), 0.5)
        cells.append(np.concatenate([bar, cell], axis=0))
    cw = max(c.shape[1] for c in cells)
    cells = [np.pad(c, ((0, 0), (0, cw - c.shape[1]), (0, 0))) for c in cells]
    while len(cells) % a.cols:
        cells.append(np.zeros_like(cells[0]))
    lines = [np.concatenate(cells[j:j + a.cols], axis=1) for j in range(0, len(cells), a.cols)]
    sheet = np.concatenate(lines, axis=0)
    out = a.out or str(Path(a.shots) / f'{a.stage}.jpg')
    cv2.imwrite(out, sheet, [cv2.IMWRITE_JPEG_QUALITY, 85])
    print(out, sheet.shape)


if __name__ == '__main__':
    main()
