/**
 * iCalendar / vCalendar parser.
 *
 * Scope: VCALENDAR + VEVENT + VALARM. VTODO, VJOURNAL, VFREEBUSY and VTIMEZONE
 * are skipped rather than rejected, so mixed files still yield their events.
 */
import { IcsAlarm, IcsDateTime, IcsEvent, IcsProperty, IcsRrule } from './IcsTypes'

/** Splits on a separator while ignoring separators inside double quotes. */
function splitUnquoted(text: string, separator: string): string[] {
  const parts: string[] = []
  let buffer: string = ''
  let quoted: boolean = false
  for (let i = 0; i < text.length; i++) {
    const ch: string = text.charAt(i)
    if (ch === '"') {
      quoted = !quoted
      buffer += ch
      continue
    }
    if (!quoted && ch === separator) {
      parts.push(buffer)
      buffer = ''
      continue
    }
    buffer += ch
  }
  parts.push(buffer)
  return parts
}

/** Finds the first separator outside quotes, or -1. */
function indexOfUnquoted(text: string, separator: string): number {
  let quoted: boolean = false
  for (let i = 0; i < text.length; i++) {
    const ch: string = text.charAt(i)
    if (ch === '"') {
      quoted = !quoted
      continue
    }
    if (!quoted && ch === separator) {
      return i
    }
  }
  return -1
}

/**
 * Reverses the text escaping defined in RFC 5545 section 3.3.11.
 * `\\n` becomes a newline, `\\,` a comma, `\\;` a semicolon and `\\\\` a backslash.
 */
export function unescapeText(text: string): string {
  let out: string = ''
  let i: number = 0
  while (i < text.length) {
    const ch: string = text.charAt(i)
    if (ch !== '\\') {
      out += ch
      i++
      continue
    }
    const next: string = text.charAt(i + 1)
    if (next === 'n' || next === 'N') {
      out += '\n'
    } else if (next === ',') {
      out += ','
    } else if (next === ';') {
      out += ';'
    } else if (next === '\\') {
      out += '\\'
    } else if (next.length > 0) {
      out += next
    } else {
      out += ch
    }
    i += 2
  }
  return out
}

/** Splits on an unescaped comma, keeping escape sequences intact for later unescaping. */
function splitEscapedList(value: string, separator: string): string[] {
  const parts: string[] = []
  let buffer: string = ''
  let i: number = 0
  while (i < value.length) {
    const ch: string = value.charAt(i)
    if (ch === '\\' && i + 1 < value.length) {
      buffer += ch + value.charAt(i + 1)
      i += 2
      continue
    }
    if (ch === separator) {
      parts.push(buffer)
      buffer = ''
      i++
      continue
    }
    buffer += ch
    i++
  }
  parts.push(buffer)
  return parts
}

/**
 * Unfolds the content lines. RFC 5545 folds long lines by inserting CRLF
 * followed by a single space or tab, which is removed on read.
 */
function unfoldLines(text: string): string[] {
  let source: string = text
  if (source.length > 0 && source.charCodeAt(0) === 0xFEFF) {
    source = source.substring(1)
  }
  const raw: string[] = source.split(/\r?\n/)
  const lines: string[] = []
  for (let i = 0; i < raw.length; i++) {
    const line: string = raw[i]
    if (line.length === 0) {
      continue
    }
    const first: string = line.charAt(0)
    if ((first === ' ' || first === '\t') && lines.length > 0) {
      lines[lines.length - 1] += line.substring(1)
      continue
    }
    lines.push(line)
  }
  return lines
}

/**
 * Parses `NAME;PARAM=value;PARAM="quoted:value":VALUE`.
 * Parameter names are upper-cased. When a parameter repeats, the last value wins.
 */
export function parseProperty(line: string): IcsProperty {
  const colon: number = indexOfUnquoted(line, ':')
  const prop: IcsProperty = {
    name: '',
    params: new Map<string, string>(),
    value: ''
  }
  if (colon < 0) {
    prop.name = line.trim().toUpperCase()
    return prop
  }
  const head: string = line.substring(0, colon)
  prop.value = line.substring(colon + 1)
  const segments: string[] = splitUnquoted(head, ';')
  prop.name = segments[0].trim().toUpperCase()
  for (let i = 1; i < segments.length; i++) {
    const segment: string = segments[i]
    const eq: number = segment.indexOf('=')
    if (eq <= 0) {
      continue
    }
    const key: string = segment.substring(0, eq).trim().toUpperCase()
    let value: string = segment.substring(eq + 1).trim()
    if (value.length >= 2 && value.charAt(0) === '"' && value.charAt(value.length - 1) === '"') {
      value = value.substring(1, value.length - 1)
    }
    prop.params.set(key, value)
  }
  return prop
}

