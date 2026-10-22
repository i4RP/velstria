# H032 赤拳のディアスのクリップを、取得済みの素材（Meshy prime / ライブラリを H032 の Meshy リグへ適用 →
# tools/blender/extract_clips.py で 15 区間化した build/h032-motion/raw-clips.json）から組み立て、
# App/Resources/Heroes/H032MotionClips.json を書く。
#   python3 tools/motion/h032_compose.py [raw-clips.json] [out.json]
# 区間回転の切り出し・時間の伸縮・重なりの補間（区間ごとの slerp）・Y 軸回りの向きの補正だけを行う（Blender 不要）。
# クリップ名は末尾 _h032（先頭の語は近接の判定 HeroMotionClip.isMeleeName に使われる）。
# 打撃の出力フレームは sim の時刻（Kit_H032 の Tune / docs/kits/Dyrroth.md）に合わせて置く。
import json
import math
import sys

FPS = 30
src_path = sys.argv[1] if len(sys.argv) > 1 else 'build/h032-motion/raw-clips.json'
out_path = sys.argv[2] if len(sys.argv) > 2 else 'App/Resources/Heroes/H032MotionClips.json'
raw = json.load(open(src_path))
SEG = raw['segments']
S = len(SEG)
CLIPS = {c['name']: c for c in raw['clips']}


def qmul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (aw*bx+ax*bw+ay*bz-az*by, aw*by-ax*bz+ay*bw+az*bx, aw*bz+ax*by-ay*bx+az*bw, aw*bw-ax*bx-ay*by-az*bz)


def slerp(a, b, t):
    d = sum(x*y for x, y in zip(a, b))
    if d < 0:
        b = tuple(-x for x in b)
        d = -d
    if d > 0.9995:
        r = tuple(x + (y - x)*t for x, y in zip(a, b))
    else:
        th = math.acos(d)
        s = math.sin(th)
        wa, wb = math.sin((1-t)*th)/s, math.sin(t*th)/s
        r = tuple(wa*x + wb*y for x, y in zip(a, b))
    n = math.sqrt(sum(x*x for x in r))
    return tuple(x/n for x in r)


def smooth(t):
    t = min(1.0, max(0.0, t))
    return t*t*(3 - 2*t)


def ry(deg):
    h = math.radians(deg)/2
    return (0.0, math.sin(h), 0.0, math.cos(h))


def frame(name, f, yaw=0.0):
    """素材の f フレーム（小数可・両端で止める）の (区間回転, 腰)。"""
    c = CLIPS[name]
    n = c['frames']
    f = min(max(f, 0.0), n - 1.0)
    i0 = int(math.floor(f))
    i1 = min(n - 1, i0 + 1)
    a = f - i0
    R, P = c['rot'], c['root']
    q = []
    for s in range(S):
        q0 = tuple(R[(i0*S+s)*4:(i0*S+s)*4+4])
        q1 = tuple(R[(i1*S+s)*4:(i1*S+s)*4+4])
        q.append(slerp(q0, q1, a))
    p = [P[i0*3+k]*(1-a) + P[i1*3+k]*a for k in range(3)]
    if yaw:
        y = ry(yaw)
        q = [qmul(y, x) for x in q]
        h = math.radians(yaw)
        p = [p[0]*math.cos(h) + p[2]*math.sin(h), p[1], -p[0]*math.sin(h) + p[2]*math.cos(h)]
    return q, p


def mix(a, b, w):
    return [slerp(x, y, w) for x, y in zip(a[0], b[0])], [x + (y - x)*w for x, y in zip(a[1], b[1])]


