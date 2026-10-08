#!/usr/bin/env python3
"""efkgen の .efkproj（XML）を、Effekseer 1.8 の .efk（バイナリ）へ書き出す純 Python の書き出し器。

`effekseer export`（Mac の Effekseer ツールの CLI）が無い環境（Windows など）で効果を作り直すための代替。
efkgen の DSL が出す XML の範囲（Fixed / PVA / Easing の移動・回転・拡大、球・円の生成、
スプライト・リング、フェード、入れ子の子ノード）だけを対応する。範囲外の要素は例外にする（黙って落とさない）。
正しさは、同梱済みの全 .efk とのバイト一致で確かめている（tools/effekseer/check_export.py）。

注意: 公式の CLI は Ring の XML（半径・色・欠け角・頂点数・Billboard）を取り込まず、既定の Ring を書き出す。
同梱済みの .efk（H001 H008 H013 H019 H020 H024 の Ring 13 本）がそうなっているため、この書き出し器も同じバイト列を出す
（バイト一致を保つため）。Ring は位置・回転・寿命・合成だけが効く。形や色が要る効果は Sprite で作る。
"""
import math
import struct
import xml.etree.ElementTree as ET

VERSION = 1810  # 0x0712（Effekseer 1.8）
INT_MAX = 0x7FFFFFFF

# ---- 低レベル ------------------------------------------------------------------------------


def i32(v):
    return struct.pack("<i", int(v))


def f32(v):
    return struct.pack("<f", float(v))


def f32r(v):
    """float32 に丸めた Python の float。"""
    return struct.unpack("<f", struct.pack("<f", float(v)))[0]


def text(node, path, default=None):
    e = node.find(path)
    return default if e is None else e.text


def num(node, path, default=0.0):
    t = text(node, path)
    return default if t is None else float(t)


def has(node, path):
    return node.find(path) is not None


def rng(node, path, default=0.0):
    """<X><Center/><Max/><Min/></X> → (max, min)。"""
    e = node.find(path)
    if e is None:
        return (default, default)
    hi, lo = float(e.find("Max").text), float(e.find("Min").text)
    return (max(hi, lo), min(hi, lo))  # エディタは大きい方を max に入れる（DSL は大小を揃えずに書くことがある）


def rad(v):
    """度 → ラジアン。エディタの結果とは float32 で最大 1 ulp ずれることがある（描画には影響しない大きさ）。"""
    return f32r(v * math.pi / 180.0)


# ---- イージングの係数 ------------------------------------------------------------------------


# エディタが書き出す係数の実測（float32 の丸めまでエディタと一致させるため、DSL が使う 2 通りは実測値を使う）。
# in = (-30, 30)、out = (30, -30)。ほかの組み合わせは下の式（Hermite、float32 丸め。最下位ビットがずれることがある）。
EASING_TABLE = {
    (-30.0, 30.0): ("01000040", "2c4ca2bf", "a330893e"),
    (30.0, -30.0): ("00000040", "f66c97c0", "ecd96e40"),
}


def easing_params(start_speed, end_speed):
    """StartSpeed / EndSpeed（度）→ 3 次の係数のバイト列。f(t) = a t^3 + b t^2 + c t（a, b, c は float32）。"""
    known = EASING_TABLE.get((float(start_speed), float(end_speed)))
    if known:
        return b"".join(bytes.fromhex(h) for h in known)
    s = f32r(math.tan(math.radians(45.0 + start_speed)))
    e = f32r(math.tan(math.radians(45.0 + end_speed)))
    a = f32r(f32r(s + e) - 2.0)
    b = f32r(f32r(3.0 - f32r(2.0 * s)) - e)
    return f32(a) + f32(b) + f32(s)


# ---- 各ブロック ------------------------------------------------------------------------------


def rvec3(axes_, conv=None):
    """3 軸の (max, min) → random_vector3d（max の 3 つ、min の 3 つ）。"""
    cv = conv or (lambda v: v)
    return b"".join(f32(cv(a[0])) for a in axes_) + b"".join(f32(cv(a[1])) for a in axes_)


def axes(node, base):
    return [rng(node, f"{base}/{n}") for n in "XYZ"]


def easing_block(e, conv=None):
    """Easing（Start / End / StartSpeed / EndSpeed）の vec3 版 → 1.8 の ParameterEasing。"""
    out = i32(-1) * 4  # RefEqS, RefEqE
    out += rvec3(axes(e, "Start"), conv) + rvec3(axes(e, "End"), conv)
    out += i32(0)  # isMiddleEnabled
    if has(e, "StartSpeed"):
        out += i32(0) + easing_params(num(e, "StartSpeed"), num(e, "EndSpeed"))  # StartEndSpeed
    else:
        out += i32(0) + f32(0.0) + f32(0.0) + f32(1.0)  # 線形 = StartEndSpeed の (a, b, c) = (0, 0, 1)
    out += i32(0x020100) + i32(0)  # チャンネル（x, y, z = 0, 1, 2）/ 個別イージングなし
    return out


