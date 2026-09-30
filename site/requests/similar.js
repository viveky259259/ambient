// Titles that look like the one being typed, so people vote for an existing idea instead of repeating it.
const words = (s) => new Set(String(s).toLowerCase().match(/[\p{L}\p{N}]{3,}/gu) ?? []);

/** Up to `limit` items sharing at least half their words with `title` (of the shorter title), best first. */
export function similar(title, items, limit = 3) {
  const typed = words(title);
  if (typed.size === 0) return [];
  return items
    .map((item) => {
      const theirs = words(item.title);
      let shared = 0;
      for (const w of typed) if (theirs.has(w)) shared++;
      return { item, score: theirs.size ? shared / Math.min(typed.size, theirs.size) : 0 };
    })
    .filter((m) => m.score >= 0.5)
    .sort((a, b) => b.score - a.score || b.item.votes - a.item.votes)
    .slice(0, limit)
    .map((m) => m.item);
}
