// A Netlify Blobs stand-in for tests: the same calls, kept in a Map.
import type { Store } from "./requests-api.ts";

export class MemoryStore implements Store {
  data = new Map<string, string>();
  async get(key: string) { const value = this.data.get(key); return value === undefined ? null : JSON.parse(value); }
  async setJSON(key: string, value: unknown) { this.data.set(key, JSON.stringify(value)); }
  async set(key: string, value: string) { this.data.set(key, value); }
  async delete(key: string) { this.data.delete(key); }
  async list({ prefix }: { prefix: string }) {
    return { blobs: [...this.data.keys()].filter((k) => k.startsWith(prefix)).sort().map((key) => ({ key })) };
  }
}
