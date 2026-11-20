// Keeps the homepage design test's tools off the public site. Visitors' browsers load a theme's styles, fonts and
// art from /themes/; the gallery, the manifest, each theme's meta.json and the notes answer 404 except on this Mac
// and on Netlify draft and branch deploys. See PREVIEW_HOST in lib/ab-core.ts.
import type { Config, Context } from "https://edge.netlify.com";
import { PREVIEW_HOST, visitorThemeFile } from "./lib/ab-core.ts";

export default async (request: Request, context: Context) => {
  const url = new URL(request.url);
  if (visitorThemeFile(url.pathname) || PREVIEW_HOST.test(url.hostname)) return context.next();
  const page = await fetch(new URL("/404.html", url));
  return new Response(page.ok ? page.body : "Not found", {
    status: 404,
    headers: { "Content-Type": "text/html; charset=utf-8", "X-Robots-Tag": "noindex" },
  });
};

export const config: Config = { path: ["/themes", "/themes/*"] };
