import { Calendar } from './calendar';
import { type DetectedDate, DateExtractor } from './dateExtractor';
import { EntityExtractor, type MoneyAmount, moneyValue } from './entityExtractor';
import {
  type CaptureInput,
  type ExtractedEntity,
  type Highlight,
  type HighlightKind,
  type ImageLabel,
  type MemoryKind,
  type ReminderDraft,
  ReminderPolicy,
  type SuggestedAction,
  type Understanding,
  entity,
  labelDisplayName,
} from './models';
import {
  Pattern,
  STOPWORDS,
  TextTokenizer,
  allLettersUppercase,
  capitalized,
  capitalizedFirst,
  charCount,
  chars,
  countWhere,
  isLetter,
  isNumber,
  isUppercase,
  lettersOf,
  trimPunctuationAndSpace,
  trimWhere,
  isPunctuation,
  isWhitespace,
  truncated,
} from './text';

const receiptCues = new Pattern(String.raw`\b(total|subtotal|sub-total|tax|vat|receipt|invoice|cash|change due|visa|mastercard|amex|debit|credit card|qty|amount due|balance due|thank you for shopping|order #|item)\b`);
const announcementCues = new Pattern(String.raw`\b(registration|register|announcement|notice|deadline|closes?|opens?|apply|application|submit|submission|attention|students?|sign[- ]?up|rsvp|venue|enrol(?:l)?ment|enrol(?:l)?|admission|open day|important)\b`);
const eventCues = new Pattern(String.raw`\b(workshop|seminar|meeting|concert|party|conference|lecture|webinar|appointment|match|festival|exhibition|ceremony|class|session|talk|meetup|show)\b`);
const taskCues = new Pattern(String.raw`^(?:to ?do:?\s*)?(buy|call|email|pick up|finish|send|pay|book|renew|return|fix|clean|schedule|cancel|order|bring|submit|check|remember to|don't forget to|need to|i need to|i have to)\b`);

const deadlineCue = new Pattern(String.raw`\b(deadline|due|closes?|closing|expires?|expiry|expiration|last day|no later than|until|till|ends?|before|by|submit|valid through|valid until|best before|use by|cutoff|cut-off)\b`);
const warningCue = new Pattern(String.raw`\b(warning|caution|danger|hazard|do not|don't|never|prohibited|not allowed|not permitted|forbidden|must not|attention|important|urgent|alert|penalty|fine of|late fee|non-refundable|no refunds?)\b`);
const requirementCue = new Pattern(String.raw`\b(must|required|requires?|mandatory|need to|needs to|have to|bring|please ensure|make sure|eligible|eligibility|requirements?|necessary)\b`);

const receiptNoise = new Pattern(String.raw`\b(receipt|invoice|tax|vat|tel|phone|www|http|date|time|order|table|cashier|server|welcome)\b`);
const totalLine = new Pattern(String.raw`^(?!.*\bsub[- ]?total\b).*\b(total|amount due|balance due|grand total|to pay)\b`);
const sentenceBreak = new Pattern(String.raw`(?<=[.!?])\s+(?=[A-Z"“])`);

const trailingConnectors = new Set(['at', 'on', 'by', 'before', 'until', 'till', 'from', 'the', 'of', 'is', 'are', 'in', 'and', 'to']);

const uniqueLower = (texts: string[]) => new Set(texts.map((t) => t.toLowerCase())).size;

export class ContentAnalyzer {
  readonly dateExtractor: DateExtractor;
  readonly entityExtractor = new EntityExtractor();

  constructor(
    readonly calendar: Calendar = Calendar.current(),
    prefersDayFirst?: boolean,
  ) {
    this.dateExtractor = new DateExtractor(calendar, prefersDayFirst);
  }

