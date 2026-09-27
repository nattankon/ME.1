# WindyPeak Control

Modular Roblox automation project.

Current release: **v.204**

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

## v.200 hotbar refresh fix

Forced weapon initialization now re-sends `Toolbar_Equip` even when the selected weapon name has not changed. If the first real-click draw still fails, slot 2 is rebuilt once more before the equip is considered failed. This targets the stale-hotbar state seen when starting Quest Farm after the game has sheathed/rebuilt the weapon slot.

## v.203 boss combat/respawn recovery

Live testing showed two separate stale states: the script could consider a direct-combat weapon ready while the game had actually sheathed it, and a player respawn could leave Boss Farm enabled without returning to the saved boss area.

v.203 changes:
- Direct-combat readiness now requires the weapon to be actually drawn.
- A temporary hotbar draw failure no longer disables Boss Farm; the Auto Weapon recovery loop keeps retrying.
- When the player respawns while Boss Farm is enabled, the script warps back to the selected boss waypoint, resets the boss scan, and force-initializes combat again.
- Status now shows `Drawn: true/false` next to the current weapon.

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


## v.197 boss list

Added **Akazo** as a Boss Farm target.

- Region: `Misc`
- Target name: `Akazo`
- No quest definition is attached to this boss.


## v.198 boss list

Added **Kaiden** as a Boss Farm target.

- Region: `Bamboo Grove`
- Target name: `Kaiden`
- No quest definition is attached to this boss.


## v.199 boss list

Added **Obari** as a Boss Farm target.

- Region: `Misc`
- Target name: `Obari`
- No quest definition is attached to this boss.


## v.201 boss list

Added four Boss Farm-only targets from the `Misc` region:

- `Thunder Trainee`
- `Stone Trainee`
- `Gyorei`
- `Zentaro`

No quest definitions were added for these four bosses.


## v.202 boss waypoints

Boss Farm now mirrors Quest Farm startup behavior:

- Every streamed boss is learned automatically and saved locally.
- Saved data is stored in `WindyPeak/boss_waypoints.json` when file APIs are available.
- Starting Boss Farm first warps to the selected boss's live/saved point, then initializes combat and begins watching.
- Changing the selected boss while Boss Farm is enabled also warps to that boss's saved area.
- If a boss has never been streamed before and has no saved point yet, Boss Farm still starts but logs that the boss must be seen once so its waypoint can be learned.


## v.204 farm position modes

Combat → Farm Position now supports four live target-relative positions:

- `Above` — stay above the target.
- `Below` — stay below the target, including underground when the map permits it.
- `Front` — stay in front of the target based on its facing direction.
- `Back` — stay behind the target.

The existing distance slider is now labeled `Offset Distance` and controls the spacing for all four modes. Default mode remains `Above`.
