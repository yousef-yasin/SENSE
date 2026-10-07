import { Calendar } from './calendar';
import { Pattern, type Span, TextTokenizer, spanOverlaps, spanUnion, toInt } from './text';

export interface DetectedDate {
  date: Date;
  includesTime: boolean;
  text: string;
  range: Span;
}

export interface ExtractOptions {
  standaloneTimes?: boolean;
}

type Piece =
  | { kind: 'day'; date: Date; defaultTime?: [number, number] }
  | { kind: 'time'; hour: number; minute: number }
  | { kind: 'instant'; date: Date };

interface Token {
  range: Span;
  piece: Piece;
  isWeekday: boolean;
}

const month = String.raw`(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\b\.?`;
const monthDay = new Pattern(String.raw`\b${month}\s+(\d{1,2})(?:st|nd|rd|th)?\b(?:,?\s+(\d{4})\b)?`);
const dayMonth = new Pattern(String.raw`\b(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?${month}(?:,?\s+(\d{4})\b)?`);
const isoDate = new Pattern(String.raw`\b(\d{4})[-/](\d{1,2})[-/](\d{1,2})\b`);
const slashDate = new Pattern(String.raw`(?<![\d/])(\d{1,2})/(\d{1,2})(?:/(\d{4}|\d{2}))?(?![\d/])`);
const separatedDate = new Pattern(String.raw`(?<![\d.\-])(\d{1,2})[.\-](\d{1,2})[.\-](\d{4}|\d{2})(?![\d.\-])`);
const meridiemTime = new Pattern(String.raw`\b(\d{1,2})(?:[:.]([0-5]\d))?\s*([ap])\.?\s?m\b`);
const clockTime = new Pattern(String.raw`\b([01]?\d|2[0-3]):([0-5]\d)\b`);
const atHour = new Pattern(String.raw`\bat\s+(\d{1,2})(?::([0-5]\d))?\b(?!\s*[ap]\.?\s?m\b)(?![:/%.]\d)`);
const namedTime = new Pattern(String.raw`\b(noon|midday|midnight|morning|afternoon|evening|night)\b`);
const relativeDay = new Pattern(String.raw`\b(day after tomorrow|today|tonight|tomorrow|tmrw)\b`);
const weekday = new Pattern(String.raw`\b(?:(next|this|coming)\s+)?(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b`);
const inDuration = new Pattern(String.raw`\bin\s+(\d+|an?|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|fifteen|twenty|thirty|forty-five|half an?)\s+(minute|min|hour|hr|day|week|month)s?\b`);
const nextPeriod = new Pattern(String.raw`\bnext\s+(week|month)\b`);

const numberWords: Record<string, number> = {
  a: 1, an: 1, one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7,
  eight: 8, nine: 9, ten: 10, eleven: 11, twelve: 12, fifteen: 15, twenty: 20,
  thirty: 30, 'forty-five': 45, 'half a': 0.5, 'half an': 0.5,
};

const weekdayNumbers: Record<string, number> = {
  sunday: 1, monday: 2, tuesday: 3, wednesday: 4, thursday: 5, friday: 6, saturday: 7,
};

const connectorWords = new Set([
  'at', 'on', 'by', 'from', 'before', 'until', 'till', 'around', 'about', 'the', 'of', 'starting',
  'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday',
]);

const monthFirstRegions = new Set(['US', 'PH', 'FM', 'MH', 'PW', 'BZ', 'AS', 'GU', 'PR', 'UM', 'VI']);

export class DateExtractor {
  readonly prefersDayFirst: boolean;

  constructor(
    readonly calendar: Calendar = Calendar.current(),
    prefersDayFirst?: boolean,
  ) {
    this.prefersDayFirst = prefersDayFirst ?? DateExtractor.localePrefersDayFirst(calendar.locale);
  }

  static localePrefersDayFirst(locale: string | undefined): boolean {
    if (!locale) return false;
    try {
      const region = new Intl.Locale(locale).maximize().region;
      if (!region) return false;
      return !monthFirstRegions.has(region);
    } catch {
      return false;
    }
  }

