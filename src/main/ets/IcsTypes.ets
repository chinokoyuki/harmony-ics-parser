/**
 * Data structures produced by the parser.
 *
 * Field names follow RFC 5545 where possible so that the mapping stays obvious
 * when reading the specification side by side with this file.
 */

/** A parsed DATE or DATE-TIME value. */
export interface IcsDateTime {
  /** Local time unless {@link isUtc} is true, in which case it is a true instant. */
  date: Date
  /** True for VALUE=DATE (a calendar day, not a point in time). */
  isAllDay: boolean
  /** The value exactly as it appeared in the source, after unfolding. */
  raw: string
  /** TZID parameter, empty for floating or UTC values. */
  tzid: string
  /** True when the source value ended with Z. */
  isUtc: boolean
}

/** A VALARM block. */
export interface IcsAlarm {
  /** Seconds relative to DTSTART. Negative means "before the event". */
  triggerSeconds: number
  /** DISPLAY, AUDIO, EMAIL or whatever the file declared. */
  action: string
  description: string
}

/** A parsed RRULE. Unsupported parts are preserved in {@link raw}. */
export interface IcsRrule {
  /** DAILY, WEEKLY, MONTHLY or YEARLY. */
  freq: string
  interval: number
  /** Raw BYDAY tokens, e.g. ["MO", "2WE", "-1FR"]. */
  byDay: string[]
  byMonthDay: number[]
  byMonth: number[]
  until: IcsDateTime | null
  /** 0 when the rule has no COUNT. */
  count: number
  /** WKST, defaults to MO. */
  weekStart: string
  raw: string
}

/** One VEVENT. */
export interface IcsEvent {
  uid: string
  summary: string
  description: string
  location: string
  dtStart: IcsDateTime | null
  dtEnd: IcsDateTime | null
  priority: number
  /** TENTATIVE, CONFIRMED or CANCELLED. */
  status: string
  categories: string[]
  rrule: IcsRrule | null
  exdates: IcsDateTime[]
  alarms: IcsAlarm[]
  isAllDay: boolean
  /** Duration in seconds. 0 when neither DTEND nor DURATION was present. */
  durationSeconds: number
  /** X-WR-CALNAME of the enclosing VCALENDAR, if any. */
  calName: string
  /** OPAQUE or TRANSPARENT. */
  transp: string
  /** RECURRENCE-ID of an exception instance, if present. */
  recurrenceId: IcsDateTime | null
  created: IcsDateTime | null
  lastModified: IcsDateTime | null
  sequence: number
}

/** A concrete instance of an event, produced by recurrence expansion. */
export interface IcsOccurrence {
  start: Date
  end: Date
  isAllDay: boolean
  /** The event this occurrence came from. */
  event: IcsEvent
}

/** An event property split into name, parameters and value. */
export interface IcsProperty {
  name: string
  params: Map<string, string>
  value: string
}
