# Task 4 Report: Warrior Reserve Weapon UI

## Status

Complete. Task 4 was implemented test-first without committing. The adventure inventory, four-resolution battle HUD, HUD visual, warrior reserve-domain, and strict project-load diagnostics are clean.

## Scope and ownership

Modified only the Task 4-owned files:

- `scripts/adventure/adventure_map_scene.gd`
- `scripts/battle/ui/battle_bottom_hud.gd`
- `tools/diagnostics/adventure_inventory_ui_check.gd`
- `tools/diagnostics/battle_hud_layout_check.gd`
- this report

`scripts/battle/ui/battle_hud_root.gd` and `tools/diagnostics/battle_hud_visual_check.gd` did not require changes. I did not modify or revert the pre-existing dirty files `scripts/battle/battle_scene.gd` or `scenes/battle_scene.tscn`, and did not commit.

## TDD evidence

All Godot commands used the project-documented Steam Godot 4.7.1 executable outside the sandbox with `--headless --disable-crash-handler --log-file`.

RED evidence:

- `task4_adventure_inventory_red.log`: reported `warrior reserve weapon row missing` and missing dual equip destinations.
- `task4_battle_hud_red.log`: reported `warrior current/reserve summary mismatch at (960, 540)`.

GREEN/final evidence:

| Check | Process exit | Evidence |
|---|---:|---|
| Adventure inventory UI | 0 | `INVENTORY_UI_DIAG: completed`; no `ERROR` |
| Battle HUD layout | 0 | `BATTLE_HUD_LAYOUT_CHECK: PASS`; no `ERROR` |
| Battle HUD visual | 0 | fixed 136x76 equipment region and separate hand frame logged; screenshot explicitly skipped by the headless display driver |
| Warrior reserve domain | 0 | `WARRIOR_RESERVE_WEAPON_DIAG: completed`; no `ERROR` |
| Strict editor load | 0 | global classes registered and no parse/resource errors |

Final logs are under `non_project_docs/godot_cli_diagnostics/task4_*_final.log`.

## Implementation

### Adventure equipment and inventory modal

- The existing `Control`/container tree is retained: modal `VBoxContainer` with one `HBoxContainer` per equipment or inventory row.
- Warriors alone receive a `备战武器` row backed by `CharacterEquipmentModel.SLOT_RESERVE_WEAPON`; its existing detail and unequip buttons work like other slots.
- A warrior backpack weapon gets explicit `装备为当前` and `装备为备战` buttons. Non-warriors retain one exact `装备` button and receive no reserve-slot control.
- Equip and unequip handlers still delegate to `AdventureSession`; returned messages are forwarded to the existing status surface before the modal refreshes.

### Battle HUD

- Warriors always display exactly two lines: `当前：<active face name or 徒手>` and `备战：<reserve face name or 无>`.
- Non-warrior summary and action-label presentation are unchanged.
- The existing fixed `EquipmentRegion` and wrapping `Label` remain in use; no `ScrollContainer`, scene-node expansion, or hand-area geometry change was added.
- Zero-action clicks still open current equipment details through the existing `BattleHudRoot` path. Single-action execution and multi-action popup behavior remain unchanged.
- `BattleHudRoot._refresh_equipment_actions()` remains unchanged and still assigns only `unit.get_equipment_actions(...)`. The layout diagnostic gives both active and reserve weapons activated effects and proves the HUD action cache equals the active query only, so reserve startup effects cannot leak into the action list.

## UI strategy review

- Theme: no new inline visual overrides were introduced; new controls inherit the existing modal/HUD theme and styles.
- Localization: new user-visible labels and warrior summary format strings use `tr()`; no plural or context-specific strings are needed.
- Responsive behavior: the project remains at its existing 1280x720 base with `canvas_items` and `expand`. HUD assertions pass at 960x540, 1280x720, 1920x1080, and 2560x1080, with wrapping enabled and no equipment scrolling.
- Code review: no critical Godot architecture, typing, signal, resource-lifecycle, or hot-path issues were found in the changed production code. `git diff --check` is clean.

