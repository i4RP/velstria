#!/usr/bin/env python3
"""モーションクリップの仕様（tools/heroref/clips.json）を、切り出しの定義表（tools/heroref/clip_defs.json）から作る。

  python3 tools/heroref/make_clips.py            # clip_defs.json → clips.json（yaw: "auto" を解決）
  python3 tools/heroref/make_clips.py --print    # 解決後の表を表示するだけ

- 定義表の 1 行: name, action（Meshy の action_id）, impact（打撃・発射の元フレーム。省略可）, start / end（元フレーム）,
  yaw（度 or "auto"）, mirror, loop, rootXZ, note。フレームは Meshy の元フレーム（最初のキー = 1）。
- yaw "auto": build/heroref/raw_clips.json（全長の抽出結果。extract_clips.py に build/heroref/raw_spec.json を渡して作る）
  から、打撃の瞬間（ループは全体の平均）の胴の向きを求め、正面 -Z へ戻す角度にする。構えで体が開いたクリップでも、
  打撃・発射は正面（= シムの攻撃方向）へ向かう。
"""
import argparse
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFS = Path(__file__).with_name("clip_defs.json")
OUT = Path(__file__).with_name("clips.json")
RAW = ROOT / "build" / "heroref" / "raw_clips.json"
RIG = "H002"


def yaw_deg(q):
    """区間回転で正面 (0,0,-1) を回したときの向き（度。0 = 正面 -Z、正 = キャラの左 -X 側）。"""
    x, y, z, w = q
    vx = -(2 * (x * z + w * y))
    vz = -(1 - 2 * (x * x + y * y))
    return math.degrees(math.atan2(-vx, -vz))


def qrot(q, v):
    x, y, z, w = q
    u = (x, y, z)
    t = (2 * (u[1] * v[2] - u[2] * v[1]), 2 * (u[2] * v[0] - u[0] * v[2]), 2 * (u[0] * v[1] - u[1] * v[0]))
    return (v[0] + w * t[0] + (u[1] * t[2] - u[2] * t[1]),
            v[1] + w * t[1] + (u[2] * t[0] - u[0] * t[2]),
            v[2] + w * t[2] + (u[0] * t[1] - u[1] * t[0]))


def add(a, b, k=1.0):
    return (a[0] + b[0] * k, a[1] + b[1] * k, a[2] + b[2] * k)


def heading(v):
    """XZ 平面の向き（度。0 = 正面 -Z、正 = 左 -X）。"""
    return math.degrees(math.atan2(-v[0], -v[2]))


def fk(seg, f, side):
    """区間回転から手首と武器の先端の位置を概算する（ヒーロー空間、腰が原点。四肢は区間回転で真下を回したもの）。
    武器は握りこぶしの親指側（腕を下ろした基準姿勢で正面 -Z）へ 0.8 m 伸びるとみなす。"""
    sx = 0.18 if side == "R" else -0.18
    shoulder = qrot(seg(f, "torso"), (sx, 0.42, 0))
    elbow = add(shoulder, qrot(seg(f, "arm" + side), (0, -0.28, 0)))
    wrist = add(elbow, qrot(seg(f, "foreArm" + side), (0, -0.26, 0)))
    tip = add(wrist, qrot(seg(f, "hand" + side), (0, 0, -1)), 0.8)
    return shoulder, wrist, tip


