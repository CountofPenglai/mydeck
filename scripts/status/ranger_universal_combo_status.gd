extends StatusEffect
class_name RangerUniversalComboStatus


func _init() -> void:
	status_id = "ranger_universal_combo"
	display_name = "无缝追击"


func modify_card_ap_cost(unit: BattleUnitState, _card: CardData, current_cost: int, _context: Dictionary = {}) -> int:
	return current_cost


func on_card_ap_cost_paid(unit: BattleUnitState, _card: CardData, context: Dictionary = {}) -> void:
	if unit == null or not unit.ranger_state.universal_combo_ready or stacks <= 0:
		return
	unit.ranger_state.universal_combo_ready = false
	unit.ranger_state.universal_combo_expires_turn_serial = -1
	stacks = 0
	var controller: BattleController = context.get("controller") as BattleController
	if controller != null:
		controller.enqueue_effect(
			Callable(controller, "gain_ranger_combo"),
			[unit, 1],
			-100,
			"无缝追击：万能连击完成",
			context
		)


func on_turn_end(unit: BattleUnitState, _context: Dictionary = {}) -> void:
	if unit != null:
		unit.ranger_state.universal_combo_ready = false
		unit.ranger_state.universal_combo_expires_turn_serial = -1
	stacks = 0
