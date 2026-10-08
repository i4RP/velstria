#!/usr/bin/env python3
"""Effekseer の効果を Python で記述して .efk（ゲームで読む形式）へ書き出す小さな DSL。

流れ: Python で Node を組む → XML（.efkproj）→ `effekseer export` で .efk。.efkefc（エディタ用）が欲しい時は `save`。
座標は右手系・Y 上向き・1 単位 = 1 m。効果は「前 = -Z」（RealityKit の前）へ向けて作る。ゲーム側は yaw で前を回す。
時間の単位は Effekseer のフレーム（60fps）。

使い方（例）:
    fx = Effect("H003_hit", frames=30)
    fx.add(Node("flash", tex="Fx_Core", blend="add", life=8, scale=Scl.ease(0.4, 1.6), color=Col.ease((255,240,200,255), (255,160,60,0))))
    fx.build()          # Effects/Effekseer/H003_hit.efk
"""
import os
import shutil
import subprocess
import tempfile
from xml.sax.saxutils import escape

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "Effects", "Effekseer")

BLEND = {"opaque": 0, "normal": 1, "add": 2, "sub": 3, "mul": 4}
# Sprite の向き: 0 ビルボード / 1 Y 軸固定 / 2 固定（回転で向ける） / 3 回転ビルボード / 4 方向ビルボード
BILLBOARD = {"billboard": 0, "yfixed": 1, "fixed": 2, "rotated": 3, "directional": 4}
# イージングの速さ（StartSpeed, EndSpeed）。負の StartSpeed = ゆっくり始まる。
SPEED = {"lin": None, "in": (-30, 30), "out": (30, -30), "inout": (-30, -30), "fast": (30, 30)}


def num(v):
    s = repr(float(v))
    return s[:-2] if s.endswith(".0") else s


def tag(name, body):
    return f"<{name}>{body}</{name}>"


def rng(v):
    """単値 or (min, max) → (center, max, min)。"""
    if isinstance(v, (tuple, list)):
        lo, hi = float(v[0]), float(v[1])
    else:
        lo = hi = float(v)
    return (lo + hi) / 2, hi, lo


def rng_xml(v):
    c, hi, lo = rng(v)
    return tag("Center", num(c)) + tag("Max", num(hi)) + tag("Min", num(lo))


def vec3(v):
    """スカラ / (x,y,z) / ((x0,y0,z0),(x1,y1,z1)) → 軸ごとの (min,max)。"""
    if isinstance(v, (int, float)):
        return [(v, v)] * 3
    if isinstance(v[0], (tuple, list)):
        return [(v[0][i], v[1][i]) for i in range(3)]
    return [(v[i], v[i]) for i in range(3)]


def vec_xml(v, names="XYZ"):
    return "".join(tag(n, rng_xml(r)) for n, r in zip(names, vec3(v)))


def fixed_xml(v, names="XYZ"):
    ax = vec3(v)
    return "".join(tag(n, num(r[0])) for n, r in zip(names, ax))


FPS = 60.0


def per_frame(v, order):
    """秒基準の値（m/s, 度/秒…）をフレーム基準へ。order=1: 速度（/60）、order=2: 加速度（/3600）。"""
    k = FPS ** order
    if isinstance(v, (int, float)):
        return v / k
    if isinstance(v[0], (tuple, list)):
        return tuple(tuple(x / k for x in side) for side in v)
    return tuple(x / k for x in v)


class _Param:
    """Location / Rotation / Scaling の値（Fixed / PVA / Easing）。

    PVA の速度 vel は「毎秒」、加速度 acc は「毎秒²」で渡す（Effekseer 内部は毎フレームなので変換する）。
    """

    def __init__(self, kind, **kw):
        self.kind, self.kw = kind, kw

    def to_xml(self, group, fixed_name, pva_name, zero_default=True):
        k, kw = self.kind, self.kw
        if k == "fixed":
            return tag("Type", "0") + tag("Fixed", tag(fixed_name, fixed_xml(kw["v"])))
        if k == "pva":
            parts = [tag(pva_name, vec_xml(kw.get("v", 0)))]
            parts.append(tag("Velocity", vec_xml(per_frame(kw.get("vel", 0), 1))))
            parts.append(tag("Acceleration", vec_xml(per_frame(kw.get("acc", 0), 2))))
            return tag("Type", "1") + tag("PVA", "".join(parts))
        if k == "ease":
            body = tag("Start", vec_xml(kw["start"])) + tag("End", vec_xml(kw["end"]))
            sp = SPEED[kw.get("curve", "lin")]
            if sp:
                body += tag("StartSpeed", num(sp[0])) + tag("EndSpeed", num(sp[1]))
            return tag("Type", "2") + tag("Easing", body)
        raise ValueError(k)


