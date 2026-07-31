# Battle UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the battle scene's scattered overlays with a responsive modular HUD matching the approved sample, while preserving existing combat input and resolution behavior.

**Architecture:** `BattleScene` remains the controller adapter for movement, targeting, card play, menus, and battle lifecycle. A new `BattleHudRoot` owns presentation modules and emits typed UI signals back to `BattleScene`; its child modules separately own turn order, deployment, details, bottom HUD, pile buttons, and the equipment action popup. `BattleMapView` gains a safe-area rectangle used only for fit/reset calculations, so HUD changes do not alter hex coordinates or combat rules.

**Tech Stack:** Godot 4.x, statically typed GDScript, `.tscn` Control scenes, existing `BattleController`/`BattleUnitState` resources, headless Godot diagnostics, generated PNG UI textures.

## Global Constraints

- Preserve all card, movement, target selection, curse, equipment, and action-resolution behavior.
- Baseline viewport is `1280x720`; minimum supported viewport is `960x540`.
- Compact mode is `960-1099` pixels wide; normal mode is `1100-1600`; wide mode is greater than `1600`.
- Bottom HUD height stays between `176` and `224` pixels and uses about 26 percent of viewport height.
- The right detail panel is hidden without content, uses `280-340` pixels width, supports hover preview plus click lock, and closes on blank battlefield click.
- Turn order displays the full locked round; current is amber, acted units are dimmed, allies are green, enemies are red.
- Equipment actions never use a `ScrollContainer`; one action is direct and multiple actions use an upward popup with two columns normally and one column in compact mode.
- Do not write runtime state into shared `CardData` or `EquipmentData` resources.
- Reuse existing deck, discard, AP, and hand textures; new art follows worn wood, black iron, brass, parchment, and higher-saturation semantic accents.
- Run Godot diagnostics with `--headless --disable-crash-handler --log-file <path> --path D:\py_work\my-deck` outside the sandbox when AppData writes are blocked.

---

## File Structure

- Create `scripts/battle/ui/battle_hud_root.gd`: responsive composition, signal forwarding, current/deployment unit binding, and popup/detail coordination.
- Create `scenes/ui/battle/battle_hud_root.tscn`: complete HUD node hierarchy and stable anchors.
- Create `scripts/battle/ui/battle_turn_order_bar.gd`: full-round portrait rail rendering.
- Create `scripts/battle/ui/battle_detail_panel.gd`: common card/equipment/unit/object/terrain detail model and hover/lock state.
- Create `scripts/battle/ui/battle_bottom_hud.gd`: health/AP/resources/zones/hand/equipment presentation and command signals.
- Create `scripts/battle/ui/battle_equipment_actions_popup.gd`: non-scrolling one/two-column action chooser.
- Create `scripts/battle/ui/battle_pile_button.gd`: circular pile count and semantic color presentation.
- Modify `scenes/battle_scene.tscn`: replace old overlays with one `BattleHudRoot` instance while retaining battle menu and confirmation dialog.
- Modify `scripts/battle/battle_scene.gd`: adapt existing handlers and refresh methods to the HUD API.
- Modify `scripts/battle/battle_map_view.gd`: expose `set_fit_safe_rect(Rect2)` and blank-click/detail signals.
- Create `tools/diagnostics/battle_hud_layout_check.gd` and `.tscn`: real-scene responsive and interaction checks.
- Modify `tools/diagnostics/druid_kaleidoscope_ui_check.gd`: assert the new equipment popup rather than removed legacy nodes.
- Add generated textures under `assets/art/ui/battle_hud/` and register them in `assets/art/asset_manifest.md`.
- Update `non_project_docs/battle_scene_prototype_guide.md` and `non_project_docs/project_structure_and_skill_workflow.md` with new ownership and regression guidance.

### Task 1: Diagnostic Contract and HUD Skeleton

