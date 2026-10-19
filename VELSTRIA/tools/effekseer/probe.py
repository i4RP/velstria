"""後処理の中で描く経路の安全装置の確かめの効果（Zt_PostProbe）。白い大きな光 1 枚（10 秒）。

EffekseerPostPass が後処理用の描き手を作った後に 1 回、画面外の小さな画へ描いて光った画素を数える（docs/EFFEKSEER.md「描画の 2 つの経路」）。
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from efkgen import Col, Effect, Loc, Node, Scl  # noqa: E402


def build():
    fx = Effect("Zt_PostProbe", frames=600)
    fx.add(Node("probe", tex="Fx_Glow", blend="add", life=600, loc=Loc.fixed(0, 0, 0), scale=Scl.fixed(3),
                color=Col.fixed(255, 255, 255, 255)))
    return [fx]


if __name__ == "__main__":
    for fx in build():
        print(fx.build())
