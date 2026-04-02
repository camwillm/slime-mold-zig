# Test Cases — Verifiable Correctness Checks

## How to Use This Document

Each test case describes:
1. **Setup** — exact initial conditions
2. **Run** — how many ticks
3. **Expected** — what must be true
4. **Measure** — specific values to check
5. **Failure modes** — what went wrong if it fails

Run these after each phase before merging.

---

## Phase 1 Tests

### Test 1.1: Single Tube Formation (Nakagaki Basic)
**Biological basis:** Two food sources → one tube, Nakagaki 2000

**Setup:**
```
Grid: 200x200
Initial conductance: 0.01 everywhere
Food source A: node (40, 100)  — left center
Food source B: node (160, 100) — right center
Sink: node (100, 100)          — grid center (initial)
```

**Run:** 1000 ticks

**Expected:**
- One clearly dominant tube connecting A and B
- The dominant tube follows approximately y=100 (horizontal path)
- Conductance on dominant tube > 1.0
- Conductance off dominant path < 0.05

**Measure:**
```
D_max_on_path  = max conductance of edges with y ∈ [98, 102], x ∈ [40, 160]
D_max_off_path = max conductance of all other edges
ratio = D_max_on_path / D_max_off_path
```
**Pass:** ratio > 10.0

**Failure modes:**
- ratio < 2: pressure solver not converging, check Gauss-Seidel implementation
- No tubes at all: check source/sink boundary conditions
- Uniform high conductance: decay constant γ too low, increase to 0.02

---

### Test 1.2: Y-Junction (Steiner Point)
**Biological basis:** Three food sources → Y junction, shortest total tube length

**Setup:**
```
Food sources at vertices of equilateral triangle:
  A: (100, 50)   — top
  B: (50, 150)   — bottom-left  
  C: (150, 150)  — bottom-right
Sink: (100, 117) — approximate Steiner point
```

**Run:** 1500 ticks

**Expected:**
- Three tubes radiating from a central Steiner point (~100, 117)
- No direct edge AB, BC, or AC dominates (they prune)
- The junction point is NOT at any food source

**Measure:**
```
// Find the node with highest degree in thick-tube subgraph
thick_edges = all edges with D > 0.5
thick_nodes = all nodes touching thick_edges
junction_node = node in thick_nodes with highest degree
junction_degree >= 3  (three tubes meeting)
```
**Pass:** junction_degree == 3 AND junction is not a food source node

**Failure modes:**
- Only two tubes form (direct A-B): try increasing simulation time
- Junction at food source: initial conductance too non-uniform

---

### Test 1.3: Dead-End Pruning
**Biological basis:** Tubes that don't connect food sources prune away

**Setup:**
```
Food source A: (50, 100)
Food source B: (150, 100)
Additional food source C: (100, 50)  — initially active, then removed at tick 300
```

**Run:** 600 ticks total

**Expected:**
- At tick 299: network connecting A, B, and C
- Remove C at tick 300
- At tick 600: network has pruned tube toward C

**Measure:**
```
At tick 600:
D_toward_C = max conductance of edges in corridor toward (100, 50)
D_main = max conductance on direct A-B path
```
**Pass:** D_toward_C < 0.1 * D_main

---

### Test 1.4: Mass Conservation Approximation
**Biological basis:** Flow into each node ≈ flow out

**After pressure solve (check once per 100 ticks):**
```
For each interior node i:
    flow_in  = Sum of Q_ij for edges where Q_ij flows INTO i
    flow_out = Sum of Q_ij for edges where Q_ij flows OUT of i
    imbalance = |flow_in - flow_out|
```
**Pass:** max imbalance < 0.001 for all interior nodes

**Failure:** Gauss-Seidel not converging — increase iterations or reduce dt

---

## Phase 2 Tests

### Test 2.1: Oscillation Period
**Expected:** Each edge phase completes one full cycle every ~100 ticks

**Measure:**
```
Record conductance[edge_0] every tick for 200 ticks
Find time between consecutive maxima
```
**Pass:** period = 95 to 105 ticks

---

### Test 2.2: Traveling Wave Direction
**Expected:** Phase wave travels in consistent direction along established tube

**Setup:** Phase 1 network with one established tube (A-B)