**Files:**
- Create: `tools/diagnostics/battle_hud_layout_check.gd`
- Create: `tools/diagnostics/battle_hud_layout_check.tscn`
- Create: `scripts/battle/ui/battle_hud_root.gd`
- Create: `scenes/ui/battle/battle_hud_root.tscn`
- Modify: `scenes/battle_scene.tscn`

**Interfaces:**
- Consumes: `BattleScene.controller`, `BattleScene.selected_deploy_unit`, and existing button handlers.
- Produces: `BattleHudRoot.bind_battle(scene: BattleScene, controller: BattleController)`, `refresh_view()`, `get_battle_safe_rect() -> Rect2`, and named children `%TurnOrderBar`, `%DeploymentPanel`, `%DetailPanel`, `%BottomHud`, `%MenuButton`.

- [x] **Step 1: Write the failing real-scene diagnostic**

  Instantiate `res://scenes/battle_scene.tscn`, resize its root to each of `Vector2(960, 540)`, `Vector2(1280, 720)`, `Vector2(1920, 1080)`, and `Vector2(2560, 1080)`, await one process frame, then assert:
  - `%BattleHudRoot` and all five named children exist.
  - the bottom HUD height is in `[176, 224]` and does not exceed 26 percent by more than one pixel after clamping;
  - visible top controls do not intersect the bottom HUD;
  - compact mode sets detail presentation to overlay and equipment columns to one;
  - normal/wide mode uses two equipment columns;
  - no descendant of `%EquipmentRegion` is a `ScrollContainer`.
  Print `BATTLE_HUD_LAYOUT_CHECK: PASS` and quit `0`; on the first failed assertion print the reason and quit `1`.

- [x] **Step 2: Run the diagnostic to verify RED**

  Run:
  ```powershell
  & 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --disable-crash-handler --log-file 'D:\py_work\my-deck\battle_hud_layout_red.log' --path 'D:\py_work\my-deck' 'res://tools/diagnostics/battle_hud_layout_check.tscn'
  ```
  Expected: exit `1` because `%BattleHudRoot` is absent.

- [x] **Step 3: Add the responsive skeleton**

  Implement `BattleHudRoot` with width breakpoints `1100` and `1600`, clamped bottom height `clampf(size.y * 0.26, 176.0, 224.0)`, a compact detail overlay, and a centered wide-mode bottom maximum width of `1560`. Connect `resized` to `_apply_responsive_layout()` and return the battlefield fit rectangle above the bottom HUD and inside visible left/right overlays.

- [x] **Step 4: Replace legacy overlay nodes in the scene**

  Instance the new HUD above `%MapView`; retain `%BattleMenu`, `%RestartConfirmation`, and the return-to-map button lifecycle. Remove `TopOverlay`, `CurrentUnitPanel`, old `BottomHud`, separate pile buttons, and `EnemyInspectPanel` from the scene only after equivalent named nodes exist inside `BattleHudRoot`.

- [x] **Step 5: Run the diagnostic to verify GREEN and commit**

  Run the command from Step 2 and require the PASS marker. Commit:
  ```powershell
  git add tools/diagnostics/battle_hud_layout_check.* scripts/battle/ui/battle_hud_root.gd scenes/ui/battle/battle_hud_root.tscn scenes/battle_scene.tscn
  git commit -m "feat: add responsive battle HUD shell"
  ```

### Task 2: Map Safe Area and Blank Inspection Close

**Files:**
- Modify: `scripts/battle/battle_map_view.gd`
- Modify: `scripts/battle/battle_scene.gd`
- Modify: `tools/diagnostics/battle_hud_layout_check.gd`

**Interfaces:**
- Consumes: `BattleHudRoot.get_battle_safe_rect()`.
- Produces: `BattleMapView.set_fit_safe_rect(value: Rect2)`, `BattleMapView.fit_safe_rect: Rect2`, and `BattleScene._clear_detail_inspection()`.

