// The feature-request board's API at /api/requests (see lib/requests-api.ts). Votes and requests live
// in the Netlify Blobs store "requests"; REQUESTS_SECRET keys the one-way hashes for voters and networks.
import { getStore } from "@netlify/blobs";
import type { Config, Context } from "https://edge.netlify.com";
import { handle, type Store } from "./lib/requests-api.ts";

export default (request: Request, context: Context) =>
  handle(request, {
    store: getStore({ name: "requests", consistency: "strong" }) as unknown as Store,
    secret: Netlify.env.get("REQUESTS_SECRET"),
    ip: context.ip,
    now: new Date(),
  });

export const config: Config = { path: ["/api/requests", "/api/requests/*"], cache: "manual" };
