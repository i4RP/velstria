# ライセンス表記

<!-- 公開用。[[include:…]] は build.mjs が docs/legal/ 以下のファイルの本文（原文のまま）に置き換える。ライブラリ・フォントを追加・更新したら、
     licenses/ の本文とこのページ、アプリ内のクレジット画面（CreditsView）を同時に更新すること。末尾の「運用メモ」は公開しない。 -->

iPhone 向けゲームアプリ「VELSIA - 星環の戦場」（以下「本アプリ」といいます）は、以下の第三者のソフトウェアとフォントを使用しています。各ライセンスの本文は原文（英語）のまま掲載します。

## 使用しているソフトウェア・フォント

| 名称 | 用途 | 著作権表示 | ライセンス |
|---|---|---|---|
| Effekseer | エフェクトの再生 | Copyright (c) 2011 Effekseer Project | MIT License |
| LLGI（Effekseer に含まれるグラフィックスライブラリ） | エフェクトの描画 | Copyright (c) 2019 Altseed | zlib License |
| stb_image（Effekseer に含まれる画像読み込みライブラリ） | エフェクト用の画像の読み込み | Copyright (c) 2017 Sean Barrett | MIT License（パブリックドメインとの選択制。本アプリは MIT License により使用しています） |
| Chakra Petch | 画面の文字（フォント） | Copyright 2018 The Chakra Petch Project Authors | SIL Open Font License 1.1 |
| Cinzel | 画面の文字（フォント） | Copyright 2020 The Cinzel Project Authors / Copyright © 2012 Natanael Gama（予約フォント名「Cinzel Decorative」） | SIL Open Font License 1.1 |

本アプリの効果音と BGM は、本アプリのプログラムで合成しています。外部の音源素材は使用していません。

## ライセンス本文

### Effekseer（MIT License）

[[include:licenses/effekseer.txt]]

### LLGI（zlib License）

[[include:licenses/llgi.txt]]

### stb_image（MIT License / Public Domain）

[[include:licenses/stb-image.txt]]

### Chakra Petch（SIL Open Font License 1.1）

[[include:licenses/ofl-chakra-petch.txt]]

### Cinzel（SIL Open Font License 1.1）

[[include:licenses/ofl-cinzel.txt]]

最終更新日: {{UPDATED_DATE}}

---

## 運用メモ（社内向け・公開しない）

- 出典: Effekseer は ThirdParty/Effekseer/LICENSE.txt。LLGI と stb_image は ThirdParty に本文が無いため、tools/build_effekseer.sh の入力
  （~/Library/Application Support/Effekseer/current/runtime-cpp、1.80.7）の src/3rdParty/LLGI/LICENSE と src/3rdParty/stb_effekseer/stb_image_effekseer.h（stb_image v2.25 を Effekseer が改変）から写した。
  libEffekseerAll.a に LLGI.*.o と stbi_* のシンボルがあることを確認済み。glslang はリンクされていない（シンボルなし）。
- MIT・zlib・OFL は、アプリ（配布物）にも著作権表示とライセンス本文を含める必要がある（MIT は必須、zlib は表示の改変禁止）。アプリのクレジット画面
  （CreditsView の CreditsCatalog.openSource）に Effekseer・stb_image（MIT）・LLGI（zlib）の本文を載せ、このページへのリンクを置いた。
  本文は licenses/ のファイルと一致させる（AppTests の OnlineSafetyTests で照合する）。フォントは App/Resources/Fonts に OFL の本文を同梱している。
- 生成 AI で作った素材（ヒーロー・構造物の 3D は Tripo、ステージの小物は Meshy、ポートレート等の 2D は Codex CLI の画像生成）は載せていない。各サービスの生成時の
  プランと利用規約の版（無料プランの出力に CC BY 等の表示義務があるか）を確認し、表示が必要ならこのページに追記する。
- サーバー（relay/）とサイト（site/）の依存（wrangler・typescript・@cloudflare/workers-types・marked）は配布物に含まれないので載せていない。
