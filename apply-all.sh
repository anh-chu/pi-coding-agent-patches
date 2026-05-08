#!/usr/bin/env bash
set -euo pipefail

PATCHES_DIR="$(cd "$(dirname "$0")/patches" && pwd)"
PI_ROOT="$(npm root -g)"

if [ ! -d "$PI_ROOT/@earendil-works/pi-coding-agent" ]; then
  echo "Error: @earendil-works/pi-coding-agent not found at $PI_ROOT"
  echo "Make sure the correct Node version is active (fnm/nvm users: check 'node --version')."
  exit 1
fi

echo "Applying patches to: $PI_ROOT"
echo

apply() {
  local patch="$PATCHES_DIR/$1"
  echo "  Applying $1 ..."
  if patch -p1 --dry-run -d "$PI_ROOT" < "$patch" &>/dev/null; then
    patch -p1 -d "$PI_ROOT" < "$patch"
    echo "  ✓ done"
  else
    echo "  ✗ dry-run failed (already applied or version mismatch — skipping)"
  fi
  echo
}

# Performance and startup improvements
apply "@mariozechner+pi-coding-agent+0.73.0.patch"

# Bug fix: empty text blocks sent to strict providers (Kimi via opencode-go)
apply "@earendil-works+pi-ai+openai-completions+empty-text.patch"

# Bug fix: invalid tool call IDs when switching to Claude mid-conversation
apply "@earendil-works+pi-ai+anthropic+normalize-tool-id.patch"

# Bug fix: duplicate user messages in print mode / subagent dispatch (#4197)
apply "@earendil-works+pi-coding-agent+issue-4197+dedup-next-turn.patch"

echo "All done."
