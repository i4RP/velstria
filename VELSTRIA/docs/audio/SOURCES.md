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
| skill_H025_s1_cast.caf | 0.70 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H025 s1 の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H025_s2_cast.caf | 1.69 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H025 s2 の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H025_s2_hit.caf | 0.54 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H025 s2 の命中 |
| skill_H025_ult_cast.caf | 1.85 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H025 ult の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H026_s1_cast.caf | 1.14 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H026 s1 の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H026_s1_hit.caf | 0.80 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H026 s1 の命中 |
| skill_H026_s2_cast.caf | 1.29 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H026 s2 の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H026_s2_hit.caf | 0.79 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H026 s2 の命中 |
| skill_H026_ult_cast.caf | 2.25 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H026 ult の発動（溜め・振り・着弾・余韻を演出の時刻に重ねた） |
| skill_H026_ult_hit.caf | 0.80 秒 | Digital Audio・Impact Sounds・Interface Sounds・RPG Audio・Sci-Fi Sounds | H026 ult の命中 |
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
| Blades（GDC 2015） | Soundopolis | Sonniss GDC | https://gdc.sonniss.com/ |
| Natures Fury_Thunder（GDC 2015） | Soundopolis | Sonniss GDC | https://gdc.sonniss.com/ |
| Gorification [HD]（GDC 2015） | Timothy McHugh | Sonniss GDC | https://gdc.sonniss.com/ |
| Black Metal（GDC 2016） | Alexander Kopeikin | Sonniss GDC | https://gdc.sonniss.com/ |
| The Gun Locker SFX Pack（GDC 2016） | Fascinated Sound | Sonniss GDC | https://gdc.sonniss.com/ |
| Ice SFX（GDC 2016） | Stuart Duffield | Sonniss GDC | https://gdc.sonniss.com/ |
| 12 Gauge Shotgun（GDC 2016） | TS Sound | Sonniss GDC | https://gdc.sonniss.com/ |
| Tanks and Jet（GDC 2017） | Double Trouble Audio | Sonniss GDC | https://gdc.sonniss.com/ |
|  Gun Sound Pack（GDC 2017） | Gamemaster Audio | Sonniss GDC | https://gdc.sonniss.com/ |
|  Punch Sound Pack（GDC 2017） | Gamemaster Audio | Sonniss GDC | https://gdc.sonniss.com/ |
| Glacier Ice（GDC 2017） | Mattia Cellotto | Sonniss GDC | https://gdc.sonniss.com/ |
| Elements - Ice（GDC 2017） | Mindful Audio | Sonniss GDC | https://gdc.sonniss.com/ |
| Hums Light Machines（GDC 2017） | RedSonic | Sonniss GDC | https://gdc.sonniss.com/ |
| Heavy Metal!（GDC 2017） | Soundopolis | Sonniss GDC | https://gdc.sonniss.com/ |
| The Dry Ice Library（GDC 2018） | Alexander Kopeikin | Sonniss GDC | https://gdc.sonniss.com/ |
| Ice Fury（GDC 2018） | FLYSOUND | Sonniss GDC | https://gdc.sonniss.com/ |
| High Voltage Electricity - The Essential Collection（GDC 2018） | Hear and Now Sound | Sonniss GDC | https://gdc.sonniss.com/ |
| Foley Elements Ice and Snow（GDC 2018） | Soundrangers | Sonniss GDC | https://gdc.sonniss.com/ |
| Hand-to-Hand Combat - Body Hits & Vocal Excursions（GDC 2018） | The Chris Alan | Sonniss GDC | https://gdc.sonniss.com/ |
| Electric Deluxe（GDC 2018） | Wakerone | Sonniss GDC | https://gdc.sonniss.com/ |
| Low Frequency Elements（GDC 2019） | 344 Audio | Sonniss GDC | https://gdc.sonniss.com/ |
| Battlefield Howitzers（GDC 2019） | Airborne Sound | Sonniss GDC | https://gdc.sonniss.com/ |
| Magic Elements vol.1（GDC 2019） | Articulated Sounds | Sonniss GDC | https://gdc.sonniss.com/ |
| IMPACT（GDC 2019） | Baxter Audio | Sonniss GDC | https://gdc.sonniss.com/ |
| Heavy Metal Impact Sound Effects（GDC 2019） | BlueZone | Sonniss GDC | https://gdc.sonniss.com/ |
| Effective Trailer Booms（GDC 2019） | Federico Soler Fernández | Sonniss GDC | https://gdc.sonniss.com/ |
| Effective Trailer Hits & Impacts（GDC 2019） | Federico Soler Fernández | Sonniss GDC | https://gdc.sonniss.com/ |
| Effective Trailer Whooshes（GDC 2019） | Federico Soler Fernández | Sonniss GDC | https://gdc.sonniss.com/ |
| Transition Movement Pack 002（GDC 2019） | L.A. Sounds | Sonniss GDC | https://gdc.sonniss.com/ |
| Bodyfall（GDC 2019） | Red Libraries | Sonniss GDC | https://gdc.sonniss.com/ |
| Melee（GDC 2019） | Rock The Speakerbox | Sonniss GDC | https://gdc.sonniss.com/ |
| Gore（GDC 2019） | Sound Spark LLC | Sonniss GDC | https://gdc.sonniss.com/ |
| Magic Spells, Buffs and Attacks（GDC 2019） | Sound Spark LLC | Sonniss GDC | https://gdc.sonniss.com/ |
| Metal Hits, Scrapes and Squeaks（GDC 2019） | Sound Spark LLC | Sonniss GDC | https://gdc.sonniss.com/ |
| Icy Snow 2 HD（GDC 2019） | Soundopolis | Sonniss GDC | https://gdc.sonniss.com/ |
| Medieval Battle（GDC 2020） | 344 Audio | Sonniss GDC | https://gdc.sonniss.com/ |
| Trailer Instruments Designed（GDC 2020） | 344 Audio | Sonniss GDC | https://gdc.sonniss.com/ |
| Metal Chains（GDC 2020） | Conor Bradley | Sonniss GDC | https://gdc.sonniss.com/ |
| Weapon Sounds - Weapon Swings（GDC 2020） | David Dumais Audio | Sonniss GDC | https://gdc.sonniss.com/ |
| Bullet Bys &Impacts（GDC 2020） | PMSFX | Sonniss GDC | https://gdc.sonniss.com/ |
| Lethal Blow（GDC 2020） | PMSFX | Sonniss GDC | https://gdc.sonniss.com/ |
| Hit & Punch（GDC 2020） | Shapeforms | Sonniss GDC | https://gdc.sonniss.com/ |
| Impacts, Hits & Whooshes（GDC 2020） | SmartSoundFX | Sonniss GDC | https://gdc.sonniss.com/ |
| Medieval（GDC 2020） | SmartSoundFX | Sonniss GDC | https://gdc.sonniss.com/ |
| Flesh, Bones & Gore（GDC 2023） | 344 Audio | Sonniss GDC | https://gdc.sonniss.com/ |
| Ice Cracking（GDC 2023） | BluezoneCorp | Sonniss GDC | https://gdc.sonniss.com/ |
| Melee Weapons Sound Effects Pack 1（GDC 2023） | David Dumais Audio | Sonniss GDC | https://gdc.sonniss.com/ |
| Potato Gun – Pipe-based Cannon（GDC 2023） | Dramatic Cat | Sonniss GDC | https://gdc.sonniss.com/ |
| Naval Warfare（GDC 2023） | Gladestock Studios | Sonniss GDC | https://gdc.sonniss.com/ |
| Essentials 04 Chains（GDC 2023） | InspectorJ | Sonniss GDC | https://gdc.sonniss.com/ |
| High Voltage（GDC 2024） | BluezoneCorp | Sonniss GDC | https://gdc.sonniss.com/ |
| Stone Impact（GDC 2024） | BluezoneCorp | Sonniss GDC | https://gdc.sonniss.com/ |
| Explosion SFX Pack（GDC 2024） | DavidDumais | Sonniss GDC | https://gdc.sonniss.com/ |
| Haunted Metal Vol.1 - Cinematic Hits & Impacts（GDC 2024） | Jake Fielding | Sonniss GDC | https://gdc.sonniss.com/ |
| Melee Weapons（GDC 2024） | Justsoundeffects | Sonniss GDC | https://gdc.sonniss.com/ |
| Sound Effects Collection（GDC 2024） | Mechanical Wave | Sonniss GDC | https://gdc.sonniss.com/ |
| The Metal Hit Sweeteners Library（GDC 2024） | Pole Position | Sonniss GDC | https://gdc.sonniss.com/ |
| Distinct Whooshes（GDC 2024） | Rescopic Sound | Sonniss GDC | https://gdc.sonniss.com/ |
| Cinematic Fight Vol. 1（GDC 2026） | 344 Audio | Sonniss GDC | https://gdc.sonniss.com/ |
| Elemental Palette Designed Vol. 1（GDC 2026） | 344 Audio | Sonniss GDC | https://gdc.sonniss.com/ |
| 100 kHz Designed Ice（GDC 2026） | Alexander Kopeikin | Sonniss GDC | https://gdc.sonniss.com/ |
| Emotion and Magic（GDC 2026） | Alexander Kopeikin | Sonniss GDC | https://gdc.sonniss.com/ |
| Melee Weapons Sound Effects Pack 2（GDC 2026） | David Dumais Audio | Sonniss GDC | https://gdc.sonniss.com/ |

