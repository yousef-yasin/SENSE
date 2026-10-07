import { computed, signal } from '@preact/signals';
import type { MemoryKind } from '../core/models';
import { HashingEmbedder, MemorySearchEngine, QueryParser, type SearchDocument, embeddingText } from '../core/search';
import { type MemoryRecord, type ReminderRecord, database, newID } from './db';
import { SenseError } from './errors';
import type { CaptureDraft } from './pipeline';

export const memories = signal<MemoryRecord[]>([]);
export const reminders = signal<ReminderRecord[]>([]);
export const storageReady = signal(false);
export const storageError = signal<SenseError | undefined>(undefined);
export const openReminders = computed(() => reminders.value.filter((r) => !r.delivered).sort((a, b) => a.fireAt.getTime() - b.fireAt.getTime()));

const embedder = new HashingEmbedder();
const engine = new MemorySearchEngine(embedder);
const queryParser = new QueryParser();

const byNewest = (a: MemoryRecord, b: MemoryRecord) => b.createdAt.getTime() - a.createdAt.getTime();

export async function loadAll() {
  try {
    const db = await database();
    const [allMemories, allReminders] = await Promise.all([db.getAll('memories'), db.getAll('reminders')]);
    const stale = allMemories.filter((m) => m.embeddingModel !== embedder.identifier);
    if (stale.length > 0) {
      const tx = db.transaction('memories', 'readwrite');
      for (const memory of stale) {
        refreshEmbedding(memory);
        await tx.store.put(memory);
      }
      await tx.done;
    }
    memories.value = allMemories.sort(byNewest);
    reminders.value = allReminders;
  } catch {
    storageError.value = new SenseError('storageUnavailable');
  } finally {
    storageReady.value = true;
  }
}

function searchableBody(summary: string, content: string, highlights: { text: string }[], place?: string): string {
  return [summary, content, ...highlights.map((h) => h.text), place ?? ''].join('\n');
}

function documentFor(memory: MemoryRecord): SearchDocument {
  return {
    id: memory.id,
    title: memory.title,
    body: searchableBody(memory.summary, memory.content, memory.highlights, memory.placeName),
    tags: memory.tags,
    kind: memory.kind,
    createdAt: memory.createdAt,
    placeName: memory.placeName,
    embedding: memory.embedding,
  };
}

function refreshEmbedding(memory: MemoryRecord) {
  memory.embedding = embedder.embed(embeddingText(documentFor(memory)));
  memory.embeddingModel = embedder.identifier;
}

let persistenceRequested = false;

export async function saveMemory(draft: CaptureDraft, title: string, kind: MemoryKind): Promise<MemoryRecord> {
  const db = await database();
  const understanding = draft.understanding;
  const memory: MemoryRecord = {
    id: newID(),
    kind,
    source: draft.input.source,
    origin: understanding.origin,
    title: title.trim(),
    summary: understanding.summary,
    content: draft.input.text,
    tags: understanding.tags,
    highlights: understanding.highlights,
    entities: understanding.entities,
    createdAt: draft.input.capturedAt,
    placeName: draft.input.placeName,
  };
  if (draft.image) memory.imageId = newID();
  refreshEmbedding(memory);

  const tx = db.transaction(['memories', 'images'], 'readwrite');
  if (draft.image && memory.imageId) await tx.objectStore('images').put(draft.image, memory.imageId);
  await tx.objectStore('memories').put(memory);
  await tx.done;

  memories.value = [memory, ...memories.value].sort(byNewest);
  if (!persistenceRequested) {
    persistenceRequested = true;
    navigator.storage?.persist?.().catch(() => undefined);
  }
  return memory;
}

export async function updateMemory(id: string, title: string, kind: MemoryKind) {
  const current = memories.value.find((m) => m.id === id);
  if (!current) return;
  const updated: MemoryRecord = { ...current, title: title.trim(), kind };
  refreshEmbedding(updated);
  await (await database()).put('memories', updated);
  memories.value = memories.value.map((m) => (m.id === id ? updated : m));
}