class Loc(_Param):
    @staticmethod
    def fixed(x=0, y=0, z=0): return Loc("fixed", v=(x, y, z))
    @staticmethod
    def pva(pos=0, vel=0, acc=0): return Loc("pva", v=pos, vel=vel, acc=acc)
    @staticmethod
    def ease(start, end, curve="lin"): return Loc("ease", start=start, end=end, curve=curve)
    def xml(self): return self.to_xml("LocationValues", "Location", "Location")


class Rot(_Param):
    @staticmethod
    def fixed(x=0, y=0, z=0): return Rot("fixed", v=(x, y, z))
    @staticmethod
    def pva(rot=0, vel=0, acc=0): return Rot("pva", v=rot, vel=vel, acc=acc)
    @staticmethod
    def ease(start, end, curve="lin"): return Rot("ease", start=start, end=end, curve=curve)
    def xml(self): return self.to_xml("RotationValues", "Rotation", "Rotation")


class Scl(_Param):
    @staticmethod
    def fixed(x=1, y=None, z=None):
        y = x if y is None else y
        z = x if z is None else z
        return Scl("fixed", v=(x, y, z))
    @staticmethod
    def pva(scale=1, vel=0, acc=0): return Scl("pva", v=scale, vel=vel, acc=acc)
    @staticmethod
    def ease(start, end, curve="lin"):
        return Scl("ease", start=start, end=end, curve=curve)
    def xml(self): return self.to_xml("ScalingValues", "Scale", "Scale")


class Col:
    """頂点色。0..255 の RGBA。"""

    def __init__(self, kind, **kw):
        self.kind, self.kw = kind, kw

    @staticmethod
    def fixed(r=255, g=255, b=255, a=255): return Col("fixed", c=(r, g, b, a))
    @staticmethod
    def rand(lo=(255, 255, 255, 255), hi=(255, 255, 255, 255)): return Col("rand", lo=lo, hi=hi)
    @staticmethod
    def ease(start, end, curve="lin"): return Col("ease", start=start, end=end, curve=curve)

    def xml(self, prefix="ColorAll"):
        k, kw = self.kind, self.kw
        if k == "fixed":
            r, g, b, a = kw["c"]
            return tag(prefix, "0") + tag(prefix + "_Fixed", tag("R", num(r)) + tag("G", num(g)) + tag("B", num(b)) + tag("A", num(a)))
        if k == "rand":
            body = "".join(tag(n, rng_xml((kw["lo"][i], kw["hi"][i]))) for i, n in enumerate("RGBA"))
            return tag(prefix, "1") + tag(prefix + "_Random", body)
        if k == "ease":
            def side(c): return "".join(tag(n, rng_xml(c[i])) for i, n in enumerate("RGBA"))
            body = tag("Start", side(kw["start"])) + tag("End", side(kw["end"]))
            sp = SPEED[kw.get("curve", "lin")]
            if sp:
                body += tag("StartSpeed", num(sp[0])) + tag("EndSpeed", num(sp[1]))
            return tag(prefix, "2") + tag(prefix + "_Easing", body)
        raise ValueError(k)


