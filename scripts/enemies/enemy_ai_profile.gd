extends Resource
class_name EnemyAIProfile

enum Preset {
	BALANCED,
	RANGED_CONTROL,
	LOW_HEALTH_GUARD,
	LOW_HEALTH_BERSERK,
}

@export_enum("均衡", "远程控距", "残血固守", "残血狂攻") var preset: int = Preset.BALANCED
@export var intent_weights: PackedFloat32Array = []
@export var low_health_modifiers: PackedFloat32Array = []
@export_range(0.05, 0.95, 0.05) var low_health_ratio: float = 0.35
@export_range(0.05, 0.95, 0.05) var harvest_health_ratio: float = 0.3
@export_range(0, 8, 1) var primary_one_ap_budget: int = 1
@export_range(0, 8, 1) var reserve_ap_for_primary_two: int = 2
@export_range(0, 12, 1) var preferred_range_min: int = 1
@export_range(0, 12, 1) var preferred_range_max: int = 2
@export_range(1, 8, 1) var max_actions_per_intent: int = 4
@export_range(0.0, 5.0, 0.1) var random_score_jitter: float = 0.5


static func create_preset(preset_id: int) -> EnemyAIProfile:
	var profile := EnemyAIProfile.new()
	profile.preset = preset_id
	profile.intent_weights = PackedFloat32Array([8.0, 5.0, 10.0, 7.0, 4.0, 1.0, 3.0])
	profile.low_health_modifiers = PackedFloat32Array([0.0, 2.0, 0.0, 0.0, 0.0, 1.0, 1.0])
	match preset_id:
		Preset.RANGED_CONTROL:
			profile.intent_weights = PackedFloat32Array([4.0, 4.0, 10.0, 7.0, 4.0, 9.0, 4.0])
			profile.low_health_modifiers = PackedFloat32Array([-1.0, 3.0, -1.0, 0.0, 0.0, 8.0, 0.0])
			profile.preferred_range_min = 3
			profile.preferred_range_max = 4
		Preset.LOW_HEALTH_GUARD:
			profile.intent_weights = PackedFloat32Array([7.0, 8.0, 8.0, 7.0, 4.0, 3.0, 3.0])
			profile.low_health_modifiers = PackedFloat32Array([-2.0, 12.0, -4.0, 2.0, 0.0, 6.0, -2.0])
		Preset.LOW_HEALTH_BERSERK:
			profile.intent_weights = PackedFloat32Array([9.0, 2.0, 11.0, 6.0, 3.0, 0.0, 8.0])
			profile.low_health_modifiers = PackedFloat32Array([3.0, -6.0, 10.0, 1.0, 0.0, -3.0, 12.0])
		_:
			pass
	return profile


func get_intent_weight(category: int) -> float:
	return _value_at(intent_weights, category)


func get_low_health_modifier(category: int) -> float:
	return _value_at(low_health_modifiers, category)


func _value_at(values: PackedFloat32Array, index: int) -> float:
	return values[index] if index >= 0 and index < values.size() else 0.0
