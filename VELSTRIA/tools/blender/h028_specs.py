"""H028 の攻撃・スキルのクリップの切り出し（author_h028_motion.py が読む）。

keys: (出力の秒, 元のフレーム) の区分線形の対応。face: 胴を正面（-Z = 対象）へ向ける元のフレーム。
events はフレーム（30fps）。impact = 打撃（通常攻撃は sim の命中 = attackReleased と同期）、
スキルは詠唱の呼び出しから castLead（0.12 秒 = 3.6 フレーム）後を impact にして先頭から再生させる。
ULT の hit = 到着（sim の 1 撃目の命中で同期）。lockLowerUntil = 移動中でも下半身を重ねる終わり（突進は sim が動かす）。
見た目の時刻は FX_H028.swift 冒頭・docs/vfx/H028.md、sim の時刻は Kit_H028.swift（Saber.md）に合わせる:
  S1 環剣: 0 秒 剣を体の周りで一回し → 0.2 秒 5 本が放射状に飛ぶ（腕を開く）
  S2 断空突進: 3m を 0.2 秒 → 到着で次の斬撃の構え
  ULT 三連断空: 毎秒 17m・最大 5.45m の突進（0.14〜0.32 秒）→ 到着・+0.39・+0.78 秒に 3 連撃 → 到着 +1.0 秒で操作可能
"""
CAST_LEAD = 0.12 * 30


def action_specs(math, V, relaxed):
    rad = math.radians

    def open_left(t0, t1):
        # 放つ瞬間に左手を開く
        def f(t):
            if t0 <= t <= t1:
                return relaxed(0.05), 14.0
            return relaxed(0.45), 0.0
        return f

    fist_left = lambda t: (relaxed(0.6), 0.0)
    A = 10 / 30   # ULT の到着（最大の突進 0.32 秒を含む。早く着けば hit の同期で先へ進む）
    return [
        # 1 撃目: 小さく溜め → 右肩から左腰への袈裟（右 → 左）
        dict(name='sword_slash_a_h028', src='attack', keys=[(0, 2), (0.30, 12), (0.62, 24), (0.80, 27)], face=12,
             events=dict(impact=9, release=9, end=24), rootXZ=0.55, blend_in=0.08, blend_out=0.2, left=fist_left),
        # 2 撃目: 腰を返して水平の返し斬り（左 → 右）
        dict(name='sword_slash_b_h028', src='attack', keys=[(0, 27), (0.30, 35.5), (0.50, 40), (0.80, 41.5)], face=35.5,
             events=dict(impact=9, release=9, end=24), rootXZ=0.55, blend_in=0.1, blend_out=0.3, left=fist_left),
        # 3 撃目: 低く沈んで全身で薙ぐ（右 → 左）
        dict(name='sword_slash_c_h028', src='attack', keys=[(0, 87), (0.30, 97.5), (0.60, 108), (0.80, 112)], face=97.5,
             events=dict(impact=9, release=9, end=24), rootXZ=0.55, blend_in=0.1, blend_out=0.22, left=fist_left),
        # S1 環剣: 0〜0.2 秒で剣を体の周りに一回し → 0.2 秒に両腕を開いて放つ → 構えへ
        dict(name='sword_whirl_h028', src='skill1', keys=[(0, 2), (0.2, 30), (0.32, 42), (0.55, 50), (0.75, 62), (0.95, 72)],
             face=44, events=dict(impact=CAST_LEAD, release=6), rootXZ=0.3, blend_in=0.04, blend_out=0.2,
             left=open_left(0.18, 0.6)),
        # S2 断空突進: 0〜0.2 秒 深い前傾で剣を後ろへ引いて駆ける → 到着で剣を引いた斬撃の構え → 構えへ
        dict(name='dash_charge_h028', src='skill2', keys=[(0, 0), (0.2, 12), (0.45, 20), (0.75, 30), (0.95, 40)],
             face=6, yaw_bias=0.0, turn={'hips': rad(45), 'torso': rad(62), 'head': rad(66)},
             events=dict(impact=CAST_LEAD, arrive=6), melee=False, rootXZ=0.0, blend_in=0.03, blend_out=0.22,
             left=fist_left, extra=dict(lockLowerUntil=7)),
        # ULT 三連断空: 突進 → 到着で打ち上げの斬り上げ → +0.39 返し → +0.78 大きく振り下ろす → +1.0 まで残心 → 構え
        dict(name='sword_triple_h028', src='ult',
             keys=[(0, 2), (A - 0.08, 16), (A, 20.5), (A + 0.39, 42.5), (A + 0.78, 71.5), (A + 1.0, 78), (A + 1.25, 88)],
             face=20.5, yaw_curve=[(0, 0), (A, 0), (A + 0.39, -10), (A + 0.78, -78), (A + 1.25, -78)],
             bridge=[(A + 0.47, A + 0.68, ('torso', 'head', 'armR', 'foreArmR', 'handR', 'armL', 'foreArmL', 'handL'))],
             events=dict(impact=CAST_LEAD, hit=A * 30, strike2=(A + 0.39) * 30, strike3=(A + 0.78) * 30),
             melee=False, rootXZ=0.0, blend_in=0.03, blend_out=0.25, left=fist_left,
             extra=dict(lockLowerUntil=round((A + 1.0) * 30, 2))),
    ]
