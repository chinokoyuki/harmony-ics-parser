# harmony-ics-parser

An iCalendar (RFC 5545) parser and recurrence expander written in ArkTS for HarmonyOS.

It turns `.ics` text into typed events, then answers the question calendar features actually ask: which dates does this event land on between A and B?

[中文说明](README.zh-CN.md)

## Features

- VCALENDAR, VEVENT and VALARM, including line unfolding, text unescaping and quoted parameters
- DATE, DATE-TIME, UTC (`Z`), `TZID` and floating time values
- `DURATION` as an alternative to `DTEND`
- Recurrence for DAILY, WEEKLY, MONTHLY and YEARLY rules, with `INTERVAL`, `COUNT`, `UNTIL`, `BYDAY` (ordinals included), `BYMONTHDAY`, `BYMONTH` and `WKST`
- `EXDATE` filtering
- No runtime dependencies, no native code, no system APIs beyond ECMAScript built-ins

## Requirements

Stage model, ArkTS. The module targets SDK 6.1.1(24) and only uses ECMAScript built-ins, so earlier API levels should work as well.

## Install

Keep the module next to your project and reference it by path:

```json5
// entry/oh-package.json5
{
  "dependencies": {
    "@chinokoyuki/ics-parser": "file:../harmony-ics-parser/library"
  }
}
```

Then run `ohpm install` in the project root.

## Quick start

```ts
import { parseIcs } from '@chinokoyuki/ics-parser'

const events = parseIcs(icsText)
for (const event of events) {
  const start = event.dtStart
  if (start !== null) {
    console.info(`${event.summary}: ${start.date.toLocaleString()}`)
  }
}
```

Expanding a repeating event over a date range:

```ts
import { expandOccurrences } from '@chinokoyuki/ics-parser'

const rangeStart = new Date(2026, 8, 1)
const rangeEnd = new Date(2026, 9, 1)

for (const event of events) {
  const occurrences = expandOccurrences(event, rangeStart, rangeEnd)
  for (const occurrence of occurrences) {
    console.info(`${occurrence.start.toLocaleString()}  ${event.summary}`)
  }
}
```

`expandOccurrences` accepts an optional fourth argument that caps the result length. It defaults to 1000, which only matters for unbounded rules queried over a wide range.

## API

| Function | Returns | Purpose |
| --- | --- | --- |
| `parseIcs(text)` | `IcsEvent[]` | Parse a full calendar file. Malformed blocks are skipped, not fatal. |
| `expandOccurrences(event, rangeStart, rangeEnd, maxCount?)` | `IcsOccurrence[]` | Materialise every instance that overlaps `[rangeStart, rangeEnd)`. |
| `getEventDurationMs(event)` | `number` | Duration of one instance. All-day events default to one day. |
| `isRecurring(event)` | `boolean` | Whether the event carries an RRULE. |
| `parseIcsDateTime(value, params?)` | `IcsDateTime \| null` | Parse a single date or date-time value. |
| `parseRrule(value)` | `IcsRrule \| null` | Parse an RRULE value without expanding it. |
| `parseDurationToSeconds(value)` | `number` | Parse `P1D`, `PT1H30M`, `-PT15M` and similar. |
| `parseProperty(line)` | `IcsProperty` | Split a content line into name, parameters and value. |
| `unescapeText(text)` | `string` | Resolve RFC 5545 text escapes. |

### Event fields

`IcsEvent` mirrors the properties the parser understands: `uid`, `summary`, `description`, `location`, `dtStart`, `dtEnd`, `isAllDay`, `durationSeconds`, `rrule`, `exdates`, `alarms`, `categories`, `status`, `transp`, `priority`, `sequence`, `created`, `lastModified`, `recurrenceId` and `calName` (from `X-WR-CALNAME`).

## Dates and time zones

- Values ending in `Z` become real instants. `isUtc` is set on the parsed value.
- Values carrying `TZID` are read as local wall-clock time. The identifier is preserved in `tzid` and the original string in `raw`, so the caller can convert with its own time zone source.
- Resolving an IANA zone would require shipping a time zone database. That is a large dependency for a parser, so it is left to the caller.
- All-day values (`VALUE=DATE`) keep `isAllDay = true`. `DTEND` is exclusive, as RFC 5545 defines it. An all-day event without `DTEND` lasts one day.
- Recurrence arithmetic follows the event: UTC events are stepped in UTC fields, floating and `TZID` events in local fields.

## Recurrence coverage

| Rule part | Status |
| --- | --- |
| `FREQ` DAILY / WEEKLY / MONTHLY / YEARLY | Supported |
| `INTERVAL`, `COUNT`, `UNTIL` | Supported |
| `BYDAY`, including `2MO` and `-1FR` | Supported |
| `BYMONTHDAY`, `BYMONTH`, `WKST` | Supported |
| `EXDATE` | Supported |
| `BYSETPOS`, `BYWEEKNO`, `BYYEARDAY` | Not supported |
| `RDATE` | Not supported |

## Out of scope

- VTODO, VJOURNAL, VFREEBUSY and VTIMEZONE are skipped rather than rejected.
- ATTENDEE and ORGANIZER are ignored.
- `RECURRENCE-ID` is parsed onto the event, but expansion does not merge override instances.

## Project layout

```
harmony-ics-parser/
├── library/                       the module, and what ohpm publishes
│   ├── Index.ets                  public exports
│   └── src/main/ets/
│       ├── IcsTypes.ets           interfaces for events, alarms, rules
│       ├── IcsParser.ets          line handling and parsing
│       └── Recurrence.ets         RRULE expansion
├── library/src/test/              hypium tests
└── entry/                         sample app
```

## Sample app

`entry/` parses a calendar embedded in its source, expands the rules over a fixed August 2026 window and lists the occurrences. The window is fixed so the output does not depend on when the app runs.

```powershell
$env:DEVECO_SDK_HOME = "E:\DevEco Studio\sdk"
$env:PATH = "E:\DevEco Studio\jbr\bin;" + $env:PATH
& "E:\DevEco Studio\tools\ohpm\bin\ohpm.bat" install
& "E:\DevEco Studio\tools\hvigor\bin\hvigorw.bat" --no-daemon assembleHap --mode module -p product=default -p module=entry@default
```

The output is `entry/build/default/outputs/default/entry-default-unsigned.hap`.

### Build warnings

A build without a signing profile prints `No signingConfig found for product default`. That is expected. Add a signing profile in DevEco Studio if you want to install the HAP on a device.

hvigor may also print two notes about the local module: `Missing module info for local modules ...` and `The version number ... does not comply with the SemVer specification`. Both come from the ohpm package name not matching the module name. They do not change the output; `ets/modules.abc` in the HAP contains `expandOccurrences` and `parseIcsDateTime`.

## Tests

Tests live in `library/src/test` and use `@ohos/hypium`. Run them from the sample project, or from any stage-model project that references the module. Start the module's test task in DevEco Studio or through hvigor.

## License

Apache-2.0. See [LICENSE](LICENSE).
