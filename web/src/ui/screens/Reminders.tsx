import { Bell, CalendarPlus, Trash2 } from 'lucide-preact';
import type { ReminderRecord } from '../../app/db';
import { addToCalendar, notificationPermission, requestNotificationPermission } from '../../app/reminders';
import { deleteReminder, reminders } from '../../app/store';
import { isStandalone } from '../install';
import { EmptyState, Group, NavBar, ReminderRow } from '../components';
import { confirmDestructive, navigate, showError } from '../state';

export function deliveryNote(): string {
  const permission = notificationPermission.value;
  if (permission === 'granted') return 'SENSE sends a notification when a reminder is due while SENSE is open. Browsers pause web apps that are closed, so add a reminder to your calendar to be alerted at the right time no matter what.';
  if (permission === 'unsupported') {
    return isStandalone()
      ? 'This browser does not support notifications. SENSE shows due reminders when you open it; add a reminder to your calendar to be alerted at the right time.'
      : 'To get notifications on iPhone, add SENSE to your Home Screen (Share → Add to Home Screen). Until then, SENSE shows due reminders when you open it, and you can add them to your calendar.';
  }
  if (permission === 'denied') return 'Notifications are turned off for SENSE. SENSE shows due reminders when you open it, and you can add them to your calendar.';
  return 'Allow notifications so SENSE can alert you while it is open. Add a reminder to your calendar to be alerted even when SENSE is closed.';
}

export function Reminders() {
  const all = [...reminders.value].sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime());
  const upcoming = all.filter((r) => !r.delivered).sort((a, b) => a.fireAt.getTime() - b.fireAt.getTime());
  const past = all.filter((r) => r.delivered);

  const remove = async (reminder: ReminderRecord) => {
    if (!(await confirmDestructive('Delete this reminder?', reminder.title, 'Delete'))) return;
    await deleteReminder(reminder.id).catch(showError);
  };

  const row = (reminder: ReminderRecord) => (
    <div class={`row reminder-line ${reminder.delivered ? 'done' : ''}`}>
      <button class="plain-button grow" onClick={() => reminder.memoryId && navigate(`#/memory/${reminder.memoryId}`)} disabled={!reminder.memoryId}>
        <ReminderRow reminder={reminder} />
      </button>
      <div class="row-actions">
        {!reminder.delivered && (
          <button class="icon-button small" onClick={() => addToCalendar(reminder)} aria-label="Add to Calendar">
            <CalendarPlus size={18} />
          </button>
        )}
        <button class="icon-button small destructive" onClick={() => remove(reminder)} aria-label="Delete reminder">
          <Trash2 size={18} />
        </button>
      </div>
    </div>
  );

  return (
    <div class="screen">
      <NavBar title="Reminders" large back backLabel="SENSE" />
      {all.length === 0 ? (
        <EmptyState icon={<Bell size={48} />} title="No Reminders" message="Reminders you add from captures or by voice appear here." />
      ) : (
        <div class="grouped">
          {upcoming.length > 0 && <Group header="Upcoming">{upcoming.map(row)}</Group>}
          {past.length > 0 && <Group header="Delivered">{past.map(row)}</Group>}
        </div>
      )}
      <div class="grouped">
        <Group footer={deliveryNote()}>
          {notificationPermission.value === 'default' && (
            <button class="row button-row tint" onClick={() => requestNotificationPermission()}>
              Allow Notifications
            </button>
          )}
        </Group>
      </div>
    </div>
  );
}
