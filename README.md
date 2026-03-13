# Lucid Blocks Co-op Mod

Initial workspace for a co-op mod built against the Steam release of Lucid Blocks.

## Current findings

- Steam app ID: `3495730`
- Steam library: `/data/SteamLibrary`
- Installed executable: `/data/SteamLibrary/steamapps/common/lucid-blocks/lucid-blocks/lucid-blocks.exe`
- Current Steam build ID: `22330271`
- Recovery snapshot: `work/recovered/lucid-blocks-20260313-100618`
- The Linux install is shipping a Windows executable plus Windows DLLs, so the game is running through Proton.
- No standalone `.pck` file is present next to the executable, so the Godot pack is likely embedded in the `.exe`.
- Official modding guidance points modders to `Godot 4.6 stable double` and `.pck`-based mods.
- GDRE recovered `5943` files and `318` scripts from the embedded pack.
- The main native `gdblocks` extension only ships Windows libraries in this build, so the recovered project will not open natively in a Linux Godot editor without extra work.

## Workspace layout

- `docs/` - notes, reverse-engineering targets, and roadmap
- `scripts/` - helper scripts for installing GDRE and recovering the project
- `mod/overrides/` - place for authored override files once the recovered project is understood
- `dist/` - exported mod packs
- `work/` - local-only extracted project, tool downloads, and logs

## Quick start

1. Install GDRE tools:

   ```bash
   ./scripts/install_gdre.sh
   ```

2. List files inside the embedded Godot pack:

   ```bash
   ./scripts/list_pck_files.sh
   ```

3. Recover the project into `work/recovered/`:

   ```bash
   ./scripts/recover_project.sh
   ```

4. Open the recovered project with the exact Godot version reported by GDRE. The official Lucid Blocks mod tutorial says to use `Godot 4.6 stable double`.

5. Build the current proof-of-concept mod pack:

   ```bash
   ./scripts/build_test_mod.sh
   ```

6. Install a built mod pack into the Steam copy:

   ```bash
   ./scripts/install_mod.sh
   ```

The current proof-of-concept mod overrides `res://main/autoload/ref.gd` and prints a startup line so there is a safe, minimal pack to iterate on.

## Co-op direction

The first playable target should stay small:

- 2 players
- host authoritative
- direct IP or LAN first
- synced player transforms
- synced block placement and breaking
- synced pickup and inventory events
- shared save separate from vanilla saves

The highest-risk unknown is whether world generation and critical gameplay systems are script-driven enough to patch cleanly from recovered `GDScript`, or whether too much logic lives in the native `libgdblocks` module.

See `docs/recovery-notes.md` for the first reverse-engineering notes and blockers.