class Gen:
    """生成位置（親の位置まわり）。"""

    def __init__(self, xml): self._xml = xml
    def xml(self): return self._xml

    @staticmethod
    def sphere(radius=0, rx=(-90, 90), ry=(-180, 180), rotate=True):
        """球面上に生成。rotate=True なら粒子の局所座標が外向きへ回る（局所 +Y へ動かすと放射状に飛ぶ）。"""
        body = tag("Type", "1") + tag("Sphere", tag("Radius", rng_xml(radius)) + tag("RotationX", rng_xml(rx)) + tag("RotationY", rng_xml(ry)))
        if rotate:
            body += tag("EffectsRotation", "True")
        return Gen(body)

    @staticmethod
    def circle(radius=1, division=32, angle=(0, 360), axis="y", rotate=True):
        ax = {"x": 0, "y": 1, "z": 2}[axis]
        body = tag("Type", "3") + tag("Circle", tag("Division", num(division)) + tag("Radius", rng_xml(radius)) + tag("AngleStart", rng_xml(angle[0])) + tag("AngleEnd", rng_xml(angle[1])) + tag("AxisDirection", num(ax)))
        if rotate:
            body += tag("EffectsRotation", "True")
        return Gen(body)

    @staticmethod
    def line(length=(0, 2), division=1, noise=0):
        return Gen(tag("Type", "4") + tag("Line", tag("Division", num(division)) + tag("PositionStart", rng_xml(0)) + tag("PositionEnd", rng_xml(length)) + tag("PositionNoize", rng_xml(noise))))


class Node:
    """効果の 1 要素（粒子の発生源）。子は親の各粒子の位置から発生する。"""

    def __init__(self, name, tex="Fx_Glow", blend="add", life=20, count=1, interval=0, delay=0,
                 loc=None, rot=None, scale=None, color=None, gen=None, gravity=None,
                 billboard="billboard", fade_in=0, fade_out=0, kind="sprite", ring=None,
                 detach=False, children=None, loop=False, zwrite=False, distort=0, uv_scroll=None,
                 bind_scale=True, bind_rot=True, remove_with_parent=True):
        self.__dict__.update(locals())
        del self.__dict__["self"]
        self.children = list(children or [])

    def add(self, *nodes):
        self.children += nodes
        return self

    def xml(self):
        b = []
        count = "<Infinite>True</Infinite>" if self.count in ("inf", None) or self.loop else tag("Value", num(self.count))
        common = tag("MaxGeneration", count) + tag("Life", rng_xml(self.life))
        if self.interval:
            common += tag("GenerationTime", rng_xml(self.interval))
        if self.delay:
            common += tag("GenerationTimeOffset", rng_xml(self.delay))
        if self.detach:
            common += tag("LocationEffectType", "1") + tag("RotationEffectType", "1") + tag("ScaleEffectType", "1")
        if not self.remove_with_parent:
            common += tag("RemoveWhenParentIsRemoved", "False")
        b.append(tag("CommonValues", common))
        if self.loc: b.append(tag("LocationValues", self.loc.xml()))
        if self.gravity is not None:
            g = self.gravity if isinstance(self.gravity, (tuple, list)) else (0, self.gravity, 0)
            g = per_frame(g, 2)  # m/s² → m/frame²
            b.append(tag("LocationAbsValues", tag("Type", "1") + tag("Gravity", tag("Gravity", fixed_xml(g)))))
        if self.rot: b.append(tag("RotationValues", self.rot.xml()))
        if self.scale: b.append(tag("ScalingValues", self.scale.xml()))
        if self.gen: b.append(tag("GenerationLocationValues", self.gen.xml()))
        rc = tag("ColorTexture", escape(f"Texture/{self.tex}.png")) + tag("AlphaBlend", num(BLEND[self.blend]))
        if self.fade_in:
            rc += tag("FadeInType", "1") + tag("FadeIn", tag("Frame", num(self.fade_in)))
        if self.fade_out:
            rc += tag("FadeOutType", "1") + tag("FadeOut", tag("Frame", num(self.fade_out)))
        if self.uv_scroll:
            sx, sy = self.uv_scroll
            rc += tag("UV", "3") + tag("UVScroll", tag("Start", tag("X", "0") + tag("Y", "0")) + tag("Size", tag("X", "1") + tag("Y", "1")) + tag("Speed", tag("X", num(sx)) + tag("Y", num(sy))))
        if self.zwrite:
            rc += tag("ZWrite", "True")
        b.append(tag("RendererCommonValues", rc))
        col = self.color or Col.fixed()
        if self.kind == "sprite":
            sp = tag("Billboard", num(BILLBOARD[self.billboard])) + col.xml("ColorAll")
            b.append(tag("DrawingValues", tag("Sprite", sp)))
        elif self.kind == "ring":
            r = self.ring or Ring()
            b.append(tag("DrawingValues", tag("Type", "3") + tag("Ring", r.xml(col, BILLBOARD[self.billboard]))))
        else:
            raise ValueError(self.kind)
        b.append(tag("Name", escape(self.name)))
        b.append(tag("Children", "".join(c.xml() for c in self.children)))
        return tag("Node", "".join(b))


