// VELSTRIA のアカウントごとのランク（Durable Object RankAccount。仕様は README.md「ランク」）。
//
// フレンドコード 1 つ = ランク 1 つ。持ち主は受信箱と同じ鍵（INBOX_KEY）で縛る（最初に来た鍵のハッシュを保存）。
// ランクの規則は Mobile Legends と同じ（アプリの RankService.swift・SeasonService.swift と同じ計算。片方を変えたらもう片方も変える）:
// - ウォリアー III〜I（星 3）/ エリート III〜I（星 4）/ マスター IV〜I（星 4）/ グランドマスター V〜I（星 5）/
//   エピック V〜I（星 5）/ レジェンド V〜I（星 5）/ ミシック（星の累計。オナー 25・グローリー 50・イモータル 100）
// - 勝利 星 +1。満星で勝つと次の段位の星 1。敗北 星 −1、星 0 で負けると 1 段位下の「満星 −1」。
// - ウォリアーは負けても星が減らない。ティアの最下段・星 0 では下のティアへ落ちない（ミシック星 0 の敗北だけレジェンド I へ）。
// - スターポイント: 勝利でたまり、満タンで星 +1（1 試合で 1 つまで）。満タンはティアごと（STAR_POINT_CAP: ウォリアー 100・
//   エリート 200・マスター 300・グランドマスター 500・エピック 700・レジェンド 1000）。ミシックには無い（上がると 0）。
// - 保護ポイント: 敗北でたまり、満タンで次の敗北の星が減らない（PROTECTION_CAP: スターポイントと同じ値、ミシック 1100。ミシックでもたまる）。
//   ティアが変わったら新しいティアの満タンに収める。1 試合の加点（勝ち 20 + 評価 × 8、MVP +30。負け 評価 × 3 + 5）は Velstria の式のまま。
// - シーズン: MLBB と同じ番号。S42 は 2026-09-16 08:00 UTC（SEASON_EPOCH_MS）から、1 シーズン 91 日（13 週）。新しいシーズンの
//   最初の get / seed / match で、前のシーズンの最終ランクから 1 回だけ下げる（SEASON_RESET。星・両ポイント・勝敗は 0、最高到達はそのまま）。
// 同じ試合（matchId）の二重送信は、最初の結果を返す。端末の記録（seed）は規則の範囲の値だけ受け付ける。

import { DurableObject } from "cloudflare:workers";
import type { Env } from "./index";

export type Tier = "warrior" | "elite" | "master" | "grandmaster" | "epic" | "legend" | "mythic";
export const TIERS: Tier[] = ["warrior", "elite", "master", "grandmaster", "epic", "legend", "mythic"];
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
/** スターポイントの満タン（Fandom「Ranked」）。ミシックは 0（星上げポイントが無い） */
export const STAR_POINT_CAP: Readonly<Record<Tier, number>> = {
  warrior: 100, elite: 200, master: 300, grandmaster: 500, epic: 700, legend: 1000, mythic: 0,
};
/** 保護ポイントの満タン（Fandom「Ranked」） */
export const PROTECTION_CAP: Readonly<Record<Tier, number>> = {
  warrior: 100, elite: 200, master: 300, grandmaster: 500, epic: 700, legend: 1000, mythic: 1100,
};
/** seed で受け付けるポイントの上限（ティアを問わない。旧版の全ティア 700 の値も入る。取り込む時にティアの満タンに収める） */
const MAX_SEED_STAR_POINTS = Math.max(...Object.values(STAR_POINT_CAP)) - 1;
/** seed で受け付ける保護ポイントの上限（ミシックの満タンが 1500 だった頃の記録も受け付け、取り込む時に満タンに収める） */
const MAX_SEED_PROTECTION_POINTS = 1500;

// ---- シーズン ----

/** シーズン制を始めたシーズン（MLBB の S42）。これより前の番号（シーズン制の前の記録の 1）はこのシーズンとして読む */
export const FIRST_SEASON = 42;
/** S42 の開始: 2026-09-16 08:00 UTC（MLBB S42 の開始日。切り替えの時刻はコミュニティの記録） */
export const SEASON_EPOCH_MS = Date.UTC(2026, 8, 16, 8);
/** 1 シーズン = 91 日（13 週。MLBB のシーズンはおよそ 3 か月で、S36〜S38・S41・S42 は 91 日） */
export const SEASON_MS = 91 * 24 * 60 * 60 * 1000;

/** その時刻のシーズン（S42 の開始より前は S42） */
export function seasonAt(ms: number): number {
  return ms >= SEASON_EPOCH_MS ? FIRST_SEASON + Math.floor((ms - SEASON_EPOCH_MS) / SEASON_MS) : FIRST_SEASON;
}

/** シーズンの開始時刻（終わりは次のシーズンの開始） */
export function seasonStartMs(season: number): number {
  return SEASON_EPOCH_MS + (Math.max(FIRST_SEASON, season) - FIRST_SEASON) * SEASON_MS;
}

