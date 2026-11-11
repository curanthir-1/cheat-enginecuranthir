# AI Tools extension

The fork ships the AI assistant extension from <https://github.com/cheat-engine/AITools> (MIT license) in
`Cheat Engine/bin/Extensions/AITools`, based on upstream commit `8c2c637` (2026-11-03). The upstream extension is
written for a newer, closed Cheat Engine than the public 7.5 source, so two things were needed: Cheat Engine had to
learn the API the extension uses ([CHANGES.md](CHANGES.md), section 4), and the extension itself had to be updated.

## Using it

1. Start Cheat Engine and open `Help -> Ask AI` (Ctrl+Alt+I).
2. Pick a provider, check the endpoint, and paste your API key. Local models (Ollama, LM Studio) need no key.
3. Pick a model from the list (it is fetched from the provider when you open the drop-down) and type your question.
   Ctrl+Enter sends.

Other entry points: right-click in the disassembler -> *Explain this function* / *Generate pseudocode for this
function*; right-click in a Lua engine or auto assembler window -> *Ask about this script*.

Chat commands: `/skills` lists the built-in skill guides, `/skill <name>` loads one, `/skill reload` rereads them.

| Provider | Default endpoint | Default model |
|---|---|---|
| Anthropic | `https://api.anthropic.com/v1/messages` | `claude-opus-5-5` |
| OpenAI | `https://api.openai.com/v1/chat/completions` | `gpt-4o` |
| DeepSeek | `https://api.deepseek.com/chat/completions` | `deepseek-chat` |
| Google Gemini | `https://generativelanguage.googleapis.com/v1beta` | `gemini-2.5-flash` |
| Local (Ollama) | `http://localhost:11434/v1/chat/completions` | `llama3.2` |
| Local (LM Studio) | `http://localhost:1234/v1/chat/completions` | `local-model` |
| Custom (OpenAI-compatible) | `http://localhost:8000/v1/chat/completions` | - |

### Privacy and safety

* Requests go **only** to the endpoint you configure. The cheatengine.org proxy and Patreon modes are removed.
* What is sent: your message, the conversation, the tool definitions, and the results of the tools the model calls
  (which can include memory contents, disassembly, module names and scripts from the process you have opened).
* The API key is stored in the Cheat Engine settings in the Windows registry (`HKCU\Software\Cheat Engine\AITOOLS`),
  unencrypted, as upstream does. Use a key you can revoke.
* The model can call `executeLuaCode`, `writeAddress` and the auto assembler tools: it can change the target process
  and run Lua inside Cheat Engine without asking first. Use it on things you are willing to have modified.

## What was changed in the extension

**Access modes**
* Removed the "Public CE API" and "Patreon CE API" modes (both sent your prompts through cheatengine.org) and the
  related consent dialog, limits lookup and session handling. The dialog only has the provider/endpoint/key row.
* Anthropic is the default provider on first use. The key field is masked.

**Anthropic (Claude) integration, rewritten for the current API**
* Models: `claude-opus-5-5` (default), `claude-fable-5-2`, `claude-sonnet-5-5`, `claude-haiku-5-5`; the list is
  fetched live from `/v1/models` when a key is entered.
* `max_tokens` raised from 4096 to 32000 (thinking counts towards it on current models).
* The assistant turn is sent back exactly as received, including `thinking` blocks and their signatures. Upstream
  dropped them, which current models reject or handle worse during tool use.
* One streaming parser handles text, tool input, thinking and signature deltas; non-streamed responses and error
  documents are handled too. Errors from the API are shown instead of producing an empty answer.
* Handles `stop_reason` `refusal` (shown to the user) and `max_tokens` (shown; an unfinished tool call is dropped).
* Tool results from failed tools are flagged `is_error`.
* On Anthropic's own endpoint, for the models that support it, the request opts into server-side refusal fallbacks
  (`fallbacks: "default"`, beta header `server-side-fallback-2026-07-01`). If the endpoint rejects that option the
  request is retried once without it.

**Tool fixes** (bugs in upstream, found by running every tool against a live process)
* `getModuleSections` was registered with the wrong function and returned its result without a key.
* `required` lists of five tools used bare identifiers (`{script}`), which made every parameter optional.
* `executeLuaCode` crashed when the script printed something; `getDetailedWatchpointData` called a missing `format`.
* `refineScan` set properties that do not exist (`ms.value`); alignment was written to a global variable.
* `setLuaEngineScript` used an undefined variable and never changed the script; `getLuaEngineScript` read the wrong
  window. `showAutoAssemblerScript` returned no window ID, so `get/setAutoAssemblerScript` could not be used on it.
* `getAddressList`, `getVersionStrings` and the documentation keyword search (case sensitivity, result size) rewritten.
* Disassembly tools no longer depend on the `prefix` field and cannot loop forever on unreadable memory.
* Watchpoints are set and removed on the main thread.
* "Explain this function" works without the built-in `disassembleSelectedFunction` of newer Cheat Engine versions.

## How it was tested

Under Wine 9 with the 64-bit build, using the Cheat Engine tutorial as the target process:

* All 39 tools (38 tools plus `getSkill`) were called with real arguments: process and module information, sections,
  disassembly, function ranges, memory and string reads, first and next scans, address list create/edit/delete, Lua
  execution, documentation lookup, auto assembler syntax check, script windows, memory writes, and a full watchpoint
  cycle (start, hits with registers, stack trace and function range, stop, delete).
* A complete chat was run through the dialog against a local mock of the Anthropic API: streaming text, a thinking
  block, two tool calls in one turn, tool results, and the follow-up answer. The requests the mock received were
  checked (headers, body, echoed thinking block, `is_error`).

Not tested: the live Anthropic/OpenAI/Gemini services (no key available), the OpenAI and Gemini code paths beyond
loading, and anything on real Windows.

## Updating from upstream later

Upstream can be dropped in over the folder, but the fixes above would be lost and the hosted modes would come back
(they will fail here: `getCEPatreonSessionID` does not exist in this build). Diff against upstream commit `8c2c637`
to see exactly what this fork changed.
