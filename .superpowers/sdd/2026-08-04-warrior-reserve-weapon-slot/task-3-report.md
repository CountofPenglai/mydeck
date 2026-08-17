# Task 3 Report: Combat Switch Pipeline and Card Dependencies

## Status

Complete. Task 3 was implemented with test-first diagnostics and no commit. All five required Godot diagnostic scenes are GREEN with their completion markers and without `ERROR:`, script parse, or resource errors.

## Scope and ownership

Modified only the Task 3-owned production and diagnostic files:

- `scripts/battle/battle_controller.gd`
- `scripts/cards/defensive_stance_card_effect.gd`
- `tools/diagnostics/warrior_reserve_weapon_check.gd`
- `tools/diagnostics/warrior_weapons_check.gd`
- `tools/diagnostics/warrior_hooks_check.gd`
- `tools/diagnostics/warrior_mechanics_check.gd`
- `tools/diagnostics/card_adjustment_check.gd`

This report is the only additional file. I did not modify `scripts/battle/battle_scene.gd`, did not revert or format unrelated dirty files, and did not commit.

## TDD RED

The five diagnostics were changed before either production file. Warrior alternate-weapon fixtures now use `reserve_weapon_equipment`, Defensive Stance omits `selected_inventory_weapon`, and focused assertions cover:

- controller prepared/compatibility API availability and result keys;
- byte-equivalent backpack state across successful and rejected combat switches;
- active/reserve equipment, faces, and instance IDs;
- observable order: started, old `on_before_switch_out`, old `on_switched_out`, new `on_switched_in`, queued switched-out/in signals, zone-owner hook, `state_changed`;
- empty-reserve atomic failure with no successful hooks;
- card-payment rollback of both weapon slots, both faces, and the full nested `equipment_instance_ids` dictionary;
- Defensive Stance requiring no inventory choice and passing exactly once through the unified controller event pipeline;
- unchanged generic controller inventory switching for a non-warrior.

RED command pattern, run outside the sandbox with Godot 4.7.1:

```powershell
& 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' `
  --headless --disable-crash-handler --path 'D:\py_work\my-deck' `
  --scene 'res://tools/diagnostics/<scene>.tscn'
```

RED evidence from the Godot user logs:

- `warrior_reserve_weapon_check`: prepared/compatibility availability ignored the reserve slot.
- `warrior_weapons_check`: Mountain Cleaver switch reset/refresh, Ember Iron burst, and Clockwork switch-out effects failed because no backpack weapon was selected.
- `warrior_hooks_check`: Armed and Armored switching, the complete prepared-switch order, empty-reserve atomicity, and full payment snapshot restoration failed.
- `warrior_mechanics_check`: Battle Cry and Attack/Defense Dance did not switch the reserve weapon.
- `card_adjustment_check`: Defensive Stance normal/momentum play failed and emitted zero unified-pipeline events.

These were expected behavior failures from the old backpack semantics; the diagnostic scripts parsed and ran to their completion lines.

## Minimal implementation

### Unified switch settlement

`BattleController` now exposes:

- `can_switch_prepared_weapon(unit: BattleUnitState) -> bool`
- `switch_prepared_weapon(unit: BattleUnitState) -> Dictionary`

`switch_prepared_weapon()` is the sole complete settlement entry for warrior combat switching. It centralizes validation, switch-start notification, old equipment pre-switch hook, exactly one call to `CharacterEquipmentModel.swap_active_and_reserve_weapons()`, switched-out/in hooks, queued controller signals, zone-owner notification, log output, and UI `state_changed` emission.

The model remains a pure data boundary: it only atomically exchanges equipment definitions, faces, and instance-ID key/value presence. It does not orchestrate battle hooks or signals and does not touch inventory.

For warriors, both `switch_equipment_from_inventory()` and the legacy `switch_weapon_from_inventory()` immediately delegate to `switch_prepared_weapon()` before any inventory lookup. The legacy availability method similarly delegates to `can_switch_prepared_weapon()`. Non-warriors continue through the existing generic inventory path.

