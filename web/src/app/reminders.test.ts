import { describe, expect, it } from 'vitest';
import { reminderICS } from './reminders';

describe('reminderICS', () => {
  it('creates a calendar event with an alert at the reminder time', () => {
    const ics = reminderICS({
      id: 'abc',
      title: 'Registration closes',
      body: 'Bring your ID; office opens at 9, closes at 4',
      fireAt: new Date(Date.UTC(2026, 9, 8, 15, 0)),
      createdAt: new Date(),
      delivered: false,
    });
    const lines = ics.split('\r\n');
    expect(lines).toContain('BEGIN:VEVENT');
    expect(lines).toContain('DTSTART:20261008T150000Z');
    expect(lines).toContain('DTEND:20261008T151500Z');
    expect(lines).toContain('SUMMARY:Registration closes');
    expect(lines).toContain('DESCRIPTION:Bring your ID\\; office opens at 9\\, closes at 4');
    expect(lines).toContain('TRIGGER:PT0M');
    expect(lines[lines.length - 2]).toBe('END:VCALENDAR');
  });
});
