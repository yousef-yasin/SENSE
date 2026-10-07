import { type DBSchema, type IDBPDatabase, openDB } from 'idb';
import type { CaptureSource, ExtractedEntity, Highlight, MemoryKind, Origin } from '../core/models';

export interface MemoryRecord {
  id: string;
  kind: MemoryKind;
  source: CaptureSource;
  origin: Origin;
  title: string;
  summary: string;
  content: string;
  tags: string[];
  highlights: Highlight[];
  entities: ExtractedEntity[];
  createdAt: Date;
  placeName?: string;
  imageId?: string;
  embedding?: Float32Array;
  embeddingModel?: string;
}

export interface ReminderRecord {
  id: string;
  title: string;
  body: string;
  fireAt: Date;
  createdAt: Date;
  memoryId?: string;
  delivered: boolean;
}

interface SenseDB extends DBSchema {
  memories: { key: string; value: MemoryRecord };
  images: { key: string; value: Blob };
  reminders: { key: string; value: ReminderRecord };
}

let connection: Promise<IDBPDatabase<SenseDB>> | undefined;

export function database(): Promise<IDBPDatabase<SenseDB>> {
  connection ??= openDB<SenseDB>('sense', 1, {
    upgrade(db) {
      db.createObjectStore('memories', { keyPath: 'id' });
      db.createObjectStore('images');
      db.createObjectStore('reminders', { keyPath: 'id' });
    },
  });
  return connection;
}

export function newID(): string {
  return crypto.randomUUID();
}
