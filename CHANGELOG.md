# Changelog

## 0.1.0 - 2026-11-01

First release.

- Parse VCALENDAR, VEVENT and VALARM into typed objects
- Handle line unfolding, text escapes and quoted parameters
- Read DATE, DATE-TIME, UTC, `TZID` and floating time values
- Expand DAILY, WEEKLY, MONTHLY and YEARLY rules with `INTERVAL`, `COUNT`, `UNTIL`, `BYDAY`, `BYMONTHDAY`, `BYMONTH` and `WKST`
- Filter occurrences listed in `EXDATE`
- Derive `DTEND` from `DURATION`
