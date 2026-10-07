import { Pattern, type Span, isNumber, spanOverlaps } from './text';

export interface MoneyAmount {
  text: string;
  /** Normalized decimal string, e.g. "4.5" for "4.50". */
  value: string;
  currency?: string;
  range: Span;
}

const currencyCodes = 'usd|eur|gbp|jod|jd|sar|aed|egp|kwd|qar|try|cad|aud|chf|jpy|inr';
const symbolAmount = new Pattern(String.raw`(?<![\w])([$€£¥₹]|${currencyCodes})\s?(\d{1,3}(?:,\d{3})+(?:\.\d{1,3})?|\d+(?:\.\d{1,3})?)(?![\d])`);
const decimalAmount = new Pattern(String.raw`(?<![\d.,])(\d{1,3}(?:,\d{3})+\.\d{2,3}|\d+\.\d{2,3})(?![\d])(?!\s?[ap]\.?m\b)(?:\s?(${currencyCodes})\b)?`);
const emailPattern = new Pattern(String.raw`[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}`);
const linkPattern = new Pattern(String.raw`\b(?:https?://|www\.)[^\s<>"']+`);
const phonePattern = new Pattern(String.raw`(?<![\w+])(?:\+\d{1,3}[\s.\-]?)?(?:\(\d{1,4}\)[\s.\-]?)?\d{2,4}(?:[\s.\-]\d{2,4}){1,3}(?![\w])`);

const symbolCodes: Record<string, string> = { $: 'USD', '€': 'EUR', '£': 'GBP', '¥': 'JPY', '₹': 'INR', jd: 'JOD' };

export function normalizeDecimal(text: string): string | null {
  const plain = text.replace(/,/g, '');
  if (!/^\d+(\.\d+)?$/.test(plain)) return null;
  let [whole, fraction = ''] = plain.split('.');
  whole = whole.replace(/^0+(?=\d)/, '');
  fraction = fraction.replace(/0+$/, '');
  return fraction ? `${whole}.${fraction}` : whole;
}

export function moneyValue(amount: MoneyAmount): number {
  return Number(amount.value);
}

export class EntityExtractor {
  money(text: string, excluding: Span[] = []): MoneyAmount[] {
    const amounts: MoneyAmount[] = [];
    const candidates = [
      ...symbolAmount.matches(text).map((match) => ({ match, symbolFirst: true })),
      ...decimalAmount.matches(text).map((match) => ({ match, symbolFirst: false })),
    ];
    for (const { match, symbolFirst } of candidates) {
      if (excluding.some((r) => spanOverlaps(match.range, r)) || amounts.some((a) => spanOverlaps(match.range, a.range))) continue;
      const numberText = (symbolFirst ? match.group(2) : match.group(1)) ?? '';
      const currencyText = symbolFirst ? match.group(1) : match.group(2);
      const value = normalizeDecimal(numberText);
      if (value === null) continue;
      const currency = currencyText ? (symbolCodes[currencyText.toLowerCase()] ?? currencyText.toUpperCase()) : undefined;
      amounts.push(currency ? { text: match.text, value, currency, range: match.range } : { text: match.text, value, range: match.range });
    }
    return amounts.sort((a, b) => a.range.start - b.range.start);
  }

  emails(text: string): string[] {
    return unique(emailPattern.matches(text).map((m) => m.text));
  }

  links(text: string): string[] {
    const urls: string[] = [];
    for (const match of linkPattern.matches(text)) {
      const cleaned = match.text.replace(/^[.,;:)\]}!?"']+|[.,;:)\]}!?"']+$/g, '');
      const normalized = cleaned.toLowerCase().startsWith('www.') ? 'https://' + cleaned : cleaned;
      try {
        if (!new URL(normalized).host) continue;
      } catch {
        continue;
      }
      if (!urls.includes(normalized)) urls.push(normalized);
    }
    return urls;
  }

  phoneNumbers(text: string, excluding: Span[] = []): string[] {
    const numbers: string[] = [];
    for (const match of phonePattern.matches(text)) {
      if (excluding.some((r) => spanOverlaps(match.range, r))) continue;
      const candidate = match.text;
      const digits = Array.from(candidate).filter(isNumber).length;
      if (digits < 7 || digits > 15) continue;
      if (!candidate.startsWith('+') && !/[ \-(]/.test(candidate)) continue;
      numbers.push(candidate);
    }
    return unique(numbers);
  }
}

function unique(values: string[]): string[] {
  const seen = new Set<string>();
  return values.filter((v) => {
    const key = v.toLowerCase();
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}