/**
 * 新しいシーズンの開始位置（前のシーズンの最終ランク → ティアと段位。星は 0）。添字 = 段位 − 1（I, II, III, …）。
 * MLBB は公式の表を出しておらず、紹介ページどうしで食い違う。マスター〜エピックは 2017 年の公式（Patch Notes 1.2.18 の
 * S5→S6）の形、ウォリアー・エリート（星だけ 0）とレジェンド・ミシックは 2026 年の各ページで一致する行（docs/OUTGAME_GAP.md 7-12）。
 */
const SEASON_RESET: Readonly<Record<Exclude<Tier, "mythic">, readonly (readonly [Tier, number])[]>> = {
  warrior: [["warrior", 1], ["warrior", 2], ["warrior", 3]],
  elite: [["elite", 1], ["elite", 2], ["elite", 3]],
  master: [["master", 3], ["master", 4], ["elite", 1], ["elite", 1]],
  grandmaster: [["grandmaster", 3], ["grandmaster", 4], ["grandmaster", 5], ["master", 1], ["master", 2]],
  epic: [["epic", 4], ["epic", 5], ["epic", 5], ["grandmaster", 1], ["grandmaster", 2]],
  legend: [["epic", 3], ["epic", 3], ["epic", 3], ["epic", 3], ["epic", 4]],
};

/**
 * 新しいシーズンの開始位置 [ティア, 段位, 星]。ミシックは星の累計で決まる（2.2.16 の映像: H・G ミシック → エピック II、
 * I ミシック（100〜）→ エピック I・星 1。ミシック 0〜24 は見つからないのでエピック II とする）
 */
export function seasonResetPlace(r: Pick<RankState, "tier" | "division" | "stars">): [Tier, number, number] {
  if (r.tier === "mythic") return r.stars >= 100 ? ["epic", 1, 1] : ["epic", 2, 0];
  const row = SEASON_RESET[r.tier];
  const [tier, division] = row[Math.min(row.length, Math.max(1, r.division)) - 1];
  return [tier, division, 0];
}

/**
 * season へ進める。前のシーズンの記録なら 1 回だけ下げる（何シーズン空いても 1 回。MLBB は新シーズンの初回ログインで下げる）。
 * 星・スターポイント・保護ポイント・勝敗は 0、最高到達はそのまま。先のシーズンの記録は戻さない。進めなければ prev をそのまま返す。
 * FIRST_SEASON より前の番号（シーズン制の前の記録の 1）は FIRST_SEASON として読む。
 */
export function rollover(prev: RankState, season: number): RankState {
  const from = Number.isSafeInteger(prev.season) ? Math.max(FIRST_SEASON, prev.season) : FIRST_SEASON;
  if (from >= season) return from === prev.season ? prev : { ...prev, season: from };
  const [tier, division, stars] = seasonResetPlace(prev);
  return { ...prev, tier, division, stars, starPoints: 0, protectionPoints: 0, wins: 0, losses: 0, season };
}

// ---- 試合 ----

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
  /** このシーズンの勝ち数・負け数 */
  wins: number;
  losses: number;
  /** シーズン（MLBB と同じ番号。seasonAt） */
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

export function initialState(season = FIRST_SEASON): RankState {
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
      const cap = STAR_POINT_CAP[r.tier];
      if (r.starPoints >= cap) {
        r.starPoints -= cap;
        addStar(r);
      }
    }
  } else {
    r.losses += 1;
    scoreBonus = Math.round(rating * 3);
    activeBonus = 5;
    if (r.protectionPoints >= PROTECTION_CAP[r.tier]) {
      r.protectionPoints = 0;
      prot = true;
    } else {
      removeStar(r);
      r.protectionPoints += scoreBonus + activeBonus;
    }
  }
  fitPoints(r);
  if (tierIndex(r.tier) > tierIndex(r.highestTier)) r.highestTier = r.tier;
  if (r.tier === "mythic") r.highestMythicStars = Math.max(r.highestMythicStars, r.stars);
  return { before: prev, after: r, starPointsGain, scoreBonus, activeBonus, protected: prot };
}

