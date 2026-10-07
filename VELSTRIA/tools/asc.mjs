#!/usr/bin/env node
// App Store Connect API の小さなクライアント（依存なし。Node 標準 crypto で ES256 の JWT を作る）。
// TestFlight 内部テストの配信と、App Store の審査提出（production ブランチ）を自動化する。
//
// 環境変数:
//   ASC_KEY_ID      API キーの Key ID（10 桁）
//   ASC_ISSUER_ID   Issuer ID（UUID）
//   ASC_KEY_PATH    .p8 の場所（省略時 ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8）
//   ASC_BUNDLE_ID   既定 com.bitcoinpay.velstria
//   ASC_INTERNAL_GROUP_ID  verify-internal で確認する既存の内部テストグループ ID
//   ASC_RELEASE_TYPE  submit 時の公開方法。AFTER_APPROVAL（既定: 承認されたら自動で公開）/ MANUAL（承認後に手動で公開）
//   RELEASE_CHECK_ALLOW  release-check の検査 ID をカンマ区切りで指定すると、その検査のエラーを警告に格下げして続行する
//                     （誤判定で正しい提出が止まるときの逃げ道と、iap-attach の「Web で確認した」申告。CI ではリポジトリの
//                     Variables に設定する）
//
// usage:
//   node tools/asc.mjs create-app [name] [sku]         アプリレコードの作成を試す（Apple が API での作成を許可している場合のみ成功）
//   node tools/asc.mjs status                         アプリとビルドの一覧
//   node tools/asc.mjs wait-build <build>             ビルドの処理完了（VALID）を待つ
//   node tools/asc.mjs verify-internal <build>        既存の内部グループ（ASC_INTERNAL_GROUP_ID）にビルドが届いたか確認する（読み取りだけ）
//   node tools/asc.mjs internal <email> [<email>...]  内部テストグループを用意し、テスターを追加（ASC ユーザであること）
//   node tools/asc.mjs testers                        ベータグループとテスターの一覧
//   node tools/asc.mjs beta-notes <build> <text>      TestFlight の「テスト内容」を設定（ブランチ・コミットの表示用）
//   node tools/asc.mjs release-check <version> [--allow=<ID>,...]
//                                                     App Store に <version> を出せるか確認する（読み取りだけ。GET 以外は送らない）。
//                                                     公開済みの番号なら即終了（MARKETING_VERSION を上げる）。続けて submit が使う
//                                                     バージョン・App 情報について、提出・公開の前に必要な Web の設定をまとめて
//                                                     確認し、1 つでも欠けていれば終了コード 1。検査 ID（--allow / RELEASE_CHECK_ALLOW で格下げ可）:
//                                                       screenshots    主言語の iPhone スクリーンショット（6.9 か 6.5 インチ）が無い
//                                                       iap            iap_products.json の課金が未登録・種別違い・提出できない状態
//                                                                      （FeatureFlags.inAppPurchases = true のとき）
//                                                       iap-attach     未承認の課金がある。バージョンへの追加は API で確認できないため、
//                                                                      Web で追加を確かめたらこの ID を許可して続行する（全件承認後は出ない）
//                                                       age-rating     年齢制限の質問票が未回答
//                                                       price          価格が未設定（無料でも明示が必要）
//                                                       availability   配信する国と地域が未設定（Apple の提出検査では止まらないが、
//                                                                      docs/APPSTORE.md §4 の配信方針どおりに明示させる）
//                                                       release-notes  2 回目以降なのに release_notes.txt が無い言語がある
//                                                       urls           （validate_appstore_metadata.py --check-urls 用。ここでは使わない）
//                                                     警告だけ出す項目: コンテンツの権利が未回答（submit が「第三者のコンテンツなし」で
//                                                     自動申告する）、初回リリースのみ API で確認できない App のプライバシーと
//                                                     Mac / Vision Pro での配信。GitHub Actions では警告・エラーを注釈と手順のまとめにも出す
//   node tools/asc.mjs submit <build> [--dry-run]     ビルドを App Store バージョンに紐付け、メタデータ（docs/appstore/metadata）を
//                                                     同期して審査に提出する。--dry-run は読み取りだけで、行う変更を表示する
//   node tools/asc.mjs sync-listing [--dry-run]       編集中の下書きに名前・サブタイトル・説明・プロモーションテキスト・キーワードだけを
//                                                     書く（docs/appstore/metadata。URL は送らない。審査には出さない）
//   node tools/asc.mjs upload-screenshots <dir> [--display-type=APP_IPHONE_67] [--replace] [--dry-run]
//                                                     <dir>/<ja|en>/NN_name.png を編集中のバージョンの該当言語・枠へ登録する
//                                                     （審査には出さない。既存の画像を入れ直すときは --replace）
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const KEY_ID = process.env.ASC_KEY_ID;
const ISSUER = process.env.ASC_ISSUER_ID;
const BUNDLE_ID = process.env.ASC_BUNDLE_ID || "com.bitcoinpay.velstria";
const KEY_PATH = process.env.ASC_KEY_PATH
  || path.join(os.homedir(), ".appstoreconnect", "private_keys", `AuthKey_${KEY_ID}.p8`);
const API = "https://api.appstoreconnect.apple.com";
const INTERNAL_GROUP_NAME = "VELSTRIA Internal";

function fail(msg) {
  console.error(`error: ${msg}`);
  process.exit(1);
}

if (!KEY_ID || !ISSUER) fail("ASC_KEY_ID と ASC_ISSUER_ID を設定してください");
if (!fs.existsSync(KEY_PATH)) fail(`API キーがありません: ${KEY_PATH}`);
const privateKey = crypto.createPrivateKey(fs.readFileSync(KEY_PATH));

function b64url(buf) {
  return Buffer.from(buf).toString("base64").replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function token() {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "ES256", kid: KEY_ID, typ: "JWT" }));
  const payload = b64url(JSON.stringify({ iss: ISSUER, iat: now, exp: now + 15 * 60, aud: "appstoreconnect-v1" }));
  const sig = crypto.sign("sha256", Buffer.from(`${header}.${payload}`), { key: privateKey, dsaEncoding: "ieee-p1363" });
  return `${header}.${payload}.${b64url(sig)}`;
}

// 読み取り専用の実行（release-check）。GET 以外を送ろうとしたら送信前に止める
let readOnly = false;

async function call(method, url, body) {
  if (readOnly && method !== "GET") throw new Error(`読み取り専用の実行で ${method} ${url} を送ろうとしました`);
  // 一時的な通信エラー（接続タイムアウト等）は最大 5 回まで待って再試行する
  let res;
  for (let attempt = 1; ; attempt++) {
    try {
      res = await fetch(url.startsWith("http") ? url : API + url, {
        method,
        headers: { Authorization: `Bearer ${token()}`, "Content-Type": "application/json" },
        body: body ? JSON.stringify(body) : undefined,
      });
      if (res.status >= 500 && attempt < 5) throw new Error(`HTTP ${res.status}`);
      break;
    } catch (e) {
      if (attempt >= 5) throw e;
      console.error(`  通信エラーのため再試行（${attempt}/5）: ${e.cause?.code || e.message}`);
      await new Promise((r) => setTimeout(r, 5000 * attempt));
    }
  }
  const text = await res.text();
  const json = text ? JSON.parse(text) : {};
  if (!res.ok) {
    const detail = (json.errors || []).map((e) => {
      const assoc = Object.values(e.meta?.associatedErrors || {}).flat()
        .map((a) => `\n    - ${a.code}: ${a.detail || a.title}`).join("");
      return `${e.status} ${e.code}: ${e.title} — ${e.detail}${assoc}`;
    }).join("\n  ");
    const err = new Error(`${method} ${url} → ${res.status}\n  ${detail}`);
    err.status = res.status;
    err.json = json;
    throw err;
  }
  return json;
}

// 未設定の項目は 404 で返る（価格・配信状況など）。404 だけ null にして、それ以外のエラーはそのまま投げる
async function getOrNull(url) {
  try {
    return await call("GET", url);
  } catch (e) {
    if (e.status === 404) return null;
    throw e;
  }
}

// 一覧を links.next をたどってすべて取得する
async function getAll(url) {
  const data = [];
  for (let next = url; next;) {
    const r = await call("GET", next);
    data.push(...r.data);
    next = r.links?.next;
  }
  return data;
}

