#!/usr/bin/env node
// App Store Connect API の小さなクライアント（依存なし。Node 標準 crypto で ES256 の JWT を作る）。
// TestFlight 内部テストの配信を自動化する。
//
// 環境変数:
//   ASC_KEY_ID      API キーの Key ID（10 桁）
//   ASC_ISSUER_ID   Issuer ID（UUID）
//   ASC_KEY_PATH    .p8 の場所（省略時 ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8）
//   ASC_BUNDLE_ID   既定 com.bitcoinpay.velstria
//
// usage:
//   node tools/asc.mjs create-app [name] [sku]         アプリレコードの作成を試す（Apple が API での作成を許可している場合のみ成功）
//   node tools/asc.mjs status                         アプリとビルドの一覧
//   node tools/asc.mjs wait-build <build>             ビルドの処理完了（VALID）を待つ
//   node tools/asc.mjs internal <email> [<email>...]  内部テストグループを用意し、テスターを追加（ASC ユーザであること）
//   node tools/asc.mjs testers                        ベータグループとテスターの一覧
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

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

async function call(method, url, body) {
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
    const detail = (json.errors || []).map((e) => `${e.status} ${e.code}: ${e.title} — ${e.detail}`).join("\n  ");
    const err = new Error(`${method} ${url} → ${res.status}\n  ${detail}`);
    err.status = res.status;
    err.json = json;
    throw err;
  }
  return json;
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

const [cmd, ...rest] = process.argv.slice(2);

if (cmd === "create-app") {
  // API でのアプリレコード作成（Apple が許可していない場合はエラー内容を表示して終了）
  const existing = await call("GET", `/v1/apps?filter[bundleId]=${encodeURIComponent(BUNDLE_ID)}`);
  if (existing.data.length) { console.log(`既に存在: ${existing.data[0].attributes.name}`); process.exit(0); }
  const bid = await call("GET", `/v1/bundleIds?filter[identifier]=${encodeURIComponent(BUNDLE_ID)}&limit=5`);
  const exact = bid.data.find((b) => b.attributes.identifier === BUNDLE_ID);
  if (!exact) fail(`Bundle ID ${BUNDLE_ID} が Developer に登録されていません`);
  console.log(`Bundle ID: ${exact.attributes.identifier}（${exact.attributes.name}, id ${exact.id}）`);
  const [name = "VELSTRIA - 星環の戦場", sku = "VELSTRIA-IOS-001"] = rest;
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
  default:
    fail("usage: node tools/asc.mjs status | wait-build <build> | internal <email>... | testers");
}
