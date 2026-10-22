// 中継（relay/src/index.ts）の結合テスト。本物の Worker を相手に、Node の組み込みテストランナーと Node の WebSocket で確かめる。
//
//   npm test                                                        手元で `wrangler dev` を空いているポートで起こして試す
//   RELAY_URL=wss://velstria-relay.<sub>.workers.dev npm test       配備済みの中継を試す
//
// 部屋コードはテストごとに乱数で作るので、配備済みの中継に対して何度・並行に流しても互いに混ざらない。

import { after, before, describe, test } from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { randomBytes, randomInt } from "node:crypto";
import { mkdtempSync, rmSync } from "node:fs";
import http from "node:http";
import https from "node:https";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const RELAY_DIR = join(dirname(fileURLToPath(import.meta.url)), "..");
const ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
const KIB = 1024;
const MAX_MESSAGE = 256 * KIB;

const GUEST_OPEN = 0x10;
const GUEST_DATA = 0x11;
const GUEST_CLOSE = 0x12;
const SEND = 0x21;
const KICK = 0x22;

/** 何も届かないことを確かめる時の待ち時間 */
const QUIET_MS = 400;
const TIMEOUT_MS = 15_000;

let wsBase = process.env.RELAY_URL?.replace(/\/+$/, "");
/** 手元の Worker でだけ、運営が利用を止めたコード（SUSPENDED_FRIEND_CODES）として渡すコード */
const SUSPENDED_CODE = process.env.RELAY_URL ? null : randomFriendCode();
/** 運営のメールの鍵（手元の Worker は乱数で渡す。配備済みの中継では環境変数 OPS_MAIL_KEY があれば使い、無ければ運営のテストを飛ばす） */
const OPS_MAIL_KEY = process.env.RELAY_URL ? (process.env.OPS_MAIL_KEY ?? null) : randomKey();
let devServer;
let persistDir;

// ---- 手元の Worker（wrangler dev）の起動と停止 ----

before(async () => {
  if (wsBase) return;
  const port = await freePort();
  const inspectorPort = await freePort();
  persistDir = mkdtempSync(join(tmpdir(), "velstria-relay-test-"));
  const wranglerBin = join(RELAY_DIR, "node_modules", "wrangler", "bin", "wrangler.js");
  const args = [
    wranglerBin, "dev",
    "--ip", "127.0.0.1",
    "--port", String(port),
    "--inspector-port", String(inspectorPort),
    "--persist-to", persistDir,
    "--var", `SUSPENDED_FRIEND_CODES:ZZZZZZZZ,${SUSPENDED_CODE}`,
    "--var", `OPS_MAIL_KEY:${OPS_MAIL_KEY}`,
    "--show-interactive-dev-session=false",
    "--log-level", "warn",
  ];
  devServer = spawn(process.execPath, args, {
    cwd: RELAY_DIR,
    env: { ...process.env, WRANGLER_SEND_METRICS: "false", NO_COLOR: "1" },
    stdio: ["ignore", "pipe", "pipe"],
  });
  let output = "";
  devServer.stdout.on("data", (chunk) => { output += chunk; });
  devServer.stderr.on("data", (chunk) => { output += chunk; });
  wsBase = `ws://127.0.0.1:${port}`;
  const deadline = Date.now() + 90_000;
  for (;;) {
    if (devServer.exitCode !== null) throw new Error(`wrangler dev が終了した:\n${output}`);
    try {
      const response = await fetch(`${httpBase()}/v1/health`);
      if (response.ok) break;
    } catch {
      // まだ起動中
    }
    if (Date.now() > deadline) throw new Error(`wrangler dev が起動しない:\n${output}`);
    await delay(250);
  }
});

after(async () => {
  if (devServer && devServer.exitCode === null) {
    const exited = new Promise((resolve) => devServer.once("exit", resolve));
    devServer.kill("SIGTERM");
    await Promise.race([exited, delay(5_000)]);
    if (devServer.exitCode === null) devServer.kill("SIGKILL");
  }
  // Windows では wrangler が止まった直後も workerd が SQLite のファイルを掴んでいて消せない（EBUSY）ので、少し待って消し直す。
  // それでも掴まれたままなら一時フォルダの片付けは諦める（テストの結果には関わらない）
  if (persistDir) {
    try {
      rmSync(persistDir, { recursive: true, force: true, maxRetries: 30, retryDelay: 200 });
    } catch (e) {
      if (process.platform !== "win32" || e?.code !== "EBUSY") throw e;
    }
  }
});

// ---- 道具 ----

function httpBase() {
  return wsBase.replace(/^ws/, "http");
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function freePort() {
  return new Promise((resolve, reject) => {
    const server = createServer();
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const { port } = server.address();
      server.close(() => resolve(port));
    });
  });
}

function randomCode() {
  let code = "";
  for (let i = 0; i < 6; i++) code += ALPHABET[randomInt(ALPHABET.length)];
  return code;
}

function roomURL(code, role, rv = "1", resumeKey = null) {
  const query = new URLSearchParams({ role });
  if (rv !== null) query.set("rv", rv);
  if (resumeKey !== null) query.set("hk", resumeKey);
  return `${wsBase}/v1/rooms/${code}?${query}`;
}

/** [u8 種類][u32 guestId][payload...] */
function frame(type, guestId, payload = new Uint8Array(0)) {
  const out = new Uint8Array(5 + payload.byteLength);
  out[0] = type;
  new DataView(out.buffer).setUint32(1, guestId, false);
  out.set(payload, 5);
  return out;
}

function parseFrame(bytes) {
  assert.ok(bytes instanceof Uint8Array, `バイナリのはずが ${typeof bytes}`);
  assert.ok(bytes.byteLength >= 5, `枠が短い: ${bytes.byteLength}`);
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  return { type: bytes[0], guestId: view.getUint32(1, false), payload: bytes.subarray(5) };
}

function withTimeout(promise, ms, what) {
  let timer;
  return Promise.race([
    promise.finally(() => clearTimeout(timer)),
    new Promise((_, reject) => { timer = setTimeout(() => reject(new Error(`時間切れ: ${what}`)), ms); }),
  ]);
}

/** 届いたメッセージを順に取り出せる WebSocket の薄い包み */
class Peer {
  constructor(url, label) {
    this.label = label;
    this.messages = [];
    this.waiters = [];
    this.ws = new WebSocket(url);
    this.ws.binaryType = "arraybuffer";
    this.opened = new Promise((resolve, reject) => {
      this.ws.addEventListener("open", () => resolve(), { once: true });
      this.ws.addEventListener("error", () => reject(new Error(`${label}: 接続できない`)), { once: true });
    });
    this.opened.catch(() => {});
    this.closed = new Promise((resolve) => {
      this.ws.addEventListener("close", (event) => {
        resolve({ code: event.code, reason: event.reason });
        for (const waiter of this.waiters.splice(0)) waiter.reject(new Error(`${label}: 閉じた (${event.code} ${event.reason})`));
      }, { once: true });
    });
    this.ws.addEventListener("message", (event) => {
      const data = typeof event.data === "string" ? event.data : new Uint8Array(event.data);
      const waiter = this.waiters.shift();
      if (waiter) waiter.resolve(data);
      else this.messages.push(data);
    });
  }

  /**
   * 開いてから、アプリと同じく生存確認の ping を 1 回送る。
   * 何も送っていない接続を中継が閉じると、close の握手の後も TCP が約 10 秒残り（workerd の既知の不具合
   * cloudflare/workerd#7566）、Node の WebSocket は close イベントをその分遅らせるため。
   */
  static async open(url, label) {
    const peer = new Peer(url, label);
    await withTimeout(peer.opened, TIMEOUT_MS, `${label} の接続`);
    peer.send("ping");
    assert.equal(await peer.next(), "pong", `${label}: 最初の ping に pong が返らない`);
    return peer;
  }

  next(ms = TIMEOUT_MS) {
    if (this.messages.length > 0) return Promise.resolve(this.messages.shift());
    if (this.ws.readyState >= WebSocket.CLOSING) return Promise.reject(new Error(`${this.label}: 閉じている`));
    const promise = new Promise((resolve, reject) => this.waiters.push({ resolve, reject }));
    return withTimeout(promise, ms, `${this.label} の受信`);
  }

  async nextFrame(ms) {
    return parseFrame(await this.next(ms));
  }

  /** しばらく何も届かないこと */
  async expectQuiet(ms = QUIET_MS) {
    await delay(ms);
    assert.deepEqual(this.messages, [], `${this.label} に余計なメッセージが届いた`);
  }

  closeEvent(ms = TIMEOUT_MS) {
    return withTimeout(this.closed, ms, `${this.label} の切断`);
  }

  send(data) {
    this.ws.send(data);
  }

  close(code = 1000, reason = "") {
    if (this.ws.readyState <= WebSocket.OPEN) this.ws.close(code, reason);
  }
}

const peers = [];
function track(peer) {
  peers.push(peer);
  return peer;
}

async function openHost(code, resumeKey = null) {
  return track(await Peer.open(roomURL(code, "host", "1", resumeKey), `host ${code}`));
}

/** 参加者を開き、ホストに届く GUEST_OPEN から guestId を取る */
async function openGuest(code, host, label = "guest") {
  const guest = track(await Peer.open(roomURL(code, "guest"), `${label} ${code}`));
  const opened = await host.nextFrame();
  assert.equal(opened.type, GUEST_OPEN);
  assert.equal(opened.payload.byteLength, 0);
  guest.id = opened.guestId;
  return guest;
}

/** 受け入れた上ですぐ閉じられること（close コードと理由） */
async function expectRejected(url, code, reason) {
  const peer = track(new Peer(url, `rejected ${code}`));
  const event = await peer.closeEvent();
  assert.deepEqual(event, { code, reason });
}

/** WebSocket の握手を生の HTTP で送り、状態コードを返す（握手前に断られた時の 400 などを見るため） */
function upgradeStatus(url) {
  const target = new URL(url.replace(/^ws/, "http"));
  const client = target.protocol === "https:" ? https : http;
  return new Promise((resolve, reject) => {
    const request = client.request(target, {
      headers: {
        Connection: "Upgrade",
        Upgrade: "websocket",
        "Sec-WebSocket-Version": "13",
        "Sec-WebSocket-Key": randomBytes(16).toString("base64"),
      },
    });
    request.on("response", (response) => {
      response.resume();
      resolve(response.statusCode);
    });
    request.on("upgrade", (response, socket) => {
      socket.destroy();
      resolve(response.statusCode);
    });
    request.on("error", reject);
    request.end();
  });
}

function closeAll() {
  for (const peer of peers.splice(0)) peer.close();
}

/** HTTP の要求（POST の時だけ本文を付ける。文字列はそのまま、ほかは JSON にする）。状態コード・見出し・本文を返す */
async function httpCall(path, body, method = "POST") {
  const init = { method };
  if (method === "POST") init.body = typeof body === "string" ? body : JSON.stringify(body);
  const response = await fetch(`${httpBase()}${path}`, init);
  const text = await response.text();
  let json = null;
  try {
    json = JSON.parse(text);
  } catch {
    // 誤りの応答は平文
  }
  return { status: response.status, headers: response.headers, text: text.trim(), json };
}

/** 誤りの応答（平文の理由）を確かめる */
function assertError(response, status, reason, what) {
  assert.deepEqual([response.status, response.text], [status, reason], what);
}

// ---- テスト ----

describe("HTTP", () => {
  test("health は 200 {ok:true, relay:1}", async () => {
    const response = await fetch(`${httpBase()}/v1/health`);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { ok: true, relay: 1 });
  });

  test("部屋コードの規則に合わなければ 400（WebSocket の握手でも）", async () => {
    const bad = ["ABCDE", "ABCDEFG", "abcdef", "ABCDE0", "ABCDE1", "ABCDEI", "ABCDEL", "ABCDEO", "ABC-EF", "ABC%20F", ""];
    for (const code of bad) {
      const response = await fetch(`${httpBase()}/v1/rooms/${code}?role=guest&rv=1`);
      assert.equal(response.status, 400, `コード "${code}"`);
      await response.body?.cancel();
    }
    assert.equal(await upgradeStatus(roomURL("abcdef", "host")), 400);
    assert.equal(await upgradeStatus(roomURL("ABCDE0", "guest")), 400);
  });

  test("role が host / guest 以外なら 400、WebSocket でなければ 426、知らない道は 404", async () => {
    assert.equal(await upgradeStatus(roomURL(randomCode(), "spectator")), 400);
    const noUpgrade = await fetch(`${httpBase()}/v1/rooms/${randomCode()}?role=host&rv=1`);
    assert.equal(noUpgrade.status, 426);
    await noUpgrade.body?.cancel();
    const unknown = await fetch(`${httpBase()}/v2/whatever`);
    assert.equal(unknown.status, 404);
    await unknown.body?.cancel();
  });
});