  analyze(input: CaptureInput, now: Date = new Date()): Understanding {
    const text = input.text.trim();
    const lines = text.split(/\r\n|\r|\n/).map((l) => l.trim()).filter((l) => l.length > 0);
    const statements = ContentAnalyzer.statements(lines);
    const dates = this.dateExtractor.extract(text, now);
    const dateRanges = dates.map((d) => d.range);
    const money = this.entityExtractor.money(text, dateRanges);
    const emails = this.entityExtractor.emails(text);
    const links = this.entityExtractor.links(text);
    const phones = this.entityExtractor.phoneNumbers(text, [...dateRanges, ...money.map((m) => m.range)]);
    const labels = [...input.imageLabels].sort((a, b) => b.confidence - a.confidence);

    const kind = this.classify(input, text, lines, dates, money, labels, now);
    const highlights = this.highlights(statements, now);
    const merchant = kind === 'receipt' ? ContentAnalyzer.merchant(lines) : undefined;
    const total = kind === 'receipt' ? ContentAnalyzer.total(lines, money, this.entityExtractor) : undefined;
    const title = this.title(kind, lines, statements, merchant, labels);

    const entities: ExtractedEntity[] = [];
    if (merchant) entities.push(entity('merchant', merchant));
    entities.push(...dates.map((d) => entity('date', d.text, undefined, d.date)));
    entities.push(...money.map((m) => entity('money', m.text, [m.value, m.currency].filter(Boolean).join(' '))));
    entities.push(...emails.map((e) => entity('email', e)));
    entities.push(...phones.map((p) => entity('phone', p, chars(p).filter((c) => isNumber(c) || c === '+').join(''))));
    entities.push(...links.map((l) => entity('link', l)));
    entities.push(...labels.slice(0, 5).map((l) => entity('label', labelDisplayName(l.identifier), l.identifier)));

    const summary = this.summarize(kind, statements, highlights, merchant, total, dates, labels);

    const suggestions: SuggestedAction[] = this.reminderSuggestions(highlights, title, kind, now).map((draft) => ({ type: 'reminder', draft }));
    suggestions.push(...links.slice(0, 2).map((url): SuggestedAction => ({ type: 'openLink', url })));
    suggestions.push(...phones.slice(0, 1).map((number): SuggestedAction => ({ type: 'call', number })));
    suggestions.push(...emails.slice(0, 1).map((address): SuggestedAction => ({ type: 'email', address })));

    return { kind, title, summary, highlights, entities, suggestions, tags: this.tags(text, labels), origin: 'onDevice' };
  }

  private classify(input: CaptureInput, text: string, lines: string[], dates: DetectedDate[], money: MoneyAmount[], labels: ImageLabel[], now: Date): MemoryKind {
    const letters = countWhere(text, isLetter);
    if (letters < 20 && labels.length > 0) return 'object';
    if (text.length === 0) return input.source === 'text' || input.source === 'voice' ? 'note' : 'observation';

    const receiptScore = receiptCues.matches(text).length + (money.length >= 2 ? 2 : 0);
    if (receiptScore >= 3 && money.length > 0) return 'receipt';

    if ((input.source === 'text' || input.source === 'voice') && taskCues.contains(text.toLowerCase())) return 'task';

    const startOfToday = this.calendar.startOfDay(now).getTime();
    const hasUpcomingDate = dates.some((d) => d.date.getTime() >= startOfToday);
    const announcementScore = uniqueLower(announcementCues.matches(text).map((m) => m.text));
    const eventScore = uniqueLower(eventCues.matches(text).map((m) => m.text));

    if (hasUpcomingDate && eventScore > 0 && eventScore >= announcementScore) return 'event';
    if (announcementScore + (hasUpcomingDate ? 2 : 0) >= 3) return 'announcement';
    if (lines.length >= 8 || charCount(text) >= 350) return 'document';
    if (input.source === 'camera' || input.source === 'photo' || input.source === 'live') return lines.length >= 3 ? 'document' : 'observation';
    return 'note';
  }

  private highlights(statements: string[], now: Date): Highlight[] {
    const result: Highlight[] = [];
    for (const statement of statements) {
      if (charCount(statement) > 280) continue;
      const date = this.dateExtractor.extract(statement, now)[0]?.date;
      let kind: HighlightKind | undefined;
      if (date && deadlineCue.contains(statement)) kind = 'deadline';
      else if (warningCue.contains(statement)) kind = 'warning';
      else if (requirementCue.contains(statement)) kind = 'requirement';
      else if (date && countWhere(statement, isLetter) >= 3) kind = 'date';
      if (kind) result.push(date ? { kind, text: statement, date } : { kind, text: statement });
      if (result.length === 8) break;
    }
    return result;
  }

  private reminderSuggestions(highlights: Highlight[], fallbackTitle: string, kind: MemoryKind, now: Date): ReminderDraft[] {
    if (kind === 'receipt') return [];
    const drafts: ReminderDraft[] = [];
    const seenDates = new Set<number>();

    for (const highlight of highlights) {
      if (highlight.kind !== 'deadline' && highlight.kind !== 'date') continue;
      const detected = this.dateExtractor.extract(highlight.text, now)[0];
      if (!detected) continue;
      if (seenDates.has(detected.date.getTime())) continue;
      seenDates.add(detected.date.getTime());
      const fireDate = ReminderPolicy.suggestedFireDate(detected.date, detected.includesTime, highlight.kind === 'deadline', now, this.calendar);
      if (!fireDate) continue;
      const due = detected.includesTime ? detected.date : this.calendar.settingTime(detected.date, ReminderPolicy.defaultHour, 0);
      const title = ContentAnalyzer.reminderTitle(highlight.text, detected) ?? fallbackTitle;
      drafts.push({ title, timing: { type: 'at', date: fireDate }, dueDate: due, refersToContext: false });
      if (drafts.length === 3) break;
    }
    return drafts;
  }

