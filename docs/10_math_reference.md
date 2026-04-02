# Math Reference — All Equations

## Variables

### Node variables
| Symbol | Name | Units | Range |
|--------|------|-------|-------|
| P_i | Pressure at node i | dimensionless | 0 to I_0 |
| c_i | Signal (cAMP) concentration at node i | dimensionless | 0 to 255 |
| Ca_i | Calcium concentration at node i | dimensionless | 0 to 1 |
| f_i | Food at node i | dimensionless | 0 to 255 |
| S_i | Source term at node i | dimensionless | -I_0, 0, or +I_0 |
| s_i | Softening agent at node i | dimensionless | 0 to 255 |

### Edge variables
| Symbol | Name | Units | Range |
|--------|------|-------|-------|
| D_ij | Conductance of edge (i,j) | dimensionless | 0 to 10 |
| Q_ij | Flow through edge (i,j) | dimensionless | -∞ to +∞ |
| L_ij | Length of edge (i,j) | grid units | 1.0 (all edges) |
| φ_ij | Oscillation phase of edge (i,j) | radians | 0 to 2π |
| D_eff_ij | Effective conductance including peristalsis | dimensionless | 0 to 13 |

### Constants
| Symbol | Name | Value |
|--------|------|-------|
| I_0 | Source/sink strength | 1.0 |
| μ | Feedback exponent | 1.0 |
| γ | Conductance decay rate | 0.01 |
| dt | Time step | 0.1 |
| ω | Oscillation angular frequency | 2π/100 |
| A | Peristaltic amplitude | 0.3 |
| K | Phase coupling strength | 0.1 |
| D_min | Minimum conductance | 0.0001 |
| D_max | Maximum conductance | 10.0 |
| D_0 | Initial uniform conductance | 0.01 |

---

## 1. Poiseuille Flow (Hagen-Poiseuille)

The flow Q through a tube is proportional to conductance and pressure difference:

```
Q_ij = D_ij * (P_i - P_j) / L_ij
```

Since L_ij = 1 for all edges:
```
Q_ij = D_ij * (P_i - P_j)
```

**Sign convention:** Q_ij > 0 means flow from i to j.

---

## 2. Pressure Conservation (Kirchhoff Current Law)

At each node, the sum of all flows must equal the source term:

```
Sum_{j ∈ N(i)} Q_ij = S_i

Where:
  S_i = +I_0   if node i is a food source (pressure source)
  S_i = -I_0   if node i is a sink (frontier node)
  S_i = 0      if node i is interior
```

Expanding using Poiseuille:
```
Sum_{j ∈ N(i)} D_ij * (P_i - P_j) = S_i

P_i * Sum_{j} D_ij - Sum_{j} D_ij * P_j = S_i
```

---

## 3. Gauss-Seidel Pressure Update

**Implementation uses Dirichlet boundary conditions** (fixed pressures), not the Neumann
current-injection form (S_i ≠ 0) from section 2. These are equivalent physics but different
numerical schemes. Dirichlet is simpler and more numerically stable on this grid.

Boundary conditions (set once, never updated by solver):
```
Food source nodes: P_i = PRESSURE_SOURCE   (fixed)
Sink nodes:        P_i = 0.0               (fixed)
```

Gauss-Seidel update for interior nodes only (S_i = 0 for all updated nodes):
```
P_i = Sum_{j ∈ N(i)} D_ij * P_j / Sum_{j ∈ N(i)} D_ij
```

This is a weighted average of neighbor pressures, weighted by conductance.
Intuition: a node's pressure is the conductance-weighted average of its neighbors.

**Do NOT apply this formula to source or sink nodes** — their pressures are fixed.

**Convergence criterion:** Iterate until max |P_i^new - P_i^old| < 0.001.
In practice: 25 iterations is sufficient.

---

## 4. Tube Adaptation (Tero 2007, Eq. 2)

The core adaptation equation:
```
dD_ij/dt = f(|Q_ij|) - γ * D_ij

Where f(Q) = |Q|^μ
```

In discrete form:
```
D_ij(t + dt) = D_ij(t) + dt * (|Q_ij(t)|^μ - γ * D_ij(t))
```

**Analysis:**
- Steady state: D* = (|Q|/γ)^(1/1) = |Q|/γ  (for μ=1)
- High flow → large D* → tube grows
- Low flow → small D* → tube shrinks
- Zero flow → D decays exponentially at rate γ

**Parameter sensitivity:**
- μ < 1: tree-like network (Steiner tree, no loops)
- μ = 1: shortest path behavior (our target)
- μ > 1: fault-tolerant network (multiple redundant paths)

---

## 5. Peristaltic Oscillation (Alim 2013)

Phase per edge advances uniformly:
```
φ_ij(t) = φ_ij(0) + ω * t   (mod 2π)
```

Effective conductance including oscillation:
```
D_eff_ij(t) = D_ij * (1 + A * sin(φ_ij(t)))
```

**Constraint:** A < 1 required to keep D_eff positive.
With A = 0.3: D_eff oscillates between 0.7*D and 1.3*D.

**Phase gradient (creates directed flow):**
For a tube of length L, the phase varies linearly:
```
φ(x, t) = ω*t + k*x + φ_0

Where k = 2π / λ (wave number)
λ = wavelength ≈ organism size (adapts automatically)
```