def vec_param(node, group, fixed_name, pva_name, kind):
    """移動・回転・拡大（Fixed / PVA / Easing）。kind は 'loc' 'rot' 'scl'。回転は度 → ラジアン。"""
    conv = rad if kind == "rot" else None
    g = node.find(group)
    if g is None:
        # 既定（エディタの初期値）: 移動・回転は Fixed(0,0,0)、拡大は Fixed(1,1,1)
        default = (1.0, 1.0, 1.0) if kind == "scl" else (0.0, 0.0, 0.0)
        return i32(0) + i32(16) + i32(-1) + b"".join(f32(v) for v in default)
    t = int(text(g, "Type", "0"))
    if t == 0:
        v = [float(g.find(f"Fixed/{fixed_name}/{n}").text) for n in "XYZ"]
        if conv:
            v = [conv(x) for x in v]
        return i32(0) + i32(16) + i32(-1) + b"".join(f32(x) for x in v)
    if t == 1:
        body = (i32(-1) * 6 + rvec3(axes(g, f"PVA/{pva_name}"), conv) + rvec3(axes(g, "PVA/Velocity"), conv)
                + rvec3(axes(g, "PVA/Acceleration"), conv))
        return i32(1) + i32(len(body)) + body
    if t == 2:
        body = easing_block(g.find("Easing"), conv)
        return i32(2) + i32(len(body)) + body
    raise ValueError(f"{group}: Type {t} は未対応")


def common_block(node):
    c = node.find("CommonValues")
    if c.find("MaxGeneration/Infinite") is not None:
        maxgen = INT_MAX
    else:
        maxgen = int(float(c.find("MaxGeneration/Value").text))
    life = rng(c, "Life")
    interval = rng(c, "GenerationTime") if has(c, "GenerationTime") else (1.0, 1.0)
    interval = tuple(max(v, 1e-5) for v in interval)  # エディタは生成間隔の下限を 0.00001 に丸める
    offset = rng(c, "GenerationTimeOffset") if has(c, "GenerationTimeOffset") else (0.0, 0.0)

    def bind(tag):
        return 1 if text(c, tag) == "1" else 2  # 1 = 親に縛らない（生成時の位置だけ追う）/ 既定 = 常に追う

    body = i32(-1) * 9
    body += i32(maxgen) + i32(bind("LocationEffectType")) + i32(bind("RotationEffectType")) + i32(bind("ScaleEffectType"))
    body += i32(0)  # GenerationType: Continuous
    body += i32(1)  # RemovalFlags: WhenLifeIsExtinct
    body += i32(life[0]) + i32(life[1])
    body += f32(interval[0]) + f32(interval[1])
    body += f32(offset[0]) + f32(offset[1])
    body += i32(1) + i32(1)  # Burst
    body += b"\x00" * 8  # Trigger ×4（uint16）
    assert len(body) == 100, len(body)
    return i32(100) + body


# LOD（全段）+ ここまで共通の既定ブロック
LOD = i32(15) + i32(0)
# 局所力場 ×4（すべて無効）
FORCE_FIELDS = i32(4) + (i32(0) + f32(1.0) + b"\x00" * 28) * 4


def generation_block(node):
    g = node.find("GenerationLocationValues")
    if g is None:
        return i32(0) + i32(0) + b"\x00" * 24
    rot = 1 if text(g, "EffectsRotation", "False") == "True" else 0
    t = int(text(g, "Type", "0"))
    if t == 1:
        s = "Sphere"
        return i32(rot) + i32(1) + b"".join(f32(v) for v in (rng(g, f"{s}/Radius") + tuple(rad(x) for x in rng(g, f"{s}/RotationX"))
                                                             + tuple(rad(x) for x in rng(g, f"{s}/RotationY"))))
    if t == 3:
        s = "Circle"
        angle_s = tuple(rad(x) for x in rng(g, f"{s}/AngleStart"))
        angle_e = tuple(rad(x) for x in rng(g, f"{s}/AngleEnd"))
        return (i32(rot) + i32(3) + i32(int(float(g.find(f"{s}/Division").text))) + b"".join(f32(v) for v in (*rng(g, f"{s}/Radius"), *angle_s, *angle_e))
                + i32(0) + i32(int(float(g.find(f"{s}/AxisDirection").text))) + f32(0) + f32(0))
    raise ValueError(f"GenerationLocation Type {t} は未対応")


# 生成の後ろ〜描画共通の前（深度・サウンド・キル・衝突）。DSL は変えないので固定値。
POST_GEN = bytes.fromhex(
    "0000000000000000000000000000803fffff7f7f00000000000000000000803f"
    "000000000100000000000000000000000000803f0000803f0000000000000000"
    "00000000000000000000000000000000")
LINEAR_COLOR_COEF = f32(0.0) + f32(0.0) + f32(1.0)  # 線形の色イージング
FADE_COEF = f32(0.0) + f32(0.0) + f32(1.0)  # フェードは線形（a=0, b=0, c=1）


