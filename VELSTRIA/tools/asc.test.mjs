import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";
import { after, test } from "node:test";

// 実際のキーや API を使わず、CLI 全体を使い捨てキーとモック応答で検証する。
const tempRoot = fs.realpathSync(os.tmpdir());
const fixtureDir = fs.mkdtempSync(path.join(tempRoot, "velstria-asc-test-"));
const keyPath = path.join(fixtureDir, "test-key.p8");
fs.writeFileSync(keyPath, crypto.generateKeyPairSync("ec", { namedCurve: "prime256v1" }).privateKey
  .export({ type: "pkcs8", format: "pem" }));
after(() => {
  const target = fs.realpathSync(fixtureDir);
  assert.equal(path.dirname(target), tempRoot);
  assert.ok(path.basename(target).startsWith("velstria-asc-test-"));
  fs.rmSync(target, { recursive: true, force: true });
});

const mockPath = path.join(fixtureDir, "mock.mjs");
fs.writeFileSync(mockPath, `
import assert from "node:assert/strict";
import fs from "node:fs";
const steps = JSON.parse(fs.readFileSync(process.env.ASC_TEST_STEPS, "utf8"));
let index = 0;
const realSetTimeout = globalThis.setTimeout;
globalThis.setTimeout = (callback, delay, ...args) => realSetTimeout(callback, 0, ...args);
globalThis.fetch = async (value, options) => {
  const url = new URL(value);
  fs.appendFileSync(process.env.ASC_TEST_CALLS, JSON.stringify({ url: url.href, method: options.method }) + "\\n");
  assert.equal(url.origin, "https://api.appstoreconnect.apple.com");
  assert.equal(options.method, "GET", "CI commands must remain read-only");
  const step = steps[index++];
  assert.ok(step, "Unexpected API request: " + url.href);
  assert.equal(url.pathname, step.path);
  for (const [key, value] of Object.entries(step.query || {})) assert.equal(url.searchParams.get(key), value);
  return new Response(JSON.stringify(step.body), { status: step.status || 200 });
};
`);

const app = { path: "/v1/apps", body: { data: [{ id: "app", attributes: { name: "Test App", bundleId: "com.test.app" } }] } };
const build = (version, attributes = {}) => ({ id: `build-${version}`, attributes: { version, processingState: "VALID", expired: false, ...attributes } });
const group = (attributes = {}) => ({ id: "internal", attributes: { name: "Internal", isInternalGroup: true, hasAccessToAllBuilds: true, ...attributes } });
const page = (requestPath, data, next) => ({ path: requestPath, body: { data, links: { next } } });
let runNumber = 0;

function run(args, steps, env = {}) {
  const prefix = path.join(fixtureDir, String(++runNumber));
  fs.writeFileSync(`${prefix}.json`, JSON.stringify([app, ...steps]));
  const result = spawnSync(process.execPath, ["--import", pathToFileURL(mockPath).href, fileURLToPath(new URL("./asc.mjs", import.meta.url)), ...args], {
    encoding: "utf8",
    timeout: 10_000,
    env: {
      ...process.env,
      ASC_KEY_ID: "TESTKEY001",
      ASC_ISSUER_ID: "00000000-0000-0000-0000-000000000001",
      ASC_KEY_PATH: keyPath,
      ASC_BUNDLE_ID: "com.test.app",
      ASC_INTERNAL_GROUP_ID: "internal",
      ASC_TEST_STEPS: `${prefix}.json`,
      ASC_TEST_CALLS: `${prefix}.calls`,
      ...env,
    },
  });
  assert.ifError(result.error);
  assert.ok(fs.existsSync(`${prefix}.calls`), result.stderr);
  result.calls = fs.readFileSync(`${prefix}.calls`, "utf8").trim().split("\n").map(JSON.parse);
  return result;
}

function succeeds(result, count) {
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.calls.length, count);
}

test("verify-internal follows group/build pagination and waits for propagation", () => {
  const result = run(["verify-internal", "103"], [
    page("/v1/apps/app/betaGroups", [{ id: "other", attributes: group().attributes }], "/v1/apps/app/betaGroups?cursor=second"),
    page("/v1/apps/app/betaGroups", [group()]),
    page("/v1/betaGroups/internal/betaTesters", [{ id: "tester" }]),
    page("/v1/betaGroups/internal/builds", [build("102")]),
    page("/v1/betaGroups/internal/builds", [build("102")], "/v1/betaGroups/internal/builds?cursor=second"),
    page("/v1/betaGroups/internal/builds", [build("103")]),
  ]);
  succeeds(result, 7);
  assert.match(result.stdout, /内部配信を確認: Internal \/ build 103 \/ テスター 1 人/);
});

test("verify-internal requires an explicitly configured group belonging to the app", () => {
  const missingID = run(["verify-internal", "103"], [], { ASC_INTERNAL_GROUP_ID: "" });
  assert.notEqual(missingID.status, 0);
  assert.match(missingID.stderr, /ASC_INTERNAL_GROUP_ID/);
  const absent = run(["verify-internal", "103"], [page("/v1/apps/app/betaGroups", [])]);
  assert.notEqual(absent.status, 0);
  assert.match(absent.stderr, /このアプリにありません/);
});

