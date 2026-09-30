// Moderation for the feature-request board, over the same Store the edge function uses.
import { loadItems, type Store } from "../netlify/edge-functions/lib/requests-api.ts";
import { board, rootOf, type BoardItem, type Item, type Status } from "../netlify/edge-functions/lib/requests-core.ts";

async function find(store: Store, id: string): Promise<Item> {
  const item = await store.get(`items/${id}`, { type: "json" }) as Item | null;
  if (!item) throw new Error(`No request ${id}.`);
  return item;
}

export async function listBoard(store: Store): Promise<BoardItem[]> {
  const [items, votes] = await Promise.all([loadItems(store), store.list({ prefix: "votes/" })]);
  return board(items, votes.blobs.map((b) => b.key));
}

export async function setStatus(store: Store, id: string, status: Status): Promise<void> {
  await store.setJSON(`items/${id}`, { ...(await find(store, id)), status });
}

export async function remove(store: Store, id: string): Promise<void> {
  await store.setJSON(`items/${id}`, { ...(await find(store, id)), removed: true });
}

export async function merge(store: Store, from: string, into: string): Promise<void> {
  if (from === into) throw new Error("A request can't be merged into itself.");
  const source = await find(store, from);
  await find(store, into);
  const byId = new Map((await loadItems(store)).map((i) => [i.id, i]));
  if (rootOf(into, byId) === from) throw new Error(`${into} is already merged into ${from}.`);
  await store.setJSON(`items/${from}`, { ...source, mergedInto: into });
}

/** Deletes a request and its votes outright. For test data; use remove for real requests. */
export async function purge(store: Store, id: string): Promise<void> {
  const { blobs } = await store.list({ prefix: `votes/${id}/` });
  await Promise.all(blobs.map((b) => store.delete(b.key)));
  await store.delete(`items/${id}`);
}

export const createdSince = (items: BoardItem[], iso: string): BoardItem[] =>
  items.filter((i) => i.created > iso).sort((a, b) => a.created.localeCompare(b.created));

export async function pruneLimits(store: Store, now: Date, all = false): Promise<number> {
  const yesterday = new Date(now.getTime() - 86_400_000).toISOString().slice(0, 10);
  const { blobs } = await store.list({ prefix: "limits/" });
  const stale = blobs.filter((b) => all || b.key.split("/")[1] < yesterday);
  await Promise.all(stale.map((b) => store.delete(b.key)));
  return stale.length;
}
