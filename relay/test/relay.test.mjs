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
  if (persistDir) rmSync(persistDir, { recursive: true, force: true });
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
