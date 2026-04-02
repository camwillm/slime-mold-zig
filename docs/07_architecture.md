# Architecture — Complete Technical Design

## Overview

This is a **graph network simulation**, not a particle simulation.
The organism IS the network. There are no agents.
Each node is a junction point. Each edge is a tube.
Fluid flows through tubes. Tubes adapt based on flow.

---

## Grid Specification

- **Dimensions:** 200 × 200 nodes
- **Total nodes:** 40,000
- **Connectivity:** 4-connected (up, down, left, right only — no diagonals)
- **Horizontal edges:** 200 rows × 199 per row = **39,800**
- **Vertical edges:** 199 rows × 200 per row = **39,800**
- **Total edges:** **79,600**

### Node Index Formula
```
index = y * WIDTH + x
```

### Edge Index Formula
```
Horizontal edge between (x,y) and (x+1,y):
  h_index = y * (WIDTH - 1) + x
  Range: 0 to 39,799

Vertical edge between (x,y) and (x,y+1):
  v_index = HORIZ_COUNT + y * WIDTH + x
  Range: 39,800 to 79,599
```

---

## Data Structures

### Node Arrays (each: [40,000]f32)
```zig
pressure:    [40000]f32  // P_i — solved each tick via linear system
signal:      [40000]f32  // cAMP concentration — advected by flow
calcium:     [40000]f32  // Ca2+ — drives peristaltic oscillation
food:        [40000]f32  // food present (0-255), decreases when consumed
softening:   [40000]f32  // structural memory agent, released when food consumed
is_source:   [40000]u8   // 1 if food source node (high pressure boundary)
is_sink:     [40000]u8   // 1 if frontier/sink node (low pressure boundary)
is_boundary: [40000]u8   // 1 if hard wall — no flow through
```

### Edge Arrays (each: [79,600]f32)
```zig
conductance: [79600]f32  // D_ij — THE key adaptive variable, tube thickness
flow:        [79600]f32  // Q_ij — current fluid flow rate (signed, direction matters)
phase:       [79600]f32  // φ_ij — oscillation phase for peristalsis (0 to 2π)
active:      [79600]u8   // 1 if edge is alive (conductance > MIN_CONDUCTANCE)
```

### Scalar State
```zig
tick: u64              // simulation time counter
source_pressure: f32   // fixed Dirichlet pressure at food source nodes (NOT the Tero I_0
                       // current injection — this implementation uses Dirichlet BCs, not Neumann)
omega: f32             // 2π / PERIOD — oscillation angular frequency
```

---

## Memory Layout (WASM)

Total memory requirement:
- Node arrays: 8 × 40,000 × 4 bytes = 1.28 MB
- Edge arrays: 4 × 79,600 × 4 bytes = 1.27 MB
- **Total: ~2.6 MB** (well within WASM 256 MB default)

All arrays are flat, contiguous, cache-friendly.
JS accesses them via Float32Array views into WASM linear memory.

---

## WASM Export Interface

```zig
// Lifecycle
export fn init(width: u32, height: u32) void
// init: allocates all arrays, sets uniform conductance D_0, randomizes phases,
//       designates center node as default sink. Frees previous alloc if called again.

export fn step() void
// step: runs one full simulation tick (all phases from doc 08). dt = 0.1 internal.

export fn reset() void
// reset: equivalent to init(current_width, current_height).
//        Reinitializes all state WITHOUT reallocating memory.
//        Use for the UI "reset" button. All food sources cleared.

// Food/source control
export fn setFood(x: u32, y: u32, strength: f32) void
export fn clearFood() void

// Memory pointers for JS to read
export fn getPressurePtr() [*]f32      // node pressure array
export fn getConductancePtr() [*]f32   // edge conductance array
export fn getFlowPtr() [*]f32          // edge flow array
export fn getSignalPtr() [*]f32        // node signal array
export fn getPhasePtr() [*]f32         // edge phase array

// Counts
export fn getNodeCount() u32           // 40,000
export fn getHorizEdgeCount() u32      // 39,800
export fn getVertEdgeCount() u32       // 39,800
export fn getTotalEdgeCount() u32      // 79,600

// Stats for UI
export fn getActiveEdgeCount() u32
export fn getMaxConductance() f32
export fn getAvgFlow() f32
```

---

## Pressure Solver: Gauss-Seidel

The system to solve each tick:
```
For each node i:
  Sum_{j ∈ neighbors(i)} D_ij * (P_i - P_j) / L_ij = S_i
```

Rearranged for Gauss-Seidel update:
```
P_i = (S_i + Sum_j [D_ij * P_j / L_ij]) / Sum_j [D_ij / L_ij]
```

**Boundary conditions:**
- Food source nodes: P_i = PRESSURE_SOURCE (fixed, not updated by solver)
- Sink nodes: P_i = 0.0 (fixed, not updated by solver)
- Boundary/wall nodes: not updated, pressure irrelevant
- Interior nodes: updated by Gauss-Seidel

**Convergence:** 20-30 iterations per tick is sufficient for visual accuracy.
For biological accuracy increase to 50 iterations.

**Note:** L_ij = 1.0 for all edges in a regular 4-connected grid, so it cancels out.

---

## Initialization State

When `init()` is called:
1. All nodes set to interior (not source, not sink, not boundary)
2. All edge conductances set to `INITIAL_CONDUCTANCE = 0.01` (organism fills grid)
3. All pressures set to 0.0
4. All phases set to random values in [0, 2π]
5. Boundary edges (at grid perimeter) set to `active = 0`
6. One sink node designated at grid center

When food is placed via `setFood()`:
1. Node marked as `is_source = 1`
2. Food value set
3. If no sinks exist anywhere: mark center node as sink

### Sink Node Lifecycle

The pressure solver requires at least one source AND one sink per connected component.
Violating this causes the Gauss-Seidel update to diverge (all pressures go to zero
or infinity).

Rules:
- **Initial state:** node at (WIDTH/2, HEIGHT/2) is the single default sink
- **When first food placed:** default sink remains; food node becomes source
- **Second food placed:** the first food node becomes a sink, the second becomes a source
  (two food sources → one is high pressure, one is low pressure = pressure differential)
- **When food consumed (Phase 4):** remove `is_source`, keep `is_sink` if it was also
  a sink. If this leaves zero sources, all remaining sinks are irrelevant (no flow).
- **Invariant:** there must always be at least one node with `is_source=1` AND at least
  one node with `is_sink=1` for any flow to occur.

**Simplest working scheme for Phase 1:** always treat first food placed as source,
second food placed as sink. If only one food is placed, use grid center as sink.
The center-sink creates a radial pruning pattern rather than a point-to-point tube.

---

## File Structure

```
src/
  main.zig      — WASM exports, global state, init/step/reset
  network.zig   — Node and Edge arrays, index helpers
  pressure.zig  — Gauss-Seidel pressure solver
  adapt.zig     — Tube conductance adaptation (Tero equations)
  peristalsis.zig — Phase oscillation and wave propagation
  signal.zig    — cAMP signal advection
  memory.zig    — Structural memory / softening agent
```
