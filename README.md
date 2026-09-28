# WindyPeak Control

Modular Roblox automation project.

Current release: **v.221**

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

## v.205 smooth boss lock fix

The no-damage watchdog no longer force re-equips the weapon just because a boss took no damage for two combo cycles. Some bosses can block or ignore damage briefly while the weapon is still correctly drawn, and the old watchdog caused the repeated drop-to-ground / redraw loop.

Now:
- If the weapon is still actually drawn, keep the current target lock and continue attacking.
- Only force a weapon recovery when the weapon is genuinely no longer drawn.
- Recovery count now increments only for a real weapon-state recovery.

## v.207 quest farm busy-lock fix

Live testing showed Quest Farm could remain forever at `Ready to accept` after two weapon sync operations overlapped. The old sync function restored the weapon-busy flag to the value it saw on entry, so a second overlapping call could leave `weaponBusy = true` permanently and block the quest accept controller.

v.207 changes:
- Weapon sync operations are serialized instead of overlapping.
- The busy flag is always released after a sync, including on Lua errors.
- Weapon purchase uses an internal unlocked sync while it already owns the weapon lock.
- Quest acceptance can resume normally once the weapon operation completes.

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


## v.206 stable farm core

This release separates target-lock/combat flow from visual weapon recovery to restore the earlier smooth farming behavior.

- Direct-combat weapons can continue sending their verified combat remote while locked, matching the stable pre-v203 behavior.
- The combat watchdog no longer equips/re-equips weapons.
- A decrease in either Humanoid health or the NPC `BlockPoints` attribute counts as real combat progress.
- Visual hotbar recovery is debounced for 2 seconds and handled only by the Auto Weapon controller.
- Auto Best weapon upgrades still switch immediately.
- Respawn recovery still returns to the saved boss waypoint and rebuilds the weapon once.


## v.208 runtime coordinator and detailed status

This release audits the concurrent controllers and prevents the main known overlap paths.

- All external weapon equip/sync work now goes through one serialized weapon operation.
- Weapon-operation errors always release the busy flag.
- Explicit movement operations use one movement owner: Quest NPC warp, Boss waypoint warp, Boss Loot, and Auto Buy shop travel.
- Heartbeat target locking pauses while another movement operation owns the character.
- Quest/Nearby/Boss Farm no longer shut themselves off because one hotbar initialization attempt failed.
- Auto Buy cannot interrupt a live target, Boss override, Boss Loot, or another movement operation; it is also skipped when Cutlass is already owned.
- Boss Watch is passive when Quest Farm is enabled so its waypoint warp does not pull the character away from the quest.
- Boss selection changes during loot are deferred instead of competing with chest/drop movement.
- Respawn recovery is generation-checked; Quest Farm has movement priority over Boss Watch after respawn.
- Quest accept/progress, Boss monitor, and Auto Weapon controllers recover from transient Lua errors instead of permanently losing their worker thread.
- Status now shows farm phase, quest flags/UI/cooldown, boss spawn/override/loot/passive state, target HP/BlockPoints/distance/down state, weapon mode/drawn/direct/cache/busy state, combo/lock/position, movement/weapon operation owners, character/target generations, watchdog stalls, and the most recent runtime event.


## v.209 continuous farm transition flow

This release restores the earlier continuous behavior by separating **weapon changes** from **farm transitions**.

- Starting Quest / Nearby / Boss Farm no longer force-redraws the same weapon.
- Quest acceptance verification no longer force-redraws the same weapon.
- During an active farm, Auto Weapon only equips when the desired weapon actually changes.
- Respawn remains the normal forced re-equip point.
- Boss detection immediately switches the target and lets the heartbeat lock onto the boss without a weapon redraw.
- Before a boss override, Quest Farm stores the current farming position.
- After boss loot finishes, Quest Farm returns to that saved position so quest targeting can resume immediately.
- The status panel now shows the stable equip policy and whether a boss-resume point is stored.


## v.210 captured boss spawn seeds

Added fixed boss spawn waypoint seeds from the user's Properties screenshots. These are used before live boss locking when the boss is not streamed yet.

Seeded from screenshots:
- Serpent Trainee: {-19.5, 3, -88}
- Akazo: {-85.584, 3, 66.23}
- Kaiden: {-315.85, 3.024, 30.55}
- Obari: {0, 0, 0}
- Thunder Trainee: {-19.5, 3, -88}
- Stone Trainee: {2516.21, 1134.774, -475.6}
- Gyorei: {-55.7, 3, 85.838}
- Zentaro: {-75.164, 3, 34.914}

Zuko and Mother Bear remain on learned/live waypoint behavior until an exact spawn Properties position is available.


## v.211 safe-air boss streaming

Boss spawn waypoint travel now uses a safe-air streaming stage when the live boss root is not available yet.

- Warp to the fixed boss spawn waypoint at +60 studs.
- Hold that exact air position while the destination streams.
- Zero linear/angular velocity during the hold so gravity or knockback cannot drop the character through unloaded terrain.
- Poll for the live boss root every 0.05s for up to 4 seconds.
- As soon as the boss root appears, switch immediately to the normal live boss lock at the configured farm offset.
- If the boss is already streamed, skip the air-hover stage entirely.


