# AI Tools extension

Adds an AI assistant to Cheat Engine: `Help -> Ask AI` (Ctrl+Alt+I), "Explain this function" / "Generate pseudocode" in
the memory view, and "Ask about this script" in the Lua engine and auto assembler windows. The assistant can use Cheat
Engine itself through tools (scan memory, set watchpoints, disassemble, create address list entries, run Lua, ...).

Based on <https://github.com/cheat-engine/AITools> (commit 8c2c637, MIT license, (c) 2026 Dark Byte), modified for the
community build. The full list of changes and the usage guide are in `docs/AITOOLS.md` of the repository.

You need your own API key (Anthropic, OpenAI, DeepSeek, Google Gemini) or a local model (Ollama, LM Studio, any
OpenAI compatible server). Nothing is sent anywhere except to the provider you configure.

With a Claude subscription instead of an API key, Claude Code or the Claude desktop app can use the same tools
through the MCP server (`mcpserver.lua` + `ce-mcp.exe`). See `docs/MCP.md`.