describe("部屋", { concurrency: false }, () => {
  after(closeAll);

  test("ホストと参加者が繋がり、GUEST_OPEN が 1 から振られる", async () => {
    const code = randomCode();
    const host = await openHost(code);
    const first = await openGuest(code, host, "guest1");
    const second = await openGuest(code, host, "guest2");
    assert.equal(first.id, 1);
    assert.equal(second.id, 2);
  });

  test("参加者 → ホストは GUEST_DATA、ホスト → 参加者は SEND の payload だけ（200 KiB も）", async () => {
    const code = randomCode();
    const host = await openHost(code);
    const guest1 = await openGuest(code, host, "guest1");
    const guest2 = await openGuest(code, host, "guest2");

    guest1.send(new Uint8Array([1, 2, 3]));
    const up = await host.nextFrame();
    assert.equal(up.type, GUEST_DATA);
    assert.equal(up.guestId, guest1.id);
    assert.deepEqual([...up.payload], [1, 2, 3]);

    const bigUp = new Uint8Array(randomBytes(200 * KIB));
    guest2.send(bigUp);
    const bigUpFrame = await host.nextFrame();
    assert.equal(bigUpFrame.type, GUEST_DATA);
    assert.equal(bigUpFrame.guestId, guest2.id);
    assert.ok(Buffer.from(bigUpFrame.payload).equals(Buffer.from(bigUp)), "200 KiB（参加者 → ホスト）が一致しない");

    // 宛先の参加者にだけ届く
    host.send(frame(SEND, guest2.id, new Uint8Array([9, 8, 7])));
    host.send(frame(SEND, guest1.id, new Uint8Array([42])));
    assert.deepEqual([...(await guest2.next())], [9, 8, 7]);
    assert.deepEqual([...(await guest1.next())], [42]);

    const bigDown = new Uint8Array(randomBytes(200 * KIB));
    host.send(frame(SEND, guest1.id, bigDown));
    const bigDownGot = await guest1.next();
    assert.ok(Buffer.from(bigDownGot).equals(Buffer.from(bigDown)), "200 KiB（ホスト → 参加者）が一致しない");
    await guest2.expectQuiet();

    // 順序が保たれる
    for (let i = 0; i < 20; i++) guest1.send(new Uint8Array([i]));
    for (let i = 0; i < 20; i++) {
      const got = await host.nextFrame();
      assert.equal(got.type, GUEST_DATA);
      assert.deepEqual([...got.payload], [i]);
    }
  });

  test("いない参加者宛ての SEND・KICK と空の payload は捨てられ、ホストは繋がったまま", async () => {
    const code = randomCode();
    const host = await openHost(code);
    const guest = await openGuest(code, host);
    host.send(frame(SEND, 999, new Uint8Array([1])));
    host.send(frame(KICK, 999));
    host.send(frame(SEND, guest.id)); // payload の無い SEND も捨てる
    guest.send(new Uint8Array(0)); // 空のバイナリはホストへ送らない
    guest.send(new Uint8Array([5]));
    const up = await host.nextFrame();
    assert.equal(up.type, GUEST_DATA);
    assert.deepEqual([...up.payload], [5]);
    await guest.expectQuiet();
  });

  test("KICK でその参加者だけが 4002 closed_by_host で閉じ、ホストに GUEST_CLOSE が届く", async () => {
    const code = randomCode();
    const host = await openHost(code);
    const kicked = await openGuest(code, host, "kicked");
    const stays = await openGuest(code, host, "stays");
    host.send(frame(KICK, kicked.id));
    assert.deepEqual(await kicked.closeEvent(), { code: 4002, reason: "closed_by_host" });
    const closed = await host.nextFrame();
    assert.deepEqual([closed.type, closed.guestId, closed.payload.byteLength], [GUEST_CLOSE, kicked.id, 0]);

    host.send(frame(SEND, stays.id, new Uint8Array([7])));
    assert.deepEqual([...(await stays.next())], [7]);
    await host.expectQuiet();
  });

  test("参加者が閉じるとホストに GUEST_CLOSE が 1 回だけ届く", async () => {
    const code = randomCode();
    const host = await openHost(code);
    const guest = await openGuest(code, host);
    guest.close(1000, "bye");
    await guest.closeEvent();
    const closed = await host.nextFrame();
    assert.deepEqual([closed.type, closed.guestId], [GUEST_CLOSE, guest.id]);
    await host.expectQuiet();
  });

  test("ホストが閉じると参加者は全員 4001 host_left で閉じ、その後の参加は 4004 no_room", async () => {
    const code = randomCode();
    const host = await openHost(code);
    const guests = [await openGuest(code, host, "guest1"), await openGuest(code, host, "guest2")];
    host.close(1000, "done");
    for (const guest of guests) assert.deepEqual(await guest.closeEvent(), { code: 4001, reason: "host_left" });
    await expectRejected(roomURL(code, "guest"), 4004, "no_room");
  });

  test("ホストがいる部屋へのホストは 4009 room_taken、元のホストはそのまま", async () => {
    const code = randomCode();
    const host = await openHost(code);
    await expectRejected(roomURL(code, "host"), 4009, "room_taken");
    const guest = await openGuest(code, host);
    guest.send(new Uint8Array([1]));
    assert.equal((await host.nextFrame()).type, GUEST_DATA);
  });

  test("同じ鍵（hk）のホストは、切れたのに気づかれていない前のホストと入れ替わり、参加者は 4001 で閉じる", async () => {
    const code = randomCode();
    const key = randomBytes(16).toString("hex");
    const stale = await openHost(code, key);
    const guest = await openGuest(code, stale, "guest");
    // 前のホストの接続が生きたまま（中継から見れば切れていない）、同じ鍵で別の接続が来る
    const fresh = await openHost(code, key);
    assert.deepEqual(await stale.closeEvent(), { code: 4011, reason: "host_replaced" });
    assert.deepEqual(await guest.closeEvent(), { code: 4001, reason: "host_left" });
    // 新しいホストは新しい参加者を受け入れ、前の参加者の番号は再利用しない
    const next = await openGuest(code, fresh, "next");
    assert.equal(next.id, guest.id + 1);
    next.send(new Uint8Array([7]));
    const up = await fresh.nextFrame();
    assert.deepEqual([up.type, up.guestId, [...up.payload]], [GUEST_DATA, next.id, [7]]);
    // 前のホストの接続からの送信は、もう誰にも届かない
    stale.send(frame(SEND, next.id, new Uint8Array([9])));
    await next.expectQuiet();
  });

  test("鍵（hk）が違う・無い・形式が不正なホストは入れ替われず 4009、元のホストと参加者はそのまま", async () => {
    const code = randomCode();
    const key = randomBytes(16).toString("hex");
    const host = await openHost(code, key);
    const guest = await openGuest(code, host, "guest");
    await expectRejected(roomURL(code, "host", "1", randomBytes(16).toString("hex")), 4009, "room_taken");
    await expectRejected(roomURL(code, "host"), 4009, "room_taken");
    await expectRejected(roomURL(code, "host", "1", "short"), 4009, "room_taken");
    // 鍵を付けずに開いたホストは、鍵付きでも入れ替えられない
    const code2 = randomCode();
    const keyless = await openHost(code2);
    await expectRejected(roomURL(code2, "host", "1", key), 4009, "room_taken");
    keyless.send(frame(KICK, 999));
    // 元のホストと参加者は繋がったまま
    guest.send(new Uint8Array([1]));
    assert.equal((await host.nextFrame()).type, GUEST_DATA);
  });

  test("ホストのいない部屋への参加は 4004 no_room", async () => {
    await expectRejected(roomURL(randomCode(), "guest"), 4004, "no_room");
  });

  test("33 人目の参加者は 4008 room_full、1 人抜ければまた入れる", async () => {
    const code = randomCode();
    const host = await openHost(code);
    const guests = [];
    for (let i = 0; i < 32; i++) guests.push(await openGuest(code, host, `guest${i + 1}`));
    assert.deepEqual(guests.map((guest) => guest.id), Array.from({ length: 32 }, (_, i) => i + 1));
    await expectRejected(roomURL(code, "guest"), 4008, "room_full");

    guests[0].close();
    const closed = await host.nextFrame();
    assert.deepEqual([closed.type, closed.guestId], [GUEST_CLOSE, 1]);
    const late = await openGuest(code, host, "late");
    assert.equal(late.id, 33);
  });

  test("rv が 1 でなければ受け入れてから 4010 relay_version（ホスト・参加者とも）", async () => {
    const code = randomCode();
    await expectRejected(roomURL(code, "host", "2"), 4010, "relay_version");
    await expectRejected(roomURL(code, "host", null), 4010, "relay_version");
    const host = await openHost(code);
    await expectRejected(roomURL(code, "guest", "0"), 4010, "relay_version");
    await host.expectQuiet();
  });

  test("256 KiB を超えるメッセージは 1009（参加者ならホストへ GUEST_CLOSE、ホストなら参加者へ host_left）", async () => {
    const code = randomCode();
    const host = await openHost(code);
    const exact = await openGuest(code, host, "exact");
    const over = await openGuest(code, host, "over");

    exact.send(new Uint8Array(MAX_MESSAGE));
    const ok = await host.nextFrame();
    assert.deepEqual([ok.type, ok.guestId, ok.payload.byteLength], [GUEST_DATA, exact.id, MAX_MESSAGE]);

    over.send(new Uint8Array(MAX_MESSAGE + 1));
    assert.equal((await over.closeEvent()).code, 1009);
    const closed = await host.nextFrame();
    assert.deepEqual([closed.type, closed.guestId], [GUEST_CLOSE, over.id]);

    host.send(new Uint8Array(MAX_MESSAGE + 1).fill(SEND, 0, 1));
    assert.equal((await host.closeEvent()).code, 1009);
    assert.deepEqual(await exact.closeEvent(), { code: 4001, reason: "host_left" });
  });

  test("ホストの不正な形式（短すぎる・未知の種類）は 1003 で閉じる", async () => {
    for (const bad of [new Uint8Array([SEND, 0, 0]), frame(0x99, 1), frame(GUEST_OPEN, 1), new Uint8Array(0)]) {
      const code = randomCode();
      const host = await openHost(code);
      const guest = await openGuest(code, host);
      host.send(bad);
      assert.equal((await host.closeEvent()).code, 1003, `枠 [${[...bad.subarray(0, 5)]}]`);
      assert.deepEqual(await guest.closeEvent(), { code: 4001, reason: "host_left" });
    }
  });

  test("テキストの ping には pong、それ以外のテキストは無視", async () => {
    const code = randomCode();
    const host = await openHost(code);
    const guest = await openGuest(code, host);
    host.send("ping");
    assert.equal(await host.next(), "pong");
    guest.send("ping");
    assert.equal(await guest.next(), "pong");

    guest.send("hello");
    guest.send(new Uint8Array([3]));
    const up = await host.nextFrame();
    assert.deepEqual([up.type, [...up.payload]], [GUEST_DATA, [3]]);
    host.send("hello");
    host.send(frame(SEND, guest.id, new Uint8Array([4])));
    assert.deepEqual([...(await guest.next())], [4]);
  });

  test("guestId は抜けた参加者・ホストの入れ替わりをまたいでも再利用しない", async () => {
    const code = randomCode();
    let host = await openHost(code);
    const first = await openGuest(code, host, "first");
    assert.equal(first.id, 1);
    first.close();
    assert.equal((await host.nextFrame()).type, GUEST_CLOSE);
    const second = await openGuest(code, host, "second");
    assert.equal(second.id, 2);

    // ホストが去って同じコードで戻る（部屋は残す）
    host.close();
    assert.deepEqual(await second.closeEvent(), { code: 4001, reason: "host_left" });
    await host.closeEvent();
    host = await openHost(code);
    const third = await openGuest(code, host, "third");
    assert.equal(third.id, 3);
    third.send(new Uint8Array([1]));
    const up = await host.nextFrame();
    assert.deepEqual([up.type, up.guestId], [GUEST_DATA, 3]);
  });
});

