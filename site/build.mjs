// VELSIA 公開サイトの生成（依存は marked だけ）。実行: node build.mjs → public/
// 法務ページは VELSTRIA/docs/legal/*.md を正本として、config.json の値を {{…}} に差し込んで作る。
// URL は docs/appstore/metadata と App/Core/FeatureFlags.swift に書いたものと一致させること。
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { marked } from "marked";

const ROOT = path.dirname(fileURLToPath(import.meta.url));
// 正本は VELSTRIA/docs/legal。リポジトリ内で実行するときは site/legal へ同期してから読む
// （Vercel へは site/ しか送られないので、同期済みのコピーをコミットしておく）。
const LEGAL_SRC = path.join(ROOT, "..", "VELSTRIA", "docs", "legal");
const LEGAL = path.join(ROOT, "legal");
if (fs.existsSync(LEGAL_SRC)) fs.cpSync(LEGAL_SRC, LEGAL, { recursive: true });
const OUT = path.join(ROOT, "public");
const cfg = JSON.parse(fs.readFileSync(path.join(ROOT, "config.json"), "utf8"));

fs.rmSync(OUT, { recursive: true, force: true });
fs.cpSync(path.join(ROOT, "assets"), path.join(OUT, "assets"), { recursive: true });

const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

// ---- Markdown（法務文書） ----
function legalHTML(file, lang) {
  let md = fs.readFileSync(path.join(LEGAL, file), "utf8");
  md = md.split(/\n---\n\n## 運用メモ/)[0]; // 社内向けメモは公開しない
  md = cfg.onlineMatch
    ? md.replace(/<!-- online:(begin|end) -->/g, "")
    : md.replace(/<!-- online:begin -->[\s\S]*?<!-- online:end -->/g, "");
  md = md.replace(/<!--[\s\S]*?-->/g, ""); // テンプレートの注意書き
  md = md.replace(/{{([A-Z_]+)}}/g, (m, k) => {
    if (!(k in cfg[lang])) throw new Error(`${file}: 未定義のプレースホルダ ${m}`);
    return cfg[lang][k];
  });
  if (/{{|}}/.test(md)) throw new Error(`${file}: 差し込み後にプレースホルダが残っています`);
  return marked.parse(md, { gfm: true });
}

// ---- レイアウト ----
const T = {
  ja: {
    lang: "ja", home: "/", name: "VELSIA - 星環の戦場", nav: [["/", "ホーム"], ["/support", "サポート"], ["/privacy", "プライバシー"], ["/terms", "利用規約"], ["/tokushoho", "特商法表記"], ["/payment-services", "資金決済法表示"]],
    other: "English", otherHref: (p) => (p === "/" ? "/en" : "/en" + p), footer: "© 2026 BitcoinPay株式会社",
  },
  en: {
    lang: "en", home: "/en", name: "VELSIA: Star Ring Arena", nav: [["/en", "Home"], ["/en/support", "Support"], ["/en/privacy", "Privacy Policy"], ["/en/terms", "Terms of Service"], ["/tokushoho", "Commercial Transactions Act (JA)"]],
    other: "日本語", otherHref: (p) => p.replace(/^\/en/, "") || "/", footer: "© 2026 BITCOINPAY K.K.",
  },
};

const CSS = `
:root{color-scheme:dark;--bg:#0b1020;--panel:#141b33;--line:#26305a;--text:#e9edff;--sub:#a3acd1;--gold:#f6c453;--cyan:#5fd4ff}
*{box-sizing:border-box}html{scroll-behavior:smooth}
body{margin:0;background:radial-gradient(1200px 600px at 70% -10%,#1c2a63 0%,transparent 60%),var(--bg);color:var(--text);font:16px/1.75 -apple-system,BlinkMacSystemFont,"Hiragino Sans","Noto Sans JP","Segoe UI",sans-serif}
a{color:var(--cyan)}a:hover{color:#fff}
header{position:sticky;top:0;z-index:5;background:rgba(11,16,32,.85);backdrop-filter:blur(10px);border-bottom:1px solid var(--line)}
.bar{max-width:1040px;margin:0 auto;padding:10px 20px;display:flex;align-items:center;gap:18px;flex-wrap:wrap}
.brand{display:flex;align-items:center;gap:10px;color:var(--text);text-decoration:none;font-weight:800;letter-spacing:.06em}
.brand img{width:34px;height:34px;border-radius:8px}
nav{display:flex;gap:4px 16px;flex-wrap:wrap;margin-left:auto;font-size:14px}
nav a{color:var(--sub);text-decoration:none}nav a:hover,nav a[aria-current]{color:var(--gold)}
main{max-width:1040px;margin:0 auto;padding:36px 20px 64px}
.hero{display:grid;grid-template-columns:1.05fr 1fr;gap:32px;align-items:center;padding:12px 0 36px}
.hero img.logo{width:min(420px,100%);height:auto}
.hero h1{font-size:30px;line-height:1.35;margin:.6em 0 .4em}
.lead{color:var(--sub);font-size:17px}
.badge{display:inline-block;border:1px solid var(--gold);color:var(--gold);padding:6px 16px;border-radius:999px;font-weight:700;margin-top:10px}
.shot{width:100%;height:auto;border-radius:14px;border:1px solid var(--line);box-shadow:0 18px 50px rgba(0,0,0,.45)}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:16px;margin:12px 0 28px}
.card{background:var(--panel);border:1px solid var(--line);border-radius:14px;padding:18px 20px}
.card h3{margin:0 0 6px;color:var(--gold);font-size:17px}.card p{margin:0;color:var(--sub);font-size:15px}
h2{font-size:22px;margin:40px 0 12px;padding-left:12px;border-left:4px solid var(--gold)}
.shots{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:14px}
.doc h1{font-size:28px}.doc h2{font-size:20px}.doc h3{font-size:17px;color:var(--gold)}
.doc table{border-collapse:collapse;width:100%;margin:16px 0;font-size:15px;display:block;overflow-x:auto}
.doc th,.doc td{border:1px solid var(--line);padding:9px 12px;vertical-align:top;text-align:left}
.doc th{background:var(--panel);white-space:nowrap}
.doc code{background:var(--panel);padding:1px 6px;border-radius:5px}
details{background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:12px 16px;margin:10px 0}
summary{cursor:pointer;font-weight:700}details p{color:var(--sub);margin:.6em 0 0}
footer{border-top:1px solid var(--line);color:var(--sub);font-size:14px}
footer .bar{justify-content:space-between}
@media(max-width:760px){.hero{grid-template-columns:1fr}.hero h1{font-size:25px}}
`;

function page({ lang, path: p, title, desc, body, cls = "" }) {
  const t = T[lang];
  const url = cfg.baseURL + (p === "/" ? "" : p);
  const alt = t.otherHref(p);
  const nav = t.nav.map(([h, l]) => `<a href="${h}"${h === p ? ' aria-current="page"' : ""}>${esc(l)}</a>`).join("") + `<a href="${alt}" hreflang="${lang === "ja" ? "en" : "ja"}">${t.other}</a>`;
  const html = `<!doctype html>
<html lang="${t.lang}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(title)}</title><meta name="description" content="${esc(desc)}">
<link rel="canonical" href="${url}"><link rel="alternate" hreflang="${lang === "ja" ? "en" : "ja"}" href="${cfg.baseURL + (alt === "/" ? "" : alt)}">
<link rel="icon" href="/assets/favicon.png"><link rel="apple-touch-icon" href="/assets/apple-touch-icon.png">
<meta property="og:title" content="${esc(title)}"><meta property="og:description" content="${esc(desc)}"><meta property="og:type" content="website">
<meta property="og:url" content="${url}"><meta property="og:image" content="${cfg.baseURL}/assets/shots/${lang}/01_battle_teamfight.jpg">
<style>${CSS}</style></head><body>
<header><div class="bar"><a class="brand" href="${t.home}"><img src="/assets/icon.jpg" alt="" width="34" height="34">VELSIA</a><nav>${nav}</nav></div></header>
<main class="${cls}">${body}</main>
<footer><div class="bar"><span>${t.footer}</span><span>${cfg[lang].SUPPORT_EMAIL}</span></div></footer>
</body></html>`;
  const file = path.join(OUT, p === "/" ? "index.html" : p + ".html");
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, html);
}

