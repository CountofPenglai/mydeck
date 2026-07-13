extends StatusEffect
class_name DruidCanopyShelterStatus

@export_range(0, 9, 1) var draw_count: int = 2


func _init() -> void:
	status_id = "druid_canopy_shelter"
	display_name = "古树庇护"


func on_turn_start(unit: BattleUnitState, context: Dictionary = {}) -> void:
	if unit == null or stacks <= 0:
		return
	var controller: BattleController = context.get("controller") as BattleController
	var current_armor := unit.get_armor_stacks()
	var retained_armor := floori(float(current_armor) * 0.5)
	unit.clear_armor({"controller": controller, "reason": "druid_canopy_shelter_expired"})
	if retained_armor > 0:
		unit.gain_armor(retained_armor, {"controller": controller, "reason": "druid_canopy_shelter_retained"})
	var drawn := 0
	if controller != null:
		drawn = unit.draw_cards(draw_count, controller.rng, context)
		controller._emit_log("%s 的古树庇护结束，保留 %d 护甲并抽取 %d 张牌。" % [unit.get_display_name(), retained_armor, drawn])
	stacks = 0