function isValidDate(year: number, month: number, day: number): boolean {
  if (isNaN(year) || isNaN(month) || isNaN(day)) {
    return false
  }
  if (month < 1 || month > 12 || day < 1 || day > 31) {
    return false
  }
  return day <= new Date(year, month, 0).getDate()
}

/**
 * Parses `YYYYMMDD` or `YYYYMMDDTHHMMSS`, with an optional trailing Z.
 *
 * Values ending in Z are converted to a real instant. Values carrying TZID are
 * read as local time, because resolving a time zone would require a tz database;
 * the identifier stays available on {@link IcsDateTime.tzid} for the caller.
 */
export function parseIcsDateTime(value: string, params: Map<string, string> = new Map<string, string>()): IcsDateTime | null {
  const trimmed: string = value.trim()
  let tzid: string = ''
  const zone: string | undefined = params.get('TZID')
  if (zone !== undefined) {
    tzid = zone
  }
  const isUtc: boolean = trimmed.length > 0 && (trimmed.charAt(trimmed.length - 1) === 'Z' || trimmed.charAt(trimmed.length - 1) === 'z')
  const clean: string = isUtc ? trimmed.substring(0, trimmed.length - 1) : trimmed
  const dateOnly: boolean = params.get('VALUE') === 'DATE' || clean.length === 8

  if (dateOnly) {
    if (clean.length < 8) {
      return null
    }
    const y: number = parseInt(clean.substring(0, 4), 10)
    const m: number = parseInt(clean.substring(4, 6), 10)
    const d: number = parseInt(clean.substring(6, 8), 10)
    if (!isValidDate(y, m, d)) {
      return null
    }
    const result: IcsDateTime = {
      date: isUtc ? new Date(Date.UTC(y, m - 1, d)) : new Date(y, m - 1, d),
      isAllDay: true,
      raw: value,
      tzid: tzid,
      isUtc: isUtc
    }
    return result
  }

  if (clean.length < 15) {
    return null
  }
  const y: number = parseInt(clean.substring(0, 4), 10)
  const m: number = parseInt(clean.substring(4, 6), 10)
  const d: number = parseInt(clean.substring(6, 8), 10)
  const h: number = parseInt(clean.substring(9, 11), 10)
  const mi: number = parseInt(clean.substring(11, 13), 10)
  const s: number = parseInt(clean.substring(13, 15), 10)
  if (!isValidDate(y, m, d) || isNaN(h) || isNaN(mi) || isNaN(s)) {
    return null
  }
  if (h > 23 || mi > 59 || s > 60) {
    return null
  }
  const result: IcsDateTime = {
    date: isUtc ? new Date(Date.UTC(y, m - 1, d, h, mi, s)) : new Date(y, m - 1, d, h, mi, s),
    isAllDay: false,
    raw: value,
    tzid: tzid,
    isUtc: isUtc
  }
  return result
}

/** Parses an ISO 8601 duration such as `-PT15M`, `P1D` or `PT1H30M` into seconds. */
export function parseDurationToSeconds(duration: string): number {
  const text: string = duration.trim().toUpperCase()
  const negative: boolean = text.charAt(0) === '-'
  let i: number = text.charAt(0) === '-' || text.charAt(0) === '+' ? 1 : 0
  if (i < text.length && text.charAt(i) === 'P') {
    i++
  }
  let total: number = 0
  let numStart: number = i
  while (i < text.length) {
    const ch: string = text.charAt(i)
    if (ch >= '0' && ch <= '9') {
      i++
      continue
    }
    const amount: number = parseInt(text.substring(numStart, i), 10)
    if (!isNaN(amount)) {
      if (ch === 'W') {
        total += amount * 604800
      } else if (ch === 'D') {
        total += amount * 86400
      } else if (ch === 'H') {
        total += amount * 3600
      } else if (ch === 'M') {
        total += amount * 60
      } else if (ch === 'S') {
        total += amount
      }
    }
    i++
    numStart = i
  }
  return negative ? -total : total
}

