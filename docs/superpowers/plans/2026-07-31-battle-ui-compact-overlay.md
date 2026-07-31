# Battle UI Compact Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the battlefield dominant, prevent hand-card occlusion, and restyle the bottom information strip with compact framed regions.

**Architecture:** Keep `BattleHudRoot` as the responsive composition owner and `BattleBottomHud` as the bottom presentation module. Remove only the player basic-attack presentation signal; controller attack APIs and gameplay handlers remain available to cards, enemies and scripts.

**Tech Stack:** Godot 4.7, GDScript, Control/Container scenes, NinePatchRect, real-scene headless diagnostics.

## Global Constraints

- Minimum resolution remains `960x540`.
- Deployment and detail panels overlay the battlefield and never alter horizontal map fit.
- Bottom HUD height is clamped to `176-196 px`.
- Status and hand rectangles never intersect.
- Equipment actions remain non-scrolling.
- No combat rule or runtime-state ownership changes.
- Remove the player basic-attack HUD entry while preserving controller APIs.
- Center a fixed vitals panel with a horizontal health bar and eight AP slots.

---

### Task 1: Encode the Layout Regression Contract

**Files:**
- Modify: `tools/diagnostics/battle_hud_layout_check.gd`

**Interfaces:**
- Consumes: `%BattleHudRoot`, `%BattleBottomHud`, `%StatusRow`, `%HandFrame`, `get_battle_safe_rect()`.
- Produces: geometry assertions for non-overlap, overlay-safe map fit, compact height, framed regions and minimum battlefield share.

- [x] Add assertions that `StatusRow` and `HandFrame` global rectangles do not intersect and every hand button is enclosed by `HandFrame`.
- [x] Assert left/right safe-rect values remain unchanged while deployment/detail visibility changes.
- [x] Assert bottom height is at most `196`, battlefield safe height is at least `55%` of the viewport, and six frame artwork nodes have textures.
- [x] Run `battle_hud_layout_check.tscn` and require the new assertions to fail on the current layout.

### Task 2: Implement Compact Overlay Geometry

**Files:**
- Modify: `scripts/battle/ui/battle_hud_root.gd`
- Modify: `scenes/ui/battle/battle_bottom_hud.tscn`
- Modify: `scripts/battle/ui/battle_bottom_hud.gd`

**Interfaces:**
- `BattleHudRoot.get_battle_safe_rect() -> Rect2` reserves only top and bottom vertical space.
- `BattleBottomHud` retains binding methods and gameplay-facing commands except the removed basic-attack HUD signal.

- [x] Clamp bottom height to `176-196` and remove deployment/detail horizontal insets from the map safe rect.
- [x] Separate status and hand rectangles, shrink region minimum widths and command buttons, and set cards to `96x120`.
- [x] Split the status strip into left, centered vitals and right groups so side content cannot move the character panel.
- [x] Remove `HudAttackButton`, add `%HealthBar`, and render exactly eight AP slots with filled, empty-capacity and locked states.
- [x] Run the layout diagnostic and require all four target sizes to pass.

### Task 3: Apply Framed Region Art

**Files:**
- Modify: `scenes/ui/battle/battle_bottom_hud.tscn`

**Interfaces:**
- Reuses: `res://assets/art/ui/battle_hud/panel_frame.png`.

- [x] Add mouse-ignoring NinePatchRect artwork to enchant, equipment, vitals, command, resource and curse regions.
- [x] Keep content controls above artwork and preserve semantic colors.
- [x] Widen enchant and curse regions for card-name summaries and replace the detail inspector artwork with a thin metal frame.
- [x] Run the layout and kaleidoscope diagnostics; verify no equipment scrolling appears.

### Task 4: Regression and Documentation

**Files:**
- Modify: `non_project_docs/battle_scene_prototype_guide.md`
- Modify: `non_project_docs/project_structure_and_skill_workflow.md`
- Modify: `docs/superpowers/plans/2026-07-31-battle-ui-compact-overlay.md`

- [x] Run HUD, kaleidoscope, curse, battlefield, card movement, battle flow and battle-load diagnostics independently.
- [x] Run Godot `--editor --quit` and scan for parser/resource errors.
- [x] Record overlay ownership, card sizing, framed-region rule and regression traps in project documentation.
- [x] Mark this plan complete and commit the verified changes.

## Self-Review

- Spec coverage: all three reported problems map to explicit geometry or artwork assertions.
- Placeholder scan: no deferred implementation or undefined interface remains.
- Type consistency: only the obsolete player basic-attack HUD signal was removed; controller/domain attack interfaces are unchanged.

## Follow-up: Vertical Acting-Unit Vitals

- [x] Restore `battle_scene.tscn`, `battle_hud_root.tscn` and `battle_bottom_hud.tscn` after accidental editor-coordinate overrides, without touching card, equipment or map resources.
- [x] Keep the five surrounding status regions compact while enlarging the centered acting-unit frame.
- [x] Move the portrait above the health bar, center it independently, and reserve the lower rows for a larger health bar and two four-slot AP banks.
- [x] Move the battle message overlay upward by the vitals overflow height.
- [x] Add four-resolution assertions for portrait order, centering, dimensions and overlap prevention, then run visual and adjacent battle diagnostics.
