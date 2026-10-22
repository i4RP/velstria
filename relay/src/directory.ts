// VELSTRIA の公開の名刺・ランキング・運営からのメール（Durable Object Directory。仕様は README.md「名刺・ランキング・メール」）。
//
// 全体で 1 つ（getByName("global")）。SQLite に、フレンドコードごとの名刺（本人が送る表示用の自己申告）と、ランク（RankAccount が
// 試合のたびに書く今のランク・今シーズンの最高ランク・勝敗）を置く。ランキングはこの表を「今シーズンの最高ランク」の順に並べる。
// 名刺の書き込みの鍵の照合は index.ts（受信箱の持ち主と同じ鍵）。ここは渡された値だけを扱う。
// 運営からのメールも同じ DO に置く（運営だけが秘密の鍵 OPS_MAIL_KEY で登録・削除。アプリは起動時に取りに来る）。

import { DurableObject } from "cloudflare:workers";
import type { Env } from "./index";
import { FRIEND_CODE } from "./inbox";
import { seasonAt, TIERS, type RankState } from "./rank";

/** ランクの位置（ティアの番号 0〜6・段位・星）。アプリの PublicRank と同じ形 */
export interface PublicRank {
  tier: number;
  division: number;
  stars: number;
}

export interface PublicHeroStat {
  heroID: string;
  matches: number;
  wins: number;
}

/** 本人が送る名刺の中身（表示用の自己申告）。ランクは送らせない（RankAccount が書く） */
export interface PublicCard {
  name: string;
  avatar: string | null;
  frame: string | null;
  level: number;
  country: string | null;
  heroes: PublicHeroStat[];
  matches: number;
  wins: number;
}

/** 読み出しの形（アプリの PublicProfile と同じ。updatedAt は ISO 8601） */
export interface PublicProfile extends PublicCard {
  code: string;
  rank: PublicRank;
  seasonBest: PublicRank;
  highest: PublicRank;
  seasonWins: number;
  seasonLosses: number;
  updatedAt: string;
}

export type RankingScope = "global" | "country" | "friends";

export interface RankingEntry {
  position: number;
  profile: PublicProfile;
}

/** 運営からのメール（アプリの MailItem に取り込む）。本文は日本語と英語 */
export interface OpsMail {
  id: string;
  titleJa: string;
  titleEn: string;
  bodyJa: string;
  bodyEn: string;
  attachments: { kind: string; amount: number; refID?: string }[];
  important: boolean;
  category: string;
  /** 公開の始まり・終わり（ミリ秒） */
  startsAt: number;
  expiresAt: number;
}

/** 名前の上限（アプリの PlayerNameRules と同じ 12 文字） */
const MAX_NAME = 12;
const HERO_ID = /^H\d{3}$/;
const COSMETIC_ID = /^[A-Za-z0-9_]{1,32}$/;
const COUNTRY = /^[A-Z]{2}$/;
const MAIL_ID = /^[A-Za-z0-9_-]{4,48}$/;
/** 添付の種類（アプリの MailAttachment.Kind と同じ生の値） */
const MAIL_KINDS = new Set(["coin", "gem", "cosmetic", "hero", "passXP", "magicDust", "emblemFragment"]);
const MAIL_CATEGORIES = new Set(["important", "system", "report", "inbox", "gift"]);
/** ランキングの上限・フレンドの範囲で渡せるコードの数・まとめて読む名刺の数 */
export const RANKING_LIMIT = 100;
export const MAX_FRIEND_CODES = 200;
export const MAX_BATCH_CODES = 100;
/** 運営のメールの既定の公開期間（60 日。MLBB の保存期間に合わせる）と、配る数の上限 */
export const MAIL_DEFAULT_TTL_MS = 60 * 24 * 60 * 60 * 1000;
const MAX_ACTIVE_MAIL = 50;

const isInt = (v: unknown, min: number, max: number): v is number =>
  Number.isSafeInteger(v) && (v as number) >= min && (v as number) <= max;

