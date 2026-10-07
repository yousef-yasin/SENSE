import { effect, signal } from '@preact/signals';
import type { ReminderRecord } from './db';
import { markDelivered, reminders } from './store';

/** Reminders that came due, shown in the app until dismissed. */
export const dueReminders = signal<ReminderRecord[]>([]);
export const notificationPermission = signal<NotificationPermission | 'unsupported'>(currentPermission());

function currentPermission(): NotificationPermission | 'unsupported' {
  return typeof Notification === 'undefined' ? 'unsupported' : Notification.permission;
}

/** Must be called from a user gesture on iOS. Never throws. */
export async function requestNotificationPermission(): Promise<boolean> {
  if (typeof Notification === 'undefined') return false;
  if (Notification.permission === 'default') {
    try {
      await Notification.requestPermission();
    } catch {
      // Older Safari only supports the callback form; the permission is read again below.
    }
  }
  notificationPermission.value = currentPermission();
  return Notification.permission === 'granted';
}

async function notify(reminder: ReminderRecord): Promise<boolean> {
  if (currentPermission() !== 'granted') return false;
  try {
    const registration = await navigator.serviceWorker?.ready;
    if (registration) {
      await registration.showNotification(reminder.title, { body: reminder.body, tag: reminder.id, data: { memoryId: reminder.memoryId } });
      return true;
    }
    new Notification(reminder.title, { body: reminder.body, tag: reminder.id });
    return true;
  } catch {
    return false;
  }
}

const timers = new Map<string, number>();
const maxTimeout = 2_147_000_000;

async function deliver(due: ReminderRecord[]) {
  if (due.length === 0) return;
  await markDelivered(due.map((r) => r.id));
  const visible = document.visibilityState === 'visible';
  for (const reminder of due) {
    const notified = await notify(reminder);
    if (visible || !notified) dueReminders.value = [...dueReminders.value.filter((r) => r.id !== reminder.id), reminder];
  }
}

/** Delivers reminders that are due and schedules the rest while SENSE is open. */
export function startReminderScheduler() {
  const check = () => {
    const now = Date.now();
    void deliver(reminders.value.filter((r) => !r.delivered && r.fireAt.getTime() <= now));
  };

  effect(() => {
    const open = reminders.value.filter((r) => !r.delivered);
    for (const [id, timer] of timers) {
      if (!open.some((r) => r.id === id)) {
        clearTimeout(timer);
        timers.delete(id);
      }
    }
    for (const reminder of open) {
      if (timers.has(reminder.id)) continue;
      const delay = reminder.fireAt.getTime() - Date.now();
      if (delay <= 0 || delay > maxTimeout) continue;
      timers.set(reminder.id, window.setTimeout(() => {
        timers.delete(reminder.id);
        check();
      }, delay));
    }
  });

  check();
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') {
      notificationPermission.value = currentPermission();
      check();
    }
  });
  window.setInterval(check, 30_000);
}

export function dismissDue(id: string) {
  dueReminders.value = dueReminders.value.filter((r) => r.id !== id);
}

function icsDate(date: Date): string {
  return date.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
}

function icsText(text: string): string {
  return text.replace(/\\/g, '\\\\').replace(/;/g, '\\;').replace(/,/g, '\\,').replace(/\r?\n/g, '\\n');
}

export function reminderICS(reminder: ReminderRecord): string {
  const end = new Date(reminder.fireAt.getTime() + 15 * 60_000);
  return [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//SENSE//Reminders//EN',
    'CALSCALE:GREGORIAN',
    'BEGIN:VEVENT',
    `UID:${reminder.id}@sense`,
    `DTSTAMP:${icsDate(new Date())}`,
    `DTSTART:${icsDate(reminder.fireAt)}`,
    `DTEND:${icsDate(end)}`,
    `SUMMARY:${icsText(reminder.title)}`,
    ...(reminder.body ? [`DESCRIPTION:${icsText(reminder.body)}`] : []),
    'BEGIN:VALARM',
    'ACTION:DISPLAY',
    `DESCRIPTION:${icsText(reminder.title)}`,
    'TRIGGER:PT0M',
    'END:VALARM',
    'END:VEVENT',
    'END:VCALENDAR',
    '',
  ].join('\r\n');
}

/** Opens the reminder as a calendar event so the system calendar can alert even when SENSE is closed. */
export function addToCalendar(reminder: ReminderRecord) {
  const blob = new Blob([reminderICS(reminder)], { type: 'text/calendar;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = `${reminder.title.replace(/[^\p{L}\p{N} _-]/gu, '').trim() || 'reminder'}.ics`;
  document.body.appendChild(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 60_000);
}
