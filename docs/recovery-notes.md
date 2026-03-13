# Recovery Notes

## Recovery snapshot

- recovered from: `/data/SteamLibrary/steamapps/common/lucid-blocks/lucid-blocks/lucid-blocks.exe`
- recovered to: `work/recovered/lucid-blocks-20260313-100618`
- recovery log: `work/logs/recover-20260313-100618.log`

## GDRE output

- detected engine version: `4.6.0`
- detected bytecode revision: `4.5.0-stable (ebc36a7)`
- verified files: `5943`
- decompiled scripts: `318`
- failed scripts: `0`
- imported resources converted: `2754`

## Important early observations

- `project.godot` already contains a built-in autoload mod loader at `main/autoload/mod_loader.gd`.
- That loader scans `<game dir>/mods` and calls `ProjectSettings.load_resource_pack()` on every `.pck` file it finds.
- The game boots from `res://main/main.tscn`.
- There is an autoload `Steamworks` singleton and the shipped build includes `godotsteam`.

## First useful hook points

- `main/autoload/mod_loader.gd` - confirms the exact mod loading behavior
- `main/autoload/ref.gd` - central singleton references to `Main`, `World`, `Player`, UI, and save systems
- `main/main.gd` - overall game boot, load, quit, respawn, and dimension transitions
- `main/world/world.gd` - world startup, loading radius, simulation toggles, and decoration/block registration
- `main/entity/player/player.gd` - local input, interaction, block breaking, and movement logic
- `main/save_file/save_file_manager.gd` - save boundaries that a co-op mode will have to avoid corrupting

## Current blocker

- `bin/gdblocks.gdextension` only references Windows DLLs in this Steam build.
- This means the recovered project will not run directly in a native Linux Godot editor without either:
  - a Linux build of the extension, or
  - a Windows Godot editor setup under Wine/Proton using the shipped DLLs.

## Current proof of concept

- built test pack: `dist/lucid-blocks-coop-test.pck`
- installed via symlink to: `/data/SteamLibrary/steamapps/common/lucid-blocks/lucid-blocks/mods/lucid-blocks-coop-test.pck`
- override file: `mod/overrides/main/autoload/ref.gd`
- expected behavior: the game should print `[lucid-blocks-coop] Ref override loaded` during startup if the mod pack is being loaded.
