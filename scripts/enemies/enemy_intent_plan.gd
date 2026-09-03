extends Resource
class_name EnemyIntentPlan

# Kept for the unprepared-plan UI and the legacy executor until it migrates to
# execution groups. Prepared plans use `current_group_index` instead.
const STAGE_PRIMARY_ONE := 0
const STAGE_PRIMARY_TWO := 1
const STAGE_FALLBACK := 2
const STAGE_FINISHED := 3
const MAX_AP_PER_SLOT := 2
const MAX_ACTIONS_PER_GROUP := 8

@export var round_locked: int = 0
@export var primary_intents: PackedInt32Array = []
@export var primary_ap_reductions: PackedInt32Array = []
@export var fallback_intent: int = EnemyIntentCategory.Type.DEFEND
@export var fallback_ap_reduction: int = 0
@export var stolen_ap_total: int = 0

# Compatibility state for the old executor. It remains meaningful only before
# prepare_execution() has assigned a runtime group.
@export var current_stage: int = STAGE_FINISHED
@export var forced_steps: Array[Dictionary] = []
@export var planned_manifest_card_ids: PackedInt64Array = []
@export var planned_manifest_fields: PackedStringArray = []
@export var expected_decay_life: int = 0

var primary_allocations: PackedInt32Array = []
var execution_groups: Array[EnemyIntentExecutionGroup] = []
var current_group_index: int = 0
var residual_ap: int = 0
var execution_prepared: bool = false

var stage_action_count: int = 0
var stage_start_ap: int = -1
var active_combo_tags: PackedStringArray = []
var _execution_finished: bool = true


func configure(primary_categories: Variant, fallback: int, locked_round: int, legacy_locked_round: int = -1) -> void:
	# The optional fourth argument keeps existing callers operational while the
	# planner/behavior migration is split into later tasks. New callers pass the
	# typed PackedInt32Array form described by the public API.
	if primary_categories is PackedInt32Array:
		primary_intents = primary_categories.duplicate()
		round_locked = locked_round
		fallback_intent = fallback
	else:
		primary_intents = PackedInt32Array([int(primary_categories), fallback])
		fallback_intent = locked_round
		round_locked = legacy_locked_round
	primary_ap_reductions.clear()
	fallback_ap_reduction = 0
	stolen_ap_total = 0
	primary_allocations.clear()
	execution_groups.clear()
	current_group_index = 0
	residual_ap = 0
	execution_prepared = false
	_execution_finished = false
	current_stage = STAGE_PRIMARY_ONE
	_reset_stage_runtime()


func prepare_execution(total_ap: int) -> void:
	primary_allocations.clear()
	execution_groups.clear()
	current_group_index = 0
	execution_prepared = true
	_execution_finished = false
	current_stage = STAGE_PRIMARY_ONE
	_reset_stage_runtime()

	var pool := maxi(0, total_ap) - maxi(0, stolen_ap_total)
	pool = maxi(0, pool)
	for slot in range(primary_intents.size()):
		var reduction := maxi(0, primary_ap_reductions[slot]) if slot < primary_ap_reductions.size() else 0
		var slot_cap := clampi(MAX_AP_PER_SLOT - reduction, 0, MAX_AP_PER_SLOT)
		var allocation := mini(slot_cap, pool)
		primary_allocations.append(allocation)
		pool -= allocation
		_add_primary_slot_to_group(primary_intents[slot], slot, allocation)
	residual_ap = pool

	if execution_groups.is_empty():
		_create_fallback_group()


