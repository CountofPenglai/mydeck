# Intent Budget and Stun Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task by task, and use `superpowers:test-driven-development` for every behavior change.

**Goal:** Implement independent enemy-intent AP budgets, adjacent-intent merging, a reusable Ranger intent-AP theft API, and the redesigned persistent stun rules without changing Ranger card definitions or stun-card stack values yet.

**Architecture:** Keep the public intent declaration and its runtime execution state in `EnemyIntentPlan`, represented by typed execution groups rather than controller-owned dictionaries. Prepare all primary budgets once at enemy action-phase start, let `TacticalEnemyBehavior` consume only the active group, return unused primary AP to the residual pool, then create the fallback budget. Record AP paid on the current `BattleActionFrame` itself. After the frame's card/action effects, triggers, and after-callback effects have all drained, enter a finalization phase inside that same resolution-stack scope and resolve stun decay there.

**Tech Stack:** Godot 4.7.1, GDScript, Resource/RefCounted battle models, headless diagnostic scenes.

**Approved specification:** `docs/card_lists/ranger_rework_mechanics.md`

## Scope and constraints

- Preserve the existing staged documentation/card-text changes and do not touch `.DS_Store` or `.obsidian/`.
- Do not redesign `守候猎物` or `猎场封锁` in this batch. Only expose the system API their later card effects will call.
- Do not change the number of stun stacks applied by existing cards. This batch changes stun semantics only.
- Keep exactly one fallback intent. Normal profiles declare two primary intents; profiles may opt into more.
- Each public intent slot has a 2 AP cap before interference. Each adjacent merged primary group has one shared 8-action cap. Fallback never merges.
- A theft succeeds by at most the target slot's remaining 2 AP capacity and the target's remaining projected AP. It records both a slot reduction and a plan-wide stolen total; repeated theft from a zeroed slot returns 0.
- No automatic commits: the working tree already contains user-approved staged work. Review and stage only the files from this plan unless the user separately asks for commits.
- The current machine has no `godot` or `godot4` executable on `PATH` and no Godot app under `/Applications`. Before runtime verification, locate a Godot 4.7.1 binary; do not install or download one without user authorization.

---

### Task 1: Add executable intent groups and AP-allocation tests

**Files:**

- Create: `scripts/enemies/enemy_intent_execution_group.gd`
- Modify: `scripts/enemies/enemy_intent_plan.gd`
- Test: `tools/diagnostics/enemy_intent_ai_check.gd`

**Step 1: Write failing allocation and merge diagnostics**

Replace the fixed two-stage assertions in `_test_category_only_public_plan()` and add focused calls from `_ready()` covering:

```gdscript
func _test_intent_budget_allocation_and_returns() -> void:
	var plan := EnemyIntentPlan.new()
	plan.configure(PackedInt32Array([
		EnemyIntentCategory.Type.UTILITY,
		EnemyIntentCategory.Type.ATTACK,
	]), EnemyIntentCategory.Type.DEFEND, 3)
	plan.prepare_execution(5)
	_assert_int_array(plan.primary_allocations, [2, 2], "primary allocations")
	if plan.residual_ap != 1 or plan.get_current_budget() != 2:
		_fail("intent allocation did not reserve the residual AP")
	plan.consume_current_budget(1)
	plan.complete_current_group()
	if plan.residual_ap != 2 or plan.get_current_budget() != 2:
		_fail("unused primary AP did not return before fallback")
	plan.consume_current_budget(2)
	plan.complete_current_group()
	if not plan.is_fallback_stage() or plan.get_current_budget() != 2:
		_fail("fallback did not receive up to 2 residual AP")


func _test_adjacent_intents_merge_only() -> void:
	var adjacent := EnemyIntentPlan.new()
	adjacent.configure(PackedInt32Array([
		EnemyIntentCategory.Type.ATTACK,
		EnemyIntentCategory.Type.ATTACK,
		EnemyIntentCategory.Type.DEFEND,
	]), EnemyIntentCategory.Type.ATTACK, 1)
	adjacent.prepare_execution(6)
	if adjacent.execution_groups.size() != 2 \
			or adjacent.execution_groups[0].allocated_ap != 4:
		_fail("adjacent attack intents did not merge into a 4 AP group")

	var separated := EnemyIntentPlan.new()
	separated.configure(PackedInt32Array([
		EnemyIntentCategory.Type.ATTACK,
		EnemyIntentCategory.Type.DEFEND,
		EnemyIntentCategory.Type.ATTACK,
	]), EnemyIntentCategory.Type.ATTACK, 1)
	separated.prepare_execution(6)
	if separated.execution_groups.size() != 3:
		_fail("non-adjacent attack intents merged")
```

