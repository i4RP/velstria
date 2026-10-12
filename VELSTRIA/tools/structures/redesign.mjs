#!/usr/bin/env node
// タワー系（外塔・内塔・基地塔・Star Core）の再デザインの 2D 画像を Codex（ChatGPT ログインの画像生成）で作る。
// 仕様は tools/structures/redesign.json（parts を連結したものがプロンプト）。ref / refs を持つ項目は、採用済みの
// マスター画像（<out>/<ref>.png）を添付して同じ設計から派生させる。
// 出力は env REDESIGN_OUT か build/tower_redesign/（git 管理外）。候補は <id>_<tag>.png、採用版は <id>.png
// （候補が初めてできたときは自動で採用版にもなる）。
//
// usage（VELSTRIA/ で実行）:
//   node tools/structures/redesign.mjs gen <id...|masters|all> [--tag t] [--note "修正指示（英語）"]
//   node tools/structures/redesign.mjs select <id> <tag>
//   node tools/structures/redesign.mjs prompt <id>
//   node tools/structures/redesign.mjs status
import fs from "node:fs";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const SPEC = JSON.parse(fs.readFileSync(path.join(ROOT, "tools", "structures", "redesign.json"), "utf8"));
const OUT = process.env.REDESIGN_OUT || path.join(ROOT, "build", "tower_redesign");
const CODEX_MODEL = process.env.STRUCT_CODEX_MODEL || "gpt-6-astra";
const SLOTS = Number(process.env.STRUCT_CODEX_SLOTS || 4);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const item = (id) => {
  const a = SPEC.items.find((x) => x.id === id);
  if (!a) throw new Error(`未知の id: ${id}`);
  return a;
};
const refsOf = (a) => (a.refs || (a.ref ? [a.ref] : []));
const isPng = (f) => {
  if (!fs.existsSync(f)) return false;
  const d = fs.readFileSync(f);
  return d.length > 8 && d[0] === 0x89 && d.toString("latin1", 1, 4) === "PNG";
};

function promptFor(a, note) {
  const body = [...a.parts.map((p) => SPEC.parts[p]), a.prompt];
  if (note) body.push(`Revision notes (must follow): ${note}`);
  return body.join("\n\n");
}

let running = 0;
const waiters = [];
async function slot() {
  if (running < SLOTS) { running++; return; }
  await new Promise((r) => waiters.push(r));
  running++;
}
function release() {
  running--;
  waiters.shift()?.();
}

function nextTag(id) {
  for (const c of "abcdefghijklmnopqrstuvwxyz") if (!fs.existsSync(path.join(OUT, `${id}_${c}.png`))) return c;
  throw new Error(`${id}: 候補が多すぎます`);
}

async function gen(id, tag, note) {
  const a = item(id);
  const refs = refsOf(a).map((r) => path.join(OUT, `${r}.png`));
  const missing = refs.filter((r) => !isPng(r));
  if (missing.length) { console.error(`${id}: 参照画像がありません ${missing.join(", ")}`); return null; }
  fs.mkdirSync(OUT, { recursive: true });
  const t = tag || nextTag(id);
  const out = path.join(OUT, `${id}_${t}.png`);
  const instruction =
    "Use your built-in image generation tool to create exactly ONE image from the prompt below"
    + (refs.length ? ` (the ${refs.length} attached image${refs.length > 1 ? "s are the approved master designs" : " is the approved master design"};`
      + " follow their shapes, parts, proportions and materials exactly, do not redesign them)" : "")
    + `. When it is done, copy the generated PNG file to ${out} (overwrite if it exists).`
    + " Do not modify the image and do not create any other files. Reply only with the output path."
    + "\n\n=== IMAGE PROMPT ===\n" + promptFor(a, note);
  // 作業ディレクトリは固定（Codex は -C の場所を ~/.codex/config.toml の trusted に登録するため）
  const work = path.join(OUT, ".codex-work");
  fs.mkdirSync(work, { recursive: true });
  for (let attempt = 1; attempt <= 3; attempt++) {
    if (fs.existsSync(out)) fs.unlinkSync(out);
    await slot();
    let tail = "";
    try {
      const args = ["exec", "--skip-git-repo-check", "--ephemeral", "--dangerously-bypass-approvals-and-sandbox",
        "-m", CODEX_MODEL, "-c", 'model_reasoning_effort="low"', "-C", work];
      for (const r of refs) args.push("-i", r);
      tail = await new Promise((resolve) => {
        const p = spawn("codex", args, { stdio: ["pipe", "pipe", "pipe"] });
        let buf = "";
        p.stdout.on("data", (d) => { buf += d; });
        p.stderr.on("data", (d) => { buf += d; });
        const timer = setTimeout(() => p.kill("SIGTERM"), 15 * 60_000);
        p.on("close", (code) => { clearTimeout(timer); resolve(`exit ${code}: ${buf.slice(-600)}`); });
        // -i は値を複数取るのでプロンプトは stdin で渡す
        p.stdin.end(instruction);
      });
    } finally {
      release();
    }
    if (isPng(out)) {
      const chosen = path.join(OUT, `${id}.png`);
      if (!fs.existsSync(chosen)) fs.copyFileSync(out, chosen);
      console.log(`${id}: ${out}`);
      return out;
    }
    console.error(`${id}: 試行 ${attempt} 失敗 (${tail})`);
    await sleep(5000 * attempt);
  }
  console.error(`${id}: 生成に失敗`);
  return null;
}

function expand(ids) {
  const all = SPEC.items.map((a) => a.id);
  return ids.flatMap((x) => (x === "all" ? all : x === "masters" ? all.filter((i) => !refsOf(item(i)).length) : [x]));
}

const [cmd, ...rest] = process.argv.slice(2);
const flag = (n) => {
  const i = rest.indexOf(n);
  if (i < 0) return undefined;
  const v = rest[i + 1];
  rest.splice(i, 2);
  return v;
};

if (cmd === "gen") {
  const tag = flag("--tag");
  const note = flag("--note");
  const ids = expand(rest);
  if (tag && ids.length > 1) throw new Error("--tag は 1 件のときだけ");
  const res = await Promise.all(ids.map((id) => gen(id, tag, note)));
  process.exit(res.every(Boolean) ? 0 : 1);
} else if (cmd === "select") {
  const [id, tag] = rest;
  const src = path.join(OUT, `${id}_${tag}.png`);
  if (!isPng(src)) throw new Error(`${src} がありません`);
  fs.copyFileSync(src, path.join(OUT, `${id}.png`));
  console.log(`${id}: ${tag} を採用`);
} else if (cmd === "prompt") {
  console.log(promptFor(item(rest[0]), flag("--note")));
} else if (cmd === "status") {
  for (const a of SPEC.items) {
    const cands = fs.existsSync(OUT) ? fs.readdirSync(OUT).filter((f) => f.startsWith(`${a.id}_`) && /^[a-z]\.png$/.test(f.slice(a.id.length + 1))) : [];
    console.log(`${a.id.padEnd(18)} ${isPng(path.join(OUT, `${a.id}.png`)) ? "採用済" : "未生成"}  候補 ${cands.length}  ${a.use}`);
  }
} else {
  console.error("usage: redesign.mjs gen|select|prompt|status ...");
  process.exit(2);
}
