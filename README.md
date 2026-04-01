# slime-mold-zig

A real-time Physarum polycephalum (slime mold) simulation written in Zig, based on the agent model described in Jeff Jones' 2010 paper.

I kept seeing videos of slime mold behavior on TikTok — a single cell with no brain solving mazes, rebuilding the Tokyo subway, predicting the future sand had to build it myself.

![demo](assets/demo.gif)

## What is Physarum?

Physarum polycephalum is a single-celled organism with no brain or nervous system that can solve maze puzzles, find efficient network paths, and anticipate recurring events. Researchers recreated the Tokyo rail network by placing food sources at city positions — the mold optimized a nearly identical layout overnight.

This simulation models that behavior using thousands of particle agents that sense, rotate toward, and deposit a chemical trail — producing emergent network patterns from simple rules.

## How it works

Each tick of the simulation:

1. **Sense** — every agent samples the trail map at three points ahead (forward-left, forward, forward-right)
2. **Rotate** — the agent turns toward the strongest signal, with random jitter to break ties
3. **Move** — the agent steps forward and deposits trail at its new position
4. **Decay + Diffuse** — the trail map fades and blurs slightly, creating the soft glowing tendrils

No pathfinding algorithm. No global coordination. The network emerges from 10,000 agents following the same three rules.

## Build and run

Requires [Zig 0.14.0](https://ziglang.org/download/)
```bash
git clone https://github.com/camwillm/slime-mold-zig.git
cd slime-mold-zig
zig build run
```

## Parameters

All tunable constants live in `src/sim.zig` under `Sim`:

| Parameter | Default | Effect |
|---|---|---|
| `AGENT_COUNT` | 10,000 | More agents = denser networks |
| `SENSOR_ANGLE` | 0.4 rad | Wider angle = more exploratory |
| `SENSOR_DISTANCE` | 9.0 | How far ahead agents sense |
| `TURN_SPEED` | 0.3 | Higher = sharper turns |
| `MOVE_SPEED` | 1.0 | Agent velocity per tick |
| `DEPOSIT_AMOUNT` | 5.0 | Trail strength deposited |
| `DECAY_RATE` | 0.95 | How fast trail fades (0-1) |

## References

- Jones, J. (2010). *Characteristics of Pattern Formation and Evolution in Approximations of Physarum Transport Networks.* Artificial Life, 16(2), 127–153.
- Sage Jenson's GPU slime simulation — [cargocollective.com/sagejenson](https://cargocollective.com/sagejenson)