/** Parses an RRULE value. Returns null when FREQ is missing or unrecognised. */
export function parseRrule(value: string): IcsRrule | null {
  let freq: string = ''
  let interval: number = 1
  const byDay: string[] = []
  const byMonthDay: number[] = []
  const byMonth: number[] = []
  let until: IcsDateTime | null = null
  let count: number = 0
  let weekStart: string = 'MO'

  const parts: string[] = value.split(';')
  for (let i = 0; i < parts.length; i++) {
    const part: string = parts[i]
    const eq: number = part.indexOf('=')
    if (eq < 0) {
      continue
    }
    const key: string = part.substring(0, eq).trim().toUpperCase()
    const val: string = part.substring(eq + 1).trim()
    if (key === 'FREQ') {
      freq = val.toUpperCase()
    } else if (key === 'INTERVAL') {
      const n: number = parseInt(val, 10)
      interval = isNaN(n) || n < 1 ? 1 : n
    } else if (key === 'BYDAY') {
      const tokens: string[] = val.split(',')
      for (let t = 0; t < tokens.length; t++) {
        const token: string = tokens[t].trim().toUpperCase()
        if (token.length > 0) {
          byDay.push(token)
        }
      }
    } else if (key === 'BYMONTHDAY') {
      const tokens: string[] = val.split(',')
      for (let t = 0; t < tokens.length; t++) {
        const n: number = parseInt(tokens[t].trim(), 10)
        if (!isNaN(n)) {
          byMonthDay.push(n)
        }
      }
    } else if (key === 'BYMONTH') {
      const tokens: string[] = val.split(',')
      for (let t = 0; t < tokens.length; t++) {
        const n: number = parseInt(tokens[t].trim(), 10)
        if (!isNaN(n)) {
          byMonth.push(n)
        }
      }
    } else if (key === 'COUNT') {
      const n: number = parseInt(val, 10)
      count = isNaN(n) ? 0 : n
    } else if (key === 'UNTIL') {
      until = parseIcsDateTime(val)
    } else if (key === 'WKST') {
      weekStart = val.toUpperCase()
    }
  }

  if (freq !== 'DAILY' && freq !== 'WEEKLY' && freq !== 'MONTHLY' && freq !== 'YEARLY') {
    return null
  }
  const rule: IcsRrule = {
    freq: freq,
    interval: interval,
    byDay: byDay,
    byMonthDay: byMonthDay,
    byMonth: byMonth,
    until: until,
    count: count,
    weekStart: weekStart,
    raw: value
  }
  return rule
}

/** Parses a comma separated EXDATE value. */
function parseExdates(value: string): IcsDateTime[] {
  const result: IcsDateTime[] = []
  const parts: string[] = value.split(',')
  for (let i = 0; i < parts.length; i++) {
    const dt: IcsDateTime | null = parseIcsDateTime(parts[i].trim())
    if (dt !== null) {
      result.push(dt)
    }
  }
  return result
}

/** Parses a VALARM block. Returns null when no ACTION was declared. */
function parseValarm(lines: string[]): IcsAlarm | null {
  let triggerSeconds: number = 0
  let action: string = ''
  let description: string = ''
  for (let i = 0; i < lines.length; i++) {
    const prop: IcsProperty = parseProperty(lines[i])
    if (prop.name === 'TRIGGER') {
      triggerSeconds = parseDurationToSeconds(prop.value)
    } else if (prop.name === 'ACTION') {
      action = prop.value.trim().toUpperCase()
    } else if (prop.name === 'DESCRIPTION') {
      description = unescapeText(prop.value)
    }
  }
  if (action.length === 0) {
    return null
  }
  const alarm: IcsAlarm = {
    triggerSeconds: triggerSeconds,
    action: action,
    description: description
  }
  return alarm
}

function emptyEvent(): IcsEvent {
  const event: IcsEvent = {
    uid: '',
    summary: '',
    description: '',
    location: '',
    dtStart: null,
    dtEnd: null,
    priority: 0,
    status: '',
    categories: [],
    rrule: null,
    exdates: [],
    alarms: [],
    isAllDay: false,
    durationSeconds: 0,
    calName: '',
    transp: '',
    recurrenceId: null,
    created: null,
    lastModified: null,
    sequence: 0
  }
  return event
}

