# Task 2 Report: Initial Loadout and Save Compatibility

## Status

Implementation is present but **not verification-complete**. The requested diagnostics did not execute in the available Steam Godot 4.7.1 tools binary, so this report does not claim GREEN/pass status.

## Files changed

- `resources/characters/battle_warrior_state.tres`
  - Keeps Mountain Cleaver active.
  - Moves Ceremonial Sword/Shield into `reserve_weapon_equipment` with face `0`.
  - Removes the Ceremonial Sword/Shield inventory stack, avoiding the starter duplicate.
- `scripts/adventure/adventure_save_store.gd`
  - Serializes `reserve_weapon` as the equipment resource path and `reserve_weapon_face`.
  - Deserializes an absent reserve path as `null` and clamps the loaded reserve face to `0..1`.
  - Leaves instance IDs in the existing `equipment_ids` / `equipment_instance_ids` dictionary.
- `scripts/curses/party_run_state.gd`
  - Advances `SAVE_VERSION` from `5` to `6`; existing accepted v3-v5 payload flow remains intact.
- `tools/diagnostics/warrior_reserve_weapon_check.gd`
  - Adds a real template assertion for active Mountain Cleaver, reserve Ceremonial Sword/Shield, face `0`, and no Ceremonial Sword/Shield inventory duplicate.
- `tools/diagnostics/adventure_system_check.gd`
  - Adds save/load assertions for a non-default reserve face and explicit reserve instance ID.
  - Adds legacy-payload coverage: erasing reserve keys must yield an empty reserve slot while preserving an explicit backpack weapon and its stack ID.
  - Adds an out-of-range reserve-face payload assertion (`99 -> 1`).

## TDD evidence

### RED

#### Verification round: stale adventure loadout expectation

Coordinator-run evidence from `non_project_docs/godot_cli_diagnostics/warrior_reserve_adventure_green.log` establishes the RED failure for this round:

- `WARRIOR_RESERVE_WEAPON_DIAG` passed.
- `ADVENTURE_DIAG` reached completion but emitted two failures from `_test_starter_deck_configuration`:
  - `battle_warrior_state.tres has the wrong starter weapon count`
  - `battle_warrior_state.tres is missing starter weapon res://resources/items/ceremonial_sword_shield.tres`

The failing assertions still expected Ceremonial Sword/Shield in the warrior inventory. They predate the approved loadout, which places that equipment in `reserve_weapon_equipment`; the production template is not changed in this verification round.

The diagnostic assertions were added before the production/template/version edits. Against the prior implementation they target two missing behaviors:

- Warrior template had no reserve weapon and retained Ceremonial Sword/Shield in inventory.
- `AdventureSaveStore` neither serialized nor restored reserve weapon path/face, and an old payload would inherit the new template's reserve weapon unless loading explicitly clears it.

Requested command attempted outside the sandbox:

```powershell
& 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --disable-crash-handler --path . 'res://tools/diagnostics/warrior_reserve_weapon_check.tscn'
```

Observed output was only the Godot 4.7.1 banner, with no `WARRIOR_RESERVE_WEAPON_DIAG:` marker or test failure. Explicit `--scene` plus an absolute project path produced the same result. This is not valid RED execution evidence.

### GREEN

After the minimal implementation, both required scene commands were attempted outside the sandbox using explicit `--scene`:

```powershell
& 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --disable-crash-handler --path 'D:\py_work\my-deck' --scene 'res://tools/diagnostics/warrior_reserve_weapon_check.tscn'
& 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --disable-crash-handler --path 'D:\py_work\my-deck' --scene 'res://tools/diagnostics/adventure_system_check.tscn'
```

Each invocation again emitted only the engine banner. Neither completion marker appeared:

- Missing: `WARRIOR_RESERVE_WEAPON_DIAG: completed`
- Missing: `ADVENTURE_DIAG: completed`

No `ERROR:`, parse, or resource message was emitted, but this cannot establish that either scene ran. Tests are therefore **unverified**, not passed.

