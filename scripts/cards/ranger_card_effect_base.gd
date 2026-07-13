extends CardEffect
class_name RangerCardEffectBase


func _enqueue_combo_completion(context: Dictionary, priority: int = -100) -> void:
	# Combo completion is centralized in BattleController after the whole card resolves.
	pass