/** 名刺の中身を検める（合わなければ null）。名前は前後の空白を落として 1〜12 文字、制御文字なし */
export function parseCard(v: unknown): PublicCard | null {
  if (typeof v !== "object" || v === null || Array.isArray(v)) return null;
  const c = v as Record<string, unknown>;
  if (typeof c.name !== "string") return null;
  const name = c.name.trim();
  // eslint-disable-next-line no-control-regex
  if ([...name].length < 1 || [...name].length > MAX_NAME || /[\u0000-\u001f\u007f]/.test(name)) return null;
  const avatar = c.avatar ?? null;
  if (avatar !== null && (typeof avatar !== "string" || !HERO_ID.test(avatar))) return null;
  const frame = c.frame ?? null;
  if (frame !== null && (typeof frame !== "string" || !COSMETIC_ID.test(frame))) return null;
  const country = c.country ?? null;
  if (country !== null && (typeof country !== "string" || !COUNTRY.test(country))) return null;
  if (!isInt(c.level, 1, 9999) || !isInt(c.matches, 0, 10_000_000) || !isInt(c.wins, 0, c.matches as number)) return null;
  if (!Array.isArray(c.heroes) || c.heroes.length > 3) return null;
  const heroes: PublicHeroStat[] = [];
  for (const h of c.heroes) {
    if (typeof h !== "object" || h === null) return null;
    const s = h as Record<string, unknown>;
    if (typeof s.heroID !== "string" || !HERO_ID.test(s.heroID) || !isInt(s.matches, 0, 10_000_000) || !isInt(s.wins, 0, s.matches as number)) {
      return null;
    }
    heroes.push({ heroID: s.heroID, matches: s.matches as number, wins: s.wins as number });
  }
  return { name, avatar, frame, level: c.level as number, country, heroes, matches: c.matches as number, wins: c.wins as number };
}

/** 運営のメールを検める（合わなければ null）。期間は省けば今から 60 日 */
export function parseMail(v: unknown, now: number): OpsMail | null {
  if (typeof v !== "object" || v === null || Array.isArray(v)) return null;
  const m = v as Record<string, unknown>;
  const text = (x: unknown, max: number) => typeof x === "string" && x.length > 0 && x.length <= max;
  if (typeof m.id !== "string" || !MAIL_ID.test(m.id)) return null;
  if (!text(m.titleJa, 80) || !text(m.titleEn, 80) || !text(m.bodyJa, 2000) || !text(m.bodyEn, 2000)) return null;
  const category = m.category ?? (m.important === true ? "important" : "system");
  if (typeof category !== "string" || !MAIL_CATEGORIES.has(category)) return null;
  const attachments: OpsMail["attachments"] = [];
  const list = m.attachments ?? [];
  if (!Array.isArray(list) || list.length > 8) return null;
  for (const a of list) {
    if (typeof a !== "object" || a === null) return null;
    const x = a as Record<string, unknown>;
    if (typeof x.kind !== "string" || !MAIL_KINDS.has(x.kind) || !isInt(x.amount, 0, 1_000_000)) return null;
    if (x.refID !== undefined && (typeof x.refID !== "string" || !COSMETIC_ID.test(x.refID))) return null;
    attachments.push(x.refID === undefined ? { kind: x.kind, amount: x.amount as number } : { kind: x.kind, amount: x.amount as number, refID: x.refID });
  }
  const startsAt = m.startsAt === undefined ? now : m.startsAt;
  if (!isInt(startsAt, 0, Number.MAX_SAFE_INTEGER)) return null;
  const expiresAt = m.expiresAt === undefined ? (startsAt as number) + MAIL_DEFAULT_TTL_MS : m.expiresAt;
  if (!isInt(expiresAt, (startsAt as number) + 1, Number.MAX_SAFE_INTEGER)) return null;
  return {
    id: m.id, titleJa: m.titleJa as string, titleEn: m.titleEn as string, bodyJa: m.bodyJa as string, bodyEn: m.bodyEn as string,
    attachments, important: m.important === true, category, startsAt: startsAt as number, expiresAt: expiresAt as number,
  };
}

/** ランクの順位の値（大きいほど上）。ティア → 段位（1 が上）→ 星。ミシックは星の累計 */
export function rankScore(r: PublicRank): number {
  return r.tier * 100_000 + (r.tier >= 6 ? r.stars : (10 - r.division) * 100 + r.stars);
}

function publicRank(s: RankState): PublicRank {
  return { tier: Math.max(0, TIERS.indexOf(s.tier)), division: s.tier === "mythic" ? 0 : s.division, stars: s.stars };
}

type Row = {
  code: string;
  card: string | null;
  updated: number;
  rank: string | null;
  best: string | null;
  best_score: number;
  high: string | null;
  season: number;
  sw: number;
  sl: number;
  rank_updated: number;
};