Also assert that an 8th recorded action reaches the group limit, that completing a capped primary returns its unused budget, and that fallback remaining AP is discarded rather than returned.

**Step 2: Run the diagnostic and confirm it fails**

```bash
godot --headless --disable-crash-handler --path . tools/diagnostics/enemy_intent_ai_check.tscn
```

Expected: parse/runtime failures because the new `configure`, `prepare_execution`, group, and budget APIs do not exist.

**Step 3: Create the typed runtime group**

Implement `EnemyIntentExecutionGroup` as `RefCounted` with:

```gdscript
extends RefCounted
class_name EnemyIntentExecutionGroup

var category: int = -1
var first_slot: int = -1
var last_slot: int = -1
var allocated_ap: int = 0
var remaining_ap: int = 0
var action_count: int = 0
var is_fallback: bool = false
var combo_tags: PackedStringArray = []
```

Provide a `create(...)` factory and `consume(ap_cost)` method. `consume` clamps to the remaining budget and increments `action_count` once per successfully started action, including a 0 AP action.

**Step 4: Refactor `EnemyIntentPlan` around arbitrary primary slots**

Use these constants and fields:

```gdscript
const MAX_AP_PER_SLOT := 2
const MAX_ACTIONS_PER_GROUP := 8

@export var primary_intents: PackedInt32Array = []
@export var primary_ap_reductions: PackedInt32Array = []
@export var fallback_intent: int = EnemyIntentCategory.Type.DEFEND
@export var fallback_ap_reduction: int = 0
@export var stolen_ap_total: int = 0

var primary_allocations: PackedInt32Array = []
var execution_groups: Array[EnemyIntentExecutionGroup] = []
var current_group_index: int = 0
var residual_ap: int = 0
var execution_prepared: bool = false
```

Implement these exact public methods:

```gdscript
func configure(primary_categories: PackedInt32Array, fallback: int, locked_round: int) -> void
func prepare_execution(total_ap: int) -> void
func get_current_group() -> EnemyIntentExecutionGroup
func get_current_category() -> int
func get_current_budget() -> int
func consume_current_budget(ap_cost: int) -> int
func current_group_reached_action_limit() -> bool
func complete_current_group() -> void
func is_fallback_stage() -> bool
func is_finished() -> bool
func finish() -> void
```

`prepare_execution` first computes `max(0, total_ap - stolen_ap_total)`, allocates primary slots in display order using `min(2 - slot_reduction, pool)`, and groups only adjacent equal categories. It retains the unallocated remainder in `residual_ap`. When the last primary group completes, create one fallback group with `min(2 - fallback_ap_reduction, residual_ap)`. Completing a primary returns its unused budget to `residual_ap`; completing fallback finishes and discards its remainder.

Update `clear`, `is_empty`, `get_headline`, and `get_summary` so zero, two, or many primaries are safe. Join all primary labels with ` → `; do not leak concrete cards.

**Step 5: Run the intent diagnostic**

Run the command from Step 2.

Expected: `ENEMY_INTENT_AI_DIAG: completed`, with no `push_error` output.

---

### Task 2: Generalize intent generation and preserve public previews

**Files:**

- Modify: `scripts/enemies/enemy_ai_profile.gd`
- Modify: `scripts/enemies/enemy_intent_planner.gd`
- Modify: `tools/diagnostics/enemy_intent_ai_check.gd`