// ---- フレンドの受信箱 ----

function randomFriendCode() {
  let code = "";
  for (let i = 0; i < 8; i++) code += ALPHABET[randomInt(ALPHABET.length)];
  return code;
}

function randomKey() {
  return randomBytes(18).toString("base64url");
}

function inboxURL(code, key, rv = "1") {
  const query = new URLSearchParams({ key });
  if (rv !== null) query.set("rv", rv);
  return `${wsBase}/v1/inbox/${code}?${query}`;
}

/** 受信箱を開き、最初の hello を受け取る */
async function openInbox(code, key, label = `inbox ${code}`) {
  const peer = track(new Peer(inboxURL(code, key), label));
  await withTimeout(peer.opened, TIMEOUT_MS, `${label} の接続`);
  const hello = JSON.parse(await peer.next());
  assert.deepEqual(hello, { t: "hello", code });
  // 生存確認の ping（理由は Peer.open のコメント）
  peer.send("ping");
  assert.equal(await peer.next(), "pong", `${label}: 最初の ping に pong が返らない`);
  return peer;
}

async function nextJson(peer, ms) {
  return JSON.parse(await peer.next(ms));
}

/** 受信箱の消去（POST /v1/inbox/<code>/erase）。状態コードと本文を返す */
function eraseInbox(code, body, method = "POST") {
  return httpCall(`/v1/inbox/${code}/erase`, body, method);
}

describe("フレンドの受信箱", () => {
  after(closeAll);

  test("招待が相手に届き、差出人は中継が付ける", async () => {
    const aCode = randomFriendCode(), bCode = randomFriendCode();
    const a = await openInbox(aCode, randomKey(), "A");
    const b = await openInbox(bCode, randomKey(), "B");
    a.send(JSON.stringify({ t: "send", to: bCode, id: 7, m: { k: "partyInvite", room: "ABCDEF", from: "偽物" } }));
    assert.deepEqual(await nextJson(a), { t: "ack", id: 7, result: "delivered" });
    const msg = await nextJson(b);
    assert.equal(msg.t, "msg");
    assert.equal(msg.from, aCode);
    assert.equal(msg.m.room, "ABCDEF");
  });

  test("不在の相手へ queue 無しは offline、queue 付きは預かって繋いだ時に渡す", async () => {
    const aCode = randomFriendCode(), bCode = randomFriendCode();
    const bKey = randomKey();
    const a = await openInbox(aCode, randomKey(), "A");
    a.send(JSON.stringify({ t: "send", to: bCode, id: 1, m: { k: "partyInvite" } }));
    assert.deepEqual(await nextJson(a), { t: "ack", id: 1, result: "offline" });
    a.send(JSON.stringify({ t: "send", to: bCode, id: 2, queue: true, m: { k: "friendRequest", name: "A" } }));
    assert.deepEqual(await nextJson(a), { t: "ack", id: 2, result: "queued" });

    const b = track(new Peer(inboxURL(bCode, bKey), "B"));
    assert.deepEqual(await nextJson(b), { t: "hello", code: bCode });
    assert.deepEqual(await nextJson(b), { t: "msg", from: aCode, m: { k: "friendRequest", name: "A" } });
    await b.expectQuiet();
  });

  test("在席の問い合わせ", async () => {
    const aCode = randomFriendCode(), bCode = randomFriendCode(), cCode = randomFriendCode();
    const a = await openInbox(aCode, randomKey(), "A");
    await openInbox(bCode, randomKey(), "B");
    a.send(JSON.stringify({ t: "presence", codes: [bCode, cCode, "bad"] }));
    assert.deepEqual(await nextJson(a), { t: "presence", online: [bCode] });
  });

  test("在席の問い合わせに、相手が知らせた今の状態（ルーム中・試合中など）が載る（知らせていなければ載らない・知らない種類は捨てる）", async () => {
    const aCode = randomFriendCode(), bCode = randomFriendCode(), cCode = randomFriendCode();
    const a = await openInbox(aCode, randomKey(), "A");
    const b = await openInbox(bCode, randomKey(), "B");
    await openInbox(cCode, randomKey(), "C");
    b.send(JSON.stringify({ t: "status", s: "match", m: "ranked", at: 1_800_000_000_000 }));
    b.send(JSON.stringify({ t: "status", s: "bogus" }));
    await delay(200);
    a.send(JSON.stringify({ t: "presence", codes: [bCode, cCode] }));
    assert.deepEqual(await nextJson(a), {
      t: "presence", online: [bCode, cCode], status: { [bCode]: { s: "match", m: "ranked", at: 1_800_000_000_000 } },
    });
    // オンラインに戻ると status から外れる
    b.send(JSON.stringify({ t: "status", s: "online" }));
    await delay(200);
    a.send(JSON.stringify({ t: "presence", codes: [bCode] }));
    assert.deepEqual(await nextJson(a), { t: "presence", online: [bCode] });
  });

  test("コードの持ち主は最初の鍵で決まり、別の鍵は 4012 で断られる", async () => {
    const code = randomFriendCode();
    const first = await openInbox(code, randomKey(), "first");
    await expectRejected(inboxURL(code, randomKey()), 4012, "inbox_taken");
    first.close();
  });

  test("同じ鍵の再接続は古い接続を入れ替える", async () => {
    const code = randomFriendCode(), key = randomKey();
    const old = await openInbox(code, key, "old");
    const fresh = await openInbox(code, key, "fresh");
    assert.deepEqual(await old.closeEvent(), { code: 4011, reason: "host_replaced" });
    fresh.close();
  });

  test("自分宛てと不正な宛先は無視される", async () => {
    const code = randomFriendCode();
    const a = await openInbox(code, randomKey(), "A");
    a.send(JSON.stringify({ t: "send", to: code, id: 1, m: {} }));
    a.send(JSON.stringify({ t: "send", to: "bad", id: 2, m: {} }));
    await a.expectQuiet();
  });

  test("不正なコード・鍵・版数は断られる", async () => {
    assert.equal(await upgradeStatus(`${wsBase}/v1/inbox/ABC?key=${randomKey()}&rv=1`), 400);
    await expectRejected(`${wsBase}/v1/inbox/${randomFriendCode()}?key=short&rv=1`, 1003, "malformed");
    await expectRejected(inboxURL(randomFriendCode(), randomKey(), "99"), 4010, "relay_version");
  });

  test("同じ差出人の同じ申請は 1 通にまとまる", async () => {
    const aCode = randomFriendCode(), bCode = randomFriendCode();
    const a = await openInbox(aCode, randomKey(), "A");
    for (const id of [1, 2]) {
      a.send(JSON.stringify({ t: "send", to: bCode, id, queue: true, m: { k: "friendRequest", name: "A" } }));
      assert.deepEqual(await nextJson(a), { t: "ack", id, result: "queued" });
    }
    const b = track(new Peer(inboxURL(bCode, randomKey()), "B"));
    assert.deepEqual(await nextJson(b), { t: "hello", code: bCode });
    assert.deepEqual(await nextJson(b), { t: "msg", from: aCode, m: { k: "friendRequest", name: "A" } });
    await b.expectQuiet();
  });
});

describe("受信箱の消去と利用停止", () => {
  after(closeAll);

  test("持ち主の鍵で消すと接続は 4014 で閉じ、預かりも消え、コードは二度と使えない", async () => {
    const aCode = randomFriendCode(), bCode = randomFriendCode(), bKey = randomKey();
    const b = await openInbox(bCode, bKey, "B");
    b.close();
    await b.closeEvent();
    const a = await openInbox(aCode, randomKey(), "A");
    a.send(JSON.stringify({ t: "send", to: bCode, id: 1, queue: true, m: { k: "friendRequest", name: "A" } }));
    assert.deepEqual(await nextJson(a), { t: "ack", id: 1, result: "queued" });

    // 鍵が違えば消せない
    assert.equal((await eraseInbox(bCode, { key: randomKey() })).status, 403);
    const erased = await eraseInbox(bCode, { key: bKey });
    assert.equal(erased.status, 200);
    assert.deepEqual(erased.json, { ok: true, result: "erased" });

    // 同じ鍵でも別の鍵でも、もう繋げない。申請も預からない。消し直しは erased のまま
    await expectRejected(inboxURL(bCode, bKey), 4014, "inbox_erased");
    await expectRejected(inboxURL(bCode, randomKey()), 4014, "inbox_erased");
    a.send(JSON.stringify({ t: "send", to: bCode, id: 2, queue: true, m: { k: "friendRequest", name: "A" } }));
    assert.deepEqual(await nextJson(a), { t: "ack", id: 2, result: "offline" });
    assert.deepEqual((await eraseInbox(bCode, { key: randomKey() })).json, { ok: true, result: "erased" });
  });

  test("繋いでいる最中に消すと、その接続は 4014 inbox_erased で閉じる", async () => {
    const code = randomFriendCode(), key = randomKey();
    const peer = await openInbox(code, key, "connected");
    assert.deepEqual((await eraseInbox(code, { key })).json, { ok: true, result: "erased" });
    assert.deepEqual(await peer.closeEvent(), { code: 4014, reason: "inbox_erased" });
  });

  test("繋いだことのないコードは none（何も作らない。その後は普通に使える）", async () => {
    const code = randomFriendCode(), key = randomKey();
    assert.deepEqual((await eraseInbox(code, { key: randomKey() })).json, { ok: true, result: "none" });
    await openInbox(code, key, "fresh");
  });

  test("消去の要求の誤りは 400 / 405", async () => {
    const code = randomFriendCode();
    assert.equal((await eraseInbox("ABC", { key: randomKey() })).status, 400);
    assert.equal((await eraseInbox(code, { key: "short" })).status, 400);
    assert.equal((await eraseInbox(code, "{not json")).status, 400);
    assert.equal((await eraseInbox(code, {})).status, 400);
    assert.equal((await eraseInbox(code, null, "GET")).status, 405);
  });

  test("運営が利用を止めたコードは 4013 で断られる（消去はできる）", { skip: SUSPENDED_CODE === null && "配備済みの中継には止めたコードを渡せない" }, async () => {
    await expectRejected(inboxURL(SUSPENDED_CODE, randomKey()), 4013, "inbox_suspended");
    assert.deepEqual((await eraseInbox(SUSPENDED_CODE, { key: randomKey() })).json, { ok: true, result: "none" });
  });
});

// ---- ランク（アカウントごと） ----

/** シーズン（rank.ts の seasonAt と同じ定義: S42 は 2026-09-16 08:00 UTC から、91 日ごと。README.md「ランク」） */
const FIRST_SEASON = 42;
const SEASON_EPOCH_MS = Date.UTC(2026, 8, 16, 8);
const DAY_MS = 24 * 60 * 60 * 1000;
const SEASON_MS = 91 * DAY_MS;
function seasonAt(ms) {
  return ms >= SEASON_EPOCH_MS ? FIRST_SEASON + Math.floor((ms - SEASON_EPOCH_MS) / SEASON_MS) : FIRST_SEASON;
}
/** テストを流している今のシーズン（中継の応答の season） */
const SEASON_NOW = seasonAt(Date.now());

/** ランクの初期値（rank.ts の initialState。ウォリアー III・星 0・今のシーズン）。応答の state はいつもこの項目だけ */
const RANK_INITIAL = Object.freeze({
  tier: "warrior", division: 3, stars: 0, starPoints: 0, protectionPoints: 0,
  highestTier: "warrior", highestMythicStars: 0, wins: 0, losses: 0, season: SEASON_NOW,
});

