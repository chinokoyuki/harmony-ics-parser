# IcsDemo

A minimal stage-model app that uses `@chinokoyuki/ics-parser`. It parses a calendar embedded in the source, expands the rules over August 2026 and lists the resulting occurrences.

The date window is fixed so the output stays the same no matter when the app runs.

## Open the project

Open `examples/IcsDemo` in DevEco Studio 6.0 or later. The module depends on the library through a path dependency:

```json5
// entry/oh-package.json5
"@chinokoyuki/ics-parser": "file:../../.."
```

DevEco Studio resolves and builds the library automatically.

## Build from the command line

```powershell
cd examples/IcsDemo
$env:DEVECO_SDK_HOME = "E:\DevEco Studio\sdk"
$env:PATH = "E:\DevEco Studio\jbr\bin;" + $env:PATH
& "E:\DevEco Studio\tools\ohpm\bin\ohpm.bat" install
& "E:\DevEco Studio\tools\hvigor\bin\hvigorw.bat" --no-daemon assembleHap --mode module -p product=default -p module=entry@default
```

The output is `entry/build/default/outputs/default/entry-default-unsigned.hap`.

The product has no signing configuration, so the build prints `No signingConfig found for product default`. That is expected. Add a signing profile in DevEco Studio if you want to install the HAP on a device.

## Expected warnings

hvigor prints two warnings about the local library:

```
Missing module info for local modules '@chinokoyuki/ics-parser'
D:\harmony-ics-parser\src\main\module.json does not exist. This library will not be merged.
```

Both come from the library living outside the demo project. The library still compiles into the HAP; you can confirm by opening `ets/modules.abc` in the package and looking for `parseIcs`. If you want a warning-free build, publish the library to a registry and depend on the version instead of the path.

## Where to look

| File | Content |
| --- | --- |
| `entry/src/main/ets/pages/Index.ets` | Parsing, expansion and the list UI |
| `entry/src/main/ets/entryability/EntryAbility.ets` | Standard entry ability |
| `entry/src/main/resources` | Strings, colours, icon |
