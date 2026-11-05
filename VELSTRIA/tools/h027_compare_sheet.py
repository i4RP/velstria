"""H027 の比較の一覧: MLBB のコマ（切り出し）と、同じ時刻・同じ向きの Velstria のクリップ（ゲームの見下ろし + 右横の拡大）を 1 行に並べる。

  python tools/h027_compare_sheet.py shots PLAN.json         # Blender に渡すショットの一覧（PLAN の隣に *_shots.json）
  Blender -b -P tools/blender/compare_h027_mlbb.py -- --shots PLAN_shots.json
  python tools/h027_compare_sheet.py sheet PLAN.json OUT.jpg  # 一覧の画像

PLAN = {"frames": {"b": "<MLBB のコマのフォルダ>"}, "render": "<描いた画像のフォルダ>",
        "rows": [{"label": "A 払い 打撃", "mlbb": ["b", 727, [x, y, w, h]], "clip": "h027_sweep", "frame": 10, "heading": 60}]}
MLBB のコマ・一覧は著作物を含むので build/ か一時フォルダに置き、リポジトリに入れない（tools/mlbb_video/README.md）。
依存: numpy・opencv-python-headless。
"""
import json
import sys
from pathlib import Path

import cv2
import numpy as np

H = 300


def shots(plan_path):
    plan = json.loads(Path(plan_path).read_text(encoding='utf-8'))
    out = Path(plan['render'])
    items = []
    for i, r in enumerate(plan['rows']):
        base = dict(clip=r['clip'], frame=r['frame'])
        items.append(dict(base, out=str(out / f'{i:03d}_game.png'), heading=r.get('heading', 0), el=r.get('el', 43)))
        items.append(dict(base, out=str(out / f'{i:03d}_side.png'), view='side'))
    dst = Path(plan_path).with_name(Path(plan_path).stem + '_shots.json')
    dst.write_text(json.dumps(items, indent=1), encoding='utf-8')
    print(dst)


def fit(img, h=H):
    s = h / img.shape[0]
    return cv2.resize(img, (max(1, int(img.shape[1] * s)), h), interpolation=cv2.INTER_CUBIC)


def text(img, s, y=18, scale=0.55):
    cv2.putText(img, s, (6, y), cv2.FONT_HERSHEY_SIMPLEX, scale, (0, 0, 0), 3, cv2.LINE_AA)
    cv2.putText(img, s, (6, y), cv2.FONT_HERSHEY_SIMPLEX, scale, (255, 255, 255), 1, cv2.LINE_AA)


def sheet(plan_path, out_path):
    plan = json.loads(Path(plan_path).read_text(encoding='utf-8'))
    render = Path(plan['render'])
    rows = []
    for i, r in enumerate(plan['rows']):
        video, n, box = r['mlbb']
        frame = cv2.imread(str(Path(plan['frames'][video]) / f'{n:04d}.jpg'))
        x, y, w, h = box
        m = fit(frame[y:y + h, x:x + w])
        text(m, f"MLBB {video}{n} ({n / 30:.2f}s)")
        game = fit(cv2.imread(str(render / f'{i:03d}_game.png')))
        text(game, f"Velstria {r['clip']} f{r['frame']}")
        side = fit(cv2.imread(str(render / f'{i:03d}_side.png')))
        text(side, 'side')
        row = np.hstack([m, game, side])
        bar = np.full((24, row.shape[1], 3), 32, np.uint8)
        text(bar, r['label'], y=17)
        rows.append(np.vstack([bar, row]))
    width = max(r.shape[1] for r in rows)
    rows = [np.hstack([r, np.zeros((r.shape[0], width - r.shape[1], 3), np.uint8)]) for r in rows]
    cv2.imwrite(out_path, np.vstack(rows), [cv2.IMWRITE_JPEG_QUALITY, 88])
    print(out_path)


if __name__ == '__main__':
    {'shots': lambda: shots(sys.argv[2]), 'sheet': lambda: sheet(sys.argv[2], sys.argv[3])}[sys.argv[1]]()
