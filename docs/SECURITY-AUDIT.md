# Network and malware audit

Done on the state of this branch after the MCP bridge was added. It answers two questions: does anything in this
project contact a server without being asked, and is there anything malware-like in it.

**Method.** Static inspection only: every URL and every use of a network API in the Pascal and Lua sources, every
caller of those, registry autostart / scheduled task / service creation, machine identifier collection, and the
import tables and embedded strings of every binary in the build. Nothing was run under a network monitor, and no
antivirus scan was run.

## Result

Nothing was found that contacts a server at startup or in the background, installs itself to start with Windows,
collects machine identifiers, or downloads and runs code on its own.

### Things that use the network, and when

| What | Trigger | Destination |
|---|---|---|
| AI chat (`Extensions/AITools`) | You send a message or open the model list | The provider endpoint you configured |
| MCP server | You enable it in the Help menu | Local named pipe only, no network |
| CEShare | Only after you set a server in `Settings -> CEShare` | That server; the server list comes from `cheatengine.org/cesharelist.txt` when you open that settings page |
| Windows symbols | You choose "download Windows symbols" (asks first) or a script calls `enableWindowsSymbols()` | `msdl.microsoft.com` |
| Java agent on Android targets | You use that feature and `jvmti.h` is missing | One header file from a GitHub mirror of OpenJDK |
| Network process / remote pointer scan (ceserver) | You connect to, or set up, a remote scanner | The host you enter; the pointer scanner listens on a port only when you start a distributed scan |
| Help, About, logo and tutorial links | You click them | Opens `cheatengine.org`, its forum, wiki or Patreon in your browser |
| Kernel driver error help | The driver fails to load (driver is not shipped) | Opens `cheatengine.org/dbkerror.php` in your browser |

### Removed earlier (see CHANGES.md)

The trainer ad window, the automatic version check, the CEShare first-run download, and the April Fools routine that
downloaded and ran a Lua script.

### Persistence and identifiers

* No `Run`/`RunOnce` registry entries, scheduled tasks or startup folder entries are created anywhere.
* Service creation exists only in the kernel driver loader (`dbk32/DBK32functions.pas`). The driver is not built or
  shipped, so that path fails with a "file not found" message.
* The only call that reads the computer name is the default node name in the distributed pointer scan dialog.

### Binaries

Built from source by `build/build.sh`: only `cheatengine-x86_64.exe` and `cheatengine-i386.exe` import network
libraries (`wininet`, `ws2_32`), for the features in the table above. The launcher, `ce-mcp.exe`, the tutorials and
all helper DLLs (speedhack, vehdebug, luaclient, allochook, winhook) import none.

Prebuilt files that were already in the upstream repository and are shipped as they are:

| Files | Network imports | Notes |
|---|---|---|
| Direct3D hooks (`d3dhook*`, `ced3d*hook*`), `lua53-*.dll`, `libipt-*`, `libmikmod*`, `CEJVMTI.dll` | none | Carry a code signature |
| `dbghelp.dll`, `symsrv.dll` | `symsrv.dll` imports `ws2_32` | Microsoft debugging tools; this is the symbol server client |
| `sqlite3.dll`, `lfs.dll`, `lua_extra/*.exe` | none | Unsigned |
| `tiny.dat`, `standalonephase1.dat` | none | 32-bit stubs the trainer generator uses for standalone trainers |

## What this audit does not prove

* The prebuilt files above were checked by their imports and embedded strings, not by reading their code, and the
  signatures were seen but not validated. They are the same files upstream ships.
* Static inspection can miss things. Running Cheat Engine behind a firewall that prompts per connection is the
  direct way to confirm the table above on your own machine.
* **Cheat tables and Lua scripts from other people are code.** A `.CT` file can contain Lua that does anything
  Cheat Engine can do, including network requests. Cheat Engine asks before running a table's Lua; read it first.

## Why browsers and antivirus flag the download

Memory scanners that inject DLLs into other processes, hook APIs, change the speed of a process and attach
debuggers do what a lot of malware does, so Cheat Engine as a family has been flagged for years (typically under
names like "HackTool" or "PUA"). This build is also unsigned and new, so it has no download reputation. A flag on
the zip is therefore expected and does not by itself say that anything is hidden in it; equally, this document is
not a guarantee. If you want certainty about what you run, build it yourself from this source (docs/BUILDING.md).