  extract(text: string, now: Date, options: ExtractOptions = {}): DetectedDate[] {
    const tokens = this.resolveOverlaps(this.tokenize(text, now));
    const filtered = this.dropWeekdaysAdjacentToDates(tokens);

    const results: DetectedDate[] = [];
    const usedTimes = new Set<number>();

    filtered.forEach((token, index) => {
      const piece = token.piece;
      if (piece.kind === 'day') {
        let range = token.range;
        let time = piece.defaultTime;
        const pairIndex = this.pairedTime(index, filtered, usedTimes, text);
        if (pairIndex !== null) {
          const paired = filtered[pairIndex].piece;
          if (paired.kind === 'time') {
            usedTimes.add(pairIndex);
            time = [paired.hour, paired.minute];
            range = spanUnion(range, filtered[pairIndex].range);
          }
        }
        const resolved = time ? this.calendar.settingTime(piece.date, time[0], time[1]) : piece.date;
        results.push({ date: resolved, includesTime: time !== undefined, text: text.slice(range.start, range.end), range });
      } else if (piece.kind === 'instant') {
        results.push({ date: piece.date, includesTime: true, text: text.slice(token.range.start, token.range.end), range: token.range });
      }
    });

    if (options.standaloneTimes) {
      filtered.forEach((token, index) => {
        if (usedTimes.has(index) || token.piece.kind !== 'time') return;
        const today = this.calendar.settingTime(now, token.piece.hour, token.piece.minute);
        const date = today.getTime() > now.getTime() ? today : this.calendar.addDays(today, 1);
        results.push({ date, includesTime: true, text: text.slice(token.range.start, token.range.end), range: token.range });
      });
    }

    return results.sort((a, b) => a.range.start - b.range.start);
  }

  private tokenize(text: string, now: Date): Token[] {
    const tokens: Token[] = [];
    const cal = this.calendar;
    const today = cal.startOfDay(now);
    const day = (range: Span, date: Date, defaultTime?: [number, number], isWeekday = false) =>
      tokens.push({ range, piece: defaultTime ? { kind: 'day', date, defaultTime } : { kind: 'day', date }, isWeekday });
    const time = (range: Span, hour: number, minute: number) => tokens.push({ range, piece: { kind: 'time', hour, minute }, isWeekday: false });

    for (const match of monthDay.matches(text)) {
      const m = monthNumber(match.group(1));
      const d = toInt(match.group(2));
      const date = m !== null && d !== null ? this.resolveDay(toInt(match.group(3)), m, d, now) : null;
      if (date) day(match.range, date);
    }
    for (const match of dayMonth.matches(text)) {
      const m = monthNumber(match.group(2));
      const d = toInt(match.group(1));
      const date = m !== null && d !== null ? this.resolveDay(toInt(match.group(3)), m, d, now) : null;
      if (date) day(match.range, date);
    }
    for (const match of isoDate.matches(text)) {
      const y = toInt(match.group(1));
      const m = toInt(match.group(2));
      const d = toInt(match.group(3));
      const date = y !== null && m !== null && d !== null ? this.resolveDay(y, m, d, now) : null;
      if (date) day(match.range, date);
    }
    for (const pattern of [slashDate, separatedDate]) {
      for (const match of pattern.matches(text)) {
        const first = toInt(match.group(1));
        const second = toInt(match.group(2));
        if (first === null || second === null) continue;
        const [m, d] = this.numericOrder(first, second);
        const date = this.resolveDay(toInt(match.group(3)), m, d, now);
        if (date) day(match.range, date);
      }
    }
    for (const match of relativeDay.matches(text)) {
      const word = (match.group(1) ?? '').toLowerCase();
      let offset = 0;
      let defaultTime: [number, number] | undefined;
      if (word === 'day after tomorrow') offset = 2;
      else if (word === 'tomorrow' || word === 'tmrw') offset = 1;
      else if (word === 'tonight') defaultTime = [20, 0];
      day(match.range, cal.addDays(today, offset), defaultTime);
    }
    for (const match of weekday.matches(text)) {
      const target = weekdayNumbers[(match.group(2) ?? '').toLowerCase()];
      if (!target) continue;
      const modifier = match.group(1)?.toLowerCase();
      const current = cal.weekday(today);
      let delta = (target - current + 7) % 7;
      if (modifier === 'next' && delta === 0) delta = 7;
      day(match.range, cal.addDays(today, delta), undefined, true);
    }
    for (const match of nextPeriod.matches(text)) {
      const isMonth = (match.group(1) ?? '').toLowerCase() === 'month';
      day(match.range, isMonth ? cal.addMonths(today, 1) : cal.addDays(today, 7));
    }
    for (const match of inDuration.matches(text)) {
      const amountText = (match.group(1) ?? '').toLowerCase();
      const amount = toInt(amountText) ?? numberWords[amountText];
      if (amount === undefined) continue;
      const unit = (match.group(2) ?? '').toLowerCase();
      if (unit === 'minute' || unit === 'min') {
        tokens.push({ range: match.range, piece: { kind: 'instant', date: new Date(now.getTime() + amount * 60_000) }, isWeekday: false });
      } else if (unit === 'hour' || unit === 'hr') {
        tokens.push({ range: match.range, piece: { kind: 'instant', date: new Date(now.getTime() + amount * 3600_000) }, isWeekday: false });
      } else if (unit === 'day') {
        day(match.range, cal.addDays(today, Math.round(amount)));
      } else if (unit === 'week') {
        day(match.range, cal.addDays(today, Math.round(amount * 7)));
      } else {
        day(match.range, cal.addMonths(today, Math.round(amount)));
      }
    }
    for (const match of meridiemTime.matches(text)) {
      const hour = toInt(match.group(1));
      if (hour === null || hour < 1 || hour > 12) continue;
      const minute = toInt(match.group(2)) ?? 0;
      const isPM = (match.group(3) ?? '').toLowerCase() === 'p';
      time(match.range, (hour % 12) + (isPM ? 12 : 0), minute);
    }
    for (const match of clockTime.matches(text)) {
      const hour = toInt(match.group(1));
      const minute = toInt(match.group(2));
      if (hour === null || minute === null) continue;
      time(match.range, hour, minute);
    }
    for (const match of atHour.matches(text)) {
      const hour = toInt(match.group(1));
      if (hour === null || hour > 23) continue;
      const minute = toInt(match.group(2)) ?? 0;
      time(match.range, hour >= 1 && hour <= 6 ? hour + 12 : hour, minute);
    }
    for (const match of namedTime.matches(text)) {
      const hours: Record<string, number> = { noon: 12, midday: 12, midnight: 0, morning: 9, afternoon: 15, evening: 18 };
      time(match.range, hours[(match.group(1) ?? '').toLowerCase()] ?? 20, 0);
    }
    return tokens;
  }

