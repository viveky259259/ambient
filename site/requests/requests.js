// The feature-request board. No account and no cookies: a random voter ID and the IDs you've voted
// for stay in this browser's storage. User text is only ever set with textContent.
import { similar } from "./similar.js";

const loadedAt = performance.now();
// The server treats anything sent sooner than 3 s after the page loaded as a bot, so wait at least that long.
const MIN_WAIT_MS = 3100;
const params = new URLSearchParams(location.search);
const source = params.get("from") === "app" ? "app" : "site";
const version = params.get("v") || "";

// Storage can be unavailable (private windows, blocked site data); never let it break the page.
const store = {
  get(key) { try { return localStorage.getItem(key); } catch { return null; } },
  set(key, value) { try { localStorage.setItem(key, value); } catch { /* ignore */ } },
};
const track = (name, data) => { try { window.umami?.track(name, data); } catch { /* ignore */ } };

const voter = store.get("ambient-voter") || (() => { const id = crypto.randomUUID(); store.set("ambient-voter", id); return id; })();
const voted = new Set((() => { try { return JSON.parse(store.get("ambient-votes") || "[]"); } catch { return []; } })());
const saveVoted = () => store.set("ambient-votes", JSON.stringify([...voted]));

const LABELS = { planned: "Planned", "in-progress": "In progress", shipped: "Shipped" };
const state = { items: [], sort: "top", filter: "all" };
const $ = (id) => document.getElementById(id);
const list = $("rq-list"), message = $("rq-message"), form = $("rq-form"), title = $("rq-title");
const details = $("rq-details"), hint = $("rq-hint"), submit = $("rq-submit"), formError = $("rq-form-error");

async function api(method, path, body) {
  const res = await fetch(path, {
    method,
    headers: body ? { "Content-Type": "application/json" } : {},
    body: body ? JSON.stringify(body) : undefined,
  });
  let data = {};
  try { data = await res.json(); } catch { /* not JSON */ }
  return { ok: res.ok, data };
}
const safely = (promise) => promise.catch(() => ({ ok: false, data: {} }));
const say = (text) => { message.textContent = text; };
const plural = (n) => `${n} vote${n === 1 ? "" : "s"}`;

function shown() {
  const items = state.items.filter((i) => state.filter === "all" || i.status === state.filter);
  return items.sort(state.sort === "new"
    ? (a, b) => b.created.localeCompare(a.created)
    : (a, b) => b.votes - a.votes || b.created.localeCompare(a.created));
}

function paintVote(button, item) {
  const mine = voted.has(item.id);
  button.setAttribute("aria-pressed", String(mine));
  button.setAttribute("aria-label", `${mine ? "Take back your vote for" : "Vote for"} ${item.title}. ${plural(item.votes)}.`);
  button.querySelector(".rq-count").textContent = String(item.votes);
}

function row(item) {
  const li = document.createElement("li");
  li.className = "rq-item";
  li.id = `req-${item.id}`;
  const button = document.createElement("button");
  button.type = "button";
  button.className = "rq-vote";
  const arrow = document.createElement("span");
  arrow.className = "rq-arrow";
  arrow.setAttribute("aria-hidden", "true");
  arrow.textContent = "▲";
  const count = document.createElement("span");
  count.className = "rq-count";
  button.append(arrow, count);
  paintVote(button, item);
  button.addEventListener("click", () => toggleVote(item));
  const body = document.createElement("div");
  body.className = "rq-body";
  const heading = document.createElement("h3");
  heading.textContent = item.title;
  if (LABELS[item.status]) {
    const badge = document.createElement("span");
    badge.className = `rq-badge rq-${item.status}`;
    badge.textContent = LABELS[item.status];
    heading.append(" ", badge);
  }
  body.append(heading);
  if (item.details) {
    const p = document.createElement("p");
    p.textContent = item.details;
    body.append(p);
  }
  li.append(button, body);
  return li;
}

function render() {
  const items = shown();
  if (!items.length) {
    const li = document.createElement("li");
    li.className = "rq-empty";
    li.textContent = state.items.length ? "Nothing here yet." : "No requests yet. Be the first.";
    list.replaceChildren(li);
    return;
  }
  list.replaceChildren(...items.map(row));
}