**Step 1: Write failing generation tests**

Extend `_test_profile_presets()` to assert every preset defaults to two primaries. Add a test that duplicates a profile, sets `primary_intent_count = 3`, builds a plan, and verifies three primaries plus exactly one fallback. Keep `_test_intent_order_prefers_setup_combo()` to protect setup-before-attack ordering.

**Step 2: Run the intent diagnostic and confirm failure**

Use the Task 1 diagnostic command.

Expected: failure because `primary_intent_count` does not exist and `_select_intents` still returns a hard-coded triplet.

**Step 3: Add profile-driven primary count**

In `EnemyAIProfile`, add:

```gdscript
@export_range(1, 6, 1) var primary_intent_count: int = 2
```

Remove runtime use of `primary_one_ap_budget`, `reserve_ap_for_primary_two`, and `max_actions_per_intent`; the new rules are plan constants. Leave deprecated exported fields in place for resource compatibility until a separate data migration, but mark them with a comment and do not consult them.

**Step 4: Generalize `_select_intents`**

Return a dictionary with `primary` and `fallback`, or an equivalent typed result that does not encode fallback as the last array element. Preserve the first-slot setup boost. For each later primary, start from the base score and subtract 3 per earlier occurrence of the same category; do not ban duplicates. Select fallback after all primaries and subtract 5 for each category already used. Pass the resulting array to the new `EnemyIntentPlan.configure` signature.

**Step 5: Run the intent diagnostic**

Expected: all preset, 3-primary, combo ordering, and existing catalog tests pass.

---

### Task 3: Enforce budgets, fallback flow, merging, and the 8-action cap

**Files:**

- Modify: `scripts/enemies/tactical_enemy_behavior.gd`
- Modify: `scripts/battle/battle_controller.gd`
- Modify: `tools/diagnostics/enemy_intent_ai_check.gd`

**Step 1: Write failing behavior tests**

Replace `_test_fallback_finishes_with_ap_remaining()` with diagnostics that exercise `TacticalEnemyBehavior` against prepared plans:

- A primary with no legal action completes, returns its assigned AP, and later gives fallback 2 AP.
- An adjacent merged ATTACK group exposes 4 AP to `EnemyIntentPlanner.choose_action`, while an unmerged 2 AP group cannot select a synthetic 3 AP enemy card.
- Eight successful 0 AP actions finish the current group on the next decision instead of looping.
- A 0-budget public slot is skipped but remains present in `primary_intents`.

**Step 2: Run the intent diagnostic and confirm failure**

Use the Task 1 diagnostic command.

Expected: old `stage_start_ap`/profile-reservation behavior ignores prepared group budgets or fails against removed stage APIs.

**Step 3: Prepare the plan at enemy action-phase start**

Override `TacticalEnemyBehavior.on_turn_start(context, enemy_state)` and call:

```gdscript
unit.enemy_state.intent_plan.prepare_execution(unit.current_ap)
```

This existing hook runs from `_begin_enemy_turn` after turn-start statuses, equipment, draw, corruption, and distortion have completed, so it uses the actual AP available to the action phase.

**Step 4: Consume only the active group**

Rewrite `choose_action` to:

- Execute existing forced steps first.
- Finish immediately if the plan is missing/unprepared.
- Skip and complete a group when budget is 0, no legal action exists, or the group has reached 8 actions.
- Call the planner with `min(unit.current_ap, plan.get_current_budget())`.
- After `_execute_action` successfully queues/starts an action, call `plan.consume_current_budget(action.ap_cost)` and merge `action.provided_tags` into the current group's `combo_tags`.
- Never use AP gained later in the turn beyond the prepared plan/group budgets.
- Let `complete_current_group()` return unused primary AP and activate fallback only after all primaries finish.

Remove `_get_stage_ap_budget` and all uses of `stage_start_ap`, `stage_action_count`, and profile per-intent limits.

**Step 5: Keep a second global safety ceiling**

