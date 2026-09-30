// Content negotiation for agents: a request that prefers text/markdown gets llms.txt for the
// homepage and a Markdown 404 for missing pages. Browsers, which ask for text/html, get HTML.
import type { Config, Context } from "https://edge.netlify.com";

const MARKDOWN = "text/markdown; charset=utf-8";

const NOT_FOUND = `# Page not found

There's no page at this address on yaml.cafe, the site for Ambient, a free Mac app that shows what Claude Code, Codex and Gemini CLI are doing.

- About Ambient, for agents: https://yaml.cafe/llms.txt
- Every page: https://yaml.cafe/sitemap.xml
- Guides: https://yaml.cafe/guides/
`;

/** The q-value the Accept header gives a media type, or -1 when it isn't listed. */
function quality(accept: string, type: string): number {
  for (const part of accept.split(",")) {
    const [media, ...params] = part.split(";").map((s) => s.trim().toLowerCase());
    if (media !== type) continue;
    const q = params.find((p) => p.startsWith("q="));
    return q ? Number(q.slice(2)) || 0 : 1;
  }
  return -1;
}

function prefersMarkdown(accept: string | null): boolean {
  if (!accept) return false;
  const markdown = quality(accept, "text/markdown");
  return markdown > 0 && markdown >= quality(accept, "text/html");
}

function withVary(response: Response): Response {
  const headers = new Headers(response.headers);
  headers.append("Vary", "Accept");
  return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
}

export default async (request: Request, context: Context) => {
  const wantsMarkdown = prefersMarkdown(request.headers.get("accept"));
  const url = new URL(request.url);

  if (wantsMarkdown && url.pathname === "/") {
    const llms = await fetch(new URL("/llms.txt", url));
    if (llms.ok) {
      return new Response(await llms.text(), { headers: { "Content-Type": MARKDOWN, "Vary": "Accept" } });
    }
  }

  const response = await context.next();
  if (wantsMarkdown && response.status === 404) {
    return new Response(NOT_FOUND, { status: 404, headers: { "Content-Type": MARKDOWN, "Vary": "Accept" } });
  }
  return withVary(response);
};

export const config: Config = {
  path: "/*",
  excludedPath: ["/api/*", "/assets/*", "/downloads/*", "/*.css", "/*.js", "/*.txt", "/*.xml"],
};
