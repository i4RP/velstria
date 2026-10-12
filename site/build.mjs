// VELSIA 公開サイトの生成（依存は marked だけ）。実行: node build.mjs → public/
// 法務ページは VELSTRIA/docs/legal/*.md を正本として、config.json の値を {{…}} に差し込んで作る。
// URL は docs/appstore/metadata と App/Core/FeatureFlags.swift に書いたものと一致させること。
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";
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
// 権利表記は App Store の copyright.txt（2026 BITCOINPAY K.K.）に合わせ、日英のフッターとプレスキットで同じものを使う
const COPYRIGHT = "© 2026 BITCOINPAY K.K.";
const T = {
  ja: {
    lang: "ja", home: "/", name: "VELSIA - 星環の戦場", nav: [["/", "ホーム"], ["/support", "サポート"], ["/press", "プレスキット"], ["/privacy", "プライバシー"], ["/terms", "利用規約"], ["/tokushoho", "特商法表記"], ["/payment-services", "資金決済法表示"]],
    other: "English", otherHref: (p) => (p === "/" ? "/en" : "/en" + p), footer: COPYRIGHT,
  },
  en: {
    lang: "en", home: "/en", name: "VELSIA: Star Ring Arena", nav: [["/en", "Home"], ["/en/support", "Support"], ["/en/press", "Press Kit"], ["/en/privacy", "Privacy"], ["/en/terms", "Terms"], ["/tokushoho", "Commercial Transactions Act (JA)"]],
    other: "日本語", otherHref: (p) => p.replace(/^\/en/, "") || "/", footer: COPYRIGHT,
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
@media(max-width:560px){.bar{row-gap:6px}nav{gap:2px 12px;font-size:13px;line-height:1.6}}
`;

// css はそのページだけに足すスタイル、image は og:image（既定はスクショ）
function page({ lang, path: p, title, desc, body, cls = "", css = "", image = `/assets/shots/${lang}/01_battle_teamfight.jpg` }) {
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
<meta property="og:url" content="${url}"><meta property="og:image" content="${cfg.baseURL}${image}">
<style>${CSS}${css}</style></head><body>
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
<h2>お問い合わせ・規約</h2><p>ご質問・不具合報告は <a href="/support">サポート</a> へ。<a href="/privacy">プライバシーポリシー</a>・<a href="/terms">利用規約</a>・<a href="/tokushoho">特定商取引法に基づく表記</a>・<a href="/payment-services">資金決済法に基づく表示</a>をご確認ください。報道・配信向けの素材は<a href="/press">プレスキット</a>にあります。</p>`,
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
<h2>Support and policies</h2><p>Questions and bug reports: <a href="/en/support">Support</a>. See the <a href="/en/privacy">Privacy Policy</a> and <a href="/en/terms">Terms of Service</a>. Assets for press and creators are in the <a href="/en/press">Press Kit</a>.</p>`,
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

// ---- プレスキット（/press, /en/press） ----
// 素材は assets/press/（一覧用の縮小版は thumbs/、スクショは assets/shots/ を流用）。寸法と容量はビルド時にファイルから読む。
// 数字はゲーム本体（master_runtime.json など）に合わせる。トップや App Store の文言（24人・72装備など）は古いので写さない。
// 対戦・通信の記述は製品版（FeatureFlags.lanMatch == false、config.json の onlineMatch: false）が前提。
const ROLE_JA = { Vanguard: "ヴァンガード", Duelist: "デュエリスト", Ranger: "レンジャー", Arcanist: "アルカニスト", Support: "サポート", Assassin: "アサシン" };
// [ID, 日本語名, 英語名, ロール]。名前は master_runtime.json の display_name_ja と App/Resources/master_en.json
const HEROES = [
  ["H001", "城門の誓衛アルデン", "Alden, Gate Warden", "Vanguard"], ["H002", "星弦のリラ", "Lyra, Starstring", "Duelist"],
  ["H003", "月弓のフィリエル", "Firiel, Moonbow", "Ranger"], ["H004", "潮祈のミレア", "Mirea, Tidecaller", "Arcanist"],
  ["H005", "黒雷のヴォス", "Voss, Blackthunder", "Support"], ["H006", "月灯のセレン", "Seren, Moonlantern", "Assassin"],
  ["H007", "岩脈のガルク", "Garruk, Stonevein", "Vanguard"], ["H008", "風標のニア", "Nia, Windvane", "Duelist"],
  ["H009", "機巧士オリン", "Orin, the Artificer", "Ranger"], ["H010", "焔冠のテッサ", "Thessa, Flamecrown", "Arcanist"],
  ["H011", "鉄翼のルーク", "Rook, Ironwing", "Support"], ["H012", "玻璃歌のエリネ", "Elyne, Crystalsong", "Assassin"],
  ["H013", "獣刻のダガン", "Dagan, Beastbrand", "Vanguard"], ["H014", "霧歩のシオ", "Sio, Mistwalker", "Duelist"],
  ["H015", "戦鐘のヴァルカ", "Valka, Warbell", "Ranger"], ["H016", "白環のイリス", "Iris, White Halo", "Arcanist"],
  ["H017", "深淵鎖のモルド", "Mord, Abysschain", "Support"], ["H018", "花星のセリア", "Celia, Blossomstar", "Assassin"],
  ["H019", "砦砕のブラム", "Bram, Fortbreaker", "Vanguard"], ["H020", "光矢のユナ", "Yuna, Lightarrow", "Duelist"],
  ["H021", "時砂のキロス", "Kiros, Timesand", "Ranger"], ["H022", "蒼爪のレア", "Rhea, Azureclaw", "Arcanist"],
  ["H023", "雷槍のトレン", "Toren, Thunderspear", "Support"], ["H024", "夢織のノア", "Noa, Dreamweaver", "Assassin"],
  ["H025", "月弦のルミナ", "Lumina, Moonstring", "Ranger"], ["H026", "紫電のエウリア", "Euria, Violetbolt", "Arcanist"],
  ["H027", "竜槍のジャルド", "Jarld, Dragonspear", "Duelist"], ["H028", "断空のザイル", "Zail, Skycleaver", "Assassin"],
  ["H029", "聖槌のボルグ", "Borg, Holyhammer", "Support"], ["H030", "星砲のライナ", "Raina, Starcannon", "Ranger"],
  ["H031", "氷嵐のオーリア", "Oria, Icestorm", "Arcanist"], ["H032", "赤拳のディアス", "Dias, Redfist", "Duelist"],
  ["H033", "紅牙のヴァルド", "Vald, Crimsonfang", "Assassin"], ["H034", "鎖鉤のゴルム", "Gorm, Chainhook", "Support"],
];
// スキンアート [ID, ヒーロー, 日本語名, 英語名]。名前は master_ja.json / master_en.json
const SKINS = [
  ["CO001", "H001", "星鍛のアルデン", "Starforged Alden"], ["CO025", "H001", "蝕の哨兵アルデン", "Eclipse Sentinel Alden"], ["CO049", "H001", "極光の城塞アルデン", "Aurora Bastion Alden"],
  ["CO007", "H007", "黒曜の巨人ガルク", "Obsidian Titan Garruk"], ["CO031", "H007", "溶岩脈のガルク", "Magma Vein Garruk"], ["CO055", "H007", "水晶の巨像ガルク", "Crystal Colossus Garruk"],
  ["CO013", "H013", "霜牙のダガン", "Frostfang Dagan"], ["CO037", "H013", "熾火纏いのダガン", "Emberhide Dagan"], ["CO061", "H013", "天獣のダガン", "Celestial Beast Dagan"],
  ["CO019", "H019", "鉄の攻城兵ブラム", "Iron Siege Bram"], ["CO043", "H019", "雷の破城槌ブラム", "Thunder Ram Bram"], ["CO067", "H019", "星墜の破砕者ブラム", "Starfall Breaker Bram"],
];

const FACTS = {
  ja: [
    ["タイトル", "VELSIA - 星環の戦場（英語版: VELSIA: Star Ring Arena）"],
    ["ジャンル", "5対5 MOBA（AIの味方と組み、AIの敵と戦う）"],
    ["App Store カテゴリ", "ゲーム（アクション、ストラテジー）"],
    ["対応機種", "iPhone（横画面専用。iPad では iPhone 互換モードで動作）"],
    ["最低 OS", "iOS 18.0 以降"],
    ["価格", "基本プレイ無料"],
    ["課金モデル", "アプリ内課金あり。アストラルジェム（160円〜15,800円）とスターパス プレミアム（シーズンごとに980円）、いずれも税込。ジェムで買えるのはスキンなどの見た目アイテム。ヒーローはプレイで貯まるコインで解放。スターパス プレミアムは見た目アイテムに加えてコインとジェムも獲得でき、ヒーローの解放が早まる。ランダム型の有料アイテムと広告はなし。"],
    ["言語", "日本語、英語（アプリ内で切り替え可能）"],
    ["通信", "AIとの対戦は通信不要（製品版の通信はアプリ内課金の購入時のみ）"],
    ["収録内容", "ヒーロー34人（6ロール）、装備92種、バトルスペル15種、ルーン30種"],
    ["年齢区分", "9+（予定）"],
    ["開発・販売", cfg.ja.PUBLISHER_NAME],
    ["公式サイト", cfg.baseURL],
    ["お問い合わせ", cfg.ja.SUPPORT_EMAIL],
    ["リリース状況", "App Store 公開準備中（社内テスト中・公開日未定）"],
    ["著作権表記", COPYRIGHT],
  ],
  en: [
    ["Title", "VELSIA: Star Ring Arena (Japanese title: VELSIA - 星環の戦場)"],
    ["Genre", "5v5 MOBA (team up with AI allies against AI enemies)"],
    ["App Store category", "Games (Action, Strategy)"],
    ["Platform", "iPhone (landscape only; runs in iPhone compatibility mode on iPad)"],
    ["Minimum OS", "iOS 18.0 or later"],
    ["Price", "Free to play"],
    ["Business model", "Optional in-app purchases: Astral Gems (JPY 160 to 15,800) and Star Pass Premium (JPY 980 per season), tax included, Japan App Store prices. Gems buy cosmetic items such as skins. Heroes unlock with Coins earned by playing. Star Pass Premium also awards Coins and Astral Gems on top of cosmetics, which speeds up hero unlocks. No paid item is randomized and there are no ads."],
    ["Languages", "Japanese, English (switchable in the app)"],
    ["Connectivity", "Not needed for matches against AI (in the release version, only in-app purchases use a connection)"],
    ["Content", "34 heroes in 6 roles, 92 items, 15 battle spells, 30 runes"],
    ["Age rating", "9+ (planned)"],
    ["Developer / Publisher", cfg.en.PUBLISHER_NAME],
    ["Website", cfg.baseURL + "/en"],
    ["Contact", cfg.en.SUPPORT_EMAIL],
    ["Release status", "Preparing for App Store release (internal testing; release date TBA)"],
    ["Copyright", COPYRIGHT],
  ],
};

const ABOUT = {
  ja: [
    "『VELSIA - 星環の戦場』は、iPhone 向けの 5対5 MOBA です。舞台は星環が砕けた世界ベルシア。34人のヒーローから1人を選び、AIの味方4人と3つのレーンを押し上げて、敵のスターコアの破壊を目指します。1試合は10〜18分ほどが目安です。",
    "ヒーローは6つのロール（ヴァンガード、デュエリスト、レンジャー、アルカニスト、サポート、アサシン）に分かれ、どのヒーローもパッシブ、2つのスキル、アルティメットを持ちます。装備92種は試合中いつでも購入・合成でき、15種のバトルスペル、30種のルーンと組み合わせて自分のビルドを作れます。レーンごとに3段のタワーがあり、ジャングルの番人や河川のボス、草むらと視界を使った駆け引きが勝敗を分けます。味方も敵もAIが状況を見て動き、難易度は3段階から選べます。",
    "モードは、クラシック、ランク戦（BAN付きドラフト、7段階のランク）、乱闘、ライジング、AI対戦／カスタム、8人で戦うオートバトラーの6つです。チュートリアル、練習場、AI同士の観戦、リプレイも用意しています。AIとの対戦は通信なしで遊べます。基本プレイ無料で、有料のアプリ内課金はスキンなどの見た目アイテムに使うアストラルジェムと、シーズンごとに購入するスターパス プレミアムです。ヒーローはプレイで貯まるコインで解放でき、スターパス プレミアムでは見た目アイテムに加えてコインとジェムも獲得できます。ランダム型の有料アイテムや広告はありません。日本語と英語に対応しています。",
  ],
  en: [
    "VELSIA: Star Ring Arena is a 5v5 MOBA for iPhone. It is set in Velsia, a world where the Star Ring has shattered. Choose one of 34 heroes, team up with four AI allies, push three lanes and destroy the enemy Star Core. Matches last roughly 10 to 18 minutes.",
    "Heroes are split into six roles: Vanguard, Duelist, Ranger, Arcanist, Support and Assassin. Every hero has a Passive, two Skills and an Ultimate. You can buy and combine any of the 92 items at any point in a match, and pair them with 15 battle spells and 30 runes to make your build. Each lane has three tiers of towers. Jungle sentinels, river bosses, brush and vision all shape the match. AI allies and enemies react to how the match unfolds, and you can choose from three difficulty levels.",
    "The modes are Classic, Ranked (draft with bans and seven tiers), Brawl, Rising, AI & Custom, and an 8-player Auto Battler. There are also a Tutorial, Practice mode, AI vs AI spectating and replays. Matches against AI work without a connection. The game is free to play. The paid in-app purchases are Astral Gems, which buy cosmetic items such as skins, and Star Pass Premium, which is bought each season. Heroes unlock with Coins earned by playing, and Star Pass Premium also awards Coins and Astral Gems on top of cosmetics. There are no randomized paid items and no ads. The game is available in Japanese and English.",
  ],
};

// [見出し, 本文]
const FEATURES = {
  ja: [
    ["34人のヒーロー、6つのロール", "どのヒーローもパッシブ、2つのスキル、アルティメットを持つ。最初はロールごとに1人の計6人を使え、残る28人はプレイで貯まるコインで解放。"],
    ["3レーンとジャングル", "レーンごとに3段のタワー、ジャングルの番人（蒼晶・紅焔）、河川のボス（星喰竜・古環の巨像）、草むらとチームごとの視界。最大レベル15。"],
    ["92種の装備、15種のバトルスペル、30種のルーン", "装備は攻撃・魔法・防御・移動の4カテゴリで、試合中いつでも購入・合成できる。ルーンは5つのパス。"],
    ["状況を読むAI", "味方も敵もレーン戦、ジャングル、撤退、ボス争奪、集団戦を状況で判断。難易度は3段階（かんたん・ふつう・むずかしい）。"],
    ["多彩なモード", "クラシック、ランク戦（BAN付きドラフト、隕鉄から星環王までの7段階）、乱闘、ライジング（6ステージの勝ち上がり）、AI対戦／カスタム、8人のオートバトラー。"],
    ["観戦とリプレイ", "AI同士の対戦を観戦でき、自分の試合は自動保存。巻き戻しや倍速で見返せる。"],
    ["はじめてでも安心", "全5章のチュートリアルと練習場。攻撃の自動ターゲットや、おすすめ装備のワンタップ購入。"],
    ["見た目中心の課金", "基本プレイ無料。有料はアストラルジェムとスターパス プレミアム（全30段階、シーズンごとの購入）。プレミアムは見た目アイテムに加えてコインとジェムも獲得できる。ランダム型の有料アイテムと広告はなし。"],
    ["遊びやすさ", "横画面のタッチ操作、左利きレイアウト、色覚サポート、30/60 FPS の切り替え。日本語と英語に対応。"],
  ],
  en: [
    ["34 heroes, 6 roles", "Every hero has a Passive, two Skills and an Ultimate. Start with six heroes, one per role, and unlock the other 28 with Coins earned by playing."],
    ["Three lanes and a jungle", "Three tiers of towers per lane, Azure and Crimson Sentinels, the river's Astral Wyrm and Ancient Colossus, brush and team vision. Level cap of 15."],
    ["92 items, 15 battle spells, 30 runes", "Items cover attack, magic, defense and movement and can be bought and combined at any point in a match. Runes come in five paths."],
    ["AI that reads the game", "Allies and enemies decide when to lane, jungle, retreat, fight for bosses and group up. Choose Easy, Normal or Hard."],
    ["Lots of modes", "Classic, Ranked (draft with bans and seven tiers, Meteorite to Star Sovereign), Brawl, Rising (a six-stage win-to-advance run), AI & Custom and an 8-player Auto Battler."],
    ["Spectate and replays", "Watch AI vs AI, and rewatch your automatically saved matches with rewind and speed controls."],
    ["Newcomer-friendly", "A five-chapter Tutorial and Practice mode, auto-targeting attacks and one-tap recommended items."],
    ["Cosmetic-focused purchases", "Free to play. Paid items are Astral Gems and Star Pass Premium (30 levels, bought each season), which also awards Coins and Astral Gems on top of cosmetics. No randomized paid items and no ads."],
    ["Accessibility and options", "Landscape touch controls, left-handed layout, colorblind support and a 30/60 FPS setting. Available in Japanese and English."],
  ],
};

const GUIDE = {
  ja: [
    "報道、レビュー、紹介記事、動画・配信、SNS への投稿で、このプレスキットの素材とゲーム画面（スクリーンショット・動画）を自由にお使いいただけます。事前のご連絡は不要です。",
    "トリミングと拡大・縮小は自由です。記事やサムネイルのレイアウトに素材を配置して、見出しなどの文字を重ねたり、ほかの画像と並べたりすることもできます。素材そのものの改変（色や形の変更、キャラクターの描き換えなど）はしないでください。",
    "ロゴとシンボルマークは変形しないでください（縦横比の変更、回転、色の変更、効果の追加、一部の切り取りを含みます）。シンボルマークは白一色なので、暗い背景の上でお使いください。",
    "キャラクターやゲームを誹謗中傷する利用、公序良俗に反する利用、当社が公認・提携していると誤解させる利用はできません。",
    `素材を掲載するときは、権利表記「${COPYRIGHT}」を添えてください。`,
    "素材そのものの販売・再配布や、グッズなどの商品化には事前の許諾が必要です。お問い合わせ先までご相談ください。",
    "スクリーンショットなどの素材には開発中の画面が含まれ、製品版と異なる場合があります。",
    "このガイドラインは予告なく変更することがあります。",
  ],
  en: [
    "You are free to use the materials in this press kit, as well as screenshots and footage of the game, in news coverage, reviews, articles, videos, streams and social media posts. You don't need to ask us first.",
    "You may crop and resize the materials. You may also place them in article and thumbnail layouts, put headlines or other text over them and show them alongside other images. Don't alter the materials themselves, for example by changing their colors or shapes or redrawing the characters.",
    "Don't alter the logo or the symbol mark (this includes stretching, rotating, recoloring, adding effects and cutting off parts). The symbol mark is solid white, so place it on a dark background.",
    "Don't use the materials to disparage the characters or the game, in ways that are offensive or against public decency, or in ways that suggest we endorse or partner with you.",
    `Include the copyright notice "${COPYRIGHT}" when you publish the materials.`,
    "Selling or redistributing the materials themselves, or using them on merchandise, needs our permission first. Please contact us.",
    "Some materials, such as screenshots, show the game in development and may differ from the released version.",
    "These guidelines may change without notice.",
  ],
};

const PT = {
  ja: {
    title: "プレスキット | VELSIA - 星環の戦場", desc: "VELSIA - 星環の戦場 の報道・配信向け素材（アイコン、ロゴ、キーアート、スクリーンショット、ヒーロー画像）とファクトシート。",
    h1: "プレスキット", lead: "報道・レビュー・配信向けに、ゲームの情報と画像素材をまとめました。下の利用ガイドラインの範囲で自由にお使いください。",
    zip: (size) => `素材一式をダウンロード（ZIP, ${size}）`, dl: "ダウンロード", logoAlt: "VELSIA 星環の戦場", keyAlt: "キーアート",
    zipNote: `アイコン、ロゴ、キーアート、スクリーンショット（日英）、ヒーロー${HEROES.length}人の画像、スキンアート${SKINS.length}点と、ファクトシート・利用ガイドライン（日英）の README.txt を収録。`,
    h: { facts: "ファクトシート", about: "概要", features: "特徴", assets: "ダウンロード素材", guide: "利用ガイドライン", contact: "お問い合わせ" },
    contact: `取材や素材についてのお問い合わせは <a href="mailto:${cfg.ja.SUPPORT_EMAIL}">${cfg.ja.SUPPORT_EMAIL}</a> までメールでお寄せください。<br>運営: ${cfg.ja.PUBLISHER_NAME}<br>ゲームについてのご質問や不具合のご報告は<a href="/support">サポート</a>へ。`,
    contactText: `取材や素材についてのお問い合わせ: ${cfg.ja.SUPPORT_EMAIL}（${cfg.ja.PUBLISHER_NAME}）`,
  },
  en: {
    title: "Press Kit | VELSIA: Star Ring Arena", desc: "Fact sheet and assets for press and creators: app icon, logo, key art, screenshots and hero art for VELSIA: Star Ring Arena.",
    h1: "Press Kit", lead: "Game information and art for press, reviewers and creators. Use them freely within the guidelines below.",
    zip: (size) => `Download all assets (ZIP, ${size})`, dl: "Download", logoAlt: "VELSIA 星環の戦場 logo", keyAlt: "Key art",
    zipNote: `Includes the app icon, logo, key art, screenshots (Japanese and English UI), portraits of all ${HEROES.length} heroes, art for ${SKINS.length} skins and a README.txt with the fact sheet and guidelines in Japanese and English.`,
    h: { facts: "Fact sheet", about: "About the game", features: "Features", assets: "Downloads", guide: "Usage guidelines", contact: "Contact" },
    contact: `For press and asset inquiries, email <a href="mailto:${cfg.en.SUPPORT_EMAIL}">${cfg.en.SUPPORT_EMAIL}</a>.<br>Operated by ${cfg.en.PUBLISHER_NAME}<br>For questions about the game and bug reports, see <a href="/en/support">Support</a>.`,
    contactText: `Press and asset inquiries: ${cfg.en.SUPPORT_EMAIL} (${cfg.en.PUBLISHER_NAME})`,
  },
};

// PNG / JPEG のヘッダから寸法を読む
function imgSize(buf, name) {
  if (buf.readUInt32BE(0) === 0x89504e47) return [buf.readUInt32BE(16), buf.readUInt32BE(20)];
  for (let i = 2; buf[i] === 0xff && i + 9 < buf.length; ) {
    const m = buf[i + 1];
    if (m === 0xff) { i++; continue; } // 詰め物の 0xFF
    if (m >= 0xc0 && m <= 0xcf && m !== 0xc4 && m !== 0xc8 && m !== 0xcc) return [buf.readUInt16BE(i + 7), buf.readUInt16BE(i + 5)];
    i += 2 + buf.readUInt16BE(i + 2);
  }
  throw new Error(`${name}: 画像の寸法を読めません`);
}

// 素材 1 点。src は assets/ から、zip は ZIP 内のパス（ファイル名は英数字だけ。ダウンロード時の名前にも使う）
// sub はカードの補足行（配列にした行は、その区切りでだけ折り返す）、readme は README のファイル一覧での名前（省略時は label）
const ASSETS = path.join(ROOT, "assets");
function asset(src, zip, label, { sub, readme } = {}) {
  const buf = fs.readFileSync(path.join(ASSETS, src));
  const thumb = src.startsWith("press/") ? [".jpg", ".png"].map((x) => src.replace("press/", "press/thumbs/").replace(/\.\w+$/, x)).find((t) => fs.existsSync(path.join(ASSETS, t))) : null;
  const tsize = thumb ? imgSize(fs.readFileSync(path.join(ASSETS, thumb)), thumb) : imgSize(buf, src);
  return { src, zip, label, sub, readme: readme ?? label, thumb: thumb ?? src, size: imgSize(buf, src), tsize, bytes: buf.length, type: src.endsWith(".png") ? "PNG" : "JPEG" };
}
const slug = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
// プレスキットに載せるスクショ [ファイル, 日本語名, 英語名]。トップの SHOTS のうち 01（廃止した旧 HUD）・03（24/24 とデバッグ用の通貨）・
// 05（旧仕様のスキル 3）は本文の数字と食い違うので、現行ビルド（34人・スキル 2 つ・新 HUD）で撮り直すまで載せない
const PRESS_SHOTS = [["02_home", "ホーム画面", "Home screen"], ["08_skin_store", "スキンストア", "Skin store"], ["10_spectate", "観戦", "Spectate"]];
const SHOT_NOTE = { ja: "開発中の画面です。製品版とは異なる場合があります。", en: "Taken during development. The released version may differ." };
// ダーク用アイコンは通常版と同じ絵柄なので、ファイルは置かずに注記だけ載せる
const PRESS_SECTIONS = [
  { id: "icon", ja: "アプリアイコン", en: "App icon", tile: "sq",
    note: { ja: "角丸なしの正方形（不透明）です。iOS のダークモード用アイコンは通常版と同じ絵柄です。", en: "Square, opaque, without rounded corners. The iOS dark mode icon uses the same artwork as the standard one." },
    items: [
      asset("press/icon/velsia-icon-1024.png", "icon/velsia-icon-1024.png", { ja: "アプリアイコン", en: "App icon" }),
      asset("press/icon/velsia-icon-512.png", "icon/velsia-icon-512.png", { ja: "アプリアイコン（小）", en: "App icon (small)" }),
      asset("press/icon/velsia-icon-tinted-1024.png", "icon/velsia-icon-tinted-1024.png", { ja: "ティント用（白黒）", en: "Tinted (white on black)" }),
    ] },
  { id: "logo", ja: "ロゴ", en: "Logo", tile: "logo",
    note: { ja: "どちらも透過 PNG です。シンボルマークは白一色なので、暗い背景の上でお使いください。", en: "Both are transparent PNGs. The logo includes the Japanese subtitle 星環の戦場 (there is no English-only version). The symbol mark is solid white, so place it on a dark background." },
    items: [
      asset("press/logo/velsia-logo.png", "logo/velsia-logo.png", { ja: "ロゴ", en: "Logo" }),
      asset("press/logo/velsia-mark.png", "logo/velsia-mark.png", { ja: "シンボルマーク（白）", en: "Symbol mark (white)" }),
    ] },
  { id: "art", ja: "キーアート・背景", en: "Key art and backdrop", tile: "wide",
    items: [
      asset("press/art/velsia-keyart.jpg", "art/velsia-keyart.jpg", { ja: "キーアート", en: "Key art" }),
      asset("press/art/velsia-backdrop.jpg", "art/velsia-backdrop.jpg", { ja: "背景アート（星環）", en: "Backdrop art (Star Ring)" }),
    ] },
  ...["ja", "en"].map((l) => ({
    id: `shots-${l}`, ja: `スクリーンショット（${l === "ja" ? "日本語版" : "英語版"}）`, en: `Screenshots (${l === "ja" ? "Japanese" : "English"} UI)`, tile: "shot", note: SHOT_NOTE,
    items: PRESS_SHOTS.map(([s, ja, en]) => asset(`shots/${l}/${s}.jpg`, `screenshots/${l}/velsia-${l}-${s}.jpg`, { ja, en })),
  })),
  { id: "heroes", ja: `ヒーロー（${HEROES.length}人）`, en: `Heroes (${HEROES.length})`, tile: "hero",
    items: HEROES.map(([id, ja, en, role]) => asset(`press/heroes/${id}.jpg`, `heroes/${id}-${slug(en)}.jpg`, { ja, en }, { sub: { ja: [en, ROLE_JA[role]], en: [ja, role] }, readme: { ja: `${ja}（${ROLE_JA[role]}）`, en: `${en} (${role})` } })) },
  { id: "skins", ja: "スキンアート", en: "Skin art", tile: "hero",
    items: SKINS.map(([id, h, ja, en]) => {
      const [, hja, hen] = HEROES.find((x) => x[0] === h);
      return asset(`press/splash/${id}.jpg`, `skins/${id}-${slug(en)}.jpg`, { ja, en }, { sub: { ja: [en, [hja, "のスキン"]], en: [ja, `Skin for ${hen}`] }, readme: { ja: `${ja}（${hja}のスキン）`, en: `${en} (skin for ${hen})` } });
    }) },
];

// スクショの枠は画像と同じ比率にする（16:9 の枠だと上下に帯が出る）。比率が揃っていなければ止める
const SHOT_RATIO = (() => {
  const r = [...new Set(PRESS_SECTIONS.filter((s) => s.tile === "shot").flatMap((s) => s.items.map((a) => a.size.join("/"))))];
  if (r.length !== 1) throw new Error(`スクショの縦横比が揃っていません: ${r.join(", ")}`);
  return r[0];
})();
const fmtBytes = (n) => (n >= 1e6 ? `${(n / 1e6).toFixed(1)} MB` : `${Math.round(n / 1e3)} KB`);
function assetCard(a, lang) {
  const label = esc(a.label[lang]);
  return `<figure class="asset"><a class="th" href="/assets/${a.src}" target="_blank" rel="noopener"><img src="/assets/${a.thumb}" width="${a.tsize[0]}" height="${a.tsize[1]}" alt="${label}" loading="lazy" decoding="async"></a>`
    + `<figcaption><b>${label}</b>${(a.sub?.[lang] ?? []).map((s) => `<span class="sub">${[s].flat().map(esc).join("<wbr>")}</span>`).join("")}<span class="meta"><span>${a.size.join(" × ")} px</span><span>${a.type} · ${fmtBytes(a.bytes)}</span></span>`
    + `<a class="dl" href="/assets/${a.src}" download="${path.basename(a.zip)}">${PT[lang].dl}</a></figcaption></figure>`;
}

// 目次から飛んだ見出しが固定ヘッダーに隠れないよう、ヘッダーの高さ＋約 20px を空ける。ヘッダーはナビの折り返しで高くなる
// （Chrome 実測: 820px 以上 55px、690〜819px 98px、561〜689px 126px、560px 以下 105px・日本語の 320px のみ 127px）。ナビを変えたら測り直す
const PRESS_CSS = `
.press [id]{scroll-margin-top:76px}
@media(max-width:899px){.press [id]{scroll-margin-top:120px}}
@media(max-width:719px){.press [id]{scroll-margin-top:148px}}
@media(max-width:560px){.press [id]{scroll-margin-top:132px}}
.press>h3{color:var(--gold);font-size:18px;margin:28px 0 4px}
.btn{display:inline-block;margin-top:16px;background:var(--gold);color:#1b1400;font-weight:800;padding:12px 24px;border-radius:999px;text-decoration:none}
.btn:hover{color:#1b1400;background:#ffd977}
.note{color:var(--sub);font-size:14px;margin:8px 0}
.toc{display:flex;flex-wrap:wrap;gap:4px 18px;font-size:15px;margin:0}
.facts{display:grid;grid-template-columns:max-content 1fr;margin:12px 0 28px;background:var(--panel);border:1px solid var(--line);border-radius:14px;overflow:hidden}
.facts dt,.facts dd{margin:0;padding:9px 16px;border-top:1px solid var(--line)}
.facts dt:first-of-type,.facts dt:first-of-type+dd{border-top:0}
.facts dt{color:var(--gold);font-weight:700;font-size:15px}
.about{background:var(--panel);border:1px solid var(--line);border-radius:14px;padding:4px 20px}
.guide li{margin:6px 0}
.assets{display:grid;grid-template-columns:repeat(auto-fill,minmax(min(100%,210px),1fr));gap:14px;margin:10px 0 8px}
.t-wide,.t-shot{grid-template-columns:repeat(auto-fill,minmax(min(100%,300px),1fr))}
.t-hero{grid-template-columns:repeat(auto-fill,minmax(min(100%,150px),1fr))}
.asset{margin:0;display:flex;flex-direction:column;background:var(--panel);border:1px solid var(--line);border-radius:12px;overflow:hidden}
.asset .th{display:block;position:relative;aspect-ratio:1;background:#070b17}
.t-wide .th{aspect-ratio:16/9}.t-shot .th{aspect-ratio:${SHOT_RATIO}}
.t-logo .th{aspect-ratio:16/9;background:repeating-conic-gradient(#1a2242 0 25%,#10162c 0 50%) 0 0/20px 20px}
.asset img{position:absolute;inset:0;width:100%;height:100%;object-fit:contain}
.t-logo img{padding:16px}
.asset figcaption{flex:1;display:flex;flex-direction:column;padding:10px 12px 12px;font-size:13px;line-height:1.55;color:var(--sub)}
.asset b{color:var(--text);font-size:14px}
.asset .sub{word-break:keep-all;overflow-wrap:anywhere}
.asset .meta{display:flex;flex-wrap:wrap;column-gap:.9em}
.asset .dl{margin-top:auto;padding-top:6px;font-weight:700}
@media(max-width:560px){.facts{grid-template-columns:1fr}.facts dd{border-top:0;padding-top:0}}
`;

function pressBody(lang, zipHref, zipBytes) {
  const t = PT[lang];
  const value = (v) => (/^https?:\/\//.test(v) ? `<a href="${v}">${v}</a>` : /^[\w.+-]+@[\w.-]+$/.test(v) ? `<a href="mailto:${v}">${v}</a>` : esc(v));
  const key = PRESS_SECTIONS.find((s) => s.id === "art").items[0];
  return `<section class="hero"><div><img class="logo" src="/assets/logo.png" alt="${t.logoAlt}" width="420"><h1>${t.h1}</h1>
<p class="lead">${t.lead}</p>
<a class="btn" href="${zipHref}" download="velsia-presskit.zip">${t.zip(fmtBytes(zipBytes))}</a><p class="note">${t.zipNote}</p></div>
<img class="shot" src="/assets/${key.src}" alt="${t.keyAlt}" width="${key.size[0]}" height="${key.size[1]}"></section>
<p class="toc">${Object.entries(t.h).map(([id, h]) => `<a href="#${id}">${h}</a>`).join("")}</p>
<h2 id="facts">${t.h.facts}</h2><dl class="facts">${FACTS[lang].map(([k, v]) => `<dt>${esc(k)}</dt><dd>${value(v)}</dd>`).join("")}</dl>
<h2 id="about">${t.h.about}</h2><div class="about">${ABOUT[lang].map((p) => `<p>${esc(p)}</p>`).join("")}</div>
<h2 id="features">${t.h.features}</h2><div class="grid">${FEATURES[lang].map(([h, p]) => `<div class="card"><h3>${esc(h)}</h3><p>${esc(p)}</p></div>`).join("")}</div>
<h2 id="assets">${t.h.assets}</h2>
${PRESS_SECTIONS.map((s) => `<h3 id="${s.id}">${esc(s[lang])}</h3>${s.note ? `<p class="note">${esc(s.note[lang])}</p>` : ""}<div class="assets t-${s.tile}">\n${s.items.map((a) => assetCard(a, lang)).join("\n")}\n</div>`).join("\n")}
<h2 id="guide">${t.h.guide}</h2><ul class="guide">${GUIDE[lang].map((g) => `<li>${esc(g)}</li>`).join("")}</ul>
<h2 id="contact">${t.h.contact}</h2><p>${t.contact}</p>`;
}

// ZIP に入れる README.txt（日英のファクトシート・概要・利用ガイドラインとファイル一覧）。Windows のメモ帳向けに BOM と CRLF
function pressReadme() {
  const L = ["VELSIA プレスキット / VELSIA Press Kit", `${cfg.baseURL}/press`, `${cfg.baseURL}/en/press`];
  const head = (t) => L.push("", "=".repeat(60), t, "=".repeat(60));
  const sec = (t) => L.push("", `■ ${t}`);
  for (const lang of ["ja", "en"]) {
    const t = PT[lang];
    head(lang === "ja" ? "日本語" : "English");
    sec(t.h.facts);
    for (const [k, v] of FACTS[lang]) L.push(`${k}: ${v}`);
    sec(t.h.about);
    L.push(ABOUT[lang].join("\n\n"));
    sec(t.h.guide);
    for (const g of GUIDE[lang]) L.push(`- ${g}`);
    sec(t.h.contact);
    L.push(t.contactText);
  }
  head("ファイル一覧 / Files");
  for (const s of PRESS_SECTIONS) {
    sec(`${s.ja} / ${s.en}`);
    if (s.note) L.push(`※ ${s.note.ja}`, `* ${s.note.en}`);
    for (const a of s.items) L.push(`${a.zip}  ${a.size.join("x")}  ${a.readme.ja} / ${a.readme.en}`);
  }
  return "﻿" + L.join("\n").replace(/\n/g, "\r\n") + "\r\n";
}

// ---- ZIP（依存なし。圧縮は node:zlib の deflateRawSync、CRC32 は自前の表） ----
const CRC_TABLE = new Uint32Array(256).map((_, n) => {
  for (let k = 0; k < 8; k++) n = n & 1 ? 0xedb88320 ^ (n >>> 1) : n >>> 1;
  return n;
});
function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
// entries: [ZIP 内のパス, Buffer]。日時は固定（中身が同じなら同じ ZIP になる）
function makeZip(entries) {
  const DOS_DATE = ((2026 - 1980) << 9) | (10 << 5) | 12, DOS_TIME = 0;
  const parts = [], dir = [];
  let offset = 0;
  for (const [name, data] of entries) {
    if (!/^[\x21-\x7e]+$/.test(name)) throw new Error(`ZIP のファイル名は英数字だけにする: ${name}`);
    const n = Buffer.from(name);
    const deflated = zlib.deflateRawSync(data, { level: 9 });
    const stored = deflated.length >= data.length; // 縮まないもの（JPEG など）は無圧縮で格納
    const body = stored ? data : deflated;
    // ローカルヘッダと中央ディレクトリで共通の 26 バイト（必要バージョン〜拡張フィールド長）
    const common = Buffer.alloc(26);
    common.writeUInt16LE(20, 0);
    common.writeUInt16LE(stored ? 0 : 8, 4);
    common.writeUInt16LE(DOS_TIME, 6);
    common.writeUInt16LE(DOS_DATE, 8);
    common.writeUInt32LE(crc32(data), 10);
    common.writeUInt32LE(body.length, 14);
    common.writeUInt32LE(data.length, 18);
    common.writeUInt16LE(n.length, 22);
    const sig = (v, extra = 0) => { const b = Buffer.alloc(4 + extra); b.writeUInt32LE(v); return b; };
    parts.push(sig(0x04034b50), common, n, body);
    const made = sig(0x02014b50, 2);
    made.writeUInt16LE(0x0314, 4); // 作成: Unix / 2.0（展開時のパーミッションを 644 にする）
    const tail = Buffer.alloc(14); // コメント長・ディスク番号・内部属性は 0
    tail.writeUInt32LE((0o100644 << 16) >>> 0, 6);
    tail.writeUInt32LE(offset, 10);
    dir.push(made, common, tail, n);
    offset += 30 + n.length + body.length;
  }
  const cd = Buffer.concat(dir);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(entries.length, 8);
  end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(cd.length, 12);
  end.writeUInt32LE(offset, 16);
  return Buffer.concat([...parts, cd, end]);
}

// ---- 出力 ----
page({ lang: "ja", path: "/", ...HOME.ja });
page({ lang: "en", path: "/en", ...HOME.en });
page({ lang: "ja", path: "/support", ...SUPPORT.ja });
page({ lang: "en", path: "/en/support", ...SUPPORT.en });
// プレスキットの ZIP を先に作り、その容量をページのボタンに載せる。/assets/ は immutable キャッシュなので ?v= に CRC を付ける
const pressZip = makeZip([
  ["velsia-presskit/README.txt", Buffer.from(pressReadme())],
  ...PRESS_SECTIONS.flatMap((s) => s.items.map((a) => [`velsia-presskit/${a.zip}`, fs.readFileSync(path.join(ASSETS, a.src))])),
]);
fs.writeFileSync(path.join(OUT, "assets", "press", "velsia-presskit.zip"), pressZip);
const pressZipHref = `/assets/press/velsia-presskit.zip?v=${crc32(pressZip).toString(16).padStart(8, "0")}`;
for (const lang of ["ja", "en"]) {
  const t = PT[lang];
  page({ lang, path: lang === "ja" ? "/press" : "/en/press", title: t.title, desc: t.desc, body: pressBody(lang, pressZipHref, pressZip.length), cls: "press", css: PRESS_CSS, image: "/assets/press/art/velsia-keyart.jpg" });
}
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
const urls = ["/", "/en", "/support", "/en/support", "/press", "/en/press", ...LEGAL_PAGES.map((x) => x[1])];
fs.writeFileSync(path.join(OUT, "sitemap.xml"), `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls.map((u) => `<url><loc>${cfg.baseURL}${u === "/" ? "" : u}</loc></url>`).join("\n")}\n</urlset>\n`);
console.log(`built ${urls.length} pages → public/`);
