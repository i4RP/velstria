"""試合の外の画面の音（タップ・決定・戻る・タブ・失敗・購入・報酬・秒読み・勝敗・マッチ成立・ピック・バン・試合開始）。

電子音（Kenney の Interface Sounds の blip・beep）をやめ、軽い打鍵・紙・カード・硬貨・金属・鐘・打楽器の実音の録音に寄せる
（MLBB の UI の手触り。2026-10-20 ユーザー指示）。ファイル名は今までと同じ（AudioFiles.sfx）。
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from sfxlib import *  # noqa: E402,F401,F403


def build():
    # タップ: タイプライターの鍵の軽い打鍵（高い所だけ）
    write("sfx_ui_tap", sn("Typewriter Space Key, Typewriter 05", p=1.15, g=0, hp=1500, hit=True, length=0.12),
          "ui", "タップ: タイプライターの鍵の軽い打鍵", target=-30.0)
    # 決定: 鍵の打鍵 + 卓上ベルの短い鳴り
    write("sfx_ui_confirm", mix([
        (0.0, sn("Typewriter Space Key, Typewriter 05", p=1.0, g=-4, hp=900, hit=True, length=0.12)),
        (0.01, sn("Bell_Waiter_Fienup_001", p=1.25, g=-6, hit=True, length=0.45))]),
        "ui", "決定: 鍵の打鍵 + 卓上ベルの鳴り", target=-26.0)
    # 戻る: 羊皮紙をめくる短い音
    write("sfx_ui_back", sn("Paper_Pergament_Pages_Turn_Flip_20", p=1.1, g=0, hp=600, start=0.05, length=0.3),
          "ui", "戻る: 羊皮紙をめくる音", target=-28.0)
    # タブの切替: カードをフェルトに置く音
    write("sfx_ui_tab", sn("Deck of cards dealt on to felt table surface 43", p=1.05, g=0, hit=True, length=0.25),
          "ui", "タブ: カードをフェルトに置く音", target=-29.0)
    # 失敗: 木の柄の鈍い打音（低く）
    write("sfx_ui_error", mix([
        (0.0, sn("STICK HIT-07", 0, p=0.7, g=0, lp=2500, hit=True, length=0.2)),
        (0.08, sn("STICK HIT-07", 0, p=0.62, g=-4, lp=2000, hit=True, length=0.2))]),
        "ui", "失敗: 木の鈍い打音を 2 つ", target=-26.0)
    # 購入: 硬貨が革袋に落ちる + 古いレジのベル
    write("sfx_purchase", mix([
        (0.0, sn("Coins_Pouch_Leather_Drop_Into_Takes_3", 0, p=1.0, g=0, hit=True, length=0.55)),
        (0.12, sn("Antique-Cash-Register_07", 0, p=1.0, g=-6, length=0.6))]),
        "ui", "購入: 硬貨が革袋に落ちる + 古いレジ", target=-24.0, cap=0.9)
    # 報酬: 硬貨の鳴り + 風鈴
    write("sfx_reward", mix([
        (0.0, sn("Coins_Hand_Jingle_Movement_Takes_6", 3, p=1.0, g=0, hit=True, length=0.5)),
        (0.05, sn("windbell,Japanese,porcelain", p=1.1, g=-2, length=0.9))]),
        "ui", "報酬: 硬貨の鳴り + 磁器の風鈴", target=-24.0, cap=1.2)
    # 秒読み: 木の短い打音（時計の刻み）
    write("sfx_countdown", sn("WOODEN SWORD HIT-11", p=1.3, g=0, hp=800, hit=True, length=0.15),
          "ui", "秒読み: 木の短い打音", target=-25.0)
    # 勝利: ティンパニ + 銅鑼 + ベルツリー
    write("sfx_victory", tail(mix([
        (0.0, sn("Timpani_Hit_Fienup_001", p=1.0, g=0, hit=True, length=2.0)),
        (0.0, sn("80,TheGong", p=1.0, g=-3, hit=True, length=2.6)),
        (0.15, sn("BELL TREE UP DOWN", 0, p=1.0, g=-6, length=1.6))]), 2.4, 3.0),
        "stinger", "勝利: ティンパニ + 銅鑼 + ベルツリー", target=-17.0)
    # 敗北: 低い角笛のブラーム + 低いティンパニ
    write("sfx_defeat", tail(mix([
        (0.0, sn("Cinematic Horn Braam, Epic, Cinematic, Dark, Instrument, Huge-32", p=0.9, g=0, length=2.6)),
        (0.0, sn("Timpani_Hit_Fienup_001", p=0.75, g=-4, hit=True, length=2.0))]), 2.4, 3.0),
        "stinger", "敗北: 低い角笛のブラーム + 低いティンパニ", target=-18.0)
    # マッチ成立: 鉢の一打 + 卓上ベル
    write("sfx_match_found", tail(mix([
        (0.0, sn("SINGING_BOWL_Strike_Sustain_D_02", p=1.35, g=0, hit=True, length=1.8)),
        (0.0, sn("Bell_Waiter_Fienup_001", p=1.0, g=-6, hit=True, length=0.8))]), 1.4, 1.9),
        "ui", "マッチ成立: 鉢の一打 + 卓上ベル", target=-21.0, cap=2.0)
    # ピックの確定: 金属の留め金 + 刃の鳴り
    write("sfx_lock_in", mix([
        (0.0, sn("Metal_Barrel_Bolt_Lock", p=1.0, g=-2, length=0.35)),
        (0.03, sn("Knife_Sword_Shing", 0, p=1.0, g=-4, hp=1500, length=0.6, hit=True))]),
        "ui", "ピックの確定: 金属の留め金 + 刃の鳴り", target=-22.0, cap=1.0)
    # バン: 重い打撃（判を押す）+ 太鼓の低音
    write("sfx_ban", mix([
        (0.0, sn("HORROR - Hammer Impact, huge", 1, p=0.85, g=0, lp=4000, hit=True, length=0.5)),
        (0.0, sn("Impact_Drum Hit_03", p=1.0, g=-4, hit=True, length=0.9))]),
        "ui", "バン: 重い打撃 + 太鼓の低音", target=-21.0, cap=1.2)
    # 試合開始の合図: 銅鑼 + ティンパニ + 角笛
    write("sfx_match_start", tail(mix([
        (0.0, sn("PotGong", p=1.0, g=0, hit=True, length=2.2)),
        (0.0, sn("Timpani_Hit_Fienup_001", p=0.9, g=-2, hit=True, length=2.0)),
        (0.05, sn("Cinematic Horn Braam, Epic, Cinematic, Dark, Instrument, Huge-32", p=1.05, g=-6, length=1.8))]), 1.8, 2.3),
        "stinger", "試合開始: 銅鑼 + ティンパニ + 角笛", target=-18.0)
