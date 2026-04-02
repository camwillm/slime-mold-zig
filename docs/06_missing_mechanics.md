# Missing Mechanics — What Current Sim Gets Wrong

## 1. Calcium oscillation NOT IMPLEMENTED
Real: Ca2+ oscillates in sync with contractions
Ca2+ rises → actomyosin contracts → tube narrows → flow increases elsewhere
Needed: Ca2+ value per node that oscillates and modulates contraction amplitude

## 2. Two timescale oscillations NOT IMPLEMENTED
Fast: 1-2 minute period (shuttle streaming, visible pulsing)
Slow: 20 minute period (amplitude modulation, net flow direction changes)
Slow oscillation is why organism appears to breathe or think

## 3. Flow-advected signaling NOT IMPLEMENTED
Current: food signal spreads only by diffusion
Real: signal travels WITH flow at 50x diffusion speed
Fix: implement upwind advection scheme for signal

## 4. Structural memory NOT IMPLEMENTED
Current: all tube thicknesses reset when food disappears
Real: tube diameter history encodes past food locations
Fix: softening agent released at food consumption, advected by flow

## 5. Active pruning vs passive decay WRONG
Current: tubes decay uniformly over time
Real: organism actively reabsorbs dead-end tubes
Cytoplasm flows back from dead ends and is reused

## 6. Organism starts FULL not empty WRONG
Current: organism grows from center outward
Real (Nakagaki 2000): organism fills entire space FIRST
THEN prunes to efficient network
The pruning IS the intelligence, not the growth

## Priority order
1. Graph network model with Tero 2007 equations (replaces particle sim)
2. Peristaltic oscillation per tube (Alim 2013)
3. Flow-advected signaling (Alim 2017)
4. Structural memory (Kramar 2021)
5. Calcium oscillation (long term)
