import type { Calendar } from './calendar';

export type CaptureSource = 'camera' | 'photo' | 'live' | 'voice' | 'text';

export interface ImageLabel {
  identifier: string;
  confidence: number;
}

export function labelDisplayName(identifier: string): string {
  return identifier
    .replace(/_/g, ' ')
    .split(' ')
    .filter((part) => part.length > 0)
    .map((part) => part.slice(0, 1).toUpperCase() + part.slice(1))
    .join(' ');
}

export interface CaptureInput {
  source: CaptureSource;
  text: string;
  imageLabels: ImageLabel[];
  capturedAt: Date;
  placeName?: string;
}

export function makeInput(source: CaptureSource, text: string, imageLabels: ImageLabel[] = [], capturedAt = new Date()): CaptureInput {
  return { source, text, imageLabels, capturedAt };
}

export function inputIsEmpty(input: CaptureInput): boolean {
  return input.text.trim().length === 0 && input.imageLabels.length === 0;
}

export const MEMORY_KINDS = ['note', 'document', 'receipt', 'announcement', 'event', 'task', 'object', 'place', 'observation', 'person'] as const;
export type MemoryKind = (typeof MEMORY_KINDS)[number];

export function isMemoryKind(value: string): value is MemoryKind {
  return (MEMORY_KINDS as readonly string[]).includes(value);
}

export type EntityKind = 'date' | 'money' | 'email' | 'phone' | 'link' | 'merchant' | 'label';

export interface ExtractedEntity {
  kind: EntityKind;
  text: string;
  value: string;
  date?: Date;
}

export function entity(kind: EntityKind, text: string, value?: string, date?: Date): ExtractedEntity {
  return date ? { kind, text, value: value ?? text, date } : { kind, text, value: value ?? text };
}

export type HighlightKind = 'deadline' | 'warning' | 'requirement' | 'date' | 'info';

export interface Highlight {
  kind: HighlightKind;
  text: string;
  date?: Date;
}

export type ReminderTiming =
  | { type: 'at'; date: Date }
  | { type: 'arriving'; place: string }
  | { type: 'leaving'; place: string }
  | { type: 'unspecified' };

export interface ReminderDraft {
  title: string;
  timing: ReminderTiming;
  dueDate?: Date;
  refersToContext: boolean;
}

export type SuggestedAction =
  | { type: 'reminder'; draft: ReminderDraft }
  | { type: 'openLink'; url: string }
  | { type: 'call'; number: string }
  | { type: 'email'; address: string };

export type Origin = 'onDevice' | 'remote' | 'onDeviceFallback';

export interface Understanding {
  kind: MemoryKind;
  title: string;
  summary: string;
  highlights: Highlight[];
  entities: ExtractedEntity[];
  suggestions: SuggestedAction[];
  tags: string[];
  origin: Origin;
}

export function reminderSuggestions(understanding: Understanding): ReminderDraft[] {
  return understanding.suggestions.flatMap((s) => (s.type === 'reminder' ? [s.draft] : []));
}

export const ReminderPolicy = {
  defaultHour: 9,

  suggestedFireDate(due: Date, includesTime: boolean, isDeadline: boolean, now: Date, calendar: Calendar): Date | null {
    const anchored = includesTime ? due : calendar.settingTime(due, ReminderPolicy.defaultHour, 0);
    if (anchored.getTime() <= now.getTime()) return null;

    const candidates: Date[] = [];
    if (isDeadline) candidates.push(calendar.addDays(anchored, -1));
    if (includesTime) candidates.push(new Date(anchored.getTime() - 3600_000));
    candidates.push(anchored);

    const soonest = now.getTime() + 300_000;
    return candidates.find((c) => c.getTime() > soonest) ?? anchored;
  },
};
