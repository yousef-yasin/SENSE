import type { ComponentType } from 'preact';
import {
  BadgeCheck,
  Box,
  Calendar,
  Camera,
  CreditCard,
  Eye,
  FileText,
  Hourglass,
  Image,
  ListChecks,
  MapPin,
  Megaphone,
  Mic,
  ScanLine,
  Smartphone,
  Sparkle,
  Sparkles,
  StickyNote,
  TextCursor,
  TriangleAlert,
  User,
  WifiOff,
} from 'lucide-preact';
import type { CaptureSource, HighlightKind, MemoryKind, Origin } from '../core/models';

type Icon = ComponentType<{ size?: number | string; strokeWidth?: number | string; class?: string; color?: string }>;

export const kindInfo: Record<MemoryKind, { title: string; icon: Icon; tint: string }> = {
  note: { title: 'Note', icon: StickyNote, tint: 'var(--gray)' },
  document: { title: 'Document', icon: FileText, tint: 'var(--blue)' },
  receipt: { title: 'Receipt', icon: CreditCard, tint: 'var(--green)' },
  announcement: { title: 'Announcement', icon: Megaphone, tint: 'var(--orange)' },
  event: { title: 'Event', icon: Calendar, tint: 'var(--purple)' },
  task: { title: 'Task', icon: ListChecks, tint: 'var(--teal)' },
  object: { title: 'Object', icon: Box, tint: 'var(--indigo)' },
  place: { title: 'Place', icon: MapPin, tint: 'var(--red)' },
  observation: { title: 'Observation', icon: Eye, tint: 'var(--gray)' },
  person: { title: 'Person', icon: User, tint: 'var(--pink)' },
};

export const highlightInfo: Record<HighlightKind, { title: string; icon: Icon; tint: string }> = {
  deadline: { title: 'Deadline', icon: Hourglass, tint: 'var(--orange)' },
  warning: { title: 'Warning', icon: TriangleAlert, tint: 'var(--red)' },
  requirement: { title: 'Requirement', icon: BadgeCheck, tint: 'var(--blue)' },
  date: { title: 'Date', icon: Calendar, tint: 'var(--purple)' },
  info: { title: 'Key point', icon: Sparkle, tint: 'var(--secondary-label)' },
};

export const sourceInfo: Record<CaptureSource, { title: string; icon: Icon }> = {
  camera: { title: 'Camera', icon: Camera },
  photo: { title: 'Photo', icon: Image },
  live: { title: 'Live view', icon: ScanLine },
  voice: { title: 'Voice', icon: Mic },
  text: { title: 'Text', icon: TextCursor },
};

export const originInfo: Record<Origin, { title: string; icon: Icon }> = {
  onDevice: { title: 'Understood on this device', icon: Smartphone },
  remote: { title: 'Enhanced by your AI provider', icon: Sparkles },
  onDeviceFallback: { title: 'Provider unavailable — understood on this device', icon: WifiOff },
};

const dateTimeFormat = new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' });
const relativeFormat = new Intl.RelativeTimeFormat(undefined, { numeric: 'auto' });

export function formatDateTime(date: Date): string {
  return dateTimeFormat.format(date);
}

export function formatRelative(date: Date, now = new Date()): string {
  const seconds = Math.round((date.getTime() - now.getTime()) / 1000);
  const abs = Math.abs(seconds);
  if (abs < 60) return relativeFormat.format(0, 'second');
  if (abs < 3600) return relativeFormat.format(Math.round(seconds / 60), 'minute');
  if (abs < 86_400) return relativeFormat.format(Math.round(seconds / 3600), 'hour');
  if (abs < 7 * 86_400) return relativeFormat.format(Math.round(seconds / 86_400), 'day');
  if (abs < 30 * 86_400) return relativeFormat.format(Math.round(seconds / (7 * 86_400)), 'week');
  if (abs < 365 * 86_400) return relativeFormat.format(Math.round(seconds / (30 * 86_400)), 'month');
  return relativeFormat.format(Math.round(seconds / (365 * 86_400)), 'year');
}

const pad = (n: number) => String(n).padStart(2, '0');

export function toLocalInput(date: Date): string {
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

export function fromLocalInput(value: string): Date | undefined {
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/.exec(value);
  if (!match) return undefined;
  const [, y, m, d, h, min] = match.map(Number);
  return new Date(y, m - 1, d, h, min);
}

export function nextHour(now = new Date()): Date {
  const result = new Date(now);
  result.setMinutes(0, 0, 0);
  result.setHours(result.getHours() + 1);
  return result;
}