const UNRANKED: PublicRank = { tier: 0, division: 3, stars: 0 };

export class Directory extends DurableObject<Env> {
  /** 今の時刻（ミリ秒）。シーズンの切り替えを試すテストは差し替える */
  protected now(): number {
    return Date.now();
  }

  // MARK: 名刺

  /** 名刺を書く（鍵の照合は index.ts）。ランクの列はそのまま */
  async putCard(code: string, card: PublicCard): Promise<PublicProfile> {
    const sql = this.schema();
    const now = this.now();
    sql.exec(
      `INSERT INTO cards (code, card, updated, country) VALUES (?, ?, ?, ?)
       ON CONFLICT(code) DO UPDATE SET card = excluded.card, updated = excluded.updated, country = excluded.country`,
      code, JSON.stringify(card), now, card.country,
    );
    return this.profile(this.row(code)!)!;
  }

  /** 名刺とランクの記録を消す（本人の求め・全データの削除・ランクの消去）。無ければ何もしない */
  async erase(code: string): Promise<boolean> {
    const sql = this.schema();
    const had = this.row(code) !== undefined;
    sql.exec("DELETE FROM cards WHERE code = ?", code);
    return had;
  }

  /** まとめて読む（名刺のある物だけ。最大 MAX_BATCH_CODES） */
  async profiles(codes: string[]): Promise<PublicProfile[]> {
    this.schema();
    const valid = [...new Set(codes.filter((c) => FRIEND_CODE.test(c)))].slice(0, MAX_BATCH_CODES);
    const out: PublicProfile[] = [];
    for (const c of valid) {
      const row = this.row(c);
      const p = row && this.profile(row);
      if (p) out.push(p);
    }
    return out;
  }

  // MARK: ランク（RankAccount の結果から index.ts が書く）

  /** 今のランク・今シーズンの最高ランク・勝敗を書く。シーズンが変わったら最高は今のランクから数え直す */
  async updateRank(code: string, state: RankState): Promise<void> {
    const sql = this.schema();
    const cur = publicRank(state);
    const score = rankScore(cur);
    const row = this.row(code);
    let best = cur;
    let bestScore = score;
    if (row && row.season === state.season && row.best && row.best_score >= score) {
      best = JSON.parse(row.best) as PublicRank;
      bestScore = row.best_score;
    }
    const high: PublicRank = { tier: Math.max(0, TIERS.indexOf(state.highestTier)), division: 0, stars: state.highestMythicStars };
    sql.exec(
      `INSERT INTO cards (code, card, updated, rank, best, best_score, high, season, sw, sl, rank_updated)
       VALUES (?, NULL, 0, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(code) DO UPDATE SET rank = excluded.rank, best = excluded.best, best_score = excluded.best_score,
         high = excluded.high, season = excluded.season, sw = excluded.sw, sl = excluded.sl, rank_updated = excluded.rank_updated`,
      code, JSON.stringify(cur), JSON.stringify(best), bestScore, JSON.stringify(high), state.season, state.wins, state.losses, this.now(),
    );
  }

  /**
   * ランキング（今シーズンの最高ランクの順。名刺のある人だけ）。上位 RANKING_LIMIT 人と、me の順位（範囲に入っていなければ null）。
   * 同じ値は先に到達した人（rank_updated が早い）を上にする。
   */
  async ranking(scope: RankingScope, country: string | null, codes: string[], me: string | null): Promise<{ entries: RankingEntry[]; me: RankingEntry | null }> {
    const sql = this.schema();
    const season = seasonAt(this.now());
    let where = "card IS NOT NULL AND season = ?";
    const params: (string | number)[] = [season];
    if (scope === "country") {
      if (!country || !COUNTRY.test(country)) return { entries: [], me: null };
      where += " AND country = ?";
      params.push(country);
    } else if (scope === "friends") {
      const list = [...new Set([...codes, ...(me ? [me] : [])].filter((c) => FRIEND_CODE.test(c)))].slice(0, MAX_FRIEND_CODES + 1);
      if (list.length === 0) return { entries: [], me: null };
      where += ` AND code IN (${list.map(() => "?").join(",")})`;
      params.push(...list);
    }
    const rows = sql
      .exec<Row>(`SELECT * FROM cards WHERE ${where} ORDER BY best_score DESC, rank_updated ASC, code ASC LIMIT ${RANKING_LIMIT}`, ...params)
      .toArray();
    const entries: RankingEntry[] = [];
    rows.forEach((row, i) => {
      const p = this.profile(row);
      if (p) entries.push({ position: i + 1, profile: p });
    });
    let mine: RankingEntry | null = null;
    if (me && FRIEND_CODE.test(me)) {
      const row = sql.exec<Row>(`SELECT * FROM cards WHERE ${where} AND code = ?`, ...params, me).toArray()[0];
      const p = row && this.profile(row);
      if (row && p) {
        const ahead = sql
          .exec<{ n: number }>(
            `SELECT COUNT(*) AS n FROM cards WHERE ${where} AND (best_score > ? OR (best_score = ? AND (rank_updated < ? OR (rank_updated = ? AND code < ?))))`,
            ...params, row.best_score, row.best_score, row.rank_updated, row.rank_updated, row.code,
          )
          .one().n;
        mine = { position: ahead + 1, profile: p };
      }
    }
    return { entries, me: mine };
  }