### GREEN verification round: corrected adventure loadout expectation

The stale adventure diagnostic expectation was updated without touching production code:

- Warrior: Mountain Cleaver active, `reserve_weapon_equipment` at `res://resources/items/ceremonial_sword_shield.tres`, and an empty inventory.
- Ranger: Ranger Dagger/Crossbow active, no reserve weapon, and an empty inventory.

The requested external-sandbox retry used absolute project paths, `--scene`, and `--log-file` paths in the system temporary directory:

```powershell
$warriorLog = Join-Path $env:TEMP 'task-2-warrior-reserve-fix-green.log'
$adventureLog = Join-Path $env:TEMP 'task-2-adventure-system-fix-green.log'
& 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --disable-crash-handler --path 'D:\py_work\my-deck' --scene 'res://tools/diagnostics/warrior_reserve_weapon_check.tscn' --log-file $warriorLog
& 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --disable-crash-handler --path 'D:\py_work\my-deck' --scene 'res://tools/diagnostics/adventure_system_check.tscn' --log-file $adventureLog
```

This environment still produced only the engine banner in both captured logs and did not set PowerShell's `$LASTEXITCODE`; neither diagnostic completion marker was emitted. The code/report portion is complete, but the coordinator must rerun these two commands in the known-working runner to establish final GREEN evidence.

## Self-review

- `git diff --check` reported no whitespace errors.
- The implementation keeps Task 1's public/domain interfaces unchanged.
- No controller, card, UI, commit, revert, or formatting-only edit was made.
- Existing unrelated dirty-worktree files were left intact.

## Follow-up concern

The available `godot.windows.opt.tools.64.exe` exits immediately in headless mode before loading even the project main scene; it also leaves PowerShell's `$LASTEXITCODE` unset. Run the two diagnostics through a known-working local Godot runner/editor and require both completion markers with no errors before accepting this task as complete.

## Review fix round 1/5: v3 fixture isolation

### RED

The review finding was confirmed by inspection: the previous test appended `diag_legacy_backpack_weapon` to the shared `run.party[0].inventory`, then formed `v3_payload` by serializing that same `run`. A new assertion was added before reorganizing the fixture; it fails whenever the v3 serialized inventory contains that exact legacy stack ID:

```gdscript
_fail("ADVENTURE_DIAG: v3 fixture inherited the legacy inventory mutation")
```

The attempted external-sandbox RED command was:

```powershell
$task2RedLog = Join-Path $env:TEMP 'task-2-v3-fixture-isolation-red.log'
& 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --disable-crash-handler --path 'D:\py_work\my-deck' --scene 'res://tools/diagnostics/adventure_system_check.tscn' --log-file $task2RedLog
```

The local runner again wrote only the Godot banner. Marker: missing `ADVENTURE_DIAG: completed`. No `ERROR:` line was emitted, but this is not execution evidence.

### GREEN structure

- Builds a fresh `v3_heroes` array from the character templates and initializes a separate `v3_run` before serialization.
- Captures every hero's serialized inventory from that independent v3 payload.
- Removes `reserve_weapon` and `reserve_weapon_face` from every v3 hero dictionary together with the existing v3-era fields.
- Requires the migrated party length to match the payload, then checks every hero for an empty reserve slot, face `0`, and inventory serialization equal to that hero's original v3 inventory payload.

The attempted external-sandbox GREEN command was:

```powershell
$task2GreenLog = Join-Path $env:TEMP 'task-2-v3-fixture-isolation-green.log'
& 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --disable-crash-handler --path 'D:\py_work\my-deck' --scene 'res://tools/diagnostics/adventure_system_check.tscn' --log-file $task2GreenLog
```

The captured output was again only the Godot banner. Marker: missing `ADVENTURE_DIAG: completed`. No `ERROR:`, parse, or resource error line was emitted; the diagnostic did not run, so the coordinator must execute this command in the known-working runner for final GREEN evidence.
