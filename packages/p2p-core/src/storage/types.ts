// Storage interface definitions
export interface Storage {
  get(key: string): Promise<unknown>
  set(key: string, value: unknown): Promise<void>
}
