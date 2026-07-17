extends Resource
class_name EnemyIntentPlan

@export var round_locked: int = 0
@export var steps: Array[Dictionary] = []
@export var attack_total: int = 0
@export var defense_total: int = 0


func clear() -> void:
	round_locked = 0
	steps.clear()
	attack_total = 0
	defense_total = 0


func is_empty() -> bool:
	return steps.is_empty()


func get_headline() -> String:
	if steps.is_empty():
		return "观望"
	return str(steps[0].get("label", "行动"))


func get_summary() -> String:
	var parts := PackedStringArray()
	if attack_total > 0:
		parts.append("攻 %d" % attack_total)
	if defense_total > 0:
		parts.append("防 %d" % defense_total)
	return " / ".join(parts) if not parts.is_empty() else "无伤害预告"

