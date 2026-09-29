# Notch effects: a black hole, and a Solar System world

Date: 2026-09-29
Status: sketches approved in chat ("looks good. now implement in ambient"); spec awaiting review
Builds on: `2026-09-29-living-wallpaper-design.md` (branch `feat/living-wallpaper`)

## Problem

The island opens when the pointer reaches the notch. The living wallpaper doesn't react to that yet: the
moment you ask Ambient what your agents are doing, the world they live in should answer too.

## Goal

When the island opens, the wallpaper plays out real physics centred on the notch; when it closes, the scene
recovers. There are two effects:

- **Black hole.** Used in Sky, Harbor and Garden. The notch collapses into a black hole, the agents are flung
  into orbits around it, and loose dust falls in. When the island closes, gravity switches off and everything
  drifts home.
- **Solar System.** A new, fourth world. With the island closed, agents are planets standing in rows. With it
  open, the notch is the sun and up to six planets orbit it.

The island's menu stays exactly as it is, in front of both effects.

Non-goals: effects on the lock screen, which has no island; effects on displays without the island; changes to
the island or its menu.

## Decisions (from the sketch rounds)

| Topic | Decision |
| --- | --- |
| Where the hole/sun sits | Centred on the notch's bottom edge; its diameter is the notch width, so only its lower half shows |
| Menu | Unchanged, drawn by the island above the wallpaper. The hole/sun sits behind it; orbits are sized to run around it |
| Black hole look | Black shadow, bright photon ring, accretion disk along the notch line (brighter on the approaching side), lensed far side of the disk under the hole, gravity-sheet grid bending into a well (only while open, fading with distance), birth flash and a gravitational wave rippling through the sheet |
| Black hole motion | Inverse-square gravity. At birth each agent gets the sideways speed of a Kepler ellipse released at its far point, with its closest pass ≥ 1.9 × the hole radius (never swallowed). Dust gets random speeds: some orbits, some spirals in (disk friction near the hole), stretches along its fall and reddens, and is swallowed at the horizon. On close, gravity switches off: bodies coast on their momentum, then a weak pull and drag bring them home. Swallowed dust fades back in |
| Solar closed | Planets in rows across the sky: one row up to 4, two centred rows beyond 4. Labels sit centred under each planet |
| Solar open | The notch ignites into the sun (corona, flares). The six most urgent agents orbit (needs you › failed › working › done › idle; most urgent innermost). Orbits are eccentric Kepler ellipses (e = 0.45) with the sun at a focus and the far point at the bottom, so planets drift across the lower screen and race round behind the sun. A lap takes ~8 s inside and ~18 s outside. Each planet joins its orbit at the point nearest its row slot. Agents beyond six fall into the sun and are swallowed. An asteroid belt turns between the middle orbits |
| Solar close | The sun dims. Swallowed planets re-emerge from it, and every planet flies to its slot in the rows on a critically damped spring, arriving with momentum |
| Light and dark | Both effects follow the scene's time of day: the light look by day (pale sky, dark ink, deeper amber and red), the dark look at dawn, dusk and night. The hole and the island menu stay black |
| How agents look during the black hole | They lift off as light: an orb in the agent's colour with its mood glow, trailing its path. The world's body for it (boat, plant stem) fades out as it leaves home and fades back in when it settles |

## Design

### Units

AmbientCore (pure, deterministic, unit tested):

| Unit | Job |
| --- | --- |
| `NotchSimulation` | The physics for both effects in screen points: bodies (agents and dust), open/close, fixed-step integration (≤ 4 ms per step, any frame rate), birth wave, absorption, return home. Outputs a frame: per-agent position, scale, visibility, speed; dust; hole/sun radius and growth; wave radius |
| `SolarLayout` | Row slots for N planets (1 or 2 centred rows), orbit assignment (six most urgent, innermost first), Kepler ellipse radius and angular speed |
| `SceneKind.solar` | The fourth world; "A new one each day" rotates through all four |

AmbientApp:

| Unit | Job |
| --- | --- |
| `NotchEffectLayer` | A `Canvas` between the scene's life layer and its text: draws the hole or sun, disk, rings, sheet, wave, dust, orbs and trails from the simulation frame |
| `SolarScene` | The Solar System world's renderer (sky by phase, closed rows); its open state is drawn by `NotchEffectLayer` |
| `IslandController` | Publishes whether the island is open, and the expanded menu size |
| `LivingWallpaper` | Feeds island state, notch geometry and menu size to the simulation on the desk layer of the island's display; runs it while it moves |
| `SceneTextLayer` | Labels follow the simulated positions while an effect runs; hidden while a body is swallowed or behind the sun |

### Data flow

```
IslandController ── open/closed, menu size ──┐
IslandGeometry ──── notch rect ──────────────┼─▶ LivingWallpaper ─▶ NotchSimulation (step per frame)
SceneState ──────── inhabitants, homes ──────┘                         │
                                                                       ▼
                                   SceneView: scenery ▸ life ▸ NotchEffectLayer ▸ text (labels at simulated positions)
```

### Running it

- It runs only on the desk layer of the display that has the island, and only while the wallpaper is visible
  there.
- While an effect moves (open, or settling after close), the life and effect layers run at 60 fps. They return
  to the normal rate once every body is home.
- **Reduce Motion:** no bodies move. The hole or sun fades in and out behind the menu, and planets stay in their
  rows.
- **Low Power Mode:** no effect.
- **Setting:** "When the island opens" in the Wallpaper pane: *Black hole* (default) or *Nothing*. It applies to
  Sky, Harbor and Garden; the Solar System world always lights its sun.

### Error handling

The simulation is pure, and its inputs are clamped: no bodies, a zero-size screen or a missing notch mean no
effect. A frame the simulation can't produce leaves the scene exactly as it is without the effect.

## Testing

Unit tests for `NotchSimulation` and `SolarLayout`:

- **Kepler:** the period ratio of two circular orbits matches (a₁/a₂)^1.5 within 2 %, and eccentric orbits
  keep their far point at the bottom.
- **Black hole:** over 20 simulated seconds no agent comes closer than 1.5 × the hole radius; dust inside the
  horizon is absorbed; after close, every agent is within 2 pt of home by 6 s.
- **Solar:**
  - six orbit and the rest are absorbed within 3 s;
  - the most urgent get the innermost orbits;
  - each joins at the angle nearest its slot;
  - after close, all are within 2 pt of their slots by 4 s.
- **Rows:** 1–4 planets make one row; 5–10 make two centred rows; every slot fits on screen.
- **Determinism:** the same seed and the same steps give the same frames.
- **Frame rate:** the same simulated time gives the same result at 12, 30 and 60 fps (within tolerance).

Manual checks (offscreen harness renders, then the real app):

- both effects, dark and light;
- 4 and 10 agents;
- the menu in front;
- CPU while the effect runs and after it settles;
- Reduce Motion;
- Low Power Mode.

## Tasks

1. Core: `NotchSimulation` (black hole) with its tests.
2. Core: `SolarLayout` and the solar mode of `NotchSimulation`, with their tests; `SceneKind.solar`.
3. App: `IslandController` publishes its state; `LivingWallpaper` drives the simulation; the 60 fps window.
4. App: `NotchEffectLayer` for the black hole; labels follow bodies.
5. App: `SolarScene` and the solar drawing in `NotchEffectLayer`; the Scene picker and daily rotation include it.
6. App: the "When the island opens" setting, Reduce Motion and Low Power Mode, dark and light, docs.
