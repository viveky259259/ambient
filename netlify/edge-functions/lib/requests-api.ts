// The feature-request board's HTTP API. Storage and secrets come in as Deps, so the same code runs
// in the edge function (Netlify Blobs) and in tests (MemoryStore).
import {
  board, cleanText, LIMITS, looksAutomated, newId, validateSubmission, type Item,
} from "./requests-core.ts";

export interface Store {
  get(key: string, options: { type: "json" }): Promise<unknown>;
  setJSON(key: string, value: unknown): Promise<unknown>;
  /** With onlyIfNew, resolves to { modified: false } when the key already exists. */
  set(key: string, value: string, options?: { onlyIfNew?: boolean }): Promise<unknown>;
  delete(key: string): Promise<unknown>;
  list(options: { prefix: string }): Promise<{ blobs: { key: string }[] }>;
}

export interface Deps {
  store: Store;
  secret: string | undefined;
  ip: string;
  now: Date;
}

const VOTER = /^[A-Za-z0-9-]{8,64}$/;
const ID = /^[a-z0-9]{8}$/;
const VOTE_PATH = /^\/api\/requests\/([a-z0-9]{8})\/vote$/;
/** A request body larger than this is refused before it's parsed. */
const BODY_MAX = 8192;

const json = (status: number, body: unknown, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", ...headers },
  });

async function hash(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("").slice(0, 32);
}

/** The JSON body, or the response that refuses it: too large (413) or not JSON (400). */
async function readBody(request: Request): Promise<{ body: Record<string, unknown> } | { refusal: Response }> {
  if (Number(request.headers.get("content-length") ?? 0) > BODY_MAX) return { refusal: json(413, { error: "That's too long to send." }) };
  const text = await request.text();
  if (text.length > BODY_MAX) return { refusal: json(413, { error: "That's too long to send." }) };
  try {
    const body = JSON.parse(text);
    if (body && typeof body === "object" && !Array.isArray(body)) return { body: body as Record<string, unknown> };
  } catch { /* fall through */ }
  return { refusal: json(400, { error: "Send the idea as JSON." }) };
}

const voterOf = (body: Record<string, unknown>): string | null =>
  typeof body.voter === "string" && VOTER.test(body.voter) ? body.voter : null;

const getItem = (store: Store, id: string) => store.get(`items/${id}`, { type: "json" }) as Promise<Item | null>;

export async function loadItems(store: Store): Promise<Item[]> {
  const { blobs } = await store.list({ prefix: "items/" });
  const items = await Promise.all(blobs.map((b) => store.get(b.key, { type: "json" })));
  return items.filter((i): i is Item => !!i && typeof i === "object" && typeof (i as Item).id === "string");
}

/** Deletes daily counts from before yesterday. Returns how many it deleted. */
export async function pruneLimits(store: Store, now: Date, all = false): Promise<number> {
  const yesterday = new Date(now.getTime() - 86_400_000).toISOString().slice(0, 10);
  const { blobs } = await store.list({ prefix: "limits/" });
  const stale = blobs.filter((b) => all || b.key.split("/")[1] < yesterday);
  await Promise.all(stale.map((b) => store.delete(b.key)));
  return stale.length;
}

/** Claims one of today's numbered slots for this network. A slot can be claimed once, so
 *  concurrent requests can't all slip under the limit. */
async function useAllowance(deps: Deps, network: string, kind: keyof typeof LIMITS): Promise<boolean> {
  const prefix = `limits/${deps.now.toISOString().slice(0, 10)}/${network}/${kind}/`;
  const used = (await deps.store.list({ prefix })).blobs.length;
  for (let slot = used; slot < LIMITS[kind]; slot++) {
    const result = await deps.store.set(prefix + slot, "1", { onlyIfNew: true }) as { modified?: boolean } | undefined;
    if (result?.modified !== false) return true;
  }
  return false;
}

/** Follows mergedInto to the request that's shown on the board. */
async function rootItem(store: Store, item: Item): Promise<Item> {
  const seen = new Set([item.id]);
  let current = item;
  while (current.mergedInto && ID.test(current.mergedInto) && !seen.has(current.mergedInto) && seen.size < 10) {
    const next = await getItem(store, current.mergedInto);
    if (!next) break;
    seen.add(next.id);
    current = next;
  }
  return current;
}

/** Distinct voters for a request and everything merged into it, listing only their votes. */
async function voteCount(store: Store, root: Item): Promise<number> {
  const ids = new Set([root.id]);
  let frontier = root.mergedFrom ?? [];
  while (frontier.length && ids.size < 50) {
    const fresh = frontier.filter((id) => ID.test(id) && !ids.has(id));
    fresh.forEach((id) => ids.add(id));
    const children = await Promise.all(fresh.map((id) => getItem(store, id)));
    frontier = children.flatMap((c) => c?.mergedFrom ?? []);
  }
  const lists = await Promise.all([...ids].map((id) => store.list({ prefix: `votes/${id}/` })));
  return new Set(lists.flatMap((l) => l.blobs.map((b) => b.key.split("/")[2]))).size;
}