**Phase coupling (Kuramoto model):**
Adjacent edges synchronize their phases:
```
dφ_i/dt = ω + K * Sum_{j adjacent} sin(φ_j - φ_i)
```

With K = 0.1, this creates smooth traveling waves without forcing rigid phase patterns.

---

## 5b. Signal → Contraction Amplitude Feedback (Alim 2017)

Signal carried by flow increases local contraction amplitude, creating a positive feedback
loop: more signal → stronger contractions → faster flow → faster signal propagation.

Effective peristaltic amplitude at edge (i,j):
```
signal_avg_ij = (c_i + c_j) / 2
A_eff_ij = A_base + A_signal * signal_avg_ij
```

Then use A_eff_ij in place of A in equation 5:
```
D_eff_ij = D_ij * (1 + A_eff_ij * sin(φ_ij))
```

**Parameters:**
- A_base = 0.3   (base peristaltic amplitude, same as A in eq. 5)
- A_signal = 0.02  (signal coupling — Alim 2017)

**Phase dependency:** A_signal = 0 in Phases 1–2; activated in Phase 3.

---

## 6. Signal Advection (Alim 2017)

Continuous equation:
```
∂c/∂t = -v * ∂c/∂x + D_diff * ∂²c/∂x² + σ * food - δ * c
```

Where v = Q / (π * r²) ≈ Q * scale_factor (tube cross-section)

**Discrete upwind scheme:**
For each active edge (i→j) with Q_ij > 0 (flow from i to j):
```
Δc = dt * Q_ij * c_i
c_i -= Δc
c_j += Δc
```

**Diffusion (explicit scheme — discrete Laplacian, sum form):**
```
For each node i:
  c_i += dt * D_diff * Sum_{j ∈ N(i)} (c_j - c_i)
```
Note: use the SUM over neighbors, not the average. The average form reduces effective
diffusivity by 1/n (n = number of active neighbors) and does not correctly discretize ∇²c.

**Production at food sources:**
```
c_i += dt * σ * f_i / 255.0
```

**Decay:**
```
c_i *= (1 - dt * δ)
```

Parameters: D_diff = 0.01, σ = 5.0, δ = 0.005

---

## 7. Structural Memory / Softening Agent (Kramar & Alim 2021)

When food at node i is fully consumed:
```
s_i += S_burst   (= 50.0)
```

Softening agent advection: identical equations to signal advection,
but with slower decay (δ_s = 0.001 vs δ_c = 0.005).

Enhanced conductance growth in regions with softening agent:
```
D_ij(t+dt) = D_ij(t) + dt * (|Q_ij|^μ + α * s_avg_ij - γ * D_ij)

Where s_avg_ij = (s_i + s_j) / 2
      α = 0.1 (softening boost factor)
```

**Effect:** Tubes that previously carried flow to consumed food remain thicker
longer, biasing network toward previously-found food paths. This is memory.

---

## 8. Food Consumption

```
df_i/dt = -β * Flow_total_i * f_i / 255.0

Where Flow_total_i = Sum_{j ∈ N(i)} |Q_ij|
      β = 0.001 (consumption rate)
```

Discrete:
```
flow_total = Sum of |Q_ij| for all active edges at node i
f_i -= dt * β * flow_total * (f_i / 255.0)
f_i = max(0.0, f_i)
```

---

## 9. Calcium Coupling (Phase 4)

Calcium oscillates with the same period as peristalsis but with a spatial pattern:
```
Ca_i(t) = Ca_base + Ca_amp * sin(ω * t + position_phase_i)
```

Calcium modulates local contraction amplitude:
```
A_local_i = A_base * (1 + Ca_coupling * Ca_i)
```

This creates spatially varying contraction amplitude that interacts with
the peristaltic wave to generate complex, realistic-looking pulsing patterns.

---

## 10. Convergence Criteria

The network has converged to steady state when:
```
max_{all edges} |D_ij(t) - D_ij(t-10)| < 0.001
```

At convergence:
- Active edges form a spanning tree connecting all food sources
- Flow through each edge satisfies Kirchhoff's laws
- Conductance of each edge satisfies D* = |Q*|/γ
- Dead edges have D < D_min

---

## 11. Numerical Parameters Summary

```
dt = 0.1              — time step (stable for γ = 0.01)
GAUSS_ITER = 25       — pressure solver iterations
μ = 1.0               — feedback exponent (shortest path)
γ = 0.01              — conductance decay rate  
ω = 2π / 100          — oscillation frequency (100 tick period)
A_base = 0.3          — base peristaltic amplitude (A in Alim 2013)
A_signal = 0.02       — signal → amplitude coupling (Alim 2017; 0 in Phases 1–2)
K = 0.1               — Kuramoto phase coupling strength (Alim 2013)
D_0 = 0.01            — initial conductance (uniform)
D_min = 0.0001        — minimum conductance (below = dead)
D_max = 10.0          — maximum conductance cap
PRESSURE_SOURCE = 1.0 — fixed Dirichlet pressure at food source nodes (Dirichlet BC;
                        note: NOT the Tero I_0 current injection — different formulation)
σ = 5.0               — signal production rate
δ = 0.005             — signal decay rate
D_diff = 0.01         — signal diffusion coefficient (sum-form Laplacian)
α = 0.1               — softening boost
δ_s = 0.001           — softening decay rate
β = 0.001             — food consumption rate
```
