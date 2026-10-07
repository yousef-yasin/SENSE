import { describe, expect, it } from 'vitest';
import { IntentParser } from '../intentParser';
import { calendar, date, now } from './fixture';

const parser = new IntentParser(calendar, false);
const parse = (text: string) => parser.parse(text, now);
const placeReminder = (title: string, type: 'arriving' | 'leaving', place: string) => ({
  type: 'remind',
  draft: { title, timing: { type, place }, refersToContext: false },
});

describe('IntentParser', () => {
  it('location reminder referring to context', () => {
    expect(parse('Remind me about this when I get to the university.')).toEqual({
      type: 'remind',
      draft: { title: '', timing: { type: 'arriving', place: 'university' }, refersToContext: true },
    });
  });

  it('timed reminder', () => {
    expect(parse('Remind me to call the lab tomorrow at 5')).toEqual({
      type: 'remind',
      draft: { title: 'Call the lab', timing: { type: 'at', date: date(2026, 10, 5, 17, 0) }, dueDate: date(2026, 10, 5, 17, 0), refersToContext: false },
    });
  });

  it('reminder with leading time', () => {
    const intent = parse('remind me at 6pm to water the plants');
    if (intent.type !== 'remind') throw new Error('Expected reminder');
    expect(intent.draft.title).toBe('Water the plants');
    expect(intent.draft.timing).toEqual({ type: 'at', date: date(2026, 10, 4, 18, 0) });
  });

  it('date-only reminder uses morning', () => {
    const intent = parse('Remind me to pay rent on Friday');
    if (intent.type !== 'remind') throw new Error('Expected reminder');
    expect(intent.draft.title).toBe('Pay rent');
    expect(intent.draft.timing).toEqual({ type: 'at', date: date(2026, 10, 9, 9, 0) });
  });

  it('arrival and departure reminders', () => {
    expect(parse("Remind me to buy milk when I'm at the supermarket")).toEqual(placeReminder('Buy milk', 'arriving', 'supermarket'));
    expect(parse('remind me to lock the door when I leave home')).toEqual(placeReminder('Lock the door', 'leaving', 'home'));
    expect(parse('remind me to charge my laptop when I get home')).toEqual(placeReminder('Charge my laptop', 'arriving', 'home'));
    expect(parse('Remind me to return the book at the library')).toEqual(placeReminder('Return the book', 'arriving', 'library'));
  });

  it('curly apostrophes', () => {
    expect(parse('Don’t let me forget to submit the form when I’m at work')).toEqual(placeReminder('Submit the form', 'arriving', 'work'));
  });

  it('recall and analyze', () => {
    expect(parse('Have I seen this before?')).toEqual({ type: 'recallSimilar' });
    expect(parse('did I already capture this')).toEqual({ type: 'recallSimilar' });
    expect(parse("What's important here?")).toEqual({ type: 'analyzeSurroundings' });
    expect(parse('What does this say')).toEqual({ type: 'analyzeSurroundings' });
  });

  it('search questions', () => {
    const first = 'What was that electronics component I saw last week?';
    expect(parse(first)).toEqual({ type: 'search', query: first });
    expect(parse('Did I already see this product?')).toEqual({ type: 'recallSimilar' });
    const second = 'Where was that announcement about registration?';
    expect(parse(second)).toEqual({ type: 'search', query: second });
  });

  it('plain capture', () => {
    expect(parse('The blue door code is 4471')).toEqual({ type: 'capture', text: 'The blue door code is 4471' });
  });
});
