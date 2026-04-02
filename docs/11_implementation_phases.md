# Implementation Phases

## Philosophy

Build in phases. Each phase produces a **working, deployable simulation**.
Never attempt to build multiple phases simultaneously.
Each phase adds one biological behavior on top of a proven foundation.

---

## Phase 1: Basic Network + Shortest Path
**Goal:** Reproduce the Nakagaki 2000 maze experiment.
**Completion:** Two food sources placed → single shortest-path tube forms.

### What to build:
- [ ] Grid of 200×200 nodes, 79,600 edges
- [ ] Uniform initial conductance D_0 = 0.01 everywhere
- [ ] Gauss-Seidel pressure solver (25 iterations)
- [ ] Poiseuille flow calculation
- [ ] Tero adaptation equation (dD/dt = |Q| - γD)
- [ ] Edge deactivation when D < D_min
- [ ] WASM exports: init, step, setFood, getConductancePtr, getFlowPtr
- [ ] JS renderer: edges as lines, thickness = conductance
- [ ] Two preset food sources (left-center and right-center)

### Success criteria:
1. Place food at (40, 100) and (160, 100)
2. Run 500 ticks
3. One thick bright tube connects the two food sources
4. Most other edges are dark/dead
5. The path is approximately the shortest route

### Known challenges:
- Need at least one sink node — use center of grid initially
- Pressure solver needs good initial conditions — start P = 0 everywhere
- May need to normalize conductance to prevent overflow

### Do NOT include in Phase 1:
- Peristalsis (no oscillation)
- Signal propagation
- Structural memory
- Food consumption
- Moving sink nodes

---

## Phase 2: Peristaltic Oscillation
**Goal:** Add visible pulsing — the "heartbeat" of the organism.
**Completion:** Tubes visibly pulse, wave travels along network.

### Prerequisites: Phase 1 working perfectly.

### What to build:
- [ ] Phase array per edge (φ_ij), initialized randomly in [0, 2π]
- [ ] Phase advance: φ += ω * dt each tick
- [ ] D_eff = D * (1 + A * sin(φ))
- [ ] Pressure solver uses D_eff instead of D
- [ ] Phase coupling: dφ/dt += K * Sum sin(φ_j - φ_i) for adjacent edges
- [ ] Renderer: modulate edge brightness with sin(φ) — the traveling wave
- [ ] Export: getPhasePtr() for JS rendering

### Success criteria:
1. Tubes visibly pulse at ~100 tick period
2. Bright spot travels along tube from one food source toward other
3. Wave travels consistently in one direction along established tubes
4. Thin exploratory edges have random-phase flickering
5. Thick tubes have synchronized phase wave

### What changes from Phase 1:
- `step()` now advances phases BEFORE pressure solve
- Renderer now reads phase array and modulates brightness

### Do NOT include in Phase 2:
- Signal propagation
- Food consumption
- Structural memory

---

## Phase 3: Signal Propagation
**Goal:** Organism responds to food stimulus rapidly via flow-advected signal.
**Completion:** Add new food source → network detects and routes toward it within seconds.

### Prerequisites: Phases 1+2 working.

### What to build:
- [ ] Signal concentration array per node (c_i)
- [ ] Signal production at food source nodes each tick
- [ ] Upwind advection scheme — signal carried by flow
- [ ] Signal diffusion (slow, D_diff = 0.01)
- [ ] Signal decay (δ = 0.005)
- [ ] Signal modulates contraction amplitude: A_local = A_base + A_signal * c_i
- [ ] Export: getSignalPtr()
- [ ] Renderer: show signal as yellow-green glow on nodes

### Success criteria:
1. Signal concentrates at food source nodes immediately
2. Signal spreads along tubes within 50-100 ticks
3. Adding new food source creates visible signal wave propagating through network
4. Network conductance begins changing toward new food source within 200 ticks
5. Response is faster than if signal only diffused (no advection)

### Test: remove one food, add new food at different location.
The network should reroute FASTER than if it had to grow from scratch.

---

## Phase 4: Structural Memory
**Goal:** Past food locations leave persistent thick tubes.
**Completion:** Food consumed → tube persists → biases future network.

### Prerequisites: Phases 1+2+3 working.

### What to build:
- [ ] Food consumption logic (food decreases based on flow)
- [ ] Softening agent array per node (s_i)
- [ ] Softening burst released when food fully consumed
- [ ] Softening advection (same as signal, slower decay)
- [ ] Conductance update enhanced by softening agent
- [ ] Export: getFoodPtr(), getSofteningPtr()
- [ ] Renderer: consumed food sites leave a visible "scar"

### Success criteria:
1. Food depletes over ~500-1000 ticks of flow
2. When food depleted, thick tube at that location persists for ~500 ticks
3. Place new food near old food location — network finds it faster
4. Place new food far from old food — network takes longer

---

## Phase 5: Interactive Experiments
**Goal:** User can recreate famous experiments.
**Completion:** Tokyo experiment, maze experiment, US cities experiment.

### What to build:
- [ ] Click to place food on canvas
- [ ] Click to remove food
- [ ] Preset: "Tokyo" — places food at Tokyo suburb positions, shows real result
- [ ] Preset: "US Cities" — top 20 cities as food sources
- [ ] Preset: "Maze" — generates a random maze, places food at entrance/exit
- [ ] Speed control slider (1x to 10x)
- [ ] Screenshot button (captures current state)
- [ ] Share button (encodes food positions in URL hash)

### Tokyo experiment data (normalized to 200x200 grid):
```javascript
const tokyoFoodSources = [
  // [x, y, label] — approximate positions
  [100, 100, "Tokyo"],      // center
  [130, 90,  "Chiba"],
  [80,  85,  "Yokohama"],
  [115, 75,  "Omiya"],
  [145, 95,  "Choshi"],
  [90,  110, "Atsugi"],
  [110, 115, "Kamakura"],
  [140, 75,  "Tsukuba"],
  [75,  95,  "Hachioji"],
  [120, 80,  "Narita"],
];
```

---

## Phase 6: Full Biology (Research Grade)
**Goal:** Add calcium coupling and two-timescale dynamics.
**Completion:** Organism behavior matches experimental videos frame by frame.

### What to build:
- [ ] Calcium oscillator per node (Ca_i coupled to mechanical strain)
- [ ] Two-timescale dynamics (fast 1-2 min + slow 20 min oscillation)
- [ ] Slow amplitude modulation creating net flow direction changes
- [ ] Phase pattern self-organizes to span 0-2π across organism
- [ ] Organism size detection for wavelength adaptation

### This phase is research-level. May require:
- Consulting additional papers
- Numerical methods beyond Gauss-Seidel
- Potential WebGL compute shaders for performance

---

## Build Order Within Each Phase

For each phase, build in this order:
1. **Zig data structures** — add arrays, update structs
2. **Core algorithm** — implement the math
3. **WASM exports** — expose new data to JS
4. **JS reads** — update memory readers
5. **Visual** — render the new data
6. **Verify** against success criteria
7. **Commit** before starting next phase

---

## Git Branch Strategy

```
main        — stable, deployed at slime.camwillm.me
dev         — current development
phase1      — branch off dev for Phase 1 work
phase2      — branch off phase1 when phase1 merged
etc.
```

Merge to dev only when phase success criteria pass.
Merge to main only for demos.
