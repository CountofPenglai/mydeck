# Battle UI Compact Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the battlefield dominant, prevent hand-card occlusion, and restyle the bottom information strip with compact framed regions.

**Architecture:** Keep `BattleHudRoot` as the responsive composition owner and `BattleBottomHud` as the bottom presentation module. Change only layout geometry and presentation resources; existing signals and `BattleScene` gameplay handlers remain unchanged.

**Tech Stack:** Godot 4.7, GDScript, Control/Container scenes, NinePatchRect, real-scene headless diagnostics.

## Global Constraints

- Minimum resolution remains `960x540`.
- Deployment and detail panels overlay the battlefield and never alter horizontal map fit.
- Bottom HUD height is clamped to `176-196 px`.
- Status and hand rectangles never intersect.
- Equipment actions remain non-scrolling.
- No combat rule or runtime-state ownership changes.

---

### Task 1: Encode the Layout Regression Contract

**Files:**
- Modify: `tools/diagnostics/battle_hud_layout_check.gd`

**Interfaces:**
- Consumes: `%BattleHudRoot`, `%BattleBottomHud`, `%StatusRow`, `%HandFrame`, `get_battle_safe_rect()`.
- Produces: geometry assertions for non-overlap, overlay-safe map fit, compact height, framed regions and minimum battlefield share.

- [ ] Add assertions that `StatusRow` and `HandFrame` global rectangles do not intersect and every hand button is enclosed by `HandFrame`.
- [ ] Assert left/right safe-rect values remain unchanged while deployment/detail visibility changes.
- [ ] Assert bottom height is at most `196`, battlefield safe height is at least `55%` of the viewport, and six frame artwork nodes have textures.
- [ ] Run `battle_hud_layout_check.tscn` and require the new assertions to fail on the current layout.

### Task 2: Implement Compact Overlay Geometry

**Files:**
- Modify: `scripts/battle/ui/battle_hud_root.gd`
- Modify: `scenes/ui/battle/battle_bottom_hud.tscn`
- Modify: `scripts/battle/ui/battle_bottom_hud.gd`

**Interfaces:**
- `BattleHudRoot.get_battle_safe_rect() -> Rect2` reserves only top and bottom vertical space.
- `BattleBottomHud` retains all existing signals and binding methods.

- [ ] Clamp bottom height to `176-196` and remove deployment/detail horizontal insets from the map safe rect.
- [ ] Separate status and hand rectangles, shrink region minimum widths and command buttons, and set cards to `96x120`.
- [ ] Run the layout diagnostic and require all four target sizes to pass.

### Task 3: Apply Framed Region Art

**Files:**
- Modify: `scenes/ui/battle/battle_bottom_hud.tscn`

**Interfaces:**
- Reuses: `res://assets/art/ui/battle_hud/panel_frame.png`.

- [ ] Add mouse-ignoring NinePatchRect artwork to enchant, equipment, vitals, command, resource and curse regions.
- [ ] Keep content controls above artwork and preserve semantic colors.
- [ ] Run the layout and kaleidoscope diagnostics; verify no equipment scrolling appears.

### Task 4: Regression and Documentation

**Files:**
- Modify: `non_project_docs/battle_scene_prototype_guide.md`
- Modify: `non_project_docs/project_structure_and_skill_workflow.md`
- Modify: `docs/superpowers/plans/2026-07-31-battle-ui-compact-overlay.md`

- [ ] Run HUD, kaleidoscope, curse, battlefield, card movement, battle flow and battle-load diagnostics independently.
- [ ] Run Godot `--editor --quit` and scan for parser/resource errors.
- [ ] Record overlay ownership, card sizing, framed-region rule and regression traps in project documentation.
- [ ] Mark this plan complete and commit the verified changes.

## Self-Review

- Spec coverage: all three reported problems map to explicit geometry or artwork assertions.
- Placeholder scan: no deferred implementation or undefined interface remains.
- Type consistency: existing HUD public methods and signal names are unchanged.

