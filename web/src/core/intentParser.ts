import { Calendar } from './calendar';
import { DateExtractor } from './dateExtractor';
import { type ReminderDraft, ReminderPolicy, type ReminderTiming } from './models';
import { Pattern, type Span, capitalizedFirst, trimPunctuation, trimWhere, isPunctuation, isWhitespace } from './text';

export type UserIntent =
  | { type: 'remind'; draft: ReminderDraft }
  | { type: 'search'; query: string }
  | { type: 'recallSimilar' }
  | { type: 'analyzeSurroundings' }
  | { type: 'capture'; text: string };

const analyze = new Pattern(String.raw`^(?:hey sense,?\s*)?(?:what(?:'s| is) important(?: here)?|what am i looking at|what does (?:this|it) say|read (?:this|it)(?: for me)?|explain (?:this|what i'?m seeing)|what(?:'s| is) (?:this|here))\b`);
const recall = new Pattern(String.raw`\b(?:have|did|had) i (?:already |ever )?(?:seen|see|captured|capture|saved|save|noticed|notice|come across|photographed) (?:this|that|it)(?:\s+(?!before\b|already\b)[a-z]+)?(?: before| already)?\s*[?.!]*$`);
const remindPrefix = new Pattern(String.raw`^(?:hey sense,?\s*)?(?:please\s+)?(?:can you\s+|could you\s+)?(?:remind me|set (?:a|up a) reminder|create a reminder|add a reminder|don'?t let me forget)(?:\s+(?:to|about|of|for|that))?\b`);
const searchPrefix = new Pattern(String.raw`^(?:hey sense,?\s*)?(?:what (?:was|were|did i)|where (?:was|were|is|did|are)|when (?:did|was)|which|did i|have i|find|search(?: for)?|show me|look up|do you remember|do i have|what's that|what is that)\b`);
const placeClause = new Pattern(String.raw`\b(?:when|once|as soon as|after|whenever)\s+i(?:\s+|')(get to|get back to|get home|get back home|arrive at|arrive in|arrive home|arrive|reach|am at|'m at|m at|am in|'m in|m in|go to|leave|exit|get)\s*(?:the\s+|my\s+)?([^,.!?]*)`);
const atPlaceClause = new Pattern(String.raw`\b(?:at|near)\s+(?:the|my)\s+([a-z][^,.!?]*)$`);
const contextReferences = new Set(['this', 'that', 'it', 'these', 'those', 'this one', 'that one', 'this thing', 'that thing']);
const edgeWords = new Set(['to', 'about', 'at', 'on', 'by', 'when', 'in', 'the', 'that', 'and', 'please', 'for', 'of']);

export class IntentParser {
  readonly dateExtractor: DateExtractor;

  constructor(
    readonly calendar: Calendar = Calendar.current(),
    prefersDayFirst?: boolean,
  ) {
    this.dateExtractor = new DateExtractor(calendar, prefersDayFirst);
  }

  parse(utterance: string, now: Date = new Date()): UserIntent {
    const text = utterance.replace(/’/g, "'").trim();
    if (!text) return { type: 'capture', text: '' };
    const lowered = text.toLowerCase();

    if (analyze.contains(lowered)) return { type: 'analyzeSurroundings' };
    if (recall.contains(lowered)) return { type: 'recallSimilar' };
    const prefix = remindPrefix.firstMatch(lowered);
    if (prefix) return { type: 'remind', draft: this.reminderDraft(text.slice(prefix.range.end), now) };
    if (searchPrefix.contains(lowered)) return { type: 'search', query: text };
    return { type: 'capture', text };
  }

  reminderDraft(remainder: string, now: Date): ReminderDraft {
    let working = remainder;
    let timing: ReminderTiming = { type: 'unspecified' };
    let dueDate: Date | undefined;

    const dates = this.dateExtractor.extract(working, now, { standaloneTimes: true });
    const first = dates.find((d) => d.date.getTime() > now.getTime()) ?? dates[0];
    if (first) {
      const date = first.includesTime ? first.date : this.calendar.settingTime(first.date, ReminderPolicy.defaultHour, 0);
      if (date.getTime() > now.getTime()) {
        timing = { type: 'at', date };
        dueDate = date;
      }
      working = removing(first.range, working);
    }

    const clause = placeClause.firstMatch(working);
    if (clause) {
      const verb = (clause.group(1) ?? '').toLowerCase();
      let place = cleanPlace(clause.group(2) ?? '');
      if (verb.includes('home')) place = 'home';
      if (place) {
        timing = verb === 'leave' || verb === 'exit' ? { type: 'leaving', place } : { type: 'arriving', place };
        working = removing(clause.range, working);
      }
    } else if (timing.type === 'unspecified') {
      const atClause = atPlaceClause.firstMatch(working);
      if (atClause) {
        const place = cleanPlace(atClause.group(1) ?? '');
        if (place) {
          timing = { type: 'arriving', place };
          working = removing(atClause.range, working);
        }
      }
    }

    const subject = cleanSubject(working);
    const refersToContext = subject.length === 0 || contextReferences.has(subject.toLowerCase());
    const draft: ReminderDraft = { title: refersToContext ? '' : capitalizedFirst(subject), timing, refersToContext };
    if (dueDate) draft.dueDate = dueDate;
    return draft;
  }
}

function removing(range: Span, text: string): string {
  if (range.end > text.length) return text;
  return text.slice(0, range.start) + ' ' + text.slice(range.end);
}

function cleanSubject(text: string): string {
  const words = trimWhere(text, (c) => isWhitespace(c) || isPunctuation(c))
    .split(/\s+/)
    .filter((w) => w.length > 0);
  while (words.length > 0 && edgeWords.has(words[0].toLowerCase())) words.shift();
  while (words.length > 0 && edgeWords.has(words[words.length - 1].toLowerCase())) words.pop();
  return trimPunctuation(words.join(' '));
}

function cleanPlace(text: string): string {
  const words = text.trim().split(/\s+/).filter((w) => w.length > 0);
  const trailing = new Set(['please', 'today', 'tomorrow', 'tonight', 'later', 'again', 'next', 'time']);
  while (words.length > 0 && (trailing.has(words[words.length - 1].toLowerCase()) || edgeWords.has(words[words.length - 1].toLowerCase()))) words.pop();
  while (words.length > 0 && ['the', 'my', 'a', 'an', 'to', 'at'].includes(words[0].toLowerCase())) words.shift();
  return words.join(' ');
}
