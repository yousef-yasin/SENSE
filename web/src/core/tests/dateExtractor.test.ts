import { describe, expect, it } from 'vitest';
import { DateExtractor, type ExtractOptions } from '../dateExtractor';
import { calendar, date, now, plusSeconds } from './fixture';

const extractor = new DateExtractor(calendar, false);
const extract = (text: string, options: ExtractOptions = {}) => extractor.extract(text, now, options);

describe('DateExtractor', () => {
  it('month name with time', () => {
    const dates = extract('Registration closes October 8 at 4 PM.');
    expect(dates.length).toBe(1);
    expect(dates[0].date).toEqual(date(2026, 10, 8, 16, 0));
    expect(dates[0].includesTime).toBe(true);
    expect(dates[0].text).toBe('October 8 at 4 PM');
  });

  it('abbreviated month with ordinal and year', () => {
    const dates = extract('Due: Oct. 12th, 2026');
    expect(dates[0].date).toEqual(date(2026, 10, 12));
    expect(dates[0].includesTime).toBe(false);
  });

  it('day before month', () => {
    expect(extract('Submit by 15 November')[0].date).toEqual(date(2026, 11, 15));
  });

  it('time before date', () => {
    expect(extract('Doors open 6:30pm on Friday, October 9')[0].date).toEqual(date(2026, 10, 9, 18, 30));
  });

  it('weekday next to date is not counted twice', () => {
    const dates = extract('Thursday, October 8');
    expect(dates.length).toBe(1);
    expect(dates[0].date).toEqual(date(2026, 10, 8));
  });

  it('numeric dates', () => {
    expect(extract('Date: 10/02/2026 14:32')[0].date).toEqual(date(2026, 10, 2, 14, 32));
    expect(extract('2026-11-20')[0].date).toEqual(date(2026, 11, 20));
    expect(extract('expires 25/12/2026')[0].date).toEqual(date(2026, 12, 25));
  });

  it('day-first locale', () => {
    const dayFirst = new DateExtractor(calendar, true);
    expect(dayFirst.extract('03/11/2026', now)[0].date).toEqual(date(2026, 11, 3));
  });

  it('year inference picks nearest occurrence', () => {
    expect(extract('January 15')[0].date).toEqual(date(2027, 1, 15));
    expect(extract('September 20')[0].date).toEqual(date(2026, 9, 20));
  });

  it('relative days', () => {
    expect(extract('tomorrow at 5pm')[0].date).toEqual(date(2026, 10, 5, 17, 0));
    expect(extract('tonight')[0].date).toEqual(date(2026, 10, 4, 20, 0));
    expect(extract('the day after tomorrow')[0].date).toEqual(date(2026, 10, 6));
    expect(extract('tomorrow morning')[0].date).toEqual(date(2026, 10, 5, 9, 0));
  });

  it('weekdays', () => {
    expect(extract('on Friday')[0].date).toEqual(date(2026, 10, 9));
    expect(extract('next Sunday')[0].date).toEqual(date(2026, 10, 11));
    expect(extract('this Sunday')[0].date).toEqual(date(2026, 10, 4));
  });

  it('durations', () => {
    expect(extract('in 2 hours')[0].date).toEqual(plusSeconds(now, 7200));
    expect(extract('in half an hour')[0].date).toEqual(plusSeconds(now, 1800));
    expect(extract('in three days')[0].date).toEqual(date(2026, 10, 7));
  });

  it('standalone times only when requested', () => {
    expect(extract('Office hours 9:00')).toEqual([]);
    expect(extract('at 5', { standaloneTimes: true })[0].date).toEqual(date(2026, 10, 4, 17, 0));
    expect(extract('at 8:15 am', { standaloneTimes: true })[0].date).toEqual(date(2026, 10, 5, 8, 15));
  });

  it('rejects invalid dates and prices', () => {
    expect(extract('February 31')).toEqual([]);
    expect(extract('Total 12.30')).toEqual([]);
    expect(extract('Rated 4.5 stars')).toEqual([]);
  });
});