**Measure:**
```
Record phase at 5 evenly spaced edges along tube A→B
Check: phase(edge_1) - phase(edge_2) is constant over time (traveling wave)
Check: phase increases monotonically from A to B (or B to A consistently)
```
**Pass:** phase difference between consecutive edges = 2π/5 ± 0.3 radians

---

### Test 2.3: Thin Edge Flickering
**Expected:** Thin edges (D < 0.05) have rapidly varying, uncorrelated phases

**Measure:**
```
Compare phases of two thin edges that are not adjacent
Compute correlation over 200 ticks
```
**Pass:** correlation < 0.2 (effectively random)

---

## Phase 3 Tests

### Test 3.1: Signal Speed vs Diffusion Speed
**Biological basis:** Signal travels at flow speed (~50x faster than diffusion alone)

**Setup:**
```
Established tube A-B (from Phase 1)
Tube length: 120 grid units (from x=40 to x=160)
Add new food at A at tick 0, check when signal reaches B
```

**Measure:**
```
Find first tick when signal[B] > 10.0
Compare to theoretical diffusion time: L² / (2 * D_diff) = 120² / (2*0.01) = 720000 ticks
```
**Pass:** signal reaches B in < 500 ticks (vs 720,000 ticks pure diffusion)

---

### Test 3.2: Network Response to New Food
**Expected:** Adding food at new location triggers network adaptation

**Setup:**
```
Established A-B tube
Add new food source at C = (100, 50) at tick 500
```

**Measure:**
```
Tick 500: max conductance toward C
Tick 700: max conductance toward C
```
**Pass:** conductance toward C at tick 700 > 2 * conductance at tick 500

---

## Phase 4 Tests

### Test 4.1: Food Depletion Rate
**Expected:** Food depletes within ~1000 ticks of being connected to network

**Measure:**
```
food_initial = 255
Record food[source_node] every 100 ticks
Find tick when food[source_node] < 5
```
**Pass:** depletion tick is between 500 and 2000

---

### Test 4.2: Structural Memory Persistence
**Expected:** Thick tube persists after food consumed

**Measure:**
```
At food consumption tick T:
  D_tube = conductance of main tube to consumed food source

At tick T + 200:
  D_tube_later = conductance of same tube
```
**Pass:** D_tube_later > 0.5 * D_tube (tube retains >50% thickness for 200 ticks)

---

### Test 4.3: Memory Guides New Search
**Expected:** Organism finds food near old consumed food location faster

**Setup:**
```
Run simulation. Food at A (50, 100) gets consumed at tick T.
Add new food at B_near = (60, 100) and B_far = (100, 50) simultaneously at tick T+50.
```

**Measure:**
```
Find tick when conductance toward B_near > 1.0  → T_near
Find tick when conductance toward B_far > 1.0   → T_far
```
**Pass:** T_near < T_far (near location found faster due to structural memory)

---

## Integration Tests (All Phases)

### Test I.1: Tokyo Experiment
**Setup:** Place food sources at Tokyo suburb positions (see Phase 5 data in 11_implementation_phases.md)

**Run:** 2000 ticks

**Expected:**
- Network forms connecting all food sources
- Compare to actual Tokyo rail network topology
- Major corridors visible (Yamanote-like ring, radiating lines)

**Visual check only** — no automated metric, compare side-by-side with reference image.

---

### Test I.2: Maze Solving
**Setup:**
```
Generate a 20×20 maze using recursive backtracking
Scale to 200×200 grid (each maze cell = 10×10 grid nodes)
Set conductance = 0 for wall edges
Place food at maze entrance (top-left) and exit (bottom-right)
```

**Run:** 3000 ticks

**Expected:**
- Network solves maze, finding path from entrance to exit
- Dead-end corridors pruned
- One dominant tube remains

**Measure:**
```
Find connected path through thick-tube subgraph from entrance to exit
path_length = number of edges on path
shortest_path_length = actual BFS shortest path through maze
```
**Pass:** path_length ≤ 1.2 * shortest_path_length (within 20% of optimal)

---

## Regression Test Suite

Run all of the above before every merge to main.
Automate where possible using a headless WASM test harness.

```javascript
// test_runner.js — run in Node.js
const { WASM } = require('./build/test_wasm');
const wasm = new WASM();

async function runAllTests() {
    console.log("Test 1.1:", await test_single_tube(wasm));
    console.log("Test 1.4:", await test_mass_conservation(wasm));
    // etc.
}
```

A failing test is a BLOCKER — do not proceed to next phase until all tests pass.
