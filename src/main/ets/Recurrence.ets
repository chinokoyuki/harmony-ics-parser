/**
 * Recurrence expansion for parsed events.
 *
 * Supported: FREQ (DAILY / WEEKLY / MONTHLY / YEARLY), INTERVAL, COUNT, UNTIL,
 * BYDAY (including ordinals such as 2MO and -1FR), BYMONTHDAY, BYMONTH and WKST.
 * EXDATE values are applied before the result is returned.
 */
import { IcsEvent, IcsOccurrence, IcsRrule } from './IcsTypes'

const DAY_MS: number = 86400000
const WEEKDAY_CODES: string[] = ['SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA']
const MAX_ITERATIONS: number = 20000

/** Calendar arithmetic that follows either UTC or local fields. */
class Calendar {
  private utc: boolean

  constructor(utc: boolean) {
    this.utc = utc
  }

  year(date: Date): number {
    return this.utc ? date.getUTCFullYear() : date.getFullYear()
  }

  month(date: Date): number {
    return this.utc ? date.getUTCMonth() : date.getMonth()
  }

  day(date: Date): number {
    return this.utc ? date.getUTCDate() : date.getDate()
  }

  weekday(date: Date): number {
    return this.utc ? date.getUTCDay() : date.getDay()
  }

  make(year: number, month: number, day: number, template: Date): Date {
    const h: number = this.utc ? template.getUTCHours() : template.getHours()
    const mi: number = this.utc ? template.getUTCMinutes() : template.getMinutes()
    const s: number = this.utc ? template.getUTCSeconds() : template.getSeconds()
    const ms: number = this.utc ? template.getUTCMilliseconds() : template.getMilliseconds()
    return this.utc ? new Date(Date.UTC(year, month, day, h, mi, s, ms)) : new Date(year, month, day, h, mi, s, ms)
  }

  addDays(date: Date, amount: number): Date {
    return this.make(this.year(date), this.month(date), this.day(date) + amount, date)
  }

  daysInMonth(year: number, month: number): number {
    if (this.utc) {
      return new Date(Date.UTC(year, month + 1, 0)).getUTCDate()
    }
    return new Date(year, month + 1, 0).getDate()
  }
}

/** Index of a weekday code such as `MO` or `2WE`. Returns -1 for unknown input. */
function weekdayIndex(token: string): number {
  const code: string = token.substring(token.length - 2).toUpperCase()
  for (let i = 0; i < WEEKDAY_CODES.length; i++) {
    if (WEEKDAY_CODES[i] === code) {
      return i
    }
  }
  return -1
}

/** Leading ordinal of a BYDAY token: `2MO` gives 2, `-1FR` gives -1, `MO` gives 0. */
function byDayOrdinal(token: string): number {
  let end: number = 0
  if (token.charAt(0) === '+' || token.charAt(0) === '-') {
    end = 1
  }
  let digits: number = 0
  while (end < token.length) {
    const ch: string = token.charAt(end)
    if (ch < '0' || ch > '9') {
      break
    }
    end++
    digits++
  }
  if (digits === 0) {
    return 0
  }
  const value: number = parseInt(token.substring(0, end), 10)
  return isNaN(value) ? 0 : value
}

/** Day of month for the nth weekday, e.g. second Monday or last Friday. Returns -1 when absent. */
function nthWeekdayOfMonth(cal: Calendar, year: number, month: number, ordinal: number, weekday: number): number {
  if (ordinal === 0) {
    return -1
  }
  const total: number = cal.daysInMonth(year, month)
  if (ordinal > 0) {
    const firstWeekday: number = cal.weekday(cal.make(year, month, 1, new Date(0)))
    const day: number = 1 + ((weekday - firstWeekday + 7) % 7) + (ordinal - 1) * 7
    return day <= total ? day : -1
  }
  const lastWeekday: number = cal.weekday(cal.make(year, month, total, new Date(0)))
  const day: number = total - ((lastWeekday - weekday + 7) % 7) + (ordinal + 1) * 7
  return day >= 1 ? day : -1
}

function sortDates(dates: Date[]): void {
  dates.sort((a: Date, b: Date): number => a.getTime() - b.getTime())
}

function containsTime(dates: Date[], time: number): boolean {
  for (let i = 0; i < dates.length; i++) {
    if (dates[i].getTime() === time) {
      return true
    }
  }
  return false
}