  static reminderTitle(statement: string, detected: DetectedDate): string | undefined {
    if (detected.range.end > statement.length) return undefined;
    const trimEdges = (s: string) => trimWhere(s, (c) => isWhitespace(c) || isPunctuation(c));
    const combined = [statement.slice(0, detected.range.start), statement.slice(detected.range.end)]
      .map(trimEdges)
      .filter((s) => s.length > 0)
      .join(' ');
    const words = combined.split(' ').filter((w) => w.length > 0);
    while (words.length > 0 && trailingConnectors.has(words[words.length - 1].toLowerCase())) words.pop();
    while (words.length > 0 && trailingConnectors.has(words[0].toLowerCase())) words.shift();
    const title = trimPunctuationAndSpace(words.join(' '));
    if (countWhere(title, isLetter) < 3) return undefined;
    return capitalizedFirst(truncated(title, 80));
  }

  private title(kind: MemoryKind, lines: string[], statements: string[], merchant: string | undefined, labels: ImageLabel[]): string {
    switch (kind) {
      case 'receipt':
        return merchant ?? '';
      case 'object':
        return labels[0] ? labelDisplayName(labels[0].identifier) : lines[0] ? truncated(lines[0], 60) : '';
      case 'announcement':
      case 'event':
      case 'document':
        return ContentAnalyzer.heading(lines) ?? (statements[0] ? truncated(statements[0], 60) : '');
      default:
        return truncated(statements[0] ?? lines[0] ?? (labels[0] ? labelDisplayName(labels[0].identifier) : ''), 60);
    }
  }

  private static heading(lines: string[]): string | undefined {
    const candidates = lines.slice(0, 4).filter((line) => {
      const letters = countWhere(line, isLetter);
      const count = charCount(line);
      return count >= 3 && count <= 60 && letters >= 3 && letters / count > 0.6;
    });
    const shouting = candidates.find((line) => {
      const letters = lettersOf(line);
      return letters.filter(isUppercase).length * 10 >= letters.length * 7;
    });
    const chosen = shouting ?? candidates[0];
    if (!chosen) return undefined;
    return allLettersUppercase(chosen) ? capitalized(chosen) : chosen;
  }

  private summarize(kind: MemoryKind, statements: string[], highlights: Highlight[], merchant: string | undefined, total: MoneyAmount | undefined, dates: DetectedDate[], labels: ImageLabel[]): string {
    if (kind === 'receipt') return [merchant, total?.text, dates[0]?.text].filter((s): s is string => !!s).join(' · ');
    if (kind === 'object' && statements.length === 0) return labels.slice(0, 3).map((l) => labelDisplayName(l.identifier)).join(', ');
    const source = highlights.length === 0 ? statements.slice(0, 2) : highlights.slice(0, 2).map((h) => h.text);
    return truncated(source.join(' '), 220);
  }

  private static merchant(lines: string[]): string | undefined {
    const line = lines.slice(0, 5).find((l) => {
      const letters = countWhere(l, isLetter);
      const digits = countWhere(l, isNumber);
      return letters >= 3 && digits <= 2 && charCount(l) <= 40 && !receiptNoise.contains(l);
    });
    if (line === undefined) return undefined;
    return allLettersUppercase(line) ? capitalized(line) : line;
  }

  private static total(lines: string[], amounts: MoneyAmount[], extractor: EntityExtractor): MoneyAmount | undefined {
    for (let index = lines.length - 1; index >= 0; index--) {
      if (!totalLine.contains(lines[index])) continue;
      const onLine = extractor.money(lines[index]);
      if (onLine.length > 0) return onLine[onLine.length - 1];
      if (index + 1 < lines.length) {
        const next = extractor.money(lines[index + 1]);
        if (next.length > 0) return next[0];
      }
    }
    return amounts.reduce<MoneyAmount | undefined>((best, a) => (best === undefined || moneyValue(a) > moneyValue(best) ? a : best), undefined);
  }

  private tags(text: string, labels: ImageLabel[]): string[] {
    const tags = labels.slice(0, 3).map((l) => labelDisplayName(l.identifier).toLowerCase());
    const words = TextTokenizer.words(text).filter((w) => charCount(w) >= 4 && chars(w).every(isLetter) && !STOPWORDS.has(w));
    const counts = new Map<string, number>();
    const order: string[] = [];
    for (const word of words) {
      if (!counts.has(word)) order.push(word);
      counts.set(word, (counts.get(word) ?? 0) + 1);
    }
    const keywords = [...order].sort((a, b) => (counts.get(b) ?? 0) - (counts.get(a) ?? 0)).slice(0, 5);
    for (const keyword of keywords) if (!tags.includes(keyword)) tags.push(keyword);
    return tags;
  }

  static statements(lines: string[]): string[] {
    return lines.flatMap((line) => {
      const pieces: string[] = [];
      let start = 0;
      for (const match of sentenceBreak.matches(line)) {
        const piece = line.slice(start, match.range.start).trim();
        if (piece) pieces.push(piece);
        start = match.range.end;
      }
      const rest = line.slice(start).trim();
      if (rest) pieces.push(rest);
      return pieces;
    });
  }
}
