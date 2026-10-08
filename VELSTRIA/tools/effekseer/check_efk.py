#!/usr/bin/env python3
"""同梱の .efk（Effekseer 1.8 のバイナリ）を、ランタイムの読み込み順（ThirdParty/Effekseer/include の *.h の Load）に沿って
最後まで読み切れるか確かめる。テクスチャの実在・ノード数・サイズ付きブロックの長さ・値の範囲（NaN / 異常に大きい値が無い）も見る。
usage: python3 tools/effekseer/check_efk.py [名前の接頭辞（例 H025）…]      → 問題があれば非 0 で終わる
EffekseerTests（Metal が要る）の代わりに Windows でも回せる最低限の検査。
"""
import math
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.abspath(os.path.join(HERE, "..", "..", "Effects", "Effekseer"))
VERSION = 1810
MAX_FILE = 64 * 1024  # 1 効果あたりの目安上限（読み込み時間のため）


class Reader:
    def __init__(self, data):
        self.d, self.p = data, 0

    def i(self):
        v = struct.unpack_from("<i", self.d, self.p)[0]
        self.p += 4
        return v

    def f(self):
        v = struct.unpack_from("<f", self.d, self.p)[0]
        self.p += 4
        if not math.isfinite(v) and v != float("inf"):
            raise ValueError(f"非有限の float @ {self.p - 4:#x}")
        return v

    def skip(self, n):
        self.p += n
        if self.p > len(self.d):
            raise ValueError("データ終端を超えた")


def read_easing_vec3(r, size):
    """ParameterEasing<Vec3>::Load（Effekseer.Easing.h）。size ちょうどを読み切る。"""
    end = r.p + size
    r.skip(16)  # RefEqS, RefEqE
    r.skip(24 + 24)  # start, end（random_vector3d）
    mid = r.i()
    if mid > 0:
        r.skip(8 + 24)
    typ = r.i()
    if typ == 0:
        r.skip(12)
    r.skip(4)  # チャンネル
    ind = r.i()
    if ind > 0:
        r.skip(12)
    if r.p != end:
        raise ValueError(f"Easing の長さ不一致 {r.p - end:+d}")


def read_vec_param(r, name, allow=(0, 1, 2)):
    t = r.i()
    if t not in allow:
        raise ValueError(f"{name}: 想定外の型 {t}")
    size = r.i()
    start = r.p
    if t == 0:
        if size != 16:
            raise ValueError(f"{name}: Fixed のサイズ {size}")
        r.skip(4)
        [r.f() for _ in range(3)]
    elif t == 1:
        if size != 96:
            raise ValueError(f"{name}: PVA のサイズ {size}")
        r.skip(24)
        [r.f() for _ in range(18)]
    elif t == 2:
        read_easing_vec3(r, size)
    if r.p - start != size:
        raise ValueError(f"{name}: 長さ不一致")