/** Duration of a single instance in milliseconds. All-day events default to one day. */
export function getEventDurationMs(event: IcsEvent): number {
  if (event.dtStart === null) {
    return 0
  }
  if (event.dtEnd !== null) {
    const diff: number = event.dtEnd.date.getTime() - event.dtStart.date.getTime()
    if (diff > 0) {
      return diff
    }
  }
  if (event.durationSeconds !== 0) {
    return event.durationSeconds * 1000
  }
  return event.dtStart.isAllDay ? DAY_MS : 0
}

/** True when the event carries an RRULE. */
export function isRecurring(event: IcsEvent): boolean {
  return event.rrule !== null
}

function overlaps(start: Date, end: Date, rangeStart: Date, rangeEnd: Date): boolean {
  if (end.getTime() <= start.getTime()) {
    return start.getTime() >= rangeStart.getTime() && start.getTime() < rangeEnd.getTime()
  }
  return start.getTime() < rangeEnd.getTime() && end.getTime() > rangeStart.getTime()
}

class Collector {
  private starts: Date[] = []
  private produced: number = 0
  private limit: number = 0
  private untilMs: number = -1
  private rangeEndMs: number = 0

  constructor(count: number, untilMs: number, rangeEndMs: number) {
    this.limit = count
    this.untilMs = untilMs
    this.rangeEndMs = rangeEndMs
  }

  /** Returns false once no further candidate can be useful. */
  accept(candidate: Date): boolean {
    const time: number = candidate.getTime()
    if (this.untilMs >= 0 && time > this.untilMs) {
      return false
    }
    if (time > this.rangeEndMs) {
      return false
    }
    if (this.limit > 0 && this.produced >= this.limit) {
      return false
    }
    this.starts.push(candidate)
    this.produced++
    return true
  }

  result(): Date[] {
    return this.starts
  }
}

function acceptAll(collector: Collector, candidates: Date[]): boolean {
  for (let i = 0; i < candidates.length; i++) {
    if (!collector.accept(candidates[i])) {
      return false
    }
  }
  return true
}

function expandDaily(cal: Calendar, start: Date, step: number, collector: Collector): void {
  for (let k = 0; k < MAX_ITERATIONS; k++) {
    if (!collector.accept(cal.addDays(start, k * step))) {
      return
    }
  }
}

function expandWeekly(cal: Calendar, rule: IcsRrule, start: Date, step: number, collector: Collector): void {
  let weekStart: number = 1
  if (weekdayIndex(rule.weekStart) >= 0) {
    weekStart = weekdayIndex(rule.weekStart)
  }
  const startWeekday: number = cal.weekday(start)
  const lead: number = (startWeekday - weekStart + 7) % 7
  const tokens: string[] = rule.byDay.length > 0 ? rule.byDay : [WEEKDAY_CODES[startWeekday]]
  for (let k = 0; k < MAX_ITERATIONS; k++) {
    const anchor: Date = cal.addDays(start, k * step * 7 - lead)
    const week: Date[] = []
    for (let t = 0; t < tokens.length; t++) {
      const index: number = weekdayIndex(tokens[t])
      if (index < 0) {
        continue
      }
      const offset: number = (index - weekStart + 7) % 7
      const day: Date = cal.addDays(anchor, offset)
      if (day.getTime() >= start.getTime()) {
        week.push(day)
      }
    }
    sortDates(week)
    if (!acceptAll(collector, week)) {
      return
    }
  }
}

function monthDaysFor(cal: Calendar, rule: IcsRrule, year: number, month: number, fallbackDay: number): number[] {
  const total: number = cal.daysInMonth(year, month)
  const days: number[] = []
  if (rule.byMonthDay.length > 0) {
    for (let i = 0; i < rule.byMonthDay.length; i++) {
      const value: number = rule.byMonthDay[i]
      const day: number = value > 0 ? value : total + value + 1
      if (day >= 1 && day <= total) {
        days.push(day)
      }
    }
    return days
  }
  if (rule.byDay.length > 0) {
    for (let i = 0; i < rule.byDay.length; i++) {
      const index: number = weekdayIndex(rule.byDay[i])
      if (index < 0) {
        continue
      }
      const day: number = nthWeekdayOfMonth(cal, year, month, byDayOrdinal(rule.byDay[i]), index)
      if (day > 0) {
        days.push(day)
      }
    }
    return days
  }
  if (fallbackDay <= total) {
    days.push(fallbackDay)
  }
  return days
}

