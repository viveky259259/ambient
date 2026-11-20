// The homepage design test, without anything that identifies a visitor: site/themes/loader.js gives each new
// visitor a design (a variant) and posts {v} once; their download carries ?v=. A view is one Netlify Blobs entry
// keyed by day and variant. scripts/ab-report.sh compares downloads per visitor across variants.

/** Link previews and crawlers aren't visitors. */
export const BOTS = /bot|crawl|spider|slurp|preview|facebookexternalhit|embedly|headless|lighthouse|whatsapp/i;

/** A variant id as the loader writes it, or "" for anything else. */
export function cleanVariant(value: unknown): string {
  return typeof value === "string" && /^[a-z0-9-]{1,40}$/.test(value) ? value : "";
}

/** The variant in a beacon's body (sendBeacon sends JSON as text/plain). */
export function variantFromBody(body: string): string {
  if (body.length > 200) return "";
  try {
    return cleanVariant(JSON.parse(body)?.v);
  } catch {
    return "";
  }
}

export function viewKey(day: string, variant: string, id: string): string {
  return `${day}/${variant}/${id}`;
}

/**
 * Where the test's tools work: ?theme= previews, the /themes/ gallery, the manifest and the notes. That's this Mac
 * (localhost, *.localhost) and Netlify draft and branch deploys (<id>--<site>.netlify.app), never yaml.cafe or
 * <site>.netlify.app. Keep in step with PREVIEW_HOST in site/themes/loader.js.
 */
export const PREVIEW_HOST = /^(localhost|127\.0\.0\.1|\[::1\])$|\.localhost$|--[a-z0-9-]+\.netlify\.app$/i;

/** What every visitor's browser needs from /themes/: a theme's styles, fonts and art, and the loader. */
export function visitorThemeFile(path: string): boolean {
  return /^\/themes\/(loader\.js|system\.css|fonts\/[a-z0-9-]+\.woff2|[a-z0-9-]+\/(theme\.css|fonts\.css|motif\.js))$/.test(path);
}

/** Download keys are day/version/tag/country/id, or day/version/tag/country/variant/id from the design test. */
export function downloadVariant(key: string): string | null {
  const parts = key.split("/");
  return parts.length === 6 ? parts[4] : null;
}
