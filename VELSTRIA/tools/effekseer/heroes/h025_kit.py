"""H025 ルミナ（MLBB: ミヤ）のキットの段に重ねる効果（Effects/Effekseer/Kit/H025_*.efk。FX_H025.swift の FXCue.efk が再生する）。

形の主役（S2 の範囲の輪・縁の光の帯・白い渦の帯・光の檻・散る矢の尾、奥義の三日月の紋章・光の柱）は SkillFX（範囲の縁を判定に
合わせて測る部品・CI の撮影に写るメッシュと帯）。ここは見せ場の粒の細部だけ: 気の炎の舌・弓の先の星・天へ抜ける矢・着弾の白い芯と
立ちのぼる光の矢・分裂の白い閃光と放射の筋・足元の星と横に伸びる光・三日月のきらめきと紫の霞。
実機の中・高画質では後処理の中で描かれてブルームが掛かり、シミュレータ・低画質は重ね描き（CI の撮影にも写る）。
MLBB の画面収録 vid3（2026-10-16、訓練場 Lv4、1108×512・30fps・62.3 px/m）で見た大きさ・色・時刻（docs/vfx/H025.md）。
時間はフレーム（60fps。録画の 1 コマ = 2 フレーム）。
  H025_s1_aura    S1 の気（発動 +0.04 秒から、術者に追従）。全身を包む濃い青の気の膨らみ・上へ揺れる青い炎の舌・昇る水色の粒。3D の上
  H025_bow_star   弓の先の星（S2 の天へ放つ瞬間）。白い芯 → 水色の 4 本の光芒・細い放射の光（約 1.6 m）。3D の上
  H025_s2_sky     天へ抜ける青い矢 3 本（毎秒 22 m・0.17 秒）。3D の上
  H025_s2_land    S2 の着弾（範囲の半径 1.7 m で作る。再生の倍率 = 半径 / 1.7）。白い芯の閃光・水色の放射の光・範囲の白い満ち・
                  輪の中から次々に立ちのぼる白〜青の光の矢 12 本・縁のきらめき。3D に隠れる
  H025_s2_split   6 本に分かれる瞬間（同じく半径 1.7 m）。範囲を満たす白い光・白い光の柱・外へ走る短い光の筋。3D に隠れる
  H025_ult_flash  奥義の足元の閃光（+0.1 秒）。白い芯・水色の星・横に長く伸びる光（約 4 m）・柱の中を漂う青い粒。3D の上
  H025_ult_moon   奥義の三日月（頭上 3.7 m）のまわりのきらめきと、消え際（+0.35 秒〜）に流れ落ちる紫の霞。3D の上
効果は前 = -Z。地面の板は fixed で (90, 0, 0)。
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from efkgen import Col, Effect, Gen, Loc, Node, Rot, Scl  # noqa: E402

P = "H025_"


def hexc(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


WHITE = hexc("#F4FCFC")      # 着弾の白い芯（f339）
CORE = hexc("#E2FCFF")       # 月光の芯
CYAN = hexc("#7BDBFD")       # 弓の先の星（f329）
PALE = hexc("#A8F8FC")       # 縁の光の帯（f340〜348）
SKYBLUE = hexc("#4CAFFF")    # 天へ抜ける矢（f330）
ARROW = hexc("#5EBAF7")      # 立ちのぼる光の矢（f340〜348）
AURA = (40, 72, 255)         # S1 の気（発動前との差 (6, 8, 83) = ほぼ純な青の加算）
PERI = hexc("#82A0FD")       # S1 の立ち上がりの閃き（f55）
VEIL = hexc("#569BE0")       # 奥義の光の柱（f401〜412）
MOTE = (102, 153, 255)       # 柱の中の青い粒
LENS = hexc("#82CFFF")       # 足元の横に伸びる光（f402〜404）
WISP = (150, 110, 255)       # 三日月が崩れる紫の霞（f409〜412）


def rgba(c, a=255):
    return (c[0], c[1], c[2], a)


def fade(c, a0=255, a1=0, curve="in"):
    return Col.ease(rgba(c, a0), rgba(c, a1), curve)


def morph(c0, c1, a0=255, a1=0, curve="in"):
    return Col.ease(rgba(c0, a0), rgba(c1, a1), curve)


def flat(name, tex, d0, d1, life, y=0.06, delay=0, color=None, blend="add", curve="out", fade_in=0, spin=0):
    """地面に寝かせた板（直径 d0 → d1 m）。"""
    rot = Rot.pva((90, 0, 0), (0, 0, spin)) if spin else Rot.fixed(90, 0, 0)
    return Node(name, tex=tex, blend=blend, life=life, delay=delay, billboard="fixed", rot=rot, loc=Loc.fixed(0, y, 0),
                scale=Scl.ease(d0, d1, curve) if d0 != d1 else Scl.fixed(d0), color=color or Col.fixed(), fade_in=fade_in)


# ---- S1 月弦分矢 ----------------------------------------------------------------------------

def s1_aura():
    """発動 +0.04 秒から（術者の足元に追従）。MLBB f54〜62: 肩の閃き → 濃い青の気が全身（幅 1.8 m・高さ 2 m）を包み、縁が炎のように上へ揺れる
    → 0.3 秒で薄れて消える。"""
    fx = Effect(P + "s1_aura", frames=26, kit=True)
    fx.add(
        # 肩の青紫の閃き（f54〜55）
        Node("flash", tex="Fx_Star", blend="add", life=7, loc=Loc.fixed(0, 1.45, 0), scale=Scl.ease(0.9, 1.5, "out"),
             color=fade(PERI, 230)),
        # 全身を包む青の膨らみ（加算の青。芯は白へ飛ばさない）
        Node("swell", tex="Fx_Glow", blend="add", life=18, delay=1, loc=Loc.fixed(0, 1.0, 0), scale=Scl.ease((1.6, 2.0, 1), (2.2, 2.6, 1), "out"),
             color=morph(AURA, AURA, 235, 0, "in"), fade_in=4),
        # 上へ揺れる青い炎の舌（体の縁。下が明るい棘の画を縦に立てて昇らせる）
        # 炎の舌は柔らかく（白い芯にしない）: 青の加算を薄く重ね、0.3 秒で出し終える
        Node("tongues", tex="Fx_Spike", blend="add", life=(8, 12), count=10, interval=0.5, delay=2, billboard="yfixed",
             gen=Gen.circle((0.25, 0.45), division=10, rotate=False), loc=Loc.pva(pos=((0, 0.1, 0), (0, 0.5, 0)), vel=((0, 1.4, 0), (0, 2.6, 0))),
             scale=Scl.ease((0.42, 0.7, 1), (0.22, 1.25, 1), "out"), color=morph(AURA, AURA, 150, 0)),
        # 昇る水色の粒（余韻）
        Node("motes", tex="Fx_Glow", blend="add", life=(12, 20), count=8, interval=1, delay=4,
             gen=Gen.circle((0.15, 0.45), division=8, rotate=False), loc=Loc.pva(pos=((0, 0.4, 0), (0, 1.4, 0)), vel=((0, 1.2, 0), (0, 2.2, 0))),
             scale=Scl.ease(0.16, 0.04), color=fade(PALE, 230)),
    )
    return fx


# ---- S2 月蝕の矢 ----------------------------------------------------------------------------

def bow_star():
    """弓の先で閃く星（f329 #7BDBFD / #9EFAFE、約 1.6 m）。"""
    fx = Effect(P + "bow_star", frames=14, kit=True)
    fx.add(
        Node("burst", tex="Fx_Burst", blend="add", life=8, scale=Scl.ease(1.0, 1.6, "out"), rot=Rot.pva(((0, 0, 0), (0, 0, 360))),
             color=morph(CYAN, SKYBLUE, 220, 0)),
        Node("star", tex="Fx_Star", blend="add", life=9, scale=Scl.ease(1.2, 1.8, "out"), rot=Rot.pva(((0, 0, -10), (0, 0, 10))),
             color=fade(CYAN, 255)),
        Node("core", tex="Fx_Core", blend="add", life=5, scale=Scl.ease(0.7, 0.95, "out"), color=fade(CORE, 240, 0, "lin")),
    )
    return fx