// ---- トップ ----
const SHOTS = ["01_battle_teamfight", "02_home", "03_heroes", "05_hero_detail", "08_skin_store", "10_spectate"];
const shots = (lang, alts) => `<div class="shots">${SHOTS.map((s, i) => `<img class="shot" loading="lazy" src="/assets/shots/${lang}/${s}.jpg" alt="${esc(alts[i])}">`).join("")}</div>`;

const HOME = {
  ja: {
    title: "VELSIA - 星環の戦場 | iPhone で遊ぶ 5対5 MOBA",
    desc: "星環が砕けた世界で、24人のヒーローから選んで挑む5対5のMOBA。AIの味方と3つのレーンを押し上げ、敵のスターコアを破壊しよう。通信不要、課金は見た目が中心。",
    body: `<section class="hero"><div><img class="logo" src="/assets/logo.png" alt="VELSIA 星環の戦場" width="420"><h1>スマホで本格 5対5 MOBA。<br>1試合 10〜18分、通信不要。</h1>
<p class="lead">星環が砕けた世界で、24人のヒーローから選んで戦う。AIの味方と3つのレーンを押し上げ、敵のスターコアを破壊しましょう。</p>
<span class="badge">iPhone 向け（iOS 18 以降）・基本プレイ無料・App Store 公開準備中</span></div>
<img class="shot" src="/assets/shots/ja/01_battle_teamfight.jpg" alt="戦闘画面" width="800"></section>
<div class="grid">
<div class="card"><h3>24人のヒーロー、6つのロール</h3><p>ヴァンガード、デュエリスト、レンジャー、アルカニスト、サポート、アサシン。パッシブ、3つのスキル、アルティメットで戦い方が変わります。</p></div>
<div class="card"><h3>3レーンとジャングル</h3><p>3段のタワー、番人、河川ボス。視界と草むらを使った奇襲や、ボス争奪の集団戦が勝敗を分けます。</p></div>
<div class="card"><h3>72装備・10スペル・30ルーン</h3><p>試合中いつでも購入、素材から上位装備へ合成。ヒーローごとに自分だけのビルドを組めます。</p></div>
<div class="card"><h3>考えて動くAI</h3><p>味方も敵もレーン戦、ジャングル、撤退、ボス争奪、集団戦を状況で判断。難易度は3段階です。</p></div>
<div class="card"><h3>はじめてでも安心</h3><p>チュートリアルと練習場つき。攻撃の自動ターゲットや、おすすめ装備のワンタップ購入が使えます。</p></div>
<div class="card"><h3>見た目中心の課金</h3><p>有料はスキンなどの見た目アイテムとスターパス プレミアム。ヒーローはプレイで貯まるコインで解放でき、ランダム型の有料アイテムはありません。</p></div>
</div>
<h2>スクリーンショット</h2>${shots("ja", ["戦闘（集団戦）", "ホーム画面", "ヒーロー一覧", "ヒーロー詳細（スキル）", "スキンストア", "観戦"])}
<h2>モード</h2><div class="grid"><div class="card"><h3>クラシック（通常戦）／ランク戦</h3><p>あなたとAIの味方4人 対 AIの敵5人。ランク戦はBAN付きドラフトで、隕鉄から星環王まで7段階。</p></div><div class="card"><h3>乱闘・ライジング・カスタム・オートバトラー</h3><p>単レーンの短期決戦、勝ち上がり、陣営や強さを選ぶ対戦、8人のオートバトル。</p></div><div class="card"><h3>観戦・リプレイ</h3><p>AI同士の対戦を観戦。自分の試合は自動保存され、巻き戻しや倍速で見返せます。</p></div></div>
<h2>お問い合わせ・規約</h2><p>ご質問・不具合報告は <a href="/support">サポート</a> へ。<a href="/privacy">プライバシーポリシー</a>・<a href="/terms">利用規約</a>・<a href="/tokushoho">特定商取引法に基づく表記</a>・<a href="/payment-services">資金決済法に基づく表示</a>をご確認ください。</p>`,
  },
  en: {
    title: "VELSIA: Star Ring Arena | 5v5 MOBA for iPhone",
    desc: "A 5v5 MOBA for iPhone. Pick from 24 heroes, push three lanes with AI allies and destroy the enemy Star Core. Plays offline; purchases are mostly cosmetic.",
    body: `<section class="hero"><div><img class="logo" src="/assets/logo.png" alt="VELSIA Star Ring Arena" width="420"><h1>A real 5v5 MOBA on your phone.<br>10–18 minute matches, no connection needed.</h1>
<p class="lead">In a world where the Star Ring has shattered, choose from 24 heroes, team up with AI allies, push three lanes and destroy the enemy Star Core.</p>
<span class="badge">For iPhone (iOS 18+) · Free to play · Coming to the App Store</span></div>
<img class="shot" src="/assets/shots/en/01_battle_teamfight.jpg" alt="Battle" width="800"></section>
<div class="grid">
<div class="card"><h3>24 heroes, 6 roles</h3><p>Vanguard, Duelist, Ranger, Arcanist, Support and Assassin. Every hero has a Passive, three Skills and an Ultimate.</p></div>
<div class="card"><h3>Three lanes and a jungle</h3><p>Three tiers of towers, jungle sentinels and river bosses. Ambush from the brush and fight for bosses to swing the match.</p></div>
<div class="card"><h3>72 items, 10 spells, 30 runes</h3><p>Buy any time during a match and combine components into stronger items. Build your own loadout for every hero.</p></div>
<div class="card"><h3>AI that reads the game</h3><p>Allies and enemies lane, jungle, retreat, contest bosses and group for teamfights. Choose from three difficulty levels.</p></div>
<div class="card"><h3>Newcomer friendly</h3><p>A Tutorial and Practice mode, auto-targeting attacks and one-tap recommended items.</p></div>
<div class="card"><h3>Cosmetic-focused purchases</h3><p>Paid items are skins and other cosmetics plus Star Pass Premium. Heroes unlock with Coins earned by playing, and nothing paid is randomized.</p></div>
</div>
<h2>Screenshots</h2>${shots("en", ["Teamfight", "Home screen", "Hero roster", "Hero details (skills)", "Skin store", "Spectate"])}
<h2>Modes</h2><div class="grid"><div class="card"><h3>Classic (Standard) and Ranked</h3><p>You and four AI allies vs five AI enemies. Ranked adds bans and seven tiers, Meteorite to Star Sovereign.</p></div><div class="card"><h3>Brawl, Rising, Custom and Auto Battler</h3><p>Single-lane quick matches, a win-to-advance run, custom rules and an 8-player auto battler.</p></div><div class="card"><h3>Spectate and Replays</h3><p>Watch AI vs AI. Your matches are saved automatically and can be rewatched with rewind and speed controls.</p></div></div>
<h2>Support and policies</h2><p>Questions and bug reports: <a href="/en/support">Support</a>. See the <a href="/en/privacy">Privacy Policy</a> and <a href="/en/terms">Terms of Service</a>.</p>`,
  },
};

