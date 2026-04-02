# Nakagaki, Yamada, Tóth (2000) — Nature 407:470
## "Maze-solving by an amoeboid organism"

### What they did
Placed Physarum in a maze with food at two exits. Organism initially filled entire maze, then pruned to single tube connecting the two food sources via shortest path.

### Key finding
Organism solves shortest-path problems without brain or nervous system. Solution emerges from local tube dynamics alone.

### Mechanism
Tubes on shortest path carry more flow → thicken via positive feedback.
Dead-end tubes carry no flow → decay → pruning.

### Rules for simulation
1. Organism starts by FILLING all available space
2. Food sources create pressure differential
3. Flow reinforces tubes on efficient paths
4. Dead ends prune automatically from flow equations

### Visual result
Start: organism fills entire grid
Middle: network of tubes connecting food sources
End: minimal spanning tree, only efficient paths remain
