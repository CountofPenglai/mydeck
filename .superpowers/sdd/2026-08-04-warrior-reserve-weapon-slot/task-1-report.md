# Task 1 Report: Reserve Slot Domain Model

## Scope

Implemented only the Task 1 reserve-weapon domain model and its dedicated headless diagnostic. No resources, save/load code, battle controller, UI, existing diagnostics, or unrelated worktree changes were modified.

## RED

Diagnostic files were created before production changes:

- `tools/diagnostics/warrior_reserve_weapon_check.gd`
- `tools/diagnostics/warrior_reserve_weapon_check.tscn`

Godot executable verified: `Godot Engine v4.7.1.stable.steam.a13da4feb`.

RED command:

```powershell
& 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --disable-crash-handler --path . 'res://tools/diagnostics/warrior_reserve_weapon_check.tscn'
```

RED evidence was written to `non_project_docs/godot_cli_diagnostics/warrior_reserve_red.log`. The diagnostic executed without test-script parse errors and failed because reserve behavior was absent:

- warrior reserve equip could not move the weapon into the reserve slot;
- reserve swap could not exchange equipment, faces, and IDs;
- reserve ID was not created by adventure initialization.

The Steam build records the detailed diagnostic stream in its Godot user log rather than PowerShell stdout; that finalized engine output was copied into the required RED log.

## Changed Files

- `scripts/characters/character_state.gd`
  - Added exported `reserve_weapon_equipment: EquipmentData` and `reserve_weapon_face: int`.
  - Added `reserve_weapon` to adventure equipment instance-ID initialization.
- `scripts/characters/character_equipment_model.gd`
  - Added `SLOT_RESERVE_WEAPON == "reserve_weapon"` and included it in valid slots.
  - Added warrior-only reserve equip/unequip validation.
  - Added reserve weapon slot type, get/set, and face support.
  - Added `swap_active_and_reserve_weapons(state: CharacterState) -> Dictionary`.
- `tools/diagnostics/warrior_reserve_weapon_check.gd`
  - Covers warrior equip/unequip, non-warrior rejections, successful swaps, empty active weapon, invalid swap rejection, unchanged inventory, face/ID transfer, and adventure ID initialization.
- `tools/diagnostics/warrior_reserve_weapon_check.tscn`
  - Headless diagnostic scene.

## GREEN

GREEN command:

```powershell
& 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --disable-crash-handler --path . 'res://tools/diagnostics/warrior_reserve_weapon_check.tscn'
```

GREEN evidence: exit code `0`; `non_project_docs/godot_cli_diagnostics/warrior_reserve_task1_green.log` contains:

```text
WARRIOR_RESERVE_WEAPON_DIAG: completed
```

The final GREEN log was checked for `ERROR:`, `SCRIPT ERROR`, and `Parse Error`; none were present.

## Self-Review

- Confirmed the swap validates null state, warrior class, and a populated reserve weapon before any slot, face, or ID mutation.
- Confirmed an empty active weapon is valid when the reserve weapon exists.
- Confirmed swap does not read from or write to inventory.
- Confirmed only the reserve slot receives the warrior restriction; existing equipment-slot behavior is unchanged.
- Confirmed exported fields and newly introduced methods are typed and follow existing GDScript naming/style.
- Confirmed no unrelated worktree changes were reverted, formatted, staged, or committed.

One diagnostic expectation was corrected during the first GREEN run: an empty-reserve rejection must preserve the active weapon's existing ID (`active_instance`), rather than require that ID to be empty. This was a test assertion correction only; production code was unchanged before the final passing GREEN run.

## Fix Round 1/5: Swap ID-Key and Result Contract

### RED

Command:

```powershell
& 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --disable-crash-handler --path . 'res://tools/diagnostics/warrior_reserve_weapon_check.tscn'
```

Output (from the Steam Godot user log):

```text
ERROR: WARRIOR_RESERVE_WEAPON_DIAG: swap did not exchange slot state while preserving inventory
ERROR: WARRIOR_RESERVE_WEAPON_DIAG: swap did not preserve instance ID key presence for active_only
ERROR: WARRIOR_RESERVE_WEAPON_DIAG: swap did not preserve instance ID key presence for reserve_only
ERROR: WARRIOR_RESERVE_WEAPON_DIAG: swap did not preserve instance ID key presence for neither
ERROR: WARRIOR_RESERVE_WEAPON_DIAG: swap did not promote a reserve weapon into an empty active slot
```

The diagnostic parsed and ran. Failures were the expected missing swap-result fields and empty-string ID-key behavior; no test syntax failure occurred.

### GREEN

Command:

```powershell
& 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --disable-crash-handler --path . 'res://tools/diagnostics/warrior_reserve_weapon_check.tscn'
```

PowerShell exit code: `0`.

Output:

```text
Godot Engine v4.7.1.stable.steam.a13da4feb - https://godotengine.org
WARRIOR_RESERVE_WEAPON_DIAG: completed
```

The diagnostic now covers all four `weapon`/`reserve_weapon` instance-ID key-presence combinations, explicitly verifies that an empty-main-hand swap erases `reserve_weapon`, and verifies the BattleController result contract (`slot`, old/new equipment, face, and instance ID).