export async function deleteMemory(id: string) {
  const memory = memories.value.find((m) => m.id === id);
  const linked = reminders.value.filter((r) => r.memoryId === id);
  const db = await database();
  const tx = db.transaction(['memories', 'images', 'reminders'], 'readwrite');
  await tx.objectStore('memories').delete(id);
  if (memory?.imageId) await tx.objectStore('images').delete(memory.imageId);
  for (const reminder of linked) await tx.objectStore('reminders').delete(reminder.id);
  await tx.done;
  if (memory?.imageId) releaseImageURL(memory.imageId);
  memories.value = memories.value.filter((m) => m.id !== id);
  reminders.value = reminders.value.filter((r) => r.memoryId !== id);
}

export function memoryByID(id: string): MemoryRecord | undefined {
  return memories.value.find((m) => m.id === id);
}

export function search(text: string): MemoryRecord[] {
  const all = memories.value;
  const hits = engine.search(queryParser.parse(text), all.map(documentFor));
  const byID = new Map(all.map((m) => [m.id, m]));
  return hits.flatMap((hit) => byID.get(hit.id) ?? []);
}

export function similarTo(memory: MemoryRecord): MemoryRecord[] {
  const all = memories.value;
  const byID = new Map(all.map((m) => [m.id, m]));
  return engine.similar(documentFor(memory), all.map(documentFor)).flatMap((hit) => byID.get(hit.id) ?? []);
}

export function similarToDraft(draft: CaptureDraft): MemoryRecord[] {
  const all = memories.value;
  const target: SearchDocument = {
    id: draft.id,
    title: draft.understanding.title,
    body: searchableBody(draft.understanding.summary, draft.input.text, draft.understanding.highlights, draft.input.placeName),
    tags: draft.understanding.tags,
    kind: draft.understanding.kind,
    createdAt: draft.input.capturedAt,
    placeName: draft.input.placeName,
  };
  target.embedding = embedder.embed(embeddingText(target));
  const byID = new Map(all.map((m) => [m.id, m]));
  return engine.similar(target, all.map(documentFor), 3).flatMap((hit) => byID.get(hit.id) ?? []);
}

export async function createReminder(input: { title: string; body: string; fireAt: Date; memoryId?: string }): Promise<ReminderRecord> {
  if (input.fireAt.getTime() <= Date.now()) throw new SenseError('reminderInPast');
  const reminder: ReminderRecord = {
    id: newID(),
    title: input.title.trim() || 'Reminder',
    body: input.body,
    fireAt: input.fireAt,
    createdAt: new Date(),
    delivered: false,
  };
  if (input.memoryId) reminder.memoryId = input.memoryId;
  await (await database()).put('reminders', reminder);
  reminders.value = [...reminders.value, reminder];
  return reminder;
}

export async function deleteReminder(id: string) {
  await (await database()).delete('reminders', id);
  reminders.value = reminders.value.filter((r) => r.id !== id);
}

export async function markDelivered(ids: string[]) {
  if (ids.length === 0) return;
  const db = await database();
  const tx = db.transaction('reminders', 'readwrite');
  const updated = reminders.value.map((r) => (ids.includes(r.id) ? { ...r, delivered: true } : r));
  for (const reminder of updated) if (ids.includes(reminder.id)) await tx.store.put(reminder);
  await tx.done;
  reminders.value = updated;
}

export async function eraseAll() {
  const db = await database();
  const tx = db.transaction(['memories', 'images', 'reminders'], 'readwrite');
  await Promise.all([tx.objectStore('memories').clear(), tx.objectStore('images').clear(), tx.objectStore('reminders').clear()]);
  await tx.done;
  for (const id of imageURLs.keys()) releaseImageURL(id);
  memories.value = [];
  reminders.value = [];
}

const imageURLs = new Map<string, string>();

export async function imageURL(imageId: string): Promise<string | undefined> {
  const cached = imageURLs.get(imageId);
  if (cached) return cached;
  const blob = await (await database()).get('images', imageId);
  if (!blob) return undefined;
  const url = URL.createObjectURL(blob);
  imageURLs.set(imageId, url);
  return url;
}

function releaseImageURL(imageId: string) {
  const url = imageURLs.get(imageId);
  if (url) URL.revokeObjectURL(url);
  imageURLs.delete(imageId);
}
