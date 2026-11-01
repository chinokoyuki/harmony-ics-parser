# harmony-ics-parser

用 ArkTS 编写的 iCalendar（RFC 5545）解析与重复规则展开库，面向 HarmonyOS。

输入一段 `.ics` 文本，得到结构化的事件；再指定一个时间区间，就能拿到这个事件落在区间内的所有实例。

[English](README.md)

## 功能

- 解析 VCALENDAR、VEVENT、VALARM，处理折行、文本转义与带引号的参数
- 支持 DATE、DATE-TIME、UTC（`Z`）、`TZID` 与浮动时间
- 支持用 `DURATION` 代替 `DTEND`
- 展开 DAILY、WEEKLY、MONTHLY、YEARLY 重复规则，覆盖 `INTERVAL`、`COUNT`、`UNTIL`、`BYDAY`（含序号写法）、`BYMONTHDAY`、`BYMONTH`、`WKST`
- 支持 `EXDATE` 排除
- 无运行时依赖，无 native 代码，除 ECMAScript 内置对象外不调用系统 API

## 环境要求

Stage 模型，ArkTS。模块的目标 SDK 为 6.1.1(24)，实现只用到 ECMAScript 内置对象，更低的 API 版本一般也能用。

## 安装

把模块放在工程旁边，用路径引用：

```json5
// entry/oh-package.json5
{
  "dependencies": {
    "@chinokoyuki/ics-parser": "file:../harmony-ics-parser/library"
  }
}
```

然后在工程根目录执行 `ohpm install`。

## 快速上手

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

展开某个时间段内的重复事件：

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

`expandOccurrences` 的第四个参数用于限制返回数量，默认 1000。只有在查询范围很大、规则又没有结束条件时才会碰到这个上限。

## API

| 函数 | 返回 | 说明 |
| --- | --- | --- |
| `parseIcs(text)` | `IcsEvent[]` | 解析整个日历文件。单个块解析失败会被跳过，不影响其余内容。 |
| `expandOccurrences(event, rangeStart, rangeEnd, maxCount?)` | `IcsOccurrence[]` | 展开与 `[rangeStart, rangeEnd)` 有交集的所有实例。 |
| `getEventDurationMs(event)` | `number` | 单个实例的时长。全天事件默认一天。 |
| `isRecurring(event)` | `boolean` | 是否带 RRULE。 |
| `parseIcsDateTime(value, params?)` | `IcsDateTime \| null` | 解析单个日期或日期时间值。 |
| `parseRrule(value)` | `IcsRrule \| null` | 只解析 RRULE，不展开。 |
| `parseDurationToSeconds(value)` | `number` | 解析 `P1D`、`PT1H30M`、`-PT15M` 这类时长。 |
| `parseProperty(line)` | `IcsProperty` | 把一行内容拆成名称、参数和值。 |
| `unescapeText(text)` | `string` | 还原 RFC 5545 的文本转义。 |

### 事件字段

`IcsEvent` 覆盖解析器认识的全部属性：`uid`、`summary`、`description`、`location`、`dtStart`、`dtEnd`、`isAllDay`、`durationSeconds`、`rrule`、`exdates`、`alarms`、`categories`、`status`、`transp`、`priority`、`sequence`、`created`、`lastModified`、`recurrenceId`，以及来自 `X-WR-CALNAME` 的 `calName`。

## 日期与时区

- 以 `Z` 结尾的值会转换成真实时刻，解析结果里 `isUtc` 为 true。
- 带 `TZID` 的值按本地墙上时间读取。时区标识保留在 `tzid`，原始字符串保留在 `raw`，调用方可以自行换算。
- 要解析 IANA 时区，需要附带一份时区数据库。对一个解析器来说这是很重的依赖，因此留给调用方处理。
- 全天值（`VALUE=DATE`）的 `isAllDay` 为 true。按 RFC 5545 的定义，`DTEND` 不包含在区间内。没有 `DTEND` 的全天事件持续一天。
- 展开重复规则时沿用事件本身的时间基准：UTC 事件按 UTC 字段步进，浮动时间和 `TZID` 事件按本地字段步进。

## 重复规则支持

| 规则部分 | 状态 |
| --- | --- |
| `FREQ` DAILY / WEEKLY / MONTHLY / YEARLY | 支持 |
| `INTERVAL`、`COUNT`、`UNTIL` | 支持 |
| `BYDAY`，含 `2MO`、`-1FR` | 支持 |
| `BYMONTHDAY`、`BYMONTH`、`WKST` | 支持 |
| `EXDATE` | 支持 |
| `BYSETPOS`、`BYWEEKNO`、`BYYEARDAY` | 不支持 |
| `RDATE` | 不支持 |

## 不在处理范围

- VTODO、VJOURNAL、VFREEBUSY、VTIMEZONE 会被跳过，不报错。
- ATTENDEE、ORGANIZER 不做解析。
- `RECURRENCE-ID` 会记录到事件上，但展开时不会合并例外实例。

## 目录结构

```
harmony-ics-parser/
├── library/                       库本体，也是 ohpm 发布的内容
│   ├── Index.ets                  对外导出
│   └── src/main/ets/
│       ├── IcsTypes.ets           事件、提醒、规则的接口定义
│       ├── IcsParser.ets          行处理与解析
│       └── Recurrence.ets         RRULE 展开
├── library/src/test/              hypium 测试
└── entry/                         示例工程
```

## 示例工程

`entry/` 解析一段写在源码里的日历，按固定的 2026 年 8 月区间展开并列出结果。区间写死，输出不随运行时间变化。

```powershell
$env:DEVECO_SDK_HOME = "E:\DevEco Studio\sdk"
$env:PATH = "E:\DevEco Studio\jbr\bin;" + $env:PATH
& "E:\DevEco Studio\tools\ohpm\bin\ohpm.bat" install
& "E:\DevEco Studio\tools\hvigor\bin\hvigorw.bat" --no-daemon assembleHap --mode module -p product=default -p module=entry@default
```

产物在 `entry/build/default/outputs/default/entry-default-unsigned.hap`。

### 构建时的警告

没配签名时会打印 `No signingConfig found for product default`，这是正常的。要在 DevEco Studio 里配一份签名才能装到设备上。

hvigor 还可能多打印两条本地模块的提示：`Missing module info for local modules ...` 和 `The version number ... does not comply with the SemVer specification`。原因是 ohpm 包名和模块名对不上。不影响产物，HAP 里的 `ets/modules.abc` 能找到 `expandOccurrences` 和 `parseIcsDateTime`。

## 测试

测试位于 `library/src/test`，使用 `@ohos/hypium`。在示例工程里跑，或放进任何引用了本模块的 Stage 工程。通过 DevEco Studio 的测试任务或 hvigor 启动。

## 许可证

Apache-2.0，见 [LICENSE](LICENSE)。
