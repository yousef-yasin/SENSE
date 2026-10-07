import { Calendar, type DateInterval, intervalContains } from './calendar';
import type { MemoryKind } from './models';
import { Pattern, STOPWORDS, TextTokenizer, chars, charCount, isNumber } from './text';

export interface MemoryQuery {
  raw: string;
  terms: string[];
  dateInterval?: DateInterval;
  kinds: Set<MemoryKind>;
  place?: string;
}

export interface SearchDocument {
  id: string;
  title: string;
  body: string;
  tags: string[];
  kind: MemoryKind;
  createdAt: Date;
  placeName?: string;
  embedding?: Float32Array;
}

export interface SearchHit {
  id: string;
  score: number;
}

export function embeddingText(doc: Pick<SearchDocument, 'title' | 'tags' | 'body'>): string {
  return [doc.title, doc.title, ...doc.tags, doc.body].join(' ');
}

export interface TextEmbedder {
  readonly identifier: string;
  readonly relevanceThreshold: number;
  embed(text: string): Float32Array | undefined;
}

export const VectorMath = {
  cosine(a: Float32Array, b: Float32Array): number {
    if (a.length !== b.length || a.length === 0) return 0;
    let dot = 0;
    let normA = 0;
    let normB = 0;
    for (let i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA <= 0 || normB <= 0) return 0;
    return dot / (Math.sqrt(normA) * Math.sqrt(normB));
  },

  normalized(vector: Float32Array): Float32Array {
    let sum = 0;
    for (const v of vector) sum += v * v;
    const norm = Math.sqrt(sum);
    if (norm <= 0) return vector;
    return vector.map((v) => v / norm);
  },
};

const FNV_OFFSET = 0xcbf29ce484222325n;
const FNV_PRIME = 0x100000001b3n;
const encoder = new TextEncoder();

export class HashingEmbedder implements TextEmbedder {
  constructor(readonly dimension = 384) {}

  get identifier() {
    return `hashing-${this.dimension}-v1`;
  }

  get relevanceThreshold() {
    return 0.32;
  }

  embed(text: string): Float32Array | undefined {
    const terms = TextTokenizer.terms(text);
    if (terms.length === 0) return undefined;
    const vector = new Float32Array(this.dimension);
    for (const term of terms) {
      this.add(term, 1, vector);
      const padded = chars(`<${term}>`);
      if (padded.length > 4) {
        for (let start = 0; start <= padded.length - 3; start++) {
          this.add(padded.slice(start, start + 3).join(''), 0.35, vector);
        }
      }
    }
    return VectorMath.normalized(vector);
  }

  private add(feature: string, weight: number, vector: Float32Array) {
    const hash = HashingEmbedder.fnv1a(feature);
    const index = Number(hash % BigInt(this.dimension));
    const sign = hash >> 63n === 0n ? 1 : -1;
    vector[index] += sign * weight;
  }

  static fnv1a(text: string): bigint {
    let hash = FNV_OFFSET;
    for (const byte of encoder.encode(text)) {
      hash ^= BigInt(byte);
      hash = BigInt.asUintN(64, hash * FNV_PRIME);
    }
    return hash;
  }
}

export class MemorySearchEngine {
  constructor(readonly embedder?: TextEmbedder) {}

  search(query: MemoryQuery, documents: SearchDocument[], limit = 50): SearchHit[] {
    let candidates = documents;
    let terms = [...query.terms];

    if (query.dateInterval) {
      const interval = query.dateInterval;
      candidates = candidates.filter((d) => intervalContains(interval, d.createdAt));
    }

    if (query.place) {
      const placeTerms = new Set(TextTokenizer.terms(query.place));
      const atPlace = candidates.filter((d) => d.placeName !== undefined && TextTokenizer.terms(d.placeName).some((t) => placeTerms.has(t)));
      if (atPlace.length === 0) terms = [...terms, ...placeTerms];
      else candidates = atPlace;
    }

    if (candidates.length === 0) return [];

    if (terms.length === 0) {
      return [...candidates]
        .sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime())
        .slice(0, limit)
        .map((d) => ({ id: d.id, score: query.kinds.has(d.kind) ? 2 : 1 }))
        .sort((a, b) => b.score - a.score);
    }

    const lexical = this.bm25(terms, candidates);
    const queryVector = this.embedder?.embed(terms.join(' ') + ' ' + query.raw);
    const threshold = this.embedder?.relevanceThreshold ?? 1;