def s2_sky():
    """弓の先から天へ抜ける青い矢 3 本（f329〜331）。向きは真上から少し前へ。"""
    fx = Effect(P + "s2_sky", frames=16, kit=True)
    fx.add(
        # 縦の光の槍（Fx_Spike は縦の画。Y 軸固定のビルボードは回転を当てない: アプリの Effekseer は Y 軸固定の板の Z の回転で
        # 横向きになった（2026-10-21 の撮影 #3。WebGL の確認環境では縦）。縦の画をそのまま縦に伸ばす）
        Node("arrows", tex="Fx_Spike", blend="add", life=10, count=3, interval=0.8, billboard="yfixed",
             gen=Gen.circle((0.05, 0.18), division=3, rotate=False),
             loc=Loc.pva(pos=((0, 0.2, 0), (0, 0.5, 0)), vel=((-0.4, 20, -1.5), (0.4, 24, -0.5))),
             scale=Scl.ease((0.32, 1.5, 1), (0.22, 1.9, 1)), color=morph(CORE, SKYBLUE, 255, 0)),
        Node("streaks", tex="Fx_Spike", blend="add", life=8, count=4, interval=0.5, billboard="yfixed",
             gen=Gen.circle((0.05, 0.2), division=4, rotate=False),
             loc=Loc.pva(pos=((0, -0.4, 0), (0, -0.1, 0)), vel=((-0.3, 18, -1.2), (0.3, 22, -0.4))),
             scale=Scl.ease((0.14, 2.2, 1), (0.06, 2.8, 1)), color=fade(SKYBLUE, 220)),
    )
    return fx