  // MARK: 運営からのメール

  async publishMail(mail: OpsMail): Promise<void> {
    this.schema().exec(
      `INSERT INTO mail (id, body, starts, expires, published) VALUES (?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET body = excluded.body, starts = excluded.starts, expires = excluded.expires`,
      mail.id, JSON.stringify(mail), mail.startsAt, mail.expiresAt, this.now(),
    );
  }

  async deleteMail(id: string): Promise<boolean> {
    const sql = this.schema();
    const had = sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM mail WHERE id = ?", id).one().n > 0;
    sql.exec("DELETE FROM mail WHERE id = ?", id);
    return had;
  }

  /** 今公開中のメール（新しい順。終わった物はここで消す） */
  async activeMail(): Promise<OpsMail[]> {
    const sql = this.schema();
    const now = this.now();
    sql.exec("DELETE FROM mail WHERE expires <= ?", now);
    return sql
      .exec<{ body: string }>(`SELECT body FROM mail WHERE starts <= ? ORDER BY published DESC LIMIT ${MAX_ACTIVE_MAIL}`, now)
      .toArray()
      .map((r) => JSON.parse(r.body) as OpsMail);
  }

  // MARK: 内部

  private schema(): SqlStorage {
    const sql = this.ctx.storage.sql;
    sql.exec(`CREATE TABLE IF NOT EXISTS cards (
      code TEXT PRIMARY KEY, card TEXT, updated INTEGER NOT NULL DEFAULT 0, country TEXT,
      rank TEXT, best TEXT, best_score INTEGER NOT NULL DEFAULT 0, high TEXT,
      season INTEGER NOT NULL DEFAULT 0, sw INTEGER NOT NULL DEFAULT 0, sl INTEGER NOT NULL DEFAULT 0,
      rank_updated INTEGER NOT NULL DEFAULT 0)`);
    sql.exec("CREATE INDEX IF NOT EXISTS cards_rank ON cards (season, best_score DESC, rank_updated)");
    sql.exec("CREATE TABLE IF NOT EXISTS mail (id TEXT PRIMARY KEY, body TEXT NOT NULL, starts INTEGER NOT NULL, expires INTEGER NOT NULL, published INTEGER NOT NULL)");
    return sql;
  }

  private row(code: string): Row | undefined {
    return this.ctx.storage.sql.exec<Row>("SELECT * FROM cards WHERE code = ?", code).toArray()[0];
  }

  /** 表の 1 行 → 公開の名刺（名刺が無ければ null）。前のシーズンのランクの行は今シーズンの勝敗・最高を 0 から */
  private profile(row: Row): PublicProfile | null {
    if (!row.card) return null;
    const card = JSON.parse(row.card) as PublicCard;
    const current = row.season === seasonAt(this.now());
    const rank = row.rank ? (JSON.parse(row.rank) as PublicRank) : UNRANKED;
    return {
      code: row.code,
      ...card,
      rank,
      seasonBest: current && row.best ? (JSON.parse(row.best) as PublicRank) : rank,
      highest: row.high ? (JSON.parse(row.high) as PublicRank) : { tier: rank.tier, division: 0, stars: 0 },
      seasonWins: current ? row.sw : 0,
      seasonLosses: current ? row.sl : 0,
      updatedAt: new Date(Math.max(row.updated, row.rank_updated)).toISOString(),
    };
  }
}
