# pi-coding-agent Patches

This repository stores patches for [@earendil-works/pi-coding-agent](https://www.npmjs.com/package/@earendil-works/pi-coding-agent) to address specific issues or add optimizations.

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

## Usage

To apply this patch to a consuming project:

1. Install patch-package if not already installed:
   ```bash
   npm install --save-dev patch-package
   ```

2. Copy the patch file to your project's `patches/` directory:
   ```bash
   cp patches/@mariozechner+pi-coding-agent+0.73.0.patch YOUR_PROJECT/patches/
   ```

3. Apply the patch:
   ```bash
   npx patch-package @earendil-works/pi-coding-agent
   ```

4. Add or update the postinstall script in your `package.json`:
   ```json
   {
     "scripts": {
       "postinstall": "patch-package"
     }
   }
   ```

This ensures the patch is automatically applied whenever dependencies are reinstalled.
