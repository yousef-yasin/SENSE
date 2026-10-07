import { describe, expect, it } from 'vitest';
import { ContentAnalyzer } from '../contentAnalyzer';
import { type CaptureSource, type ImageLabel, makeInput, reminderSuggestions } from '../models';
import { calendar, date, now } from './fixture';

const analyzer = new ContentAnalyzer(calendar, false);
const analyze = (text: string, source: CaptureSource = 'camera', labels: ImageLabel[] = []) => analyzer.analyze(makeInput(source, text, labels, now), now);

describe('ContentAnalyzer', () => {
  it('announcement produces deadline reminder', () => {
    const result = analyze('FALL SEMESTER REGISTRATION\nRegistration closes October 8 at 4 PM.\nStudents must bring their ID card to the registrar office.');
    expect(result.kind).toBe('announcement');
    expect(result.title).toBe('Fall Semester Registration');

    const deadline = result.highlights.find((h) => h.kind === 'deadline');
    expect(deadline?.text).toBe('Registration closes October 8 at 4 PM.');
    expect(deadline?.date).toEqual(date(2026, 10, 8, 16, 0));
    expect(result.highlights.some((h) => h.kind === 'requirement')).toBe(true);

    const reminder = reminderSuggestions(result)[0];
    expect(reminder?.title).toBe('Registration closes');
    expect(reminder?.dueDate).toEqual(date(2026, 10, 8, 16, 0));
    expect(reminder?.timing).toEqual({ type: 'at', date: date(2026, 10, 7, 16, 0) });
  });

  it('receipt extraction', () => {
    const result = analyze('BLUE BEAN CAFE\n123 Main Street\nDate: 10/02/2026 14:32\nLatte 4.50\nCroissant 3.25\nSubtotal 7.75\nTax 0.62\nTOTAL $8.37\nVISA ****1234', 'photo');
    expect(result.kind).toBe('receipt');
    expect(result.title).toBe('Blue Bean Cafe');
    expect(result.summary).toContain('$8.37');
    expect(result.entities.some((e) => e.kind === 'merchant' && e.text === 'Blue Bean Cafe')).toBe(true);
    expect(result.entities.some((e) => e.kind === 'date' && e.date?.getTime() === date(2026, 10, 2, 14, 32).getTime())).toBe(true);
    expect(result.entities.some((e) => e.kind === 'money' && e.value === '8.37 USD')).toBe(true);
    expect(reminderSuggestions(result)).toEqual([]);
  });

  it('document warnings and requirements', () => {
    const result = analyze('Lab Safety Guidelines\nDo not eat or drink in the laboratory.\nSafety goggles are required at all times.\nReports are due November 2.');
    expect(result.highlights.some((h) => h.kind === 'warning' && h.text.startsWith('Do not eat'))).toBe(true);
    expect(result.highlights.some((h) => h.kind === 'requirement' && h.text.includes('goggles'))).toBe(true);
    expect(result.highlights.some((h) => h.kind === 'deadline' && h.date?.getTime() === date(2026, 11, 2).getTime())).toBe(true);
    expect(reminderSuggestions(result)[0]?.timing).toEqual({ type: 'at', date: date(2026, 11, 1, 9, 0) });
  });

  it('event classification', () => {
    const result = analyze('Robotics workshop\nSaturday October 10, 2:00 PM in Hall B');
    expect(result.kind).toBe('event');
    expect(reminderSuggestions(result)[0]?.dueDate).toEqual(date(2026, 10, 10, 14, 0));
  });

  it('object from image labels', () => {
    const result = analyze('', 'camera', [
      { identifier: 'circuit_board', confidence: 0.82 },
      { identifier: 'electronics', confidence: 0.77 },
    ]);
    expect(result.kind).toBe('object');
    expect(result.title).toBe('Circuit Board');
    expect(result.summary).toBe('Circuit Board, Electronics');
    expect(result.tags).toContain('electronics');
  });

  it('contact suggestions', () => {
    const result = analyze('Questions? Email help@campus.edu or call +1 555 010 2030. Details at www.campus.edu/register');
    expect(result.suggestions).toContainEqual({ type: 'email', address: 'help@campus.edu' });
    expect(result.suggestions).toContainEqual({ type: 'call', number: '+1 555 010 2030' });
    expect(result.suggestions).toContainEqual({ type: 'openLink', url: 'https://www.campus.edu/register' });
  });

  it('typed task note', () => {
    expect(analyze('Buy resistors for the lab kit', 'text').kind).toBe('task');
    expect(analyze('The parking lot behind building C is free after 6', 'text').kind).toBe('note');
  });

  it('past dates do not create reminders', () => {
    expect(reminderSuggestions(analyze('Registration closed on September 30.'))).toEqual([]);
  });
});