// 既存の内部グループにビルドが届いたことを確認する。グループの作成・招待・設定変更はしない
async function verifyInternal(appID, version) {
  readOnly = true;
  const groupID = process.env.ASC_INTERNAL_GROUP_ID || fail("ASC_INTERNAL_GROUP_ID を設定してください");
  const groups = await getAll(`/v1/apps/${appID}/betaGroups?limit=200`
    + "&fields[betaGroups]=name,isInternalGroup,hasAccessToAllBuilds");
  const group = groups.find((item) => item.id === groupID);
  if (!group) fail(`指定された内部グループがこのアプリにありません: ${groupID}`);
  if (group.attributes.isInternalGroup !== true) fail("指定されたグループは内部テストグループではありません");
  if (group.attributes.hasAccessToAllBuilds !== true) fail("内部グループの全ビルド自動配信が無効です");
  const groupPath = `/v1/betaGroups/${encodeURIComponent(groupID)}`;
  const testers = await getAll(`${groupPath}/betaTesters?limit=200&fields[betaTesters]=state`);
  if (!testers.length) fail("内部グループにテスターがいません");

  // Apple の処理完了直後はグループへの反映に時間差があるため、最大 3 分待つ
  for (let attempt = 0; attempt <= 12; attempt++) {
    const available = await getAll(`${groupPath}/builds?limit=200&fields[builds]=version,processingState,expired`);
    const build = available.find((item) => item.attributes.version === version);
    const state = build?.attributes.processingState || "NOT_FOUND";
    if (build && build.attributes.expired !== false) fail(`ビルド ${version} が有効期限内であることを確認できません`);
    if (state === "FAILED" || state === "INVALID") fail(`ビルド ${version} の処理が失敗しました（${state}）`);
    if (state === "VALID") {
      console.log(`内部配信を確認: ${group.attributes.name} / build ${version} / テスター ${testers.length} 人`);
      return;
    }
    console.log(`  内部配信 build ${version}: ${state}（${attempt + 1}/13）`);
    if (attempt < 12) await new Promise((resolve) => setTimeout(resolve, 15_000));
  }
  fail(`3 分待ってもビルド ${version} の内部グループへの配信を確認できません`);
}

async function findApp() {
  const r = await call("GET", `/v1/apps?filter[bundleId]=${encodeURIComponent(BUNDLE_ID)}&fields[apps]=name,bundleId,sku`);
  if (!r.data.length) {
    fail(`App Store Connect に ${BUNDLE_ID} のアプリレコードがありません（「アプリ」→「＋」→「新規アプリ」で作成）`);
  }
  return r.data[0];
}

async function builds(appID) {
  const r = await call("GET", `/v1/builds?filter[app]=${appID}&sort=-uploadedDate&limit=20`
    + "&fields[builds]=version,processingState,uploadedDate,expired,usesNonExemptEncryption");
  return r.data;
}

async function internalGroup(appID) {
  const r = await call("GET", `/v1/apps/${appID}/betaGroups?limit=50`);
  let g = r.data.find((x) => x.attributes.isInternalGroup);
  if (!g) {
    const created = await call("POST", "/v1/betaGroups", {
      data: {
        type: "betaGroups",
        attributes: { name: INTERNAL_GROUP_NAME, isInternalGroup: true, hasAccessToAllBuilds: true },
        relationships: { app: { data: { type: "apps", id: appID } } },
      },
    });
    g = created.data;
    console.log(`内部テストグループを作成: ${g.attributes.name}（全ビルドを自動配信）`);
  }
  return g;
}

async function addTester(group, email) {
  const found = await call("GET", `/v1/betaTesters?filter[email]=${encodeURIComponent(email)}&limit=1`);
  if (found.data.length) {
    await call("POST", `/v1/betaGroups/${group.id}/relationships/betaTesters`, {
      data: [{ type: "betaTesters", id: found.data[0].id }],
    });
    console.log(`追加: ${email}（既存テスター）→ ${group.attributes.name}`);
    return;
  }
  await call("POST", "/v1/betaTesters", {
    data: {
      type: "betaTesters",
      attributes: { email },
      relationships: { betaGroups: { data: [{ type: "betaGroups", id: group.id }] } },
    },
  });
  console.log(`追加: ${email} → ${group.attributes.name}（TestFlight の招待メールが届きます）`);
}

async function ensureBuildInGroup(group, build) {
  if (group.attributes.hasAccessToAllBuilds) return;
  await call("POST", `/v1/betaGroups/${group.id}/relationships/builds`, {
    data: [{ type: "builds", id: build.id }],
  });
  console.log(`ビルド ${build.attributes.version} をグループに追加`);
}

// ---- App Store 提出（production） ----

const APP_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const META_DIR = path.join(APP_ROOT, "docs", "appstore", "metadata");
// appVersionState（新）と appStoreState（旧）の両方の値を扱う
const EDITABLE = new Set(["PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED",
  "INVALID_BINARY", "READY_FOR_REVIEW"]);
const UNDER_REVIEW = new Set(["WAITING_FOR_REVIEW", "IN_REVIEW", "WAITING_FOR_EXPORT_COMPLIANCE"]);
// 承認済み・公開中・公開済み（このバージョン番号ではもう提出できない）
const SHIPPED = new Set(["ACCEPTED", "PENDING_APPLE_RELEASE", "PENDING_DEVELOPER_RELEASE", "PROCESSING_FOR_DISTRIBUTION",
  "PROCESSING_FOR_APP_STORE", "READY_FOR_DISTRIBUTION", "READY_FOR_SALE", "PREORDER_READY_FOR_SALE",
  "REPLACED_WITH_NEW_VERSION", "REMOVED_FROM_SALE", "DEVELOPER_REMOVED_FROM_SALE"]);
