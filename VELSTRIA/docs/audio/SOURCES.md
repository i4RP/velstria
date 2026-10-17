# 音の素材の出典（自動生成: tools/audio/build_audio.py）

アプリに入れている音のファイルは、下の CC0 の素材を加工（切り出し・重ね・音程・音量・残響・形式の変換）したもの。
MLBB の音は使っていない。素材の原本・素材集の形ではリポジトリに入れない（tools/audio/.cache に落として加工する）。
ライセンス: すべて CC0 1.0（https://creativecommons.org/publicdomain/zero/1.0/）。帰属表示は必須ではないが、アプリ内の「クレジット > 音楽・効果音」と下の表に記す。

## 素材

| 素材 | 作者 | ライセンス | URL |
|---|---|---|---|
| Interface Sounds | Kenney | CC0 1.0 | https://kenney.nl/assets/interface-sounds |
| Impact Sounds | Kenney | CC0 1.0 | https://kenney.nl/assets/impact-sounds |
| RPG Audio | Kenney | CC0 1.0 | https://kenney.nl/assets/rpg-audio |
| Sci-Fi Sounds | Kenney | CC0 1.0 | https://kenney.nl/assets/sci-fi-sounds |
| Digital Audio | Kenney | CC0 1.0 | https://kenney.nl/assets/digital-audio |
| Music Jingles | Kenney | CC0 1.0 | https://kenney.nl/assets/music-jingles |
| Casino Audio | Kenney | CC0 1.0 | https://kenney.nl/assets/casino-audio |
| A Legend Will Rise | CodeManu | CC0 1.0 | https://opengameart.org/content/a-legend-will-rise-orchestral |
| Fantasy Orchestral Theme | Joth | CC0 1.0 | https://opengameart.org/content/fantasy-orchestral-theme |
| Treasure Hunter | TAD | CC0 1.0 | https://opengameart.org/content/treasure-hunter |
| Once Upon a Time (loop) | TAD | CC0 1.0 | https://opengameart.org/content/once-upon-a-time-loop |
| Battle Theme | Wolfgang_ | CC0 1.0 | https://opengameart.org/content/battle-theme-0 |
| Final Stand | iamoneabe | CC0 1.0 | https://opengameart.org/content/final-stand |
| Intro Cue | Vehicle | CC0 1.0 | https://opengameart.org/content/intro-cue |
| At Home (orchestral) | Wolfgang_ | CC0 1.0 | https://opengameart.org/content/at-home-orchestral |

## 出力（App/Resources/Audio）

