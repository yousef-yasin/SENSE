export interface Span {
  start: number;
  end: number;
}

export function spanOverlaps(a: Span, b: Span): boolean {
  return a.start < b.end && b.start < a.end;
}

export function spanUnion(a: Span, b: Span): Span {
  return { start: Math.min(a.start, b.start), end: Math.max(a.end, b.end) };
}

export class PatternMatch {
  constructor(private readonly result: RegExpExecArray) {}

  get range(): Span {
    return { start: this.result.index, end: this.result.index + this.result[0].length };
  }

  get text(): string {
    return this.result[0];
  }

  group(index: number): string | undefined {
    return this.result[index] ?? undefined;
  }
}

/** Case-insensitive regular expression with whole-input anchors. */
export class Pattern {
  private readonly global: RegExp;
  private readonly single: RegExp;

  constructor(source: string) {
    this.global = new RegExp(source, 'gi');
    this.single = new RegExp(source, 'i');
  }

  matches(text: string): PatternMatch[] {
    return Array.from(text.matchAll(this.global), (m) => new PatternMatch(m as RegExpExecArray));
  }

  firstMatch(text: string): PatternMatch | undefined {
    const result = this.single.exec(text);
    return result ? new PatternMatch(result) : undefined;
  }

  contains(text: string): boolean {
    return this.single.test(text);
  }
}

const letterRe = /\p{L}/u;
const upperRe = /\p{Lu}/u;
const numberRe = /\p{N}/u;
const punctuationRe = /\p{P}/u;
const whitespaceRe = /\s/u;

export const isLetter = (c: string) => letterRe.test(c);
export const isUppercase = (c: string) => upperRe.test(c);
export const isNumber = (c: string) => numberRe.test(c);
export const isPunctuation = (c: string) => punctuationRe.test(c);
export const isWhitespace = (c: string) => whitespaceRe.test(c);

export const chars = (s: string) => Array.from(s);
export const charCount = (s: string) => chars(s).length;
export const countWhere = (s: string, predicate: (c: string) => boolean) => chars(s).filter(predicate).length;
export const lettersOf = (s: string) => chars(s).filter(isLetter);

export function trimWhere(s: string, predicate: (c: string) => boolean): string {
  const list = chars(s);
  let start = 0;
  let end = list.length;
  while (start < end && predicate(list[start])) start++;
  while (end > start && predicate(list[end - 1])) end--;
  return list.slice(start, end).join('');
}

export const trimmed = (s: string) => s.trim();
export const trimPunctuation = (s: string) => trimWhere(s, isPunctuation);
export const trimPunctuationAndSpace = (s: string) => trimWhere(s, (c) => isPunctuation(c) || isWhitespace(c));

export function truncated(s: string, limit: number): string {
  const list = chars(s);
  if (list.length <= limit) return s;
  const prefix = list.slice(0, limit);
  const space = prefix.lastIndexOf(' ');
  if (space !== -1 && space > Math.floor(limit / 2)) {
    return trimPunctuationAndSpace(prefix.slice(0, space).join('')) + '…';
  }
  return prefix.join('') + '…';
}

export function capitalizedFirst(s: string): string {
  const list = chars(s);
  if (list.length === 0) return s;
  return list[0].toUpperCase() + list.slice(1).join('');
}

/** Upper-cases the first letter of every word and lower-cases the rest. */
export function capitalized(s: string): string {
  let result = '';
  let atWordStart = true;
  for (const c of chars(s)) {
    if (isLetter(c) || isNumber(c)) {
      result += atWordStart ? c.toUpperCase() : c.toLowerCase();
      atWordStart = false;
    } else {
      result += c;
      atWordStart = c !== "'" && c !== '’';
    }
  }
  return result;
}

export function allLettersUppercase(s: string): boolean {
  return lettersOf(s).every(isUppercase);
}

/** Parses a string of ASCII digits; anything else yields null. */
export function toInt(s: string | undefined): number | null {
  if (s === undefined || !/^\d+$/.test(s)) return null;
  return Number(s);
}

export const TextTokenizer = {
  words(text: string): string[] {
    const folded = text.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase();
    return folded.match(/[\p{L}\p{N}]+/gu) ?? [];
  },

  terms(text: string, extraStopwords: Set<string> = new Set()): string[] {
    return TextTokenizer.words(text)
      .filter((word) => {
        if (STOPWORDS.has(word) || extraStopwords.has(word)) return false;
        return charCount(word) > 1 || chars(word).every(isNumber);
      })
      .map(TextTokenizer.stem);
  },

  stem(word: string): string {
    if (charCount(word) <= 3 || !chars(word).every(isLetter)) return word;
    let w = word;
    const n = () => charCount(w);

    if (w.endsWith('ies') && n() > 4) {
      w = w.slice(0, -3) + 'y';
    } else if (w.endsWith('sses')) {
      w = w.slice(0, -2);
    } else if (w.endsWith('es') && n() - 2 >= 3 && ['s', 'x', 'z', 'ch', 'sh'].some((s) => w.slice(0, -2).endsWith(s))) {
      w = w.slice(0, -2);
    } else if (w.endsWith('s') && !w.endsWith('ss') && !w.endsWith('us') && !w.endsWith('is')) {
      w = w.slice(0, -1);
    }

    if (w.endsWith('ing') && n() - 3 >= 3) {
      w = w.slice(0, -3);
    } else if (w.endsWith('ed') && n() - 2 >= 3) {
      w = w.slice(0, -2);
    }

    if (w.endsWith('e') && n() > 3) {
      w = w.slice(0, -1);
    }
    return w;
  },
};

export const STOPWORDS = new Set([
  'a', 'about', 'above', 'after', 'again', 'against', 'all', 'am', 'an', 'and', 'any', 'are', 'as', 'at',
  'be', 'because', 'been', 'before', 'being', 'below', 'between', 'both', 'but', 'by', 'can', 'could',
  'did', 'do', 'does', 'doing', 'down', 'during', 'each', 'few', 'for', 'from', 'further', 'had', 'has',
  'have', 'having', 'he', 'her', 'here', 'hers', 'herself', 'him', 'himself', 'his', 'how', 'i', 'if',
  'in', 'into', 'is', 'it', 'its', 'itself', 'just', 'me', 'more', 'most', 'my', 'myself', 'no', 'nor',
  'not', 'now', 'of', 'off', 'on', 'once', 'only', 'or', 'other', 'our', 'ours', 'ourselves', 'out',
  'over', 'own', 'same', 'she', 'should', 'so', 'some', 'such', 'than', 'that', 'the', 'their',
  'theirs', 'them', 'themselves', 'then', 'there', 'these', 'they', 'this', 'those', 'through', 'to',
  'too', 'under', 'until', 'up', 'very', 'was', 'we', 'were', 'what', 'when', 'where', 'which', 'while',
  'who', 'whom', 'why', 'will', 'with', 'would', 'you', 'your', 'yours', 'yourself', 'yourselves',
  'im', 'ive', 'id', 'ill', 'dont', 'didnt', 's', 't',
]);