function expandMonthly(cal: Calendar, rule: IcsRrule, start: Date, step: number, collector: Collector): void {
  const base: number = cal.year(start) * 12 + cal.month(start)
  const startDay: number = cal.day(start)
  for (let k = 0; k < MAX_ITERATIONS; k++) {
    const total: number = base + k * step
    const year: number = Math.floor(total / 12)
    const month: number = total % 12
    if (rule.byMonth.length > 0 && rule.byMonth.indexOf(month + 1) < 0) {
      continue
    }
    const days: number[] = monthDaysFor(cal, rule, year, month, startDay)
    const candidates: Date[] = []
    for (let i = 0; i < days.length; i++) {
      const candidate: Date = cal.make(year, month, days[i], start)
      if (candidate.getTime() >= start.getTime()) {
        candidates.push(candidate)
      }
    }
    sortDates(candidates)
    if (!acceptAll(collector, candidates)) {
      return
    }
  }
}

function expandYearly(cal: Calendar, rule: IcsRrule, start: Date, step: number, collector: Collector): void {
  const startYear: number = cal.year(start)
  const startDay: number = cal.day(start)
  for (let k = 0; k < MAX_ITERATIONS; k++) {
    const year: number = startYear + k * step
    const months: number[] = []
    if (rule.byMonth.length > 0) {
      for (let m = 0; m < rule.byMonth.length; m++) {
        months.push(rule.byMonth[m] - 1)
      }
    } else {
      months.push(cal.month(start))
    }
    const candidates: Date[] = []
    for (let i = 0; i < months.length; i++) {
      const month: number = months[i]
      if (month < 0 || month > 11) {
        continue
      }
      const days: number[] = monthDaysFor(cal, rule, year, month, startDay)
      for (let d = 0; d < days.length; d++) {
        const candidate: Date = cal.make(year, month, days[d], start)
        if (candidate.getTime() >= start.getTime()) {
          candidates.push(candidate)
        }
      }
    }
    sortDates(candidates)
    if (!acceptAll(collector, candidates)) {
      return
    }
  }
}

function expandRule(event: IcsEvent, rule: IcsRrule, rangeEnd: Date): Date[] {
  const start: Date = event.dtStart === null ? new Date(0) : event.dtStart.date
  const cal: Calendar = new Calendar(event.dtStart !== null && event.dtStart.isUtc)
  let untilMs: number = -1
  if (rule.until !== null) {
    untilMs = rule.until.date.getTime()
    if (rule.until.isAllDay) {
      untilMs += DAY_MS - 1
    }
  }
  const collector: Collector = new Collector(rule.count, untilMs, rangeEnd.getTime())
  const step: number = rule.interval > 0 ? rule.interval : 1

  if (rule.freq === 'DAILY') {
    expandDaily(cal, start, step, collector)
  } else if (rule.freq === 'WEEKLY') {
    expandWeekly(cal, rule, start, step, collector)
  } else if (rule.freq === 'MONTHLY') {
    expandMonthly(cal, rule, start, step, collector)
  } else {
    expandYearly(cal, rule, start, step, collector)
  }

  const starts: Date[] = collector.result()
  if (rule.count > 0) {
    if (!containsTime(starts, start.getTime())) {
      starts.push(new Date(start.getTime()))
      sortDates(starts)
    }
    if (starts.length > rule.count) {
      starts.splice(rule.count, starts.length - rule.count)
    }
  }
  return starts
}

/**
 * Returns every instance of an event that intersects `[rangeStart, rangeEnd)`.
 *
 * Events without an RRULE produce at most one occurrence. `maxCount` caps the
 * result, which matters for unbounded rules queried over a long range.
 */
export function expandOccurrences(event: IcsEvent, rangeStart: Date, rangeEnd: Date, maxCount: number = 1000): IcsOccurrence[] {
  const occurrences: IcsOccurrence[] = []
  if (event.dtStart === null || rangeEnd.getTime() <= rangeStart.getTime()) {
    return occurrences
  }
  const duration: number = getEventDurationMs(event)
  const excluded = new Set<number>()
  for (let i = 0; i < event.exdates.length; i++) {
    excluded.add(event.exdates[i].date.getTime())
  }

  let starts: Date[] = []
  if (event.rrule === null) {
    starts.push(event.dtStart.date)
  } else {
    starts = expandRule(event, event.rrule, rangeEnd)
  }

  for (let i = 0; i < starts.length; i++) {
    const start: Date = starts[i]
    if (excluded.has(start.getTime())) {
      continue
    }
    const end: Date = new Date(start.getTime() + duration)
    if (!overlaps(start, end, rangeStart, rangeEnd)) {
      continue
    }
    const occurrence: IcsOccurrence = {
      start: start,
      end: end,
      isAllDay: event.isAllDay,
      event: event
    }
    occurrences.push(occurrence)
    if (occurrences.length >= maxCount) {
      break
    }
  }
  return occurrences
}
