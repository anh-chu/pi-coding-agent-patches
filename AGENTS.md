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

## Current patches (applied to v0.80.10)

> `apply-all.sh` `TARGET_VERSION` is `0.80.10`. All 7 patches apply cleanly to 0.80.10 (some hunks land with line offsets, which `patch` handles). v0.80.3 restructured the bundled pi-ai: Anthropic message-building moved from `providers/anthropic.js` to `api/anthropic-messages.js`, `openai-completions.js` moved to `api/`, and retry classification moved from `agent-session.js` into pi-ai `utils/retry.js`. v0.80.10 further split Anthropic tool_result building into `convertToolResult`, so `normalize-tool-id` was rebased (see its section). Apply order matters (see `apply-all.sh`): `dedup-next-turn` before the perf patch, `normalize-tool-id` before `orphaned-tool-use-repair`.

### Performance patches (`@mariozechner+pi-coding-agent+0.80.3.patch`)

Rebased onto v0.80.3. Targets files in
`node_modules/@earendil-works/pi-coding-agent/dist/`:

| File                        | Change                                                                          |
| --------------------------- | ------------------------------------------------------------------------------- |
| `main.js`                   | Startup splash TUI ("Starting Pi…") shown while the runtime/extensions load     |
| `core/session-manager.js`   | 4 KB cap on session preview text (`MAX_PREVIEW`)                                |
| `core/package-manager.js`   | `resolve()` result cache keyed on settings hash; cleared on add/remove/update   |
| `core/agent-session.js`     | System prompt cache with stable key; invalidated on tool/resource changes       |
| `core/extensions/loader.js` | **Extension loading parallelized** (`min(8,cores)`) in `loadExtensionsInternal` |

**Why this is the dominant startup win:** pristine v0.80.3 still loads all
extensions **sequentially** (`for…of await` in `loadExtensionsInternal`). With
~40 extensions this serializes every jiti transpile/instantiate. The patch loads
them concurrently (capped near core count), turning the longest pre-prompt phase
into a parallel one.

**Dropped in the 0.80.3 rebase:** the old jiti-singleton + `fsCache` loader hunk.
v0.80.3 added its own module-level factory cache (`extensionCache` keyed by a
cacheToken, plus `loadExtensionsCached`), so layering a shared-jiti `fsCache` on
top is marginal and risks colliding with upstream's caching. Only the concurrency
change is carried.

### Empty text content fix (`@earendil-works+pi-ai+openai-completions+empty-text.patch`)

Targets `node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/api/openai-completions.js` (moved from `providers/` in v0.80.3).

Fixes `Invalid request: text content is empty` from strict providers (kimi-k2.6 via opencode-go) when interrupting an agent turn then sending a new message.

- Filter `{type:"text",text:""}` blocks from user messages (mirrors `anthropic.js` behavior)
- Skip user messages with empty string content
- Send `content:""` instead of `null` for assistant messages that have only tool calls — the opencode.ai proxy normalizes `null` to `[{type:"text",text:""}]` before forwarding to kimi

### Tool call ID normalization (`@earendil-works+pi-ai+anthropic+normalize-tool-id.patch`)

Targets `node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/api/anthropic-messages.js` (Anthropic message-building moved here from `providers/anthropic.js` in v0.80.3).

Fixes `tool_use.id: String should match pattern '^[a-zA-Z0-9_-]+$'` when switching from a non-Anthropic model (e.g. kimi via opencode-go) to Claude mid-conversation.

- `normalizeToolCallId` now returns `"tool_call_0"` for empty/null input
- `block.id` always sanitized at the point of building `tool_use` blocks
- `toolCallId` always sanitized when building `tool_result` blocks

> **Rebased to v0.80.10:** upstream now threads `normalizeToolCallId` through `transformMessages` (covering the cross-model replay case) and split tool_result building into `convertToolResult`. The patch's residual value is the empty/null-id guard plus the payload-build-time safety net at both build points (`convertToolResult`'s `tool_use_id: normalizeToolCallId(msg.toolCallId)` and the `tool_use` block's `id: normalizeToolCallId(block.id)`). The orphan-repair synthetic ids derive from the already-normalized `tool_use` blocks, so no extra normalization is needed there.