// ---- サポート ----
const SUPPORT = {
  ja: {
    title: "サポート | VELSIA - 星環の戦場", desc: "VELSIA のお問い合わせ窓口とよくある質問。",
    body: `<div class="doc"><h1>サポート</h1>
<p>ご質問・不具合のご連絡は、メールでお問い合わせください。</p>
<p><strong>お問い合わせ先: <a href="mailto:${cfg.ja.SUPPORT_EMAIL}">${cfg.ja.SUPPORT_EMAIL}</a></strong><br>運営: ${cfg.ja.PUBLISHER_NAME}</p>
<p>不具合のご報告には、アプリ内の「設定 > サポート」から作成できるメールが便利です（アプリのバージョン・端末・OS が自動で入ります）。お返事までにお時間をいただく場合があります。</p>
<h2>よくある質問</h2>
<details><summary>購入したジェムが反映されません</summary><p>通信状態を確認してアプリを再起動してください。未完了の購入は起動時に自動で処理されます。スターパス プレミアムはストアの「購入の復元」で復元できます。解決しない場合はメールでご連絡ください。</p></details>
<details><summary>返金を受けたい</summary><p>App Store での購入は Apple が処理します。<a href="https://reportaproblem.apple.com" rel="noopener">reportaproblem.apple.com</a> から申請してください。返金されたジェムは残高から差し引かれることがあります。</p></details>
<details><summary>データはどこに保存されますか？ 機種変更したい</summary><p>プロフィールやリプレイなどのデータはすべて端末内に保存され、サーバーには送信されません。機種変更では、旧端末の「設定 > データ引き継ぎ」でバックアップを書き出し、新しい端末の同じ画面から読み込んでください。データの削除は「設定 > プライバシー」から行えます。</p></details>
<details><summary>購入に上限はありますか？</summary><p>初回起動時に選ぶ年齢区分に応じて、1か月あたりの購入上限があります（15歳以下 5,000円、16〜19歳 10,000円、20歳以上は上限なし）。未成年の方は保護者の同意を得てご購入ください。</p></details>
<details><summary>対応機種は？</summary><p>iOS 18 以降の iPhone（横画面専用）です。iPad では iPhone 互換モードで動作します。</p></details>
<details><summary>オンラインや通信が必要ですか？</summary><p>対戦はすべてAI相手で、通信なしで遊べます（アプリ内課金の購入時のみ通信します）。</p></details>
<h2>規約・表記</h2>
<ul><li><a href="/privacy">プライバシーポリシー</a></li><li><a href="/terms">利用規約</a></li><li><a href="/tokushoho">特定商取引法に基づく表記</a></li><li><a href="/payment-services">資金決済法に基づく表示</a></li></ul></div>`,
  },
  en: {
    title: "Support | VELSIA: Star Ring Arena", desc: "Contact and FAQ for VELSIA: Star Ring Arena.",
    body: `<div class="doc"><h1>Support</h1>
<p>For questions and bug reports, please email us.</p>
<p><strong>Contact: <a href="mailto:${cfg.en.SUPPORT_EMAIL}">${cfg.en.SUPPORT_EMAIL}</a></strong><br>Operated by ${cfg.en.PUBLISHER_NAME}</p>
<p>For bug reports, the email you can create from Settings &gt; Support in the app is handy (it fills in the app version, device and OS). Replies may take some time.</p>
<h2>FAQ</h2>
<details><summary>My purchased gems didn't arrive</summary><p>Check your connection and restart the app; unfinished purchases are processed at launch. Star Pass Premium can be recovered with Restore Purchases in the Store. Contact us if it persists.</p></details>
<details><summary>How do I get a refund?</summary><p>App Store purchases are handled by Apple. Request a refund at <a href="https://reportaproblem.apple.com" rel="noopener">reportaproblem.apple.com</a>. Refunded gems may be deducted from your balance.</p></details>
<details><summary>Where is my data stored? I'm switching iPhones</summary><p>Your profile, replays and other data are stored only on your device and never sent to a server. To move to a new iPhone, export a backup from Settings &gt; Data Transfer on the old device and import it from the same screen on the new one. You can delete your data from Settings &gt; Privacy.</p></details>
<details><summary>Is there a spending limit?</summary><p>Monthly purchase limits apply based on the age group you choose at first launch (15 and under: ¥5,000; 16 to 19: ¥10,000; 20 and over: none). Minors need a parent's or guardian's consent to buy.</p></details>
<details><summary>Which devices are supported?</summary><p>iPhone with iOS 18 or later (landscape only). On iPad it runs in iPhone compatibility mode.</p></details>
<details><summary>Do I need an internet connection?</summary><p>Every match is against AI and works without a connection (only in-app purchases need one).</p></details>
<h2>Policies</h2>
<ul><li><a href="/en/privacy">Privacy Policy</a></li><li><a href="/en/terms">Terms of Service</a></li><li><a href="/tokushoho">Notation based on the Act on Specified Commercial Transactions (Japanese)</a></li></ul></div>`,
  },
};

