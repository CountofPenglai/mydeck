extends Resource
class_name EnemyIntentPlan

const STAGE_PRIMARY_ONE := 0
const STAGE_PRIMARY_TWO := 1
const STAGE_FALLBACK := 2
const STAGE_FINISHED := 3

@export var round_locked: int = 0
@export var primary_intents: PackedInt32Array = []
@export var fallback_intent: int = EnemyIntentCategory.Type.DEFEND
@export var current_stage: int = STAGE_FINISHED
@export var forced_steps: Array[Dictionary] = []
@export var planned_manifest_card_ids: PackedInt64Array = []
@export var planned_manifest_fields: PackedStringArray = []
@export var expected_decay_life: int = 0

var stage_action_count: int = 0
var stage_start_ap: int = -1
var active_combo_tags: PackedStringArray = []


func configure(primary_one: int, primary_two: int, fallback: int, locked_round: int) -> void:
	round_locked = locked_round
	primary_intents = PackedInt32Array([primary_one, primary_two])
	fallback_intent = fallback
	current_stage = STAGE_PRIMARY_ONE
	_reset_stage_runtime()


func clear() -> void:
	round_locked = 0
	primary_intents.clear()
	fallback_intent = EnemyIntentCategory.Type.DEFEND
	current_stage = STAGE_FINISHED
	forced_steps.clear()
	planned_manifest_card_ids.clear()
	planned_manifest_fields.clear()
	expected_decay_life = 0
	_reset_stage_runtime()


func is_empty() -> bool:
	return forced_steps.is_empty() and is_finished()


func get_current_category() -> int:
	if current_stage >= STAGE_PRIMARY_ONE and current_stage <= STAGE_PRIMARY_TWO \
			and current_stage < primary_intents.size():
		return primary_intents[current_stage]
	if current_stage == STAGE_FALLBACK:
		return fallback_intent
	return -1


func advance_stage() -> void:
	if is_finished():
		return
	current_stage += 1
	if current_stage > STAGE_FALLBACK:
		current_stage = STAGE_FINISHED
	_reset_stage_runtime()


func finish() -> void:
	current_stage = STAGE_FINISHED
	_reset_stage_runtime()


func is_fallback_stage() -> bool:
	return current_stage == STAGE_FALLBACK


func is_finished() -> bool:
	return current_stage >= STAGE_FINISHED


func get_headline() -> String:
	if primary_intents.size() < 2:
		return "观望"
	return "%s → %s" % [
		EnemyIntentCategory.get_label(primary_intents[0]),
		EnemyIntentCategory.get_label(primary_intents[1]),
	]


func get_summary() -> String:
	var parts := PackedStringArray(["备 %s" % EnemyIntentCategory.get_label(fallback_intent)])
	if not planned_manifest_fields.is_empty():
		parts.append("显化 %s" % "、".join(planned_manifest_fields))
	if expected_decay_life > 0:
		parts.append("衰退 -%d生命" % expected_decay_life)
	return " / ".join(parts)


func _reset_stage_runtime() -> void:
	stage_action_count = 0
	stage_start_ap = -1
	active_combo_tags.clear()
