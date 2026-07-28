extends RefCounted
class_name MageCombatState

const BattleSurfaceState = preload("res://scripts/battle/battle_surface_state.gd")

var spell_mana: Dictionary = {}
var discard_conversion_used: bool = false
var active_infusion_used: bool = false


func reset_for_battle() -> void:
	spell_mana.clear()
	for element in BattleSurfaceState.BASE_ELEMENTS:
		spell_mana[element] = 0
	start_action_phase()


func start_action_phase() -> void:
	discard_conversion_used = false
	active_infusion_used = false


func get_mana(element: int) -> int:
	return maxi(0, int(spell_mana.get(element, 0)))


func gain_mana(element: int, amount: int) -> int:
	if not BattleSurfaceState.BASE_ELEMENTS.has(element):
		return 0
	var actual := maxi(0, amount)
	if actual <= 0:
		return 0
	spell_mana[element] = get_mana(element) + actual
	return actual


func can_pay_mana(element: int, amount: int = 1) -> bool:
	return BattleSurfaceState.BASE_ELEMENTS.has(element) and get_mana(element) >= maxi(0, amount)


func pay_mana(element: int, amount: int = 1) -> bool:
	var cost := maxi(0, amount)
	if not can_pay_mana(element, cost):
		return false
	spell_mana[element] = get_mana(element) - cost
	return true


func gain_mana_batch(gains: Dictionary) -> Dictionary:
	var actual: Dictionary = {}
	for element_value in gains:
		var element := int(element_value)
		var gained := gain_mana(element, int(gains[element_value]))
		if gained > 0:
			actual[element] = gained
	return actual


func snapshot() -> Dictionary:
	return {
		"spell_mana": spell_mana.duplicate(true),
		"discard_conversion_used": discard_conversion_used,
		"active_infusion_used": active_infusion_used,
	}


func restore(snapshot_data: Dictionary) -> void:
	spell_mana = (snapshot_data.get("spell_mana", {}) as Dictionary).duplicate(true)
	for element in BattleSurfaceState.BASE_ELEMENTS:
		if not spell_mana.has(element):
			spell_mana[element] = 0
	discard_conversion_used = bool(snapshot_data.get("discard_conversion_used", false))
	active_infusion_used = bool(snapshot_data.get("active_infusion_used", false))
