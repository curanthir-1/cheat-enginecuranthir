# Using Cheat Engine from Claude Code or Claude Desktop (MCP)

The in-app chat (`Help -> Ask AI`) needs an API key or a local model. If you have a Claude subscription instead, you
can let **Claude Code** or the **Claude desktop app** drive Cheat Engine: they sign in with your subscription, and
Cheat Engine offers its AI tools to them through the Model Context Protocol (MCP). You chat in Claude, and Claude
calls the same 39 tools the in-app assistant uses (open a process, scan memory, disassemble, watchpoints, address
list, Lua, auto assembler, the skill guides).

```
Claude Code / Claude Desktop  <--MCP over stdio-->  ce-mcp.exe  <--named pipe-->  Cheat Engine
```

`ce-mcp.exe` is a small bridge in the Cheat Engine folder. The AI client starts it; it forwards messages to the MCP
server inside Cheat Engine (`Extensions/AITools/mcpserver.lua`). Usage counts against your subscription's normal
limits. No API key is involved and nothing is sent to anyone but the client you connect.

## 1. Enable the server in Cheat Engine

Start Cheat Engine and click `Help -> MCP server (Claude Code / Claude Desktop)`. Confirm the explanation once. The
menu item shows a check mark while the server is on, and the choice is remembered for the next start.

## 2a. Claude Code in WSL

WSL can start Windows programs, so Claude Code in WSL runs the Windows bridge directly. Use the `/mnt/c/...` path of
`ce-mcp.exe` (adjust it to where you unzipped Cheat Engine):

```bash
claude mcp add cheatengine -- "/mnt/c/Tools/CheatEngine/bin/ce-mcp.exe"
```

Start `claude`, run `/mcp` to check that `cheatengine` is connected, and ask for something, for example
"open the process Tutorial-x86_64.exe and tell me which modules it has loaded".

This needs WSL's Windows interop, which is on by default. If `"/mnt/c/Windows/System32/cmd.exe" /c ver` prints the
Windows version from your WSL shell, it works.

## 2b. Claude Code on Windows (PowerShell)

```bash
claude mcp add cheatengine -- "C:\Tools\CheatEngine\bin\ce-mcp.exe"
```

## 2c. Claude desktop app

Open `Settings -> Developer -> Edit Config` and add the server to `claude_desktop_config.json`, then restart the
app:

```json
{
  "mcpServers": {
    "cheatengine": {
      "command": "C:\\Tools\\CheatEngine\\bin\\ce-mcp.exe"
    }
  }
}
```

## Things to know

* **Start order.** Cheat Engine must be running with the server enabled when the client connects. If it was not,
  start it and reconnect (`/mcp` in Claude Code, restart for the desktop app). If Cheat Engine is restarted during a
  session, the bridge reconnects by itself on the next tool call.
* **One client at a time**, and one Cheat Engine instance (the first one that enables the server owns the pipe).
* **What Claude can do.** The tools include `executeLuaCode`, `writeAddress` and the auto assembler tools, so Claude
  can change the target process and run Lua inside Cheat Engine. Claude Code asks for permission before it uses a
  tool unless you allowed it; Cheat Engine itself does not ask again.
* **Who can connect.** While the server is enabled, any program running on your computer can connect to the pipe
  (network users are refused). Turn the server off in the menu when you are not using it.
* **Administrator.** Cheat Engine normally runs elevated. The pipe accepts connections from normal programs, the same
  way Cheat Engine's other helper pipes do, so the client does not need to be elevated. This was not verified on real
  Windows (see below).
* **Long operations.** A big memory scan blocks the tool call until it is done. If the client gives up on a slow
  call, raise its tool timeout (Claude Code: the `MCP_TOOL_TIMEOUT` environment variable, in milliseconds).
* **Troubleshooting.** The bridge writes diagnostics to stderr; `claude --debug` shows them. `ce-mcp.exe --wait 30`
  waits longer for Cheat Engine, and `--pipe <name>` uses another pipe name (change `MCP_PIPENAME` in
  `mcpserver.lua` to match).

## What was tested

Under Wine, with a scripted MCP client talking to `ce-mcp.exe` over stdio while the 64-bit Cheat Engine was running:
`initialize`, `ping`, `tools/list` (39 tools, all schemas valid), tool calls that succeed and that fail, an unknown
tool, an unknown method, a 300 KB request and a 300 KB response, a second client connecting after the first left,
turning the server off, and the error answers when Cheat Engine is not running.

**Not tested:** a real Claude Code or Claude desktop client, WSL, and real Windows (including the elevated Cheat
Engine / normal client combination). The protocol side follows the MCP specification (versions 2024-11-05,
2025-03-26 and 2025-06-18), but expect that a first run on your machine may turn up something to fix.

## Protocol notes (for developers)

* Pipe: `\\.\pipe\cheatengine-mcp`. Each message is a 4 byte little endian length followed by that many bytes of
  JSON (one JSON-RPC message). Cheat Engine answers every message with one message; length 0 means "no answer"
  (notifications).
* The server is stateless: it does not require `initialize` before other requests, which is what makes reconnecting
  after a Cheat Engine restart transparent.
* Tool results are returned as one text block containing the JSON the tool produced; `isError` is set when the tool
  raised an error or returned an `error` field.
* Only tools are offered (`resources/list` and `prompts/list` return empty lists). The skill guides are reachable
  through the `getSkill` tool and are summarized in the server instructions.
* Source: `Cheat Engine/mcpbridge/cemcp.lpr` (bridge) and `Cheat Engine/bin/Extensions/AITools/mcpserver.lua`.