- [x] **Step 1: Extend the diagnostic with safe-area assertions**

  Assert that `_reset_view_to_fit()` places all four corners of `controller.map_data.map_size` inside `fit_safe_rect` at every test resolution, and that an unoccupied blank click while input mode is `NONE` clears a locked detail.

- [x] **Step 2: Run RED**

  Expected: parse/runtime failure because `set_fit_safe_rect` does not exist.

- [x] **Step 3: Implement safe-area fit without changing map coordinates**

  Add `fit_safe_rect`, defaulting to the full control rect. Calculate available size from that rect minus `FIT_PADDING * 2`, and calculate `view_offset` from `fit_safe_rect.position + (fit_safe_rect.size - map_size * view_zoom) * 0.5`. Clamp against the same rect. `BattleScene` updates it after HUD layout and before map redraw.

- [x] **Step 4: Implement blank-click close**

  When `InputMode.NONE` receives a map click with no unit and no battle object, call the HUD detail panel's clear-lock method. Preserve all existing deployment and target-mode click branches.

- [x] **Step 5: Run GREEN and commit**

  Commit:
  ```powershell
  git add scripts/battle/battle_map_view.gd scripts/battle/battle_scene.gd tools/diagnostics/battle_hud_layout_check.gd
  git commit -m "feat: fit battle map around HUD safe areas"
  ```

### Task 3: Turn Order and Deployment Modules

**Files:**
- Create: `scripts/battle/ui/battle_turn_order_bar.gd`
- Modify: `scenes/ui/battle/battle_hud_root.tscn`
- Modify: `scripts/battle/ui/battle_hud_root.gd`
- Modify: `scripts/battle/battle_scene.gd`
- Modify: `tools/diagnostics/battle_hud_layout_check.gd`

**Interfaces:**
- Consumes: `controller.turn_order`, `controller.current_turn_index`, `controller.battle_round`, `controller.player_units`, and `selected_deploy_unit`.
- Produces: `BattleTurnOrderBar.bind_round(order: Array[BattleUnitState], current_index: int, round_number: int)` and signals `unit_hovered(unit)`, `unit_unhovered(unit)`, `unit_pressed(unit)`; HUD signal `deployment_unit_selected(unit)`.

- [x] **Step 1: Add failing state-render assertions**

  Start the sample battle after deploying players, bind an order of at least one ally and one enemy, and assert each entry exposes metadata `current`, `acted`, and `faction`. Assert deployment panel is visible only during deployment and selected unit is visually marked.

- [x] **Step 2: Run RED**

  Expected: missing `bind_round`.

- [x] **Step 3: Implement the full-round rail**

  Build stable fixed-size portrait buttons from the locked array without sorting it. Set current index amber, indices below current dim, ally frames emerald, enemy frames crimson. Put entries in a horizontal `ScrollContainer` only in compact mode; do not wrap or resize entries.

- [x] **Step 4: Implement deployment presentation and signals**

  Render player rows with deployed/pending status and connect selection to `BattleScene._select_deploy_unit`. Keep Start Battle in this panel and hide the whole panel when phase changes to battle.

- [x] **Step 5: Run GREEN and commit**

  Commit:
  ```powershell
  git add scripts/battle/ui/battle_turn_order_bar.gd scenes/ui/battle/battle_hud_root.tscn scripts/battle/ui/battle_hud_root.gd scripts/battle/battle_scene.gd tools/diagnostics/battle_hud_layout_check.gd
  git commit -m "feat: add battle turn rail and deployment panel"
  ```

### Task 4: Bottom HUD, Piles, Cards, and Commands

**Files:**
- Create: `scripts/battle/ui/battle_bottom_hud.gd`
- Create: `scripts/battle/ui/battle_pile_button.gd`
- Modify: `scenes/ui/battle/battle_hud_root.tscn`
- Modify: `scripts/battle/ui/battle_hud_root.gd`
- Modify: `scripts/battle/battle_scene.gd`
- Modify: `tools/diagnostics/battle_hud_layout_check.gd`

