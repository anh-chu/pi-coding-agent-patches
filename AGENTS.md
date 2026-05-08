# pi-coding-agent-patches

Patches for the globally installed `@earendil-works/pi-coding-agent` npm package. Patches are applied directly to the installed files — there is no build step.

## Global install location

```
/home/sil/.local/share/fnm/node-versions/v24.14.1/installation/lib/node_modules/@earendil-works/pi-coding-agent/
```

The package bundles its own copy of `@earendil-works/pi-ai` and `@earendil-works/pi-agent-core` inside its `node_modules/`. Patches to those sub-packages target paths inside the bundle, not the top-level package.

## How to apply a patch

Apply from the `lib/` directory using `patch -p1`:

```bash
cd /home/sil/.local/share/fnm/node-versions/v24.14.1/installation/lib
patch -p1 < /home/sil/pi-extensions/pi-coding-agent-patches/patches/<patch-file>.patch
```

Always do a dry run first:

```bash
patch -p1 --dry-run < patches/<patch-file>.patch
```

## Current patches (applied to v0.74.0)

### Performance patches (`@mariozechner+pi-coding-agent+0.73.0.patch`)

Targets files in `node_modules/@earendil-works/pi-coding-agent/dist/`:

| File | Change |
|------|--------|
| `main.js` | Startup splash TUI; moved benchmark flag earlier |
| `core/session-manager.js` | `mapWithConcurrency` (64-wide pool); 4 KB cap on session preview text |
| `core/package-manager.js` | `resolve()` result cache keyed on settings hash; cleared on add/remove/update |
| `core/agent-session.js` | System prompt cache with stable key; invalidated on tool/resource changes |
| `core/extensions/loader.js` | Shared jiti singleton with `fsCache`; concurrency=2 for extension loading |
| `modes/interactive/interactive-mode.js` | Defer `renderInitialMessages` via `setTimeout(0)`; fire-and-forget provider count |
| `node_modules/.../pi-tui/dist/components/editor.js` | Layout/visual-line-map caches; tiered autocomplete debounce |

### Empty text content fix (`@earendil-works+pi-ai+openai-completions+empty-text.patch`)

Targets `node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/providers/openai-completions.js`.

Fixes `Invalid request: text content is empty` from strict providers (kimi-k2.6 via opencode-go) when interrupting an agent turn then sending a new message.

- Filter `{type:"text",text:""}` blocks from user messages (mirrors `anthropic.js` behavior)
- Skip user messages with empty string content
- Send `content:""` instead of `null` for assistant messages that have only tool calls — the opencode.ai proxy normalizes `null` to `[{type:"text",text:""}]` before forwarding to kimi

### Tool call ID normalization (`@earendil-works+pi-ai+anthropic+normalize-tool-id.patch`)

Targets `node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/providers/anthropic.js`.

Fixes `tool_use.id: String should match pattern '^[a-zA-Z0-9_-]+$'` when switching from a non-Anthropic model (e.g. kimi via opencode-go) to Claude mid-conversation.

- `normalizeToolCallId` now returns `"tool_call_0"` for empty/null input
- `block.id` always sanitized at the point of building `tool_use` blocks
- `toolCallId` always sanitized when building `tool_result` blocks

## Key architecture notes

- `opencode-go/kimi-k2.6` uses `api: "openai-completions"` — all requests go through `openai-completions.js`, not a kimi-specific file
- `transformMessages` in `transform-messages.js` handles cross-provider message replay (skips aborted turns, synthesizes missing tool results, normalizes IDs for cross-model). It is called inside each provider's `convertMessages`
- Tool call ID normalization in `anthropic.js` runs at two levels: `transformMessages` (cross-model detection) and now also at payload build time (safety net)
- Patches to pi-ai sub-package must target the NESTED path inside pi-coding-agent's own `node_modules`, not any global pi-ai install

### Extra-usage retry fix (`@earendil-works+pi-coding-agent+0.74.0+extra-usage-retry.patch`)

Targets `dist/core/agent-session.js`.

Fixes orchestrator going silent after subagent notifications hit the CC extra-usage cap. Pi's `_isRetryableError()` regex did not match `"You're out of extra usage..."`, so the error was classified as non-retryable. The failed turn was rewound, the notification was dropped, and the orchestrator waited indefinitely for user input.

Adds `extra.?usage` to the retryable pattern. The errors are transient (CC extra-usage pool recovers within minutes), so the existing exponential-backoff retry path handles them correctly.

### Duplicate user message fix (`@earendil-works+pi-coding-agent+issue-4197+dedup-next-turn.patch`)

Targets `node_modules/@earendil-works/pi-coding-agent/dist/core/agent-session.js`.

Fixes #4197: `pi -p "task"` (and subagent dispatch) sends two identical consecutive user messages to the LLM — one from `prompt()` and one from `_pendingNextTurnMessages` — wasting tokens and confusing the model.

**Root cause:** `custom`-role messages in `_pendingNextTurnMessages` become `role:"user"` after `convertToLlm`. When an extension echoes the user input into `_pendingNextTurnMessages` (via `sendCustomMessage` with `deliverAs:"nextTurn"`), the drain loop in `prompt()` pushes an identical second user message. Since custom messages convert to user messages in the API payload, the LLM sees the task twice.

**Fix:** When draining `_pendingNextTurnMessages`, skip any entry whose text content matches `expandedText` (the message already added as the user turn).

## Adding a new patch

1. Edit the installed file directly
2. Capture the diff as a `.patch` file in `./patches/`
3. Document it in `README.md` and in this file
4. Commit: `git add patches/ README.md AGENTS.md && git commit -m "fix(...): ..."`
