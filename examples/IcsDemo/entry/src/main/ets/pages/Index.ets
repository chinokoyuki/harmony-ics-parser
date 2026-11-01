import { expandOccurrences, IcsEvent, IcsOccurrence, parseIcs } from '@chinokoyuki/ics-parser';

/**
 * A small calendar kept in the source so the demo runs without file access.
 * It shows a weekly rule with an excluded date, an all-day event and a
 * monthly rule that picks the second Monday.
 */
const SAMPLE_ICS: string = [
  'BEGIN:VCALENDAR',
  'VERSION:2.0',
  'PRODID:-//harmony-ics-parser//demo//EN',
  'X-WR-CALNAME:Demo calendar',
  'BEGIN:VEVENT',
  'UID:weekly-1@demo',
  'DTSTART:20260803T190000',
  'DTEND:20260803T203000',
  'RRULE:FREQ=WEEKLY;BYDAY=MO,WE;COUNT=6',
  'EXDATE:20260805T190000',
  'SUMMARY:Evening class',
  'LOCATION:Room 302',
  'END:VEVENT',
  'BEGIN:VEVENT',
  'UID:all-day-1@demo',
  'DTSTART;VALUE=DATE:20260815',
  'SUMMARY:Project deadline',
  'END:VEVENT',
  'BEGIN:VEVENT',
  'UID:monthly-1@demo',
  'DTSTART:20260810T140000',
  'DTEND:20260810T150000',
  'RRULE:FREQ=MONTHLY;BYDAY=2MO;COUNT=3',
  'SUMMARY:Club meeting',
  'LOCATION:Room 105',
  'END:VEVENT',
  'END:VCALENDAR'
].join('\r\n');

interface DemoRow {
  title: string;
  detail: string;
  time: number;
}

function pad(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

function formatDay(date: Date): string {
  return `${date.getMonth() + 1}/${date.getDate()}`;
}

function formatTime(date: Date): string {
  return `${formatDay(date)} ${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

@Entry
@Component
struct Index {
  @State rows: DemoRow[] = [];

  aboutToAppear(): void {
    const events: IcsEvent[] = parseIcs(SAMPLE_ICS);
    const rangeStart: Date = new Date(2026, 7, 1);
    const rangeEnd: Date = new Date(2026, 8, 1);
    const collected: DemoRow[] = [];

    for (let i = 0; i < events.length; i++) {
      const event: IcsEvent = events[i];
      const occurrences: IcsOccurrence[] = expandOccurrences(event, rangeStart, rangeEnd);
      for (let j = 0; j < occurrences.length; j++) {
        const occurrence: IcsOccurrence = occurrences[j];
        const row: DemoRow = {
          title: event.summary,
          detail: event.isAllDay ? 'All day' : event.location,
          time: occurrence.start.getTime()
        };
        collected.push(row);
      }
    }

    collected.sort((a: DemoRow, b: DemoRow): number => a.time - b.time);
    this.rows = collected;
  }

  build() {
    Column({ space: 6 }) {
      Text('harmony-ics-parser')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .width('100%');
      Text(`${this.rows.length} occurrences between Aug 1 and Sep 1, 2026`)
        .fontSize(12)
        .fontColor('#6B6B6B')
        .width('100%')
        .margin({ bottom: 10 });

      List({ space: 4 }) {
        ForEach(this.rows, (row: DemoRow) => {
          ListItem() {
            Row({ space: 12 }) {
              Text(formatTime(new Date(row.time)))
                .fontSize(12)
                .fontColor('#6B6B6B')
                .width(92);
              Column({ space: 2 }) {
                Text(row.title).fontSize(16);
                Text(row.detail).fontSize(12).fontColor('#6B6B6B');
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1);
            }
            .width('100%')
            .padding({ top: 8, bottom: 8 });
          }
        }, (row: DemoRow, index: number): string => `${index}-${row.time}`);
      }
      .layoutWeight(1)
      .width('100%');
    }
    .padding(20)
    .width('100%')
    .height('100%');
  }
}