## v.213 final captured spawn checkpoints

Updated the two remaining existing boss spawn checkpoints from HumanoidRootPart CFrame screenshots:
- Kaiden: {581.227, 1148.984, -1316.309}
- Serpent Trainee: {-269.851, 1294.5, -1534.159}


## v.214 auto skill Z/X

Added two optional Auto Skill toggles in the Combat tab:
- Auto Skill Z
- Auto Skill X

Behavior:
- Skills are only attempted while a farm target is alive, not downed, and within 10 studs.
- One skill key is attempted between completed normal attack combos.
- Z and X alternate when both are enabled.
- Each key has a 0.75 second retry gate to avoid input spam while the game handles its own cooldown.
- Skill input uses VirtualInputManager key events.
- Skill state and the last attempted key are shown in Status.


## v.215 Thunder Katana

Added Thunder Katana as the new highest Auto Best weapon from the captured live data.

Captured weapon data:
- Toolbar index: 63
- Inventory Id: 63
- Held state: `Thunder KatanaEquipped`
- Tool model: `Thunder Katana`
- Combat_Service alias: `Regular Katana`
- Combo timings: 1=.125, 2=.065, 3=.065, 4=.1, 5=.075
- Item card: Legendary, +1.5 Additional Damage, 1.04x Additional Damage Factor, +1 Block Point, 1.08x Movement Speed Factor, 1.07x Stamina Regen Speed

Auto Best priority:
Thunder Katana > Cutlass > Fancy Katana > Regular Katana > Fist


## v.216 diagonal farm positions

Added four new farm-position modes:
- Above Front
- Above Back
- Below Front
- Below Back

The diagonal offset is normalized before applying the selected distance, so the existing Offset Distance slider still represents the actual distance from the target.

## v.217 boss warp cancellation

Fixed Boss Farm movement continuing briefly after **Watch Boss Spawn** is turned off.

- Boss waypoint streaming waits now receive a cancellation callback from Main.
- Turning Boss Farm off cancels the active saved-waypoint / safe-air hold on the next stream tick instead of continuing to re-apply the old boss CFrame.
- A cancelled startup warp no longer continues into the normal `Watching: <boss>` state.

## v.218 Hoyuzo guards quest

Added **Hoyuzo Guards Lv40 - Wagwan** to Quest Farm.

- NPC: Wagwan / Bamboo Grove.
- Quest remote text: `I will clear out his guards(Lv 40)`.
- Target: `Hoyuzo Subordinate` / Bamboo Grove.
- Required kills: 4.
- Quest panel: `Clear Hoyuzo's Guard`.
- Added Wagwan NPC waypoint seed: `{723.762, 1021.697, -801.984}`.

## v.219 Hoyuzo boss quest

Added **Hoyuzo Lv50 - Wagwan** to Quest Farm.

- NPC: Wagwan / Bamboo Grove.
- Quest remote text: `I will take care of Hoyuzo(Lv 50)`.
- Target: `Hoyuzo` / Bamboo Grove, matching the existing BossData target.
- Required kills: 1.
- Quest panel: `Defeat Hoyuzo`.
- Reuses the existing Wagwan NPC waypoint seed.

## v.220 auto skill C/V/B

Extended Auto Skill with three additional keys:

- Auto Skill C
- Auto Skill V
- Auto Skill B

All five supported skills now share the existing farm-target/range checks and rotate through enabled keys in the order Z -> X -> C -> V -> B. Each key keeps its own retry gate.

## v.221 boss list expansion

Added eight Boss Farm targets with captured HumanoidRootPart waypoint seeds:

- Reaper / Misc: `{97.011, 1045.5, -573.736}`
- Saneri / Misc: `{-379.108, 1095.905, -422.421}`
- Shinora / Misc: `{-453.71, 966.999, -5.109}`
- Insect Trainee / Misc: `{-1396.103, 264, 66.274}`
- Nezura / Misc: `{-1456.823, 278.45, 937.317}`
- Fujiko / Final Selection Plains: `{-2458.743, 40.354, 1118.262}`
- Flame Trainee / Misc: `{-1126.897, 1031.548, 1000.671}`
- Rengu / Misc: `{-710.026, 967.499, 881.654}`

## v.222 speed cap

Locked the Movement tab Walk Speed control to the tested stable range:

- Default Walk Speed: `41`
- Maximum Walk Speed: `41`
- Minimum remains `16`
- Speed toggle remains off by default.

## v.223 independent auto skill cadence

Auto Skill no longer waits for the normal attack combo to finish.

- Enabled skills rotate in the existing order: Z -> X -> C -> V -> B.
- One skill attempt is made every 1.00 second while combat conditions remain valid.
- Existing checks remain: active farm target, target alive/not downed, within 10 studs, no weapon operation, no movement lock, and Quest Farm not accepting/moving.
- The existing per-key 0.75 second retry gate remains in place.