async function post(request: Request, deps: Deps, secret: string, network: string): Promise<Response> {
  const read = await readBody(request);
  if ("refusal" in read) return read.refusal;
  const { body } = read;
  if (looksAutomated(body)) {
    const title = cleanText(body.title) || "Thanks";
    return json(201, { item: { id: newId(), title, details: cleanText(body.details), status: "open", created: deps.now.toISOString(), votes: 1 } });
  }
  const checked = validateSubmission(body);
  if (!checked.ok) return json(400, { error: checked.error });
  const voter = voterOf(body);
  if (!voter) return json(400, { error: "Missing voter." });
  if (!(await useAllowance(deps, network, "post"))) {
    return json(429, { error: `You've suggested ${LIMITS.post} things today. Thank you! Try again tomorrow.` });
  }
  const item: Item = { id: newId(), ...checked.value, status: "open", created: deps.now.toISOString() };
  const voterKey = `votes/${item.id}/${await hash(`${secret}:voter:${voter}`)}`;
  await Promise.all([
    deps.store.setJSON(`items/${item.id}`, item),
    deps.store.set(voterKey, "1"),
    pruneLimits(deps.store, deps.now),
  ]);
  const { id, title, details, status, created } = item;
  return json(201, { item: { id, title, details, status, created, votes: 1 } });
}

async function vote(request: Request, deps: Deps, secret: string, network: string, id: string): Promise<Response> {
  const read = await readBody(request);
  if ("refusal" in read) return read.refusal;
  const voter = voterOf(read.body);
  if (!voter) return json(400, { error: "Missing voter." });
  const key = `votes/${id}/${await hash(`${secret}:voter:${voter}`)}`;
  // Independent reads go together: each Blobs call is a round trip from the edge.
  const [target, existing] = await Promise.all([getItem(deps.store, id), deps.store.get(key, { type: "json" })]);
  if (!target || target.removed) return json(404, { error: "That request isn't on the board anymore." });
  const adding = request.method === "POST";
  if (adding === (existing === null)) {
    // A real change: every one, adding or taking back, uses today's allowance.
    if (!(await useAllowance(deps, network, "vote"))) {
      return json(429, { error: "That's a lot of votes for one day. Thank you! Try again tomorrow." });
    }
    await (adding ? deps.store.set(key, "1") : deps.store.delete(key));
  }
  return json(200, { votes: await voteCount(deps.store, await rootItem(deps.store, target)) });
}

const isJSON = (request: Request) => (request.headers.get("content-type") ?? "").toLowerCase().startsWith("application/json");

async function route(request: Request, deps: Deps): Promise<Response> {
  if (!deps.secret) return json(500, { error: "The board isn't set up yet. Try again in a moment." });
  const secret = deps.secret;
  const url = new URL(request.url);
  const path = url.pathname.replace(/\/+$/, "");
  const network = await hash(`${secret}:${deps.now.toISOString().slice(0, 10)}:${deps.ip}`);
  // Only the board's own page calls this, with JSON. Other sites' forms can't send JSON without
  // asking first, so they can't post or vote from their visitors' browsers.
  if (request.method !== "GET" && !isJSON(request)) return json(415, { error: "Send JSON." });

  if (path === "/api/requests") {
    if (request.method === "GET") {
      // A query string would make a new cache entry, so a script could skip the cache at will.
      if (url.search) return json(400, { error: "Unexpected query." });
      const [items, votes] = await Promise.all([loadItems(deps.store), deps.store.list({ prefix: "votes/" })]);
      return json(200, { items: board(items, votes.blobs.map((b) => b.key)) }, {
        "Cache-Control": "public, max-age=0, must-revalidate",
        "Netlify-CDN-Cache-Control": "public, s-maxage=30, stale-while-revalidate=60",
      });
    }
    if (request.method === "POST") return post(request, deps, secret, network);
    return json(405, { error: "Method not allowed." }, { Allow: "GET, POST" });
  }
  const match = path.match(VOTE_PATH);
  if (match && (request.method === "POST" || request.method === "DELETE")) return vote(request, deps, secret, network, match[1]);
  return json(404, { error: "Not found." });
}

export async function handle(request: Request, deps: Deps): Promise<Response> {
  try {
    return await route(request, deps);
  } catch (error) {
    console.error("feature requests failed", error);
    return json(500, { error: "Something went wrong. Try again in a moment." });
  }
}
