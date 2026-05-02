# EcoSim

A real-time ecological simulation built in [Processing](https://processing.org/). A procedurally generated world is populated with herbivores, carnivores, and plants. Every creature runs its own energy-driven state machine, reproduces sexually with trait inheritance and mutation, and responds to terrain, predators, and territory. The simulation is designed to run as a live backdrop during a presentation — the population graph, HUD, and creature states all update in real time and can be manipulated without pausing.

---

## Quick Start

1. Open the `main/` folder as a Processing sketch.
2. Press the **Run** button (or Ctrl+R / Cmd+R).
3. Use the controls below to navigate and interact.

---

## Controls

| Key | Action |
|---|---|
| `Arrow keys` | Pan the camera |
| `R` | Toggle detection-range rings |
| `P` | Pause / resume |
| `G` | Toggle population graph |
| `A` / `D` | Cycle manual spawn type (Herbivore → Carnivore) |
| `Space` | Spawn selected type at the mouse cursor |

---

## The World

The map is a **200 × 200 unit grid** rendered through a scrolling camera viewport. Terrain is generated fresh each run using Perlin noise, producing four biome types:

| Tile | Color | Notes |
|---|---|---|
| Grassland | Light green | Primary habitat; plants spawn here |
| Brush | Dark green | Secondary habitat; plants spawn here |
| Water | Blue | Impassable; creatures steer around it |
| Rock | Grey-tan | Passable but no plants |

Plants never spawn adjacent to water or inside lairs, which keeps food sources away from the most dangerous areas.

---

## Creature Types

### Herbivores (blue triangles)

Herbivores are the prey population. They have moderate speed, low metabolism, and short detection range. Their priority order each frame is:

1. **Avoid lairs** — flee any lair center within radius + 2.5 units
2. **Flee predators** — if a carnivore is closer than the nearest food source
3. **Reproduce** — seek the nearest energy-ready mate
4. **Seek food** — move toward the nearest plant outside all lairs
5. **Wander** — default random movement

When a herbivore population drops below **30 alive**, new herbivores begin spawning in from the map edges. The batch size scales with how far below the threshold the population is (1 creature per 5 below, capped at 6 per batch), and batches fire every 2 seconds. This prevents full extinction while keeping pressure on the ecosystem.

### Carnivores (red or orange triangles)

Carnivores are territory-holding predators. Each one belongs to one of two lairs and will never mate with a creature from the other lair. Their priority order is:

1. **Guard duty** (guards only) — hold a fixed post; hunt enemies and herbivore intruders on sight
2. **Hunt enemy carnivores** — if a rival-lair predator enters the territory zone
3. **Defend lair** — kill herbivores that have wandered inside
4. **Return to lair** — if energy is above 85%, head home to hibernate
5. **Hibernate** — rest inside the lair at 30% of normal metabolism until energy drops below 45%
6. **Reproduce** — seek a same-lair mate outside the lair
7. **Chase prey** — hunt herbivores within the current roam radius (or anywhere if hunger > 70%)
8. **Roam** — patrol within an energy-scaled radius; the lower the energy, the farther they wander

---

## Territory System

Two carnivore lairs spawn each run on opposite sides of the map — far enough apart that only a hungry, wide-roaming predator could realistically reach the other side.

| Lair | Creature color |
|---|---|
| Lair 1 | Red tones |
| Lair 2 | Orange tones |

Each lair has:
- A **rest zone** (inner circle) — where hibernating creatures recover
- A **territory zone** (outer circle) — any enemy carnivore inside this radius is attacked on sight
- **Two permanent guards** — pinned to flanking posts, full energy at all times, first responders to intrusions
- A **resident cap of 5** non-guard carnivores; the strongest occupants are evicted first when overcrowded

Creatures remember their allegiance across generations — offspring inherit the lair index of their parent.

---

## Hibernation and Roam Radius

Carnivores cycle through a rest-and-hunt loop driven entirely by energy:

```
Energy > 85%  →  RETURN to lair
Inside lair, energy > 45%  →  HIBERNATE (metabolism × 0.30)
Energy < 45%  →  leave lair, begin roaming

Roam radius = lerp(80, 20, energy / maxEnergy)
  → Full energy: radius 20 units  (stays near lair)
  → Near death:  radius 80 units  (hunts far out)
```

This means well-fed predators are practically invisible near their lair while starving ones fan out aggressively, creating natural boom-bust hunting pressure.

---

## Reproduction and Evolution

Both species reproduce sexually. When a creature's energy reaches the **75-unit threshold** it enters REPRODUCE state and seeks the nearest eligible partner.

- Both parents each spend **25 energy** on birth
- The offspring spawns at the midpoint between parents
- Stats are averaged between parents, then mutated ±8%: metabolism, max speed, max force, and detection range all drift each generation
- Offspring inherit the lair allegiance of parent A (carnivores only)

Over time, populations can evolve toward faster or more efficient variants depending on which traits survive.

---

## HUD Reference

The top-left overlay shows live simulation state:

```
Herbivores alive : N   (births: N   edge: N)
Carnivores alive : N   (births: N)
Plants           : N
Lair 1: N  |  Lair 2: N
Herbivore avg:  spd:0.000  met:0.000  det:0.0
Carnivore avg:  spd:0.000  met:0.000  det:0.0
Camera: (x, y)
Repro threshold: 75  |  Cost: 25 / parent
Herb edge-spawn threshold: 30
Hibernate: return >85% energy, exit <45%
```

The **population graph** (bottom-right, toggle with G) plots the last 300 frames of herbivore (blue) and carnivore (red) counts on a shared auto-scaling axis.

The **spawn indicator** (bottom-left) shows the currently selected manual spawn type.

---

## Creature Visual Reference

| Symbol | Meaning |
|---|---|
| Blue triangle | Herbivore |
| Red triangle | Lair 1 carnivore |
| Orange triangle | Lair 2 carnivore |
| White triangle | Guard (any lair) |
| Dark faded triangle | Dead creature (corpse) |
| `♥` above creature | Currently in REPRODUCE state |
| `Z` above creature | Currently HIBERNATING |
| Small bar below | Energy bar (full = bright, empty = dark) |
| State label | Current AI state (WANDER, CHASE, FLEE, etc.) |

---

## State Machine Labels

| Label | Species | Meaning |
|---|---|---|
| `WANDER` | Both | Default random movement |
| `SEEK` | Herbivore | Moving toward a plant |
| `FLEE` | Herbivore | Running from a carnivore |
| `AVOID_LAIR` | Herbivore | Fleeing a lair perimeter |
| `REPRODUCE` | Both | Seeking a mate |
| `CHASE` | Carnivore | Pursuing prey |
| `ROAM` | Carnivore | Patrolling territory at current roam radius |
| `RETURN` | Carnivore | Heading back to lair (high energy) |
| `HIBERNATE` | Carnivore | Resting in lair (slow metabolism) |
| `GUARD` | Carnivore | Holding a fixed sentinel post |
| `DEFEND` | Carnivore | Chasing herbivore intruder inside lair |
| `HUNT_ENEMY` | Carnivore | Chasing a rival-lair predator |
| `LEAVE_LAIR` | Carnivore | Exiting lair (evicted or energy threshold met) |
| `DEAD` | Both | Creature has died; corpse remains briefly |

---

## Configuration Constants

All tuning values are at the top of their respective files and can be changed without touching logic code.

**world.pde**

| Constant | Default | Effect |
|---|---|---|
| `MAX_HERBIVORES` | 120 | Hard cap on alive herbivores |
| `MAX_CARNIVORES` | 50 | Hard cap on alive carnivores (both lairs combined) |
| `MAX_CORPSES` | 30 | Max dead creatures kept before pruning |
| `HERB_SPAWN_THRESHOLD` | 30 | Below this, edge spawning activates |
| `HIBERNATE_RETURN_THRESHOLD` | 0.85 | Energy fraction that triggers return-to-lair |
| `HIBERNATE_EXIT_THRESHOLD` | 0.45 | Energy fraction that ends hibernation |
| `ROAM_RADIUS_MIN` | 20 | Roam radius at near-full energy |
| `ROAM_RADIUS_MAX` | 80 | Roam radius at near-zero energy |

**main.pde** (initial spawn counts)

| Variable | Default |
|---|---|
| `initHerbivore` | 70 |
| `initCarnivore` | 30 |
| `initPlant` | 120 |

---

## File Structure

```
main/
├── main.pde        Entry point — setup(), draw(), keyPressed()
├── world.pde       World state, terrain, update loop, spawning, HUD, graph
├── creatures.pde   Creature class — state machines, steering, drawing
├── systems.pde     LifecycleSystem — energy, stats, reproduction, crossbreeding
└── camera.pde      Viewport — pan, visibility check, world-to-screen coords
```

---

## Credits

- Map terrain and water avoidance — Rikesh
- Perception system — Mansa
- Lifecycle, reproduction, territory, and lair systems — team collaboration
