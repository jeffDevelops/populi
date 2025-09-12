// In-memory storage implementation
import type { Storage } from './types.js'

export class MemoryStorage implements Storage {
  private data = new Map<string, unknown>()

  async get(key: string): Promise<unknown> {
    return this.data.get(key)
  }

  async set(key: string, value: unknown): Promise<void> {
    this.data.set(key, value)
  }
}
