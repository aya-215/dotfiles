---
name: jar-class-inspect
description: Use when you need the exact signature (arguments, return type, overloads) of a class or method that exists only as a compiled .class inside a jar, with no source available — typically eBASE-Web's WEB-INF/lib jars on WSL. Triggers include "does class X have method Y", "what are the arguments of Foo.bar", "inspect the jar", "no .java source, only jar". Avoids leaving temp-file debris on /mnt/c or /mnt/d.
---

# jar-class-inspect

## Overview

eBASE-Web ships no `.java` source — only compiled classes inside the jars under `WEB-INF/lib`. To learn a class's real method signatures (args, return type, overloads), disassemble the class with the **Windows JDK `javap.exe`** from WSL.

**Core principle: pass the jar directly to `javap -classpath`. Never extract `.class` files to a temp dir.** Extraction onto `/mnt/c` or `/mnt/d` leaves debris that the delete-guard refuses to clean up. The jar-direct method has zero temp files.

## When to Use

- "Does `EbaseWeb.util.CsvReader` have a `getMapSetting` method? What are its args?"
- A JSP/PR review references a method and you must confirm it exists / its signature.
- `grep` over the repo finds no `.java` (source absent) — only `.class` in a jar.
- You need to distinguish overloads (e.g. `getMapSetting(String)` vs `getMapSetting(String, boolean)`).

**Not for:** searching JSP conventions, auto-include rules, or anything where the source IS present (just read it).

## Procedure

```bash
# 1. Find which jar contains the class (package path + .class, slashes not dots)
cd /mnt/d/tomcat/webapps/hankyu
for j in $(find WEB-INF/lib -name "*.jar"); do
  unzip -l "$j" 2>/dev/null | grep -q "EbaseWeb/util/CsvReader.class" && echo "$j"
done
# → WEB-INF/lib/eBDbpWebUtil.jar

# 2. Convert the jar path to a Windows path. Use wslpath -w — ONLY this.
JAR_WIN=$(wslpath -w "WEB-INF/lib/eBDbpWebUtil.jar")

# 3. Locate javap.exe: try the known path first, fall back to a scoped find.
JAVAP="/mnt/c/Program Files/Java/jdk1.8.0_144/bin/javap.exe"
[ -x "$JAVAP" ] || JAVAP=$(find "/mnt/c/Program Files/Java" -name javap.exe 2>/dev/null | head -1)

# 4. Disassemble. Pass the jar directly as classpath; use the fully-qualified
#    class name with DOTS (not slashes).
"$JAVAP" -classpath "$JAR_WIN" 'EbaseWeb.util.CsvReader'
# Add -s for raw bytecode descriptors, -p to include private members.
```

The output lists every method with full generic signatures, e.g.:

```
public static java.util.Map<java.lang.String, java.lang.String> getMapSetting(java.lang.String);
public static java.util.Map<java.lang.String, java.lang.String> getMapSetting(java.lang.String, boolean);
```

## Critical Notes

- **No temp files. No `.class` extraction.** The jar goes straight to `-classpath`. Do not copy classes to `/mnt/c` or `/mnt/d` — the delete-guard blocks cleanup and the debris stays forever.
- **Path conversion: `wslpath -w` only.** Hand-rolled `sed`/`tr` conversion mangles `\t` (tomcat) and `\l` (lib) into control chars. `wslpath -w` is the WSL-native, correct tool.
- **Display with `printf '%s'`, never `echo`.** `echo "$JAR_WIN"` renders `\t`/`\l` as garbage on screen even though the variable's real bytes are correct and `javap` receives them fine. Use `printf '%s\n' "$JAR_WIN"` to verify visually.
- **`strings` is NOT enough.** `strings CsvReader.class | grep getMapSetting` confirms the *name* exists but cannot give arg/return types or distinguish overloads. Always finish with `javap` for the real signature.
- **Class name uses dots, jar entry uses slashes.** `unzip -l` grep target is `EbaseWeb/util/CsvReader.class`; the `javap` argument is `EbaseWeb.util.CsvReader`.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Extracted `.class` to `/mnt/d/tmp_javap` then couldn't delete it | Pass the jar itself to `-classpath`; never extract |
| `sed 's#/#\\#g'` produced `D:\tomcat` → `D:<tab>omcat` | Use `wslpath -w "$jar"` |
| Concluded "method doesn't exist" after grepping `.java`/source | Source is absent in eBASE-Web; disassemble the jar instead |
| Stopped at `strings` output | `strings` gives names only — confirm signature with `javap` |
