# Simulation Loop — Every Tick, In Order

## Overview

Each call to `step()` executes all phases in this exact order.
Do NOT reorder phases — the sequence matters for numerical stability.

---

## Phase 0: Advance Time
```
tick += 1
global_phase = (omega * tick) mod (2π)
```

---

## Phase 1: Advance Peristaltic Phases

For each active edge (i, j):
```
// Kuramoto phase coupling — synchronize with adjacent edges
// "adjacent edges" = all edges sharing a node with this edge
coupling = 0.0
count = 0
For each edge (neighbor_edge) sharing a node with edge:
    coupling += sin(phase[neighbor_edge] - phase[edge])
    count += 1
if count > 0:
    phase[edge] += K * dt * coupling

// Advance phase
phase[edge] += omega * dt
if phase[edge] > 2π:
    phase[edge] -= 2π

// Effective conductance including peristaltic modulation
// Phase 3+: A_eff uses signal at the edge's nodes (see below)
node_i, node_j = nodes of edge
signal_avg = (signal[node_i] + signal[node_j]) / 2.0
A_eff = AMPLITUDE + SIGNAL_COUPLING * signal_avg  // SIGNAL_COUPLING = 0.0 until Phase 3
D_eff[edge] = conductance[edge] * (1.0 + A_eff * sin(phase[edge]))
D_eff[edge] = max(D_eff[edge], 0.0001)  // never go negative
```

**Parameters:**
- K = 0.1   (Kuramoto coupling strength — Alim 2013)
- AMPLITUDE = 0.3   (base peristaltic amplitude)
- SIGNAL_COUPLING = 0.02   (signal → amplitude feedback — Alim 2017; set to 0 in Phase 1-2)

**Why first:** Pressure solver uses D_eff, so phase must be current.

---

## Phase 2: Solve Pressure (Gauss-Seidel)

**Setup source terms S_i:**
```
For food source nodes:  pressure[i] = PRESSURE_SOURCE  (fixed, skip in loop)
For sink nodes:         pressure[i] = 0.0              (fixed, skip in loop)
For boundary nodes:     skip
```

**Gauss-Seidel iterations (repeat 25 times):**
```
For each interior node i (not source, not sink, not boundary):
    numerator = 0.0
    denominator = 0.0
    
    For each neighbor j of i:
        edge = edge_between(i, j)
        if active[edge]:
            D = D_eff[edge]
            numerator += D * pressure[j]
            denominator += D
    
    if denominator > 0.0001:
        pressure[i] = numerator / denominator
        // (source term S_i = 0 for interior nodes, cancels out)
```

**Why 25 iterations:** Empirically converges well for this grid size.
More iterations = more biological accuracy but slower.

---

## Phase 3: Calculate Flow

For each active edge between nodes i and j:
```
Q = D_eff[edge] * (pressure[i] - pressure[j])
flow[edge] = Q
// Positive Q = flow from i to j
// Negative Q = flow from j to i
```

---

## Phase 4: Update Conductance (Tero Adaptation)

For each edge (active and inactive):
```
Q = abs(flow[edge])
dD = dt * (pow(Q, MU) - DECAY * conductance[edge])
conductance[edge] += dD

// Clamp
if conductance[edge] < MIN_CONDUCTANCE:
    conductance[edge] = MIN_CONDUCTANCE
    active[edge] = 0

if conductance[edge] > MAX_CONDUCTANCE:
    conductance[edge] = MAX_CONDUCTANCE

// Reactivate if above threshold
if conductance[edge] > REACTIVATION_THRESHOLD:
    active[edge] = 1
```

**Parameters:**
- MU = 1.0
- DECAY = 0.01
- MIN_CONDUCTANCE = 0.0001
- MAX_CONDUCTANCE = 10.0
- REACTIVATION_THRESHOLD = 0.001
- dt = 0.1

---

## Phase 5: Advect Signal (cAMP)

For each active edge between nodes i and j:
```
Q = flow[edge]  // signed flow

if Q > 0:
    // Flow goes from i to j
    transported = dt * Q * signal[i]
    signal[i] -= transported
    signal[j] += transported
elif Q < 0:
    // Flow goes from j to i
    transported = dt * abs(Q) * signal[j]
    signal[j] -= transported
    signal[i] += transported
```