  private resolveOverlaps(tokens: Token[]): Token[] {
    const ordered = [...tokens].sort((a, b) => {
      const la = a.range.end - a.range.start;
      const lb = b.range.end - b.range.start;
      return la !== lb ? lb - la : a.range.start - b.range.start;
    });
    const accepted: Token[] = [];
    for (const token of ordered) {
      if (!accepted.some((t) => spanOverlaps(t.range, token.range))) accepted.push(token);
    }
    return accepted.sort((a, b) => a.range.start - b.range.start);
  }

  private dropWeekdaysAdjacentToDates(tokens: Token[]): Token[] {
    return tokens.filter((token, index) => {
      if (!token.isWeekday || index + 1 >= tokens.length) return true;
      const next = tokens[index + 1];
      if (next.piece.kind !== 'day' || next.isWeekday) return true;
      return next.range.start - token.range.end > 4;
    });
  }

  private pairedTime(index: number, tokens: Token[], used: Set<number>, source: string): number | null {
    const dayRange = tokens[index].range;
    let best: { index: number; distance: number } | null = null;
    tokens.forEach((token, candidate) => {
      if (token.piece.kind !== 'time' || used.has(candidate)) return;
      let gap: Span;
      if (token.range.start >= dayRange.end) {
        gap = { start: dayRange.end, end: token.range.start };
      } else if (token.range.end <= dayRange.start) {
        gap = { start: token.range.end, end: dayRange.start };
      } else {
        return;
      }
      const length = gap.end - gap.start;
      if (length > 20) return;
      const gapText = source.slice(gap.start, gap.end);
      if (gapText.includes('\n')) return;
      if (TextTokenizer.words(gapText).some((w) => !connectorWords.has(w))) return;
      const distance = length + (token.range.start < dayRange.start ? 1 : 0);
      if (best === null || distance < best.distance) best = { index: candidate, distance };
    });
    return best === null ? null : (best as { index: number }).index;
  }

  private numericOrder(first: number, second: number): [number, number] {
    if (first > 12) return [second, first];
    if (second > 12) return [first, second];
    return this.prefersDayFirst ? [second, first] : [first, second];
  }

  private resolveDay(year: number | null, month: number, day: number, now: Date): Date | null {
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    const cal = this.calendar;
    if (year !== null) return cal.make(year < 100 ? 2000 + year : year, month, day);
    const today = cal.startOfDay(now).getTime();
    const currentYear = cal.year(now);
    let best: Date | null = null;
    for (const y of [currentYear - 1, currentYear, currentYear + 1]) {
      const candidate = cal.make(y, month, day);
      if (!candidate) continue;
      if (best === null || Math.abs(candidate.getTime() - today) < Math.abs(best.getTime() - today)) best = candidate;
    }
    return best;
  }
}

function monthNumber(text: string | undefined): number | null {
  if (!text) return null;
  const months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
  const index = months.indexOf(text.toLowerCase().slice(0, 3));
  return index === -1 ? null : index + 1;
}