func reduce_public_intent_budget(
		slot_index: int,
		is_fallback: bool,
		requested: int,
		projected_total_ap: int
	) -> int:
	if requested <= 0 or execution_prepared or is_finished():
		return 0

	var current_reduction := 0
	if is_fallback:
		if slot_index != 0:
			return 0
		current_reduction = maxi(0, fallback_ap_reduction)
	else:
		if slot_index < 0 or slot_index >= primary_intents.size():
			return 0
		current_reduction = maxi(0, primary_ap_reductions[slot_index]) \
			if slot_index < primary_ap_reductions.size() else 0

	var slot_remaining := clampi(MAX_AP_PER_SLOT - current_reduction, 0, MAX_AP_PER_SLOT)
	var projected_remaining := maxi(0, projected_total_ap - stolen_ap_total)
	var actual_stolen := mini(requested, mini(slot_remaining, projected_remaining))
	if actual_stolen <= 0:
		return 0

	if is_fallback:
		fallback_ap_reduction = current_reduction + actual_stolen
	else:
		if primary_ap_reductions.size() < primary_intents.size():
			primary_ap_reductions.resize(primary_intents.size())
		primary_ap_reductions[slot_index] = current_reduction + actual_stolen
	stolen_ap_total += actual_stolen
	return actual_stolen


func clear() -> void:
	round_locked = 0
	primary_intents.clear()
	primary_ap_reductions.clear()
	fallback_intent = EnemyIntentCategory.Type.DEFEND
	fallback_ap_reduction = 0
	stolen_ap_total = 0
	current_stage = STAGE_FINISHED
	forced_steps.clear()
	planned_manifest_card_ids.clear()
	planned_manifest_fields.clear()
	expected_decay_life = 0
	primary_allocations.clear()
	execution_groups.clear()
	current_group_index = 0
	residual_ap = 0
	execution_prepared = false
	_execution_finished = true
	_reset_stage_runtime()


func is_empty() -> bool:
	return forced_steps.is_empty() and is_finished()


func get_current_category() -> int:
	var group := get_current_group()
	if group != null:
		return group.category
	if not execution_prepared and not _execution_finished:
		if current_stage >= STAGE_PRIMARY_ONE and current_stage < primary_intents.size():
			return primary_intents[current_stage]
		if current_stage == STAGE_FALLBACK:
			return fallback_intent
	return -1


func get_current_group() -> EnemyIntentExecutionGroup:
	if not execution_prepared or current_group_index < 0 or current_group_index >= execution_groups.size():
		return null
	return execution_groups[current_group_index]


func get_current_budget() -> int:
	var group := get_current_group()
	return group.remaining_ap if group != null else 0


func consume_current_budget(ap_cost: int) -> int:
	var group := get_current_group()
	if group == null or current_group_reached_action_limit():
		return 0
	return group.consume(ap_cost)


func current_group_reached_action_limit() -> bool:
	var group := get_current_group()
	return group == null or group.action_count >= MAX_ACTIONS_PER_GROUP


func complete_current_group() -> void:
	var group := get_current_group()
	if group == null:
		return
	if group.is_fallback:
		finish()
		return
	residual_ap += group.remaining_ap
	group.remaining_ap = 0
	current_group_index += 1
	if current_group_index >= execution_groups.size():
		_create_fallback_group()


func _add_primary_slot_to_group(category: int, slot: int, allocation: int) -> void:
	if not execution_groups.is_empty():
		var previous: EnemyIntentExecutionGroup = execution_groups.back()
		if not previous.is_fallback and previous.category == category and previous.last_slot == slot - 1:
			previous.last_slot = slot
			previous.allocated_ap += allocation
			previous.remaining_ap += allocation
			return
	execution_groups.append(EnemyIntentExecutionGroup.create(category, slot, slot, allocation))


func _create_fallback_group() -> void:
	if not execution_groups.is_empty() and execution_groups.back().is_fallback:
		current_group_index = execution_groups.size() - 1
		return
	var fallback_reduction := maxi(0, fallback_ap_reduction)
	var fallback_cap := clampi(MAX_AP_PER_SLOT - fallback_reduction, 0, MAX_AP_PER_SLOT)
	var fallback_budget := mini(fallback_cap, residual_ap)
	residual_ap -= fallback_budget
	execution_groups.append(EnemyIntentExecutionGroup.create(
		fallback_intent,
		primary_intents.size(),
		primary_intents.size(),
		fallback_budget,
		true
	))
	current_group_index = execution_groups.size() - 1
	current_stage = STAGE_FALLBACK


func advance_stage() -> void:
	if execution_prepared or is_finished():
		return
	current_stage += 1
	if current_stage > STAGE_FALLBACK:
		finish()
	else:
		_reset_stage_runtime()


