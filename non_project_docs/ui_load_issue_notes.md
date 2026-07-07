# UI Load Issue Notes

Date: 2026-07-07

## Symptom

Battle UI failed to load after adding two new UI textures:

- `assets/art/ui/discard_button.png`
- `assets/art/ui/ap_orb_full.png`

The real error from the console Godot binary was:

```text
ERROR: Unable to open file: res://.godot/imported/ap_orb_full.png-8922533d6707cc62da6a2343eef7d669.ctex.
ERROR: Failed loading resource: res://assets/art/ui/ap_orb_full.png.
SCRIPT ERROR: Parse Error: Could not preload resource file "res://assets/art/ui/ap_orb_full.png".
ERROR: res://scenes/battle_scene.tscn:129 - Parse Error: [ext_resource] referenced non-existent resource at: res://assets/art/ui/discard_button.png.
```

## Root Cause

The new PNG assets had `.png.import` sidecar files, but the local Godot import cache did not contain the matching generated `.ctex` files under `.godot/imported/`.

Godot script preload and scene `ExtResource` loading followed the `.png.import` remap to these missing files:

- `.godot/imported/ap_orb_full.png-8922533d6707cc62da6a2343eef7d669.ctex`
- `.godot/imported/discard_button.png-4e3280be848b83b05212299b833203f4.ctex`

Because `.godot/` is intentionally git-ignored, those cache files must be generated locally by Godot import. Committing `.png.import` is necessary, but it does not by itself create the local `.ctex` cache.

## Fix

Run a real Godot import pass with the console binary:

```powershell
& "D:\deep_learning_tool\godot\Godot_v4.6.3-stable_win64_console.exe" --headless --disable-crash-handler --log-file "tmp\godot_import.log" --path "D:\py_work\my-deck" --import
```

This generated:

- `.godot/imported/ap_orb_full.png-8922533d6707cc62da6a2343eef7d669.ctex`
- `.godot/imported/discard_button.png-4e3280be848b83b05212299b833203f4.ctex`

The project still keeps only the source PNG and `.png.import` files in version control; `.godot/` remains ignored.

## Verification

After import, the battle scene loaded, deployed all player units, started battle, and reached the first turn:

```text
DIAG: loading all project resources
DIAG: instantiating battle scene
DIAG: deploying players
DIAG: starting battle through controller
DIAG: current unit 莉娜 AP 4/4 HP 28/28 hand 5
DIAG: completed
```

## Prevention

When adding UI PNG files:

- Commit the PNG file.
- Commit its matching `.png.import` file.
- Run `--import` once before testing scene load from command line or a clean checkout.
- Use the console binary for diagnostics. The GUI `godot.exe` can hide stdout/stderr and made earlier verification misleading.