**Interfaces:**
- Consumes: current acting unit in battle, selected deployment unit in deployment, existing `_select_card`, `_on_move_pressed`, `_on_attack_pressed`, `_on_end_turn_pressed`, `_on_deck_pressed`, `_on_discard_pressed`, and `_show_curse_popup` handlers.
- Produces: `BattleBottomHud.bind_unit(unit: BattleUnitState, controller: BattleController, interactive: bool)`, `bind_hand(cards: Array[CardData], costs: Array[int], interactive: bool)`, and signals `card_pressed(card)`, `card_hovered(card)`, `card_unhovered(card)`, `move_pressed`, `attack_pressed`, `end_turn_pressed`, `deck_pressed`, `discard_pressed`, `curse_pressed`, `enchant_pressed`.

- [x] **Step 1: Add failing binding assertions**

  Assert deployment binds the selected player, battle binds `controller.current_unit`, inspecting another unit does not change the bottom binding, AP orb count equals current AP up to visible slots, and each hand card has stable `112x138` minimum size.

- [x] **Step 2: Run RED**

  Expected: missing `BattleBottomHud.bind_unit`.

- [x] **Step 3: Implement the bottom composition**

  Compose unframed functional regions in one row: enchant, equipment, portrait/vitals/AP, move/attack/end, resources/status, curse. Place the portrait ring above the row and the wooden hand board below. Put circular discard and deck buttons at opposite ends. Keep cards horizontally scrollable only when their total width exceeds the board.

- [x] **Step 4: Move refresh rendering behind the module API**

  Replace direct legacy node writes in `_refresh`, `_refresh_hand_list`, `_refresh_class_resource_list`, `_refresh_discard_button`, and `_refresh_curse_button` with module methods. Keep popup creation and gameplay callbacks in `BattleScene` in this task.

- [x] **Step 5: Run GREEN and commit**

  Commit:
  ```powershell
  git add scripts/battle/ui/battle_bottom_hud.gd scripts/battle/ui/battle_pile_button.gd scenes/ui/battle/battle_hud_root.tscn scripts/battle/ui/battle_hud_root.gd scripts/battle/battle_scene.gd tools/diagnostics/battle_hud_layout_check.gd
  git commit -m "feat: rebuild battle bottom HUD"
  ```

### Task 5: Unified Detail Panel

**Files:**
- Create: `scripts/battle/ui/battle_detail_panel.gd`
- Modify: `scenes/ui/battle/battle_hud_root.tscn`
- Modify: `scripts/battle/ui/battle_hud_root.gd`
- Modify: `scripts/battle/battle_scene.gd`
- Remove: `scripts/enemies/enemy_inspect_panel.gd`
- Remove: `scenes/ui/enemy_inspect_panel.tscn`
- Modify: `tools/diagnostics/battle_hud_layout_check.gd`

**Interfaces:**
- Produces: `preview_card(card, context)`, `preview_equipment(equipment, unit)`, `preview_unit(unit)`, `preview_object(object_state)`, `preview_terrain(cell, detail_text)`, `lock_current()`, `clear_preview()`, `clear_lock()`, `is_locked() -> bool`.
- Hover never replaces locked content permanently; mouse exit restores locked content. Click locks the currently previewed subject.

- [x] **Step 1: Add failing hover/lock assertions**

  Preview card A, lock it, preview enemy B, clear preview, and assert A returns. Clear lock and assert panel hides. Bind an enemy and assert intent headline, summary, steps, recipe, zone counts, and seen cards remain available.

- [x] **Step 2: Run RED**

  Expected: missing common detail API.

- [x] **Step 3: Implement typed detail builders**

  Use a single internal dictionary with `kind`, `identity`, `title`, `subtitle`, `art`, `body`, and `sections`. Card body includes rarity/type/AP/range/effect; equipment includes slot/components/base damage/range/runtime; friendly unit includes health/AP/armor/stats/resources; enemy adds intent; object and terrain use controller detail strings.

