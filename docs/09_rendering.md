# Rendering — Visualizing the Network

## Core Concept

We are drawing a **network of tubes**, not a trail map.
The key visual elements are:
1. **Edges** as lines — thickness = conductance, color = flow state
2. **Nodes** as tiny points — only food sources and high-signal nodes are visible
3. **Peristaltic pulse** — brightness waves traveling along tubes
4. **Food sources** — pulsing glowing circles

---

## Canvas Setup

Two layered canvases:
```html
<canvas id="bg" style="position:absolute">     <!-- network, updated every frame -->
<canvas id="ui" style="position:absolute">     <!-- food dots, stats overlay -->
```

Grid scale: canvas_size / grid_size
If canvas = 800px, grid = 200: scale = 4 (each cell = 4×4 pixels)

---

## Edge Index → Node Coordinates

This is the critical mapping needed before any edge can be drawn.
Doc 07 gives the index formulas; here is the JS implementation:

```javascript
const W = 200, H = 200;
const HORIZ_COUNT = (W - 1) * H;  // 39,800
const SCALE = canvasWidth / W;    // 4 for 800px canvas

// Given edge index e, returns pixel coords of both endpoints
function edgePixels(e) {
    let x1, y1, x2, y2;
    if (e < HORIZ_COUNT) {
        // Horizontal edge: connects (x,y)↔(x+1,y)
        const y = Math.floor(e / (W - 1));
        const x = e % (W - 1);
        x1 = x * SCALE;      y1 = y * SCALE;
        x2 = (x+1) * SCALE;  y2 = y * SCALE;
    } else {
        // Vertical edge: connects (x,y)↔(x,y+1)
        const e2 = e - HORIZ_COUNT;
        const y = Math.floor(e2 / W);
        const x = e2 % W;
        x1 = x * SCALE;  y1 = y * SCALE;
        x2 = x * SCALE;  y2 = (y+1) * SCALE;
    }
    return [x1, y1, x2, y2];
}
```

Precompute and cache all `edgePixels(e)` results at init time (79,600 calls once).
Do not recompute per frame — it's pure geometry, never changes.

```javascript
// At init time:
const edgeCoords = new Float32Array(TOTAL_EDGES * 4);  // x1,y1,x2,y2 per edge
for (let e = 0; e < TOTAL_EDGES; e++) {
    const [x1,y1,x2,y2] = edgePixels(e);
    edgeCoords[e*4]   = x1;
    edgeCoords[e*4+1] = y1;
    edgeCoords[e*4+2] = x2;
    edgeCoords[e*4+3] = y2;
}
```

---

## Edge Rendering

### Per edge, every frame:

```javascript
const D = conductance[edgeIdx];
if (D < 0.002) continue;  // Skip invisible edges

const Q = flow[edgeIdx];
const φ = phase[edgeIdx];

// Line thickness from conductance
const lineWidth = Math.min(8, D * 4);

// Peristaltic brightness modulation
const pulse = 0.5 + 0.5 * Math.sin(φ);  // 0 to 1

// Flow direction tint
const flowAbs = Math.abs(Q);
const flowDir = Q > 0 ? 1 : -1;

// Base color: dark green → bright green → white as conductance increases
const greenBase = Math.min(255, 60 + D * 120);
const whiteMix = Math.min(255, D * 200);
const r = Math.floor(whiteMix * pulse);
const g = Math.floor(greenBase * pulse + whiteMix * 0.5 * pulse);
const b = Math.floor(whiteMix * 0.3 * pulse);
const a = Math.min(1.0, 0.3 + D * 0.7);

ctx.strokeStyle = `rgba(${r},${g},${b},${a})`;
ctx.lineWidth = lineWidth;

// Get pixel coordinates
const [x1,y1] = nodeToPixel(node_i);
const [x2,y2] = nodeToPixel(node_j);

ctx.beginPath();
ctx.moveTo(x1, y1);
ctx.lineTo(x2, y2);
ctx.stroke();
```

### Optimization — batching by thickness:
Group edges into buckets by lineWidth (0.5, 1, 2, 4, 8).
Draw each bucket as a single path with `ctx.beginPath()` / `ctx.stroke()`.
Reduces draw calls from 80,000 to ~5.

```javascript
const buckets = {0.5: [], 1: [], 2: [], 4: [], 8: []};

// Fill buckets
for edge in activeEdges:
    width = quantize(conductance[edge] * 4)
    buckets[width].push(edge)

// Draw each bucket
for ([width, edges] of buckets):
    ctx.lineWidth = width
    ctx.beginPath()
    for edge in edges:
        ctx.moveTo(...)
        ctx.lineTo(...)
    ctx.stroke()
```

