# pi-coding-agent Patches

This repository stores patches for [@mariozechner/pi-coding-agent](https://www.npmjs.com/package/@mariozechner/pi-coding-agent) to address specific issues or add optimizations.

## Patches

### @mariozechner+pi-coding-agent+0.73.0.patch

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
   npx patch-package @mariozechner/pi-coding-agent
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
