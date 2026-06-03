# Mini-King

A low-poly Roblox kingdom-builder. You're a royal child sent off to build your own
empire from scratch — balance food, clothing, security and Aura to attract peasants,
work the land for lumber/stone/gold, and out-build your siblings within a year.

See the full design in the project's `MiniKing.md`.

## Tech & workflow

- **Engine:** Roblox (Luau)
- **Sync:** [Rojo](https://rojo.space) — code lives here in `src/`, syncs into Studio.
  - Install Rojo, then `rojo serve` and connect from the Roblox Studio plugin.
- **Repo:** this is the source of truth; Studio is the renderer/test harness.

```
src/
  ReplicatedStorage/
    Config/      # Buildings.luau, GameConfig.luau  ← balance data (done first)
    Shared/      # types, utilities, remote definitions
  ServerScriptService/   # authoritative game logic (economy, population, combat)
  StarterPlayer/
    StarterPlayerScripts/ # client: placement UI, HUD, build/shop menus
```

Server is authoritative for all economy/state; client handles input and presentation.

## Build roadmap (proposed)

The game is large, so we build it as vertical slices — each one playable on its own.

1. **Foundation:** project scaffold + config data. ✅
2. **Grid & placement:** place/move/delete with footprint validation, server-authoritative. ✅
3. **Economy tick:** continuous per-minute production, storage caps (silo/warehouse
   multipliers + Manor floor), producer chains, XP, live HUD. ✅
4. **Population loop:** peasants arrive (Aura-paced) into housing, auto-fill jobs by
   priority, eat food + wear clothing, and leave when starved. Staffing now scales
   production. ✅
5. **HUD + Build/Shop menus:** real UI — player card (gold/XP/aura/pop), resources panel,
   right-side action buttons, building-card Build menu, Shop shell, and a Move/Delete
   context menu on placed buildings. (Thumbnails are placeholder swatches for now.) ✅
6. **Aura system:** computed from food volume/diversity, clothing, ruler presence, and
   storage waste; drives population growth (and military/cost multipliers once those
   exist). Security + neighbor relations stubbed until Phase 8. ✅
7. **Map & exploration:** 5000×5000 generation, stone/diamond outcroppings, discovery.
8. **Military & NPC villages:** training, waypoints/flags, combat, trade, conquest.
9. **Onboarding:** intro cutscene + guided first-build tutorial.
10. **Monetization:** gold packs / Robux (Buy screen).

## Decisions locked

- **Time is normalised to minutes** — no "days" in the economy. Food = 0.5/60 min,
  clothing = 0.1/300 min. Production accrues every `Economy.TICK_RATE` seconds so
  counters climb smoothly. Day/night (`GameConfig.DayNight`) is **cosmetic only**.
- **Everything is a dial.** Balance values live in `GameConfig` (Economy, Storage, Aura,
  Camera, DayNight) so feel can be tuned without touching logic.

## Known simplifications (revisit if needed)

- Resource stock is one aggregate number per resource (not per-building inventories).
  The doc's first-come-first-served filling and "destroying a building loses its
  contents" aren't simulated yet.
- Aura's *security* and *neighbor relations* inputs are stubbed neutral until military
  and NPC villages exist (Phase 8). Clothing now matters via Aura, as the design intends.
- Aura's military/cost multipliers are wired but only bite once military and building
  costs are defined.
- No persistence yet — state resets on rejoin.