class Ring:
    """Ring レンダラ（輪・扇・衝撃波）。outer / inner は半径（Easing 可）、angle=(開始, 終了) 度で欠けた輪（斬撃の弧）。"""

    def __init__(self, outer=1.0, inner=0.0, outer_end=None, inner_end=None, vertices=32, angle=None, curve="out"):
        self.__dict__.update(locals())
        del self.__dict__["self"]

    def xml(self, col, billboard):
        def radius(name, a, b):
            if b is None:
                return tag(name, "0") + tag(name + "_Fixed", tag("Location", num(a)))
            sp = SPEED[self.curve]
            body = tag("Start", tag("Location", rng_xml(a))) if False else tag("Start", rng_xml(a)) + tag("End", rng_xml(b))
            if sp:
                body += tag("StartSpeed", num(sp[0])) + tag("EndSpeed", num(sp[1]))
            return tag(name, "2") + tag(name + "_Easing", body)
        out = tag("Billboard", num(billboard)) + tag("VertexCount", num(self.vertices))
        out += radius("Outer", self.outer, self.outer_end) + radius("Inner", self.inner, self.inner_end)
        if self.angle:
            a0, a1 = self.angle
            out += tag("RingShape", tag("Type", "1") + tag("Crescent", tag("StartingAngle", "0") + tag("StartingAngle_Fixed", num(a0)) + tag("EndingAngle", "0") + tag("EndingAngle_Fixed", num(a1))))
        # 色: 外・中央・内の 3 つに同じ色（Easing / Fixed）
        for part in ("Outer", "Center", "Inner"):
            out += col.xml(part + "Color")
        return out


class Effect:
    def __init__(self, name, frames=60, loop=False):
        self.name, self.frames, self.loop = name, frames, loop
        self.nodes = []

    def add(self, *nodes):
        self.nodes += nodes
        return self

    def xml(self):
        root = tag("Name", "Root") + tag("Children", "".join(n.xml() for n in self.nodes))
        # 注意: 項目名は旧形式（ColorAll_Easing など）で書く。ToolVersion を新しい値（1.80.7）にすると新形式として読まれ、旧形式の項目が無視される。ToolVersion は 1.53c（旧形式として読ませる）
        return ('<?xml version="1.0" encoding="utf-8"?>\n<EffekseerProject>' + tag("Root", root)
                + tag("ToolVersion", "1.53c") + tag("Version", "3")
                + tag("StartFrame", "0") + tag("EndFrame", num(self.frames)) + tag("IsLoop", "True" if self.loop else "False")
                + "</EffekseerProject>")

    def build(self, out_dir=OUT, keep_project=False):
        """.efk を out_dir/<name>.efk へ書き出す（テクスチャは out_dir/Texture/ にある前提）。"""
        os.makedirs(out_dir, exist_ok=True)
        proj = os.path.join(out_dir, self.name + ".efkproj")
        with open(proj, "w", encoding="utf-8") as f:
            f.write(self.xml())
        dst = os.path.join(out_dir, self.name + ".efk")
        if os.path.exists(dst):
            os.remove(dst)
        if shutil.which("effekseer"):
            subprocess.run(["effekseer", "export", proj, dst], check=True, capture_output=True)
        else:
            # CLI が無い環境（Windows など）は、純 Python の書き出し器で同じ .efk を作る（efkexport.py）
            import efkexport
            with open(dst, "wb") as f:
                f.write(efkexport.export_efk(self.xml()))
        if not keep_project:
            os.remove(proj)
        if not os.path.exists(dst) or os.path.getsize(dst) == 0:
            raise RuntimeError(f"{self.name}: .efk の書き出しに失敗")
        return dst