Raise `BattleController.MAX_ENEMY_DECISIONS_PER_TURN` from 32 to 64. The per-group 8-action limit is the rules-facing limit; 64 remains a fail-safe for special enemies with several groups and forced steps.

**Step 6: Run behavior and flow diagnostics**

```bash
godot --headless --disable-crash-handler --path . tools/diagnostics/enemy_intent_ai_check.tscn
godot --headless --disable-crash-handler --path . tools/diagnostics/battle_flow_check.tscn
```

Expected: both scenes print their `completed` marker and exit 0.

---

### Task 4: Add the reusable Ranger intent-AP theft API

**Files:**

- Modify: `scripts/enemies/enemy_intent_plan.gd`
- Modify: `scripts/battle/battle_controller.gd`
- Modify: `tools/diagnostics/enemy_intent_ai_check.gd`

**Step 1: Write failing theft diagnostics**

Add tests for this sequence:

```gdscript
var plan := EnemyIntentPlan.new()
plan.configure(PackedInt32Array([
	EnemyIntentCategory.Type.ATTACK,
	EnemyIntentCategory.Type.DEFEND,
]), EnemyIntentCategory.Type.UTILITY, 2)
var stolen := plan.reduce_public_intent_budget(0, false, 1, 4)
if stolen != 1 or plan.primary_ap_reductions[0] != 1 or plan.stolen_ap_total != 1:
	_fail("primary intent theft was not recorded")
plan.prepare_execution(4)
_assert_int_array(plan.primary_allocations, [1, 2], "theft-adjusted allocation")
if plan.residual_ap != 0:
	_fail("stolen AP leaked into the residual pool")
```

Also cover stacking, trying to steal after a slot reaches 0, trying to exceed the remaining projected AP, fallback targeting, and rejecting interference after `execution_prepared` becomes true.

Add an integration assertion that `BattleController.steal_enemy_intent_ap(...)` grants only the returned amount to the Ranger and emits `state_changed` after the plan changes.

**Step 2: Run the intent diagnostic and confirm failure**

Use the Task 1 diagnostic command.

Expected: missing plan/controller theft APIs.

**Step 3: Implement plan-level reduction**

Add:

```gdscript
func reduce_public_intent_budget(
	slot_index: int,
	is_fallback: bool,
	requested: int,
	projected_total_ap: int
) -> int
```

Reject non-positive requests, invalid slot indices, and prepared/finished plans. Compute actual theft as the minimum of the request, the target slot's remaining 2 AP capacity, and `max(0, projected_total_ap - stolen_ap_total)`. Increment the selected reduction and `stolen_ap_total`, then return actual theft.

**Step 4: Implement controller-level Ranger API**

Add:

```gdscript
func steal_enemy_intent_ap(
	thief: BattleUnitState,
	target: BattleUnitState,
	slot_index: int,
	is_fallback: bool,
	requested: int
) -> int
```

Validate that the thief is a living Ranger, the target is a living enemy with a locked, unprepared plan, and this is the thief's active action phase. Pass `target.get_max_ap(config)` as projected AP. Add only the plan-returned amount to `thief.current_ap`, log the slot label and actual theft, emit `state_changed`, and return the amount. Returning 0 must not grant AP or mutate the plan.

**Step 5: Run the intent diagnostic**

Expected: all theft and allocation examples pass, including the approved 4 AP → `[1, 2]` example.

---

### Task 5: Track AP spending at the complete-action boundary

**Files:**

- Modify: `scripts/status/status_effect.gd`
- Modify: `scripts/battle/battle_action_frame.gd`
- Modify: `scripts/battle/battle_resolution_runner.gd`
- Modify: `scripts/battle/battle_unit_state.gd`
- Modify: `scripts/battle/battle_controller.gd`
- Modify: `scripts/items/equipment_effect.gd`
- Modify: `tools/diagnostics/battle_flow_check.gd`

**Step 1: Write failing action-ledger diagnostics**

Add a diagnostic-only status class in `tools/diagnostics/battle_flow_check.gd` that records `on_ap_action_completed` calls. Test:

