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
| skill_H027_s1_cast.caf | 1.20 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H027 s1 の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H027_s1_hit.caf | 0.36 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H027 s1 の命中 |
| skill_H027_s2_cast.caf | 0.64 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H027 s2 の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H027_s2_hit.caf | 0.40 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H027 s2 の命中 |
| skill_H027_ult_cast.caf | 1.44 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H027 ult の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H028_s1_cast.caf | 1.12 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H028 s1 の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H028_s1_hit.caf | 0.35 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H028 s1 の命中 |
| skill_H028_s2_cast.caf | 0.88 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H028 s2 の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H028_s2_hit.caf | 0.42 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H028 s2 の命中 |
| skill_H028_ult_cast.caf | 1.75 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H028 ult の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H028_ult_hit.caf | 0.44 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H028 ult の命中 |
| skill_H030_s1_cast.caf | 1.13 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H030 s1 の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H030_s1_hit.caf | 0.80 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H030 s1 の命中 |
| skill_H030_s2_cast.caf | 0.69 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H030 s2 の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H030_s2_hit.caf | 0.79 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H030 s2 の命中 |
| skill_H030_ult_cast.caf | 3.50 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H030 ult の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H030_ult_hit.caf | 0.80 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H030 ult の命中 |
| skill_H031_s1_cast.caf | 1.20 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H031 s1 の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H031_s1_hit.caf | 0.48 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H031 s1 の命中 |
| skill_H031_s2_cast.caf | 1.17 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H031 s2 の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
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
| skill_H033_s2_cast.caf | 0.71 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H033 s2 の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H033_s2_hit.caf | 0.44 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H033 s2 の命中 |
| skill_H033_ult_cast.caf | 1.43 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H033 ult の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H033_ult_hit.caf | 0.45 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H033 ult の命中 |
| skill_H033_ult_r1_cast.caf | 1.23 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H033 ult 段1 の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |

## Sonniss GDC Game Audio Bundle（録音の音: tools/audio/make_sounds.py）

Sonniss の GDC Game Audio Bundle（無料・商用可・帰属表示は不要。素材のまま再配布・販売しない、AI の学習に使わない）の
録音を、重ね・切り出し・音程・帯域・音量・残響で加工した完成品だけを置く（原本・素材集の形ではリポジトリに入れない）。
ライセンス: https://sonniss.com/gdc-bundle-license/　配布: https://gdc.sonniss.com/（同じ素材を archive.org の写し
sonniss-gdc-<年>-game-audio-bundle-normalized から、使う素材だけ落とした。tools/audio/sonniss_lib.py）。

