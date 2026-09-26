# WindyPeak Control

Modular Roblox automation project.

Current release: **v.191**

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

## Update rule

Growing data is kept outside Main.lua. UI/runtime temporary locals are scoped so the old single-file local-register limit does not accumulate the same way.

The repository must remain public for direct `game:HttpGet` raw GitHub loading without embedding credentials.
