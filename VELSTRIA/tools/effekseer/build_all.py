#!/usr/bin/env python3
"""全ヒーローの効果と共通テクスチャを作り直す（Effects/Effekseer/ へ）。usage: python3 tools/effekseer/build_all.py [hero…]"""
import importlib
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "heroes"))

HEROES = ["h001", "h003", "h007", "h008", "h009", "h011", "h012", "h013", "h016", "h019", "h020", "h024",
          "h025", "h026", "h027", "h028", "h029", "h030", "h031", "h032", "h033", "h034"]


def main():
    want = [a.lower() for a in sys.argv[1:]] or HEROES
    if not sys.argv[1:]:
        importlib.import_module("textures").main()
    for h in want:
        m = importlib.import_module(h)
        if hasattr(m, "build"):
            from kit import build_set
            build_set(m.build())
        else:
            m.build_all()


if __name__ == "__main__":
    main()
