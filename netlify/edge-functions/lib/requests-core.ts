// Pure logic for the feature-request board: no I/O and no Netlify APIs, so the edge function,
// the moderation script and the tests all share it.

export type Status = "open" | "planned" | "in-progress" | "shipped";
export const STATUSES: readonly Status[] = ["open", "planned", "in-progress", "shipped"];

export interface Item {
  id: string;
  title: string;
  details: string;
  status: Status;
  created: string;
  source: "app" | "site";
  version: string;
  removed?: boolean;
  mergedInto?: string;
  /** Requests merged into this one, recorded by requests.sh merge, so a vote can count without a scan. */
  mergedFrom?: string[];
}

export interface BoardItem {
  id: string;
  title: string;
  details: string;
  status: Status;
  created: string;
  votes: number;
}

export interface Submission {
  title: string;
  details: string;
  source: "app" | "site";
  version: string;
}

export type Result<T> = { ok: true; value: T } | { ok: false; error: string };

export const LIMITS = { post: 3, vote: 50 } as const;
export const TITLE_MIN = 3;
export const TITLE_MAX = 80;
export const DETAILS_MAX = 500;
export const MIN_ELAPSED_MS = 3000;
/** Raw input caps, checked before any per-character work. Generous enough for 80 emoji. */
export const TITLE_RAW_MAX = 1000;
export const DETAILS_RAW_MAX = 4000;

const LINKS = /https?:\/\/\S+|www\.\S+/gi;
/** Control and format characters (terminal escapes, bidi overrides, zero-width spaces), except the
 *  joiners emoji and some scripts need. */
export const INVISIBLE = /\p{Cc}|(?![\u200C\u200D])\p{Cf}/gu;
/** Characters that draw nothing: spaces, format marks, combining marks alone, and blank fillers. */
const BLANK = /^[\s\p{Cf}\p{M}\u2800\u3164\uFFA0\u115F\u1160]*$/u;
const VERSION = /^\d+(\.\d+){0,3}$/;
const graphemes = new Intl.Segmenter("en", { granularity: "grapheme" });

const fields = (body: unknown): Record<string, unknown> =>
  body && typeof body === "object" && !Array.isArray(body) ? body as Record<string, unknown> : {};

/** Characters as people count them: "👩‍💻" is one. */
export const length = (s: string): number => [...graphemes.segment(s)].length;

const visible = (s: string): number => [...graphemes.segment(s)].filter((g) => !BLANK.test(g.segment)).length;

/** Removes links, control and bidi characters and stacks of combining marks, collapses whitespace
 *  and trims. Anything that isn't a string becomes "". */
export function cleanText(value: unknown): string {
  if (typeof value !== "string") return "";
  return value
    .replace(LINKS, " ")
    .replace(/\s+/g, " ")
    .replace(INVISIBLE, "")
    .replace(/(\p{M}{2})\p{M}+/gu, "$1")
    .replace(/ {2,}/g, " ")
    .trim();
}

export function validateSubmission(body: unknown): Result<Submission> {
  const b = fields(body);
  if (typeof b.title === "string" && b.title.length > TITLE_RAW_MAX) {
    return { ok: false, error: `Keep the title to ${TITLE_MAX} characters; there's room for more in the details.` };
  }
  if (typeof b.details === "string" && b.details.length > DETAILS_RAW_MAX) {
    return { ok: false, error: `Keep the details to ${DETAILS_MAX} characters.` };
  }
  const title = cleanText(b.title);
  const details = cleanText(b.details);
  if (visible(title) < TITLE_MIN) return { ok: false, error: `Give your idea a title of at least ${TITLE_MIN} characters.` };
  if (length(title) > TITLE_MAX) return { ok: false, error: `Keep the title to ${TITLE_MAX} characters; there's room for more in the details.` };
  if (length(details) > DETAILS_MAX) return { ok: false, error: `Keep the details to ${DETAILS_MAX} characters.` };
  const version = typeof b.version === "string" && VERSION.test(b.version) ? b.version : "";
  return { ok: true, value: { title, details, source: b.source === "app" ? "app" : "site", version } };
}

/** The hidden trap field was filled, or the form went faster than a person types. */
export function looksAutomated(body: unknown): boolean {
  const b = fields(body);
  if (typeof b.website === "string" && b.website.trim() !== "") return true;
  return !(typeof b.elapsedMs === "number" && b.elapsedMs >= MIN_ELAPSED_MS);
}

export const limitReached = (count: number, kind: keyof typeof LIMITS): boolean => count >= LIMITS[kind];

export const isStatus = (s: unknown): s is Status => typeof s === "string" && (STATUSES as readonly string[]).includes(s);

export function newId(random: () => number = Math.random): string {
  let id = "";
  for (let i = 0; i < 8; i++) id += Math.floor(random() * 36).toString(36);
  return id;
}

/** Where an item's votes land: follows mergedInto, stopping at a missing target, a cycle or 10 hops. */
export function rootOf(id: string, byId: Map<string, Item>): string {
  const seen = new Set<string>();
  let current = id;
  while (!seen.has(current) && seen.size < 10) {
    seen.add(current);
    const next = byId.get(current)?.mergedInto;
    if (!next || !byId.has(next)) return current;
    current = next;
  }
  return current;
}

/** The public board: visible items, each voter counted once, merged duplicates folded in, most votes first. */
export function board(items: Item[], voteKeys: string[]): BoardItem[] {
  const byId = new Map(items.map((i) => [i.id, i]));
  const voters = new Map<string, Set<string>>();
  for (const key of voteKeys) {
    const [prefix, id, voter] = key.split("/");
    if (prefix !== "votes" || !id || !voter || !byId.has(id)) continue;
    const root = rootOf(id, byId);
    if (!voters.has(root)) voters.set(root, new Set());
    voters.get(root)!.add(voter);
  }
  return items
    .filter((i) => !i.removed && !i.mergedInto)
    .map(({ id, title, details, status, created }) => ({ id, title, details, status, created, votes: voters.get(id)?.size ?? 0 }))
    .sort((a, b) => b.votes - a.votes || b.created.localeCompare(a.created));
}
