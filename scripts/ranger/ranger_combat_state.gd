extends RefCounted
class_name RangerCombatState

const BattleSurfaceState = preload("res://scripts/battle/battle_surface_state.gd")

const ELEMENT_LIMIT := 5

var stealth_active: bool = false
var stealth_expires_turn_serial: int = -1
var combo_points: int = 0
var combo_window_open: bool = false
var element_inventory: Dictionary = {}
var prepared_blend: int = BattleSurfaceState.Element.NONE
var prepared_weapon_slot: String = ""
var discard_debt: int = 0
var pending_hand_discard_count: int = 0
var cards_played_this_turn: int = 0
var elements_collected_this_turn: int = 0
var universal_combo_ready: bool = false
var universal_combo_expires_turn_serial: int = -1
var no_place_recall_charges: int = 3
var active_weapon_lock_slot: String = ""
var weapon_lock_expires_turn_serial: int = -1


func reset_for_battle() -> void:
	stealth_active = false
	stealth_expires_turn_serial = -1
	combo_points = 0
	combo_window_open = false
	element_inventory.clear()
	prepared_blend = BattleSurfaceState.Element.NONE
	prepared_weapon_slot = ""
	discard_debt = 0
	pending_hand_discard_count = 0
	cards_played_this_turn = 0
	elements_collected_this_turn = 0
	universal_combo_ready = false
	universal_combo_expires_turn_serial = -1
	no_place_recall_charges = 3
	active_weapon_lock_slot = ""
	weapon_lock_expires_turn_serial = -1


func load_element_inventory(source: Dictionary) -> void:
	element_inventory.clear()
	for element in BattleSurfaceState.BASE_ELEMENTS:
		var amount := maxi(0, int(source.get(element, 0)))
		for _index in range(amount):
			if get_element_total() >= ELEMENT_LIMIT:
				return
			element_inventory[element] = int(element_inventory.get(element, 0)) + 1


func start_turn(turn_serial: int) -> void:
	combo_window_open = false
	cards_played_this_turn = 0
	elements_collected_this_turn = 0
	if weapon_lock_expires_turn_serial >= 0 and turn_serial >= weapon_lock_expires_turn_serial:
		active_weapon_lock_slot = ""
		weapon_lock_expires_turn_serial = -1
	if universal_combo_expires_turn_serial >= 0 and turn_serial >= universal_combo_expires_turn_serial:
		universal_combo_ready = false
		universal_combo_expires_turn_serial = -1


func add_element(element: int, amount: int = 1) -> int:
	if not BattleSurfaceState.BASE_ELEMENTS.has(element) or amount <= 0:
		return 0
	var added := 0
	for _i in range(amount):
		if get_element_total() >= ELEMENT_LIMIT:
			break
		element_inventory[element] = int(element_inventory.get(element, 0)) + 1
		added += 1
	elements_collected_this_turn += added
	return added


func get_element_total() -> int:
	var total := 0
	for amount_value in element_inventory.values():
		total += int(amount_value)
	return total


func get_element_type_count() -> int:
	var count := 0
	for element in BattleSurfaceState.BASE_ELEMENTS:
		if int(element_inventory.get(element, 0)) > 0:
			count += 1
	return count


func can_pay_elements(elements: Array[int]) -> bool:
	var required: Dictionary = {}
	for element in elements:
		required[element] = int(required.get(element, 0)) + 1
	for element_value in required.keys():
		if int(element_inventory.get(element_value, 0)) < int(required[element_value]):
			return false
	return true


func pay_elements(elements: Array[int]) -> bool:
	if not can_pay_elements(elements):
		return false
	for element in elements:
		var remaining := int(element_inventory.get(element, 0)) - 1
		if remaining <= 0:
			element_inventory.erase(element)
		else:
			element_inventory[element] = remaining
	return true


func get_summary() -> String:
	var parts := PackedStringArray()
	for element in BattleSurfaceState.BASE_ELEMENTS:
		var amount := int(element_inventory.get(element, 0))
		if amount > 0:
			parts.append("%s%d" % [BattleSurfaceState.label(element), amount])
	return "无" if parts.is_empty() else " ".join(parts)