def circ_mean(degs):
    s = sum(math.sin(math.radians(d)) for d in degs)
    c = sum(math.cos(math.radians(d)) for d in degs)
    return math.degrees(math.atan2(s, c))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--print", action="store_true")
    a = ap.parse_args()
    defs = json.loads(DEFS.read_text())
    raw = json.loads(RAW.read_text())
    segs = raw["segments"]
    S = len(segs)
    torso = segs.index("torso")
    clips_raw = {c["name"]: c for c in raw["clips"]}

    def seg(c, f, s):
        f = max(0, min(c["frames"] - 1, f))
        o = (f * S + s) * 4
        return c["rot"][o:o + 4]

    out = []
    for d in defs["clips"]:
        c = clips_raw.get(f"raw_{d['action']}")
        if c is None:
            raise SystemExit(f"{d['name']}: raw_{d['action']} がありません（raw_clips.json を作り直す）")
        n = c["frames"]  # 出力フレーム 0..n-1 = 元フレーム 1..n
        start = d.get("start", 1)
        end = d.get("end", n)
        yaw = d.get("yaw", "auto")
        sg = lambda f, name, c=c: seg(c, f, segs.index(name))
        if yaw in ("tip", "hand", "tipL", "handL"):
            # 打撃の瞬間に武器の先端（tip）／手首（hand、肩からの向き）が正面へ来る角度
            side = "L" if yaw.endswith("L") else "R"
            i = int(round(d["impact"])) - 1
            hs = []
            for f in range(i - 1, i + 2):
                shoulder, wrist, tip = fk(lambda ff, nn: sg(ff, nn), f, side)
                v = tip if yaw.startswith("tip") else (wrist[0] - shoulder[0], 0, wrist[2] - shoulder[2])
                hs.append(heading(v))
            yaw = round(-circ_mean(hs) + d.get("yawAdd", 0.0), 1)
        elif yaw == "aim":
            # 銃・弓: 引き手（右手首）→ 押し手（左手首）の向き = 狙い（銃身・矢）を正面へ
            i = int(round(d["impact"])) - 1
            hs = []
            for f in range(i - 1, i + 2):
                _, wr, _ = fk(lambda ff, nn: sg(ff, nn), f, "R")
                _, wl, _ = fk(lambda ff, nn: sg(ff, nn), f, "L")
                hs.append(heading((wl[0] - wr[0], 0, wl[2] - wr[2])))
            yaw = round(-circ_mean(hs) + d.get("yawAdd", 0.0), 1)
        elif yaw == "travel":
            # 腰の水平の移動方向（始め → 終わり）を正面へ（回避・突進）
            r = c["root"]
            a0, a1 = int(start) - 1, min(n, int(end)) - 1
            v = (r[a1 * 3] - r[a0 * 3], 0, r[a1 * 3 + 2] - r[a0 * 3 + 2])
            yaw = round(-heading(v) + d.get("yawAdd", 0.0), 1)
        elif yaw == "auto":
            if d.get("loop") or "impact" not in d:
                ys = [yaw_deg(seg(c, f - 1, torso)) for f in range(int(start), int(end))]
                yaw = -circ_mean(ys)
            else:
                # 打撃の前後 2 フレームの胴の向き
                i = int(round(d["impact"])) - 1
                yaw = -circ_mean([yaw_deg(seg(c, f, torso)) for f in range(i - 2, i + 3)])
            yaw = round(yaw * d.get("yawScale", 1.0) + d.get("yawAdd", 0.0), 1)
        clip = {"name": d["name"], "source": {"rig": RIG, "action_id": d["action"]}, "start": start, "end": end}
        if d.get("loop"):
            clip["loop"] = True
        if d.get("mirror"):
            clip["mirror"] = True
        if yaw:
            clip["yaw"] = yaw
        clip["rootXZ"] = d.get("rootXZ", 0.25)
        if "impact" in d:
            clip["events"] = {"impact": d["impact"]}
        if d.get("note"):
            clip["note"] = d["note"]
        out.append(clip)
        if a.print:
            print(f"{d['name']:18s} a={d['action']:3d} [{start},{end}] impact={d.get('impact', '-')} yaw={yaw}"
                  f"{' mirror' if d.get('mirror') else ''}{' loop' if d.get('loop') else ''}")
    if not a.print:
        spec = {"$comment": "tools/heroref/make_clips.py が clip_defs.json から作る（手で直さない）。キーの意味は "
                            "tools/blender/extract_clips.py の先頭。フレームは Meshy の元フレーム（最初のキー = 1）。",
                "version": 1, "clips": out}
        OUT.write_text(json.dumps(spec, ensure_ascii=False, indent=1) + "\n")
        print(f"{OUT} ({len(out)} clips)")


if __name__ == "__main__":
    main()
