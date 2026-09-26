# WindyPeak Control

Modular Roblox automation project.

Current release: **v.196**

## Run

Keep this one short bootstrap in your executor:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/nattankon/ME.1/main/loader.lua?cb=" .. tostring(os.time())))()
```

When an update is published:
1. Press **Shutdown Script** in the UI.
2. Run the same bootstrap again.
3. The loader downloads the current manifest and modules automatically.

## Structure

- `loader.lua` — stable remote bootstrap.
- `manifest.lua` — current release and module paths.
- `modules/Config.lua` — version, combat timing, quest timing, loot timing.
- `modules/QuestData.lua` — quest definitions/order.
- `modules/BossData.lua` — boss definitions/order.
- `modules/WeaponData.lua` — weapon definitions/modes.
- `modules/Main.lua` — runtime engine and UI.

## Quest NPC waypoints

Roblox may not stream distant StationaryNpcs to the client. v.192 automatically learns and saves each quest NPC CFrame when that NPC is streamed once. On later joins/checkpoints, Start Quest Farm uses the saved waypoint to teleport into streaming range before accepting the quest.

The cache is stored locally as `WindyPeak/quest_npc_waypoints.json` when the executor supports `readfile/writefile`. A quest may also define `npcWaypoint = {x, y, z}` in QuestData.lua so a brand-new client can jump into streaming range before it has ever seen that NPC.

## Update rule

Growing data is kept outside Main.lua. UI/runtime temporary locals are scoped so the old single-file local-register limit does not accumulate the same way.

The repository must remain public for direct `game:HttpGet` raw GitHub loading without embedding credentials.


## v.195 farm height control

The Combat tab now includes **Farm Position → Head Hover Height**. It updates the vertical farm offset live while farming. Current default remains `Config.FARM_HEIGHT = 6`; once a preferred value is confirmed it can be changed in Config.lua.


## v.196 boss list

Added **Serpent Trainee** as a Boss Farm target.

- Region: `Misc`
- Target name: `Serpent Trainee`
- No quest definition is attached to this boss.