def render_common(node, tex_index):
    r = node.find("RendererCommonValues")
    tex = text(r, "ColorTexture")
    blend = int(float(text(r, "AlphaBlend", "1")))
    out = i32(0) + f32(1.0)  # MaterialType: Default / EmissiveScaling
    out += i32(tex_index[tex]) + i32(-1) * 6
    out += i32(blend)
    out += (i32(1) + i32(0)) * 7  # フィルタ・ラップ ×7
    out += i32(1) + i32(0)  # ZTest / ZWrite
    for name in ("FadeIn", "FadeOut"):
        if text(r, name + "Type", "0") not in ("0", None):
            out += i32(1) + f32(num(r, name + "/Frame")) + FADE_COEF
        else:
            out += i32(0)
    out += i32(0) * 3 + f32(0.0) + i32(0) + i32(-1) + i32(0) * 2 + f32(0.0)  # UV ×3 / 歪み強度 / UV3 / ブレンド種別 / UV4,5 / 歪み強度
    out += i32(0) + i32(0) + f32(1.0) + i32(0) + i32(0)  # 左右反転確率 / 色の親子 / 歪み強度 / CustomData ×2
    if has(r, "UV") or has(r, "ZWrite"):
        raise ValueError("UV / ZWrite は未対応")
    return out


def color_block(parent, base):
    """色（Fixed / Easing）→ AllTypeColor。"""
    t = int(float(text(parent, base, "0")))
    if t == 0:
        f = parent.find(base + "_Fixed")
        return i32(0) + bytes(int(float(f.find(n).text)) for n in "RGBA")
    if t == 2:
        e = parent.find(base + "_Easing")

        def col(side, which):
            return bytes(int(float(e.find(f"{side}/{n}/{which}").text)) for n in "RGBA")

        out = i32(2)
        for side in ("Start", "End"):
            out += b"\x00\x00" + col(side, "Min") + col(side, "Max")
        if not has(e, "StartSpeed"):
            return out + LINEAR_COLOR_COEF
        return out + easing_params(num(e, "StartSpeed"), num(e, "EndSpeed"))
    raise ValueError(f"色 Type {t} は未対応")


SPRITE_POS = i32(1) + b"".join(f32(v) for v in (-0.5, -0.5, 0.5, -0.5, -0.5, 0.5, 0.5, 0.5))
# Ring（既定の Ring。公式 CLI が XML の Ring を取り込まないため、これが書き出される）
RING_TAIL = bytes.fromhex("0300000000000000000000000000000000000000ffffffff0000000001000000000000bf0000003f010000000000000000000000")


def count_nodes(node):
    return 1 + sum(count_nodes(c) for c in node.find("Children").findall("Node"))


def node_blob(node, tex_index, order):
    """1 ノード（と子）のバイト列。order は通し番号の [0] 参照。"""
    draw = node.find("DrawingValues")
    ring = draw.find("Ring") is not None
    kids = node.find("Children").findall("Node")
    out = i32(3 if ring else 2) + i32(1) + i32(order[0])
    order[0] += 1
    out += common_block(node) + LOD
    out += vec_param(node, "LocationValues", "Location", "Location", "loc")
    out += FORCE_FIELDS
    out += vec_param(node, "RotationValues", "Rotation", "Rotation", "rot")
    out += vec_param(node, "ScalingValues", "Scale", "Scale", "scl")
    out += generation_block(node) + POST_GEN
    out += render_common(node, tex_index)
    out += b"\x00" * 20
    if ring:
        out += RING_TAIL
    else:
        sp = draw.find("Sprite")
        out += i32(2) + i32(0) + i32(int(float(sp.find("Billboard").text)))
        out += color_block(sp, "ColorAll")
        out += i32(0) + SPRITE_POS + i32(0) + i32(0)
    out += i32(len(kids))
    for k in kids:
        out += node_blob(k, tex_index, order)
    return out


HEADER_MID = None


def collect_textures(node, acc):
    acc.add(text(node, "RendererCommonValues/ColorTexture"))
    for k in node.find("Children").findall("Node"):
        collect_textures(k, acc)


def export_efk(xml_text):
    root = ET.fromstring(xml_text)
    top = root.find("Root/Children").findall("Node")
    texs = set()
    for n in top:
        collect_textures(n, texs)
    texs = sorted(texs)
    tex_index = {t: i for i, t in enumerate(texs)}
    out = b"SKFE" + i32(VERSION) + i32(len(texs))
    for t in texs:
        out += i32(len(t) + 1) + t.encode("utf-16-le") + b"\x00\x00"
    out += i32(0) * 2  # 法線・歪みテクスチャ
    total = sum(count_nodes(n) for n in top)
    out += i32(0) * 5 + i32(4) + i32(0) * 5 + i32(total) + i32(0) + f32(1.0) + i32(-1) + i32(0) * 4 + i32(-1) + i32(len(top))
    order = [0]
    for n in top:
        out += node_blob(n, tex_index, order)
    return out