- A card with base AP plus `PayAPCondition` reports their sum once, after the card's queued effects, triggers, and after callback have all completed.
- A movement action reports its calculated AP cost after movement completes.
- Basic attacks against units and battle objects each report `config.basic_attack_ap_cost` once.
- A 0 AP action sends no AP-completed notification.
- AP gained by the card effect does not lower the amount already recorded as spent.
- A completion hook that enqueues an effect resolves that effect before the current action frame is popped, proving AP completion remains attached to the current resolution stack.

**Step 2: Run the flow diagnostic and confirm failure**

```bash
godot --headless --disable-crash-handler --path . tools/diagnostics/battle_flow_check.tscn
```

Expected: the new status hook and controller ledger do not exist.

**Step 3: Add the status completion hook**

In `StatusEffect` add:

```gdscript
func on_ap_action_completed(
	_unit: BattleUnitState,
	_ap_spent: int,
	_context: Dictionary = {}
) -> void:
	pass
```

In `BattleUnitState`, add `notify_ap_action_completed(ap_spent, context)` that notifies a duplicate of `statuses` and then calls `remove_expired_statuses()`.

**Step 4: Attach the AP ledger to `BattleActionFrame`**

Add `ap_spend_entries: Dictionary` to `BattleActionFrame`, keyed by unit instance ID, with values holding the unit reference and cumulative AP amount. Add `record_ap_spent(unit, amount)` and `get_ap_spend_entries()` methods. The ledger is created and discarded with the action frame, so nested/queued actions cannot consume one another's stun.

In `BattleResolutionRunner`, retain `current_action_frame` only while `_resolve_action_frame` is running and expose:

```gdscript
func record_current_action_ap_spent(unit: BattleUnitState, amount: int) -> void
```

Reset `current_action_frame` before and after every frame and in `reset()`.

**Step 5: Add an in-stack action-finalization phase**

Implement the resolution order as:

```text
frame callback
→ drain action/card effects and triggers
→ after callback
→ drain after-callback effects and triggers
→ controller finalizes AP-consuming action statuses
→ drain effects/triggers enqueued by finalization
→ controller performs action-ID cleanup
→ pop the frame's effect-queue scope
```

Add `BattleController._finalize_ap_action(frame, action_id)`. It calls `notify_ap_action_completed` once for every positive per-unit total with context `{ "controller": self, "action_id": action_id, "phase": "action_finalize" }`. Call it from `BattleResolutionRunner._resolve_action_frame` after the existing after-stage drain, then drain the current queue once more before `_on_action_resolution_completed` and `_pop_effect_queue_scope`.

This finalizer must run inside the frame's existing queue scope. Do not call stun decay directly from card payment, movement payment, basic attack payment, `_notify_action_resolution_finished`, or the next action frame.

**Step 6: Add the controller recording entry point**

Implement:

```gdscript
func _record_action_ap_spent(unit: BattleUnitState, amount: int) -> void
```

Ignore amounts `<= 0` and calls outside an action frame. Delegate accepted amounts to `resolution_runner.record_current_action_ap_spent`. Keep `_on_action_resolution_completed(action_id)` for existing action-ID cleanup only.

**Step 7: Record every existing action AP deduction**

- Card: after all play costs and special conditions succeed, compute `payment_snapshot.current_ap - frame.user.current_ap` and record that amount once. Failed payments already roll back and must not be recorded.
- Movement: immediately after subtracting `ap_cost`, record it.
- Basic attack against unit/object: immediately after subtracting the configured cost, record it.

Do not route turn-start curse penalties, turn-end AP clearing, or the old stun AP loss through this ledger; they are not AP paid for an action.

**Step 8: Make equipment action AP costs ledger-compatible**

Add `get_action_ap_cost(...) -> int` to `EquipmentEffect`, default 0, and include `"ap_cost"` in its base `get_activated_actions` result. Preserve custom action dictionaries by reading missing keys as 0. In `can_activate_equipment_action`, require enough AP. In `_resolve_equipment_action`, pay the advertised AP only when the effect activates successfully, then call `_record_action_ap_spent`; all current equipment actions remain 0 AP and retain behavior.

