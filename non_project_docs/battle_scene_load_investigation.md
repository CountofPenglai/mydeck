# Battle Scene Load Investigation

Date: 2026-07-07

## Scope

The battle scene was reported as still failing to load after recent UI and character-system changes. The investigation covered:

- Battle scene resource loading.
- Newly added UI texture imports.
- Character, enemy, equipment, card, and battle config resources affected by the base-stat refactor.
- Runtime setup through deployment and battle start.

## Confirmed Issue

The battle scene failed before gameplay initialization because two UI textures resolved to missing imported cache files:

```text
res://assets/art/ui/ap_orb_full.png
res://assets/art/ui/discard_button.png
```

Godot followed the `.png.import` remap to `.godot/imported/*.ctex`, but the `.ctex` files did not exist locally. This caused `BattleScene` script parsing to fail at the AP orb preload and caused `battle_scene.tscn` to reject the discard button texture ext resource.

## Solution

1. Kept the `.png.import` files for both new UI textures.
2. Ran a Godot import pass with the console binary:

```powershell
& "D:\deep_learning_tool\godot\Godot_v4.6.3-stable_win64_console.exe" --headless --disable-crash-handler --log-file "tmp\godot_import.log" --path "D:\py_work\my-deck" --import
```

3. Verified that `.godot/imported/` now contains the generated `.ctex` cache files.

## Character-System Check

After the import fix, a diagnostic scene loaded all resources, instantiated `res://scenes/battle_scene.tscn`, deployed all player units, and started battle through `BattleController`.

Observed first-turn state:

```text
DIAG: current unit 莉娜 AP 4/4 HP 28/28 hand 5
```

This confirms the current sample battle path can initialize:

- Character and enemy resources.
- Strength-derived max health.
- Agility-derived turn order.
- Intelligence-derived starting hand size.
- AP initialization.
- Scene prototype enemy creation.
- Equipment-backed range and damage profile loading.

No role-system runtime error was reproduced after the UI texture import cache was regenerated.

## Diagnostic Notes

Use the console Godot executable for command-line validation:

```powershell
& "D:\deep_learning_tool\godot\Godot_v4.6.3-stable_win64_console.exe" --headless --disable-crash-handler --log-file "tmp\godot_diagnose.log" --path "D:\py_work\my-deck" --scene "res://tools/diagnostics/diagnose_battle_load.tscn"
```

The GUI `godot.exe` is not reliable for this workflow because it does not expose useful stdout/stderr in the shell and made earlier scene-load checks appear successful when they had not exercised the failing path.

## Follow-Up

For future UI asset additions, treat `--import` as part of the verification checklist. A clean checkout cannot use `.png.import` remaps until Godot regenerates the ignored `.godot/imported/*.ctex` cache.