// appInfo の状態（appStoreVersion とは別の列挙。REPLACED_WITH_NEW_INFO などの履歴も一覧に残る）
const EDITABLE_INFO = new Set(["PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "READY_FOR_REVIEW"]);
const LIVE_ONCE = new Set(["READY_FOR_DISTRIBUTION", "READY_FOR_SALE", "REPLACED_WITH_NEW_VERSION",
  "REMOVED_FROM_SALE", "DEVELOPER_REMOVED_FROM_SALE"]);

const versionState = (v) => v.attributes.appVersionState || v.attributes.appStoreState;
// 一度でも公開されたバージョンが無ければ初回リリース（「このバージョンの新機能」は入力できない）
const isFirstRelease = (versions) => !versions.some((v) => LIVE_ONCE.has(versionState(v)));
const infoState = (x) => x.attributes.state || x.attributes.appStoreState;
// "1.0" と "1.0.0" は同じバージョンとして扱う（末尾の .0 を落として比較）
const normVersion = (s) => String(s).split(".").map(Number).join(".").replace(/(\.0)+$/, "");
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function findBuild(appID, version) {
  const r = await call("GET", `/v1/builds?filter[app]=${appID}&filter[version]=${encodeURIComponent(version)}&limit=1`
    + "&fields[builds]=version,processingState,uploadedDate,expired,usesNonExemptEncryption");
  if (!r.data.length) fail(`ビルド ${version} が App Store Connect にありません`);
  return r.data[0];
}

async function iosVersions(appID) {
  const r = await call("GET", `/v1/apps/${appID}/appStoreVersions?filter[platform]=IOS&limit=50`
    + "&fields[appStoreVersions]=versionString,appVersionState,appStoreState,releaseType,createdDate");
  return r.data;
}

async function appInfos(appID) {
  return (await call("GET", `/v1/apps/${appID}/appInfos?limit=200&fields[appInfos]=state,appStoreState,appStoreAgeRating`)).data;
}

// submit が名前・カテゴリを書き込む App 情報（公開中でないもの）。release-check も同じものを確認する
function editableAppInfo(infos) {
  return infos.find((x) => infoState(x) === "PREPARE_FOR_SUBMISSION")
    || infos.find((x) => EDITABLE_INFO.has(infoState(x)));
}

function readMeta(rel) {
  const p = path.join(META_DIR, rel);
  if (!fs.existsSync(p)) return undefined;
  const text = fs.readFileSync(p, "utf8").trim();
  return text === "" ? undefined : text;
}

function loadMetadata() {
  const locales = fs.readdirSync(META_DIR, { withFileTypes: true })
    .filter((d) => d.isDirectory() && d.name !== "review_information").map((d) => d.name).sort();
  const meta = {
    copyright: readMeta("copyright.txt"),
    categories: {
      primaryCategory: readMeta("primary_category.txt"),
      primarySubcategoryOne: readMeta("primary_first_sub_category.txt"),
      primarySubcategoryTwo: readMeta("primary_second_sub_category.txt"),
    },
    review: {
      contactFirstName: readMeta("review_information/first_name.txt"),
      contactLastName: readMeta("review_information/last_name.txt"),
      contactPhone: readMeta("review_information/phone_number.txt"),
      contactEmail: readMeta("review_information/email_address.txt"),
      notes: readMeta("review_information/notes.txt"),
      demoAccountRequired: false,
    },
    locales: {},
  };
  for (const loc of locales) {
    meta.locales[loc] = {
      version: {
        description: readMeta(`${loc}/description.txt`),
        keywords: readMeta(`${loc}/keywords.txt`),
        promotionalText: readMeta(`${loc}/promotional_text.txt`),
        marketingUrl: readMeta(`${loc}/marketing_url.txt`),
        supportUrl: readMeta(`${loc}/support_url.txt`),
        whatsNew: readMeta(`${loc}/release_notes.txt`),
      },
      info: {
        name: readMeta(`${loc}/name.txt`),
        subtitle: readMeta(`${loc}/subtitle.txt`),
        privacyPolicyUrl: readMeta(`${loc}/privacy_url.txt`),
      },
    };
  }
  // 最後の防波堤: 仮値が残ったまま審査に出さない（通常は validate_appstore_metadata.py --release で先に止まる）
  const leftovers = [];
  (function walk(o, where) {
    for (const [k, v] of Object.entries(o)) {
      if (v && typeof v === "object") walk(v, `${where}${k}.`);
      else if (typeof v === "string" && (/\{\{[A-Z_]+\}\}/.test(v) || v.includes("velstria.example"))) leftovers.push(where + k);
    }
  })(meta, "");
  return { meta, leftovers };
}

// 値が undefined の項目は送らない（ASC 側の既存値を消さない）
const defined = (o) => Object.fromEntries(Object.entries(o).filter(([, v]) => v !== undefined));

async function activeSubmissions(appID, states) {
  const r = await call("GET", `/v1/reviewSubmissions?filter[app]=${appID}&filter[platform]=IOS`
    + `&filter[state]=${states.join(",")}&limit=20`);
  return r.data;
}

async function submissionHasVersion(submissionID, versionID) {
  const r = await call("GET", `/v1/reviewSubmissions/${submissionID}/items?include=appStoreVersion&limit=50`);
  return r.data.some((it) => it.relationships?.appStoreVersion?.data?.id === versionID);
}

// 提出を取り下げ、取り下げが完了（COMPLETE）するまで待つ。CANCELING の間は新しい提出を作れない
async function cancelSubmissions(subs, reason, dry) {
  for (const s of subs) {
    console.log(`${dry ? "[dry-run] " : ""}${reason}: 提出 ${s.id}（${s.attributes.state}）を取り下げる（新しいビルドで出し直すため）`);
    if (dry) continue;
    await call("PATCH", `/v1/reviewSubmissions/${s.id}`,
      { data: { type: "reviewSubmissions", id: s.id, attributes: { canceled: true } } });
    for (let i = 0; ; i++) {
      const st = (await call("GET", `/v1/reviewSubmissions/${s.id}?fields[reviewSubmissions]=state`)).data.attributes.state;
      if (st === "COMPLETE") break;
      if (i >= 40) fail(`提出 ${s.id} の取り下げが 10 分で完了しません（${st}）。App Store Connect で状態を確認してください`);
      console.log(`  取り下げ待ち: ${st}`);
      await sleep(15_000);
    }
  }
}

// 審査待ち・審査中の提出を取り下げ、バージョンが編集可能になるまで待つ（production の新しい push を優先する）
async function cancelUnderReview(appID, versionID, dry) {
  const subs = await activeSubmissions(appID, ["WAITING_FOR_REVIEW", "IN_REVIEW", "UNRESOLVED_ISSUES"]);
  await cancelSubmissions(subs, "審査中", dry);
  if (dry) return;
  for (let i = 0; i < 40; i++) {
    const v = (await iosVersions(appID)).find((x) => x.id === versionID);
    const st = v ? versionState(v) : "NOT_FOUND";
    if (EDITABLE.has(st)) return;
    console.log(`  取り下げ待ち: ${st}`);
    await sleep(15_000);
  }
  fail("審査の取り下げが 10 分で完了しませんでした。App Store Connect で状態を確認してください");
}

async function releaseCheck(appID, marketing) {
  const versions = await iosVersions(appID);
  const shipped = versions.find((v) => normVersion(v.attributes.versionString) === normVersion(marketing)
    && SHIPPED.has(versionState(v)));
  if (shipped) {
    fail(`バージョン ${shipped.attributes.versionString} は App Store で承認済み・公開済みです（${versionState(shipped)}）。\n`
      + "  VELSTRIA/project.yml の MARKETING_VERSION を上げ（例 1.0.1）、"
      + "docs/appstore/metadata/<言語>/release_notes.txt（このバージョンの新機能）を用意してから production に push してください");
  }
  const open = versions.find((v) => EDITABLE.has(versionState(v)) || UNDER_REVIEW.has(versionState(v)));
  return { versions, open };
}

// ---- 提出前チェック（release-check。submit や審査で初めて気づく Web 側の不足と、docs/APPSTORE.md の方針に反する未設定を、
//      ビルド前に GET だけで挙げる） ----

const IAP_JSON = path.join(APP_ROOT, "docs", "appstore", "iap_products.json");
const FEATURE_FLAGS = path.join(APP_ROOT, "App", "Core", "FeatureFlags.swift");
// 検査 ID → 内容（ファイル先頭の usage と一致させる）。RELEASE_CHECK_ALLOW / --allow で ID ごとにエラーを警告へ格下げできる
const RELEASE_CHECKS = {
  screenshots: "主言語の iPhone スクリーンショット",
  iap: "App 内課金の登録と状態",
  "iap-attach": "未承認の App 内課金のバージョンへの追加（API で確認できないため Web で確かめて許可する）",
  "age-rating": "年齢制限の質問票",
  price: "価格",
  availability: "配信する国と地域",
  "release-notes": "このバージョンの新機能（release_notes.txt）",
  urls: "公開 URL の到達確認（validate_appstore_metadata.py --check-urls）",
};
// 提出に必須の iPhone の枠: 6.9 / 6.7 インチ（API の値は APP_IPHONE_67）か 6.5 インチ（APP_IPHONE_65）のどちらか
const REQUIRED_IPHONE_SHOTS = ["APP_IPHONE_67", "APP_IPHONE_65"];
// アップロード済み（COMPLETE = 処理済み、UPLOAD_COMPLETE = 処理中）。AWAITING_UPLOAD・FAILED は数えない
const SHOT_UPLOADED = new Set(["COMPLETE", "UPLOAD_COMPLETE"]);
// App 内課金のうち審査に出せる・審査中・承認済みの状態。これ以外は Web で直すまで提出できない
const IAP_SUBMITTABLE = new Set(["READY_TO_SUBMIT", "WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_BINARY_APPROVAL", "APPROVED"]);
const IAP_STATE_HINT = {
  MISSING_METADATA: "表示名・説明・価格・配信地域・審査用スクリーンショットのどれかが未入力",
  WAITING_FOR_UPLOAD: "ホストするコンテンツのアップロード待ち",
  PROCESSING_CONTENT: "ホストするコンテンツの処理中",
  DEVELOPER_ACTION_NEEDED: "審査で修正を求められている",
  REJECTED: "却下されている",
  REMOVED_FROM_SALE: "販売停止中",
  DEVELOPER_REMOVED_FROM_SALE: "販売停止中",
};
const IAP_TYPE = { consumable: "CONSUMABLE", non_consumable: "NON_CONSUMABLE" };
// 年齢制限の質問票で回答が必須の項目（回答済みのアプリでも null のまま残る kidsAgeBand・socialMedia・
// socialMediaAgeRestricted・gracRatingClassificationNumber・developerAgeRatingInfoUrl と、既定値のある *Override は含めない）
const AGE_RATING_REQUIRED = ["advertising", "alcoholTobaccoOrDrugUseOrReferences", "contests", "gambling",
  "gamblingSimulated", "gunsOrOtherWeapons", "healthOrWellnessTopics", "lootBox", "medicalOrTreatmentInformation",
  "messagingAndChat", "parentalControls", "profanityOrCrudeHumor", "ageAssurance", "sexualContentGraphicAndNudity",
  "sexualContentOrNudity", "horrorOrFearThemes", "matureOrSuggestiveThemes", "unrestrictedWebAccess",
  "userGeneratedContent", "violenceCartoonOrFantasy", "violenceRealisticProlongedGraphicOrSadistic", "violenceRealistic"];
const EXPECTED_AGE_RATING = "NINE_PLUS"; // docs/appstore/age_rating.md

// ローカライズの iPhone / iPad などの枠ごとの枚数 { APP_IPHONE_67: { uploaded, other } }
async function screenshotCounts(localizationID) {
  const r = await call("GET", `/v1/appStoreVersionLocalizations/${localizationID}/appScreenshotSets?limit=50`
    + "&include=appScreenshots&limit[appScreenshots]=50"
    + "&fields[appScreenshotSets]=screenshotDisplayType,appScreenshots&fields[appScreenshots]=assetDeliveryState");
  const state = new Map((r.included || []).filter((x) => x.type === "appScreenshots")
    .map((x) => [x.id, x.attributes.assetDeliveryState?.state]));
  const out = {};
  for (const set of r.data) {
    const ids = (set.relationships?.appScreenshots?.data || []).map((x) => x.id);
    const uploaded = ids.filter((id) => SHOT_UPLOADED.has(state.get(id))).length;
    out[set.attributes.screenshotDisplayType] = { uploaded, other: ids.length - uploaded };
  }
  return out;
}

// すべての検査を行い、問題をまとめて返す（途中で止めない）。errors は { id, msg }
async function preSubmitChecks(appID, versions, open) {
  const errors = [];
  const warnings = [];
  const passed = [];
  const error = (id, msg) => errors.push({ id, msg });
  const warn = (msg) => warnings.push(msg);
  const ok = (msg) => passed.push(msg);
  // API が想定外のエラーを返した検査もその ID のエラーにする（他の検査は続ける。誤判定と同じく格下げできる）
  const check = async (id, fn) => {
    try {
      await fn();
    } catch (e) {
      error(id, `確認できませんでした: ${e.message}`);
    }
  };
  const { meta } = loadMetadata();
  const firstRelease = isFirstRelease(versions);
  const appAttrs = (await call("GET", `/v1/apps/${appID}?fields[apps]=primaryLocale,contentRightsDeclaration`)).data.attributes;
  const primary = appAttrs.primaryLocale;

  // スクリーンショット（submit が紐付けるバージョン = releaseCheck の open）
  await check("screenshots", async () => {
    if (!open) {
      warn("提出時に App Store バージョンを新しく作るため、スクリーンショットは確認できません（前のバージョンから引き継がれる）");
      return;
    }
    const locs = (await call("GET", `/v1/appStoreVersions/${open.id}/appStoreVersionLocalizations?limit=50`
      + "&fields[appStoreVersionLocalizations]=locale")).data;
    const locales = [primary, ...Object.keys(meta.locales).filter((l) => l !== primary)];
    for (const locale of locales) {
      const loc = locs.find((x) => x.attributes.locale === locale);
      const counts = loc ? await screenshotCounts(loc.id) : {};
      const have = Object.entries(counts)
        .map(([type, c]) => `${type} ${c.uploaded} 枚${c.other ? `（未完了・失敗 ${c.other} 枚）` : ""}`).join(", ") || "なし";
      if (REQUIRED_IPHONE_SHOTS.some((type) => counts[type]?.uploaded > 0)) {
        ok(`スクリーンショット ${locale}: ${have}`);
        continue;
      }
      const msg = `${locale} の iPhone スクリーンショット（6.9 インチ = APP_IPHONE_67 か 6.5 インチ = APP_IPHONE_65）がありません`
        + `（登録済み: ${have}${loc ? "" : "。この言語のバージョン情報が未作成で、submit が作成する"}）`;
      if (locale === primary) {
        error("screenshots", `主言語 ${msg}。docs/appstore/screenshots.md の手順で撮影し、Web でバージョン ${open.attributes.versionString} に登録してください`);
      } else {
        warn(`${msg}。この言語の製品ページには主言語（${primary}）の画像が使われます`);
      }
    }
  });

  // App 内課金（FeatureFlags.inAppPurchases が有効なら iap_products.json の全商品が登録済みで提出できる状態であること）
  await check("iap", async () => {
    const flag = /\bstatic\s+let\s+inAppPurchases\s*=\s*(true|false)\b/.exec(fs.readFileSync(FEATURE_FLAGS, "utf8"));
    if (!flag) warn("App/Core/FeatureFlags.swift に inAppPurchases が見つかりません（有効として確認します）");
    if (flag?.[1] === "false") {
      ok("App 内課金: FeatureFlags.inAppPurchases = false のため確認しない");
      return;
    }
    const products = JSON.parse(fs.readFileSync(IAP_JSON, "utf8")).products;
    const registered = await getAll(`/v1/apps/${appID}/inAppPurchasesV2?limit=200`
      + "&fields[inAppPurchases]=productId,inAppPurchaseType,state");
    const byID = new Map(registered.map((x) => [x.attributes.productId, x.attributes]));
    const missing = products.filter((p) => !byID.has(p.product_id)).map((p) => p.product_id);
    if (missing.length) {
      error("iap", `App Store Connect に未登録の App 内課金があります（登録 ${products.length - missing.length} / `
        + `iap_products.json ${products.length} 件）: ${missing.join(", ")}。docs/appstore/in_app_purchases.md の内容で Web から登録してください`);
    }
    for (const p of products) {
      const a = byID.get(p.product_id);
      if (!a) continue;
      if (a.inAppPurchaseType !== IAP_TYPE[p.type]) {
        error("iap", `${p.product_id}: 種別が ${a.inAppPurchaseType} です（iap_products.json は ${IAP_TYPE[p.type] || p.type}）`);
      }
      if (!IAP_SUBMITTABLE.has(a.state)) {
        error("iap", `${p.product_id}: 状態が ${a.state} のため審査に出せません（${IAP_STATE_HINT[a.state] || "Web で確認"}）`);
      }
    }
    // 未承認の課金をバージョンに追加したかは API で追加も確認もできない。追加し忘れても submit は App だけを提出して成功し、
    // ガイドライン 2.1 で却下される。警告だとログに埋もれるため、Web で確かめたことを RELEASE_CHECK_ALLOW=iap-attach で申告させる
    const notApproved = products.filter((p) => byID.get(p.product_id)?.state !== "APPROVED").map((p) => p.product_id);
    if (notApproved.length) {
      error("iap-attach", `App 内課金 ${notApproved.length} 件がまだ承認されていません（${notApproved.join(", ")}）。`
        + "初めて審査に出す App 内課金は、Web のバージョンページ「App 内課金とサブスクリプション」でこのバージョンに追加してください"
        + "（API では追加も確認もできず、追加し忘れると App だけが提出されてガイドライン 2.1 で却下される）。"
        + "追加を確かめたら RELEASE_CHECK_ALLOW に iap-attach を入れて再実行してください（すべて承認されたら外す）");
    } else {
      ok(`App 内課金: ${products.length} 件すべて承認済み`);
    }
  });

  // 年齢制限（submit が書き込むのと同じ App 情報。無ければ公開中のもの）
  await check("age-rating", async () => {
    const infos = await appInfos(appID);
    const info = editableAppInfo(infos) || infos[0];
    if (!info) {
      error("age-rating", "App 情報がありません");
      return;
    }
    const decl = (await call("GET", `/v1/appInfos/${info.id}/ageRatingDeclaration`)).data.attributes;
    const unanswered = AGE_RATING_REQUIRED.filter((k) => decl[k] == null);
    const rating = info.attributes.appStoreAgeRating;
    if (unanswered.length) {
      error("age-rating", `年齢制限の質問票が未回答です（${unanswered.length} 項目: ${unanswered.join(", ")}）。`
        + "docs/appstore/age_rating.md の回答を Web の「App 情報 > 年齢制限」で入力してください");
    } else if (rating && rating !== EXPECTED_AGE_RATING) {
      warn(`年齢制限が ${rating} です（docs/appstore/age_rating.md の想定は 9+ = ${EXPECTED_AGE_RATING}）。回答を確認してください`);
    } else {
      ok(`年齢制限: ${rating || "回答済み"}`);
    }
  });

  // 価格（未設定だと価格スケジュールの manualPrices が 404 になる。無料も「無料」を選んで保存しないと未設定のまま）
  await check("price", async () => {
    const schedule = await getOrNull(`/v1/apps/${appID}/appPriceSchedule`);
    const prices = schedule && await getOrNull(`/v1/appPriceSchedules/${schedule.data.id}/manualPrices?limit=50`
      + "&include=appPricePoint,territory");
    if (!prices?.data.length) {
      error("price", "価格が未設定です。無料でも Web の「価格および配信状況」で価格（無料）を設定してください（docs/APPSTORE.md §4）");
      return;
    }
    const today = new Date().toISOString().slice(0, 10);
    const current = prices.data.find((x) => (!x.attributes.startDate || x.attributes.startDate <= today)
      && (!x.attributes.endDate || x.attributes.endDate > today)) || prices.data[0];
    const pointID = current.relationships?.appPricePoint?.data?.id;
    const price = (prices.included || []).find((x) => x.type === "appPricePoints" && x.id === pointID)?.attributes.customerPrice;
    const territory = current.relationships?.territory?.data?.id || "?";
    if (price != null && Number(price) !== 0) {
      warn(`価格が無料ではありません（${territory} ${price}）。docs/APPSTORE.md §4 は無料（App 内課金あり）`);
    } else {
      ok(`価格: ${price != null ? "無料" : "設定済み"}（基準 ${territory}）`);
    }
  });

  // 配信する国と地域（未設定だと appAvailabilityV2 が 404）。Apple の提出検査ではこれで止まらない（同じアカウントの別アプリは
  // 404 のまま審査に提出できた）。それでも未設定のまま承認されると、中国本土を含むのか・どこにも配信されないのかが決まらず
  // docs/APPSTORE.md §4（中国本土は除外・日本で配信）に反するため、明示的な設定を必須にしている
  await check("availability", async () => {
    const availability = await getOrNull(`/v1/apps/${appID}/appAvailabilityV2`);
    if (!availability) {
      error("availability", "配信する国と地域が未設定です。提出はできてしまうが配信先が方針どおりにならないため、"
        + "Web の「価格および配信状況」で設定してください（docs/APPSTORE.md §4: 中国本土は除外・日本で配信）");
      return;
    }
    const territories = await getAll(`/v2/appAvailabilities/${availability.data.id}/territoryAvailabilities?limit=200`
      + "&include=territory&fields[territoryAvailabilities]=available,territory");
    const on = territories.filter((x) => x.attributes.available).map((x) => x.relationships?.territory?.data?.id);
    if (!on.length) {
      error("availability", "配信する国と地域が 1 つも選ばれていません（docs/APPSTORE.md §4）");
      return;
    }
    if (!on.includes("JPN")) warn("日本（JPN）で配信しない設定です（docs/APPSTORE.md §4）");
    if (on.includes("CHN")) warn("中国本土（CHN）で配信する設定です。ゲームは版号が必要なため除外する方針です（docs/APPSTORE.md §4）");
    ok(`配信: ${on.length} の国と地域`);
  });

  // このバージョンの新機能（submit と同じ判定。2 回目以降は全言語に必要）
  await check("release-notes", async () => {
    if (firstRelease) {
      ok("このバージョンの新機能: 初回リリースのため不要");
      return;
    }
    const lacking = Object.entries(meta.locales).filter(([, m]) => !m.version.whatsNew).map(([loc]) => loc);
    for (const loc of lacking) {
      error("release-notes", `2 回目以降のリリースには docs/appstore/metadata/${loc}/release_notes.txt（このバージョンの新機能）が必要です`);
    }
    if (!lacking.length) ok(`このバージョンの新機能: ${Object.keys(meta.locales).join(", ")}`);
  });

  // API で確認できない項目（警告のみ）
  if (!appAttrs.contentRightsDeclaration) {
    warn("コンテンツの権利が未回答です。submit が自動で DOES_NOT_USE_THIRD_PARTY_CONTENT（第三者のコンテンツを含まない）と申告します。"
      + "ヒーロー・スキンのポートレートなど生成 AI で作った画像を含むため、この申告でよいか docs/appstore/compliance.md で確認し、"
      + "違う場合は先に Web の「App 情報 > コンテンツの権利」で回答してください");
  } else {
    ok(`コンテンツの権利: ${appAttrs.contentRightsDeclaration}`);
  }
  if (firstRelease) {
    // 2 回目以降は前のバージョンの回答・設定が引き継がれる
    warn("App のプライバシー（栄養ラベル）は API で確認できません。Web で「データを収集しない」を公開済みか確認してください"
      + "（docs/appstore/app_privacy.md）");
    warn("Apple Silicon Mac / Apple Vision Pro での配信可否は API で確認できません。Web の「価格および配信状況」で"
      + "オフになっているか確認してください（docs/APPSTORE.md §4）");
  }
  return { errors, warnings, passed };
}

// GitHub Actions のワークフローコマンドの値（% と改行を符号化する）
const ghaEscape = (s) => String(s).replace(/%/g, "%25").replace(/\r/g, "%0D").replace(/\n/g, "%0A");

// GitHub Actions の手順のまとめ（Summary）に結果の一覧を書く。注釈は手順ごとに 10 件までしか出ないため、全件はここで見せる
function writeStepSummary(blocking, warnings, passed) {
  const file = process.env.GITHUB_STEP_SUMMARY;
  if (!file) return;
  const list = (items) => items.map((x) => `- ${x.replace(/\n/g, " ")}`).join("\n");
  const lines = [
    "### 提出前チェック（App Store Connect の設定）",
    blocking.length ? `**エラー ${blocking.length} 件**（Web で直して push し直す。誤判定・確認済みなら Variables の RELEASE_CHECK_ALLOW に検査 ID）`
      : `合格（警告 ${warnings.length} 件）`,
  ];
  if (blocking.length) lines.push("", "#### エラー", list(blocking.map((e) => `\`${e.id}\` ${e.msg}`)));
  if (warnings.length) lines.push("", "#### 警告（提出は続く。却下につながるものがないか確認する）", list(warnings));
  if (passed.length) lines.push("", "<details><summary>確認済み</summary>", "", list(passed), "", "</details>");
  fs.appendFileSync(file, `${lines.join("\n")}\n`);
}

// 検査結果を表示し、格下げされていないエラーがあれば終了コード 1。
// GitHub Actions ではログを開かなくても見えるよう、警告・エラーを注釈（::warning / ::error）と手順のまとめにも出す
function reportPreSubmit({ errors, warnings: plain, passed }, allowArgs) {
  const raw = [process.env.RELEASE_CHECK_ALLOW || "", ...allowArgs].join(",");
  const allow = new Set(raw.split(",").map((s) => s.trim()).filter(Boolean));
  // 許可で格下げしたエラーは、ほかの警告より先に出す（注釈は 10 件までなので、重要なものを落とさない）
  const warnings = errors.filter((x) => allow.has(x.id))
    .map((e) => `[${e.id}] ${e.msg}（RELEASE_CHECK_ALLOW / --allow で許可されているため続行）`);
  for (const id of allow) {
    if (!(id in RELEASE_CHECKS)) warnings.push(`RELEASE_CHECK_ALLOW の「${id}」は不明な検査 ID です（${Object.keys(RELEASE_CHECKS).join(", ")}）`);
  }
  warnings.push(...plain);
  const blocking = errors.filter((e) => !allow.has(e.id));
  const gha = process.env.GITHUB_ACTIONS === "true";
  for (const p of passed) console.log(`  ok: ${p}`);
  for (const w of warnings) {
    if (gha) console.log(`::warning title=提出前チェック::${ghaEscape(w)}`);
    else console.warn(`warning: ${w}`);
  }
  for (const e of blocking) {
    if (gha) console.log(`::error title=提出前チェック（${e.id}）::${ghaEscape(e.msg)}`);
    else console.error(`error[${e.id}]: ${e.msg}`);
  }
  writeStepSummary(blocking, warnings, passed);
  if (blocking.length) {
    const ids = [...new Set(blocking.map((e) => e.id))];
    fail(`提出前チェックで ${blocking.length} 件のエラー（${ids.join(", ")}）。App Store Connect の Web で設定してから production に push し直してください。\n`
      + `  判定が誤っていて提出できる状態（iap-attach は Web でバージョンへの追加を確かめた後）なら、リポジトリの Variables に`
      + ` RELEASE_CHECK_ALLOW=${ids.join(",")} を設定して再実行すると`
      + "警告として続行します（手元では --allow=<ID>,...）");
  }
  console.log(`ok: 提出前チェックに合格（警告 ${warnings.length} 件）`);
}

async function upsertLocalizations(kind, parent, existing, wanted, dry) {
  // kind: appStoreVersionLocalizations（親 appStoreVersion）/ appInfoLocalizations（親 appInfo）
  const parentType = kind === "appStoreVersionLocalizations" ? "appStoreVersions" : "appInfos";
  const parentRel = kind === "appStoreVersionLocalizations" ? "appStoreVersion" : "appInfo";
  for (const [locale, attrs] of Object.entries(wanted)) {
    const body = defined(attrs);
    if (!Object.keys(body).length) continue;
    const cur = existing.find((x) => x.attributes.locale === locale);
    if (cur) {
      const changed = Object.keys(body).filter((k) => (cur.attributes[k] ?? undefined) !== body[k]);
      if (!changed.length) continue;
      console.log(`${dry ? "[dry-run] " : ""}${kind} ${locale}: 更新 ${changed.join(", ")}`);
      if (!dry) {
        await call("PATCH", `/v1/${kind}/${cur.id}`, { data: { type: kind, id: cur.id, attributes: body } });
      }
    } else {
      console.log(`${dry ? "[dry-run] " : ""}${kind} ${locale}: 作成 ${Object.keys(body).join(", ")}`);
      if (!dry) {
        await call("POST", `/v1/${kind}`, {
          data: {
            type: kind,
            attributes: { locale, ...body },
            relationships: { [parentRel]: { data: { type: parentType, id: parent.id } } },
          },
        });
      }
    }
  }
}

async function submitBuild(appID, buildVersion, dry) {
  const tag = dry ? "[dry-run] " : "";
  const releaseType = process.env.ASC_RELEASE_TYPE || "AFTER_APPROVAL";
  if (!["AFTER_APPROVAL", "MANUAL"].includes(releaseType)) fail(`ASC_RELEASE_TYPE は AFTER_APPROVAL か MANUAL: ${releaseType}`);

  const { meta, leftovers } = loadMetadata();
  if (leftovers.length) {
    const msg = `docs/appstore/metadata に仮値が残っています: ${leftovers.join(", ")}`;
    if (dry) console.warn(`warning: ${msg}（--dry-run なので続行）`); else fail(msg);
  }

  const build = await findBuild(appID, buildVersion);
  if (build.attributes.processingState !== "VALID") fail(`ビルド ${buildVersion} は処理中または無効です（${build.attributes.processingState}）`);
  const pre = await call("GET", `/v1/builds/${build.id}/preReleaseVersion?fields[preReleaseVersions]=version`);
  const marketing = pre.data.attributes.version;
  console.log(`ビルド: ${marketing} (${buildVersion})`);

  // 1) 対象の App Store バージョン（編集中・審査中のもの。無ければ作る）
  let { versions, open: target } = await releaseCheck(appID, marketing);
  if (target && UNDER_REVIEW.has(versionState(target))) {
    await cancelUnderReview(appID, target.id, dry);
  } else if (target) {
    // 却下された提出（UNRESOLVED_ISSUES）が残っていると新しい提出を作れないため取り下げる
    await cancelSubmissions(await activeSubmissions(appID, ["UNRESOLVED_ISSUES"]), "却下された提出", dry);
  }
  if (!target) {
    console.log(`${tag}App Store バージョン ${marketing} を作成（${releaseType}）`);
    if (dry) {
      target = { id: "(new)", attributes: { versionString: marketing, releaseType } };
    } else {
      const r = await call("POST", "/v1/appStoreVersions", {
        data: {
          type: "appStoreVersions",
          attributes: { platform: "IOS", versionString: marketing, releaseType },
          relationships: { app: { data: { type: "apps", id: appID } } },
        },
      });
      target = r.data;
    }
  }
  const firstRelease = isFirstRelease(versions);

  // 2) バージョンの属性（番号はビルドに合わせる・公開方法・著作権）
  const vAttrs = defined({
    versionString: target.attributes.versionString !== marketing ? marketing : undefined,
    releaseType: target.attributes.releaseType !== releaseType ? releaseType : undefined,
    copyright: meta.copyright,
  });
  console.log(`${tag}バージョン ${target.attributes.versionString} → ${JSON.stringify(vAttrs)}`);
  if (!dry) {
    await call("PATCH", `/v1/appStoreVersions/${target.id}`,
      { data: { type: "appStoreVersions", id: target.id, attributes: vAttrs } });
  }

  // 3) ストア掲載文（バージョンごと）。「このバージョンの新機能」は初回リリースでは入力できない
  const versionLocs = {};
  for (const [loc, m] of Object.entries(meta.locales)) {
    const { whatsNew, ...rest } = m.version;
    if (!firstRelease && !whatsNew) {
      fail(`2 回目以降のリリースには docs/appstore/metadata/${loc}/release_notes.txt（このバージョンの新機能）が必要です`);
    }
    versionLocs[loc] = firstRelease ? rest : { ...rest, whatsNew };
  }
  const curVLocs = target.id === "(new)" ? [] : (await call("GET",
    `/v1/appStoreVersions/${target.id}/appStoreVersionLocalizations?limit=50`)).data;
  await upsertLocalizations("appStoreVersionLocalizations", target, curVLocs, versionLocs, dry);

  // 4) App 情報（名前・サブタイトル・プライバシーポリシー URL・カテゴリ）。公開中でない appInfo だけが編集できる
  const infos = await appInfos(appID);
  const info = editableAppInfo(infos);
  if (!info && !dry) {
    fail(`編集可能な App 情報がありません（${infos.map(infoState).join(", ")}）。名前・サブタイトル・プライバシーポリシー URL を同期できないため中止します`);
  }
  if (info) {
    const curILocs = (await call("GET", `/v1/appInfos/${info.id}/appInfoLocalizations?limit=50`)).data;
    const infoLocs = Object.fromEntries(Object.entries(meta.locales).map(([loc, m]) => [loc, m.info]));
    await upsertLocalizations("appInfoLocalizations", info, curILocs, infoLocs, dry);
    const rel = {};
    for (const [k, id] of Object.entries(meta.categories)) if (id) rel[k] = { data: { type: "appCategories", id } };
    if (Object.keys(rel).length) {
      console.log(`${tag}カテゴリ: ${Object.values(meta.categories).filter(Boolean).join(" / ")}`);
      if (!dry) await call("PATCH", `/v1/appInfos/${info.id}`, { data: { type: "appInfos", id: info.id, relationships: rel } });
    }
  } else {
    console.warn("warning: 編集可能な App 情報がありません（名前・サブタイトル・カテゴリは更新しません）");
  }

  // 5) コンテンツの権利（docs/appstore/compliance.md: 第三者のコンテンツを含まない）。未回答のときだけ設定する
  const appAttrs = (await call("GET", `/v1/apps/${appID}?fields[apps]=contentRightsDeclaration`)).data.attributes;
  if (!appAttrs.contentRightsDeclaration) {
    console.log(`${tag}コンテンツの権利: DOES_NOT_USE_THIRD_PARTY_CONTENT`);
    if (!dry) await call("PATCH", `/v1/apps/${appID}`,
      { data: { type: "apps", id: appID, attributes: { contentRightsDeclaration: "DOES_NOT_USE_THIRD_PARTY_CONTENT" } } });
  }

  // 6) 審査に関する情報（連絡先・メモ。サインイン不要）
  const review = defined(meta.review);
  let detail = null;
  if (target.id !== "(new)") {
    try {
      detail = (await call("GET", `/v1/appStoreVersions/${target.id}/appStoreReviewDetail`)).data;
    } catch (e) {
      if (e.status !== 404) throw e;
    }
  }
  console.log(`${tag}審査情報: ${detail ? "更新" : "作成"} ${Object.keys(review).join(", ")}`);
  if (!dry) {
    if (detail) {
      await call("PATCH", `/v1/appStoreReviewDetails/${detail.id}`,
        { data: { type: "appStoreReviewDetails", id: detail.id, attributes: review } });
    } else {
      await call("POST", "/v1/appStoreReviewDetails", {
        data: {
          type: "appStoreReviewDetails",
          attributes: review,
          relationships: { appStoreVersion: { data: { type: "appStoreVersions", id: target.id } } },
        },
      });
    }
  }

  // 7) 輸出コンプライアンス（Info.plist の ITSAppUsesNonExemptEncryption=NO が反映されていなければ明示）
  if (build.attributes.usesNonExemptEncryption == null) {
    console.log(`${tag}ビルド ${buildVersion}: 輸出コンプライアンス = 暗号化なし`);
    if (!dry) await call("PATCH", `/v1/builds/${build.id}`,
      { data: { type: "builds", id: build.id, attributes: { usesNonExemptEncryption: false } } });
  }

  // 8) ビルドを紐付けて審査に提出
  console.log(`${tag}ビルド ${buildVersion} をバージョン ${marketing} に紐付け`);
  if (!dry) await call("PATCH", `/v1/appStoreVersions/${target.id}/relationships/build`,
    { data: { type: "builds", id: build.id } });

  if (dry) {
    console.log(`[dry-run] 審査に提出（公開方法 ${releaseType}）`);
    return;
  }
  let [sub] = await activeSubmissions(appID, ["READY_FOR_REVIEW"]);
  if (!sub) {
    sub = (await call("POST", "/v1/reviewSubmissions", {
      data: {
        type: "reviewSubmissions",
        attributes: { platform: "IOS" },
        relationships: { app: { data: { type: "apps", id: appID } } },
      },
    })).data;
  }
  if (!(await submissionHasVersion(sub.id, target.id))) {
    await retryWhileNotReady("審査項目の追加", () => call("POST", "/v1/reviewSubmissionItems", {
      data: {
        type: "reviewSubmissionItems",
        relationships: {
          reviewSubmission: { data: { type: "reviewSubmissions", id: sub.id } },
          appStoreVersion: { data: { type: "appStoreVersions", id: target.id } },
        },
      },
    }));
  }
  // 項目を追加してから Apple がバージョンを READY_FOR_REVIEW にするまで少しかかる（すぐ提出すると 409）
  for (let i = 0; i < 20; i++) {
    const st = versionState((await call("GET",
      `/v1/appStoreVersions/${target.id}?fields[appStoreVersions]=appVersionState,appStoreState`)).data);
    if (st === "READY_FOR_REVIEW") break;
    console.log(`  提出準備待ち: ${st}`);
    await sleep(15_000);
  }
  try {
    await retryWhileNotReady("審査への提出", () => call("PATCH", `/v1/reviewSubmissions/${sub.id}`,
      { data: { type: "reviewSubmissions", id: sub.id, attributes: { submitted: true } } }));
  } catch (e) {
    console.error(String(e.message));
    const missing = (e.json?.errors || []).some((x) => Object.keys(x.meta?.associatedErrors || {}).length);
    fail(missing
      ? "審査に提出できませんでした。上に挙がった項目を App Store Connect で設定してから、Actions の「App Store」を再実行してください"
        + "（初回はスクリーンショット・App のプライバシー・価格と配信状況・年齢制限・App 内課金の登録が Web で必要。"
        + "docs/APPSTORE.md「production ブランチからの自動提出」）"
      : "審査に提出できませんでした（上の Apple のエラーを参照）");
  }
  console.log(`審査に提出しました: ${marketing} (${buildVersion})。`
    + (releaseType === "AFTER_APPROVAL" ? "承認されると自動で App Store に公開されます。" : "承認後、App Store Connect で公開してください。"));
}

// 「まだ準備中」の 409 だけを待って再試行する（それ以外のエラーはそのまま投げる）
async function retryWhileNotReady(what, fn) {
  for (let attempt = 1; ; attempt++) {
    try {
      return await fn();
    } catch (e) {
      const text = JSON.stringify(e.json?.errors || []);
      const notReady = e.status === 409 && /not ready|try again later|ENTITY_STATE_INVALID|in progress/i.test(text)
        && !(e.json?.errors || []).some((x) => Object.keys(x.meta?.associatedErrors || {}).length);
      if (!notReady || attempt >= 6) throw e;
      console.log(`  ${what}: Apple 側の準備待ち（${attempt}/6）`);
      await sleep(20_000);
    }
  }
}

async function setBetaNotes(build, text) {
  const whatsNew = text.slice(0, 4000);
  const r = await call("GET", `/v1/builds/${build.id}/betaBuildLocalizations?limit=50`);
  const cur = r.data.find((x) => x.attributes.locale === "ja");
  if (cur) {
    await call("PATCH", `/v1/betaBuildLocalizations/${cur.id}`,
      { data: { type: "betaBuildLocalizations", id: cur.id, attributes: { whatsNew } } });
  } else {
    await call("POST", "/v1/betaBuildLocalizations", {
      data: {
        type: "betaBuildLocalizations",
        attributes: { locale: "ja", whatsNew },
        relationships: { build: { data: { type: "builds", id: build.id } } },
      },
    });
  }
  console.log(`ビルド ${build.attributes.version} のテスト内容を設定:\n${whatsNew}`);
}

// ---- 掲載情報の下書き同期（審査には出さない） ----

// 編集中の App Store バージョンと App 情報に、名前・サブタイトル・説明・プロモーションテキスト・キーワードだけを書く。
// 公開 URL（プライバシー・サポート・マーケティング）は確定値になるまで仮値なので送らない。審査への提出・ビルドの紐付けはしない。
async function syncListing(appID, dry) {
  const tag = dry ? "[dry-run] " : "";
  const { meta } = loadMetadata();
  const versionLocs = {};
  const infoLocs = {};
  for (const [loc, m] of Object.entries(meta.locales)) {
    versionLocs[loc] = { description: m.version.description, keywords: m.version.keywords, promotionalText: m.version.promotionalText };
    infoLocs[loc] = { name: m.info.name, subtitle: m.info.subtitle };
  }
  const leftovers = Object.entries({ ...versionLocs, ...infoLocs })
    .filter(([, v]) => Object.values(v).some((s) => typeof s === "string" && (/\{\{[A-Z_]+\}\}/.test(s) || s.includes("velstria.example"))))
    .map(([loc]) => loc);
  if (leftovers.length) fail(`掲載文に仮値が残っています: ${leftovers.join(", ")}`);

  const versions = await iosVersions(appID);
  const target = versions.find((v) => EDITABLE.has(versionState(v)));
  if (!target) fail(`編集できる App Store バージョンがありません（${versions.map(versionState).join(", ") || "なし"}）`);
  console.log(`${tag}対象: App Store ${target.attributes.versionString}（${versionState(target)}）`);
  const curVLocs = (await call("GET", `/v1/appStoreVersions/${target.id}/appStoreVersionLocalizations?limit=50`)).data;
  await upsertLocalizations("appStoreVersionLocalizations", target, curVLocs, versionLocs, dry);

  const info = editableAppInfo(await appInfos(appID));
  if (!info) fail("編集できる App 情報がありません（名前・サブタイトルを書けないため中止）");
  const curILocs = (await call("GET", `/v1/appInfos/${info.id}/appInfoLocalizations?limit=50`)).data;
  await upsertLocalizations("appInfoLocalizations", info, curILocs, infoLocs, dry);
  console.log(`${tag}掲載情報の同期が完了（審査には提出していません）`);
}

// ---- スクリーンショットの登録 ----

// 言語ディレクトリ名 → ASC のロケール
const SHOT_LOCALES = { ja: "ja", en: "en-US" };
const SHOT_SETTLED = new Set(["COMPLETE", "FAILED"]);

// <dir>/<ja|en>/NN_name.png（名前順 = 掲載順）。review/ などのサブディレクトリは対象外
function listScreenshots(dir) {
  const out = {};
  for (const [sub, locale] of Object.entries(SHOT_LOCALES)) {
    const d = path.join(dir, sub);
    if (!fs.existsSync(d)) continue;
    const files = fs.readdirSync(d, { withFileTypes: true })
      .filter((e) => e.isFile() && /^\d\d_.+\.png$/.test(e.name)).map((e) => path.join(d, e.name)).sort();
    if (files.length) out[locale] = files;
  }
  return out;
}

async function uploadScreenshot(setID, file) {
  const bytes = fs.readFileSync(file);
  const created = (await call("POST", "/v1/appScreenshots", {
    data: {
      type: "appScreenshots",
      attributes: { fileName: path.basename(file), fileSize: bytes.length },
      relationships: { appScreenshotSet: { data: { type: "appScreenshotSets", id: setID } } },
    },
  })).data;
  for (const op of created.attributes.uploadOperations || []) {
    const headers = Object.fromEntries((op.requestHeaders || []).map((h) => [h.name, h.value]));
    const res = await fetch(op.url, { method: op.method, headers, body: bytes.subarray(op.offset, op.offset + op.length) });
    if (!res.ok) fail(`${path.basename(file)} の転送に失敗しました（HTTP ${res.status}）`);
  }
  await call("PATCH", `/v1/appScreenshots/${created.id}`, {
    data: {
      type: "appScreenshots", id: created.id,
      attributes: { uploaded: true, sourceFileChecksum: crypto.createHash("md5").update(bytes).digest("hex") },
    },
  });
  for (let i = 0; i < 60; i++) {
    const s = (await call("GET", `/v1/appScreenshots/${created.id}?fields[appScreenshots]=assetDeliveryState`)).data.attributes.assetDeliveryState;
    if (SHOT_SETTLED.has(s?.state)) {
      if (s.state === "FAILED") fail(`${path.basename(file)} を Apple が受理しませんでした: ${JSON.stringify(s.errors || [])}`);
      return created.id;
    }
    await new Promise((r) => setTimeout(r, 3000));
  }
  fail(`${path.basename(file)} の処理が 3 分たっても完了しません`);
}

// 言語ごとの画像一式を、編集中のバージョンの該当ローカライズ・枠（displayType）へ登録する。
// 枠に既に画像があるときは --replace を付けた時だけ消して入れ直す（付けなければ中止）。
async function uploadScreenshots(appID, dir, displayType, replace, dry) {
  const tag = dry ? "[dry-run] " : "";
  const plan = listScreenshots(dir);
  if (!Object.keys(plan).length) fail(`${dir} に <ja|en>/NN_name.png がありません`);
  const target = (await iosVersions(appID)).find((v) => EDITABLE.has(versionState(v)));
  if (!target) fail("編集できる App Store バージョンがありません");
  const locs = (await call("GET", `/v1/appStoreVersions/${target.id}/appStoreVersionLocalizations?limit=50&fields[appStoreVersionLocalizations]=locale`)).data;
  for (const [locale, files] of Object.entries(plan)) {
    const loc = locs.find((x) => x.attributes.locale === locale);
    if (!loc) {
      console.log(`${tag}${locale}: バージョンのローカライズがありません（先に sync-listing で作ります）。${files.length} 枚は未登録`);
      if (!dry) fail(`${locale} のローカライズが無いため中止`);
      continue;
    }
    const sets = await call("GET", `/v1/appStoreVersionLocalizations/${loc.id}/appScreenshotSets?limit=50`
      + "&include=appScreenshots&limit[appScreenshots]=50&fields[appScreenshotSets]=screenshotDisplayType,appScreenshots");
    const set = sets.data.find((s) => s.attributes.screenshotDisplayType === displayType);
    const existing = (set?.relationships?.appScreenshots?.data || []).map((x) => x.id);
    if (existing.length && !replace) fail(`${locale} の ${displayType} には既に ${existing.length} 枚あります。入れ直すなら --replace`);
    console.log(`${tag}${locale} ${displayType}: ${existing.length ? `既存 ${existing.length} 枚を削除して ` : ""}${files.length} 枚を登録（${files.map((f) => path.basename(f)).join(", ")}）`);
    if (dry) continue;
    for (const id of existing) await call("DELETE", `/v1/appScreenshots/${id}`);
    const setID = set?.id || (await call("POST", "/v1/appScreenshotSets", {
      data: {
        type: "appScreenshotSets",
        attributes: { screenshotDisplayType: displayType },
        relationships: { appStoreVersionLocalization: { data: { type: "appStoreVersionLocalizations", id: loc.id } } },
      },
    })).data.id;
    const ids = [];
    for (const f of files) {
      ids.push(await uploadScreenshot(setID, f));
      console.log(`  ${locale}: ${path.basename(f)} を登録`);
    }
    await call("PATCH", `/v1/appScreenshotSets/${setID}/relationships/appScreenshots`,
      { data: ids.map((id) => ({ type: "appScreenshots", id })) });
  }
  console.log(`${tag}スクリーンショットの登録が完了（審査には提出していません）`);
}

const [cmd, ...rest] = process.argv.slice(2);
// release-check と、--dry-run を付けた下書き同期は GET 以外を送らせない
readOnly = cmd === "release-check" || (["sync-listing", "upload-screenshots"].includes(cmd) && rest.includes("--dry-run"));

if (cmd === "create-app") {
  // API でのアプリレコード作成（Apple が許可していない場合はエラー内容を表示して終了）
  const existing = await call("GET", `/v1/apps?filter[bundleId]=${encodeURIComponent(BUNDLE_ID)}`);
  if (existing.data.length) { console.log(`既に存在: ${existing.data[0].attributes.name}`); process.exit(0); }
  const bid = await call("GET", `/v1/bundleIds?filter[identifier]=${encodeURIComponent(BUNDLE_ID)}&limit=5`);
  const exact = bid.data.find((b) => b.attributes.identifier === BUNDLE_ID);
  if (!exact) fail(`Bundle ID ${BUNDLE_ID} が Developer に登録されていません`);
  console.log(`Bundle ID: ${exact.attributes.identifier}（${exact.attributes.name}, id ${exact.id}）`);
  const [name = "VELSIA - 星環の戦場", sku = "VELSTRIA-IOS-001"] = rest;
  try {
    const r = await call("POST", "/v1/apps", {
      data: {
        type: "apps",
        attributes: { name, sku, primaryLocale: "ja", bundleId: BUNDLE_ID },
        relationships: { bundleId: { data: { type: "bundleIds", id: exact.id } } },
      },
    });
    console.log(`作成: ${r.data.attributes.name}（id ${r.data.id}）`);
  } catch (e) {
    fail(`アプリレコードを API で作成できませんでした:\n${e.message}`);
  }
  process.exit(0);
}

const app = await findApp();
console.log(`アプリ: ${app.attributes.name}（${app.attributes.bundleId}, id ${app.id}）`);

switch (cmd) {
  case "status": {
    for (const v of await iosVersions(app.id)) {
      console.log(`  App Store ${v.attributes.versionString}  ${versionState(v)}  ${v.attributes.releaseType || ""}`);
    }
    for (const b of await builds(app.id)) {
      const a = b.attributes;
      console.log(`  build ${a.version}  ${a.processingState}  ${a.uploadedDate}${a.expired ? "  (expired)" : ""}`);
    }
    break;
  }
  case "wait-build": {
    const version = rest[0] || fail("ビルド番号を指定してください");
    for (let i = 0; i < 120; i++) {
      const b = (await builds(app.id)).find((x) => x.attributes.version === version);
      const state = b ? b.attributes.processingState : "NOT_FOUND";
      console.log(`  build ${version}: ${state}`);
      if (state === "VALID") process.exit(0);
      if (state === "FAILED" || state === "INVALID") fail(`ビルド ${version} の処理が失敗しました（${state}）`);
      await new Promise((r) => setTimeout(r, 30_000));
    }
    fail("60 分待っても処理が完了しません");
    break;
  }
  case "verify-internal": {
    await verifyInternal(app.id, rest[0] || fail("ビルド番号を指定してください"));
    break;
  }
  case "internal": {
    if (!rest.length) fail("メールアドレスを指定してください");
    const group = await internalGroup(app.id);
    for (const email of rest) {
      try {
        await addTester(group, email);
      } catch (e) {
        console.error(String(e.message));
        console.error(`  ${email} は App Store Connect の「ユーザとアクセス」に登録されたユーザである必要があります（内部テスト）。`);
        process.exitCode = 1;
      }
    }
    const latest = (await builds(app.id)).find((x) => x.attributes.processingState === "VALID");
    if (latest) await ensureBuildInGroup(group, latest);
    break;
  }
  case "testers": {
    const groups = await call("GET", `/v1/apps/${app.id}/betaGroups?limit=50`);
    for (const g of groups.data) {
      const t = await call("GET", `/v1/betaGroups/${g.id}/betaTesters?limit=200&fields[betaTesters]=email,inviteType,state`);
      console.log(`  ${g.attributes.name}${g.attributes.isInternalGroup ? "（内部）" : "（外部）"}: `
        + (t.data.map((x) => `${x.attributes.email} [${x.attributes.state || "-"}]`).join(", ") || "テスターなし"));
    }
    break;
  }
  case "beta-notes": {
    const [version, ...words] = rest;
    if (!version || !words.length) fail("usage: node tools/asc.mjs beta-notes <build> <text>");
    await setBetaNotes(await findBuild(app.id, version), words.join(" "));
    break;
  }
  case "release-check": {
    const marketing = rest.find((x) => !x.startsWith("--")) || fail("バージョン（例 1.0.0）を指定してください");
    const { versions, open } = await releaseCheck(app.id, marketing);
    if (!open) console.log(`App Store バージョン ${marketing} を新しく作成して提出します`);
    else if (UNDER_REVIEW.has(versionState(open))) {
      console.log(`バージョン ${open.attributes.versionString} は審査中（${versionState(open)}）です。取り下げて新しいビルドで出し直します`);
    } else {
      console.log(`編集中のバージョン ${open.attributes.versionString}（${versionState(open)}）に ${marketing} のビルドを紐付けて提出します`);
    }
    console.log("提出前チェック（App Store Connect の設定。読み取りのみ）:");
    reportPreSubmit(await preSubmitChecks(app.id, versions, open),
      rest.filter((x) => x.startsWith("--allow=")).map((x) => x.slice("--allow=".length)));
    break;
  }
  case "submit": {
    const buildVersion = rest.find((x) => !x.startsWith("--")) || fail("ビルド番号を指定してください");
    await submitBuild(app.id, buildVersion, rest.includes("--dry-run"));
    break;
  }
  case "sync-listing": {
    await syncListing(app.id, rest.includes("--dry-run"));
    break;
  }
  case "upload-screenshots": {
    const dir = rest.find((x) => !x.startsWith("--")) || fail("画像のディレクトリ（<dir>/<ja|en>/NN_name.png）を指定してください");
    const displayType = (rest.find((x) => x.startsWith("--display-type=")) || "--display-type=APP_IPHONE_67").slice("--display-type=".length);
    await uploadScreenshots(app.id, path.resolve(dir), displayType, rest.includes("--replace"), rest.includes("--dry-run"));
    break;
  }
  default:
    fail("usage: node tools/asc.mjs status | wait-build <build> | verify-internal <build> | internal <email>... | testers"
      + " | beta-notes <build> <text> | release-check <version> [--allow=<ID>,...] | submit <build> [--dry-run]"
      + " | sync-listing [--dry-run] | upload-screenshots <dir> [--display-type=<type>] [--replace] [--dry-run]");
}