**Step 9: Run the flow diagnostic**

Expected: all ledger assertions pass and `FLOW_DIAG: completed` exits 0.

---

### Task 6: Implement the redesigned stun debuffs and decay

**Files:**

- Modify: `scripts/status/status_effect.gd`
- Modify: `scripts/status/stun_status.gd`
- Modify: `scripts/battle/battle_unit_state.gd`
- Modify: `tools/diagnostics/battle_flow_check.gd`
- Modify: `tools/diagnostics/mage_warlock_mechanics_check.gd`

**Step 1: Write failing stun diagnostics**

Add `_test_stun_rules()` covering:

- 1 and 5 stacks both add exactly 2 to each incoming damage segment.
- Non-fixed outgoing damage loses exactly 2 and clamps to 0; damage tagged `fixed_damage` is unchanged.
- Move distance per AP changes from `n` to `ceil(n / 2.0)`, minimum 1.
- A completed 3 AP action removes 3 stacks, a 0 AP action removes none, and AP gained during resolution does not affect removal.
- `on_turn_start` neither changes AP nor clears stacks.
- `on_turn_end` removes exactly 1 stack.

Keep the existing corruption test in `mage_warlock_mechanics_check.gd` to prove stun remains a corruptible counter.

**Step 2: Run diagnostics and confirm failure**

```bash
godot --headless --disable-crash-handler --path . tools/diagnostics/battle_flow_check.tscn
godot --headless --disable-crash-handler --path . tools/diagnostics/mage_warlock_mechanics_check.tscn
```

Expected: old stun still removes AP at turn start and lacks the three fixed debuffs/action-end decay.

**Step 3: Add outgoing status modification**

Add this no-op hook to `StatusEffect`:

```gdscript
func modify_outgoing_damage(
	_unit: BattleUnitState,
	_damage_context: DamageContext
) -> void:
	pass
```

Update `BattleUnitState.modify_outgoing_damage` to call status hooks before equipment hooks and remove expired statuses afterward. `BattleController.apply_damage` already skips this path for `fixed_damage` and environmental damage, preserving fixed damage.

**Step 4: Replace `StunStatus` behavior**

Use constants `INCOMING_DAMAGE_BONUS := 2` and `OUTGOING_DAMAGE_PENALTY := 2`. Implement:

```gdscript
func modify_incoming_damage(_unit: BattleUnitState, context: DamageContext) -> void:
	if stacks > 0 and context != null:
		context.amount += INCOMING_DAMAGE_BONUS


func modify_outgoing_damage(_unit: BattleUnitState, context: DamageContext) -> void:
	if stacks > 0 and context != null:
		context.amount = maxi(0, context.amount - OUTGOING_DAMAGE_PENALTY)


func modify_move_distance_per_ap(
	_unit: BattleUnitState,
	current_distance: int,
	_context: Dictionary = {}
) -> int:
	return maxi(1, ceili(float(current_distance) / 2.0)) if stacks > 0 else current_distance


func on_ap_action_completed(unit: BattleUnitState, ap_spent: int, context: Dictionary = {}) -> void:
	_remove_stacks(unit, ap_spent, context, "行动消耗")


func on_turn_end(unit: BattleUnitState, context: Dictionary = {}) -> void:
	_remove_stacks(unit, 1, context, "回合结束")
```

Delete the old turn-start AP-loss/clear behavior; retain `is_corruptible_counter = true`. Log only actual stack removal.

**Step 5: Run stun and legacy diagnostics**

Run both commands from Step 2, then:

```bash
godot --headless --disable-crash-handler --path . tools/diagnostics/warrior_mechanics_check.tscn
godot --headless --disable-crash-handler --path . tools/diagnostics/card_adjustment_check.tscn
```

Expected: all scenes exit 0. Existing cards still apply their previous stack counts.

---

### Task 7: Show intent budgets/interference in both intent UIs

**Files:**