**After advection — diffusion pass:**
```
For each interior node i:
    // Sum form (correct discrete Laplacian: ∂c/∂t = D∇²c)
    // NOT average form — that would reduce effective D by factor of n
    diff = 0.0
    For each active neighbor j of i:
        diff += signal[j] - signal[i]
    signal[i] += dt * SIGNAL_DIFFUSION * diff
```

**Production at food source nodes:**
```
For each food source node i:
    signal[i] += dt * SIGNAL_PRODUCTION * food[i] / 255.0
```

**Decay everywhere:**
```
For each node i:
    signal[i] *= (1.0 - dt * SIGNAL_DECAY)
    signal[i] = max(0.0, signal[i])
    signal[i] = min(255.0, signal[i])
```

**Parameters:**
- SIGNAL_DIFFUSION = 0.01
- SIGNAL_PRODUCTION = 5.0
- SIGNAL_DECAY = 0.005

---

## Phase 6: Advect Softening Agent

Identical to signal advection but with different parameters.
Softening agent released at food nodes when food is consumed.

```
// Released when food consumed (in phase 7):
softening[i] += SOFTENING_BURST  // = 50.0

// Advection (same as signal — upwind scheme)

// Diffusion — sum form (same as signal, slower coefficient)
For each interior node i:
    diff = 0.0
    For each active neighbor j of i:
        diff += softening[j] - softening[i]
    softening[i] += dt * SOFTENING_DIFFUSION * diff

// Decay (slower than signal)
```

**Parameters:**
- SOFTENING_DIFFUSION = 0.005
- SOFTENING_DECAY = 0.001 (persists much longer than signal)

**Effect on conductance (modifies Phase 4):**
The conductance update becomes:
```
softening_boost = (softening[i] + softening[j]) / 2.0
dD = dt * (pow(Q, MU) + SOFTENING_WEIGHT * softening_boost - DECAY * conductance[edge])
```
- SOFTENING_WEIGHT = 0.1

---

## Phase 7: Update Food Consumption

For each food source node i:
```
// Food consumed proportional to total flow at node
// Asymptotic formula (doc 10 eq 8): slows as food depletes, matches biology
total_flow = 0.0
For each active edge at node i:
    total_flow += abs(flow[edge])

food[i] -= dt * CONSUMPTION_RATE * total_flow * (food[i] / 255.0)
food[i] = max(0.0, food[i])

// Trigger dieback when food drops below threshold (asymptotic formula never
// reaches exactly zero — threshold is the practical "depleted" signal)
if food[i] < FOOD_DEPLETED_THRESHOLD:
    softening[i] += SOFTENING_BURST
    is_source[i] = 0
    food[i] = 0.0
```

- CONSUMPTION_RATE = 0.001
- FOOD_DEPLETED_THRESHOLD = 5.0
// NOTE: if dieback triggers too late or too early in practice, switch to
// linear formula: `food[i] -= dt * CONSUMPTION_RATE * total_flow`
// and trigger at `food[i] <= 0.0`. Linear version depletes in ~10,000 ticks
// at flow=1.0 vs asymptotic ~never. Tune CONSUMPTION_RATE to adjust timing.

---

## Phase 8: Update Calcium (Optional — Phase 4 of project)

For each node i:
```
// Calcium oscillates coupled to mechanical strain
// Simple model: Ca2+ = base + A_ca * sin(global_phase + position_offset)
calcium[i] = CA_BASE + CA_AMPLITUDE * sin(global_phase + calcium_phase_offset[i])
```

Calcium modulates contraction amplitude in Phase 1:
```
local_amplitude = AMPLITUDE * (1.0 + CA_COUPLING * calcium[i] / CA_MAX)
D_eff[edge] = conductance[edge] * (1.0 + local_amplitude * sin(phase[edge]))
```

---

## Tick Rate

Target: 60 ticks/second in browser.
Each tick = ~16.67ms real time.
Simulation time: 1 tick = 1 second biological time (configurable).
Peristalsis period: 100 ticks = ~100 seconds (matches real ~100s period).

Speed slider multiplies ticks per frame: 1x to 10x.
At 10x speed: 600 ticks/second simulation time, 10 second biological minutes per real second.

---

## Numerical Stability Notes

1. Never let D_eff go negative — clamp to small positive value
2. Pressure solver needs at least one source AND one sink per connected component
3. If no active sinks exist, add the farthest node from all sources as sink
4. Signal/softening values must be clamped to [0, 255] to prevent blow-up
5. dt = 0.1 is conservative — larger dt may cause oscillation in conductance