| 素材集 | 作者 | ライセンス | URL |
|---|---|---|---|
| Twisted Zither（GDC 2015） | RDGSFX009 | Sonniss GDC | https://gdc.sonniss.com/ |
| Natures Fury_Thunder（GDC 2015） | Soundopolis | Sonniss GDC | https://gdc.sonniss.com/ |
| The Source Collection SFX Pack（GDC 2016） | George Karagioules | Sonniss GDC | https://gdc.sonniss.com/ |
|  Just Whoosh 3 _ Whoosh Essentials（GDC 2016） | SoundBits | Sonniss GDC | https://gdc.sonniss.com/ |
| Ice SFX（GDC 2016） | Stuart Duffield | Sonniss GDC | https://gdc.sonniss.com/ |
| Thin Ice（GDC 2017） | Articulated Sounds | Sonniss GDC | https://gdc.sonniss.com/ |
| Unsettling Creaks and Squeaks（GDC 2017） | SoundBits | Sonniss GDC | https://gdc.sonniss.com/ |
| Unsettling Creaks and Squeaks – Extension I（GDC 2017） | SoundBits | Sonniss GDC | https://gdc.sonniss.com/ |
| High Voltage Electricity - The Essential Collection（GDC 2018） | Hear and Now Sound | Sonniss GDC | https://gdc.sonniss.com/ |
| Foley Elements Ice and Snow（GDC 2018） | Soundrangers | Sonniss GDC | https://gdc.sonniss.com/ |
| Thunder（GDC 2018） | Soundrangers | Sonniss GDC | https://gdc.sonniss.com/ |
| Electric Deluxe（GDC 2018） | Wakerone | Sonniss GDC | https://gdc.sonniss.com/ |
| Super Heroes Sound Design（GDC 2019） | 2496SoundEffects | Sonniss GDC | https://gdc.sonniss.com/ |
| Low Frequency Elements（GDC 2019） | 344 Audio | Sonniss GDC | https://gdc.sonniss.com/ |
| IMPACTUS（GDC 2019） | 3maze | Sonniss GDC | https://gdc.sonniss.com/ |
| Organic Whooshes（GDC 2019） | Airborne Sound | Sonniss GDC | https://gdc.sonniss.com/ |
| Magic Elements vol.1（GDC 2019） | Articulated Sounds | Sonniss GDC | https://gdc.sonniss.com/ |
| IMPACT（GDC 2019） | Baxter Audio | Sonniss GDC | https://gdc.sonniss.com/ |
| Heavy Metal Impact Sound Effects（GDC 2019） | BlueZone | Sonniss GDC | https://gdc.sonniss.com/ |
| Wood Sound Effects（GDC 2019） | BlueZone | Sonniss GDC | https://gdc.sonniss.com/ |
| Helina（GDC 2019） | Eiravaein Works | Sonniss GDC | https://gdc.sonniss.com/ |
| Nocked（GDC 2019） | Eiravaein Works | Sonniss GDC | https://gdc.sonniss.com/ |
| Effective Trailer Booms（GDC 2019） | Federico Soler Fernández | Sonniss GDC | https://gdc.sonniss.com/ |
| Effective Trailer Hits & Impacts（GDC 2019） | Federico Soler Fernández | Sonniss GDC | https://gdc.sonniss.com/ |
| Effective Trailer Whooshes（GDC 2019） | Federico Soler Fernández | Sonniss GDC | https://gdc.sonniss.com/ |
| Singing Bowls（GDC 2019） | Prismo Sound | Sonniss GDC | https://gdc.sonniss.com/ |
| Bodyfall（GDC 2019） | Red Libraries | Sonniss GDC | https://gdc.sonniss.com/ |
| Melee（GDC 2019） | Rock The Speakerbox | Sonniss GDC | https://gdc.sonniss.com/ |
| Gore（GDC 2019） | Sound Spark LLC | Sonniss GDC | https://gdc.sonniss.com/ |
| Magic Spells, Buffs and Attacks（GDC 2019） | Sound Spark LLC | Sonniss GDC | https://gdc.sonniss.com/ |
| Metal Hits, Scrapes and Squeaks（GDC 2019） | Sound Spark LLC | Sonniss GDC | https://gdc.sonniss.com/ |
| Trailer Instruments Designed（GDC 2020） | 344 Audio | Sonniss GDC | https://gdc.sonniss.com/ |
| Metal Chains（GDC 2020） | Conor Bradley | Sonniss GDC | https://gdc.sonniss.com/ |
| Weapon Sounds - Weapon Swings（GDC 2020） | David Dumais Audio | Sonniss GDC | https://gdc.sonniss.com/ |
| Lethal Blow（GDC 2020） | PMSFX | Sonniss GDC | https://gdc.sonniss.com/ |
| Hit & Punch（GDC 2020） | Shapeforms | Sonniss GDC | https://gdc.sonniss.com/ |
| Impacts, Hits & Whooshes（GDC 2020） | SmartSoundFX | Sonniss GDC | https://gdc.sonniss.com/ |
| Medieval（GDC 2020） | SmartSoundFX | Sonniss GDC | https://gdc.sonniss.com/ |
| Flesh, Bones & Gore（GDC 2023） | 344 Audio | Sonniss GDC | https://gdc.sonniss.com/ |
| Melee Weapons Sound Effects Pack 1（GDC 2023） | David Dumais Audio | Sonniss GDC | https://gdc.sonniss.com/ |
| Essentials 01 Thunder（GDC 2023） | InspectorJ | Sonniss GDC | https://gdc.sonniss.com/ |
| Essentials 04 Chains（GDC 2023） | InspectorJ | Sonniss GDC | https://gdc.sonniss.com/ |
| Druid Magic（GDC 2023） | Rogue Waves | Sonniss GDC | https://gdc.sonniss.com/ |
| High Voltage（GDC 2024） | BluezoneCorp | Sonniss GDC | https://gdc.sonniss.com/ |
| Stone Impact（GDC 2024） | BluezoneCorp | Sonniss GDC | https://gdc.sonniss.com/ |
| Haunted Metal Vol.1 - Cinematic Hits & Impacts（GDC 2024） | Jake Fielding | Sonniss GDC | https://gdc.sonniss.com/ |
| Melee Weapons（GDC 2024） | Justsoundeffects | Sonniss GDC | https://gdc.sonniss.com/ |
| The Metal Hit Sweeteners Library（GDC 2024） | Pole Position | Sonniss GDC | https://gdc.sonniss.com/ |
| Distinct Whooshes（GDC 2024） | Rescopic Sound | Sonniss GDC | https://gdc.sonniss.com/ |
| Cinematic Fight Vol. 1（GDC 2026） | 344 Audio | Sonniss GDC | https://gdc.sonniss.com/ |
| Elemental Palette Designed Vol. 1（GDC 2026） | 344 Audio | Sonniss GDC | https://gdc.sonniss.com/ |
| Emotion and Magic（GDC 2026） | Alexander Kopeikin | Sonniss GDC | https://gdc.sonniss.com/ |
| Melee Weapons Sound Effects Pack 2（GDC 2026） | David Dumais Audio | Sonniss GDC | https://gdc.sonniss.com/ |
| Elemental Mutation Whooshes and Impacts（GDC 2026） | Epic Stock Media | Sonniss GDC | https://gdc.sonniss.com/ |