- Modify: `scripts/enemies/enemy_intent_plan.gd`
- Modify: `scripts/battle/ui/battle_detail_panel.gd`
- Modify: `scripts/battle/battle_map_view.gd`
- Modify: `tools/diagnostics/enemy_intent_ai_check.gd`

**Step 1: Write failing public-text diagnostics**

Extend `_test_public_intent_ui_text()` to assert:

- Every primary is still listed in display order.
- Each slot shows its projected cap, e.g. `攻击 1/2 AP` after one theft.
- Adjacent identical primaries visibly show a merge marker and combined 4 AP when execution is prepared.
- Fallback shows its own cap/allocation and is never included in a merge.
- No concrete card/action name leaks into the public plan.

**Step 2: Run the intent diagnostic and confirm failure**

Use the Task 1 diagnostic command.

Expected: current badge/detail text shows category labels only.

**Step 3: Centralize display strings on the plan**

Add `get_primary_slot_display(index)`, `get_fallback_display()`, and `get_execution_display()` to `EnemyIntentPlan`. Before the target turn, show projected slot caps after theft; after `prepare_execution`, show assigned/current remaining AP and merged group boundaries. Keep manifestation and decay summaries separate.

Update `BattleDetailPanel._build_enemy_intent` and `BattleMapView._draw_enemy_intent_badge` to use those helpers. Keep the map badge compact; put complete per-slot information in the detail panel.

**Step 4: Run the intent diagnostic**

Expected: budget, theft, merge, and information-hiding assertions pass.

---

### Task 8: Update implementation status and run the regression matrix

**Files:**

- Modify: `docs/card_lists/ranger_rework_mechanics.md`
- Modify: `docs/card_lists/CHANGELOG.md`
- Verify: `tools/diagnostics/*.tscn`

**Step 1: Update documentation only after code diagnostics pass**

Change the mechanism document status from `尚未实现` to `已实现系统层；游侠卡牌重做与眩晕数值调整待后续`. Add the implementation clarifications used by code:

- Intent theft is limited by the slot's remaining cap and the target's remaining projected AP.
- Interference cannot retarget a plan after that enemy's action phase has started.
- Stun decay is registered on the AP-paying action's own resolution stack and resolves in that frame's finalization phase, after all ordinary effects and after-callback effects.

Do not mark `守候猎物`, `猎场封锁`, element-card reworks, or stun-card numeric rebalancing complete. In `CHANGELOG.md`, keep their follow-up status explicit.

**Step 2: Run compile/import verification**

```bash
godot --headless --disable-crash-handler --path . --editor --quit
```

Expected: exit 0 with no GDScript parse errors or failed resource imports.

**Step 3: Run focused diagnostics**

```bash
godot --headless --disable-crash-handler --path . tools/diagnostics/enemy_intent_ai_check.tscn
godot --headless --disable-crash-handler --path . tools/diagnostics/battle_flow_check.tscn
godot --headless --disable-crash-handler --path . tools/diagnostics/mage_warlock_mechanics_check.tscn
godot --headless --disable-crash-handler --path . tools/diagnostics/warrior_mechanics_check.tscn
godot --headless --disable-crash-handler --path . tools/diagnostics/card_adjustment_check.tscn
godot --headless --disable-crash-handler --path . tools/diagnostics/ranger_mechanics_check.tscn
```

Expected: each prints its `completed` marker and exits 0.

**Step 4: Run the full diagnostic suite**

```bash
for scene in tools/diagnostics/*_check.tscn; do
	godot --headless --disable-crash-handler --path . "$scene" || exit 1
done
```

Expected: every diagnostic scene exits 0. If Godot remains unavailable, do not claim runtime verification; report that exact blocker and provide static checks only.

**Step 5: Review the final diff without disturbing existing staged work**

```bash
git status --short
git diff --check
git diff -- scripts/enemies scripts/battle scripts/status scripts/items tools/diagnostics docs/card_lists
git diff --cached --stat
```

Confirm no changes under `.obsidian/`, no `.DS_Store` changes, no Ranger card resource rewrites, and no stun-card stack-value changes.
