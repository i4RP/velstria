# VELSIA 公開サイト（https://velsia.bitcessing.com）

静的サイト（Vercel、プロジェクト `velsia-site`）。トップ・サポート・プライバシー・利用規約・特商法表記・資金決済法表示（日英）。

- 生成: `cd site && npm install && node build.mjs` → `public/`。法務ページは `VELSTRIA/docs/legal/*.md` が正本で、`site/legal/` に同期してから `config.json` の値を `{{…}}` に差し込む（`onlineMatch: false` の間はオンライン対戦の節を除く）。
- 事業者情報・窓口メール・施行日は `config.json`。変えたら `VELSTRIA/App/Screens/Store/StoreLogic.swift`（`StoreLegalText`）と `FeatureFlags.swift`、`docs/appstore/metadata/*/…_url.txt` も合わせる。
- デプロイ: git の作者情報が付くと Vercel が「コミット作者に権限がない」として BLOCKED にするため、リポジトリ外へコピーして行う:
  `rsync -a --exclude node_modules --exclude public --exclude .env.local site/ /tmp/velsia-site-deploy/ && cd /tmp/velsia-site-deploy && vercel deploy --prod --yes`
- ドメインの DNS は Njalla（外部）。`A velsia.bitcessing.com 76.76.21.21` が必要。
