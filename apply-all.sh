#!/usr/bin/env bash
set -euo pipefail

PATCHES_DIR="$(cd "$(dirname "$0")/patches" && pwd)"
# npm root -g returns .../lib/node_modules; patches reference node_modules/... so
# we need the parent (.../lib/) as the working directory for patch -p1.
PI_ROOT="$(dirname "$(npm root -g)")"

if [ ! -d "$PI_ROOT/node_modules/@earendil-works/pi-coding-agent" ]; then
  echo "Error: @earendil-works/pi-coding-agent not found at $PI_ROOT/node_modules"
  echo "Make sure the correct Node version is active (fnm/nvm users: check 'node --version')."
  exit 1
fi

TARGET_VERSION="0.80.3"
INSTALLED_VERSION=$(node -e "console.log(require('$PI_ROOT/node_modules/@earendil-works/pi-coding-agent/package.json').version)")

echo "Applying patches to: $PI_ROOT/node_modules"
echo "Installed version:   $INSTALLED_VERSION (patches target $TARGET_VERSION)"
if [ "$INSTALLED_VERSION" != "$TARGET_VERSION" ]; then
  echo "Warning: version mismatch. Patches may not apply cleanly."
fi
echo
echo

apply() {
  local patch="$PATCHES_DIR/$1"
  echo "  Applying $1 ..."
  if patch -p1 --dry-run -d "$PI_ROOT" < "$patch" &>/dev/null; then
    patch -p1 -d "$PI_ROOT" < "$patch" --no-backup-if-mismatch
    echo "  ✓ applied"
  elif patch -p1 --dry-run -R -d "$PI_ROOT" < "$patch" &>/dev/null; then
    echo "  ↩ already applied — skipping"
  else
    echo "  ✗ version mismatch — skipping"
    patch -p1 --dry-run -d "$PI_ROOT" < "$patch" 2>&1 | grep -E 'FAILED|offset|can.t find|Hunk' | sed 's/^/     /' || true
  fi
  echo
}

# Order matters: some patches share a file and are generated to stack.
#  - dedup-next-turn must precede the perf patch (both touch agent-session.js)
#  - normalize-tool-id must precede orphaned-tool-use-repair (both touch anthropic-messages.js)

# Bug fix: Bad control character in JSON crashes SSE stream, causing 400 loop
apply "@earendil-works+pi-ai+json-parse+control-char-repair.patch"

# Bug fix: orchestrator silent after subagent notifications hit CC extra-usage cap
apply "@earendil-works+pi-ai+retry+extra-usage.patch"

# Bug fix: empty text blocks sent to strict providers (Kimi via opencode-go)
apply "@earendil-works+pi-ai+openai-completions+empty-text.patch"

# Bug fix: invalid tool call IDs when switching to Claude mid-conversation
apply "@earendil-works+pi-ai+anthropic+normalize-tool-id.patch"

# Bug fix: tool_use ids without tool_result blocks in long conversations (recurring 400)
apply "@earendil-works+pi-ai+anthropic+orphaned-tool-use-repair.patch"

# Bug fix: duplicate user messages in print mode / subagent dispatch (#4197)
apply "@earendil-works+pi-coding-agent+issue-4197+dedup-next-turn.patch"

# Performance and startup improvements
apply "@mariozechner+pi-coding-agent+0.80.3.patch"

echo "All done."
