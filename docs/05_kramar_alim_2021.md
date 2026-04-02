# Kramar & Alim (2021) — PNAS 118:e2011289118
## "Encoding memory in tube diameter hierarchy"

### Discovery
Physarum has STRUCTURAL MEMORY.
Past food locations encoded in tube diameters.
Thick tubes persist after food gone and bias future behavior.

### How memory works
1. Food contact releases softening molecule
2. Soft walls expand under internal pressure
3. Tube widens
4. Wide tube persists even after food gone
5. Lower resistance path biases future network routing
6. Organism shaped by its history

### Softening agent model
dS/dt = production(food_contact) - decay*S - flow_advection
Tube width responds: dw/dt = S * pressure - elastic_restoring

### Rules for simulation
1. Food consumed at node → release softening agent S
2. S spreads by flow advection
3. Tubes exposed to S have higher conductance growth rate
4. Creates persistent thick tubes at past food locations
5. These bias future path selection

### Visual result
Old food locations leave scars — persistent thick bright tubes.
Even after food disappears, efficient path to it remains.
This is why Tokyo experiment worked.