    const hits: SearchHit[] = [];
    candidates.forEach((doc, index) => {
      const lexicalScore = lexical[index];
      let semantic = 0;
      if (queryVector && doc.embedding) semantic = Math.max(0, VectorMath.cosine(queryVector, doc.embedding));
      if (!(lexicalScore > 0 || semantic >= threshold)) return;
      let score = lexicalScore + semantic * 2;
      if (query.kinds.has(doc.kind)) score *= 1.5;
      hits.push({ id: doc.id, score });
    });
    return hits.sort((a, b) => b.score - a.score).slice(0, limit);
  }

  similar(target: SearchDocument, documents: SearchDocument[], limit = 10): SearchHit[] {
    const targetTerms = new Set(fieldTerms(target));
    if (targetTerms.size === 0 && !target.embedding) return [];
    const hits: SearchHit[] = [];
    for (const doc of documents) {
      if (doc.id === target.id) continue;
      const terms = new Set(fieldTerms(doc));
      const union = new Set([...targetTerms, ...terms]).size;
      const intersection = [...targetTerms].filter((t) => terms.has(t)).length;
      const jaccard = union === 0 ? 0 : intersection / union;
      let semantic = 0;
      if (target.embedding && doc.embedding) semantic = Math.max(0, VectorMath.cosine(target.embedding, doc.embedding));
      const score = jaccard * 0.5 + semantic * 0.5;
      const threshold = this.embedder?.relevanceThreshold ?? 0.25;
      if (!(jaccard >= 0.25 || semantic >= Math.max(threshold, 0.5))) continue;
      hits.push({ id: doc.id, score });
    }
    return hits.sort((a, b) => b.score - a.score).slice(0, limit);
  }

  private bm25(terms: string[], documents: SearchDocument[]): number[] {
    const k1 = 1.2;
    const b = 0.75;
    const tokenized = documents.map(fieldTerms);
    const averageLength = Math.max(1, tokenized.reduce((sum, t) => sum + t.length, 0) / tokenized.length);
    const queryTerms = [...new Set(terms)];
    const count = documents.length;

    const documentFrequency = new Map<string, number>();
    for (const term of queryTerms) {
      documentFrequency.set(term, tokenized.filter((tokens) => tokens.some((t) => termMatches(t, term))).length);
    }

    return tokenized.map((tokens) => {
      const length = tokens.length;
      let score = 0;
      for (const term of queryTerms) {
        let frequency = 0;
        for (const token of tokens) {
          if (token === term) frequency += 1;
          else if (termMatches(token, term)) frequency += 0.5;
        }
        if (frequency <= 0) continue;
        const df = documentFrequency.get(term) ?? 0;
        const idf = Math.log(1 + (count - df + 0.5) / (df + 0.5));
        score += (idf * (frequency * (k1 + 1))) / (frequency + k1 * (1 - b + (b * length) / averageLength));
      }
      return score;
    });
  }
}

function fieldTerms(doc: SearchDocument): string[] {
  return TextTokenizer.terms([doc.title, doc.title, ...doc.tags, ...doc.tags, doc.body].join(' '));
}

function termMatches(token: string, term: string): boolean {
  if (token === term) return true;
  if (charCount(term) < 3 || charCount(token) < 3) return false;
  return token.startsWith(term) || term.startsWith(token);
}

const fillerWords = new Set([
  'saw', 'see', 'seen', 'seeing', 'capture', 'captured', 'capturing', 'photographed', 'photo', 'picture',
  'remember', 'recall', 'find', 'search', 'show', 'look', 'looked', 'thing', 'something', 'stuff',
  'already', 'ever', 'anything', 'everything', 'get', 'got', 'also', 'one', 'ones', 'like', 'kind',
  'sense', 'please', 'hey', 'know', 'noticed', 'notice', 'save', 'saved', 'mention', 'mentioned',
]);

const kindWords: Record<string, MemoryKind> = {
  receipt: 'receipt', receipts: 'receipt', invoice: 'receipt', invoices: 'receipt',
  document: 'document', documents: 'document', doc: 'document', docs: 'document',
  announcement: 'announcement', announcements: 'announcement', notice: 'announcement',
  notices: 'announcement', poster: 'announcement', posters: 'announcement', flyer: 'announcement',
  event: 'event', events: 'event',
  task: 'task', tasks: 'task', todo: 'task', todos: 'task',
  note: 'note', notes: 'note',
};