/** Parses a single VEVENT block. Returns null when DTSTART is missing or invalid. */
function parseVevent(lines: string[]): IcsEvent | null {
  const event: IcsEvent = emptyEvent()
  let i: number = 0
  while (i < lines.length) {
    const line: string = lines[i]
    if (line.toUpperCase().startsWith('BEGIN:VALARM')) {
      const alarmLines: string[] = []
      i++
      while (i < lines.length && !lines[i].toUpperCase().startsWith('END:VALARM')) {
        alarmLines.push(lines[i])
        i++
      }
      i++
      const alarm: IcsAlarm | null = parseValarm(alarmLines)
      if (alarm !== null) {
        event.alarms.push(alarm)
      }
      continue
    }
    const prop: IcsProperty = parseProperty(line)
    const value: string = prop.value
    if (prop.name === 'UID') {
      event.uid = value.trim()
    } else if (prop.name === 'SUMMARY') {
      event.summary = unescapeText(value)
    } else if (prop.name === 'DESCRIPTION') {
      event.description = unescapeText(value)
    } else if (prop.name === 'LOCATION') {
      event.location = unescapeText(value)
    } else if (prop.name === 'DTSTART') {
      event.dtStart = parseIcsDateTime(value, prop.params)
      if (event.dtStart !== null) {
        event.isAllDay = event.dtStart.isAllDay
      }
    } else if (prop.name === 'DTEND') {
      event.dtEnd = parseIcsDateTime(value, prop.params)
    } else if (prop.name === 'DURATION') {
      event.durationSeconds = parseDurationToSeconds(value)
    } else if (prop.name === 'PRIORITY') {
      const n: number = parseInt(value, 10)
      event.priority = isNaN(n) ? 0 : n
    } else if (prop.name === 'STATUS') {
      event.status = value.trim().toUpperCase()
    } else if (prop.name === 'TRANSP') {
      event.transp = value.trim().toUpperCase()
    } else if (prop.name === 'CATEGORIES') {
      const raw: string[] = splitEscapedList(value, ',')
      for (let c = 0; c < raw.length; c++) {
        const category: string = unescapeText(raw[c]).trim()
        if (category.length > 0) {
          event.categories.push(category)
        }
      }
    } else if (prop.name === 'RRULE') {
      event.rrule = parseRrule(value)
    } else if (prop.name === 'EXDATE') {
      const dates: IcsDateTime[] = parseExdates(value)
      for (let d = 0; d < dates.length; d++) {
        event.exdates.push(dates[d])
      }
    } else if (prop.name === 'RECURRENCE-ID') {
      event.recurrenceId = parseIcsDateTime(value, prop.params)
    } else if (prop.name === 'CREATED') {
      event.created = parseIcsDateTime(value, prop.params)
    } else if (prop.name === 'LAST-MODIFIED') {
      event.lastModified = parseIcsDateTime(value, prop.params)
    } else if (prop.name === 'SEQUENCE') {
      const n: number = parseInt(value, 10)
      event.sequence = isNaN(n) ? 0 : n
    }
    i++
  }

  if (event.dtStart === null) {
    return null
  }
  if (event.dtEnd === null && event.durationSeconds !== 0) {
    const derived: IcsDateTime = {
      date: new Date(event.dtStart.date.getTime() + event.durationSeconds * 1000),
      isAllDay: event.dtStart.isAllDay,
      raw: '',
      tzid: event.dtStart.tzid,
      isUtc: false
    }
    event.dtEnd = derived
  }
  return event
}

/**
 * Parses iCalendar or vCalendar text into a list of events.
 *
 * Events that cannot be parsed are dropped individually; one malformed block
 * never prevents the rest of the file from being read. Order is preserved.
 */
export function parseIcs(text: string): IcsEvent[] {
  const lines: string[] = unfoldLines(text)
  const events: IcsEvent[] = []
  let calName: string = ''
  let i: number = 0
  while (i < lines.length) {
    const upper: string = lines[i].toUpperCase()
    if (upper.startsWith('BEGIN:VCALENDAR')) {
      calName = ''
      i++
      continue
    }
    if (upper.startsWith('X-WR-CALNAME')) {
      calName = unescapeText(parseProperty(lines[i]).value).trim()
      i++
      continue
    }
    if (upper.startsWith('BEGIN:VEVENT')) {
      const body: string[] = []
      i++
      while (i < lines.length && !lines[i].toUpperCase().startsWith('END:VEVENT')) {
        body.push(lines[i])
        i++
      }
      i++
      const event: IcsEvent | null = parseVevent(body)
      if (event !== null) {
        event.calName = calName
        events.push(event)
      }
      continue
    }
    i++
  }
  return events
}