/** ポイントを今のティアの満タンに収める（スターポイントは満タン未満でミシックは 0、保護ポイントは満タンまで） */
function fitPoints(r: RankState) {
  r.starPoints = Math.max(0, Math.min(r.starPoints, STAR_POINT_CAP[r.tier] - 1));
  r.protectionPoints = Math.max(0, Math.min(r.protectionPoints, PROTECTION_CAP[r.tier]));
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
 * ほかは省けば初期値、送るなら 0 以上の整数（スターポイントは 999 まで、保護ポイントは 1500 まで。旧版の 700 共通の値も入る）で、
 * ポイントはティアの満タンに収める。season は省けば今のシーズン、FIRST_SEASON より前は FIRST_SEASON、先は次のシーズンまで
 * （端末の時計が進んでいて、もう下げてある記録）。知らない項目は取り込まない。
 */
function parseState(v: unknown, season: number): RankState | null {
  if (typeof v !== "object" || v === null || Array.isArray(v)) return null;
  const s = v as Partial<Record<keyof RankState, unknown>>;
  const tier = s.tier as Tier;
  if (!TIERS.includes(tier)) return null;
  const base = initialState(season);
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
    season: s.season ?? base.season,
  };
  const shape = SHAPE[tier];
  const valid =
    intIn(r.division, 1, shape.divisions) &&
    intIn(r.stars, 0, tier === "mythic" ? undefined : shape.stars) &&
    intIn(r.starPoints, 0, MAX_SEED_STAR_POINTS) &&
    intIn(r.protectionPoints, 0, MAX_SEED_PROTECTION_POINTS) &&
    TIERS.includes(r.highestTier as Tier) &&
    intIn(r.highestMythicStars, 0) &&
    intIn(r.wins, 0) &&
    intIn(r.losses, 0) &&
    intIn(r.season, 0);
  if (!valid) return null;
  const state = r as RankState;
  state.season = Math.min(Math.max(FIRST_SEASON, state.season), season + 1);
  fitPoints(state);
  return state;
}

const HEX64 = /^[0-9a-f]{64}$/;
const MATCH_ID = /^[A-Za-z0-9_-]{8,64}$/;
/** 試合 ID: 8〜64 文字の英数・_・-（文字列だけ）。Object.prototype の名前（__proto__・toString など）は recent の引き当てを誤るので断る */
const isMatchId = (v: unknown): v is string => typeof v === "string" && MATCH_ID.test(v) && !(v in Object.prototype);
const MAX_RECENT = 50;

export type RankCallResult =
  | { ok: true; state: RankState; result?: MatchResult }
  | { ok: false; error: "forbidden" | "bad_request" | "not_seeded" };

export class RankAccount extends DurableObject<Env> {
  /** 今の時刻（ミリ秒）。シーズンの切り替えを試すテストは差し替える */
  protected now(): number {
    return Date.now();
  }

  private season(): number {
    return seasonAt(this.now());
  }

  private check(keyHash: string): boolean {
    if (!HEX64.test(keyHash)) return false;
    const owner = this.ctx.storage.kv.get<string>("owner");
    if (owner === undefined) {
      this.ctx.storage.kv.put("owner", keyHash);
      return true;
    }
    return owner === keyHash;
  }

  /** 保存した記録（無ければ undefined）。前のシーズンの記録なら、ここで今のシーズンへ進めて保存する（新シーズンの最初の呼び出しで下げる） */
  private stored(): RankState | undefined {
    const saved = this.ctx.storage.kv.get<RankState>("rank");
    if (!saved) return undefined;
    const r = rollover(saved, this.season());
    if (r !== saved) this.ctx.storage.kv.put("rank", r);
    return r;
  }

  async get(keyHash: string): Promise<RankCallResult> {
    if (!this.check(keyHash)) return { ok: false, error: "forbidden" };
    return { ok: true, state: this.stored() ?? initialState(this.season()) };
  }

  /** 端末の記録を最初の一度だけ取り込む（サーバーにまだ記録が無い時だけ。前のシーズンの記録なら下げてから） */
  async seed(keyHash: string, state: unknown): Promise<RankCallResult> {
    if (!this.check(keyHash)) return { ok: false, error: "forbidden" };
    const cur = this.stored();
    if (cur) return { ok: true, state: cur };
    const season = this.season();
    const parsed = parseState(state, season);
    if (!parsed) return { ok: false, error: "bad_request" };
    const s = rollover(parsed, season);
    this.ctx.storage.kv.put("rank", s);
    return { ok: true, state: s };
  }

  async match(keyHash: string, input: MatchInput): Promise<RankCallResult> {
    if (!this.check(keyHash)) return { ok: false, error: "forbidden" };
    if (!isMatchId(input.matchId) || typeof input.won !== "boolean" || typeof input.rating !== "number") {
      return { ok: false, error: "bad_request" };
    }
    // 記録の無いアカウント（起動時の seed がまだ届いていない）には試合を足さない。ウォリアー III から数え直した値で
    // 端末のランクを上書きしないため。端末は自分の計算のまま進み、次の起動の seed でその値が取り込まれる
    const cur = this.stored();
    if (!cur) return { ok: false, error: "not_seeded" };
    const recent = this.ctx.storage.kv.get<Record<string, MatchResult>>("recent") ?? {};
    const done = recent[input.matchId];
    if (done) return { ok: true, state: cur, result: done };
    const result = applyMatch(cur, { ...input, mvp: !!input.mvp });
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
    return { ok: true, state: initialState(this.season()) };
  }
}