/** ティアごとの満タン（rank.ts の STAR_POINT_CAP・PROTECTION_CAP。Fandom「Ranked」。ミシックには星上げポイントが無い） */
const STAR_POINT_CAP = { warrior: 100, elite: 200, master: 300, grandmaster: 500, epic: 700, legend: 1000, mythic: 0 };
const PROTECTION_CAP = { warrior: 100, elite: 200, master: 300, grandmaster: 500, epic: 700, legend: 1000, mythic: 1100 };
/** ティアの段位の数（最下段の番号） */
const DIVISIONS = { warrior: 3, elite: 3, master: 4, grandmaster: 5, epic: 5, legend: 5, mythic: 1 };

/** 初期値の一部を変えたランク */
function rankState(overrides = {}) {
  return { ...RANK_INITIAL, ...overrides };
}

/** アプリが seed で送る形（RankCloud の CloudRank。season は送らない） */
function cloudRank(overrides = {}) {
  const state = rankState(overrides);
  delete state.season;
  return state;
}

/** ランクの要求（POST /v1/rank/<code>/<op>） */
function rankCall(code, op, body, method = "POST") {
  return httpCall(`/v1/rank/${code}/${op}`, body, method);
}

/** 試したアカウント。最後に持ち主の鍵で消す（ランクには期限による自動の消去が無いので、配備済みの中継に流しても残さない） */
const rankAccounts = [];

/** 新しいアカウント（乱数のコードと鍵）を作り、アプリの起動時と同じく端末の記録を seed で預ける */
async function newRankAccount(local = cloudRank()) {
  const account = { code: randomFriendCode(), key: randomKey() };
  rankAccounts.push(account);
  const seeded = await rankCall(account.code, "seed", { key: account.key, state: local });
  assert.deepEqual([seeded.status, seeded.json], [200, { ok: true, state: rankState(local) }], `seed: ${seeded.text}`);
  return account;
}

function rankMatch({ code, key }, match) {
  return rankCall(code, "match", { key, match });
}

async function rankGet({ code, key }) {
  const got = await rankCall(code, "get", { key });
  assert.equal(got.status, 200, got.text);
  return got.json.state;
}

/** 試合 ID（アプリは "m_" + 36 進のハッシュ） */
function newMatchId() {
  return `m_${randomBytes(6).toString("hex")}`;
}

/** ティアの名前（表の見出し用） */
const TIER_NAME = {
  warrior: "ウォリアー", elite: "エリート", master: "マスター", grandmaster: "グランドマスター",
  epic: "エピック", legend: "レジェンド", mythic: "ミシック",
};
const NON_MYTHIC = Object.keys(STAR_POINT_CAP).filter((tier) => tier !== "mythic");

/**
 * ランクの規則（rank.ts の applyMatch。アプリの RankService.swift と同じ計算）。seed した記録から 1 試合する。
 * after は seed した記録から変わる項目（勝敗の数は試合から足す）、result は応答の result の before / after 以外。
 * 同じ表を中継（wrangler dev）と rank.ts の applyMatch の両方に流す。
 */
const RANK_RULES = [
  {
    name: "満星で勝つと次の段位の星 1（スターポイントの端数は四捨五入: 20 + 8.2 × 8 = 85.6 → 86）",
    seed: { tier: "elite", division: 2, stars: 4, highestTier: "elite" },
    match: { won: true, rating: 8.2, mvp: false },
    after: { division: 1, stars: 1, starPoints: 86 },
    result: { starPointsGain: 86, scoreBonus: 0, activeBonus: 0, protected: false },
  },
  {
    name: "ティアの最上段の満星で勝つと次のティアの最下段・星 1（最高到達も上がる）",
    seed: { tier: "elite", division: 1, stars: 4, highestTier: "elite" },
    match: { won: true, rating: 5, mvp: false },
    after: { tier: "master", division: 4, stars: 1, starPoints: 60, highestTier: "master" },
    result: { starPointsGain: 60, scoreBonus: 0, activeBonus: 0, protected: false },
  },
  {
    name: "星 0 で負けると 1 段位下の満星 −1（保護ポイントに 評価 × 3 + 5）",
    seed: { tier: "master", division: 3, stars: 0, highestTier: "master" },
    match: { won: false, rating: 8.2, mvp: false },
    after: { division: 4, stars: 3, protectionPoints: 30 },
    result: { starPointsGain: 0, scoreBonus: 25, activeBonus: 5, protected: false },
  },
  {
    name: "ティアの最下段・星 0 で負けても下のティアへは落ちない",
    seed: { tier: "grandmaster", division: 5, stars: 0, highestTier: "grandmaster" },
    match: { won: false, rating: 0, mvp: false },
    after: { protectionPoints: 5 },
    result: { starPointsGain: 0, scoreBonus: 0, activeBonus: 5, protected: false },
  },
  {
    name: "ウォリアーは負けても星が減らない（保護ポイントはたまる）",
    seed: { tier: "warrior", division: 2, stars: 2 },
    match: { won: false, rating: 10, mvp: false },
    after: { protectionPoints: 35 },
    result: { starPointsGain: 0, scoreBonus: 30, activeBonus: 5, protected: false },
  },
  {
    name: "エピックのスターポイントは 700 で星がもう 1 つ（MVP は +30: 690 + 178 → 星 +2・残り 168）",
    seed: { tier: "epic", division: 5, stars: 0, starPoints: 690, highestTier: "epic" },
    match: { won: true, rating: 16, mvp: true },
    after: { stars: 2, starPoints: 168 },
    result: { starPointsGain: 178, scoreBonus: 0, activeBonus: 0, protected: false },
  },
  {
    name: "満タンを 1 試合で 2 回越えても星のおまけは 1 つ（ウォリアー: 99 + 178 → 星 +2・残りは満タン未満の 99）",
    seed: { tier: "warrior", division: 3, stars: 0, starPoints: 99 },
    match: { won: true, rating: 16, mvp: true },
    after: { stars: 2, starPoints: 99 },
    result: { starPointsGain: 178, scoreBonus: 0, activeBonus: 0, protected: false },
  },
  {
    name: "レジェンドの保護ポイント 1000 で負けると星が減らず、保護ポイントは 0 に戻る",
    seed: { tier: "legend", division: 2, stars: 3, protectionPoints: 1000, highestTier: "legend" },
    match: { won: false, rating: 10, mvp: false },
    after: { protectionPoints: 0 },
    result: { starPointsGain: 0, scoreBonus: 30, activeBonus: 5, protected: true },
  },
  {
    name: "レジェンドは保護ポイント 700 では守らない（満タンは 1000。旧規則の全ティア 700 ではない）",
    seed: { tier: "legend", division: 2, stars: 3, protectionPoints: 700, highestTier: "legend" },
    match: { won: false, rating: 10, mvp: false },
    after: { stars: 2, protectionPoints: 735 },
    result: { starPointsGain: 0, scoreBonus: 30, activeBonus: 5, protected: false },
  },
  {
    name: "エピックの保護ポイントは満タンの 700 で止まる",
    seed: { tier: "epic", division: 3, stars: 2, protectionPoints: 690, highestTier: "epic" },
    match: { won: false, rating: 16, mvp: false },
    after: { stars: 1, protectionPoints: 700 },
    result: { starPointsGain: 0, scoreBonus: 48, activeBonus: 5, protected: false },
  },
  {
    name: "レジェンド I の満星で勝つとミシック星 0（ミシックにはスターポイントが無いので 0 にする）",
    seed: { tier: "legend", division: 1, stars: 5, starPoints: 100, highestTier: "legend" },
    match: { won: true, rating: 10, mvp: true },
    after: { tier: "mythic", division: 1, stars: 0, starPoints: 0, highestTier: "mythic" },
    result: { starPointsGain: 0, scoreBonus: 0, activeBonus: 0, protected: false },
  },
  {
    name: "ミシックの勝ちは星の累計 +1 で、最高の星も上がる",
    seed: { tier: "mythic", division: 1, stars: 24, highestTier: "mythic", highestMythicStars: 24 },
    match: { won: true, rating: 16, mvp: true },
    after: { stars: 25, highestMythicStars: 25 },
    result: { starPointsGain: 0, scoreBonus: 0, activeBonus: 0, protected: false },
  },
  {
    name: "ミシック星 0 で負けるとレジェンド I・星 4（ミシックでも保護ポイントはたまる。最高到達はミシックのまま）",
    seed: { tier: "mythic", division: 1, stars: 0, highestTier: "mythic", highestMythicStars: 7 },
    match: { won: false, rating: 10, mvp: false },
    after: { tier: "legend", division: 1, stars: 4, protectionPoints: 35 },
    result: { starPointsGain: 0, scoreBonus: 30, activeBonus: 5, protected: false },
  },
  {
    name: "ミシックからレジェンドへ落ちたら、保護ポイントはレジェンドの満タン 1000 に収める",
    seed: { tier: "mythic", division: 1, stars: 0, protectionPoints: 1000, highestTier: "mythic" },
    match: { won: false, rating: 16, mvp: false },
    after: { tier: "legend", division: 1, stars: 4, protectionPoints: 1000 },
    result: { starPointsGain: 0, scoreBonus: 48, activeBonus: 5, protected: false },
  },
  {
    name: "評価は 16 までに収める（99 は 16 と同じ。mvp を省けば MVP でない）",
    seed: { tier: "elite", division: 3, stars: 0, highestTier: "elite" },
    match: { won: true, rating: 99 },
    after: { stars: 1, starPoints: 148 },
    result: { starPointsGain: 148, scoreBonus: 0, activeBonus: 0, protected: false },
  },
  {
    name: "評価は 0 からに収める（-5 は 0 と同じ）",
    seed: { tier: "elite", division: 3, stars: 2, highestTier: "elite" },
    match: { won: false, rating: -5, mvp: false },
    after: { stars: 1, protectionPoints: 5 },
    result: { starPointsGain: 0, scoreBonus: 0, activeBonus: 5, protected: false },
  },
  // ティアごとの満タン（スターポイント: 満タン − 1 から評価 0 の勝ち（+20）で星 +2・残り 19、満タン − 21 からなら星 +1 だけ）
  ...NON_MYTHIC.flatMap((tier) => {
    const cap = STAR_POINT_CAP[tier];
    const seed = { tier, division: DIVISIONS[tier], stars: 0, highestTier: tier };
    const match = { won: true, rating: 0, mvp: false };
    const result = { starPointsGain: 20, scoreBonus: 0, activeBonus: 0, protected: false };
    return [
      {
        name: `${TIER_NAME[tier]}のスターポイントの満タンは ${cap}（${cap - 1} + 20 → 星 +2・残り 19）`,
        seed: { ...seed, starPoints: cap - 1 }, match, after: { stars: 2, starPoints: 19 }, result,
      },
      {
        name: `${TIER_NAME[tier]}のスターポイントは ${cap} 未満では星が増えない（${cap - 21} + 20 = ${cap - 1}）`,
        seed: { ...seed, starPoints: cap - 21 }, match, after: { stars: 1, starPoints: cap - 1 }, result,
      },
    ];
  }),
  // ティアごとの満タン（保護ポイント: 満タンで負けると星が減らずに 0 へ、満タン − 1 なら星が減って満タンで止まる）
  ...Object.keys(PROTECTION_CAP).flatMap((tier) => {
    const cap = PROTECTION_CAP[tier];
    const stars = tier === "mythic" ? 10 : 2;
    const seed = { tier, division: 1, stars, highestTier: tier, highestMythicStars: tier === "mythic" ? stars : 0 };
    const match = { won: false, rating: 0, mvp: false };
    return [
      {
        name: `${TIER_NAME[tier]}の保護ポイントの満タンは ${cap}（満タンで負けると星が減らない）`,
        seed: { ...seed, protectionPoints: cap }, match, after: { protectionPoints: 0 },
        result: { starPointsGain: 0, scoreBonus: 0, activeBonus: 5, protected: true },
      },
      {
        name: `${TIER_NAME[tier]}の保護ポイントが ${cap - 1} なら守らず、${cap} で止まる`,
        seed: { ...seed, protectionPoints: cap - 1 }, match,
        // ウォリアーはもともと星が減らない
        after: { stars: tier === "warrior" ? stars : stars - 1, protectionPoints: cap },
        result: { starPointsGain: 0, scoreBonus: 0, activeBonus: 5, protected: false },
      },
    ];
  }),
];

