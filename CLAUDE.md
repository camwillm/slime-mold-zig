# CLAUDE.md — Slime Mold Simulation

## 1. Project Overview

Physarum polycephalum network simulation. Zig 0.14.0 → WASM, plain JS canvas renderer.
Reproduces Nakagaki 2000 / Tero 2007 / Alim 2013/2017 / Kramar & Alim 2021 models.

## 2. Current State

**Architecture: Spiderweb growth model** (implemented, replacing "fill then prune").

- Organism starts as a small blob (radius 5) at grid center.
- Food gradient diffuses outward through space (unrestricted by active edges).
- Every 10 ticks, `adapt.expandFrontier` grows the active network one cell toward
  any location where food gradient exceeds EXPAND_THRESHOLD (0.5).
- Tubes under flow thicken (Tero adaptation). Tubes with no flow decay and die.
- Result: radial network grows toward food, non-load-bearing branches prune away.

**Grid:** 100×100 nodes, 19,800 edges, 8px per cell on 800×800 canvas.

**Simulation loop order (per tick):**
1. `adapt.advancePhases` — phase advance + D_eff (peristalsis)
2. `pressure.solve` — Gauss-Seidel 15 iter, active-frontier only
3. `adapt.calcFlow` — Q = D_eff * ΔP
4. `adapt.updateConductance` — Tero dD + gradient boost + softening (skips inactive edges)
5. `signal.advectSignal` — cAMP advection + diffusion
6. `signal.advectSoftening` — structural memory agent
7. `signal.updateFood` — food consumption + softening burst on depletion
8. `signal.diffuseFoodGradient` — spatial diffusion (30% blend, no edge restriction)
9. `adapt.expandFrontier` — every 10 ticks, grow frontier toward food gradient

**Key parameters:**
- DECAY = 0.1 (gentle; flow > 0.1·D to survive)
- MIN_CONDUCTANCE = 0.001 (lower kill floor)
- INITIAL_RADIUS = 5 cells
- GRADIENT_DIFFUSION_BLEND = 0.30 (30% neighbor blend per tick, fast enough to guide frontier)
- EXPAND_THRESHOLD = 0.5 (gradient level needed to trigger frontier expansion)
- GAUSS_ITER = 15 (down from 25 for perf)

**Performance optimizations applied:**
- Active-frontier pressure solver (only solve nodes connected to live edges)
- Batched JS rendering: 3 Path2D buckets (thin/medium/thick) = 3 draw calls
- Uniform phase advance (Kuramoto coupling removed — O(n²) → O(1))
- Dead edges skipped in conductance update and phase advance
- Render threshold D > 0.01 (skip invisible edges)

## 3. File Map

| File | Responsibility |
|------|----------------|
| `src/main.zig` | WASM exports, global state, spiderwebInit(), step() orchestration |
| `src/network.zig` | Network struct, all constants, edge indexing helpers |
| `src/pressure.zig` | Gauss-Seidel solver with active-frontier optimization |
| `src/adapt.zig` | Phase advance, flow calc, conductance update, expandFrontier |
| `src/signal.zig` | cAMP signal, softening, food consumption, food gradient diffusion |
| `www/index.html` | JS renderer, WASM loader, stats overlay, food placement UI |
| `build.zig` | Zig build config (always targets wasm32-freestanding) |

## 4. Build Commands

```bash
zig build -Doptimize=ReleaseSmall   # production WASM → www/slime.wasm
zig build -Doptimize=ReleaseFast    # faster WASM (larger binary)
cd www && python3 -m http.server 8080
```

Deploy:
```bash
sudo cp www/slime.wasm /var/www/slime/
sudo cp www/index.html /var/www/slime/
```

## 5. Implementation Phases

See `docs/11_implementation_phases.md`. Currently working on Phase 2 (peristaltic
oscillation). Phase 2 Zig side complete; JS renders phase modulation.
Phases 3 (signal) and 4 (softening/memory) are implemented but not yet validated.

## 6. Rules

- Read all `docs/` before modifying simulation math or parameters.
- Never start a new phase before the current phase passes its success criteria.
- Each phase must be committed and working before the next begins.
- Zig changes require rebuild before testing.
- Do not add error handling for impossible cases. Trust WASM memory guarantees.
