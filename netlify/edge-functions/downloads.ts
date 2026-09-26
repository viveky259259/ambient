// Counts DMG downloads without identifying anyone: one Netlify Blobs entry per download, keyed by
// day, version, launch tag (the ?ref= a launch post links with) and country. No IP address, cookie
// or email is stored. scripts/downloads.sh prints the totals.
import { getStore } from "@netlify/blobs";
import type { Config, Context } from "https://edge.netlify.com";

// Link previews (Slack, Discord, iMessage, Telegram, WhatsApp) fetch links too; they aren't downloads.
const BOTS = /bot|crawl|spider|slurp|preview|facebookexternalhit|embedly|headless|whatsapp/i;

const clean = (value: string | null) =>
  (value ?? "").toLowerCase().replace(/[^a-z0-9._-]/g, "").slice(0, 60);

/** The launch tag: ?ref= on the DMG link, else the ?ref= of the page that linked it, else where it came from. */
function launchTag(request: Request, url: URL): string {
  const direct = clean(url.searchParams.get("ref"));
  if (direct) return direct;
  const referer = request.headers.get("referer");
  if (!referer) return "direct";
  try {
    const from = new URL(referer);
    if (from.hostname !== url.hostname) return clean(from.hostname) || "direct";
    return clean(from.searchParams.get("ref")) || "site";
  } catch {
    return "direct";
  }
}

/** A real download: a GET from a person, from the first byte (a resumed download isn't a new one).
 *  Netlify hands HEAD requests to edge functions as GET, so a HEAD from a non-bot still counts. */
function isDownload(request: Request): boolean {
  const range = request.headers.get("range");
  return request.method === "GET" &&
    !BOTS.test(request.headers.get("user-agent") ?? "") &&
    (!range || /^bytes=0-/.test(range));
}

export default async (request: Request, context: Context) => {
  const response = await context.next();
  if (!isDownload(request) || (response.status !== 200 && response.status !== 206)) return response;

  try {
    const url = new URL(request.url);
    const version = url.pathname.match(/Ambient-([\d.]+)\.dmg$/)?.[1] ?? "other";
    const day = new Date().toISOString().slice(0, 10);
    const country = clean(context.geo?.country?.code ?? null).toUpperCase() || "XX";
    const key = `${day}/${version}/${launchTag(request, url)}/${country}/${crypto.randomUUID()}`;
    const write = getStore("downloads")
      .set(key, "1")
      .catch((error) => console.error("download count failed", error));
    // Never hold up the download for the count.
    if (typeof context.waitUntil === "function") context.waitUntil(write); else await write;
  } catch (error) {
    console.error("download count failed", error);
  }
  return response;
};

export const config: Config = { path: "/downloads/*" };