def s2_land():
    """着弾（s2Land）から。半径 1.7 m で作る（倍率 = 判定の半径 / 1.7）。MLBB f339: 中心の白い閃光 → f340〜348 輪の中の地面から
    矢じりが上の白〜青の光の矢が次々に昇る（#5EBAF7）。範囲の縁の光の帯・白い渦の帯・光の檻は SkillFX。"""
    R = 1.7
    fx = Effect(P + "s2_land", frames=40, kit=True)
    fx.add(
        # 範囲の白い満ち（地面。0.17 秒で引く）
        flat("fill", "Fx_SoftDisc", 2 * R * 0.9, 2 * R, 10, y=0.05, color=fade(PALE, 170, 0, "in")),
        # 白い芯の閃光（白飛びの手前: 芯 #F4FCFC・アルファ 230）と水色の放射の光
        Node("flash", tex="Fx_Core", blend="add", life=8, loc=Loc.fixed(0, 0.7, 0), scale=Scl.ease(2.4, 3.2, "out"),
             color=fade(WHITE, 230, 0, "lin")),
        Node("burst", tex="Fx_Burst", blend="add", life=10, loc=Loc.fixed(0, 0.6, 0), scale=Scl.ease(2.8, 4.0, "out"),
             rot=Rot.pva(((0, 0, 0), (0, 0, 360))), color=morph(PALE, CYAN, 220, 0)),
        # 立ちのぼる光の矢（先が上に尖る縦の光の槍。縦の画 Fx_Spike を回転なしで縦に伸ばし、ゆっくり昇らせる）
        Node("arrows", tex="Fx_Spike", blend="add", life=(16, 22), count=14, interval=0.8, delay=2, billboard="yfixed",
             gen=Gen.circle((0.25, R * 0.86), division=14, rotate=False),
             loc=Loc.pva(pos=((0, 0.55, 0), (0, 0.95, 0)), vel=((0, 1.0, 0), (0, 2.2, 0))),
             scale=Scl.ease((0.34, 1.7, 1), (0.24, 2.1, 1), "out"), color=morph(WHITE, ARROW, 255, 0)),
        # 縁のきらめき
        Node("glints", tex="Fx_Star4", blend="add", life=(10, 18), count=10, interval=0.8, delay=4,
             gen=Gen.circle((R * 0.85, R * 1.0), division=10, rotate=False), loc=Loc.pva(pos=((0, 0.2, 0), (0, 0.6, 0)), vel=(0, 0.8, 0)),
             scale=Scl.ease(0.5, 0.2, "out"), color=fade(PALE, 230)),
    )
    return fx