- [x] **Step 4: Connect all inspection sources**

  Connect hand cards, turn portraits, equipment entries, pile/zone list entries, map units, battle objects, and terrain hover. Keep click-to-target branches higher priority than inspection during active target modes.

- [x] **Step 5: Remove old enemy-only panel, run GREEN, and commit**

  Commit:
  ```powershell
  git add scripts/battle/ui/battle_detail_panel.gd scenes/ui/battle/battle_hud_root.tscn scripts/battle/ui/battle_hud_root.gd scripts/battle/battle_scene.gd tools/diagnostics/battle_hud_layout_check.gd
  git rm scripts/enemies/enemy_inspect_panel.gd scenes/ui/enemy_inspect_panel.tscn
  git commit -m "feat: unify battle detail inspection"
  ```

### Task 6: Non-Scrolling Equipment Actions

**Files:**
- Create: `scripts/battle/ui/battle_equipment_actions_popup.gd`
- Modify: `scenes/ui/battle/battle_hud_root.tscn`
- Modify: `scripts/battle/ui/battle_bottom_hud.gd`
- Modify: `scripts/battle/ui/battle_hud_root.gd`
- Modify: `scripts/battle/battle_scene.gd`
- Modify: `tools/diagnostics/druid_kaleidoscope_ui_check.gd`
- Modify: `tools/diagnostics/battle_hud_layout_check.gd`

**Interfaces:**
- Consumes: `unit.get_equipment_actions(context)` dictionaries and `controller.can_activate_equipment_action(unit, effect, action_id)`.
- Produces: `set_actions(unit, actions, can_activate: Callable, compact: bool)`, `close()`, `is_open()`, and `action_selected(unit, effect, action_id)`.

- [ ] **Step 1: Write failing direct/expanded action assertions**

  With one action, assert the equipment button directly invokes it and no popup opens. With three actions, assert an expand indicator is visible, popup opens upward, grid columns are two at `1280` and one at `960`, no `ScrollContainer` exists, and selecting one action closes the popup.

- [ ] **Step 2: Run RED**

  Expected: missing popup class and old kaleidoscope diagnostic node references.

- [ ] **Step 3: Implement action grouping and popup lifecycle**

  Build buttons from each action dictionary, with disabled state from the supplied callable. Close on action execution, current unit change, detail lock, blank click, and equipment button re-click. Use measured popup height and place it immediately above `%EquipmentRegion` inside viewport bounds.

- [ ] **Step 4: Update the kaleidoscope diagnostic**

  Replace assertions for `CurrentUnitPanel` and `equipment_list` with `%EquipmentRegion`, direct/expanded state, end-turn enabled state, and absence of equipment scrolling.

- [ ] **Step 5: Run both diagnostics GREEN and commit**

  Commit:
  ```powershell
  git add scripts/battle/ui/battle_equipment_actions_popup.gd scenes/ui/battle/battle_hud_root.tscn scripts/battle/ui/battle_bottom_hud.gd scripts/battle/ui/battle_hud_root.gd scripts/battle/battle_scene.gd tools/diagnostics/druid_kaleidoscope_ui_check.gd tools/diagnostics/battle_hud_layout_check.gd
  git commit -m "feat: add expandable equipment action HUD"
  ```

### Task 7: Battle HUD Art Assets

**Files:**
- Create: `assets/art/ui/battle_hud/bottom_wood_panel.png`
- Create: `assets/art/ui/battle_hud/panel_frame.png`
- Create: `assets/art/ui/battle_hud/turn_order_rail.png`
- Create: `assets/art/ui/battle_hud/detail_frame.png`
- Create: `assets/art/ui/battle_hud/command_icons.png`
- Create: `assets/art/ui/battle_hud/current_unit_ring.png`
- Create: `assets/art/ui/battle_hud/turn_ally_frame.png`
- Create: `assets/art/ui/battle_hud/turn_enemy_frame.png`
- Modify: `scenes/ui/battle/battle_hud_root.tscn`
- Modify: `assets/art/asset_manifest.md`