/** 規則の表の 1 行: seed した記録・試合の後の記録 */
function ruleStates(rule) {
  const before = rankState(rule.seed);
  const after = {
    ...before,
    ...rule.after,
    wins: before.wins + (rule.match.won ? 1 : 0),
    losses: before.losses + (rule.match.won ? 0 : 1),
  };
  return { before, after };
}

describe("ランク", () => {
  after(async () => {
    for (const { code, key } of rankAccounts.splice(0)) await rankCall(code, "erase", { key }).catch(() => {});
  });

  test("seed で端末の記録を預け、match の結果が保存され、get で同じ値が読める（応答は JSON・no-store）", async () => {
    const local = cloudRank({ tier: "epic", division: 2, stars: 1, starPoints: 300, highestTier: "epic", wins: 10, losses: 7 });
    const account = await newRankAccount(local);
    const start = rankState(local);

    const won = await rankMatch(account, { matchId: "m_happy001", won: true, rating: 10, mvp: true });
    assert.equal(won.status, 200);
    assert.equal(won.headers.get("cache-control"), "no-store");
    assert.match(won.headers.get("content-type") ?? "", /^application\/json/);
    const afterWin = { ...start, stars: 2, starPoints: 430, wins: 11 };
    assert.deepEqual(won.json, {
      ok: true,
      state: afterWin,
      result: { before: start, after: afterWin, starPointsGain: 130, scoreBonus: 0, activeBonus: 0, protected: false },
    });

    const lost = await rankMatch(account, { matchId: "m_happy002", won: false, rating: 8.2, mvp: false });
    const afterLoss = { ...afterWin, stars: 1, protectionPoints: 30, losses: 8 };
    assert.deepEqual(lost.json, {
      ok: true,
      state: afterLoss,
      result: { before: afterWin, after: afterLoss, starPointsGain: 0, scoreBonus: 25, activeBonus: 5, protected: false },
    });

    const got = await rankCall(account.code, "get", { key: account.key });
    assert.equal(got.headers.get("cache-control"), "no-store");
    assert.deepEqual(got.json, { ok: true, state: afterLoss });
  });

  test("get は記録を作らない。seed は記録が無い時だけ端末の値を取り込み（知らない項目は捨てる）、以後は今の記録を返す", async () => {
    const code = randomFriendCode(), key = randomKey();
    rankAccounts.push({ code, key });
    assert.deepEqual((await rankCall(code, "get", { key })).json, { ok: true, state: RANK_INITIAL });

    // 降格して最高到達より下にいる記録
    const local = cloudRank({
      tier: "grandmaster", division: 3, stars: 2, starPoints: 420, protectionPoints: 140,
      highestTier: "epic", wins: 31, losses: 25,
    });
    const seeded = await rankCall(code, "seed", { key, state: { ...local, nickname: "x" } });
    assert.equal(seeded.status, 200);
    assert.deepEqual(seeded.json, { ok: true, state: rankState(local) });

    // 2 回目からは、送った値（正しくても誤っていても、無くても）を見ずに今の記録を返す
    for (const state of [cloudRank({ tier: "mythic", division: 1, stars: 80 }), { tier: "bronze" }, undefined]) {
      const again = await rankCall(code, "seed", state === undefined ? { key } : { key, state });
      assert.deepEqual(again.json, { ok: true, state: rankState(local) }, `state: ${JSON.stringify(state)}`);
    }
    const played = await rankMatch({ code, key }, { matchId: "m_seed0001", won: true, rating: 8, mvp: false });
    assert.deepEqual((await rankCall(code, "seed", { key, state: local })).json, { ok: true, state: played.json.state });
  });

  test("応答の season は今のシーズン（S42 = 2026-09-16 08:00 UTC から 91 日ごと）。seed の season は省けば今のシーズン（旧版のアプリ）", async () => {
    assert.ok(SEASON_NOW >= FIRST_SEASON);
    const fresh = { code: randomFriendCode(), key: randomKey() };
    rankAccounts.push(fresh);
    assert.equal((await rankGet(fresh)).season, SEASON_NOW);
    // 旧版のアプリは season を送らない: 今のシーズンの記録として、下げずに取り込む
    const local = cloudRank({ tier: "legend", division: 3, stars: 4, starPoints: 950, protectionPoints: 1000, highestTier: "legend" });
    const account = await newRankAccount(local);
    assert.deepEqual(await rankGet(account), { ...local, season: SEASON_NOW });
    // 今のシーズンを送っても同じ
    const same = { code: randomFriendCode(), key: randomKey() };
    rankAccounts.push(same);
    const seeded = await rankCall(same.code, "seed", { key: same.key, state: { ...local, season: SEASON_NOW } });
    assert.deepEqual(seeded.json, { ok: true, state: { ...local, season: SEASON_NOW } });
  });

  test("seed の先のシーズンは次のシーズンまで（端末の時計が進んでいて、もう下げてある記録）。中継はシーズンを戻さない", async () => {
    const local = cloudRank({ tier: "epic", division: 3, stars: 0, highestTier: "mythic", wins: 2, losses: 1 });
    const account = { code: randomFriendCode(), key: randomKey() };
    rankAccounts.push(account);
    const seeded = await rankCall(account.code, "seed", { key: account.key, state: { ...local, season: SEASON_NOW + 7 } });
    assert.deepEqual(seeded.json, { ok: true, state: { ...local, season: SEASON_NOW + 1 } });
    const played = await rankMatch(account, { matchId: newMatchId(), won: true, rating: 8, mvp: false });
    assert.deepEqual(played.json.state, { ...local, stars: 1, starPoints: 84, wins: 3, season: SEASON_NOW + 1 });
  });

  test("旧版のアプリの値（全ティア 700 共通の頃のポイント）も seed で受け付け、ティアの満タンに収める", async () => {
    const cases = [
      [{ tier: "master", division: 4, stars: 1, starPoints: 699, protectionPoints: 700, highestTier: "master" },
        { starPoints: 299, protectionPoints: 300 }],
      [{ tier: "warrior", division: 2, stars: 1, starPoints: 650, protectionPoints: 120 }, { starPoints: 99, protectionPoints: 100 }],
      // ミシックにはスターポイントが無い（0 にする）。保護ポイントの満タンは 1100
      [{ tier: "mythic", division: 1, stars: 3, starPoints: 650, protectionPoints: 700, highestTier: "mythic", highestMythicStars: 3 },
        { starPoints: 0, protectionPoints: 700 }],
    ];
    for (const [old, fitted] of cases) {
      const account = { code: randomFriendCode(), key: randomKey() };
      rankAccounts.push(account);
      const seeded = await rankCall(account.code, "seed", { key: account.key, state: cloudRank(old) });
      assert.deepEqual([seeded.status, seeded.json], [200, { ok: true, state: rankState({ ...old, ...fitted }) }], JSON.stringify(old));
    }
  });

  for (const rule of RANK_RULES) {
    test(`規則: ${rule.name}`, async () => {
      const account = await newRankAccount(cloudRank(rule.seed));
      const response = await rankMatch(account, { matchId: newMatchId(), ...rule.match });
      const { before, after } = ruleStates(rule);
      assert.equal(response.status, 200, response.text);
      assert.deepEqual(response.json, { ok: true, state: after, result: { before, after, ...rule.result } });
    });
  }

  test("最高到達（highestTier・highestMythicStars）は降格しても下がらず、勝敗は数え続ける", async () => {
    const account = await newRankAccount(
      cloudRank({ tier: "mythic", division: 1, stars: 1, highestTier: "mythic", highestMythicStars: 1, wins: 40, losses: 30 }),
    );
    const steps = [
      [true, { tier: "mythic", stars: 2, highestTier: "mythic", highestMythicStars: 2 }],
      [false, { tier: "mythic", stars: 1, highestTier: "mythic", highestMythicStars: 2 }],
      [false, { tier: "mythic", stars: 0, highestTier: "mythic", highestMythicStars: 2 }],
      [false, { tier: "legend", division: 1, stars: 4, highestTier: "mythic", highestMythicStars: 2 }],
      [false, { tier: "legend", division: 1, stars: 3, highestTier: "mythic", highestMythicStars: 2 }],
    ];
    for (const [i, [won, expected]] of steps.entries()) {
      const { json } = await rankMatch(account, { matchId: newMatchId(), won, rating: 10, mvp: false });
      const got = Object.fromEntries(Object.keys(expected).map((k) => [k, json.state[k]]));
      assert.deepEqual(got, expected, `${i + 1} 試合目`);
    }
    const state = await rankGet(account);
    assert.deepEqual([state.wins, state.losses], [41, 34]);
  });

  test("seed の前の match は 409 not_seeded で数えない（ウォリアー III から数え直して端末のランクを上書きしない）", async () => {
    const account = { code: randomFriendCode(), key: randomKey() };
    rankAccounts.push(account);
    const early = await rankMatch(account, { matchId: newMatchId(), won: true, rating: 8, mvp: false });
    assert.deepEqual([early.status, early.text], [409, "not_seeded"]);
    // 後から届いた seed（端末の記録）はそのまま取り込まれ、その後の試合は数える
    const local = cloudRank({ tier: "epic", division: 3, stars: 2, highestTier: "epic" });
    const seeded = await rankCall(account.code, "seed", { key: account.key, state: local });
    assert.deepEqual([seeded.status, seeded.json], [200, { ok: true, state: rankState(local) }], seeded.text);
    const later = await rankMatch(account, { matchId: newMatchId(), won: true, rating: 8, mvp: false });
    assert.equal(later.status, 200, later.text);
    assert.equal(later.json.state.stars, 3);
  });

  test("同じ matchId の二重送信は最初の結果を返して数えない（中身が違っても）。state はその時の記録", async () => {
    const account = await newRankAccount();
    const first = await rankMatch(account, { matchId: "m_retry001", won: true, rating: 10, mvp: true });
    assert.equal(first.status, 200);
    const resent = await rankMatch(account, { matchId: "m_retry001", won: false, rating: 0, mvp: false });
    assert.deepEqual(resent.json, first.json);

    const other = await rankMatch(account, { matchId: "m_retry002", won: false, rating: 4, mvp: false });
    assert.deepEqual(other.json.result.before, first.json.state);
    const late = await rankMatch(account, { matchId: "m_retry001", won: true, rating: 10, mvp: true });
    assert.deepEqual(late.json, { ok: true, state: other.json.state, result: first.json.result });
    const state = await rankGet(account);
    assert.deepEqual(state, other.json.state);
    assert.deepEqual([state.wins, state.losses], [1, 1]);
  });

  test("同じ matchId を同時に送っても 1 回だけ数え、別々の試合を同時に送るとすべて 1 つずつ数える", async () => {
    const account = await newRankAccount();
    const same = await Promise.all(
      Array.from({ length: 8 }, () => rankMatch(account, { matchId: "m_burst000", won: true, rating: 8, mvp: false })),
    );
    for (const response of same) assert.deepEqual(response.json, same[0].json);
    assert.equal((await rankGet(account)).wins, 1);

    const distinct = await Promise.all(
      Array.from({ length: 8 }, (_, i) => rankMatch(account, { matchId: `m_burst${i + 1}00`, won: true, rating: 8, mvp: false })),
    );
    // 1 つずつ順に適用される（どの試合も、その前の試合の後の記録から数える）
    assert.deepEqual(distinct.map((response) => response.json.result.before.wins).sort((a, b) => a - b), [1, 2, 3, 4, 5, 6, 7, 8]);
    assert.equal((await rankGet(account)).wins, 9);
  });

  test("matchId を覚えるのは直近 50 試合まで（それより前の matchId は新しい試合として数える）", async () => {
    const account = await newRankAccount();
    const oldest = { matchId: "m_oldest01", won: true, rating: 8, mvp: false };
    assert.equal((await rankMatch(account, oldest)).status, 200);
    for (let i = 0; i < 49; i++) {
      const filler = await rankMatch(account, { matchId: `m_fill${String(i).padStart(4, "0")}`, won: false, rating: 8, mvp: false });
      assert.equal(filler.status, 200);
    }
    // 50 試合まではまだ覚えている
    assert.equal((await rankMatch(account, oldest)).json.state.wins, 1);
    // 51 試合目で最も古い matchId を忘れる
    assert.equal((await rankMatch(account, { matchId: "m_fill0049", won: false, rating: 8, mvp: false })).status, 200);
    const again = await rankMatch(account, oldest);
    assert.deepEqual([again.json.result.before.wins, again.json.state.wins, again.json.state.losses], [1, 2, 50]);
  });

  test("持ち主は最初の鍵で決まり、別の鍵は get / seed / match / erase とも 403 forbidden（記録は変わらない）", async () => {
    const account = await newRankAccount(cloudRank({ tier: "epic", division: 4, stars: 2, highestTier: "epic" }));
    assert.equal((await rankMatch(account, { matchId: "m_owner001", won: true, rating: 8, mvp: false })).status, 200);
    const state = await rankGet(account);
    const other = randomKey();
    const match = { matchId: "m_owner002", won: true, rating: 8, mvp: false };
    assertError(await rankCall(account.code, "get", { key: other }), 403, "forbidden", "get");
    assertError(await rankCall(account.code, "seed", { key: other, state: cloudRank() }), 403, "forbidden", "seed");
    assertError(await rankCall(account.code, "match", { key: other, match }), 403, "forbidden", "match");
    assertError(await rankCall(account.code, "erase", { key: other }), 403, "forbidden", "erase");
    assert.deepEqual(await rankGet(account), state);
    // 断られた matchId は覚えていないので、持ち主が送れば数える
    assert.deepEqual((await rankMatch(account, match)).json.result.before, state);
  });

  test("使い始めのコードに別々の鍵が同時に来ても、持ち主は 1 人だけ", async () => {
    const code = randomFriendCode();
    const keys = Array.from({ length: 6 }, () => randomKey());
    const responses = await Promise.all(keys.map((key) => rankCall(code, "get", { key })));
    const owners = keys.filter((_, i) => responses[i].status === 200);
    assert.equal(owners.length, 1, `200 は 1 つだけのはず: ${responses.map((r) => r.status)}`);
    rankAccounts.push({ code, key: owners[0] });
    for (const response of responses) if (response.status !== 200) assertError(response, 403, "forbidden");
    assert.equal((await rankCall(code, "get", { key: owners[0] })).status, 200);
  });

  test("erase は持ち主の鍵で記録・持ち主・覚えている matchId を消す（以後は初期のランクで、seed し直せる）", async () => {
    const local = cloudRank({ tier: "legend", division: 2, stars: 3, highestTier: "legend", wins: 50, losses: 40 });
    const account = await newRankAccount(local);
    const played = await rankMatch(account, { matchId: "m_erase001", won: true, rating: 8, mvp: false });
    assert.equal(played.status, 200);

    // 鍵が違えば消せない
    assertError(await rankCall(account.code, "erase", { key: randomKey() }), 403, "forbidden");
    assert.deepEqual(await rankGet(account), played.json.state);

    const erased = await rankCall(account.code, "erase", { key: account.key });
    assert.equal(erased.status, 200);
    assert.equal(erased.headers.get("cache-control"), "no-store");
    assert.deepEqual(erased.json, { ok: true, state: RANK_INITIAL });
    assert.deepEqual(await rankGet(account), RANK_INITIAL);
    // 記録が無いので seed で取り込み直せ、消す前の matchId も新しい試合として数える
    assert.deepEqual((await rankCall(account.code, "seed", { key: account.key, state: local })).json, { ok: true, state: rankState(local) });
    const again = await rankMatch(account, { matchId: "m_erase001", won: true, rating: 8, mvp: false });
    assert.deepEqual([again.json.result.before, again.json.state.wins], [rankState(local), 51]);

    // コードの持ち主（受信箱と同じ鍵）は残る: ランクを消しても別の鍵では使えない（他人にコードを渡さない）。同じ鍵ならまた使える
    assert.equal((await rankCall(account.code, "erase", { key: account.key })).status, 200);
    assertError(await rankCall(account.code, "get", { key: randomKey() }), 403, "forbidden");
    assert.deepEqual(await rankGet(account), RANK_INITIAL);
  });

  test("使ったことのないコードの erase と消し直しも 200（何も残さない）", async () => {
    const code = randomFriendCode(), key = randomKey();
    for (let i = 0; i < 2; i++) {
      const erased = await rankCall(code, "erase", { key });
      assert.deepEqual([erased.status, erased.json], [200, { ok: true, state: RANK_INITIAL }], `${i + 1} 回目`);
    }
    const next = { code, key: randomKey() };
    rankAccounts.push(next);
    assert.deepEqual(await rankGet(next), RANK_INITIAL);
  });

  test("コードの誤りは 400 bad_friend_code、鍵の誤りは 400 bad_key（鍵は 16〜64 文字の英数・_・-）", async () => {
    const key = randomKey();
    for (const code of ["ABC", "ABCDEFGHJ", "abcdefgh", "ABCDEFG0", "ABCDEFG1", "ABCDEFGI", "ABCDEFGL", "ABCDEFGO", "ABCD-FGH", ""]) {
      assertError(await rankCall(code, "get", { key }), 400, "bad_friend_code", `コード "${code}"`);
    }
    const code = randomFriendCode();
    const bodies = [
      {}, null, [], JSON.stringify("key"), { key: null }, { key: 1234567890123456 },
      { key: "short" }, { key: "k".repeat(15) }, { key: "k".repeat(65) }, { key: `${"k".repeat(15)}!` },
    ];
    for (const body of bodies) {
      assertError(await rankCall(code, "get", body), 400, "bad_key", `本文 ${JSON.stringify(body)}`);
    }
    // 16 文字・64 文字の境目は受け付ける
    for (const length of [16, 64]) {
      const account = { code: randomFriendCode(), key: "k".repeat(length) };
      rankAccounts.push(account);
      assert.equal((await rankCall(account.code, "get", { key: account.key })).status, 200, `鍵 ${length} 文字`);
    }
  });

  test("本文の誤り（JSON でない・4 KiB 超）は 400 bad_request、POST 以外は 405（Allow: POST）、知らない道は 404", async () => {
    const account = { code: randomFriendCode(), key: randomKey() };
    rankAccounts.push(account);
    for (const body of ["{not json", "", "{\"key\":"]) {
      assertError(await rankCall(account.code, "get", body), 400, "bad_request", `本文 ${JSON.stringify(body)}`);
    }
    // 本文は 4 KiB まで（ちょうど 4096 バイトは受け付ける）
    const padded = (length) => {
      const head = `{"key":"${account.key}","pad":"`;
      return `${head}${"x".repeat(length - head.length - 2)}"}`;
    };
    assert.equal((await rankCall(account.code, "get", padded(4096))).status, 200);
    assertError(await rankCall(account.code, "get", padded(4097)), 400, "bad_request");

    for (const method of ["GET", "PUT", "DELETE"]) {
      const response = await rankCall(account.code, "get", undefined, method);
      assertError(response, 405, "method_not_allowed", method);
      assert.equal(response.headers.get("allow"), "POST", method);
    }
    const base = `/v1/rank/${account.code}`;
    for (const path of [`${base}/delete`, `${base}/GET`, `${base}/get/`, base, "/v1/rank"]) {
      assertError(await httpCall(path, { key: account.key }), 404, "not_found", path);
    }
  });

  test("match の誤りは 400 bad_request で数えない（matchId は 8〜64 文字の英数・_・- の文字列、won は真偽、rating は数）", async () => {
    const account = await newRankAccount();
    const ok = { matchId: "m_valid001", won: true, rating: 8, mvp: false };
    const bad = [
      undefined, null, "m_valid001", [],
      { ...ok, matchId: undefined }, { ...ok, matchId: 12345678 }, { ...ok, matchId: ["m_valid001"] },
      { ...ok, matchId: "m_short" }, { ...ok, matchId: `m_${"x".repeat(63)}` }, { ...ok, matchId: "m_bad id!" },
      // Object.prototype の名前（覚えている matchId の引き当てを誤る）
      ...["__proto__", "toString", "constructor", "hasOwnProperty"].map((matchId) => ({ ...ok, matchId })),
      { ...ok, won: undefined }, { ...ok, won: "true" }, { ...ok, won: 1 },
      { ...ok, rating: undefined }, { ...ok, rating: "8" }, { ...ok, rating: null },
    ];
    for (const match of bad) {
      const body = match === undefined ? { key: account.key } : { key: account.key, match };
      assertError(await rankCall(account.code, "match", body), 400, "bad_request", `match: ${JSON.stringify(match)}`);
    }
    assert.deepEqual(await rankGet(account), RANK_INITIAL);
    // 8 文字・64 文字の境目は受け付ける
    for (const matchId of ["m_8chars", `m_${"x".repeat(62)}`]) {
      assert.equal((await rankMatch(account, { ...ok, matchId })).status, 200, matchId);
    }
    assert.equal((await rankGet(account)).wins, 2);
  });

  test("seed の誤りは 400 bad_request で取り込まない（ティア・段位・星は規則の範囲、ほかは 0 以上の整数）", async () => {
    const ok = cloudRank({ tier: "master", division: 4, stars: 4, highestTier: "master" });
    await newRankAccount(ok);
    const code = randomFriendCode(), key = randomKey();
    rankAccounts.push({ code, key });
    const bad = [
      undefined, null, "master", [],
      { ...ok, tier: undefined }, { ...ok, tier: "bronze" }, { ...ok, highestTier: "bronze" },
      { ...ok, division: undefined }, { ...ok, division: 0 }, { ...ok, division: 5 }, { ...ok, division: 2.5 }, { ...ok, division: "2" },
      { ...ok, stars: undefined }, { ...ok, stars: -1 }, { ...ok, stars: 5 }, { ...ok, stars: 1.5 },
      { ...ok, tier: "mythic", division: 2, stars: 30 },
      // ポイントはどのティアでもスターポイント 999・保護ポイント 1500 まで（ティアの満タンを越える分は取り込む時に収める）
      { ...ok, starPoints: 1000 }, { ...ok, starPoints: -1 }, { ...ok, starPoints: "abc" },
      { ...ok, protectionPoints: 1501 }, { ...ok, protectionPoints: -1 },
      { ...ok, highestMythicStars: "3" }, { ...ok, wins: -1 }, { ...ok, losses: 1.5 },
      { ...ok, season: -1 }, { ...ok, season: 42.5 }, { ...ok, season: "42" },
    ];
    for (const state of bad) {
      const body = state === undefined ? { key } : { key, state };
      assertError(await rankCall(code, "seed", body), 400, "bad_request", `state: ${JSON.stringify(state)}`);
    }
    // 取り込んでいないので、正しい記録はまだ seed できる（ミシックの星は累計で上限なし）
    const mythic = cloudRank({ tier: "mythic", division: 1, stars: 130, highestTier: "mythic", highestMythicStars: 130 });
    assert.deepEqual((await rankCall(code, "seed", { key, state: mythic })).json, { ok: true, state: rankState(mythic) });
  });

  test("運営が利用を止めたコードは get / seed / match が 403 suspended（消去はできる）", { skip: SUSPENDED_CODE === null && "配備済みの中継には止めたコードを渡せない" }, async () => {
    const key = randomKey();
    assertError(await rankCall(SUSPENDED_CODE, "get", { key }), 403, "suspended", "get");
    assertError(await rankCall(SUSPENDED_CODE, "seed", { key, state: cloudRank() }), 403, "suspended", "seed");
    const match = { matchId: newMatchId(), won: true, rating: 8, mvp: false };
    assertError(await rankCall(SUSPENDED_CODE, "match", { key, match }), 403, "suspended", "match");
    const erased = await rankCall(SUSPENDED_CODE, "erase", { key });
    assert.deepEqual([erased.status, erased.json], [200, { ok: true, state: RANK_INITIAL }]);
  });

  test("ランクの道は rv（中継の版数）を見ない。版は道の /v1 で、ほかの版の道は 404", async () => {
    const account = await newRankAccount();
    // アプリの RankCloud は rv を付けない（rv を見るのは WebSocket の接続だけ）
    for (const query of ["", "?rv=1", "?rv=99"]) {
      const got = await httpCall(`/v1/rank/${account.code}/get${query}`, { key: account.key });
      assert.deepEqual([got.status, got.json], [200, { ok: true, state: RANK_INITIAL }], `"${query}"`);
    }
    assertError(await httpCall(`/v2/rank/${account.code}/get`, { key: account.key }), 404, "not_found");
  });
});