def s2_split():
    """6 本に分かれる瞬間（s2Split）から。MLBB f349〜350: 範囲が白く光る（#F6FBFD）→ f351〜 矢が 6 方向へ（矢そのものは SkillFX の travel）。"""
    R = 1.7
    fx = Effect(P + "s2_split", frames=24, kit=True)
    fx.add(
        flat("fill", "Fx_SoftDisc", 2 * R * 0.95, 2 * R * 1.0, 9, y=0.06, color=fade(WHITE, 220, 0, "in")),
        Node("column", tex="Fx_Glow", blend="add", life=9, billboard="yfixed", loc=Loc.fixed(0, 1.1, 0),
             scale=Scl.ease((1.1, 2.4, 1), (1.3, 2.9, 1), "out"), color=fade(WHITE, 190, 0, "in")),
        Node("flash", tex="Fx_Core", blend="add", life=6, loc=Loc.fixed(0, 0.7, 0), scale=Scl.ease(2.6, 3.4, "out"),
             color=fade(WHITE, 220, 0, "lin")),
        # 外へ走る短い光の筋（地面すれすれ。6 本の矢の向きとは別の飾り）
        Node("lines", tex="Fx_Streak", blend="add", life=(6, 10), count=12, billboard="directional",
             gen=Gen.sphere(0.3, rx=(78, 90), ry=(-180, 180)), loc=Loc.pva(pos=((0, 0.5, 0), (0, 0.7, 0)), vel=((0, 7, 0), (0, 11, 0))),
             scale=Scl.ease((0.9, 0.12, 1), (1.4, 0.04, 1)), color=fade(PALE, 220)),
    )
    return fx


# ---- 奥義 隠れ月光 --------------------------------------------------------------------------

def ult_flash():
    """足元の閃光（発動 +0.1 秒）。MLBB f402〜404: 水色の星と横に伸びる光（#64AAF9 / #82CFFF）→ f405〜412 柱の中に青い粒。"""
    fx = Effect(P + "ult_flash", frames=48, kit=True)
    fx.add(
        Node("core", tex="Fx_Core", blend="add", life=8, loc=Loc.fixed(0, 0.35, 0), scale=Scl.ease(1.2, 1.7, "out"),
             color=fade(CORE, 230, 0, "lin")),
        Node("star", tex="Fx_Star", blend="add", life=9, loc=Loc.fixed(0, 0.35, 0), scale=Scl.ease(1.4, 2.0, "out"),
             color=fade(LENS, 255)),
        # 横に長く伸びる光（レンズの筋。画面の横へ約 4 m）
        Node("lens", tex="Fx_Streak", blend="add", life=10, loc=Loc.fixed(0, 0.35, 0), scale=Scl.ease((3.0, 0.28, 1), (4.2, 0.12, 1), "out"),
             color=fade(LENS, 240)),
        # 柱の中を漂う青い粒
        Node("motes", tex="Fx_Glow", blend="add", life=(24, 36), count=12, interval=1.2, delay=6,
             gen=Gen.circle((0.2, 0.85), division=12, rotate=False), loc=Loc.pva(pos=((0, 0.2, 0), (0, 1.6, 0)), vel=((0, 0.3, 0), (0, 0.8, 0))),
             scale=Scl.ease(0.2, 0.06), color=fade(MOTE, 230)),
    )
    return fx


def ult_moon():
    """頭上の三日月（発動 +0.03 秒、三日月の中心）。MLBB f400〜408: 三日月の縁のきらめき → f409〜412 紫の霞になって崩れて消える。"""
    fx = Effect(P + "ult_moon", frames=50, kit=True)
    fx.add(
        Node("glints", tex="Fx_Star4", blend="add", life=(10, 18), count=9, interval=1.2, delay=4,
             gen=Gen.circle((0.75, 0.95), division=9, angle=(-80, 190), axis="z", rotate=False),
             scale=Scl.ease(0.55, 0.2, "out"), color=fade(CORE, 240)),
        # 消え際の紫の霞（下と外へ流れて薄れる）
        Node("wisps", tex="Fx_Smoke", blend="add", life=(18, 28), count=10, interval=0.8, delay=20,
             gen=Gen.circle((0.5, 0.95), division=10, angle=(-80, 190), axis="z", rotate=False),
             loc=Loc.pva(pos=0, vel=((-0.4, -1.4, -0.2), (0.4, -0.6, 0.2))), rot=Rot.pva(0, ((0, 0, -90), (0, 0, 90))),
             scale=Scl.ease(0.32, 0.6, "out"), color=morph(WISP, WISP, 150, 0)),
    )
    return fx


def build():
    return [s1_aura(), bow_star(), s2_sky(), s2_land(), s2_split(), ult_flash(), ult_moon()]


if __name__ == "__main__":
    for e in build():
        print(e.build())
