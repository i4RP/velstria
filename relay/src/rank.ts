// VELSTRIA のアカウントごとのランク（Durable Object RankAccount。仕様は README.md「ランク」）。
//
// フレンドコード 1 つ = ランク 1 つ。持ち主は受信箱と同じ鍵（INBOX_KEY）で縛る（最初に来た鍵のハッシュを保存）。
// ランクの規則は Mobile Legends と同じ（アプリの RankService.swift と同じ計算。片方を変えたらもう片方も変える）:
// - ウォリアー III〜I（星 3）/ エリート III〜I（星 4）/ マスター IV〜I（星 4）/ グランドマスター V〜I（星 5）/
//   エピック V〜I（星 5）/ レジェンド V〜I（星 5）/ ミシック（星の累計。オナー 25・グローリー 50・イモータル 100）
// - 勝利 星 +1。満星で勝つと次の段位の星 1。敗北 星 −1、星 0 で負けると 1 段位下の「満星 −1」。
// - ウォリアーは負けても星が減らない。ティアの最下段・星 0 では下のティアへ落ちない（ミシック星 0 の敗北だけレジェンド I へ）。
// - スターポイント: 勝利でたまる（700 で星 +1）。保護ポイント: 敗北でたまる（700 になると次の敗北で星が減らない）。
// 同じ試合（matchId）の二重送信は、最初の結果を返す。端末の記録（seed）は規則の範囲の値だけ受け付ける。

import { DurableObject } from "cloudflare:workers";
import type { Env } from "./index";

export type Tier = "warrior" | "elite" | "master" | "grandmaster" | "epic" | "legend" | "mythic";
const TIERS: Tier[] = ["warrior", "elite", "master", "grandmaster", "epic", "legend", "mythic"];
/** 段位の数と 1 段位の星の数（ミシックは段位なし） */
const SHAPE: Record<Tier, { divisions: number; stars: number }> = {
  warrior: { divisions: 3, stars: 3 },
  elite: { divisions: 3, stars: 4 },
  master: { divisions: 4, stars: 4 },
  grandmaster: { divisions: 5, stars: 5 },
  epic: { divisions: 5, stars: 5 },
  legend: { divisions: 5, stars: 5 },
  mythic: { divisions: 1, stars: 0 },
};
export const BAR = 700;

export interface RankState {
  tier: Tier;
  /** 段位（大きいほど下。ミシックは 1） */
  division: number;
  /** 段位内の星（ミシックは累計） */
  stars: number;
  starPoints: number;
  protectionPoints: number;
  highestTier: Tier;
  highestMythicStars: number;
  wins: number;
  losses: number;
  season: number;
}

export interface MatchInput {
  matchId: string;
  won: boolean;
  /** 試合の評価（0〜16。MLBB の評価点と同じ尺度） */
  rating: number;
  mvp: boolean;
}

export interface MatchResult {
  before: RankState;
  after: RankState;
  starPointsGain: number;
  scoreBonus: number;
  activeBonus: number;
  protected: boolean;
}

export function initialState(season = 1): RankState {
  return {
    tier: "warrior", division: 3, stars: 0, starPoints: 0, protectionPoints: 0,
    highestTier: "warrior", highestMythicStars: 0, wins: 0, losses: 0, season,
  };
}

const tierIndex = (t: Tier) => TIERS.indexOf(t);

export function applyMatch(prev: RankState, m: MatchInput): MatchResult {
  const r: RankState = { ...prev };
  const rating = Math.max(0, Math.min(16, m.rating));
  let starPointsGain = 0, scoreBonus = 0, activeBonus = 0, prot = false;
  if (m.won) {
    r.wins += 1;
    addStar(r);
    if (r.tier !== "mythic") {
      starPointsGain = Math.round(20 + rating * 8 + (m.mvp ? 30 : 0));
      r.starPoints += starPointsGain;
      if (r.starPoints >= BAR) {
        r.starPoints -= BAR;
        addStar(r);
      }
    }
  } else {
    r.losses += 1;
    if (r.tier !== "mythic") {
      scoreBonus = Math.round(rating * 3);
      activeBonus = 5;
    }
    if (r.protectionPoints >= BAR) {
      r.protectionPoints = 0;
      prot = true;
    } else {
      removeStar(r);
      r.protectionPoints = Math.min(BAR, r.protectionPoints + scoreBonus + activeBonus);
    }
  }
  if (tierIndex(r.tier) > tierIndex(r.highestTier)) r.highestTier = r.tier;
  if (r.tier === "mythic") r.highestMythicStars = Math.max(r.highestMythicStars, r.stars);
  return { before: prev, after: r, starPointsGain, scoreBonus, activeBonus, protected: prot };
}

function addStar(r: RankState) {
  if (r.tier === "mythic") {
    r.stars += 1;
    return;
  }
  const max = SHAPE[r.tier].stars;
  if (r.stars < max) {
    r.stars += 1;
    return;
  }
  if (r.division > 1) {
    r.division -= 1;
    r.stars = 1;
    return;
  }
  const next = TIERS[tierIndex(r.tier) + 1];
  r.tier = next;
  r.division = SHAPE[next].divisions;
  r.stars = next === "mythic" ? 0 : 1;
}

