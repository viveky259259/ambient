// A Netlify Blobs stand-in for tests: the same calls, kept in a Map. `delayMs` makes every call
// yield first, like a network round trip, so tests can race concurrent requests; `listed` records
// each prefix listed, so tests can check what a request scanned.
import type { Store } from "./requests-api.ts";

export class MemoryStore implements Store {
  data = new Map<string, string>();
  listed: string[] = [];
  constructor(private delayMs = 0) {}

  private tick() { return new Promise((resolve) => setTimeout(resolve, this.delayMs)); }

  async get(key: string) {
    await this.tick();
    const value = this.data.get(key);
    return value === undefined ? null : JSON.parse(value);
  }
  async setJSON(key: string, value: unknown) { await this.tick(); this.data.set(key, JSON.stringify(value)); }
  async set(key: string, value: string, options: { onlyIfNew?: boolean } = {}) {
    await this.tick();
    if (options.onlyIfNew && this.data.has(key)) return { modified: false };
    this.data.set(key, value);
    return { modified: true };
  }
  async delete(key: string) { await this.tick(); this.data.delete(key); }
  async list({ prefix }: { prefix: string }) {
    await this.tick();
    this.listed.push(prefix);
    return { blobs: [...this.data.keys()].filter((k) => k.startsWith(prefix)).sort().map((key) => ({ key })) };
  }
}
