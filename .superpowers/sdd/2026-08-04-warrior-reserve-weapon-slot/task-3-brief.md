# Task 3: Combat Switch Pipeline and Card Dependencies

Owned production files:

- `scripts/battle/battle_controller.gd`
- `scripts/cards/defensive_stance_card_effect.gd`

Owned diagnostics:

- `tools/diagnostics/warrior_reserve_weapon_check.gd`
- `tools/diagnostics/warrior_weapons_check.gd`
- `tools/diagnostics/warrior_hooks_check.gd`
- `tools/diagnostics/warrior_mechanics_check.gd`
- `tools/diagnostics/card_adjustment_check.gd`

Do not modify `scripts/battle/battle_scene.gd`; it has unrelated user changes. Defensive Stance must stop requesting an inventory weapon, so the existing generic UI branch becomes unreachable for this card without changing the scene.

Requirements:

- Add `can_switch_prepared_weapon(unit: BattleUnitState) -> bool` and `switch_prepared_weapon(unit: BattleUnitState) -> Dictionary`.
- For warriors, `can_switch_weapon_from_inventory()` and `switch_weapon_from_inventory()` are compatibility delegates to the prepared APIs.
- A successful prepared switch uses `CharacterEquipmentModel.swap_active_and_reserve_weapons()` exactly once and preserves hook order: started, old `on_before_switch_out`, atomic swap, old `on_switched_out`, new `on_switched_in`, queued switched-out/in signals, zone-owner notification, UI state change.
- Use the model result keys unchanged so Attack/Defense Dance can read old/new equipment and faces.
- Empty reserve fails without changing active weapon, reserve, backpack, faces, instance IDs, or emitting successful switch hooks.
- Combat switching never reads or mutates inventory.
- Card-payment snapshot/restore includes reserve weapon, reserve face, and the full `equipment_instance_ids` dictionary in addition to existing active weapon state.
- Defensive Stance `can_play()` depends on prepared-switch availability, never requests inventory weapon choice, and calls `switch_prepared_weapon()` directly. Its normal block and momentum strike semantics remain unchanged.
- Battle Cry, Attack/Defense Dance, Armed and Armored, Merciless Slaughter, Mountain Cleaver, Ceremonial Sword/Shield, Ember Iron Greataxe, and Clockwork Gear continue to work through compatibility calls and hooks.
- Non-warrior generic inventory equipment switching remains unchanged.

TDD:

1. Before production edits, update focused diagnostics to place alternate warrior weapons in `reserve_weapon_equipment` rather than inventory. Add assertions that backpack remains byte-for-byte equivalent, result dictionary is compatible, hook order is observable, empty reserve fails, and payment snapshot restores both slots/faces/IDs.
2. Update Defensive Stance diagnostics to omit `selected_inventory_weapon`, assert no inventory choice is required, and verify the reserve weapon becomes active.
3. Run all five diagnostic scenes outside sandbox and capture RED evidence caused by current backpack semantics.
4. Implement minimal controller/effect changes.
5. Run all five scenes GREEN with completion markers and no `ERROR:`/parse/resource errors.

Preserve unrelated controller code and do not broadly rename legacy APIs. Do not commit or touch files outside this brief. Append full evidence and self-review to `.superpowers/sdd/2026-08-04-warrior-reserve-weapon-slot/task-3-report.md`.