// ---- ランクの規則とシーズンの切り替え（rank.ts を直接。時計と保存先を差し替える） ----

/**
 * rank.ts を wrangler と同じ esbuild で 1 つの ES モジュールにまとめて読み込む。cloudflare:workers は Node に無いので、
 * DurableObject を ctx・env を持つだけの代役に替える（本物の Worker の結合テストは上の「ランク」）。
 */
async function importRankModule() {
  const { build } = await import("esbuild");
  const bundled = await build({
    entryPoints: [join(RELAY_DIR, "src", "rank.ts")],
    bundle: true,
    format: "esm",
    platform: "neutral",
    target: "es2022",
    write: false,
    logLevel: "silent",
    plugins: [{
      name: "cloudflare-workers-stand-in",
      setup(b) {
        b.onResolve({ filter: /^cloudflare:workers$/ }, (args) => ({ path: args.path, namespace: "stand-in" }));
        b.onLoad({ filter: /.*/, namespace: "stand-in" }, () => ({
          contents: "export class DurableObject { constructor(ctx, env) { this.ctx = ctx; this.env = env; } }",
          loader: "js",
        }));
      },
    }],
  });
  return import(`data:text/javascript;base64,${Buffer.from(bundled.outputFiles[0].text).toString("base64")}`);
}