const todayPattern = new Pattern(String.raw`\b(today|this morning|this afternoon|this evening|tonight)\b`);
const yesterdayPattern = new Pattern(String.raw`\b(yesterday|last night)\b`);
const thisWeek = new Pattern(String.raw`\bthis week\b`);
const lastWeek = new Pattern(String.raw`\b(last week|past week|previous week)\b`);
const thisMonth = new Pattern(String.raw`\bthis month\b`);
const lastMonth = new Pattern(String.raw`\b(last month|past month|previous month)\b`);
const recently = new Pattern(String.raw`\b(recently|lately|the other day)\b`);
const daysAgo = new Pattern(String.raw`\b(\d+|two|three|four|five|six|seven|ten) days ago\b`);
const lastNDays = new Pattern(String.raw`\b(?:last|past) (\d+|two|three|four|five|six|seven|ten|fourteen|thirty) days\b`);
const onWeekday = new Pattern(String.raw`\b(?:on|last) (monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b`);
const placePhrase = new Pattern(String.raw`\b(?:at|in|near|from) (?:the |my |a )?([a-z][a-z'\- ]{1,40}?)(?=\s+(?:yesterday|today|tonight|last|this|on|in|at|about|that|which|when|where|recently|ago|\d)\b|\s*[?.!,]|\s*$)`);

const queryNumberWords: Record<string, number> = { two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, ten: 10, fourteen: 14, thirty: 30 };
const weekdays = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'];
const nonPlaces = new Set(['the morning', 'morning', 'afternoon', 'evening', 'night', 'week', 'month', 'year', 'the past', 'it', 'this', 'that', 'there', 'here', 'all']);

export class QueryParser {
  constructor(readonly calendar: Calendar = Calendar.current()) {}

  parse(text: string, now: Date = new Date()): MemoryQuery {
    let working = text.toLowerCase().replace(/’/g, "'");
    let interval: DateInterval | undefined;
    const cal = this.calendar;
    const startOfToday = cal.startOfDay(now);
    const day = (offset: number) => cal.addDays(startOfToday, offset);
    const blank = (range: { start: number; end: number }) => {
      working = working.slice(0, range.start) + ' ' + working.slice(range.end);
    };

    let match;
    if ((match = yesterdayPattern.firstMatch(working))) {
      interval = { start: day(-1), end: startOfToday };
      blank(match.range);
    } else if ((match = todayPattern.firstMatch(working))) {
      interval = { start: startOfToday, end: day(1) };
      blank(match.range);
    } else if ((match = lastWeek.firstMatch(working))) {
      const thisWeekStart = cal.startOfWeek(now);
      interval = { start: cal.addDays(thisWeekStart, -7), end: thisWeekStart };
      blank(match.range);
    } else if ((match = thisWeek.firstMatch(working))) {
      interval = { start: cal.startOfWeek(now), end: day(1) };
      blank(match.range);
    } else if ((match = lastMonth.firstMatch(working))) {
      const thisMonthStart = cal.startOfMonth(now);
      interval = { start: cal.addMonths(thisMonthStart, -1), end: thisMonthStart };
      blank(match.range);
    } else if ((match = thisMonth.firstMatch(working))) {
      interval = { start: cal.startOfMonth(now), end: day(1) };
      blank(match.range);
    } else if ((match = daysAgo.firstMatch(working))) {
      const value = number(match.group(1));
      interval = { start: day(-value), end: day(-value + 1) };
      blank(match.range);
    } else if ((match = lastNDays.firstMatch(working))) {
      interval = { start: day(-number(match.group(1))), end: day(1) };
      blank(match.range);
    } else if ((match = onWeekday.firstMatch(working)) && weekdays.includes(match.group(1) ?? '')) {
      const index = weekdays.indexOf(match.group(1) ?? '');
      const current = cal.weekday(now) - 1;
      let delta = (current - index + 7) % 7;
      if (delta === 0) delta = 7;
      interval = { start: day(-delta), end: day(-delta + 1) };
      blank(match.range);
    } else if ((match = recently.firstMatch(working))) {
      interval = { start: day(-7), end: day(1) };
      blank(match.range);
    }

    let place: string | undefined;
    for (const m of placePhrase.matches(working)) {
      const candidate = (m.group(1) ?? '').trim();
      if (!candidate || nonPlaces.has(candidate)) continue;
      const words = TextTokenizer.words(candidate);
      if (words.some((w) => kindWords[w] !== undefined)) continue;
      if (words.every((w) => STOPWORDS.has(w))) continue;
      place = candidate;
      blank(m.range);
      break;
    }

    const kinds = new Set<MemoryKind>();
    const terms: string[] = [];
    for (const word of TextTokenizer.words(working)) {
      const kind = kindWords[word];
      if (kind) {
        kinds.add(kind);
        continue;
      }
      if (STOPWORDS.has(word) || fillerWords.has(word)) continue;
      if (!(charCount(word) > 1 || chars(word).every(isNumber))) continue;
      terms.push(TextTokenizer.stem(word));
    }

    const query: MemoryQuery = { raw: text, terms, kinds };
    if (interval) query.dateInterval = interval;
    if (place) query.place = place;
    return query;
  }
}

function number(text: string | undefined): number {
  if (text === undefined) return 1;
  if (/^\d+$/.test(text)) return Number(text);
  return queryNumberWords[text] ?? 1;
}