function syncControls() {
  document.querySelectorAll("[data-sort]").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.sort === state.sort)));
  document.querySelectorAll("[data-filter]").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.filter === state.filter)));
}

// A vote shows at once; the server's count replaces the guess when it answers (it can take a second
// or two), and a failure puts things back. Only that row's button changes: the list isn't rebuilt or
// re-sorted, so rows don't move under the pointer and keyboard focus stays wherever it is.
const pending = new Set();

function applyVote(item, mine, votes) {
  if (mine) voted.add(item.id); else voted.delete(item.id);
  saveVoted();
  item.votes = votes;
  const button = document.querySelector(`#req-${item.id} .rq-vote`);
  if (button) paintVote(button, item);
}

async function toggleVote(item) {
  if (pending.has(item.id)) return;
  pending.add(item.id);
  const adding = !voted.has(item.id);
  const before = item.votes;
  applyVote(item, adding, before + (adding ? 1 : -1));
  const { ok, data } = await safely(api(adding ? "POST" : "DELETE", `/api/requests/${item.id}/vote`, { voter }));
  pending.delete(item.id);
  if (!ok) {
    applyVote(item, !adding, before);
    return say(data.error || "Couldn't save your vote. Try again in a moment.");
  }
  if (adding) track("Vote");
  applyVote(item, adding, data.votes);
}

function showHint() {
  const matches = similar(title.value, state.items);
  if (!matches.length) { hint.hidden = true; hint.replaceChildren(); return; }
  const lead = document.createElement("p");
  lead.textContent = "Is it one of these? Vote instead.";
  const ul = document.createElement("ul");
  for (const match of matches) {
    const li = document.createElement("li");
    const a = document.createElement("a");
    a.href = `#req-${match.id}`;
    a.textContent = `${match.title} (${plural(match.votes)})`;
    a.addEventListener("click", (event) => {
      event.preventDefault();
      state.filter = "all";
      syncControls();
      render();
      const target = document.getElementById(`req-${match.id}`);
      target?.scrollIntoView({ block: "center" });
      target?.querySelector(".rq-vote")?.focus();
    });
    li.append(a);
    ul.append(li);
  }
  hint.replaceChildren(lead, ul);
  hint.hidden = false;
}

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  formError.textContent = "";
  if (title.value.trim().length < 3) {
    formError.textContent = "Give your idea a title of at least 3 characters.";
    title.focus();
    return;
  }
  submit.disabled = true;
  submit.textContent = "Sending…";
  const wait = MIN_WAIT_MS - (performance.now() - loadedAt);
  if (wait > 0) await new Promise((resolve) => setTimeout(resolve, wait));
  const { ok, data } = await safely(api("POST", "/api/requests", {
    title: title.value, details: details.value, source, version, voter,
    website: form.elements.website.value, elapsedMs: Math.round(performance.now() - loadedAt),
  }));
  submit.disabled = false;
  submit.textContent = "Suggest it";
  if (!ok) { formError.textContent = data.error || "Couldn't send your idea. Check your connection and try again."; return; }
  voted.add(data.item.id);
  saveVoted();
  state.items.unshift(data.item);
  state.sort = "new";
  state.filter = "all";
  syncControls();
  render();
  form.reset();
  hint.hidden = true;
  say("Thanks! It's on the board, with your vote.");
  track("Request posted", { from: source });
});

title.addEventListener("input", showHint);
document.querySelectorAll("[data-sort]").forEach((b) => b.addEventListener("click", () => { state.sort = b.dataset.sort; syncControls(); render(); }));
document.querySelectorAll("[data-filter]").forEach((b) => b.addEventListener("click", () => { state.filter = b.dataset.filter; syncControls(); render(); }));

syncControls();
say("Loading the board…");
const { ok, data } = await safely(api("GET", "/api/requests"));
if (ok && Array.isArray(data.items)) {
  state.items = data.items;
  say("");
  render();
} else {
  say("The board couldn't load. Try again in a moment.");
}