function removeStar(r: RankState) {
  if (r.tier === "warrior") return;
  if (r.tier === "mythic") {
    if (r.stars > 0) r.stars -= 1;
    else {
      r.tier = "legend";
      r.division = 1;
      r.stars = SHAPE.legend.stars - 1;
    }
    return;
  }
  if (r.stars > 0) {
    r.stars -= 1;
    return;
  }
  if (r.division < SHAPE[r.tier].divisions) {
    r.division += 1;
    r.stars = SHAPE[r.tier].stars - 1;
  }
  // ティアの最下段・星 0: 下のティアへは落ちない
}

/** min 以上 max 以下の整数か */
function intIn(v: unknown, min: number, max = Number.MAX_SAFE_INTEGER): v is number {
  return Number.isSafeInteger(v) && (v as number) >= min && (v as number) <= max;
}

/**
 * 端末から預かる記録（seed）を検め、RankState の項目だけを取り出す（合わなければ null）。
 * ティア・段位・星は必須で規則の範囲（アプリの RankState の読み込みが収める範囲。ミシックは段位 1、星は累計）。
 * ほかは省けば初期値、送るなら 0 以上の整数（スターポイントは 700 未満、保護ポイントは 700 まで）。知らない項目と season は取り込まない。
 */
function parseState(v: unknown): RankState | null {
  if (typeof v !== "object" || v === null || Array.isArray(v)) return null;
  const s = v as Partial<Record<keyof RankState, unknown>>;
  const tier = s.tier as Tier;
  if (!TIERS.includes(tier)) return null;
  const base = initialState();
  const r = {
    ...base,
    tier,
    division: s.division,
    stars: s.stars,
    starPoints: s.starPoints ?? base.starPoints,
    protectionPoints: s.protectionPoints ?? base.protectionPoints,
    highestTier: s.highestTier ?? base.highestTier,
    highestMythicStars: s.highestMythicStars ?? base.highestMythicStars,
    wins: s.wins ?? base.wins,
    losses: s.losses ?? base.losses,
  };
  const shape = SHAPE[tier];
  const valid =
    intIn(r.division, 1, shape.divisions) &&
    intIn(r.stars, 0, tier === "mythic" ? undefined : shape.stars) &&
    intIn(r.starPoints, 0, BAR - 1) &&
    intIn(r.protectionPoints, 0, BAR) &&
    TIERS.includes(r.highestTier as Tier) &&
    intIn(r.highestMythicStars, 0) &&
    intIn(r.wins, 0) &&
    intIn(r.losses, 0);
  return valid ? (r as RankState) : null;
}

const HEX64 = /^[0-9a-f]{64}$/;
const MATCH_ID = /^[A-Za-z0-9_-]{8,64}$/;
/** 試合 ID: 8〜64 文字の英数・_・-（文字列だけ）。Object.prototype の名前（__proto__・toString など）は recent の引き当てを誤るので断る */
const isMatchId = (v: unknown): v is string => typeof v === "string" && MATCH_ID.test(v) && !(v in Object.prototype);
const MAX_RECENT = 50;

export type RankCallResult =
  | { ok: true; state: RankState; result?: MatchResult }
  | { ok: false; error: "forbidden" | "bad_request" };

export class RankAccount extends DurableObject<Env> {
  private check(keyHash: string): boolean {
    if (!HEX64.test(keyHash)) return false;
    const owner = this.ctx.storage.kv.get<string>("owner");
    if (owner === undefined) {
      this.ctx.storage.kv.put("owner", keyHash);
      return true;
    }
    return owner === keyHash;
  }

  private load(): RankState {
    return this.ctx.storage.kv.get<RankState>("rank") ?? initialState();
  }

  async get(keyHash: string): Promise<RankCallResult> {
    if (!this.check(keyHash)) return { ok: false, error: "forbidden" };
    return { ok: true, state: this.load() };
  }

  /** 端末の記録を最初の一度だけ取り込む（サーバーにまだ記録が無い時だけ） */
  async seed(keyHash: string, state: unknown): Promise<RankCallResult> {
    if (!this.check(keyHash)) return { ok: false, error: "forbidden" };
    const cur = this.ctx.storage.kv.get<RankState>("rank");
    if (cur) return { ok: true, state: cur };
    const s = parseState(state);
    if (!s) return { ok: false, error: "bad_request" };
    this.ctx.storage.kv.put("rank", s);
    return { ok: true, state: s };
  }

  async match(keyHash: string, input: MatchInput): Promise<RankCallResult> {
    if (!this.check(keyHash)) return { ok: false, error: "forbidden" };
    if (!isMatchId(input.matchId) || typeof input.won !== "boolean" || typeof input.rating !== "number") {
      return { ok: false, error: "bad_request" };
    }
    const recent = this.ctx.storage.kv.get<Record<string, MatchResult>>("recent") ?? {};
    const done = recent[input.matchId];
    if (done) return { ok: true, state: this.load(), result: done };
    const result = applyMatch(this.load(), { ...input, mvp: !!input.mvp });
    recent[input.matchId] = result;
    const keys = Object.keys(recent);
    for (const k of keys.slice(0, Math.max(0, keys.length - MAX_RECENT))) delete recent[k];
    this.ctx.storage.kv.put("rank", result.after);
    this.ctx.storage.kv.put("recent", recent);
    return { ok: true, state: result.after, result };
  }

  async erase(keyHash: string): Promise<RankCallResult> {
    if (!this.check(keyHash)) return { ok: false, error: "forbidden" };
    await this.ctx.storage.deleteAll();
    return { ok: true, state: initialState() };
  }
}
