# VELSIA 公開サイト（https://velsia.bitcessing.com）

静的サイト（Vercel、プロジェクト `velsia-site`）。トップ・サポート・プレスキットと、規約・ポリシーの一覧（/legal）および各法務ページ（日英）。

- 生成: `cd site && npm install && node build.mjs` → `public/`。法務ページは `VELSTRIA/docs/legal/*.md` が正本で、`site/legal/` に同期してから `config.json` の値を `{{…}}` に差し込む。
  末尾の `---` + `## 運用メモ` 以降は公開しない。`[[include:licenses/…]]` の行はライセンスの原文（`docs/legal/licenses/`）に置き換わる。
- 法務ページの一覧は `build.mjs` の `LEGAL_DOCS`（ハブ /legal、フッター、サイトマップもここから作る）。

  | ページ | 日本語 | 英語 |
  |---|---|---|
  | 利用規約 | /terms | /en/terms |
  | コミュニティガイドライン | /community | /en/community |
  | 通報とブロック | /safety | /en/safety |
  | プライバシーポリシー | /privacy | /en/privacy |
  | データの削除とプライバシーの選択 | /privacy-choices | /en/privacy-choices |
  | 外部送信について | /external-transmission | /en/external-transmission（参考訳） |
  | 特定商取引法に基づく表記 | /tokushoho | /en/tokushoho（参考訳） |
  | 資金決済法に基づく表示 | /payment-services | /en/payment-services（参考訳） |
  | ライセンス表記 | /licenses | /en/licenses |
  | 保護者の方へ | /parents | /en/parents |

  既存の URL（/privacy・/terms・/tokushoho・/payment-services・/support・/press と /en/…）はアプリと App Store Connect に登録済みなので変えない。
  アプリ（`FeatureFlags`）は /privacy・/terms・/community・/safety・/privacy-choices・/external-transmission・/legal・/licenses（と /en/…）を開く。
- 法務文書はオンライン機能ありのアプリ（`FeatureFlags.lanMatch == true`）に合わせて書いてある。`config.json` の `onlineMatch` は `true` のままにする。
  リポジトリ内でビルドすると、`FeatureFlags.lanMatch` と `onlineMatch` が食い違っていればエラーにする（`<!-- online:begin/end -->` の除去の仕組みは残してあるが、
  オフライン版の文書は保守していない。オンラインを外して出すなら文書を見直すこと）。
- App Store Connect に登録する URL（/legal の表）は `build.mjs` の `ASC_URLS`。リポジトリ内のビルドでは `docs/appstore/metadata/<locale>/*_url.txt` と照合する。
- 事業者情報・窓口メール・施行日・改定日は `config.json`。変えたら `VELSTRIA/App/Screens/Store/StoreLogic.swift`（`StoreLegalText`）と `FeatureFlags.swift`、`docs/appstore/metadata/*/…_url.txt` も合わせる。
- 全角の括弧に続く URL は GFM の自動リンクに巻き込まれて壊れるので、法務文書の URL は `<https://…>` で囲む（ビルドが壊れたリンクを検出して止める）。
- ビルドの最後に、出力した全ページの内部リンク（`/…` と `https://velsia.bitcessing.com/…`）・画像・og:image・アンカー（`#…`）が実在するか、
  リポジトリ内のビルドでは `FeatureFlags.swift` に書いたこのサイトの URL が実在するページか確かめ、無ければエラーにする。
- プレスキットのヒーローは `ACTIVE_HERO_IDS`（`HeroRoster.activeHeroIDs` と照合する）。出していないヒーローとそのスキンは載せない。
- プレスキット（`/press`・`/en/press`）: 素材は `assets/press/`（一覧用の縮小版は `thumbs/`、スクショは `assets/shots/`）。一式の ZIP はビルド時に `public/assets/press/velsia-presskit.zip` として作る（コミットしない）。素材を差し替えるときはファイル名も変える（`/assets/` は immutable キャッシュ）。
- デプロイ: git の作者情報が付くと Vercel が「コミット作者に権限がない」として BLOCKED にするため、リポジトリ外へコピーして行う:
  `rsync -a --exclude node_modules --exclude public --exclude .env.local site/ /tmp/velsia-site-deploy/ && cd /tmp/velsia-site-deploy && vercel deploy --prod --yes`
- ドメインの DNS は Njalla（外部）。`A velsia.bitcessing.com 76.76.21.21` が必要。
