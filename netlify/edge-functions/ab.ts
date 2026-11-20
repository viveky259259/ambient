// Counts the homepage design test's visitors: one Netlify Blobs entry per new visitor, keyed by day and the design
// they were shown. No IP address, cookie or identifier is stored. See lib/ab-core.ts and scripts/ab-report.sh.
import { getStore } from "@netlify/blobs";
import type { Config, Context } from "https://edge.netlify.com";
import { BOTS, PREVIEW_HOST, variantFromBody, viewKey } from "./lib/ab-core.ts";

export default async (request: Request, context: Context) => {
  if (request.method !== "POST") return new Response(null, { status: 405, headers: { Allow: "POST" } });
  if (BOTS.test(request.headers.get("user-agent") ?? "")) return new Response(null, { status: 204 });
  const variant = variantFromBody(await request.text());
  if (!variant) return new Response(null, { status: 400 });
  // Visits to a draft deploy are testing, not visitors: they go to a store of their own that the report doesn't read.
  const store = PREVIEW_HOST.test(new URL(request.url).hostname) ? "ab-views-preview" : "ab-views";
  const write = getStore(store)
    .set(viewKey(new Date().toISOString().slice(0, 10), variant, crypto.randomUUID()), "1")
    .catch((error) => console.error("design-test count failed", error));
  if (typeof context.waitUntil === "function") context.waitUntil(write); else await write;
  return new Response(null, { status: 204 });
};

export const config: Config = { path: "/api/ab", method: "POST" };