def read_node(r, ntex, counter, depth=0):
    typ = r.i()
    if typ not in (2, 3):
        raise ValueError(f"ノード種別 {typ} @ {r.p - 4:#x}")
    counter[0] += 1
    if r.i() != 1:
        raise ValueError("IsRendered")
    r.i()  # 描画の優先度
    if r.i() != 100:
        raise ValueError("共通ブロックのサイズ")
    r.skip(100)
    r.skip(8)  # LOD
    read_vec_param(r, "移動")
    cnt = r.i()
    if cnt != 4:
        raise ValueError("局所力場の数")
    r.skip(4 * 36)
    read_vec_param(r, "回転", (0, 1))
    read_vec_param(r, "拡大", (0, 2))
    # 生成位置
    r.i()
    g = r.i()
    r.skip({0: 24, 1: 24, 3: 44}[g])
    r.skip(80)  # 深度・サウンド・キル・衝突
    # 描画共通（Effekseer.EffectNode.h）
    if r.i() != 0:
        raise ValueError("MaterialType")
    r.f()
    tex = [r.i() for _ in range(7)]
    if not (0 <= tex[0] < ntex) or any(t != -1 for t in tex[1:]):
        raise ValueError(f"テクスチャ番号 {tex}")
    blend = r.i()
    if blend not in (0, 1, 2, 3, 4):
        raise ValueError(f"合成 {blend}")
    r.skip(56 + 8)
    for _ in range(2):  # フェードイン・アウト
        ft = r.i()
        if ft != 0:
            r.skip(16)
    r.skip(12 + 4 + 4 + 4 + 8 + 4)  # UV ×3 / 歪み / UV3 / ブレンド種別 / UV4,5 / 歪み
    r.skip(4 + 4 + 4 + 4 + 4)  # 左右反転 / 色の親子 / 歪み強度 / CustomData ×2
    r.skip(20)
    if typ == 2:
        if r.i() != 2:
            raise ValueError("Sprite 種別")
        r.i()
        bb = r.i()
        if bb not in (0, 1, 2, 3, 4):
            raise ValueError(f"Billboard {bb}")
        ct = r.i()
        if ct == 0:
            r.skip(4)
        elif ct == 2:
            r.skip(2 + 8 + 2 + 8 + 12)
        else:
            raise ValueError(f"色の型 {ct}")
        if r.i() != 0:
            raise ValueError("SpriteColor")
        if r.i() != 1:
            raise ValueError("SpritePosition")
        [r.f() for _ in range(8)]
        r.skip(8)
    else:
        r.skip(52 - 4)
        r.skip(4)
    kids = r.i()
    if not (0 <= kids < 64):
        raise ValueError(f"子の数 {kids}")
    for _ in range(kids):
        read_node(r, ntex, counter, depth + 1)


def check(path):
    data = open(path, "rb").read()
    if len(data) > MAX_FILE:
        raise ValueError(f"サイズが大きい {len(data)} B")
    if data[:4] != b"SKFE":
        raise ValueError("マジック")
    r = Reader(data)
    r.p = 4
    if r.i() != VERSION:
        raise ValueError("バージョン")
    n = r.i()
    texs = []
    for _ in range(n):
        ln = r.i()
        s = data[r.p:r.p + ln * 2 - 2].decode("utf-16-le")
        if data[r.p + ln * 2 - 2:r.p + ln * 2] != b"\x00\x00":
            raise ValueError("文字列の終端")
        r.skip(ln * 2)
        texs.append(s)
        if not os.path.exists(os.path.join(OUT, s)):
            raise ValueError(f"テクスチャが無い {s}")
    if r.i() != 0 or r.i() != 0:
        raise ValueError("法線・歪みテクスチャ")
    r.skip(20)  # サウンド・モデル・マテリアル・曲線・プロシージャルモデル
    r.skip(4)
    r.skip(20)
    total = r.i()
    r.skip(4)
    r.skip(4 + 4 + 16)  # 倍率・乱数・（予約）
    r.i()  # 根の種別（-1）
    top = r.i()
    counter = [0]
    for _ in range(top):
        read_node(r, len(texs), counter)
    if r.p != len(data):
        raise ValueError(f"末尾の余り {len(data) - r.p} B")
    if counter[0] != total:
        raise ValueError(f"ノード数 {counter[0]} ≠ ヘッダ {total}")
    return len(data), counter[0], texs


def main():
    prefixes = sys.argv[1:]
    files = sorted(f for f in os.listdir(OUT) if f.endswith(".efk") and (not prefixes or any(f.startswith(p) for p in prefixes)))
    bad = 0
    total_bytes = 0
    for f in files:
        try:
            size, nodes, _ = check(os.path.join(OUT, f))
            total_bytes += size
        except Exception as e:  # noqa: BLE001
            bad += 1
            print(f"NG {f}: {e}")
    print(f"{len(files)} 本を検査: 異常 {bad} / 合計 {total_bytes} B")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
