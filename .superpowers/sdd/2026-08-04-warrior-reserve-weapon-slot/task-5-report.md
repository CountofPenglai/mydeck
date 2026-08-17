# Task 5 Report: Documentation and Full Regression

## Documentation

- Updated the external and project-local Warrior weapon documents to define the persistent current/reserve slots, atomic combat exchange, empty-reserve failure, initial loadout, runtime-state lifetime, and UI behavior.
- Updated the current Warrior card list and `defensive_stance.tres` so player-facing text no longer describes backpack weapon selection.
- Updated `mountain_cleaver.tres` to describe entering the reserve slot rather than the backpack.
- Updated the project structure/testing guide with the controller/model encapsulation boundary and rollback requirements.

## Verification

- Strict Godot 4.7.1 editor load: clean.
- Focused/dependent diagnostics: reserve weapon, adventure system, adventure inventory UI, Warrior weapons, Warrior hooks, Warrior mechanics, card adjustment, battle HUD layout, battle HUD visual, battle flow, and battle load all completed without `ERROR:`, parse, script, or resource failures.
- Windowed 1280x720 HUD screenshot saved at `.godot_user/compact_hud_preview.png`; current/reserve labels remain inside the equipment region and do not cover the hand.
- Additional detail-popup regression confirms Warrior current/reserve detail entries coexist with only the current weapon's activated actions.
- Production search finds exactly one call to `swap_active_and_reserve_weapons()`, from `BattleController.switch_prepared_weapon()`.
- The generic `switch_equipment_from_inventory()` contract remains class-agnostic and honors explicitly requested equipment. All Warrior gameplay callers use the prepared APIs directly; the old weapon-from-inventory names remain compatibility wrappers only.
- The generic and prepared public entries share one private hook/signal settlement function, while their validation and data mutations remain separate.
- Remaining backpack-selection identifiers belong to the preserved generic compatibility path and dormant generic card-choice UI; Warrior gameplay switching bypasses both.
- Scoped `git diff --check` is clean.
