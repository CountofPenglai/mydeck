# Task 2: Initial Loadout and Save Compatibility

Owned files:

- Modify `resources/characters/battle_warrior_state.tres`
- Modify `scripts/adventure/adventure_save_store.gd`
- Modify `scripts/curses/party_run_state.gd`
- Modify `tools/diagnostics/warrior_reserve_weapon_check.gd`
- Modify `tools/diagnostics/adventure_system_check.gd`

Read the approved spec and current Task 1 interfaces. Requirements:

- New warrior template: Mountain Cleaver active, Ceremonial Sword/Shield in reserve, and no ceremonial duplicate in inventory.
- Serialize/deserialize reserve equipment resource path and reserve face.
- Reserve instance ID travels through the existing `equipment_instance_ids` dictionary.
- Increment current save version while retaining old save compatibility.
- An old payload missing reserve fields loads an empty reserve slot and leaves inventory unchanged; do not auto-select any backpack weapon.
- Clamp loaded face to `0..1`.
- Preserve all unrelated save fields and migration behavior.

TDD:

1. Add template and save round-trip assertions before production edits. Save a non-default reserve face and explicit reserve ID, reload, and assert equality. Remove reserve keys from a serialized payload and assert empty reserve plus unchanged inventory.
2. Run `warrior_reserve_weapon_check.tscn` and `adventure_system_check.tscn` outside sandbox with `--disable-crash-handler`, capture RED logs.
3. Implement minimal resource/save/version changes.
4. Run both GREEN and check completion markers with no `ERROR:`/parse/resource errors.

Do not edit battle controller, cards, UI, or Task 1 production API. Do not commit. Do not revert unrelated worktree edits. Report to `.superpowers/sdd/2026-08-04-warrior-reserve-weapon-slot/task-2-report.md` with RED/GREEN evidence and self-review.
