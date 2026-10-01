// The feature-request board's HTTP API. Storage and secrets come in as Deps, so the same code runs
// in the edge function (Netlify Blobs) and in tests (MemoryStore).
import {
  board, cleanText, LIMITS, limitReached, looksAutomated, newId, validateSubmission, type Item,
} from "./requests-core.ts";

export interface Store {
  get(key: string, options: { type: "json" }): Promise<unknown>;
  setJSON(key: string, value: unknown): Promise<unknown>;
  set(key: string, value: string): Promise<unknown>;
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
const VOTE_PATH = /^\/api\/requests\/([a-z0-9]{8})\/vote$/;

const json = (status: number, body: unknown, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", ...headers },
  });

async function hash(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("").slice(0, 32);
}

async function readBody(request: Request): Promise<Record<string, unknown> | null> {
  try {
    const body = await request.json();
    return body && typeof body === "object" && !Array.isArray(body) ? body as Record<string, unknown> : null;
  } catch {
    return null;
  }
}

const voterOf = (body: Record<string, unknown> | null): string | null =>
  body && typeof body.voter === "string" && VOTER.test(body.voter) ? body.voter : null;

export async function loadItems(store: Store): Promise<Item[]> {
  const { blobs } = await store.list({ prefix: "items/" });
  const items = await Promise.all(blobs.map((b) => store.get(b.key, { type: "json" })));
  return items.filter((i): i is Item => !!i && typeof i === "object" && typeof (i as Item).id === "string");
}

async function currentBoard(store: Store) {
  const [items, votes] = await Promise.all([loadItems(store), store.list({ prefix: "votes/" })]);
  return { items, board: board(items, votes.blobs.map((b) => b.key)) };
}

/** Records one use of today's allowance for this network, or says it's used up. */
async function useAllowance(deps: Deps, network: string, kind: keyof typeof LIMITS): Promise<boolean> {
  const prefix = `limits/${deps.now.toISOString().slice(0, 10)}/${network}/${kind}/`;
  const used = (await deps.store.list({ prefix })).blobs.length;
  if (limitReached(used, kind)) return false;
  await deps.store.set(prefix + crypto.randomUUID(), "1");
  return true;
}

async function post(request: Request, deps: Deps, secret: string, network: string): Promise<Response> {
  const body = await readBody(request);
  if (!body) return json(400, { error: "Send the idea as JSON." });
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
  await Promise.all([deps.store.setJSON(`items/${item.id}`, item), deps.store.set(voterKey, "1")]);
  const { id, title, details, status, created } = item;
  return json(201, { item: { id, title, details, status, created, votes: 1 } });
}

async function vote(request: Request, deps: Deps, secret: string, network: string, id: string): Promise<Response> {
  const voter = voterOf(await readBody(request));
  if (!voter) return json(400, { error: "Missing voter." });
  const key = `votes/${id}/${await hash(`${secret}:voter:${voter}`)}`;
  // Independent reads go together: each Blobs call is a round trip from the edge.
  const [target, existing] = await Promise.all([
    deps.store.get(`items/${id}`, { type: "json" }) as Promise<Item | null>,
    deps.store.get(key, { type: "json" }),
  ]);
  if (!target || target.removed) return json(404, { error: "That request isn't on the board anymore." });
  if (request.method === "POST") {
    if (existing === null) {
      if (!(await useAllowance(deps, network, "vote"))) {
        return json(429, { error: "That's a lot of votes for one day. Thank you! Try again tomorrow." });
      }
      await deps.store.set(key, "1");
    }
  } else {
    await deps.store.delete(key);
  }
  const { items, board: visible } = await currentBoard(deps.store);
  let root = id;
  const byId = new Map(items.map((i) => [i.id, i]));
  for (let hops = 0; byId.get(root)?.mergedInto && hops < 10; hops++) root = byId.get(root)!.mergedInto!;
  return json(200, { votes: visible.find((i) => i.id === root)?.votes ?? 0 });
}

async function route(request: Request, deps: Deps): Promise<Response> {
  if (!deps.secret) return json(500, { error: "The board isn't set up yet. Try again in a moment." });
  const secret = deps.secret;
  const path = new URL(request.url).pathname.replace(/\/+$/, "");
  const network = await hash(`${secret}:${deps.now.toISOString().slice(0, 10)}:${deps.ip}`);

  if (path === "/api/requests") {
    if (request.method === "GET") {
      const { board: items } = await currentBoard(deps.store);
      return json(200, { items }, {
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