### 出力（App/Resources/Audio、48 kHz）

| ファイル | 長さ | 素材 | 加工 |
|---|---|---|---|
| skill_H025_passive.caf | 0.43 秒 | RDGSFX009 - Twisted Zither・George Karagioules - The Source Collection SFX Pack・Eiravaein Works - Helina | 弓の先の閃き（弦の小さな鳴り + ガラスの一打 + 風鈴） |
| skill_H025_s1_cast.caf | 0.98 秒 | George Karagioules - The Source Collection SFX Pack・SoundBits - Unsettling Creaks and Squeaks – Extension I・Airborne Sound - Organic Whooshes・Eiravaein Works - Helina・Eiravaein Works - Nocked・Prismo Sound - Singing Bowls | 矢をつがえる弦と革のきしみ → ガラスの一打と風鈴（月光）+ 布の風 + 低いボウルの響き |
| skill_H025_s2_cast.caf | 1.44 秒 | George Karagioules - The Source Collection SFX Pack・SoundBits - Unsettling Creaks and Squeaks・Soundrangers - Foley Elements Ice and Snow・2496SoundEffects - Super Heroes Sound Design・Baxter Audio - IMPACT・BlueZone - Wood Sound Effects・Eiravaein Works - Nocked・SmartSoundFX – Medieval・Epic Stock Media - Elemental Mutation Whooshes and Impacts | 弓を引き絞る（弦・木・革）→ 弦の弾けと天へ抜ける矢 → 0.65 着弾（矢が地に刺さる・氷のひび・低い芯）→ 0.98 小さな矢が散る |
| skill_H025_s2_hit_1.caf | 0.45 秒 | Stuart Duffield - Ice SFX・Articulated Sounds - Thin Ice・Soundrangers - Foley Elements Ice and Snow・Baxter Audio - IMPACT・SmartSoundFX – Medieval | 矢が刺さる + 氷の檻のひび・砕け + 霜 + 低い芯 |
| skill_H025_s2_hit_2.caf | 0.45 秒 | Stuart Duffield - Ice SFX・Articulated Sounds - Thin Ice・Soundrangers - Foley Elements Ice and Snow・Baxter Audio - IMPACT・SmartSoundFX – Medieval | 矢が刺さる + 氷の檻のひび・砕け + 霜 + 低い芯 |
| skill_H025_s2_hit_3.caf | 0.45 秒 | Articulated Sounds - Thin Ice・Soundrangers - Foley Elements Ice and Snow・3maze - IMPACTUS・Baxter Audio - IMPACT・SmartSoundFX – Medieval | 矢が刺さる + 氷の檻のひび・砕け + 霜 + 低い芯 |
| skill_H025_ult_cast.caf | 1.63 秒 | George Karagioules - The Source Collection SFX Pack・Airborne Sound - Organic Whooshes・Eiravaein Works - Helina・Prismo Sound - Singing Bowls・Rescopic Sound - Distinct Whooshes・Epic Stock Media - Elemental Mutation Whooshes and Impacts | 身を翻す布の風 → 三日月と光の柱（ボウル・ガラス・風鈴・ガラス片の流れ）→ 加速の風 + 低いボウルのうねり |
| skill_H026_passive.caf | 0.33 秒 | Hear and Now Sound - High Voltage Electricity - The Essential Collection・Rogue Waves - Druid Magic・BluezoneCorp - High Voltage | 超伝導の印（小さな放電の弾け + ぱちぱち） |
| skill_H026_s1_cast.caf | 0.86 秒 | Hear and Now Sound - High Voltage Electricity - The Essential Collection・Soundrangers – Thunder・InspectorJ - Essentials 01 Thunder・BluezoneCorp - High Voltage | 杖の火花 → 0.05 稲妻が裂ける（間近の雷鳴・放電の弾け・低い雷の芯）→ 電弧のぱちぱち → 雷鳴の尾 |
| skill_H026_s1_hit_1.caf | 0.29 秒 | Soundopolis - Natures Fury_Thunder・Hear and Now Sound - High Voltage Electricity - The Essential Collection・Baxter Audio - IMPACT・Rogue Waves - Druid Magic・BluezoneCorp - High Voltage | 体に走る放電の弾け + ぱちぱち + 短い雷の裂け + 低い芯 |
| skill_H026_s1_hit_2.caf | 0.30 秒 | Soundopolis - Natures Fury_Thunder・Hear and Now Sound - High Voltage Electricity - The Essential Collection・Baxter Audio - IMPACT・Rogue Waves - Druid Magic・BluezoneCorp - High Voltage | 体に走る放電の弾け + ぱちぱち + 短い雷の裂け + 低い芯 |
| skill_H026_s1_hit_3.caf | 0.30 秒 | Soundopolis - Natures Fury_Thunder・Hear and Now Sound - High Voltage Electricity - The Essential Collection・Baxter Audio - IMPACT・Rogue Waves - Druid Magic・BluezoneCorp - High Voltage | 体に走る放電の弾け + ぱちぱち + 短い雷の裂け + 低い芯 |
| skill_H026_s2_cast.caf | 0.64 秒 | SoundBits -  Just Whoosh 3 _ Whoosh Essentials・Hear and Now Sound - High Voltage Electricity - The Essential Collection・BluezoneCorp - High Voltage | 放電が集まる → 投げる（袖の風・放電の弾け）→ 飛ぶ球のアークとうなり |
| skill_H026_s2_hit_1.caf | 0.49 秒 | Soundopolis - Natures Fury_Thunder・Hear and Now Sound - High Voltage Electricity - The Essential Collection・Soundrangers – Thunder・BluezoneCorp - High Voltage | 雷球が弾ける（放電・雷の裂け）+ スタンのぱちぱち + 低い雷の芯 |
| skill_H026_s2_hit_2.caf | 0.49 秒 | Soundopolis - Natures Fury_Thunder・Hear and Now Sound - High Voltage Electricity - The Essential Collection・Soundrangers – Thunder・BluezoneCorp - High Voltage | 雷球が弾ける（放電・雷の裂け）+ スタンのぱちぱち + 低い雷の芯 |
| skill_H026_s2_hit_3.caf | 0.48 秒 | Soundopolis - Natures Fury_Thunder・Hear and Now Sound - High Voltage Electricity - The Essential Collection・Soundrangers – Thunder・BluezoneCorp - High Voltage | 雷球が弾ける（放電・雷の裂け）+ スタンのぱちぱち + 低い雷の芯 |
| skill_H026_ult_cast.caf | 1.87 秒 | Soundopolis - Natures Fury_Thunder・Hear and Now Sound - High Voltage Electricity - The Essential Collection・Soundrangers – Thunder・Wakerone - Electric Deluxe・InspectorJ - Essentials 01 Thunder・BluezoneCorp - High Voltage | 電弧が巡る・遠い雷鳴が吸い込まれる → 0.45 落雷（間近の雷鳴・放電・深い雷の低音）→ 0.59 外側の雷 → 転がる雷鳴 |
| skill_H026_ult_hit_1.caf | 0.46 秒 | Hear and Now Sound - High Voltage Electricity - The Essential Collection・Soundrangers – Thunder・InspectorJ - Essentials 01 Thunder・Rogue Waves - Druid Magic・BluezoneCorp - High Voltage | 体を打つ雷（裂け・放電）+ ぱちぱち + 低い雷の芯 |
| skill_H026_ult_hit_2.caf | 0.46 秒 | Hear and Now Sound - High Voltage Electricity - The Essential Collection・Soundrangers – Thunder・InspectorJ - Essentials 01 Thunder・Rogue Waves - Druid Magic・BluezoneCorp - High Voltage | 体を打つ雷（裂け・放電）+ ぱちぱち + 低い雷の芯 |
| skill_H026_ult_hit_3.caf | 0.46 秒 | Hear and Now Sound - High Voltage Electricity - The Essential Collection・Soundrangers – Thunder・InspectorJ - Essentials 01 Thunder・Rogue Waves - Druid Magic・BluezoneCorp - High Voltage | 体を打つ雷（裂け・放電）+ ぱちぱち + 低い雷の芯 |
| skill_H029_atk_1.caf | 0.44 秒 | Baxter Audio - IMPACT・BlueZone - Heavy Metal Impact Sound Effects・Pole Position - The Metal Hit Sweeteners Library・David Dumais Audio - Melee Weapons Sound Effects Pack 2 | 重い武器の振り → 鈍い着弾 + 槌の金属の鳴り |
| skill_H029_atk_2.caf | 0.43 秒 | Baxter Audio - IMPACT・BlueZone - Heavy Metal Impact Sound Effects・Pole Position - The Metal Hit Sweeteners Library・David Dumais Audio - Melee Weapons Sound Effects Pack 2 | 重い武器の振り → 鈍い着弾 + 槌の金属の鳴り |
| skill_H029_atk_3.caf | 0.43 秒 | Baxter Audio - IMPACT・BlueZone - Heavy Metal Impact Sound Effects・Pole Position - The Metal Hit Sweeteners Library・David Dumais Audio - Melee Weapons Sound Effects Pack 2 | 重い武器の振り → 鈍い着弾 + 槌の金属の鳴り |
| skill_H029_atk_4.caf | 0.44 秒 | Baxter Audio - IMPACT・BlueZone - Heavy Metal Impact Sound Effects・Pole Position - The Metal Hit Sweeteners Library・David Dumais Audio - Melee Weapons Sound Effects Pack 2 | 重い武器の振り → 鈍い着弾 + 槌の金属の鳴り |
| skill_H029_atkhit_1.caf | 0.40 秒 | Justsoundeffects - Melee Weapons | 鎧に当たる金属 |
| skill_H029_atkhit_2.caf | 0.40 秒 | Justsoundeffects - Melee Weapons | 鎧に当たる金属 |
| skill_H029_atkhit_3.caf | 0.40 秒 | Justsoundeffects - Melee Weapons | 鎧に当たる金属 |
| skill_H029_passive.caf | 1.12 秒 | Sound Spark LLC – Magic Spells, Buffs and Attacks・Justsoundeffects - Melee Weapons | 盾の加護（光の音 + 盾のきらめき） |
| skill_H029_s1_cast.caf | 1.59 秒 | 344 Audio - Low Frequency Elements・Articulated Sounds - Magic Elements vol.1・Federico Soler Fernández - Effective Trailer Hits & Impacts・Federico Soler Fernández - Effective Trailer Whooshes・Sound Spark LLC – Magic Spells, Buffs and Attacks・Sound Spark LLC – Metal Hits, Scrapes and Squeaks・BluezoneCorp - Stone Impact・Jake Fielding - Haunted Metal Vol.1 - Cinematic Hits & Impacts・344 Audio - Cinematic Fight Vol. 1 | 叩きつけ（槌・岩・地響き）→ 低音のふくらみ → 3 波目の芯と地鳴り |
| skill_H029_s1_hit_1.caf | 0.69 秒 | Sound Spark LLC – Magic Spells, Buffs and Attacks・BluezoneCorp - Stone Impact | 岩の着弾 + 炎 |
| skill_H029_s1_hit_2.caf | 0.70 秒 | Sound Spark LLC – Magic Spells, Buffs and Attacks・BluezoneCorp - Stone Impact | 岩の着弾 + 炎 |
| skill_H029_s1_hit_3.caf | 0.68 秒 | Sound Spark LLC – Magic Spells, Buffs and Attacks・BluezoneCorp - Stone Impact | 岩の着弾 + 炎 |
| skill_H029_s2_cast.caf | 1.63 秒 | Federico Soler Fernández - Effective Trailer Whooshes・Sound Spark LLC – Magic Spells, Buffs and Attacks・Jake Fielding - Haunted Metal Vol.1 - Cinematic Hits & Impacts・Justsoundeffects - Melee Weapons・344 Audio - Cinematic Fight Vol. 1・David Dumais Audio - Melee Weapons Sound Effects Pack 2 | 盾の金属 + 体の芯 + 突進の風 → 盾の擦れ・地響き → 小さな押し運びの打撃 |
| skill_H029_s2_hit_1.caf | 0.69 秒 | Justsoundeffects - Melee Weapons・344 Audio - Cinematic Fight Vol. 1 | 盾の打撃 + 体への衝撃 |
| skill_H029_s2_hit_2.caf | 0.69 秒 | Justsoundeffects - Melee Weapons・344 Audio - Cinematic Fight Vol. 1 | 盾の打撃 + 体への衝撃 |
| skill_H029_s2_hit_3.caf | 0.69 秒 | Justsoundeffects - Melee Weapons・344 Audio - Cinematic Fight Vol. 1 | 盾の打撃 + 体への衝撃 |
| skill_H029_s2_r1_cast.caf | 1.16 秒 | Federico Soler Fernández - Effective Trailer Booms・Sound Spark LLC – Metal Hits, Scrapes and Squeaks・Pole Position - The Metal Hit Sweeteners Library・344 Audio - Cinematic Fight Vol. 1・David Dumais Audio - Melee Weapons Sound Effects Pack 2 | 振り上げの風 → 槌の金属 + 体の芯 + 低音（打ち上げ） |
| skill_H029_ult_cast.caf | 1.78 秒 | 344 Audio - Low Frequency Elements・Articulated Sounds - Magic Elements vol.1・Federico Soler Fernández - Effective Trailer Hits & Impacts・Federico Soler Fernández - Effective Trailer Whooshes・344 Audio - Trailer Instruments Designed・Jake Fielding - Haunted Metal Vol.1 - Cinematic Hits & Impacts・Justsoundeffects - Melee Weapons・Pole Position - The Metal Hit Sweeteners Library・344 Audio - Cinematic Fight Vol. 1・344 Audio - Elemental Palette Designed Vol. 1・Alexander Kopeikin - Emotion and Magic | 掲げる一撃 → 吸い込み（地鳴り・渦・気・逆再生の打撃）→ 崩落（重い一撃・金属・岩） |
| skill_H029_ult_hit_1.caf | 0.70 秒 | BlueZone - Heavy Metal Impact Sound Effects・BluezoneCorp - Stone Impact | 重い金属の着弾 + 岩 |
| skill_H029_ult_hit_2.caf | 0.70 秒 | BlueZone - Heavy Metal Impact Sound Effects・BluezoneCorp - Stone Impact | 重い金属の着弾 + 岩 |
| skill_H029_ult_hit_3.caf | 0.70 秒 | BlueZone - Heavy Metal Impact Sound Effects・BluezoneCorp - Stone Impact | 重い金属の着弾 + 岩 |
| skill_H034_atk_1.caf | 0.45 秒 | Baxter Audio - IMPACT・Conor Bradley - Metal Chains・Justsoundeffects - Melee Weapons | 斧鉤の打撃（肉と鉄）+ 低い芯 + 鎖の鳴り |
| skill_H034_atk_2.caf | 0.44 秒 | Baxter Audio - IMPACT・Conor Bradley - Metal Chains・Justsoundeffects - Melee Weapons | 斧鉤の打撃（肉と鉄）+ 低い芯 + 鎖の鳴り |
| skill_H034_atk_3.caf | 0.45 秒 | Baxter Audio - IMPACT・Conor Bradley - Metal Chains・Justsoundeffects - Melee Weapons | 斧鉤の打撃（肉と鉄）+ 低い芯 + 鎖の鳴り |
| skill_H034_atk_4.caf | 0.44 秒 | Baxter Audio - IMPACT・Conor Bradley - Metal Chains・Justsoundeffects - Melee Weapons | 斧鉤の打撃（肉と鉄）+ 低い芯 + 鎖の鳴り |
| skill_H034_atkhit_1.caf | 0.32 秒 | PMSFX - Lethal Blow・Shapeforms - Hit & Punch | 肉を打つ鈍い音 |
| skill_H034_atkhit_2.caf | 0.36 秒 | Rock The Speakerbox - Melee・Shapeforms - Hit & Punch | 肉を打つ鈍い音 |
| skill_H034_atkhit_3.caf | 0.20 秒 | Shapeforms - Hit & Punch | 肉を打つ鈍い音 |
| skill_H034_passive.caf | 1.14 秒 | 344 Audio - Low Frequency Elements・Sound Spark LLC – Magic Spells, Buffs and Attacks・Alexander Kopeikin - Emotion and Magic | 闘気（低音のふくらみ + 光のきらめき） |
| skill_H034_s1_cast.caf | 1.02 秒 | Baxter Audio - IMPACT・Rock The Speakerbox - Melee・344 Audio - Trailer Instruments Designed・Conor Bradley - Metal Chains・InspectorJ - Essentials 04 Chains・344 Audio - Elemental Palette Designed Vol. 1 | 鎖を回す → 投げ（風切り・鎖の放り出し）→ 飛ぶ鎖の連なり |
| skill_H034_s1_hit_1.caf | 0.88 秒 | 344 Audio - Low Frequency Elements・Conor Bradley - Metal Chains・PMSFX - Lethal Blow・SmartSoundFX - Impacts, Hits & Whooshes・344 Audio - Flesh, Bones & Gore・InspectorJ - Essentials 04 Chains・David Dumais Audio - Melee Weapons Sound Effects Pack 2 | 鉤が刺さる重い打撃 + 鉄 → 0.45 秒後に鎖を引く |
| skill_H034_s1_hit_2.caf | 0.94 秒 | 344 Audio - Low Frequency Elements・Conor Bradley - Metal Chains・PMSFX - Lethal Blow・SmartSoundFX - Impacts, Hits & Whooshes・344 Audio - Flesh, Bones & Gore・InspectorJ - Essentials 04 Chains・David Dumais Audio - Melee Weapons Sound Effects Pack 2 | 鉤が刺さる重い打撃 + 鉄 → 0.45 秒後に鎖を引く |
| skill_H034_s1_hit_3.caf | 0.88 秒 | 344 Audio - Low Frequency Elements・Conor Bradley - Metal Chains・PMSFX - Lethal Blow・SmartSoundFX - Impacts, Hits & Whooshes・344 Audio - Flesh, Bones & Gore・InspectorJ - Essentials 04 Chains・David Dumais Audio - Melee Weapons Sound Effects Pack 2 | 鉤が刺さる重い打撃 + 鉄 → 0.45 秒後に鎖を引く |
| skill_H034_s2_cast.caf | 0.90 秒 | 344 Audio - Low Frequency Elements・Articulated Sounds - Magic Elements vol.1・Baxter Audio - IMPACT・Red Libraries - Bodyfall・Sound Spark LLC – Magic Spells, Buffs and Attacks・SmartSoundFX - Impacts, Hits & Whooshes・David Dumais Audio - Melee Weapons Sound Effects Pack 1 | 短い振り上げ → 叩きつけ（体の芯・低音・土・鉄）→ 低音の尾 |
| skill_H034_s2_hit_1.caf | 0.26 秒 | Red Libraries - Bodyfall・Shapeforms - Hit & Punch | 衝撃が体に当たる鈍い音 + 土 |
| skill_H034_s2_hit_2.caf | 0.24 秒 | Red Libraries - Bodyfall・Shapeforms - Hit & Punch | 衝撃が体に当たる鈍い音 + 土 |
| skill_H034_s2_hit_3.caf | 0.23 秒 | Red Libraries - Bodyfall・Shapeforms - Hit & Punch | 衝撃が体に当たる鈍い音 + 土 |
| skill_H034_ult_cast.caf | 2.03 秒 | 344 Audio - Low Frequency Elements・Baxter Audio - IMPACT・Red Libraries - Bodyfall・Rock The Speakerbox - Melee・Conor Bradley - Metal Chains・David Dumais Audio - Weapon Sounds - Weapon Swings・PMSFX - Lethal Blow・344 Audio - Flesh, Bones & Gore・David Dumais Audio - Melee Weapons Sound Effects Pack 1・InspectorJ - Essentials 04 Chains・344 Audio - Cinematic Fight Vol. 1・David Dumais Audio - Melee Weapons Sound Effects Pack 2 | 掴みかかる一閃（鞭・鎖・掴み）→ 拘束の擦れと低いうなり |
| skill_H034_ult_hit_1.caf | 0.62 秒 | 344 Audio - Low Frequency Elements・Sound Spark LLC – Gore・Conor Bradley - Metal Chains・PMSFX - Lethal Blow・SmartSoundFX - Impacts, Hits & Whooshes・344 Audio - Flesh, Bones & Gore | 拳と斧鉤の重い打撃 + 砕け + 低音の芯 + 鎖の跳ね |
| skill_H034_ult_hit_2.caf | 0.58 秒 | 344 Audio - Low Frequency Elements・Sound Spark LLC – Gore・Conor Bradley - Metal Chains・PMSFX - Lethal Blow・SmartSoundFX - Impacts, Hits & Whooshes・344 Audio - Flesh, Bones & Gore | 拳と斧鉤の重い打撃 + 砕け + 低音の芯 + 鎖の跳ね |
| skill_H034_ult_hit_3.caf | 0.55 秒 | 344 Audio - Low Frequency Elements・Sound Spark LLC – Gore・Conor Bradley - Metal Chains・PMSFX - Lethal Blow・SmartSoundFX - Impacts, Hits & Whooshes・344 Audio - Flesh, Bones & Gore | 拳と斧鉤の重い打撃 + 砕け + 低音の芯 + 鎖の跳ね |
