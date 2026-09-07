extends CardEffect
class_name RangerExoticBottleCardEffect

@export_range(0, 99, 1) var center_base_damage: int = 8
@export_range(0, 99, 1) var adjacent_base_damage: int = 4

func get_fixed_equipment_slot(_context: Dictionary = {}) -> String:
	return "paired"


func requires_ranger_recipe_choice(context: Dictionary = {}) -> bool:
	return not context.has("bottle_payload")


func get_ranger_recipe_options(context: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for payload in _preview_payloads(context):
		var labels: Array[String] = []
		for element in payload:
			labels.append(BattleSurfaceState.label(element))
		result.append({"label": "装载：%s" % " → ".join(labels), "bottle_payload": payload.duplicate()})
	return result


func can_play(context: Dictionary = {}) -> bool:
	var user := context.get("user") as BattleUnitState
	if user == null or not user.is_ranger():
		return false
	var paired_equipment := user.character_state.get_equipment_for_attack_slot(
		"paired",
		user.get_active_weapon_face_index()
	)
	if paired_equipment == null or paired_equipment.range_type != EquipmentData.WeaponRangeType.RANGED:
		return false
	return not _preview_payloads(context).is_empty()


func modify_effective_range(user_value, equipment_slot: String, current_range: int) -> int:
	var user := user_value as BattleUnitState
	if user == null or equipment_slot != "paired":
		return current_range
	return user.get_attack_range_for_targeting(equipment_slot, {"controller": user.battle_controller})


func can_pay_play_cost(context: Dictionary = {}) -> bool:
	var payload := _payload_from_context(context)
	if payload.is_empty():
		return false
	var available := _preview_elements(context)
	for element in payload:
		if int(available.get(element, 0)) <= 0:
			return false
	return true


func are_targets_valid(context: Dictionary = {}, targets: Array = [], write_log: bool = true) -> bool:
	var controller := context.get("controller") as BattleController
	var user := context.get("user") as BattleUnitState
	if controller == null or user == null or targets.size() != 1 or not targets[0] is Vector2i:
		return false
	var cell := targets[0] as Vector2i
	if controller.map_data == null or not controller.map_data.is_valid_cell(cell):
		return false
	if controller.map_data.get_distance(user.cell, cell) <= controller.get_effective_targeting_range_at_cell(user, cell, "paired"):
		return true
	if write_log:
		controller._emit_log("异域爆瓶的目标位置超出远程配件实际射程。")
	return false


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller := context.get("controller") as BattleController
	var user := context.get("user") as BattleUnitState
	var card := context.get("card") as CardData
	if controller == null or user == null or card == null or targets.size() != 1 or not targets[0] is Vector2i:
		return
	var payload := _payload_from_context(context)
	var cells := _collection_cells(controller, user)
	var batch := controller.collect_ranger_temporary_batch(user, cells, "异域爆瓶", {"card": card})
	if not _batch_contains(batch.get("elements", {}) as Dictionary, payload):
		return
	_store_leftovers(user, batch.get("elements", {}) as Dictionary, payload)
	var target_cell := targets[0] as Vector2i
	var bonus := user.get_damage_bonus({"controller": controller, "source": card, "card": card, "resolved_damage_type": CardEnums.DamageType.AGILITY})
	var multiplier := controller.consume_ranger_stealth_for_attack(user)
	controller.resolution_runner.begin_attack_scope()
	_apply_damage(controller, user, target_cell, center_base_damage, bonus, multiplier, "异域爆瓶中心", card)
	for cell in BattleHexGrid.neighbors(target_cell):
		if controller.map_data.is_valid_cell(cell):
			_apply_damage(controller, user, cell, adjacent_base_damage, bonus, multiplier, "异域爆瓶波及", card)
	controller.resolution_runner.drain_active_attack_effects()
	for element in payload:
		controller.apply_surface_element(target_cell, element, {
			"source": user,
			"source_cell": user.cell,
			"source_card": card,
			"bottle_payload": true,
		})
	var final_surface := controller.surface_state.get_element(target_cell)
	if final_surface != BattleSurfaceState.Element.NONE:
		for cell in BattleHexGrid.neighbors(target_cell):
			if controller.map_data.is_valid_cell(cell):
				controller.apply_surface_element(cell, final_surface, {
					"source": user,
					"source_cell": target_cell,
					"source_card": card,
					"bottle_spread": true,
				})
	controller.resolution_runner.end_attack_scope()
	user.remove_expired_statuses()

func _apply_damage(controller: BattleController, user: BattleUnitState, cell: Vector2i, base: int, bonus: int, multiplier: float, label: String, card: CardData) -> void:
	var amount := maxi(0, ceili(float(base + bonus) * multiplier))
	var unit := controller.get_unit_at_cell(cell)
	if unit != null and unit.faction != user.faction and unit.is_alive():
		controller.apply_damage(user, unit, amount, label, {
			"source_card": card,
			"area": true,
			"agility_damage": true,
		})
	var object := controller.get_battle_object_at_cell(cell)
	if object != null:
		controller.apply_object_damage(user, object, amount, label, {
			"source_card": card,
			"area": true,
			"strike": true,
			"source_cell": user.cell,
		})

func _preview_payloads(context: Dictionary) -> Array[Array]:
	var elements := _preview_elements(context)
	var bases: Array[int] = []
	for element in BattleSurfaceState.BASE_ELEMENTS:
		if int(elements.get(element, 0)) > 0:
			bases.append(element)
	var result: Array[Array] = []
	for first in bases:
		result.append([first])
		for second in bases:
			if first != second: result.append([first, second])
	return result

func _preview_elements(context: Dictionary) -> Dictionary:
	var controller := context.get("controller") as BattleController
	var user := context.get("user") as BattleUnitState
	if controller == null or user == null:
		return {}
	return RangerSurfaceElementCollector.preview(
		controller,
		user,
		_collection_cells(controller, user),
		"异域爆瓶",
		context
	).get("elements", {}) as Dictionary

func _collection_cells(controller: BattleController, user: BattleUnitState) -> Array[Vector2i]:
	var result: Array[Vector2i] = [user.cell]
	for cell in BattleHexGrid.neighbors(user.cell):
		if controller.map_data.is_valid_cell(cell):
			result.append(cell)
	return result

func _payload_from_context(context: Dictionary) -> Array[int]:
	var raw: Array = context.get("bottle_payload", []) as Array
	if raw.is_empty() or raw.size() > 2:
		return []
	var result: Array[int] = []
	for value in raw:
		var element := int(value)
		if not BattleSurfaceState.BASE_ELEMENTS.has(element) or result.has(element):
			return []
		result.append(element)
	return result

func _batch_contains(elements: Dictionary, payload: Array[int]) -> bool:
	for element in payload:
		if int(elements.get(element, 0)) < 1:
			return false
	return true

func _store_leftovers(user: BattleUnitState, elements: Dictionary, payload: Array[int]) -> void:
	for element_value in elements:
		var element := int(element_value)
		var amount := int(elements.get(element, 0)) - (1 if payload.has(element) else 0)
		user.ranger_state.store_element_without_collection(element, amount)
	user.sync_ranger_element_inventory()