## Key architecture notes

- `opencode-go/kimi-k2.6` uses `api: "openai-completions"` — all requests go through `openai-completions.js`, not a kimi-specific file
- `transformMessages` in `transform-messages.js` handles cross-provider message replay (skips aborted turns, synthesizes missing tool results, normalizes IDs for cross-model). It is called inside each provider's `convertMessages`
- Tool call ID normalization in `anthropic.js` runs at two levels: `transformMessages` (cross-model detection) and now also at payload build time (safety net)
- Patches to pi-ai sub-package must target the NESTED path inside pi-coding-agent's own `node_modules`, not any global pi-ai install

### Extra-usage retry fix (`@earendil-works+pi-ai+retry+extra-usage.patch`)

Targets `node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/utils/retry.js`.

> Renamed and re-homed in the v0.80.3 rebase. The retry classifier moved out of `agent-session.js`'s inline `_isRetryableError()` regex into pi-ai's shared `isRetryableAssistantError()` / `RETRYABLE_PROVIDER_ERROR_PATTERN`. (Old patch: `@earendil-works+pi-coding-agent+0.74.0+extra-usage-retry.patch`, retired.)

Fixes orchestrator going silent after subagent notifications hit the CC extra-usage cap. The retryable pattern did not match `"You're out of extra usage..."`, so the error was classified as non-retryable. The failed turn was rewound, the notification was dropped, and the orchestrator waited indefinitely for user input.

Adds `"extra.?usage"` to `RETRYABLE_PROVIDER_ERROR_PATTERN`. The errors are transient (CC extra-usage pool recovers within minutes); it is not caught by `NON_RETRYABLE_PROVIDER_LIMIT_ERROR_PATTERN` (budget/quota/billing), so the existing exponential-backoff retry path handles it.

### Orphaned tool_use repair (`@earendil-works+pi-ai+anthropic+orphaned-tool-use-repair.patch`)

Targets `node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/api/anthropic-messages.js`.

Fixes recurring `400 invalid_request_error: tool_use ids were found without tool_result blocks immediately after` from the Anthropic API in long conversations.

**Root cause:** `transformMessages` inserts synthetic `tool_result` messages for orphaned tool calls, but it has gaps. Specifically: aborted assistant messages are skipped before their tool calls update `pendingToolCalls`, cross-model ID normalization collisions can leave IDs uncovered, and any other edge case in the second pass can slip through. When these gaps hit `convertMessages`, the final `params` array sent to Anthropic contains an assistant message with `tool_use` blocks that is NOT followed by matching `tool_result` blocks — causing the 400.

**Fix:** A final repair pass runs inside `convertMessages` after the message loop and before `cache_control` processing. It scans `params` for every assistant message containing `tool_use` blocks, computes which IDs are not covered by the immediately following user message, and injects synthetic `tool_result` entries (prepended into the existing next user message if it exists, or as a new standalone user message). This is a deterministic last-resort guard that cannot be defeated by any earlier logic failure.

### JSON control-char repair (`@earendil-works+pi-ai+json-parse+control-char-repair.patch`)

Targets `node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai/dist/utils/json-parse.js`.

Fixes `Bad control character in string literal in JSON` crashing the SSE stream and triggering the `tool_use` 400 loop.

**Root cause:** `parseJsonWithRepair` tries `repairJson` as a fallback, but `repairJson`'s `inString` tracking breaks when a JSON string value contains unescaped inner quotes (e.g. code in `edit.newText`). It exits the string early at the unescaped quote, so a control char later in the same value (e.g. `\x1b` ANSI escape) is seen as outside a string and passes through unchanged. The second `JSON.parse` fails and the original error is rethrown, crashing the stream.

**Fix:** Wrap the `repairJson` retry in `try/catch`. Add a second fallback: brute-force replace all bare control chars (`\x00-\x08`, `\x0b`, `\x0c`, `\x0e-\x1f`) with `\uXXXX` escapes and retry. Only rethrow if all three attempts fail.

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
