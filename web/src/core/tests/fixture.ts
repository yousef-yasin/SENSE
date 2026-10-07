import { Calendar } from '../calendar';

export const calendar = new Calendar(1, 'en-US');

export function date(year: number, month: number, day: number, hour = 0, minute = 0): Date {
  return new Date(year, month - 1, day, hour, minute);
}

export const now = date(2026, 10, 4, 10, 0);

export const plusSeconds = (base: Date, seconds: number) => new Date(base.getTime() + seconds * 1000);