func is_fallback_stage() -> bool:
	var group := get_current_group()
	if group != null:
		return group.is_fallback
	return not execution_prepared and not _execution_finished and current_stage == STAGE_FALLBACK


func is_finished() -> bool:
	return _execution_finished


func finish() -> void:
	_execution_finished = true
	residual_ap = 0
	current_stage = STAGE_FINISHED
	current_group_index = execution_groups.size()
	_reset_stage_runtime()


func get_headline() -> String:
	if primary_intents.is_empty():
		return "观望"
	var labels := PackedStringArray()
	for category in primary_intents:
		labels.append(EnemyIntentCategory.get_label(category))
	return " → ".join(labels)


func get_primary_slot_display(index: int) -> String:
	if index < 0 or index >= primary_intents.size():
		return ""
	var label := EnemyIntentCategory.get_label(primary_intents[index])
	var reduction := maxi(0, primary_ap_reductions[index]) \
		if index < primary_ap_reductions.size() else 0
	var slot_cap := clampi(MAX_AP_PER_SLOT - reduction, 0, MAX_AP_PER_SLOT)
	if not execution_prepared:
		return "%s %d/%d AP" % [label, slot_cap, MAX_AP_PER_SLOT]

	var allocation := primary_allocations[index] if index < primary_allocations.size() else 0
	var group := _find_primary_execution_group(index)
	if group == null:
		return "%s %d/%d AP（待执行）" % [label, allocation, slot_cap]
	if group.first_slot != group.last_slot:
		return "%s %d/%d AP（合并 %d-%d，组 %d/%d AP）" % [
			label,
			allocation,
			slot_cap,
			group.first_slot + 1,
			group.last_slot + 1,
			group.remaining_ap,
			group.allocated_ap,
		]
	return "%s %d/%d AP（剩余 %d/%d AP）" % [
		label,
		allocation,
		slot_cap,
		group.remaining_ap,
		group.allocated_ap,
	]


func get_fallback_display() -> String:
	var label := EnemyIntentCategory.get_label(fallback_intent)
	var fallback_cap := clampi(
		MAX_AP_PER_SLOT - maxi(0, fallback_ap_reduction),
		0,
		MAX_AP_PER_SLOT
	)
	if not execution_prepared:
		return "%s %d/%d AP" % [label, fallback_cap, MAX_AP_PER_SLOT]

	var group := _find_fallback_execution_group()
	if group == null:
		return "%s 待分配（上限 %d/%d AP）" % [label, fallback_cap, MAX_AP_PER_SLOT]
	return "%s %d/%d AP（剩余 %d/%d AP）" % [
		label,
		group.allocated_ap,
		fallback_cap,
		group.remaining_ap,
		group.allocated_ap,
	]


func get_execution_display() -> String:
	var primary_parts := PackedStringArray()
	for index in range(primary_intents.size()):
		primary_parts.append(get_primary_slot_display(index))
	var primary_text := "观望" if primary_parts.is_empty() else " → ".join(primary_parts)
	return "%s | 备 %s" % [primary_text, get_fallback_display()]


func get_summary() -> String:
	var parts := PackedStringArray(["备 %s" % EnemyIntentCategory.get_label(fallback_intent)])
	if not planned_manifest_fields.is_empty():
		parts.append("显化 %s" % "、".join(planned_manifest_fields))
	if expected_decay_life > 0:
		parts.append("衰退 -%d生命" % expected_decay_life)
	return " / ".join(parts)


func _find_primary_execution_group(index: int) -> EnemyIntentExecutionGroup:
	for group in execution_groups:
		if group != null and not group.is_fallback \
				and index >= group.first_slot and index <= group.last_slot:
			return group
	return null


func _find_fallback_execution_group() -> EnemyIntentExecutionGroup:
	for group in execution_groups:
		if group != null and group.is_fallback:
			return group
	return null


func _reset_stage_runtime() -> void:
	stage_action_count = 0
	stage_start_ap = -1
	active_combo_tags.clear()