class Piece:
    """出力の [t0, t1] 秒に素材の [f0, f1] フレームを線形に割り当てる。ease で素材の進みを緩急付け（溜め・伸ばし）。"""
    def __init__(self, src, f0, f1, t0, t1, yaw=0.0, ease=None):
        self.src, self.f0, self.f1, self.t0, self.t1, self.yaw, self.ease = src, f0, f1, t0, t1, yaw, ease

    def at(self, t):
        u = 0.0 if self.t1 <= self.t0 else min(1.0, max(0.0, (t - self.t0)/(self.t1 - self.t0)))
        if self.ease:
            u = self.ease(u)
        return frame(self.src, self.f0 + (self.f1 - self.f0)*u, self.yaw)


def timeline(pieces, duration):
    """重なる区間は後の部品へ smoothstep で移る（腕の連動を保ったまま 2 つの素材をつなぐ）。"""
    n = int(round(duration*FPS)) + 1
    frames = []
    for i in range(n):
        t = i/FPS
        cur = pieces[0].at(t)
        for k in range(1, len(pieces)):
            p, prev = pieces[k], pieces[k-1]
            # 前の部品の終わりと次の始まりの間（重なり・隙間のどちらも）を補間の窓にする（最短 2 フレーム）
            ws, we = min(p.t0, prev.t1), max(p.t0, prev.t1)
            we = max(we, ws + 2/FPS)
            if t < ws:
                break
            cur = mix(cur, p.at(t), smooth((t - ws)/(we - ws)))
        frames.append(cur)
    return frames


def loop(src, a, b, k=0, yaw=0.0):
    """[a, b) の 1 周。先頭 k フレームは b 以降からの続きと混ぜて継ぎ目を消す。"""
    out = []
    for i in range(b - a):
        pose = frame(src, a + i, yaw)
        if i < k:
            pose = mix(frame(src, b + i, yaw), pose, smooth((i + 1)/(k + 1)))
        out.append(pose)
    return out


def ease_hold(u):
    # 溜め: 前半は遅く引き絞り、最後に一気に放つ手前まで
    return u**0.6


def pack(name, frames, loop_=False, events=None, **extra):
    rot, root = [], []
    prev = None
    for q, p in frames:
        q = list(q)
        if prev is not None:
            q = [x if sum(a*b for a, b in zip(x, y)) >= 0 else tuple(-v for v in x) for x, y in zip(q, prev)]
        prev = q
        for x in q:
            rot += [round(v, 4) for v in x]
        root += [round(v, 4) for v in p]
    c = {'name': name, 'source': 'h032', 'frames': len(frames), 'loop': loop_, 'rootXZ': 0.0,
         'events': events or {}, 'rot': rot, 'root': root}
    c.update(extra)
    return c


def hips_fix(frames, y=None):
    """腰の水平の移動を消す（ゲームの移動と二重にしない）。上下は残す。"""
    return [(q, [0.0, p[1] if y is None else y, 0.0]) for q, p in frames]


clips = []
# 待機: prime の構え（左足前・拳を顎の高さで左右ずらす・呼吸）。ライブラリの打撃の構え（胴 -39°）へ寄せて少しだけ右へ回す
idle = loop('raw_idle', 20, 110, k=10, yaw=-20)
clips.append(pack('idle_h032', hips_fix(idle), True))
# 歩行: ライブラリ Walk Fight Forward（構えを保った前進の足取り、50 フレーム = 1 周、その場）
walk = loop('lib_walk_fight', 0, 50, k=4)
clips.append(pack('walk_h032', hips_fix(walk), True, groundSpeed=1.25))
# 走行: prime の深い前傾の走り（f8〜27 = 1 周。腰の前進 2.65 脚長 / 0.633 秒 ≈ 3.3 m/s）
run = loop('raw_run', 8, 27, k=4)
clips.append(pack('run_h032', hips_fix(run), True, groundSpeed=3.3))

