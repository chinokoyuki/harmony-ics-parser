import { describe, it, expect } from '@ohos/hypium'
import { parseIcs, parseDurationToSeconds, unescapeText } from '../main/ets/IcsParser'
import { expandOccurrences, getEventDurationMs } from '../main/ets/Recurrence'
import { IcsEvent } from '../main/ets/IcsTypes'

function ics(lines: string[]): string {
  return lines.join('\r\n')
}

const BASIC: string = ics([
  'BEGIN:VCALENDAR',
  'VERSION:2.0',
  'PRODID:-//Example//Example//EN',
  'X-WR-CALNAME:Study plan',
  'BEGIN:VEVENT',
  'UID:basic-1@example.com',
  'DTSTART:20260810T140000',
  'DTEND:20260810T153000',
  'SUMMARY:Linear algebra',
  'LOCATION:Room 302',
  'DESCRIPTION:Chapter 4\\, exercises 1-20',
  'CATEGORIES:Course,Math',
  'PRIORITY:3',
  'STATUS:CONFIRMED',
  'END:VEVENT',
  'END:VCALENDAR'
])

export default function icsParserTest() {
  describe('parseIcs', () => {
    it('reads the core fields of a VEVENT', 0, () => {
      const events: IcsEvent[] = parseIcs(BASIC)
      expect(events.length).assertEqual(1)
      const event: IcsEvent = events[0]
      expect(event.uid).assertEqual('basic-1@example.com')
      expect(event.summary).assertEqual('Linear algebra')
      expect(event.location).assertEqual('Room 302')
      expect(event.description).assertEqual('Chapter 4, exercises 1-20')
      expect(event.categories.length).assertEqual(2)
      expect(event.priority).assertEqual(3)
      expect(event.status).assertEqual('CONFIRMED')
      expect(event.calName).assertEqual('Study plan')
      expect(event.dtStart !== null).assertTrue()
      expect(event.dtStart !== null && event.dtStart.date.getTime()).assertEqual(new Date(2026, 7, 10, 14, 0, 0).getTime())
    })

    it('rejoins folded lines', 0, () => {
      const text: string = ics([
        'BEGIN:VCALENDAR',
        'BEGIN:VEVENT',
        'UID:folded@example.com',
        'DTSTART:20260810T090000',
        'SUMMARY:A very long title that was split across',
        '  two physical lines',
        'END:VEVENT',
        'END:VCALENDAR'
      ])
      const events: IcsEvent[] = parseIcs(text)
      expect(events.length).assertEqual(1)
      expect(events[0].summary).assertEqual('A very long title that was split across two physical lines')
    })

    it('converts Z values to an instant', 0, () => {
      const text: string = ics([
        'BEGIN:VCALENDAR',
        'BEGIN:VEVENT',
        'UID:utc@example.com',
        'DTSTART:20260810T060000Z',
        'SUMMARY:UTC event',
        'END:VEVENT',
        'END:VCALENDAR'
      ])
      const event: IcsEvent = parseIcs(text)[0]
      expect(event.dtStart !== null && event.dtStart.isUtc).assertTrue()
      expect(event.dtStart !== null && event.dtStart.date.toISOString()).assertEqual('2026-08-10T06:00:00.000Z')
    })

    it('keeps TZID for the caller instead of guessing', 0, () => {
      const text: string = ics([
        'BEGIN:VCALENDAR',
        'BEGIN:VEVENT',
        'UID:tzid@example.com',
        'DTSTART;TZID=Asia/Shanghai:20260810T140000',
        'SUMMARY:Zoned event',
        'END:VEVENT',
        'END:VCALENDAR'
      ])
      const event: IcsEvent = parseIcs(text)[0]
      expect(event.dtStart !== null && event.dtStart.tzid).assertEqual('Asia/Shanghai')
      expect(event.dtStart !== null && event.dtStart.isUtc).assertFalse()
    })

    it('reads all-day dates', 0, () => {
      const text: string = ics([
        'BEGIN:VCALENDAR',
        'BEGIN:VEVENT',
        'UID:date@example.com',
        'DTSTART;VALUE=DATE:20260810',
        'SUMMARY:Holiday',
        'END:VEVENT',
        'END:VCALENDAR'
      ])
      const event: IcsEvent = parseIcs(text)[0]
      expect(event.isAllDay).assertTrue()
      expect(getEventDurationMs(event)).assertEqual(86400000)
    })

    it('handles quoted parameters that contain a colon', 0, () => {
      const text: string = ics([
        'BEGIN:VCALENDAR',
        'BEGIN:VEVENT',
        'UID:param@example.com',
        'DTSTART:20260810T140000',
        'ORGANIZER;CN="Doe: John":mailto:john@example.com',
        'SUMMARY:Quoted parameter',
        'END:VEVENT',
        'END:VCALENDAR'
      ])
      const events: IcsEvent[] = parseIcs(text)
      expect(events.length).assertEqual(1)
      expect(events[0].summary).assertEqual('Quoted parameter')
    })

    it('reads VALARM triggers', 0, () => {
      const text: string = ics([
        'BEGIN:VCALENDAR',
        'BEGIN:VEVENT',
        'UID:alarm@example.com',
        'DTSTART:20260810T140000',
        'SUMMARY:With alarm',
        'BEGIN:VALARM',
        'TRIGGER:-PT15M',
        'ACTION:DISPLAY',
        'DESCRIPTION:Reminder',
        'END:VALARM',
        'END:VEVENT',
        'END:VCALENDAR'
      ])
      const event: IcsEvent = parseIcs(text)[0]
      expect(event.alarms.length).assertEqual(1)
      expect(event.alarms[0].triggerSeconds).assertEqual(-900)
      expect(event.alarms[0].action).assertEqual('DISPLAY')
    })

    it('derives DTEND from DURATION', 0, () => {
      const text: string = ics([
        'BEGIN:VCALENDAR',
        'BEGIN:VEVENT',
        'UID:duration@example.com',
        'DTSTART:20260810T140000',
        'DURATION:PT1H30M',
        'SUMMARY:One and a half hours',
        'END:VEVENT',
        'END:VCALENDAR'
      ])
      const event: IcsEvent = parseIcs(text)[0]
      expect(getEventDurationMs(event)).assertEqual(5400000)
      expect(event.dtEnd !== null && event.dtEnd.date.getTime()).assertEqual(new Date(2026, 7, 10, 15, 30, 0).getTime())
    })

    it('skips a malformed block without dropping the rest', 0, () => {
      const text: string = ics([
        'BEGIN:VCALENDAR',
        'BEGIN:VEVENT',
        'UID:no-start@example.com',
        'SUMMARY:Missing DTSTART',
        'END:VEVENT',
        'BEGIN:VEVENT',
        'UID:good@example.com',
        'DTSTART:20260810T140000',
        'SUMMARY:Valid',
        'END:VEVENT',
        'END:VCALENDAR'
      ])
      const events: IcsEvent[] = parseIcs(text)
      expect(events.length).assertEqual(1)
      expect(events[0].uid).assertEqual('good@example.com')
    })

    it('parses durations and escaped text', 0, () => {
      expect(parseDurationToSeconds('P1D')).assertEqual(86400)
      expect(parseDurationToSeconds('PT1H30M')).assertEqual(5400)
      expect(parseDurationToSeconds('-PT10M')).assertEqual(-600)
      expect(parseDurationToSeconds('P2W')).assertEqual(1209600)
      expect(unescapeText('a\\, b\\; c\\n d')).assertEqual('a, b; c\n d')
    })
  })

  describe('expandOccurrences', () => {
    it('expands a weekly rule with BYDAY and COUNT', 0, () => {
      const text: string = ics([
        'BEGIN:VCALENDAR',
        'BEGIN:VEVENT',
        'UID:weekly@example.com',
        'DTSTART:20260810T190000',
        'DTEND:20260810T200000',
        'RRULE:FREQ=WEEKLY;INTERVAL=1;BYDAY=MO,WE;COUNT=4',
        'SUMMARY:Evening class',
        'END:VEVENT',
        'END:VCALENDAR'
      ])
      const event: IcsEvent = parseIcs(text)[0]
      const occurrences = expandOccurrences(event, new Date(2026, 7, 1), new Date(2026, 8, 1))
      expect(occurrences.length).assertEqual(4)
      expect(occurrences[0].start.getTime()).assertEqual(new Date(2026, 7, 10, 19, 0, 0).getTime())
      expect(occurrences[1].start.getTime()).assertEqual(new Date(2026, 7, 12, 19, 0, 0).getTime())
      expect(occurrences[2].start.getTime()).assertEqual(new Date(2026, 7, 17, 19, 0, 0).getTime())
      expect(occurrences[3].start.getTime()).assertEqual(new Date(2026, 7, 19, 19, 0, 0).getTime())
    })

    it('honours INTERVAL', 0, () => {
      const text: string = ics([
        'BEGIN:VCALENDAR',
        'BEGIN:VEVENT',
        'UID:biweekly@example.com',
        'DTSTART:20260810T100000',
        'RRULE:FREQ=WEEKLY;INTERVAL=2',
        'SUMMARY:Every other week',
        'END:VEVENT',
        'END:VCALENDAR'
      ])
      const event: IcsEvent = parseIcs(text)[0]
      const occurrences = expandOccurrences(event, new Date(2026, 7, 1), new Date(2026, 9, 1))
      expect(occurrences.length).assertEqual(4)
      expect(occurrences[1].start.getTime()).assertEqual(new Date(2026, 7, 24, 10, 0, 0).getTime())
    })

    it('skips dates listed in EXDATE', 0, () => {
      const text: string = ics([
        'BEGIN:VCALENDAR',
        'BEGIN:VEVENT',
        'UID:exdate@example.com',
        'DTSTART:20260810T100000',
        'RRULE:FREQ=DAILY;COUNT=4',
        'EXDATE:20260811T100000',
        'SUMMARY:Daily standup',
        'END:VEVENT',
        'END:VCALENDAR'
      ])
      const event: IcsEvent = parseIcs(text)[0]
      const occurrences = expandOccurrences(event, new Date(2026, 7, 1), new Date(2026, 8, 1))
      expect(occurrences.length).assertEqual(3)
      expect(occurrences[0].start.getTime()).assertEqual(new Date(2026, 7, 10, 10, 0, 0).getTime())
      expect(occurrences[1].start.getTime()).assertEqual(new Date(2026, 7, 12, 10, 0, 0).getTime())
    })

    it('skips days that do not exist in a month', 0, () => {
      const text: string = ics([
        'BEGIN:VCALENDAR',
        'BEGIN:VEVENT',
        'UID:monthly@example.com',
        'DTSTART:20260131T090000',
        'RRULE:FREQ=MONTHLY;BYMONTHDAY=31',
        'SUMMARY:Month end review',
        'END:VEVENT',
        'END:VCALENDAR'
      ])
      const event: IcsEvent = parseIcs(text)[0]
      const occurrences = expandOccurrences(event, new Date(2026, 0, 1), new Date(2026, 4, 1))
      expect(occurrences.length).assertEqual(2)
      expect(occurrences[0].start.getTime()).assertEqual(new Date(2026, 0, 31, 9, 0, 0).getTime())
      expect(occurrences[1].start.getTime()).assertEqual(new Date(2026, 2, 31, 9, 0, 0).getTime())
    })

    it('supports ordinal BYDAY in monthly rules', 0, () => {
      const text: string = ics([
        'BEGIN:VCALENDAR',
        'BEGIN:VEVENT',
        'UID:ordinal@example.com',
        'DTSTART:20260112T180000',
        'RRULE:FREQ=MONTHLY;BYDAY=2MO',
        'SUMMARY:Club meeting',
        'END:VEVENT',
        'END:VCALENDAR'
      ])
      const event: IcsEvent = parseIcs(text)[0]
      const occurrences = expandOccurrences(event, new Date(2026, 0, 1), new Date(2026, 3, 1))
      expect(occurrences.length).assertEqual(3)
      expect(occurrences[1].start.getTime()).assertEqual(new Date(2026, 1, 9, 18, 0, 0).getTime())
    })

    it('stops at UNTIL', 0, () => {
      const text: string = ics([
        'BEGIN:VCALENDAR',
        'BEGIN:VEVENT',
        'UID:until@example.com',
        'DTSTART:20260810T080000',
        'RRULE:FREQ=DAILY;UNTIL=20260812T235959Z',
        'SUMMARY:Morning routine',
        'END:VEVENT',
        'END:VCALENDAR'
      ])
      const event: IcsEvent = parseIcs(text)[0]
      const occurrences = expandOccurrences(event, new Date(2026, 7, 1), new Date(2026, 8, 1))
      expect(occurrences.length).assertEqual(3)
    })

    it('returns one occurrence for a plain event', 0, () => {
      const event: IcsEvent = parseIcs(BASIC)[0]
      const inside = expandOccurrences(event, new Date(2026, 7, 10), new Date(2026, 7, 11))
      const outside = expandOccurrences(event, new Date(2026, 8, 1), new Date(2026, 8, 2))
      expect(inside.length).assertEqual(1)
      expect(outside.length).assertEqual(0)
    })

    it('respects WKST when grouping weeks', 0, () => {
      const text: string = ics([
        'BEGIN:VCALENDAR',
        'BEGIN:VEVENT',
        'UID:wkst@example.com',
        'DTSTART:20260812T090000',
        'RRULE:FREQ=WEEKLY;WKST=SU;BYDAY=SU,MO;COUNT=4',
        'SUMMARY:Week start on Sunday',
        'END:VEVENT',
        'END:VCALENDAR'
      ])
      const event: IcsEvent = parseIcs(text)[0]
      const occurrences = expandOccurrences(event, new Date(2026, 7, 1), new Date(2026, 8, 1))
      expect(occurrences.length).assertEqual(4)
      expect(occurrences[0].start.getDate()).assertEqual(12)
      expect(occurrences[1].start.getDate()).assertEqual(16)
      expect(occurrences[2].start.getDate()).assertEqual(17)
      expect(occurrences[3].start.getDate()).assertEqual(23)
    })

    it('supports negative BYMONTHDAY', 0, () => {
      const text: string = ics([
        'BEGIN:VCALENDAR',
        'BEGIN:VEVENT',
        'UID:last-day@example.com',
        'DTSTART:20260131T090000',
        'RRULE:FREQ=MONTHLY;BYMONTHDAY=-1',
        'SUMMARY:Last day of month',
        'END:VEVENT',
        'END:VCALENDAR'
      ])
      const event: IcsEvent = parseIcs(text)[0]
      const occurrences = expandOccurrences(event, new Date(2026, 0, 1), new Date(2026, 3, 1))
      expect(occurrences.length).assertEqual(3)
      expect(occurrences[1].start.getDate()).assertEqual(28)
    })

    it('keeps an occurrence that started before the range', 0, () => {
      const text: string = ics([
        'BEGIN:VCALENDAR',
        'BEGIN:VEVENT',
        'UID:overlap@example.com',
        'DTSTART:20260810T230000',
        'DTEND:20260811T010000',
        'SUMMARY:Late session',
        'END:VEVENT',
        'END:VCALENDAR'
      ])
      const event: IcsEvent = parseIcs(text)[0]
      const occurrences = expandOccurrences(event, new Date(2026, 7, 11, 0, 30), new Date(2026, 7, 12))
      expect(occurrences.length).assertEqual(1)
    })
  })

  describe('edge cases', () => {
    it('keeps calendar names separate in one file', 0, () => {
      const text: string = ics([
        'BEGIN:VCALENDAR',
        'X-WR-CALNAME:Work',
        'BEGIN:VEVENT',
        'UID:work@example.com',
        'DTSTART:20260810T090000',
        'SUMMARY:Work item',
        'END:VEVENT',
        'END:VCALENDAR',
        'BEGIN:VCALENDAR',
        'X-WR-CALNAME:Personal',
        'BEGIN:VEVENT',
        'UID:personal@example.com',
        'DTSTART:20260810T100000',
        'SUMMARY:Personal item',
        'END:VEVENT',
        'END:VCALENDAR'
      ])
      const events: IcsEvent[] = parseIcs(text)
      expect(events.length).assertEqual(2)
      expect(events[0].calName).assertEqual('Work')
      expect(events[1].calName).assertEqual('Personal')
    })

    it('accepts quoted parameters that contain a semicolon', 0, () => {
      const text: string = ics([
        'BEGIN:VCALENDAR',
        'BEGIN:VEVENT',
        'UID:semicolon@example.com',
        'DTSTART:20260810T090000',
        'ORGANIZER;CN="Smith; Jane";ROLE=CHAIR:mailto:jane@example.com',
        'SUMMARY:Quoted semicolon',
        'END:VEVENT',
        'END:VCALENDAR'
      ])
      expect(parseIcs(text).length).assertEqual(1)
    })
  })
}
