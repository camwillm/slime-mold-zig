# Build System & Migration Guide

## Toolchain Requirements

- **Zig version:** 0.14.0 (pinned in `build.zig.zon`, `minimum_zig_version = "0.14.0"`)
- **No external dependencies** — `build.zig.zon` has empty `.dependencies`
- **No raylib, no particle sim deps** — pure Zig + WASM

---

## Build Commands

```bash
# Development build (fast compile, slow runtime)
zig build

# Production build (slow compile, 3-5x faster runtime — use for deployment)
zig build -Doptimize=ReleaseFast

# Output location
www/slime.wasm    # always, regardless of optimize flag
```

Serve locally:
```bash
cd www && python3 -m http.server 8080
# then open http://localhost:8080
```

---

## How `build.zig` Works

```zig
// Current build.zig — no changes needed when adding source files
target = wasm32-freestanding   // no OS, no libc
exe.rdynamic = true            // makes export fn visible to JS
exe.entry = .disabled          // no main() entry point — WASM library mode
output → www/slime.wasm        // co-located with index.html
```

**Key point:** `build.zig` only references `src/main.zig`. All other `.zig` files
(network.zig, pressure.zig, adapt.zig, etc.) are pulled in via `@import` chains.
No changes to `build.zig` are needed when adding new source files.

---

## Multi-File Zig Module Pattern

The new architecture has 7 source files. They wire together like this:

```zig
// src/main.zig
const network    = @import("network.zig");
const pressure   = @import("pressure.zig");
const adapt      = @import("adapt.zig");
const peristalsis = @import("peristalsis.zig");
const signal     = @import("signal.zig");
const memory     = @import("memory.zig");
```

Each module accesses shared state by passing a pointer to the global `State` struct
defined in `network.zig`. No global mutable state in submodules — everything
flows through the single `State` that `main.zig` owns.

```zig
// Example: pressure.zig signature
pub fn solve(state: *network.State, iterations: u32) void { ... }

// main.zig calls it as:
pressure.solve(&state, 25);
```

---

## Migration: What to Delete

The current codebase is a **particle simulation** — completely different architecture.
All of it must be replaced for Phase 1. Files to delete:

```
src/sim.zig      — particle agent simulation (50k agents, explore/return)
src/render.zig   — empty file (1 line), dead code
src/root.zig     — default Zig library stub, never used
```

Files to rewrite from scratch:
```
src/main.zig     — keep WASM boilerplate, replace all exports
www/index.html   — keep HTML structure, replace JS renderer entirely
```

Files to create new:
```
src/network.zig
src/pressure.zig
src/adapt.zig
src/peristalsis.zig
src/signal.zig
src/memory.zig
```

**Do not try to refactor sim.zig into the network model.** The conceptual model
is different enough that a clean rewrite is faster and clearer.

---

## WASM Memory Access Pattern (JS side)

After `wasm.init(W, H)`, get typed array views into WASM linear memory:

```javascript
// Must be called after every init() — buffer may be reallocated
function refreshViews(wasm) {
    const mem = wasm.memory.buffer;
    const W = 200, H = 200;
    const N = W * H;         // 40,000 nodes
    const E = (W-1)*H + W*(H-1);  // 79,600 edges

    return {
        pressure:    new Float32Array(mem, wasm.getPressurePtr(),    N),
        conductance: new Float32Array(mem, wasm.getConductancePtr(), E),
        flow:        new Float32Array(mem, wasm.getFlowPtr(),        E),
        signal:      new Float32Array(mem, wasm.getSignalPtr(),      N),
        phase:       new Float32Array(mem, wasm.getPhasePtr(),       E),
    };
}
```

These are **live views** — they update in place every tick without copying.
Do NOT cache across `init()` calls (pointer may change).

---

## Page Allocator in WASM

`std.heap.page_allocator` is used (already in current `main.zig`).
In `wasm32-freestanding`, this grows WASM memory via the `memory.grow` instruction.
The JS side accesses it via `instance.exports.memory.buffer`.

Total allocation: ~2.6 MB (see doc 07). Well within default WASM 256 MB limit.
No need to set a custom memory limit in `build.zig`.

---

## Debug Build vs Release

| Mode | Build time | Step() time | Use for |
|------|-----------|-------------|---------|
| Debug (default) | ~2s | ~80ms | development, test cases |
| ReleaseFast | ~8s | ~15ms | deployment, performance testing |

At Debug speeds, the 60fps target may not be met (step() too slow).
Use `ReleaseFast` when testing visual behavior and performance budget.