/** 持ち主の鍵のハッシュ（64 桁の 16 進） */
const OWNER_HASH = "a".repeat(64);

/** 時計（clock.ms）と保存先（Map。Durable Object と同じく値を複製して出し入れする）を差し替えた RankAccount */
function clockedRankAccount(rank, clock) {
  const kv = new Map();
  const ctx = {
    storage: {
      kv: {
        get: (key) => (kv.has(key) ? structuredClone(kv.get(key)) : undefined),
        put: (key, value) => void kv.set(key, structuredClone(value)),
      },
      deleteAll: async () => kv.clear(),
    },
  };
  class ClockedRankAccount extends rank.RankAccount {
    now() {
      return clock.ms;
    }
  }
  return { account: new ClockedRankAccount(ctx, {}), kv };
}

describe("ランクの規則とシーズン（rank.ts を直接）", () => {
  let rank;
  before(async () => {
    rank = await importRankModule();
  });

  test("満タンはティアごと（スター 100/200/300/500/700/1000・ミシック無し、保護は同じ値・ミシック 1100）", () => {
    assert.deepEqual({ ...rank.STAR_POINT_CAP }, STAR_POINT_CAP);
    assert.deepEqual({ ...rank.PROTECTION_CAP }, PROTECTION_CAP);
  });

  for (const rule of RANK_RULES) {
    test(`規則（applyMatch）: ${rule.name}`, () => {
      const { before, after } = ruleStates(rule);
      const result = rank.applyMatch(before, { matchId: "m_unit0001", ...rule.match });
      assert.deepEqual(result, { before, after, ...rule.result });
    });
  }

  test("シーズンの境目: S42 は 2026-09-16 08:00 UTC から 91 日ごと（S43 は 2026-12-16、S44 は 2027-03-17 の 08:00 UTC）", () => {
    assert.equal(rank.FIRST_SEASON, FIRST_SEASON);
    assert.equal(new Date(rank.SEASON_EPOCH_MS).toISOString(), "2026-09-16T08:00:00.000Z");
    assert.equal(rank.SEASON_MS, 91 * DAY_MS);
    const cases = [
      ["2026-01-01T00:00:00.000Z", 42], // シーズン制の前は S42
      ["2026-09-16T07:59:59.999Z", 42],
      ["2026-09-16T08:00:00.000Z", 42],
      ["2026-10-21T00:00:00.000Z", 42],
      ["2026-12-16T07:59:59.999Z", 42],
      ["2026-12-16T08:00:00.000Z", 43],
      ["2027-03-17T07:59:59.999Z", 43],
      ["2027-03-17T08:00:00.000Z", 44],
      ["2027-06-16T08:00:00.000Z", 45],
    ];
    for (const [iso, season] of cases) {
      assert.equal(rank.seasonAt(Date.parse(iso)), season, iso);
      assert.equal(seasonAt(Date.parse(iso)), season, `テスト側の計算 ${iso}`);
    }
    assert.equal(new Date(rank.seasonStartMs(43)).toISOString(), "2026-12-16T08:00:00.000Z");
    assert.equal(new Date(rank.seasonStartMs(44)).toISOString(), "2027-03-17T08:00:00.000Z");
    assert.equal(rank.seasonStartMs(1), rank.SEASON_EPOCH_MS, "S42 より前の番号は S42");
  });

  test("新しいシーズンの開始位置（前のシーズンの最終ランクから。ミシックは星の累計で決まる）", () => {
    const table = [
      // [ティア, 段位, 星] → [ティア, 段位, 星]（星は I ミシックだけ 1、ほかは 0 から）
      [["warrior", 3, 2], ["warrior", 3, 0]], [["warrior", 2, 1], ["warrior", 2, 0]], [["warrior", 1, 3], ["warrior", 1, 0]],
      [["elite", 3, 4], ["elite", 3, 0]], [["elite", 2, 0], ["elite", 2, 0]], [["elite", 1, 4], ["elite", 1, 0]],
      [["master", 4, 0], ["elite", 1, 0]], [["master", 3, 4], ["elite", 1, 0]], [["master", 2, 1], ["master", 4, 0]], [["master", 1, 4], ["master", 3, 0]],
      [["grandmaster", 5, 0], ["master", 2, 0]], [["grandmaster", 4, 5], ["master", 1, 0]], [["grandmaster", 3, 0], ["grandmaster", 5, 0]],
      [["grandmaster", 2, 3], ["grandmaster", 4, 0]], [["grandmaster", 1, 5], ["grandmaster", 3, 0]],
      [["epic", 5, 0], ["grandmaster", 2, 0]], [["epic", 4, 2], ["grandmaster", 1, 0]], [["epic", 3, 5], ["epic", 5, 0]],
      [["epic", 2, 0], ["epic", 5, 0]], [["epic", 1, 5], ["epic", 4, 0]],
      [["legend", 5, 0], ["epic", 4, 0]], [["legend", 4, 1], ["epic", 3, 0]], [["legend", 3, 2], ["epic", 3, 0]],
      [["legend", 2, 3], ["epic", 3, 0]], [["legend", 1, 5], ["epic", 3, 0]],
      [["mythic", 1, 0], ["epic", 2, 0]], [["mythic", 1, 24], ["epic", 2, 0]],
      [["mythic", 1, 25], ["epic", 2, 0]], [["mythic", 1, 49], ["epic", 2, 0]],
      [["mythic", 1, 50], ["epic", 2, 0]], [["mythic", 1, 99], ["epic", 2, 0]],
      [["mythic", 1, 100], ["epic", 1, 1]], [["mythic", 1, 800], ["epic", 1, 1]],
    ];
    for (const [[tier, division, stars], expected] of table) {
      assert.deepEqual(rank.seasonResetPlace({ tier, division, stars }), expected, `${tier} ${division} ★${stars}`);
    }
  });

  test("rollover: 前のシーズンの記録を 1 回だけ下げ、星・ポイント・勝敗を 0 に（最高到達はそのまま）。二度目・先のシーズンは何もしない", () => {
    const s42 = {
      tier: "mythic", division: 1, stars: 37, starPoints: 0, protectionPoints: 900,
      highestTier: "mythic", highestMythicStars: 61, wins: 80, losses: 52, season: 42,
    };
    const s43 = rank.rollover(s42, 43);
    assert.deepEqual(s43, { ...s42, tier: "epic", division: 2, stars: 0, protectionPoints: 0, wins: 0, losses: 0, season: 43 });
    assert.equal(rank.rollover(s43, 43), s43, "同じシーズンへは同じ記録（二度下げない）");
    assert.deepEqual(rank.rollover(s42, 47), { ...s43, season: 47 }, "何シーズン空いても下げるのは 1 回");
    assert.equal(rank.rollover(s43, 42), s43, "先のシーズンの記録は戻さない");
    // シーズン制の前の記録（season 1）は S42 として読む
    const legacy = { ...s42, season: 1 };
    assert.deepEqual(rank.rollover(legacy, 42), s42);
    assert.deepEqual(rank.rollover(legacy, 43), s43);
    const { season: _season, ...noSeason } = s42;
    assert.deepEqual(rank.rollover(noSeason, 43), s43, "season の無い記録も S42 として読む");
  });

  test("新しいシーズンの最初の get で下げて保存し、新しい番号を返す（二度目からは同じ記録。seed も今の記録を返す）", async () => {
    const clock = { ms: Date.parse("2026-12-01T00:00:00Z") }; // S42
    const { account, kv } = clockedRankAccount(rank, clock);
    const local = cloudRank({
      tier: "legend", division: 2, stars: 3, starPoints: 640, protectionPoints: 120,
      highestTier: "mythic", highestMythicStars: 12, wins: 44, losses: 30,
    });
    assert.deepEqual(await account.seed(OWNER_HASH, local), { ok: true, state: { ...local, season: 42 } });
    clock.ms = Date.parse("2026-12-16T08:00:00Z"); // S43 の始まり
    const reset = { ...local, tier: "epic", division: 3, stars: 0, starPoints: 0, protectionPoints: 0, wins: 0, losses: 0, season: 43 };
    assert.deepEqual(await account.get(OWNER_HASH), { ok: true, state: reset });
    assert.deepEqual(kv.get("rank"), reset, "下げた記録を保存する");
    assert.deepEqual(await account.get(OWNER_HASH), { ok: true, state: reset }, "二度目は下げない");
    assert.deepEqual(await account.seed(OWNER_HASH, local), { ok: true, state: reset }, "記録があれば seed は今の記録を返す");
  });

  test("新しいシーズンの最初の match は、下げてから試合を数える（result.before は下げた記録。同じ matchId は数え直さない）", async () => {
    const clock = { ms: Date.parse("2027-03-17T07:00:00Z") }; // S43 の終わり
    const { account } = clockedRankAccount(rank, clock);
    await account.seed(OWNER_HASH, cloudRank({ tier: "mythic", division: 1, stars: 55, highestTier: "mythic", highestMythicStars: 60, wins: 70, losses: 40 }));
    clock.ms = Date.parse("2027-03-17T08:00:00Z"); // S44
    const match = { matchId: "m_season01", won: true, rating: 8, mvp: false };
    const played = await account.match(OWNER_HASH, match);
    const reset = rankState({ tier: "epic", division: 2, stars: 0, highestTier: "mythic", highestMythicStars: 60, season: 44 });
    const after = { ...reset, stars: 1, starPoints: 84, wins: 1 };
    assert.deepEqual(played, {
      ok: true, state: after, result: { before: reset, after, starPointsGain: 84, scoreBonus: 0, activeBonus: 0, protected: false },
    });
    assert.deepEqual(await account.match(OWNER_HASH, match), played);
  });

  test("seed: 前のシーズンの端末の記録は下げてから取り込む。season を省けば今のシーズン、先のシーズンは次のシーズンまで", async () => {
    const clock = { ms: Date.parse("2026-12-20T00:00:00Z") }; // S43
    const legend = cloudRank({ tier: "legend", division: 5, stars: 2, starPoints: 300, highestTier: "legend", wins: 9, losses: 8 });
    const lowered = { ...legend, tier: "epic", division: 4, stars: 0, starPoints: 0, wins: 0, losses: 0, season: 43 };
    const fromS42 = clockedRankAccount(rank, clock).account;
    assert.deepEqual(await fromS42.seed(OWNER_HASH, { ...legend, season: 42 }), { ok: true, state: lowered });
    const legacy = clockedRankAccount(rank, clock).account; // シーズン制の前の番号は S42
    assert.deepEqual(await legacy.seed(OWNER_HASH, { ...legend, season: 1 }), { ok: true, state: lowered });
    const oldApp = clockedRankAccount(rank, clock).account; // 旧版のアプリは season を送らない: 今のシーズンの記録
    assert.deepEqual(await oldApp.seed(OWNER_HASH, legend), { ok: true, state: { ...legend, season: 43 } });

    // 端末の時計が進んでいて、もう S44 へ下げてある記録: S44 になっても下げない（二度下げない）。S45 で下げる
    const ahead = clockedRankAccount(rank, clock).account;
    assert.deepEqual(await ahead.seed(OWNER_HASH, { ...legend, season: 50 }), { ok: true, state: { ...legend, season: 44 } });
    clock.ms = Date.parse("2027-03-17T08:00:00Z"); // S44
    assert.deepEqual(await ahead.get(OWNER_HASH), { ok: true, state: { ...legend, season: 44 } });
    clock.ms = Date.parse("2027-06-16T08:00:00Z"); // S45
    assert.deepEqual(await ahead.get(OWNER_HASH), { ok: true, state: { ...lowered, season: 45 } });
  });

  test("記録の無い get は今のシーズンの初期値（記録は作らない）。seed の前の match は数えず、erase の後も今のシーズン", async () => {
    const clock = { ms: Date.parse("2027-01-05T00:00:00Z") }; // S43
    const { account, kv } = clockedRankAccount(rank, clock);
    const initial = { ...RANK_INITIAL, season: 43 };
    assert.deepEqual(await account.get(OWNER_HASH), { ok: true, state: initial });
    assert.equal(kv.has("rank"), false);
    assert.deepEqual(await account.match(OWNER_HASH, { matchId: "m_season02", won: true, rating: 8, mvp: false }),
      { ok: false, error: "not_seeded" });
    assert.deepEqual(await account.seed(OWNER_HASH, cloudRank()), { ok: true, state: initial });
    assert.deepEqual(await account.erase(OWNER_HASH), { ok: true, state: initial });
    assert.equal(kv.size, 0);
  });
});