# 通常攻撃: ライブラリの左ジャブ / 右ストレート（構え → 小さな溜め → 踏み込み・腰のひねり → 全伸展 → 引き戻し → 構え）。
# impact = 腕が伸び切る最初のフレーム（実行時に sim の windup へ合わせる）
jab = timeline([Piece('lib_jab_l', 2, 44, 0, 42/FPS)], 42/FPS)
clips.append(pack('punch_jab_l_h032', jab, events={'impact': 12.0}, melee=True))
cross = timeline([Piece('lib_jab_r', 3, 40, 0, 37/FPS)], 37/FPS)
clips.append(pack('punch_cross_r_h032', cross, events={'impact': 13.0}, melee=True))

# S1 赤拳連斬: 衝撃 0.26 / 0.46 / 0.66 秒（burstFirstDelay 0.26 + 0.2 × n）に 右・左・右 を全伸展。castStart = 0（発動の瞬間から）
s1 = timeline([
    Piece('lib_jab_r', 4, 16, 0.0, 0.26),          # 引いて右ストレート（0.26）
    Piece('lib_jab_l', 9, 14, 0.30, 0.46),         # 右を引き戻しつつ左（0.46）
    Piece('lib_jab_r', 10, 16, 0.52, 0.66),        # 左を戻して右（0.66）
    Piece('lib_jab_r', 16, 40, 0.66, 1.30),        # 引き戻し → 構え
], 1.30)
clips.append(pack('punch_s1_h032', s1, events={'impact': 0.26*FPS}, melee=True))

# S2 1 回目: 低い前傾の突進（4.15 m を 0.4 秒）。prime の飛びかかりの低い踏み出し（f4〜16）を突進の間保ち、構えへ戻す
s2a = timeline([
    Piece('raw_s2leap', 2, 12, 0.0, 0.12),
    Piece('raw_s2leap', 12, 16, 0.12, 0.40, ease=lambda u: u*0.5),
    Piece('lib_jab_l', 40, 50, 0.46, 0.70),
], 0.70)
clips.append(pack('dash_s2_h032', hips_fix(s2a), events={'impact': 0.40*FPS}))
# S2 2 回目「致命の一撃」: 振りかぶり → 飛びかかり（空中で両拳を振り上げる）→ 到着で振り下ろし（1 撃）→ 0.13 左 → 0.2 右
s2b = timeline([
    Piece('raw_s2leap', 18, 30, 0.0, 0.10),
    Piece('raw_s2leap', 30, 36, 0.10, 0.27),       # 到着（1 撃目）= 0.27 秒（振りかぶり 0.06 + 2.5 m / 12 m/s の目安）
    Piece('lib_jab_l', 10, 14, 0.30, 0.40),        # +0.13
    Piece('lib_jab_r', 12, 16, 0.42, 0.47),        # +0.2
    Piece('lib_jab_r', 16, 40, 0.47, 1.10),
], 1.10)
clips.append(pack('punch_s2_strike_h032', hips_fix(s2b), events={'impact': 0.27*FPS}, melee=True))

# ULT 奈落の一撃: 0.76 秒の溜め（足は動かさない）で右拳を腰へ引き絞り胴をねじる → 0.76 秒に全身で真っすぐ突き出す。
ult = timeline([
    Piece('lib_prep_straight', 30, 47, 0.0, 0.62, ease=ease_hold),   # 引き絞り（ゆっくり、最後まで締める）
    Piece('lib_prep_straight', 47, 57, 0.62, 0.76),                   # 放つ（全伸展 = 0.76）
    Piece('lib_prep_straight', 57, 63, 0.76, 1.00),                   # 伸び切りを保つ
    Piece('lib_prep_straight', 63, 95, 1.00, 1.80),                   # 構えへ
], 1.80)
clips.append(pack('punch_ult_h032', hips_fix(ult), events={'impact': 0.76*FPS}, melee=True))

out = {'version': 1, 'fps': FPS, 'segments': SEG, 'clips': clips}
with open(out_path, 'w') as f:
    json.dump(out, f, separators=(',', ':'))
for c in clips:
    print(c['name'], c['frames'], c['events'])
