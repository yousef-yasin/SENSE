import { describe, expect, it } from 'vitest';
import type { MemoryKind } from '../models';
import { HashingEmbedder, MemorySearchEngine, QueryParser, type SearchDocument, VectorMath, embeddingText } from '../search';
import { TextTokenizer } from '../text';
import { calendar, date, now } from './fixture';

const queryParser = new QueryParser(calendar);
const engine = new MemorySearchEngine(new HashingEmbedder());
let counter = 0;

function document(title: string, body: string, options: { kind?: MemoryKind; daysAgo?: number; place?: string; tags?: string[] } = {}): SearchDocument {
  const doc: SearchDocument = {
    id: `doc-${++counter}`,
    title,
    body,
    tags: options.tags ?? [],
    kind: options.kind ?? 'note',
    createdAt: new Date(now.getTime() - (options.daysAgo ?? 0) * 86_400_000),
    placeName: options.place,
  };
  doc.embedding = new HashingEmbedder().embed(embeddingText(doc));
  return doc;
}

const parse = (text: string) => queryParser.parse(text, now);

describe('Search', () => {
  it('query parser extracts filters', () => {
    const query = parse('What did I capture at the university yesterday?');
    expect(query.place).toBe('university');
    expect(query.dateInterval).toEqual({ start: date(2026, 10, 3), end: date(2026, 10, 4) });
    expect(query.terms).toEqual([]);
  });

  it('query parser last week and terms', () => {
    const query = parse('What was that electronics component I saw last week?');
    expect(query.dateInterval).toEqual({ start: date(2026, 9, 27), end: date(2026, 10, 4) });
    expect(query.terms).toEqual(['electronic', 'component']);
  });

  it('query parser kinds', () => {
    const query = parse('Where was that announcement about registration?');
    expect([...query.kinds]).toEqual(['announcement']);
    expect(query.terms).toEqual(['registration']);
    expect(query.place).toBeUndefined();
  });

  it('keyword search ranks relevant memory first', () => {
    const registration = document('Fall Registration', 'Registration closes October 8 at 4 PM.', { kind: 'announcement', daysAgo: 2 });
    const receipt = document('Blue Bean Cafe', 'Latte 4.50 Total 8.37', { kind: 'receipt', daysAgo: 1 });
    const resistor = document('Resistor Kit', 'Electronic components: resistors, capacitors', { kind: 'object', daysAgo: 5, tags: ['electronics'] });

    const hits = engine.search(parse('Where was that announcement about registration?'), [receipt, resistor, registration]);
    expect(hits[0]?.id).toBe(registration.id);
    expect(hits.some((h) => h.id === receipt.id)).toBe(false);

    const componentHits = engine.search(parse('electronics component'), [receipt, resistor, registration]);
    expect(componentHits[0]?.id).toBe(resistor.id);
  });

  it('filter-only query returns matching place and day', () => {
    const atUniversity = document('Lab schedule', 'Lab moved to room 204', { daysAgo: 1, place: 'University of Jordan' });
    const atHome = document('Groceries', 'Eggs and bread', { daysAgo: 1, place: 'Home' });
    const olderAtUniversity = document('Parking', 'Lot C closed', { daysAgo: 4, place: 'University of Jordan' });
    const hits = engine.search(parse('What did I capture at the university yesterday?'), [atUniversity, atHome, olderAtUniversity]);
    expect(hits.map((h) => h.id)).toEqual([atUniversity.id]);
  });

  it('unknown place falls back to keywords', () => {
    const memory = document('Library hours', 'The library opens at 8');
    expect(engine.search(parse('what did I see at the library'), [memory])[0]?.id).toBe(memory.id);
  });

  it('no matches returns empty', () => {
    const memory = document('Blue Bean Cafe', 'Latte', { kind: 'receipt' });
    expect(engine.search(parse('quantum physics lecture'), [memory])).toEqual([]);
  });

  it('similar finds related capture', () => {
    const first = document('Arduino Uno board', 'Arduino Uno microcontroller board with USB', { kind: 'object', daysAgo: 6, tags: ['electronics'] });
    const unrelated = document('Groceries', 'Eggs bread milk', { daysAgo: 3 });
    const again = document('Arduino Uno', 'Arduino Uno board', { kind: 'object', tags: ['electronics'] });
    expect(engine.similar(again, [first, unrelated, again]).map((h) => h.id)).toEqual([first.id]);
  });

  it('embedding is normalized', () => {
    const vector = new HashingEmbedder().embed('registration deadline')!;
    expect(VectorMath.cosine(vector, vector)).toBeCloseTo(1, 4);
  });

  it('stemming', () => {
    expect(TextTokenizer.stem('components')).toBe(TextTokenizer.stem('component'));
    expect(TextTokenizer.stem('captured')).toBe(TextTokenizer.stem('capture'));
    expect(TextTokenizer.stem('batteries')).toBe('battery');
    expect(TextTokenizer.stem('boxes')).toBe('box');
  });
});
