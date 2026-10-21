"""H030 ライナ（MLBB: ライラ）のキットの段に重ねる効果（Effects/Effekseer/Kit/H030_*.efk。FX_H030.swift の FXCue.efk が再生する）。

MLBB の画面収録（vid10。訓練場、1108×512・30fps・55 px/m 前後）で読んだ大きさ・色・時刻（docs/vfx/H030.md）。時間はフレーム（60fps。
録画の 1 コマ = 2 フレーム）。効果は前 = -Z。色は録画の画素（芯 #F2FCFF・弾の青 #4A94E8・明るい縁の水色 #A6F2FF・紺の電光 #0249CF・
奥義の金 #FDDC82 / #F8F2BE・刻印の桃 #A64CC3・灰色の石 #5A6F88・藍の靄 #3556B3）。
  H030_muzzle     S1・S2 の砲口の発射（砲口に置く。前 = 照準）: 白い芯 1 コマ → 前へ伸びる白い閃光（約 1.5 m）と青い光だまり、
                   前を向いた水色の輪、前へ散る水色のきらめき、紺の電光。3D の上の層
  H030_muzzle_up  S2 の掲げた砲口（前の上 55°）の発射: 同じ部品を 55° 上へ傾け、水色の白の星形の閃光を足す。3D の上の層
  H030_shot_hit   S1 の命中・奥義の被弾: 白い閃き（体を覆う）と、前へ散る水色の火花。3D の上の層
  H030_s2_burst   S2 の爆発（胸の高さ。半径 1.9 m で作る。倍率 = 半径 / 1.9）: 白い芯の閃き → 球の中の水色の電光 ×4・外へ飛ぶ光の欠片・
                   球の縁の淡い光の輪（ガラスの縁）→ ラベンダーの残り光。球そのもの（白 → 青 → 藍）と範囲の縁の輪は SkillFX
  H030_mark_pop   刻印の弾け（足元）: 桃の泡 → 足元の灰色の尖った石の輪（半径 0.9〜1.5 m）・桃の電光・床を這う水色の電光・藍の靄
  H030_ult_charge 奥義の溜め（砲口の前の溜めの球の位置。発動の 0.17 秒後から 0.38 秒）: 外から球へ吸い込まれる水色の光の粒・
                   球のまわりを回る紺の三日月の渦・青い芯の脈
  H030_ult_flash  奥義の発射の閃光（溜めの球の位置。発射の 0.08 秒前から）: 淡い金の閃光と横に伸びるレンズの光条 → 白い閃光と光芒。
                   3D の上の層
  H030_ult_root   奥義のビームの根元（ビームの始まり。発射から）: 前を向いた水色の輪 ×2 が広がる・横と後ろへ散る水色の火花・根元の光の点
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from efkgen import Col, Effect, Gen, Loc, Node, Rot, Scl  # noqa: E402

P = "H030_"


def hexc(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def rgba(c, a=255):
    return (c[0], c[1], c[2], a)


def fade(c, a0=255, a1=0, curve="in"):
    return Col.ease(rgba(c, a0), rgba(c, a1), curve)


def morph(c0, c1, a0=255, a1=0, curve="in"):
    return Col.ease(rgba(c0, a0), rgba(c1, a1), curve)


CORE = hexc("#F2FCFF")
BLUE = hexc("#4A94E8")
CYAN = hexc("#A6F2FF")
NAVY_BOLT = hexc("#0249CF")
DEEP = hexc("#2660C3")
GOLD = hexc("#FDDB82")
GOLD_PALE = hexc("#F8F2BE")
PINK = hexc("#A64CC3")
STONE = hexc("#5A6F88")
STONE_LIGHT = hexc("#6B87AC")
INDIGO = hexc("#3556B3")
LAVENDER = hexc("#7182F2")
NAVY = hexc("#16214D")


def facing(name, tex, d0, d1, life, color, blend="add", delay=0, z=0.0, y=0.0, curve="out"):
    """前（-Z）を向いて立つ板（直径 d0 → d1 m）。砲口・ビームの根元の輪。"""
    return Node(name, tex=tex, blend=blend, life=life, delay=delay, billboard="fixed", rot=Rot.fixed(0, 0, 0),
                loc=Loc.fixed(0, y, z), scale=Scl.ease(d0, d1, curve), color=color)


def forward_streak(name, length, width, life, color, yaw=0, delay=0, z=None, y=0.0):
    """前へ伸びる光の筋（砲口の高さで水平に寝かせた板。yaw = 前からの開き）。"""
    z = -length * 0.5 if z is None else z
    return Node(name, tex="Fx_Streak", life=life, delay=delay, billboard="fixed", rot=Rot.fixed(90, 90 + yaw, 0),
                loc=Loc.fixed(0, y, z), scale=Scl.ease((length * 0.6, width, 1), (length, width * 0.5, 1), "out"), color=color)


# ---- S1・S2 の砲口 --------------------------------------------------------------------------

def muzzle_parts():
    return [
        Node("flash", tex="Fx_Core", life=5, scale=Scl.ease(1.4, 2.4, "out"), color=fade(CORE, 255, 0, "lin")),
        forward_streak("blast", 2.2, 3.2, 7, fade(CORE, 255)),
        forward_streak("blast_l", 1.6, 1.8, 6, fade(CYAN, 230), yaw=-12),
        forward_streak("blast_r", 1.6, 1.8, 6, fade(CYAN, 230), yaw=12),
        Node("bloom", tex="Fx_Glow", life=14, delay=1, loc=Loc.fixed(0, 0, -0.35), scale=Scl.ease(1.6, 2.6, "out"),
             color=fade(BLUE, 210)),
        facing("ring", "Fx_RingSoft", 0.3, 0.9, 8, fade(CYAN, 150), z=-0.25),
        Node("glints", tex="Fx_Glow", life=(10, 18), count=8, delay=1, loc=Loc.pva(pos=0, vel=((-2.0, -1.0, -10.0), (2.0, 2.0, -4.0))),
             scale=Scl.ease(0.16, 0.03), color=morph(CYAN, BLUE, 255, 0)),
        Node("bolt", tex="Fx_Bolt", life=6, count=2, delay=2, interval=2, loc=Loc.fixed(0, 0, -0.6),
             rot=Rot.pva(((0, 0, -40), (0, 0, 40))), scale=Scl.fixed(1.0, 0.32, 1), color=morph(NAVY_BOLT, CYAN, 255, 0, "lin")),
    ]


def muzzle():
    """砲口の発射（録画 f1047〜f1052: 砲口の水色の光 → 前へ伸びる白い閃光 → 青い光だまりと紺の電光）。S1（水平の砲口）。"""
    fx = Effect(P + "muzzle", frames=24, kit=True)
    fx.add(*muzzle_parts())
    return fx


def muzzle_up():
    """S2 の掲げた砲口（前の上 55°）の発射。同じ部品を、前を 55° 上へ傾けた見えない親の子にする（録画 f971: 水色の白の星形の閃光）。"""
    fx = Effect(P + "muzzle_up", frames=24, kit=True)
    tilt = Node("tilt", tex="Fx_Glow", life=24, rot=Rot.fixed(55, 0, 0), scale=Scl.fixed(1), color=Col.fixed(255, 255, 255, 0))
    tilt.add(*muzzle_parts())
    tilt.add(Node("star", tex="Fx_Star4", life=7, rot=Rot.pva(((0, 0, -15), (0, 0, 15))), scale=Scl.ease(1.2, 2.0, "out"),
                  color=fade(CYAN, 240)))
    fx.add(tilt)
    return fx


# ---- 命中 ------------------------------------------------------------------------------------

def shot_hit():
    """S1 の命中・奥義の被弾（録画 f1057・f387: 体が 1 コマ白く光る。爆発は無い）。"""
    fx = Effect(P + "shot_hit", frames=20, kit=True)
    fx.add(
        Node("flash", tex="Fx_Core", life=5, scale=Scl.ease(1.3, 1.9, "out"), color=fade(CORE, 255, 0, "lin")),
        Node("glow", tex="Fx_Glow", life=9, scale=Scl.ease(1.4, 2.0, "out"), color=fade(CYAN, 170)),
        Node("sparks", tex="Fx_Glow", life=(8, 14), count=9, loc=Loc.pva(pos=0, vel=((-3.0, -1.5, -8.0), (3.0, 3.0, -3.0)), acc=(0, -6, 0)),
             scale=Scl.ease(0.14, 0.03), color=morph(CORE, CYAN, 255, 0)),
    )
    return fx


# ---- S2 の爆発 ------------------------------------------------------------------------------

def s2_burst():
    """S2 の爆発（胸の高さ。録画 f908〜f914）。球（白 → 青 → 藍）は SkillFX のメッシュ（CI の撮影に写り、範囲の輪と時刻を測る）。
    ここは閃き・球の中の電光・飛ぶ光の欠片・球の縁の光の輪・ラベンダーの残り光。"""
    fx = Effect(P + "s2_burst", frames=36, kit=True)
    fx.add(
        Node("flash", tex="Fx_Core", life=5, scale=Scl.ease(1.6, 3.2, "out"), color=fade(CORE, 255, 0, "lin")),
        Node("rim", tex="Fx_RingSoft", life=10, delay=3, scale=Scl.ease(3.0, 3.6, "out"), color=fade(CYAN, 170)),
        Node("bolts", tex="Fx_Bolt", life=(7, 11), count=4, delay=4, interval=1, gen=Gen.sphere((0.2, 0.8), rotate=False),
             rot=Rot.pva(((0, 0, -180), (0, 0, 180))), scale=Scl.fixed(1.2, 0.4, 1), color=morph(CORE, CYAN, 255, 0, "lin")),
        Node("shards", tex="Fx_Glow", life=(12, 20), count=12, delay=2, gen=Gen.sphere(0.3), loc=Loc.pva(pos=0, vel=((0, 3.0, 0), (0, 6.0, 0))),
             scale=Scl.ease(0.18, 0.03), color=morph(CYAN, BLUE, 255, 0)),
        Node("after", tex="Fx_Glow", blend="normal", life=16, delay=8, scale=Scl.ease(3.0, 3.5, "out"), color=fade(LAVENDER, 110)),
        Node("late_bolts", tex="Fx_Bolt", life=(6, 9), count=3, delay=12, interval=2, gen=Gen.sphere((0.3, 0.9), rotate=False),
             rot=Rot.pva(((0, 0, -180), (0, 0, 180))), scale=Scl.fixed(0.8, 0.28, 1), color=fade(CYAN, 220, 0, "lin")),
    )
    return fx


# ---- 刻印の弾け --------------------------------------------------------------------------------

def mark_pop():
    """刻印の弾け（足元に置く。録画 f942〜f952: 桃の泡 → 白い球と足元の灰色の尖った石の輪 → 藍の球に桃の電光 → 藍の靄と床を這う電光）。"""
    fx = Effect(P + "mark_pop", frames=40, kit=True)
    fx.add(
        Node("bubble", tex="Fx_Glow", life=7, loc=Loc.fixed(0, 1.0, 0), scale=Scl.ease(1.6, 2.9, "out"), color=fade(PINK, 255)),
        Node("stones", tex="Fx_Shard", blend="normal", life=(16, 22), count=10, delay=3, billboard="yfixed",
             gen=Gen.circle((0.9, 1.5), division=10, rotate=False), loc=Loc.fixed(0, 0.2, 0),
             scale=Scl.ease((0.45, 0.65, 1), (0.65, 1.15, 1), "out"), color=morph(STONE_LIGHT, STONE, 255, 0)),
        Node("pink_bolts", tex="Fx_Bolt", life=(7, 10), count=3, delay=5, interval=2, gen=Gen.sphere((0.2, 0.7), rotate=False),
             loc=Loc.fixed(0, 1.0, 0), rot=Rot.pva(((0, 0, -180), (0, 0, 180))), scale=Scl.fixed(1.0, 0.34, 1),
             color=morph(PINK, CORE, 255, 0, "lin")),
        Node("floor_bolts", tex="Fx_Bolt", life=(9, 13), count=4, delay=8, interval=1, billboard="fixed",
             gen=Gen.circle((0.4, 1.2), division=4, rotate=True), loc=Loc.fixed(0, 0.06, 0), rot=Rot.fixed(90, 0, 0),
             scale=Scl.fixed(1.6, 0.45, 1), color=fade(CYAN, 240, 0, "lin")),
        Node("haze", tex="Fx_Smoke", blend="normal", life=(20, 26), count=3, delay=8, gen=Gen.sphere(0.5, rotate=False),
             loc=Loc.pva(pos=((0, 0.8, 0), (0, 1.0, 0)), vel=((0, 0.2, 0), (0, 0.5, 0))), scale=Scl.ease(1.2, 1.8),
             color=fade(INDIGO, 160)),
    )
    return fx


# ---- 奥義 --------------------------------------------------------------------------------------

def ult_charge():
    """奥義の溜め（溜めの球の位置に置く。発動の 0.17 秒後 → 発射の 0.55 秒まで = 23 フレーム。録画 f376〜f384）。"""
    fx = Effect(P + "ult_charge", frames=26, kit=True)
    fx.add(
        # 外（半径 1.2 m）から球へ吸い込まれる水色の光の粒（局所 +Y = 外向き。内向きの速さで寄る）
        Node("gather", tex="Fx_Glow", life=(10, 14), count=18, interval=0.8, gen=Gen.sphere((1.0, 1.3)),
             loc=Loc.pva(pos=0, vel=((0, -5.5, 0), (0, -7.0, 0))), scale=Scl.ease(0.1, 0.3, "in"), color=morph(CYAN, CORE, 0, 255, "in")),
        # 球のまわりを回る紺の三日月の渦（2 枚）
        Node("swirl_a", tex="Fx_Crescent", blend="normal", life=22, rot=Rot.pva((0, 0, 0), (0, 0, 600)), scale=Scl.ease(0.7, 1.0, "out"),
             color=Col.ease(rgba(NAVY, 0), rgba(NAVY, 220), "out")),
        Node("swirl_b", tex="Fx_Crescent", blend="normal", life=22, delay=2, rot=Rot.pva((0, 0, 180), (0, 0, 600)),
             scale=Scl.ease(0.6, 0.9, "out"), color=Col.ease(rgba(DEEP, 0), rgba(DEEP, 200), "out")),
        # 青い芯の脈（溜まるほど明るく）
        Node("pulse", tex="Fx_Glow", life=20, scale=Scl.ease(0.6, 1.2, "in"), color=Col.ease(rgba(BLUE, 80), rgba(CYAN, 230), "in")),
    )
    return fx


def ult_flash():
    """奥義の発射の閃光（溜めの球の位置。発射の 5 フレーム前から。録画 f385〜f387: 淡い金の閃光と横の光条 → 白い閃光）。"""
    fx = Effect(P + "ult_flash", frames=20, kit=True)
    fx.add(
        Node("gold", tex="Fx_Core", life=6, scale=Scl.ease(1.6, 3.2, "out"), color=morph(GOLD_PALE, GOLD, 255, 0, "lin")),
        Node("lens", tex="Fx_Streak", life=9, delay=1, scale=Scl.ease((5.0, 1.0, 1), (7.5, 0.4, 1), "out"),
             color=morph(GOLD_PALE, CORE, 255, 0)),
        Node("white", tex="Fx_Core", life=6, delay=5, scale=Scl.ease(2.0, 3.2, "out"), color=fade(CORE, 255, 0, "lin")),
        Node("star", tex="Fx_Star4", life=7, delay=5, rot=Rot.pva(((0, 0, -10), (0, 0, 10))), scale=Scl.ease(1.6, 2.6, "out"),
             color=fade(CORE, 230)),
    )
    return fx


def ult_root():
    """奥義のビームの根元（ビームの始まりに置く。前 = ビーム。録画 f388〜f396）。"""
    fx = Effect(P + "ult_root", frames=34, kit=True)
    fx.add(
        facing("ring_a", "Fx_RingSoft", 1.6, 3.8, 10, fade(CYAN, 220), z=-0.2),
        facing("ring_b", "Fx_RingSoft", 1.2, 3.0, 10, fade(CORE, 180), delay=4, z=-0.6),
        Node("spray", tex="Fx_Glow", life=(12, 20), count=14, delay=1, loc=Loc.pva(pos=0, vel=((-6.0, -1.5, 0.5), (6.0, 3.0, 4.0)), acc=(0, -4, 0)),
             scale=Scl.ease(0.16, 0.03), color=morph(CYAN, BLUE, 255, 0)),
        Node("dot", tex="Fx_Glow", life=20, delay=10, scale=Scl.ease(1.1, 0.6, "in"), color=fade(CYAN, 230)),
    )
    return fx


def build():
    return [muzzle(), muzzle_up(), shot_hit(), s2_burst(), mark_pop(), ult_charge(), ult_flash(), ult_root()]


if __name__ == "__main__":
    for e in build():
        print(e.build())
