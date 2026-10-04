#!/usr/bin/env node
// App Store Connect API の小さなクライアント（依存なし。Node 標準 crypto で ES256 の JWT を作る）。
// TestFlight 内部テストの配信と、App Store の審査提出（production ブランチ）を自動化する。
//
// 環境変数:
//   ASC_KEY_ID      API キーの Key ID（10 桁）
//   ASC_ISSUER_ID   Issuer ID（UUID）
//   ASC_KEY_PATH    .p8 の場所（省略時 ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8）
//   ASC_BUNDLE_ID   既定 com.bitcoinpay.velstria
//   ASC_RELEASE_TYPE  submit 時の公開方法。AFTER_APPROVAL（既定: 承認されたら自動で公開）/ MANUAL（承認後に手動で公開）
//
// usage:
//   node tools/asc.mjs create-app [name] [sku]         アプリレコードの作成を試す（Apple が API での作成を許可している場合のみ成功）
//   node tools/asc.mjs status                         アプリとビルドの一覧
//   node tools/asc.mjs wait-build <build>             ビルドの処理完了（VALID）を待つ
//   node tools/asc.mjs internal <email> [<email>...]  内部テストグループを用意し、テスターを追加（ASC ユーザであること）
//   node tools/asc.mjs testers                        ベータグループとテスターの一覧
//   node tools/asc.mjs beta-notes <build> <text>      TestFlight の「テスト内容」を設定（ブランチ・コミットの表示用）
//   node tools/asc.mjs release-check <version>        App Store に <version> を出せるか確認（公開済みなら MARKETING_VERSION を上げる）
//   node tools/asc.mjs submit <build> [--dry-run]     ビルドを App Store バージョンに紐付け、メタデータ（docs/appstore/metadata）を
//                                                     同期して審査に提出する。--dry-run は読み取りだけで、行う変更を表示する
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

const META_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "docs", "appstore", "metadata");
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
  const isFirstRelease = !versions.some((v) => LIVE_ONCE.has(versionState(v)));

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
    if (!isFirstRelease && !whatsNew) {
      fail(`2 回目以降のリリースには docs/appstore/metadata/${loc}/release_notes.txt（このバージョンの新機能）が必要です`);
    }
    versionLocs[loc] = isFirstRelease ? rest : { ...rest, whatsNew };
  }
  const curVLocs = target.id === "(new)" ? [] : (await call("GET",
    `/v1/appStoreVersions/${target.id}/appStoreVersionLocalizations?limit=50`)).data;
  await upsertLocalizations("appStoreVersionLocalizations", target, curVLocs, versionLocs, dry);

  // 4) App 情報（名前・サブタイトル・プライバシーポリシー URL・カテゴリ）。公開中でない appInfo だけが編集できる
  const infos = (await call("GET", `/v1/apps/${appID}/appInfos?limit=200&fields[appInfos]=state,appStoreState`)).data;
  const infoState = (x) => x.attributes.state || x.attributes.appStoreState;
  const info = infos.find((x) => infoState(x) === "PREPARE_FOR_SUBMISSION")
    || infos.find((x) => EDITABLE_INFO.has(infoState(x)));
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
    const marketing = rest[0] || fail("バージョン（例 1.0.0）を指定してください");
    const { open } = await releaseCheck(app.id, marketing);
    if (!open) console.log(`App Store バージョン ${marketing} を新しく作成して提出します`);
    else if (UNDER_REVIEW.has(versionState(open))) {
      console.log(`バージョン ${open.attributes.versionString} は審査中（${versionState(open)}）です。取り下げて新しいビルドで出し直します`);
    } else {
      console.log(`編集中のバージョン ${open.attributes.versionString}（${versionState(open)}）に ${marketing} のビルドを紐付けて提出します`);
    }
    break;
  }
  case "submit": {
    const buildVersion = rest.find((x) => !x.startsWith("--")) || fail("ビルド番号を指定してください");
    await submitBuild(app.id, buildVersion, rest.includes("--dry-run"));
    break;
  }
  default:
    fail("usage: node tools/asc.mjs status | wait-build <build> | internal <email>... | testers"
      + " | beta-notes <build> <text> | release-check <version> | submit <build> [--dry-run]");
}