**Interfaces:**
- Textures are presentation-only and must not contain rendered words.
- Frames must tolerate nine-patch or keep-aspect scaling without clipping their ornamental borders.

- [ ] **Step 1: Generate coherent raster assets**

  Use the image-generation tool with the existing art guide: gritty western fantasy game HUD, hand-painted worn dark wood, blackened iron, brass rivets, parchment, stronger but controlled saturation, transparent or clean dark background, no text, no symbols that resemble letters, orthographic UI asset, readable at game scale.

- [ ] **Step 2: Import and bind textures**

  Use `NinePatchRect` for panel/frame textures, `TextureRect` for rails/rings, and atlas regions for move/attack/end/menu/expand icons. Preserve familiar symbols and add tooltips to icon-only buttons.

- [ ] **Step 3: Run the real-scene diagnostic and import scan**

  Require all texture paths to load as `Texture2D`, all four resolutions to pass, and Godot output to contain no missing-resource or parser errors.

- [ ] **Step 4: Update manifest and commit**

  Record path, purpose, generation date, style, and primary scene for every asset. Commit:
  ```powershell
  git add assets/art/ui/battle_hud assets/art/asset_manifest.md scenes/ui/battle/battle_hud_root.tscn
  git commit -m "art: add saturated battle HUD assets"
  ```

### Task 8: Full Regression and Documentation

**Files:**
- Modify: `non_project_docs/battle_scene_prototype_guide.md`
- Modify: `non_project_docs/project_structure_and_skill_workflow.md`
- Modify: `docs/superpowers/plans/2026-07-31-battle-ui-redesign.md`

**Interfaces:**
- Documentation must identify UI ownership, responsive breakpoints, detail lock behavior, equipment popup invariants, safe-area fitting, and exact headless test command.

- [ ] **Step 1: Run targeted diagnostics**

  Run `battle_hud_layout_check.tscn`, `druid_kaleidoscope_ui_check.tscn`, `curse_system_check.tscn`, `battlefield_features_check.tscn`, `card_movement_check.tscn`, and `diagnose_battle_load.tscn`. Require exit `0` and each script's completion marker.

- [ ] **Step 2: Run project-wide headless load**

  Run:
  ```powershell
  & 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --disable-crash-handler --log-file 'D:\py_work\my-deck\battle_ui_project_check.log' --path 'D:\py_work\my-deck' --editor --quit
  ```
  Require exit `0`; treat known ObjectDB/RID shutdown warnings as non-blocking only when no parser/resource errors exist.

- [ ] **Step 3: Check responsive node bounds**

  Re-run the layout diagnostic at all four target sizes and inspect emitted bounds for overlap, negative size, clipped labels, and blank textures. Confirm map remains interactive around every HUD safe region.

- [ ] **Step 4: Update documentation**

  Document the module tree, signal flow, detail data model, no-scroll equipment action rule, common regression traps, and the sandbox-safe Godot command.

- [ ] **Step 5: Mark this plan complete and commit**

  Check every completed box in this file and commit:
  ```powershell
  git add docs/superpowers/plans/2026-07-31-battle-ui-redesign.md assets/art/asset_manifest.md
  git commit -m "docs: record battle HUD architecture and tests"
  ```

## Self-Review

- Spec coverage: all approved layout regions, interaction rules, equipment expansion behavior, responsive breakpoints, map-safe fit, art direction, and four target resolutions map to Tasks 1-8.
- Placeholder scan: the plan contains no `TBD`, implementation-later instruction, or unspecified error-handling step.
- Type consistency: `BattleHudRoot`, `BattleBottomHud`, `BattleTurnOrderBar`, `BattleDetailPanel`, and `BattleEquipmentActionsPopup` method names are defined once and reused consistently.
- Risk control: gameplay handlers remain in `BattleScene`; the refactor changes presentation binding and signal forwarding, not resolution ownership.