// ---- 出力 ----
page({ lang: "ja", path: "/", ...HOME.ja });
page({ lang: "en", path: "/en", ...HOME.en });
page({ lang: "ja", path: "/support", ...SUPPORT.ja });
page({ lang: "en", path: "/en/support", ...SUPPORT.en });
const LEGAL_PAGES = [
  ["ja", "/privacy", "privacy_policy_ja.md", "プライバシーポリシー | VELSIA", "VELSIA のプライバシーポリシー"],
  ["en", "/en/privacy", "privacy_policy_en.md", "Privacy Policy | VELSIA", "Privacy Policy for VELSIA: Star Ring Arena"],
  ["ja", "/terms", "terms_of_service_ja.md", "利用規約 | VELSIA", "VELSIA の利用規約"],
  ["en", "/en/terms", "terms_of_service_en.md", "Terms of Service | VELSIA", "Terms of Service for VELSIA: Star Ring Arena"],
  ["ja", "/tokushoho", "tokushoho_ja.md", "特定商取引法に基づく表記 | VELSIA", "特定商取引法に基づく表記"],
  ["ja", "/payment-services", "payment_services_act_ja.md", "資金決済法に基づく表示 | VELSIA", "資金決済法に基づく表示（前払式支払手段）"],
];
for (const [lang, p, file, title, desc] of LEGAL_PAGES) page({ lang, path: p, title, desc, body: legalHTML(file, lang), cls: "doc" });
fs.writeFileSync(path.join(OUT, "robots.txt"), `User-agent: *\nAllow: /\nSitemap: ${cfg.baseURL}/sitemap.xml\n`);
const urls = ["/", "/en", "/support", "/en/support", ...LEGAL_PAGES.map((x) => x[1])];
fs.writeFileSync(path.join(OUT, "sitemap.xml"), `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls.map((u) => `<url><loc>${cfg.baseURL}${u === "/" ? "" : u}</loc></url>`).join("\n")}\n</urlset>\n`);
console.log(`built ${urls.length} pages → public/`);
