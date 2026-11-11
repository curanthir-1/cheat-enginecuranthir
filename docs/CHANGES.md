# Changes in this fork

This fork starts from the last public Cheat Engine source (`cheat-engine/cheat-engine` master, the 7.5 code base,
commit `ec45d5f`). Everything below was changed on top of that. The changes were written by Claude (Anthropic's AI
model) using Claude Code.

## 1. Advertising, update nagging and unprompted network traffic removed

The open source code never contained the installer bundleware (that lives in the official installer, which this fork
does not use). It did contain a few things that contact a server or show ads. These are gone or opt-in now:

| What | Where | Change |
|---|---|---|
| Ad window for trainers (`supportCheatEngine`, loaded `cheatengine.org/ceads.php` in an embedded Internet Explorer) | `cesupport.pas`, `LuaHandler.pas`, `trainergenerator.pas/.lfm` | The window never creates a browser and never loads anything. `supportCheatEngine()` is still accepted by old trainer scripts but does nothing. The trainer generator no longer writes the call and its checkbox is disabled. |
| Automatic version check (`cheatengine.org/latestversion.txt`, then sends you to the official download) | `bin/autorun/versioncheck.lua` | Deleted. |
| CEShare first-run dialog, which downloaded a server list from cheatengine.org at startup | `bin/autorun/ceshare.lua` | No request and no dialog at startup. CEShare stays off until you choose a server in `Settings -> CEShare`. |
| April Fools "cheat-e-coins": downloaded a Lua script from cheatengine.org and ran it | `MainUnit.pas`, `frmmicrotransactionsunit.pas` | Disabled; the download-and-run code is removed. |
| AppVeyor config that enabled RDP on build workers and pulled installers from Dropbox | `appveyor.yml` | Deleted, replaced by a GitHub Actions workflow. |

What still talks to the network, only when you use it: CEShare (after you configure it), the Windows symbol server
options, links in the Help/About menus, Lua scripts you run, and the AI tools (to the provider you configure).

## 2. Builds with current tools

* Compiles with **Lazarus 3.0 / FPC 3.2.2** (the upstream instructions need Lazarus 2.2.2):
  `ExtractFileNameWithoutExt` now comes from `LazFileUtils` everywhere, and the virtual tree registration no longer
  depends on a `laztrunk` define.
* **Cross-builds from Linux** to Windows, 64-bit and 32-bit, with one script. See [BUILDING.md](BUILDING.md).
* GitHub Actions workflow (`.github/workflows/build.yml`) that builds everything and uploads a zip.

## 3. Bugs fixed

* `autorun/custom/*.lua` was loaded from the wrong folder (the loader always used the `autorun` path).
* `TCEForm.LoadFromFileLFM` crashed on a form that had no saved design yet.
* `debug_setBreakpoint` swallowed every error and returned nothing; it now reports success or the error.

## 4. New Lua API (needed by current extensions)

Documented at the end of `Cheat Engine/bin/celua.txt`.

* **Extensions folder** with `loadorder.txt` support, and `getCurrentScriptPath()`.
* `getSystemArchitecture()`, `dirExists()` / `directoryExists()`.
* `Internet` objects: `Header` is honoured by `postURL` (JSON APIs work), and `OnReceiveData` streams the response.
* `createFormFromFile` loads Lazarus `.LFM` forms and skips properties it does not know.
* `TMarkdownViewer` control (plain text stand-in) and the SynEdit gutter part classes are registered for form loading.
* `enumModules()` entries have `Size`.
* `debug_setBreakpoint` returns `true, id`; new `debug_removeBreakpointByID(id)`.
* `MemScan`: `FoundCount`, `ErrorString`, `getFoundCount()`; `waitTillDone()` returns `true`.
* Lua modules `json` and `forEachForm` (`bin/json.lua`, `bin/forEachForm.lua`).
* `bin/autorun/apicompat.lua`: `getFunctionRange`, `enumSectionsOfModule`, `debug_getCurrentContextTable`,
  `debug_stacktrace`, `tostringx`.

## 5. AI Tools extension included and updated

`Cheat Engine/bin/Extensions/AITools`. See [AITOOLS.md](AITOOLS.md).

## 6. MCP bridge

`ce-mcp.exe` plus `Extensions/AITools/mcpserver.lua` expose the AI tools over the Model Context Protocol, so Claude
Code or the Claude desktop app (signed in with a subscription) can drive Cheat Engine. Off by default; enabled from
`Help -> MCP server`. See [MCP.md](MCP.md).

While building it, a bug in Cheat Engine's pipe code was found and fixed: `TPipeConnection.ReadBytes` and
`WriteBytes` asked for the full size again after a partial read or write, which overran the buffer and hung on
messages larger than the pipe buffer (`luapipe.pas`).

## Known limitations

* **Components that need Visual Studio are not built.** The zip contains what the Lazarus projects produce plus the
  prebuilt files that were already in the repository (Direct3D hooks, Lua, libipt, libmikmod, dbghelp). Not included:
  the kernel driver (DBK), DBVM, the tiny C compiler DLLs (`{$C}` / `{$CCODE}` blocks), the Mono and .NET data
  collectors, the Java agent and the C# compiler helper. Features that depend on those report that the file is missing.
* **The executables are not code signed.** Windows SmartScreen and antivirus products may warn about them, as they do
  for most unsigned memory editing tools.
* **Tested under Wine, not on a real Windows machine.** Start-up, the UI, opening a process, scanning, the address
  list, the Lua engine, the auto assembler, the debugger (watchpoints) and the AI extension were exercised with the
  64-bit build under Wine 9. The 32-bit build compiles but was not run.
* The markdown viewer shows the raw markdown text; it does not render formatting.
* The AI integration was tested against a local mock of the Anthropic API, not against the live services (no API key
  was available during development). The MCP bridge was tested with a scripted client, not with a real Claude client.
