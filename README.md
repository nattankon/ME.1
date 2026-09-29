# WindyPeak Control

Modular Roblox automation project.

Current release: **v.228**  
Project status: **closed / waiting for new map**

## Run

Stable bootstrap:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/nattankon/ME.1/main/loader.lua?cb=" .. tostring(os.time())))()
```

After a published update:
1. Press **Shutdown Script**.
2. Run the same bootstrap again.
3. The loader downloads the current manifest/modules.

## Structure

- `loader.lua` — stable remote bootstrap.
- `manifest.lua` — release version and module paths.
- `modules/Config.lua` — shared timings/limits/version.
- `modules/QuestData.lua` — quest definitions/order.
- `modules/BossData.lua` — boss definitions/order/waypoints.
- `modules/BossRotation.lua` — multi-select rotation state.
- `modules/BossWaypoint.lua` — boss waypoint/streaming movement.
- `modules/WeaponData.lua` — weapon definitions/modes.
- `modules/FarmPosition.lua` — target-relative positioning.
- `modules/SkillAutomation.lua` — Z/X/C/V/B skill input rotation.
- `modules/Main.lua` — runtime engine/UI/controllers.

## Current production behavior

### Movement

Walk Speed is intentionally capped:
- Default: `41`
- Min: `16`
- Max: `41`
- Speed toggle default: OFF

This cap followed client/server snapback testing; the fast-movement investigation is closed.

### Farm Position

Modes:
- Above
- Below
- Front
- Back
- Above Front
- Above Back
- Below Front
- Below Back

Diagonal modes are normalized so Offset Distance stays the true distance.

### Auto Skill

Keys:
`Z -> X -> C -> V -> B`

Current policy:
- independent from normal combo,
- one skill attempt every `1.00s`,
- each key has its own `0.75s` retry gate,
- target must be alive, not down, within `10` studs,
- no movement or weapon-operation conflict.

### Quest Farm

Current quests:
- 3 Bandits - Krue
- Bandit Boss Lv7 - Krue
- Bear Cubs Lv10 - Tom
- Mother Bear Lv18 - Tom
- Hoyuzo Guards Lv40 - Wagwan
- Hoyuzo Lv50 - Wagwan

Quest progress trusts replicated quest UI/server state.

Quest NPC waypoint cache:
`WindyPeak/quest_npc_waypoints.json`

### Boss Farm

Boss selection is multi-select.

UI shows:
- `Rotation: A -> B -> C`
- `Current: B (2/3)`

Standalone:
- visit current boss,
- if not spawned, advance,
- kill -> optional loot -> next boss,
- wrap to first.

Quest compatibility remains:
Quest is primary; a selected spawned boss may temporarily override and Quest can resume afterward.

Boss waypoint cache:
`WindyPeak/boss_waypoints.json`

Current fixed-waypoint bosses include:
Serpent Trainee, Akazo, Kaiden, Obari, Thunder Trainee, Stone Trainee,
Gyorei, Zentaro, Tai Chi Trainee Suzume, Datai, Gyutai, Sumari, Yahari,
Hoyuzo, Reaper, Saneri, Shinora, Insect Trainee, Nezura, Fujiko,
Flame Trainee, Rengu, Water Trainee Sabito, Enru, Giyen.

Zuko and Mother Bear use live/learned behavior when no repo seed exists.

### Weapons

Auto Best:
`Thunder Katana > Cutlass > Fancy Katana > Regular Katana > Fist`

Current direct-combat katana family uses the verified Combat_Service path and katana timing table.
Main farming intentionally stops normal combo at hit 4.

### Respawn weapon preservation

v.225-v.226 changed respawn recovery:
- remember weapon held before death,
- keep internal weapon identity through respawn,
- clear character-local combat cache,
- do not redraw the same direct-combat weapon just because the character respawned.

This was based on a live reset test where Thunder Katana stayed equipped and could attack immediately after respawn without touching hotbar.

## Runtime coordination

Production invariants:
- one serialized external weapon operation,
- one explicit movement owner,
- heartbeat target lock pauses during explicit movement,
- Auto Buy cannot interrupt active combat/loot,
- stale respawn/loot work is generation-checked,
- same-weapon redraw is avoided on ordinary transitions.

See:
`RUNTIME_CONCURRENCY_AUDIT.md` in the local project workspace for the final audit.

## Release summary

- v.191 — modular migration.
- v.192-v.213 — quest/boss waypoint persistence, combat/hotbar fixes, runtime coordinator, boss checkpoint expansion.
- v.214 — Auto Skill Z/X.
- v.215 — Thunder Katana.
- v.216 — diagonal farm positions.
- v.217 — boss waypoint cancellation.
- v.218 — Hoyuzo Guards quest.
- v.219 — Hoyuzo quest.
- v.220 — Auto Skill C/V/B.
- v.221 — eight new bosses.
- v.222 — speed capped at 41.
- v.223 — skills decoupled from combo, 1 second cadence.
- v.224-v.226 — respawn weapon preservation fixes.
- v.227 — multi-boss rotation.
- v.228 — Water Trainee Sabito, Enru, Giyen.

## Closure

After v.228, the user received Error Code 267 with moderation message `Exploiting`.
The exact trigger was not isolated.

The user explicitly closed this WindyPeak project and asked to wait for a new map.

Do not continue old-map feature work unless the user explicitly reopens it.
