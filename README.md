# pi-coding-agent Patches

Patches for the globally installed [@earendil-works/pi-coding-agent](https://www.npmjs.com/package/@earendil-works/pi-coding-agent). Applied directly to installed files — no build step, no project dependency.

## Quick start

Clone and apply all patches in one go:

```bash
git clone https://github.com/anh-chu/pi-coding-agent-patches
cd pi-coding-agent-patches
bash apply-all.sh
```

Or apply a single patch manually:

```bash
# npm root -g returns .../lib/node_modules; patches reference node_modules/...
# so use the parent directory as the working directory for patch -p1.
PI_ROOT=$(dirname $(npm root -g))

# Dry-run first
patch -p1 --dry-run -d "$PI_ROOT" < patches/<patch-name>.patch

# Apply
patch -p1 -d "$PI_ROOT" < patches/<patch-name>.patch
```

> If you use **fnm** or **nvm**, make sure the right Node version is active before running `npm root -g` so it resolves to the version where pi is installed.

## Patches

### @earendil-works+pi-ai+anthropic+normalize-tool-id.patch

**Purpose:** Fix `tool_use.id: String should match pattern '^[a-zA-Z0-9_-]+$'` when switching from a non-Anthropic model (e.g. kimi via opencode-go) to Claude mid-conversation.

**Changes (in `anthropic.js`):**

- `normalizeToolCallId` now handles empty/null input (returns `"tool_call_0"` fallback) and guards against all-invalid-char IDs
- `tool_use.id` in assistant message blocks is now always passed through `normalizeToolCallId` at formatting time
- `tool_use_id` in all tool result blocks is also sanitized at formatting time

**Why:** `transformMessages` normalizes tool call IDs for cross-provider replays, but normalization was only applied when `!isSameModel` and the function was only called indirectly. If the stored ID was empty (aborted stream) or contained chars outside `[a-zA-Z0-9_-]`, Anthropic rejected the request. Applying normalization at the point where the API payload is built ensures Anthropic always receives valid IDs regardless of source.

### @earendil-works+pi-ai+openai-completions+empty-text.patch

**Purpose:** Fix "Invalid request: text content is empty" from strict providers (Kimi k2.6 via opencode-go) when interrupting agent work mid-turn.

**Changes (in `openai-completions.js`):**

- Filter empty text blocks from user messages with array content (mirrors existing `anthropic.js` behavior)
- Skip user messages with empty string content
- When an assistant message has `content: null` combined with `tool_calls`, send `content: ""` instead — the opencode.ai proxy normalizes `null` to `[{type:"text",text:""}]` before forwarding to Kimi, which rejects the empty text block

**Root cause:** Two paths produce empty text content in the request history:

1. Any custom/extension message with empty string content reaches kimi as `{type:"text",text:""}`
2. Tool-only assistant turns (model responds immediately with tool calls, no preamble text) have `content: null`; the opencode.ai proxy normalizes this to `[{"type":"text","text":""}]` before sending to kimi

The second path explains why the error specifically appears after interrupting mid-turn: the interrupt exposes the raw tool-only assistant turn in message history on the next send, whereas a completed turn would normally be followed by tool results and another assistant message.

### @earendil-works+pi-coding-agent+0.73.0.patch (filename kept for patch-package compat)

**Purpose:** Performance optimizations for startup, session loading, and editor rendering.

**Changes:**

- Introduces `mapWithConcurrency()` utility function to process arrays with a concurrency limit while preserving order
- Optimizes `buildSessionInfo()` to avoid unbounded string arrays when collecting message previews; now caps preview text at 4KB
- Updates two session loading methods to use the new concurrent processing utility with a concurrency limit of 8
- Adds resolve caching in DefaultPackageManager to avoid rescanning skills/prompts/themes/extensions on repeated calls
- Defers interactive startup provider-count updates so the UI can paint sooner without blocking on footer metadata
- Defers initial message rendering to next tick, allowing UI to paint before loading chat history
- Caches editor layout and visual line maps to reduce cursor-move and redraw cost
- Invalidates editor layout cache on cursor-only movement so arrow-key navigation updates the visible cursor
- Caches the system prompt in AgentSession to avoid re-merging skills/tools/context on every send
- Tiered autocomplete debounce: 0ms for Tab/first-trigger chars, 150ms for mid-word typing
- Loads extensions with a low concurrency cap tuned for cached jiti imports, avoiding CPU and filesystem cache contention
- Reuses one cached jiti importer for extension loading to avoid repeated importer setup and module parsing
- Stores jiti transform cache under `~/.pi/agent/cache/jiti` so repeated starts reuse compiled extension code
- Uses bundled virtual modules for extension imports in Node.js, fixing missing peer imports and avoiding slow failed resolution
- Shows a minimal startup splash TUI before runtime/resource loading so the terminal responds immediately

**Why:** Improves startup performance and memory efficiency when loading sessions with many messages, preventing excessive memory accumulation and UI blocking during startup.

### @earendil-works+pi-coding-agent+0.74.0+extra-usage-retry.patch

**Purpose:** Fix orchestrator going silent after subagent notifications when the CC extra-usage cap is hit.

**Changes (in `agent-session.js`):**

- Adds `extra.?usage` to the `_isRetryableError()` regex

**Root cause:** When parallel subagents complete and inject notifications back into the orchestrator session, the triggered LLM turn can hit Anthropic's transient CC extra-usage cap. Pi's retryable error regex did not match `"You're out of extra usage..."`, so the error was classified as permanent. The failed turn was rewound, the notification was dropped, and the orchestrator waited indefinitely for user input. The errors are transient (the extra-usage pool recovers within minutes), so adding the pattern lets the existing exponential-backoff retry path handle them without any user intervention.

### @earendil-works+pi-ai+anthropic+orphaned-tool-use-repair.patch

**Purpose:** Fix recurring `400 invalid_request_error: tool_use ids were found without tool_result blocks immediately after` in long conversations.

**Changes (in `anthropic.js`):**

- Adds a final repair pass inside `convertMessages()` that runs after the main message loop and before `cache_control` processing
- The pass scans the final `params` array for every assistant message with `tool_use` blocks, checks which IDs are not covered by the immediately following user message, and injects synthetic `tool_result` entries for the orphans
- Orphaned results are prepended into the existing next user message if it has array content, or inserted as a standalone user message otherwise

**Root cause:** `transformMessages` inserts synthetic `tool_result` messages for orphaned tool calls via a `pendingToolCalls` tracker — but it has gaps. Aborted assistant messages are skipped (via `continue`) after `insertSyntheticToolResults()` runs but before their tool calls update `pendingToolCalls`, so an aborted message's own tool calls are never tracked. Cross-model ID normalization collisions can also leave IDs uncovered. Any of these gaps produce an assistant message in the converted `params` with a `tool_use` block and no following `tool_result`, which Anthropic rejects with a 400. The fix is a deterministic last-resort guard: it cannot be defeated by any earlier logic failure because it operates directly on the final API payload.

**Why sessions get stuck:** When the 400 hits, the failing turn is rewound. On retry, the same broken history is replayed, hitting the same 400 again. The session loops indefinitely (or the agent silently freezes) with no way to proceed.

### @earendil-works+pi-ai+json-parse+control-char-repair.patch

**Purpose:** Fix `Bad control character in string literal in JSON` crashing the SSE stream and triggering the `tool_use` without `tool_result` 400 loop.

**Changes (in `utils/json-parse.js`):**

- The existing `repairJson` fallback in `parseJsonWithRepair` is now wrapped in `try/catch` so a failed repair attempt doesn't immediately throw
- Adds a second fallback: brute-force regex replace of all bare control chars (`\x00-\x08`, `\x0b`, `\x0c`, `\x0e-\x1f`) with their `\uXXXX` Unicode escapes, then retries `JSON.parse`
- Only rethrows the original error if all three attempts fail

**Root cause:** The Anthropic SSE stream delivers tool call arguments as `partial_json` deltas. When the model generates code containing ANSI escape sequences or other control chars (e.g. `\x1b[0m` in `edit.newText`), the raw SSE data line contains a literal control character inside a JSON string. `parseJsonWithRepair` is called on the full SSE event JSON. The first fallback, `repairJson`, correctly tracks string boundaries and escapes control chars — but its tracking breaks when the JSON value also contains unescaped inner quotes (e.g. Go or TypeScript string literals in `newText`). When tracking exits the string early at an unescaped quote, the control char is seen as outside a string and passes through unchanged. `JSON.parse` fails, `repairJson` produces an identical string, so `parseJsonWithRepair` rethrows. The error propagates out of the streaming loop, the assistant message is stored with `stopReason: "error"` and the tool call has `arguments: {}`. On the next turn, the 400 loop starts.

## Notes

- Patches target the **global install** of `@earendil-works/pi-coding-agent`, not a project `node_modules`.
- Patches to `pi-ai` target the copy bundled _inside_ pi at `node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/`.
- After a `pi update --self`, re-run `apply-all.sh` — the update replaces the installed files.
- Tested on v0.77.0. On other versions do a dry-run first to check for offsets.