---

## Node Rendering

Most nodes are invisible — only draw notable ones.

**Food source nodes:** Pulsing circle
```javascript
for food source node at (x, y):
    const strength = food[nodeIdx] / 255.0;
    const pulse = 0.7 + 0.3 * Math.sin(Date.now() / 400);
    const radius = 6 + 4 * pulse;
    
    const gradient = ctx.createRadialGradient(px, py, 0, px, py, radius * 2);
    gradient.addColorStop(0, `rgba(255, 255, 200, ${strength})`);
    gradient.addColorStop(0.4, `rgba(100, 255, 100, ${strength * 0.8})`);
    gradient.addColorStop(1, 'rgba(0, 100, 0, 0)');
    
    ctx.fillStyle = gradient;
    ctx.beginPath();
    ctx.arc(px, py, radius * 2, 0, Math.PI * 2);
    ctx.fill();
```

**High signal nodes:** Small dot
```javascript
for node i where signal[i] > 50:
    const alpha = signal[i] / 255.0;
    ctx.fillStyle = `rgba(200, 255, 100, ${alpha * 0.6})`;
    ctx.beginPath();
    ctx.arc(px, py, 2, 0, Math.PI * 2);
    ctx.fill();
```

---

## Color Palette

| State | Color |
|-------|-------|
| Dead edge (D < 0.002) | Not drawn |
| Thin active edge | rgba(0, 60, 0, 0.4) |
| Medium tube | rgba(20, 150, 20, 0.7) |
| Thick vein | rgba(100, 255, 100, 1.0) |
| Major highway (D > 5) | rgba(255, 255, 200, 1.0) — white-yellow |
| Food source | White center → green glow |
| High signal | Yellow-green dots |
| Flow positive direction | Slight blue tint |
| Flow negative direction | Slight red tint |

Background: `#000800` (very dark green-black)

---

## Peristaltic Wave Visualization

The traveling wave is the most visually distinctive behavior.
Each edge has a phase φ that advances at ω radians per tick.
Adjacent edges have slightly offset phases, creating a wave.

The wave should be visible as a bright spot moving along the tube.
Implement by modulating the green channel with sin(φ):

```javascript
const wave = 0.5 + 0.5 * Math.sin(phase[edgeIdx]);
const g = Math.floor(greenBase + wave * 80);  // +80 at wave peak
```

At default speed this wave travels at ~2 grid cells per tick, which looks like
smooth flow. At high conductance, the wave appears faster (thicker tubes pulse more visibly).

---

## Stats Overlay (bottom-left panel)

```javascript
// Updated every second (not every frame — expensive WASM calls)
const activeEdges = wasm.getActiveEdgeCount();
const maxD = wasm.getMaxConductance();
const avgFlow = wasm.getAvgFlow();

ctx.fillStyle = 'rgba(0,0,0,0.6)';
ctx.fillRect(10, canvas.height - 100, 200, 90);

ctx.fillStyle = '#00ff44';
ctx.font = '11px monospace';
ctx.fillText(`Active tubes: ${activeEdges.toLocaleString()}`, 20, canvas.height - 80);
ctx.fillText(`Max conductance: ${maxD.toFixed(3)}`, 20, canvas.height - 65);
ctx.fillText(`Avg |flow|: ${avgFlow.toFixed(4)}`, 20, canvas.height - 50);
ctx.fillText(`Food remaining: ${foodCount} / ${totalFood}`, 20, canvas.height - 35);
ctx.fillText(`${fps} fps`, 20, canvas.height - 20);
```

---

## Performance Budget

Target: 60fps on a mid-range laptop.

| Operation | Time budget |
|-----------|-------------|
| WASM step() call | ~8ms |
| Reading WASM memory | ~0.5ms |
| Edge drawing | ~3ms |
| Node drawing | ~0.5ms |
| Stats update (1/sec) | ~1ms |
| Total | ~13ms → 76fps theoretical |

If performance drops below 30fps:
1. Reduce grid to 150×150 (reduce edges by ~44%)
2. Skip edges with D < 0.005 (stricter threshold)
3. Reduce Gauss-Seidel iterations to 15
4. Reduce step calls per frame to 1 regardless of speed slider

---

## Debug Rendering Mode

Toggle with 'D' key:
- Show pressure field as heatmap overlay
- Show signal concentration as colored dots
- Show edge indices for selected node on hover
- Show flow direction as arrows (every 10th active edge)