Existing Battle Cry, Attack/Defense Dance, Armed and Armored, Merciless Slaughter, and block-trigger status callers retain their old compatibility calls; they do not duplicate exchange or hook orchestration. Defensive Stance calls `switch_prepared_weapon()` directly.

### Card-payment rollback

The payment snapshot and restore now include:

- `reserve_weapon_equipment`
- `reserve_weapon_face`
- a deep duplicate of the full `equipment_instance_ids` dictionary

Existing active weapon, armor, accessories, inventory, card zones, and runtime state restoration remain intact.

### Defensive Stance

- `can_play()` delegates to prepared-switch availability.
- Obsolete inventory-choice overrides and `selected_inventory_weapon` handling were removed.
- `play()` calls `switch_prepared_weapon()` directly.
- Normal block and momentum nearest-enemy strike behavior were left unchanged.

## GREEN verification

Required scenes:

```powershell
$godot = 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
& $godot --headless --disable-crash-handler --path 'D:\py_work\my-deck' --scene 'res://tools/diagnostics/warrior_reserve_weapon_check.tscn'
& $godot --headless --disable-crash-handler --path 'D:\py_work\my-deck' --scene 'res://tools/diagnostics/warrior_weapons_check.tscn'
& $godot --headless --disable-crash-handler --path 'D:\py_work\my-deck' --scene 'res://tools/diagnostics/warrior_hooks_check.tscn'
& $godot --headless --disable-crash-handler --path 'D:\py_work\my-deck' --scene 'res://tools/diagnostics/warrior_mechanics_check.tscn'
& $godot --headless --disable-crash-handler --path 'D:\py_work\my-deck' --scene 'res://tools/diagnostics/card_adjustment_check.tscn'
```

Final evidence:

| Scene | Exit | Completion marker | Error scan |
|---|---:|---|---|
| warrior reserve weapon | 0 | `WARRIOR_RESERVE_WEAPON_DIAG: completed` | clean |
| warrior weapons | 0 | `WARRIOR_WEAPONS: completed` | clean |
| warrior hooks | 0 | `WARRIOR_HOOK: completed` | clean |
| warrior mechanics | 0 | `WARRIOR_MECH: completed` | clean |
| card adjustment | 0 | `CARD_ADJUST: completed` | clean |

The scan checked `ERROR:`, `SCRIPT ERROR`, `Parse Error`, missing-resource, and failed-resource-load patterns.

## Self-review

- Production reference audit finds `swap_active_and_reserve_weapons()` called exactly once in production, from `BattleController.switch_prepared_weapon()`; cards and statuses do not call the model swap.
- Every warrior-facing controller route reaches the unified prepared settlement before inventory code. The old compatibility entry is a thin delegate for warriors.
- Defensive Stance and the old compatibility entry are both proven through real switch state and event observation, without adding a production test hook or test-only API.
- Successful switching preserves the model result keys consumed by Attack/Defense Dance.
- Empty reserve validation occurs before started/hook/signal/UI notifications and before any model mutation.
- Backpack payloads include object identity, item identity/path, count, and stack ID in byte comparisons.
- Payment rollback deep-restores unrelated and nested instance-ID entries, not only the two weapon keys.
- The non-warrior generic inventory path has an explicit regression assertion.
- `git diff --check` was clean before this report; no broad rename or formatting pass was performed.
- `scripts/battle/battle_scene.gd` remains untouched by Task 3 despite its pre-existing user changes.

## Concern / runner note

The Steam Godot executable returns after printing only its banner to the invoking PowerShell stream, while scene output is written a few seconds later to `%APPDATA%\Godot\app_userdata\my_deck\logs\godot.log`. Supplying `--log-file` in this environment also produced banner-only files during the attempted RED capture. Final verification therefore read the delayed Godot user log after each bounded run; no process was left waiting indefinitely.

For coordinator reproduction with explicit files, use the same five commands above and append a distinct argument such as:

```powershell
--log-file "$env:TEMP\task-3-<scene>-green.log"
```

Require the matching completion marker and no error patterns; if the explicit file again contains only the banner, inspect the Godot user log immediately after that single scene run.