### 出力（App/Resources/Audio、48 kHz）

| ファイル | 長さ | 素材 | 加工 |
|---|---|---|---|
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
| skill_H030_passive.caf | 0.30 秒 | Gamemaster Audio -  Gun Sound Pack・Hear and Now Sound - High Voltage Electricity - The Essential Collection・BluezoneCorp - High Voltage | 砲口の小さな火花 + 細かい放電 + 撃鉄の金属音 |
| skill_H030_s1_cast.caf | 0.70 秒 | Fascinated Sound - The Gun Locker SFX Pack・Double Trouble Audio - Tanks and Jet・Gamemaster Audio -  Gun Sound Pack・Hear and Now Sound - High Voltage Electricity - The Essential Collection・BluezoneCorp - High Voltage | 撃鉄と放電の溜め → 0.1 秒の発射（機関砲・放電の弾け・戦車砲の低音）→ 飛ぶ弾の放電 |
| skill_H030_s1_hit_1.caf | 0.46 秒 | Hear and Now Sound - High Voltage Electricity - The Essential Collection・The Chris Alan - Hand-to-Hand Combat - Body Hits & Vocal Excursions・PMSFX - Bullet Bys &Impacts・BluezoneCorp - High Voltage | 放電の弾け + 弾が体に当たる音 + 低い芯 + 火花 |
| skill_H030_s1_hit_2.caf | 0.57 秒 | Hear and Now Sound - High Voltage Electricity - The Essential Collection・The Chris Alan - Hand-to-Hand Combat - Body Hits & Vocal Excursions・PMSFX - Bullet Bys &Impacts・BluezoneCorp - High Voltage | 放電の弾け + 弾が体に当たる音 + 低い芯 + 火花 |
| skill_H030_s1_hit_3.caf | 0.44 秒 | Hear and Now Sound - High Voltage Electricity - The Essential Collection・The Chris Alan - Hand-to-Hand Combat - Body Hits & Vocal Excursions・PMSFX - Bullet Bys &Impacts・BluezoneCorp - High Voltage | 放電の弾け + 弾が体に当たる音 + 低い芯 + 火花 |
| skill_H030_s2_cast.caf | 0.66 秒 | TS Sound - 12 Gauge Shotgun・RedSonic - Hums Light Machines・Wakerone - Electric Deluxe・Airborne Sound - Battlefield Howitzers・Dramatic Cat - Potato Gun – Pipe-based Cannon | 装填 → 0.1 秒の発射（空気砲・榴弾砲の低音）→ 飛ぶ球の電気のうなり |
| skill_H030_s2_hit_1.caf | 0.57 秒 | Hear and Now Sound - High Voltage Electricity - The Essential Collection・Airborne Sound - Battlefield Howitzers・Gladestock Studios - Naval Warfare・BluezoneCorp - High Voltage・DavidDumais - Explosion SFX Pack | 放電の大きな弾け + 爆発 + 砲弾の着弾 + 放電の尾 + 低音 |
| skill_H030_s2_hit_2.caf | 0.60 秒 | Hear and Now Sound - High Voltage Electricity - The Essential Collection・Airborne Sound - Battlefield Howitzers・Gladestock Studios - Naval Warfare・BluezoneCorp - High Voltage・DavidDumais - Explosion SFX Pack | 放電の大きな弾け + 爆発 + 砲弾の着弾 + 放電の尾 + 低音 |
| skill_H030_s2_hit_3.caf | 0.54 秒 | Hear and Now Sound - High Voltage Electricity - The Essential Collection・Airborne Sound - Battlefield Howitzers・Gladestock Studios - Naval Warfare・BluezoneCorp - High Voltage・DavidDumais - Explosion SFX Pack | 放電の大きな弾け + 爆発 + 砲弾の着弾 + 放電の尾 + 低音 |
| skill_H030_ult_cast.caf | 1.80 秒 | TS Sound - 12 Gauge Shotgun・Double Trouble Audio - Tanks and Jet・Hear and Now Sound - High Voltage Electricity - The Essential Collection・Wakerone - Electric Deluxe・Airborne Sound - Battlefield Howitzers・BluezoneCorp - High Voltage | 砲身を引く → 変圧器のうなりと放電の溜め → 0.55 秒の発射（戦車砲・放電・榴弾砲）→ ビームの放電 → 砲の尾 |
| skill_H030_ult_hit_1.caf | 0.51 秒 | Hear and Now Sound - High Voltage Electricity - The Essential Collection・PMSFX - Bullet Bys &Impacts・Gladestock Studios - Naval Warfare・BluezoneCorp - High Voltage | 放電の弾け + 体の打撃 + 着弾の低音 + 放電の尾 |
| skill_H030_ult_hit_2.caf | 0.49 秒 | Hear and Now Sound - High Voltage Electricity - The Essential Collection・PMSFX - Bullet Bys &Impacts・Gladestock Studios - Naval Warfare・BluezoneCorp - High Voltage | 放電の弾け + 体の打撃 + 着弾の低音 + 放電の尾 |
| skill_H030_ult_hit_3.caf | 0.46 秒 | Hear and Now Sound - High Voltage Electricity - The Essential Collection・PMSFX - Bullet Bys &Impacts・Gladestock Studios - Naval Warfare・BluezoneCorp - High Voltage | 放電の弾け + 体の打撃 + 着弾の低音 + 放電の尾 |
| skill_H031_passive.caf | 0.89 秒 | Mindful Audio - Elements - Ice・Alexander Kopeikin - The Dry Ice Library・Soundrangers - Foley Elements Ice and Snow | 凍りつくひび + 霜 + 氷のきしみ |
| skill_H031_s1_cast.caf | 1.89 秒 | Stuart Duffield - Ice SFX・Mattia Cellotto - Glacier Ice・Mindful Audio - Elements - Ice・Alexander Kopeikin - The Dry Ice Library・FLYSOUND – Ice Fury・Articulated Sounds - Magic Elements vol.1・BluezoneCorp - Ice Cracking・Mechanical Wave - Sound Effects Collection | 霜が集まる → 落ちる氷塊の風 → 0.56 秒の着弾（氷塊・砕け・ひび・低音）→ 雹 5 つの砕け → 霜の床 |
| skill_H031_s1_hit_1.caf | 0.48 秒 | Stuart Duffield - Ice SFX・Gamemaster Audio -  Punch Sound Pack・Soundrangers - Foley Elements Ice and Snow | 氷の塊が体に当たって砕ける + 体の芯 + 凍りつくひび |
| skill_H031_s1_hit_2.caf | 0.51 秒 | Gamemaster Audio -  Punch Sound Pack・Soundrangers - Foley Elements Ice and Snow・Soundopolis - Icy Snow 2 HD | 氷の塊が体に当たって砕ける + 体の芯 + 凍りつくひび |
| skill_H031_s1_hit_3.caf | 0.47 秒 | Gamemaster Audio -  Punch Sound Pack・FLYSOUND – Ice Fury・Soundrangers - Foley Elements Ice and Snow | 氷の塊が体に当たって砕ける + 体の芯 + 凍りつくひび |
| skill_H031_s2_cast.caf | 1.42 秒 | Mindful Audio - Elements - Ice・Alexander Kopeikin - The Dry Ice Library・Soundrangers - Foley Elements Ice and Snow・Articulated Sounds - Magic Elements vol.1・BluezoneCorp - Ice Cracking・Mechanical Wave - Sound Effects Collection・Rescopic Sound - Distinct Whooshes・Alexander Kopeikin - 100 kHz Designed Ice | 払う霜 → 冷たい突風 → 0.56 秒に凍りつくひび → 0.76 秒に地面が凍る割れ |
| skill_H031_s2_hit_1.caf | 0.42 秒 | Stuart Duffield - Ice SFX・Gamemaster Audio -  Punch Sound Pack・Soundrangers - Foley Elements Ice and Snow | 体が凍りつく（凍るひび・氷の砕け・体の芯） |
| skill_H031_s2_hit_2.caf | 0.45 秒 | Stuart Duffield - Ice SFX・Gamemaster Audio -  Punch Sound Pack・Soundrangers - Foley Elements Ice and Snow | 体が凍りつく（凍るひび・氷の砕け・体の芯） |
| skill_H031_s2_hit_3.caf | 0.46 秒 | Stuart Duffield - Ice SFX・Gamemaster Audio -  Punch Sound Pack・Soundrangers - Foley Elements Ice and Snow | 体が凍りつく（凍るひび・氷の砕け・体の芯） |
| skill_H031_ult_cast.caf | 2.53 秒 | Stuart Duffield - Ice SFX・Mattia Cellotto - Glacier Ice・Mindful Audio - Elements - Ice・Alexander Kopeikin - The Dry Ice Library・FLYSOUND – Ice Fury・Soundrangers - Foley Elements Ice and Snow・BluezoneCorp - Ice Cracking・Mechanical Wave - Sound Effects Collection・Alexander Kopeikin - 100 kHz Designed Ice | 霜が集まる → 0.26 秒の霜の道のひび → 氷河が育つきしみ → 1.49 秒に氷河が砕ける（氷山・氷塊・砕け） |
| skill_H031_ult_hit_1.caf | 0.57 秒 | Gamemaster Audio -  Punch Sound Pack・Mattia Cellotto - Glacier Ice・Soundrangers - Foley Elements Ice and Snow・Soundopolis - Icy Snow 2 HD | 大きな氷の塊が体を打つ + 氷の割れ + 体の芯 |
| skill_H031_ult_hit_2.caf | 0.57 秒 | Gamemaster Audio -  Punch Sound Pack・Mattia Cellotto - Glacier Ice・FLYSOUND – Ice Fury・Soundrangers - Foley Elements Ice and Snow | 大きな氷の塊が体を打つ + 氷の割れ + 体の芯 |
| skill_H031_ult_hit_3.caf | 0.57 秒 | Stuart Duffield - Ice SFX・Gamemaster Audio -  Punch Sound Pack・Mattia Cellotto - Glacier Ice・Soundrangers - Foley Elements Ice and Snow | 大きな氷の塊が体を打つ + 氷の割れ + 体の芯 |
| skill_H032_passive.caf | 0.68 秒 | Soundopolis - Blades・Alexander Kopeikin - Black Metal・L.A. Sounds - Transition Movement Pack 002 | 両手の刃が鳴る + 鉄板の低いうなり |
| skill_H032_s1_cast.caf | 1.20 秒 | Soundopolis - Blades・Soundopolis - Natures Fury_Thunder・Alexander Kopeikin - Black Metal・Soundopolis - Heavy Metal!・David Dumais Audio - Weapon Sounds - Weapon Swings・David Dumais Audio - Melee Weapons Sound Effects Pack 2 | 刃の振り ×3（0.26・0.46・0.66 秒の輪）+ 刃の鳴り + 鉄の打撃 + 鉄板のうなり・地鳴り |
| skill_H032_s1_hit_1.caf | 0.43 秒 | Alexander Kopeikin - Black Metal・344 Audio - Flesh, Bones & Gore・David Dumais Audio - Melee Weapons Sound Effects Pack 1・Justsoundeffects - Melee Weapons | 刃が肉と鎧を斬る + 体の砕け + 鉄板の低い芯 |
| skill_H032_s1_hit_2.caf | 0.47 秒 | Alexander Kopeikin - Black Metal・Sound Spark LLC – Gore・344 Audio - Flesh, Bones & Gore・Justsoundeffects - Melee Weapons | 刃が肉と鎧を斬る + 体の砕け + 鉄板の低い芯 |
| skill_H032_s1_hit_3.caf | 0.42 秒 | Timothy McHugh - Gorification [HD]・Alexander Kopeikin - Black Metal・344 Audio - Flesh, Bones & Gore・Justsoundeffects - Melee Weapons | 刃が肉と鎧を斬る + 体の砕け + 鉄板の低い芯 |
| skill_H032_s2_cast.caf | 0.76 秒 | Soundopolis - Natures Fury_Thunder・Alexander Kopeikin - Black Metal・L.A. Sounds - Transition Movement Pack 002・David Dumais Audio - Weapon Sounds - Weapon Swings・SmartSoundFX – Medieval | 踏み込む重い振り + 鎧と鎖 → 突進の風 + 刃の擦れ → 鉄板のうねり |
| skill_H032_s2_hit_1.caf | 0.35 秒 | Timothy McHugh - Gorification [HD]・Alexander Kopeikin - Black Metal・Soundopolis - Heavy Metal!・Justsoundeffects - Melee Weapons | 刃と鎧のぶつかり（斧と鎖・盾の金属）+ 肉を斬る + 低い芯 |
| skill_H032_s2_hit_2.caf | 0.37 秒 | Timothy McHugh - Gorification [HD]・Alexander Kopeikin - Black Metal・Soundopolis - Heavy Metal!・Justsoundeffects - Melee Weapons | 刃と鎧のぶつかり（斧と鎖・盾の金属）+ 肉を斬る + 低い芯 |
| skill_H032_s2_hit_3.caf | 0.35 秒 | Timothy McHugh - Gorification [HD]・Alexander Kopeikin - Black Metal・Soundopolis - Heavy Metal!・Justsoundeffects - Melee Weapons | 刃と鎧のぶつかり（斧と鎖・盾の金属）+ 肉を斬る + 低い芯 |
| skill_H032_s2_r1_cast.caf | 0.88 秒 | Alexander Kopeikin - Black Metal・Soundopolis - Heavy Metal!・L.A. Sounds - Transition Movement Pack 002・David Dumais Audio - Weapon Sounds - Weapon Swings・David Dumais Audio - Melee Weapons Sound Effects Pack 1・David Dumais Audio - Melee Weapons Sound Effects Pack 2 | 跳ぶ風 → 回る刃の擦れ ×3 → 三日月の払い → 鉄板の低音 |
| skill_H032_ult_cast.caf | 1.63 秒 | Soundopolis - Natures Fury_Thunder・Timothy McHugh - Gorification [HD]・Alexander Kopeikin - Black Metal・Soundopolis - Heavy Metal!・344 Audio - Medieval Battle・David Dumais Audio - Weapon Sounds - Weapon Swings・David Dumais Audio - Melee Weapons Sound Effects Pack 2 | 鎌の振り ×4 と闇のうねりの溜め → 槍が伸びる刃の擦れ → 0.76 秒に放つ（刃の振り抜き・斧と鎖の打撃・地鳴り） |
| skill_H032_ult_hit_1.caf | 0.48 秒 | Timothy McHugh - Gorification [HD]・Alexander Kopeikin - Black Metal・Soundopolis - Heavy Metal!・344 Audio - Flesh, Bones & Gore | 刃の槍が体を貫く + 斧と鎖の打撃 + 体の砕け + 鉄板の低音 |
| skill_H032_ult_hit_2.caf | 0.47 秒 | Timothy McHugh - Gorification [HD]・Alexander Kopeikin - Black Metal・Soundopolis - Heavy Metal!・344 Audio - Flesh, Bones & Gore | 刃の槍が体を貫く + 斧と鎖の打撃 + 体の砕け + 鉄板の低音 |
| skill_H032_ult_hit_3.caf | 0.48 秒 | Timothy McHugh - Gorification [HD]・Alexander Kopeikin - Black Metal・Soundopolis - Heavy Metal!・344 Audio - Flesh, Bones & Gore | 刃の槍が体を貫く + 斧と鎖の打撃 + 体の砕け + 鉄板の低音 |
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