test("verify-internal rejects external groups, disabled auto-distribution, and empty tester groups", () => {
  for (const attributes of [{ isInternalGroup: false }, { hasAccessToAllBuilds: false }]) {
    const result = run(["verify-internal", "103"], [page("/v1/apps/app/betaGroups", [group(attributes)])]);
    assert.notEqual(result.status, 0);
    assert.equal(result.calls.length, 2);
  }
  const empty = run(["verify-internal", "103"], [
    page("/v1/apps/app/betaGroups", [group()]),
    page("/v1/betaGroups/internal/betaTesters", []),
  ]);
  assert.notEqual(empty.status, 0);
  assert.match(empty.stderr, /テスターがいません/);
});

test("verify-internal fails for expired/invalid builds and after missing-build propagation retries", () => {
  const prefix = [
    page("/v1/apps/app/betaGroups", [group()]),
    page("/v1/betaGroups/internal/betaTesters", [{ id: "tester" }]),
  ];
  for (const attributes of [{ expired: true }, { expired: null }, { processingState: "INVALID" }]) {
    const result = run(["verify-internal", "103"], [...prefix, page("/v1/betaGroups/internal/builds", [build("103", attributes)])]);
    assert.notEqual(result.status, 0);
    assert.equal(result.calls.length, 4);
  }
  const missing = run(["verify-internal", "103"], [...prefix, ...Array.from({ length: 13 }, () => page("/v1/betaGroups/internal/builds", []))]);
  assert.notEqual(missing.status, 0);
  assert.equal(missing.calls.length, 16);
  assert.match(missing.stderr, /3 分待っても/);
});

const draftVersion = { path: "/v1/apps/app/appStoreVersions", body: { data: [{ id: "v1", attributes: { versionString: "1.0", appVersionState: "PREPARE_FOR_SUBMISSION" } }] } };

test("sync-listing --dry-run reads the draft, lists the listing fields to write, and sends no writes", () => {
  const result = run(["sync-listing", "--dry-run"], [
    draftVersion,
    { path: "/v1/appStoreVersions/v1/appStoreVersionLocalizations", body: { data: [{ id: "vl-ja", attributes: { locale: "ja", description: "old" } }] } },
    { path: "/v1/apps/app/appInfos", body: { data: [{ id: "i1", attributes: { state: "PREPARE_FOR_SUBMISSION" } }] } },
    { path: "/v1/appInfos/i1/appInfoLocalizations", body: { data: [{ id: "il-ja", attributes: { locale: "ja", name: "VELSTRIA - 星環の戦場" } }] } },
  ]);
  succeeds(result, 5);
  assert.match(result.stdout, /appStoreVersionLocalizations ja: 更新 description/);
  assert.match(result.stdout, /appStoreVersionLocalizations en-US: 作成 description, keywords, promotionalText/);
  assert.match(result.stdout, /appInfoLocalizations ja: 更新 name/);
  assert.doesNotMatch(result.stdout, /Url/i, "公開 URL（仮値）は送らない");
  assert.match(result.stdout, /審査には提出していません/);
});

test("sync-listing refuses when no App Store version is editable", () => {
  const result = run(["sync-listing", "--dry-run"], [
    { path: "/v1/apps/app/appStoreVersions", body: { data: [{ id: "v1", attributes: { versionString: "1.0", appVersionState: "READY_FOR_SALE" } }] } },
  ]);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /編集できる App Store バージョンがありません/);
});

function screenshotDir(files) {
  const dir = fs.mkdtempSync(path.join(fixtureDir, "shots-"));
  for (const f of files) {
    fs.mkdirSync(path.join(dir, path.dirname(f)), { recursive: true });
    fs.writeFileSync(path.join(dir, f), "png");
  }
  return dir;
}

const shotSteps = (existing) => [
  draftVersion,
  { path: "/v1/appStoreVersions/v1/appStoreVersionLocalizations", body: { data: [{ id: "vl-ja", attributes: { locale: "ja" } }] } },
  {
    path: "/v1/appStoreVersionLocalizations/vl-ja/appScreenshotSets",
    body: {
      data: existing.length
        ? [{ id: "set1", attributes: { screenshotDisplayType: "APP_IPHONE_67" }, relationships: { appScreenshots: { data: existing.map((id) => ({ id })) } } }]
        : [],
    },
  },
];

test("upload-screenshots --dry-run plans ja files in name order and ignores review/ and non-numbered files", () => {
  const dir = screenshotDir(["ja/02_home.png", "ja/01_battle.png", "ja/review/iap_store.png", "ja/notes.png", "en/01_battle.png"]);
  const result = run(["upload-screenshots", dir, "--dry-run"], shotSteps([]));
  succeeds(result, 4);
  assert.match(result.stdout, /ja APP_IPHONE_67: 2 枚を登録（01_battle\.png, 02_home\.png）/);
  assert.match(result.stdout, /en-US: バージョンのローカライズがありません/);
});

test("upload-screenshots refuses to touch an occupied screenshot set without --replace", () => {
  const dir = screenshotDir(["ja/01_battle.png"]);
  const refused = run(["upload-screenshots", dir, "--dry-run"], shotSteps(["a", "b"]));
  assert.notEqual(refused.status, 0);
  assert.match(refused.stderr, /既に 2 枚あります。入れ直すなら --replace/);
  const replaced = run(["upload-screenshots", dir, "--dry-run", "--replace"], shotSteps(["a", "b"]));
  succeeds(replaced, 4);
  assert.match(replaced.stdout, /既存 2 枚を削除して 1 枚を登録/);
});
