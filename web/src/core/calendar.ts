/** Gregorian calendar arithmetic in the runtime's local time zone. Weekdays are 1 (Sunday) through 7 (Saturday). */
export class Calendar {
  constructor(
    readonly firstWeekday = 1,
    readonly locale?: string,
  ) {}

  static current(): Calendar {
    const locale = typeof navigator !== 'undefined' ? navigator.language : undefined;
    let firstWeekday = 1;
    try {
      const info = locale ? new Intl.Locale(locale) : undefined;
      const weekInfo = info && ((info as any).getWeekInfo?.() ?? (info as any).weekInfo);
      if (weekInfo?.firstDay) firstWeekday = (weekInfo.firstDay % 7) + 1;
    } catch {
      // Keep Sunday when week information isn't available.
    }
    return new Calendar(firstWeekday, locale);
  }

  startOfDay(date: Date): Date {
    const result = new Date(date);
    result.setHours(0, 0, 0, 0);
    return result;
  }

  addDays(date: Date, days: number): Date {
    const result = new Date(date);
    result.setDate(result.getDate() + days);
    return result;
  }

  addMonths(date: Date, months: number): Date {
    const result = new Date(date);
    const day = result.getDate();
    result.setDate(1);
    result.setMonth(result.getMonth() + months);
    const lastDay = new Date(result.getFullYear(), result.getMonth() + 1, 0).getDate();
    result.setDate(Math.min(day, lastDay));
    return result;
  }

  settingTime(date: Date, hour: number, minute: number): Date {
    const result = new Date(date);
    result.setHours(hour, minute, 0, 0);
    return result;
  }

  weekday(date: Date): number {
    return date.getDay() + 1;
  }

  year(date: Date): number {
    return date.getFullYear();
  }

  /** Start of the given day, or null when the components don't form a real date. */
  make(year: number, month: number, day: number): Date | null {
    const result = new Date(2000, 0, 1);
    result.setFullYear(year, month - 1, day);
    result.setHours(0, 0, 0, 0);
    if (result.getMonth() !== month - 1 || result.getDate() !== day) return null;
    return result;
  }

  startOfWeek(date: Date): Date {
    const start = this.startOfDay(date);
    const delta = (this.weekday(start) - this.firstWeekday + 7) % 7;
    return this.addDays(start, -delta);
  }

  startOfMonth(date: Date): Date {
    return new Date(date.getFullYear(), date.getMonth(), 1);
  }
}

export interface DateInterval {
  start: Date;
  end: Date;
}

export function intervalContains(interval: DateInterval, date: Date): boolean {
  return date.getTime() >= interval.start.getTime() && date.getTime() <= interval.end.getTime();
}