// ---- 名刺・ランキング・運営からのメール（Directory） ----

/** 名刺の要求（POST /v1/profile/<code>/<op>） */
function profileCall(code, op, body) {
  return httpCall(`/v1/profile/${code}/${op}`, body);
}

/** 正しい名刺（一部を変えられる） */
function card(overrides = {}) {
  return {
    name: "テスト", avatar: "H027", frame: null, level: 12, country: "JP",
    heroes: [{ heroID: "H027", matches: 20, wins: 12 }], matches: 40, wins: 22, ...overrides,
  };
}

describe("名刺・ランキング・運営からのメール", () => {
  /** 試したアカウント（最後に名刺とランクを消す） */
  const accounts = [];
  after(async () => {
    for (const { code, key } of accounts.splice(0)) {
      await profileCall(code, "erase", { key }).catch(() => {});
      await rankCall(code, "erase", { key }).catch(() => {});
    }
  });

  /** ランクを預けて（seed）名刺を置いたアカウント */
  async function newCardAccount(rank = cloudRank(), overrides = {}) {
    const account = { code: randomFriendCode(), key: randomKey() };
    accounts.push(account);
    const seeded = await rankCall(account.code, "seed", { key: account.key, state: rank });
    assert.equal(seeded.status, 200, seeded.text);
    const put = await profileCall(account.code, "put", { key: account.key, profile: card(overrides) });
    assert.equal(put.status, 200, put.text);
    return account;
  }

  test("名刺を置いて、まとめて読める（ランクは中継の記録。自己申告のランクは受け取らない）。消すと読めない", async () => {
    const account = { code: randomFriendCode(), key: randomKey() };
    accounts.push(account);
    const put = await profileCall(account.code, "put", { key: account.key, profile: { ...card(), rank: { tier: 6, division: 0, stars: 999 } } });
    assert.equal(put.status, 200, put.text);
    assert.equal(put.headers.get("cache-control"), "no-store");
    const p = put.json.profile;
    assert.equal(p.code, account.code);
    assert.equal(p.name, "テスト");
    assert.deepEqual(p.rank, { tier: 0, division: 3, stars: 0 }, "ランクは送った値でなく初期値");
    assert.match(p.updatedAt, /^\d{4}-\d{2}-\d{2}T/);
    const read = await httpCall("/v1/profiles", { codes: [account.code, randomFriendCode(), "bad"] });
    assert.equal(read.status, 200, read.text);
    assert.deepEqual(read.json.profiles.map((x) => x.code), [account.code], "名刺のあるコードだけ");
    assert.ok(read.json.profiles[0].lastSeen, "最終ログイン（受信箱の最後の利用）");
    const erased = await profileCall(account.code, "erase", { key: account.key });
    assert.deepEqual(erased.json, { ok: true, result: "erased" });
    assert.deepEqual((await httpCall("/v1/profiles", { codes: [account.code] })).json.profiles, []);
  });

  test("名刺の持ち主はランク・受信箱と同じ鍵（先に使った鍵）。違う鍵では置けず、消せない", async () => {
    const account = await newCardAccount();
    assertError(await profileCall(account.code, "put", { key: randomKey(), profile: card() }), 403, "forbidden");
    assertError(await profileCall(account.code, "erase", { key: randomKey() }), 403, "forbidden");
    // 名刺を先に置いたコードのランクも、同じ鍵でしか使えない
    const fresh = { code: randomFriendCode(), key: randomKey() };
    accounts.push(fresh);
    assert.equal((await profileCall(fresh.code, "put", { key: fresh.key, profile: card() })).status, 200);
    assertError(await rankCall(fresh.code, "seed", { key: randomKey(), state: cloudRank() }), 403, "forbidden");
  });

  test("名刺の中身を検める（名前 1〜12 文字・ヒーロー ID・国・勝ち数 ≤ 試合数・得意ヒーロー 3 体まで）", async () => {
    const code = randomFriendCode(), key = randomKey();
    accounts.push({ code, key });
    for (const bad of [
      card({ name: "" }), card({ name: "あ".repeat(13) }), card({ name: "a\u0007b" }), card({ avatar: "X1" }),
      card({ country: "jp" }), card({ level: 0 }), card({ wins: 41 }),
      card({ heroes: [1, 2, 3, 4].map(() => ({ heroID: "H027", matches: 1, wins: 1 })) }),
      card({ heroes: [{ heroID: "H027", matches: 1, wins: 2 }] }), null, "x",
    ]) {
      assertError(await profileCall(code, "put", { key, profile: bad }), 400, "bad_profile");
    }
    assertError(await profileCall(code, "put", { profile: card() }), 400, "bad_key");
    assertError(await httpCall("/v1/profiles", { codes: Array.from({ length: 101 }, randomFriendCode) }), 400, "bad_request");
  });

  test("ランキング: 今シーズンの最高ランクの順（フレンド・国の範囲、自分の順位、範囲の外は null = ランク外）", async () => {
    const legend = await newCardAccount(cloudRank({ tier: "legend", division: 2, stars: 3, highestTier: "legend" }), { country: "JP" });
    const mythic = await newCardAccount(cloudRank({ tier: "mythic", division: 1, stars: 30, highestTier: "mythic", highestMythicStars: 30 }), { country: "US" });
    const epic = await newCardAccount(cloudRank({ tier: "epic", division: 1, stars: 4, highestTier: "epic" }), { country: "JP" });
    const codes = [legend.code, mythic.code, epic.code];
    const friends = await httpCall("/v1/ranking", { scope: "friends", codes, me: epic.code });
    assert.equal(friends.status, 200, friends.text);
    assert.deepEqual(friends.json.entries.map((e) => [e.position, e.profile.code]), [[1, mythic.code], [2, legend.code], [3, epic.code]]);
    assert.deepEqual(friends.json.entries[0].profile.seasonBest, { tier: 6, division: 0, stars: 30 });
    assert.deepEqual([friends.json.me.position, friends.json.me.profile.code], [3, epic.code]);
    // 国の範囲（JP だけ）。自分が US なら範囲の外（ランク外）
    const jp = await httpCall("/v1/ranking", { scope: "country", country: "JP", me: mythic.code });
    const jpCodes = jp.json.entries.map((e) => e.profile.code);
    assert.ok(jpCodes.includes(legend.code) && jpCodes.includes(epic.code) && !jpCodes.includes(mythic.code));
    assert.equal(jp.json.me, null);
    // 世界: 並びは最高ランクの順（ほかのテストの名刺も混ざる）
    const world = await httpCall("/v1/ranking", { scope: "global", me: legend.code });
    const scores = world.json.entries.map((e) => e.profile.seasonBest);
    const score = (r) => r.tier * 100000 + (r.tier >= 6 ? r.stars : (10 - r.division) * 100 + r.stars);
    for (let i = 1; i < scores.length; i++) assert.ok(score(scores[i - 1]) >= score(scores[i]), "最高ランクの順");
    assert.equal(world.json.me.profile.code, legend.code);
    assertError(await httpCall("/v1/ranking", { scope: "all" }), 400, "bad_scope");
  });

  test("ランク戦の結果で、今のランクと今シーズンの最高が名刺に反映される（下がっても最高はそのまま）", async () => {
    const account = await newCardAccount(cloudRank({ tier: "legend", division: 1, stars: 5, highestTier: "legend" }));
    const up = await rankMatch(account, { matchId: newMatchId(), won: true, rating: 8, mvp: false });
    assert.equal(up.status, 200, up.text);
    let p = (await httpCall("/v1/profiles", { codes: [account.code] })).json.profiles[0];
    assert.deepEqual(p.rank, { tier: 6, division: 0, stars: 0 }, "ミシックへ上がった");
    assert.deepEqual(p.seasonBest, { tier: 6, division: 0, stars: 0 });
    assert.deepEqual([p.seasonWins, p.seasonLosses], [1, 0]);
    const down = await rankMatch(account, { matchId: newMatchId(), won: false, rating: 2, mvp: false });
    assert.equal(down.status, 200, down.text);
    p = (await httpCall("/v1/profiles", { codes: [account.code] })).json.profiles[0];
    assert.deepEqual(p.rank, { tier: 5, division: 1, stars: 4 }, "レジェンド I へ落ちた");
    assert.deepEqual(p.seasonBest, { tier: 6, division: 0, stars: 0 }, "今シーズンの最高はミシックのまま");
    // ランクを消すと名刺も消える
    assert.equal((await rankCall(account.code, "erase", { key: account.key })).status, 200);
    assert.deepEqual((await httpCall("/v1/profiles", { codes: [account.code] })).json.profiles, []);
  });

  test("運営のメール: 鍵が無い・違うと登録できず、登録した物は GET で配られ、消すと配られない", { skip: !OPS_MAIL_KEY }, async () => {
    const id = `ops_${randomBytes(4).toString("hex")}`;
    const mail = {
      id, titleJa: "メンテナンスのお知らせ", titleEn: "Maintenance", bodyJa: "本文", bodyEn: "Body",
      attachments: [{ kind: "coin", amount: 500 }], important: true,
    };
    assertError(await httpCall("/v1/mail/publish", { mail }), 403, "forbidden");
    assertError(await httpCall("/v1/mail/publish", { key: randomKey(), mail }), 403, "forbidden");
    assertError(await httpCall("/v1/mail/publish", { key: OPS_MAIL_KEY, mail: { ...mail, attachments: [{ kind: "bogus", amount: 1 }] } }), 400, "bad_mail");
    const published = await httpCall("/v1/mail/publish", { key: OPS_MAIL_KEY, mail });
    assert.deepEqual(published.json, { ok: true, id });
    const list = await httpCall("/v1/mail", undefined, "GET");
    assert.equal(list.status, 200, list.text);
    const got = list.json.mail.find((m) => m.id === id);
    assert.ok(got, "配られる");
    assert.equal(got.category, "important", "重要の印があれば重要なお知らせ");
    assert.ok(got.expiresAt - got.startsAt === 60 * 24 * 60 * 60 * 1000, "期間は既定で 60 日");
    assert.deepEqual((await httpCall("/v1/mail/delete", { key: OPS_MAIL_KEY, id })).json, { ok: true, result: "deleted" });
    assert.ok(!(await httpCall("/v1/mail", undefined, "GET")).json.mail.some((m) => m.id === id));
  });
});
