# Task 1: Reserve Slot Domain Model

Read the approved spec at `docs/superpowers/specs/2026-08-04-warrior-reserve-weapon-slot-design.md` only for terminology. Your owned files are:

- Create `tools/diagnostics/warrior_reserve_weapon_check.gd`
- Create `tools/diagnostics/warrior_reserve_weapon_check.tscn`
- Modify `scripts/characters/character_state.gd`
- Modify `scripts/characters/character_equipment_model.gd`

Requirements:

- Add `CharacterEquipmentModel.SLOT_RESERVE_WEAPON == "reserve_weapon"`.
- Add exported `CharacterState.reserve_weapon_equipment: EquipmentData` and `reserve_weapon_face: int`.
- Include the reserve slot in adventure equipment instance-ID initialization.
- Only warriors may equip or unequip the reserve slot through the model.
- Add `CharacterEquipmentModel.swap_active_and_reserve_weapons(state: CharacterState) -> Dictionary`.
- A successful swap moves weapon definition, face, and `equipment_instance_ids` between `weapon` and `reserve_weapon` without changing inventory.
- Reject null state, non-warrior, and empty reserve before mutation.
- Allow active empty + reserve present.
- Preserve existing equipment/inventory APIs and behavior outside the new slot.

TDD:

1. Create the diagnostic first and run it outside the sandbox with Godot 4.7.1, `--headless --disable-crash-handler`, logging to `non_project_docs/godot_cli_diagnostics/warrior_reserve_red.log`.
2. Confirm RED fails because reserve behavior is absent, not due to test syntax.
3. Implement minimal production changes.
4. Re-run to `warrior_reserve_task1_green.log` and require exit 0 with `WARRIOR_RESERVE_WEAPON_DIAG: completed` and no errors.

Do not modify resources, save/load, battle controller, UI, or existing diagnostics in this task. Do not commit. You are not alone in the worktree; do not revert or reformat others' edits.

Write a detailed report to `.superpowers/sdd/2026-08-04-warrior-reserve-weapon-slot/task-1-report.md` containing RED command/evidence, changed files, GREEN command/evidence, and self-review. Return only status, one-line test summary, and concerns.