| ファイル | 長さ | 素材 | 加工 |
|---|---|---|---|
| bgm_draft.m4a | 116.11 秒 | Battle Theme | ヒーロー選択（ピック） |
| bgm_draft_tense.m4a | 64.00 秒 | Final Stand | ヒーロー選択の残り時間が少ない時 |
| bgm_home_fantasia.m4a | 191.69 秒 | Fantasy Orchestral Theme | ホームの選べる曲「幻想の序曲」 |
| bgm_home_journey.m4a | 65.07 秒 | Treasure Hunter | ホームの選べる曲「宝探しの旅」 |
| bgm_home_legend.m4a | 69.64 秒 | A Legend Will Rise | ホームの選べる曲「伝説の夜明け」 |
| bgm_loading.m4a | 43.26 秒 | Intro Cue | ロード画面（試合開始へつなぐ） |
| bgm_lobby.m4a | 57.60 秒 | Once Upon a Time (loop) | ロビー・パーティ・ヒーロー選択（通常） |
| bgm_result.m4a | 74.32 秒 | At Home (orchestral) | 結果画面 |
| sfx_ban.caf | 0.68 秒 | Music Jingles・Impact Sounds・Digital Audio | jingles_HIT13 + impactPunch_heavy_000（低く）+ lowDown（バン） |
| sfx_countdown.caf | 0.12 秒 | Interface Sounds | tick_004 + bong_001 を重ねた（残り秒の秒読み） |
| sfx_defeat.caf | 1.74 秒 | Music Jingles | jingles_HIT09（こもらせた）+ jingles_PIZZI01、残響（敗北） |
| sfx_lock_in.caf | 0.56 秒 | Music Jingles・Impact Sounds・Interface Sounds | jingles_HIT07 + impactMetal_heavy_000 + confirmation_002（ピック確定） |
| sfx_match_found.caf | 1.38 秒 | Music Jingles | jingles_HIT10 + jingles_PIZZI15、残響（マッチ成立） |
| sfx_match_start.caf | 2.09 秒 | Music Jingles・Impact Sounds | jingles_HIT03 + impactPlate_heavy_000（低く）+ jingles_HIT15、残響（試合開始の合図） |
| sfx_purchase.caf | 0.37 秒 | Casino Audio・Interface Sounds | chips-stack-1 + confirmation_003 を重ねた |
| sfx_reward.caf | 1.10 秒 | Music Jingles・Interface Sounds | jingles_PIZZI10 + glass_001、残響 |
| sfx_ui_back.caf | 0.07 秒 | Interface Sounds | back_002 |
| sfx_ui_confirm.caf | 0.29 秒 | Interface Sounds | confirmation_001 |
| sfx_ui_error.caf | 0.10 秒 | Interface Sounds | error_004 |
| sfx_ui_tab.caf | 0.14 秒 | Interface Sounds | switch_002 |
| sfx_ui_tap.caf | 0.04 秒 | Interface Sounds | select_002 |
| sfx_victory.caf | 1.81 秒 | Music Jingles | jingles_HIT11 + jingles_PIZZI02、残響（勝利） |
| skill_H025_s1_cast.caf | 0.66 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H025 s1 の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H025_s2_cast.caf | 1.69 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H025 s2 の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H025_s2_hit.caf | 0.54 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H025 s2 の命中 |
| skill_H025_ult_cast.caf | 1.85 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H025 ult の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H026_s1_cast.caf | 1.11 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H026 s1 の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H026_s1_hit.caf | 0.80 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H026 s1 の命中 |
| skill_H026_s2_cast.caf | 1.28 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H026 s2 の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H026_s2_hit.caf | 0.79 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H026 s2 の命中 |
| skill_H026_ult_cast.caf | 2.25 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H026 ult の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H026_ult_hit.caf | 0.80 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H026 ult の命中 |
| skill_H027_s1_cast.caf | 1.17 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H027 s1 の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H027_s1_hit.caf | 0.36 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H027 s1 の命中 |
| skill_H027_s2_cast.caf | 0.64 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H027 s2 の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H027_s2_hit.caf | 0.40 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H027 s2 の命中 |
| skill_H027_ult_cast.caf | 1.44 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H027 ult の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H028_s1_cast.caf | 1.11 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H028 s1 の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H028_s1_hit.caf | 0.35 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H028 s1 の命中 |
| skill_H028_s2_cast.caf | 0.88 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H028 s2 の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H028_s2_hit.caf | 0.42 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H028 s2 の命中 |
| skill_H028_ult_cast.caf | 1.75 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H028 ult の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H028_ult_hit.caf | 0.44 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H028 ult の命中 |
| skill_H029_s1_cast.caf | 1.78 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H029 s1 の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H029_s1_hit.caf | 0.47 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H029 s1 の命中 |
| skill_H029_s2_cast.caf | 1.42 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H029 s2 の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H029_s2_hit.caf | 0.47 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H029 s2 の命中 |
| skill_H029_s2_r1_cast.caf | 0.97 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H029 s2 段1 の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H029_ult_cast.caf | 3.30 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H029 ult の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H029_ult_hit.caf | 0.57 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H029 ult の命中 |
| skill_H030_s1_cast.caf | 1.03 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H030 s1 の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H030_s1_hit.caf | 0.80 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H030 s1 の命中 |
| skill_H030_s2_cast.caf | 0.64 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H030 s2 の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H030_s2_hit.caf | 0.79 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H030 s2 の命中 |
| skill_H030_ult_cast.caf | 3.42 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H030 ult の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H030_ult_hit.caf | 0.80 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H030 ult の命中 |
| skill_H031_s1_cast.caf | 1.20 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H031 s1 の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H031_s1_hit.caf | 0.48 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H031 s1 の命中 |
| skill_H031_s2_cast.caf | 0.97 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H031 s2 の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H031_s2_hit.caf | 0.20 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H031 s2 の命中 |
| skill_H031_ult_cast.caf | 2.65 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H031 ult の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H031_ult_hit.caf | 0.24 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H031 ult の命中 |
| skill_H032_s1_cast.caf | 1.29 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H032 s1 の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H032_s1_hit.caf | 0.69 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H032 s1 の命中 |
| skill_H032_s2_cast.caf | 1.56 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H032 s2 の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H032_s2_hit.caf | 0.61 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H032 s2 の命中 |
| skill_H032_s2_r1_cast.caf | 0.84 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H032 s2 段1 の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H032_ult_cast.caf | 2.85 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H032 ult の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H032_ult_hit.caf | 0.65 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H032 ult の命中 |
| skill_H033_s1_cast.caf | 1.14 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H033 s1 の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H033_s1_hit.caf | 0.40 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H033 s1 の命中 |
| skill_H033_s2_cast.caf | 0.65 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H033 s2 の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H033_s2_hit.caf | 0.44 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H033 s2 の命中 |
| skill_H033_ult_cast.caf | 1.43 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H033 ult の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H033_ult_hit.caf | 0.45 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H033 ult の命中 |
| skill_H033_ult_r1_cast.caf | 1.23 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H033 ult 段1 の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H034_s1_cast.caf | 1.42 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H034 s1 の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H034_s1_hit.caf | 0.47 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H034 s1 の命中 |
| skill_H034_s2_cast.caf | 2.49 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H034 s2 の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H034_s2_hit.caf | 0.49 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H034 s2 の命中 |
| skill_H034_ult_cast.caf | 0.69 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H034 ult の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H034_ult_hit.caf | 0.71 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H034 ult の命中 |
