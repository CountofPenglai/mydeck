extends CardEffect
class_name RangerExoticBottleCardEffect

const ADVANCED_ELEMENTS: Array[int] = [
	BattleSurfaceState.Element.STEAM,
	BattleSurfaceState.Element.LAVA,
	BattleSurfaceState.Element.BLAZE,
	BattleSurfaceState.Element.POISON_BOG,
	BattleSurfaceState.Element.ICE,
	BattleSurfaceState.Element.SANDSTORM,
]

@export_range(1, 12, 1) var target_range: int = 4
@export_range(0, 99, 1) var center_base_damage: int = 8
@export_range(0, 99, 1) var adjacent_base_damage: int = 4


func requires_ranger_recipe_choice(context: Dictionary = {}) -> bool:
	return not context.has("selected_blend") or not context.has("selected_catalyst")


func get_ranger_recipe_options(context: Dictionary = {}) -> Array[Dictionary]:
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var result: Array[Dictionary] = []
	if user == null or not user.is_ranger():
		return result
	for blend in ADVANCED_ELEMENTS:
		var ingredients: Array[int] = BattleSurfaceState.new().get_component_elements(blend)
		for catalyst in BattleSurfaceState.BASE_ELEMENTS:
			var costs: Array[int] = ingredients.duplicate()
			costs.append(catalyst)
			if user.ranger_state.can_pay_elements(costs):
				result.append({
					"label": "%s + 催化剂%s" % [BattleSurfaceState.label(blend), BattleSurfaceState.label(catalyst)],
					"selected_blend": blend,
					"selected_catalyst": catalyst,
				})
	return result


func can_play(context: Dictionary = {}) -> bool:
	var user: BattleUnitState = context.get("user") as BattleUnitState
	return user != null and user.is_ranger() and _has_any_payment(user)


func can_pay_play_cost(context: Dictionary = {}) -> bool:
	var user: BattleUnitState = context.get("user") as BattleUnitState
	return user != null and not _resolve_payment(context, user).is_empty()


func pay_play_cost(context: Dictionary = {}) -> bool:
	var user: BattleUnitState = context.get("user") as BattleUnitState
	if user == null:
		return false
	var payment := _resolve_payment(context, user)
	if payment.is_empty():
		return false
	var costs: Array[int] = []
	costs.assign(payment.get("costs", []) as Array)
	if not user.ranger_state.pay_elements(costs):
		return false
	user.sync_ranger_element_inventory()
	return true


func are_targets_valid(context: Dictionary = {}, targets: Array = [], write_log: bool = true) -> bool:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	if controller == null or user == null or targets.size() != 1 or not (targets[0] is Vector2i):
		return false
	var target_cell: Vector2i = targets[0]
	if controller.map_data == null or not controller.map_data.is_valid_cell(target_cell):
		return false
	if controller.map_data.get_distance(user.cell, target_cell) <= target_range:
		return true
	if write_log:
		controller._emit_log("异域爆瓶的目标位置超出范围 %d。" % target_range)
	return false


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	if controller == null or user == null or card == null or targets.size() != 1 or not (targets[0] is Vector2i):
		return

	var payment := _resolve_payment(context, user)
	if payment.is_empty():
		return

	var target_cell: Vector2i = targets[0]
	var blend := int(payment.get("blend", BattleSurfaceState.Element.NONE))
	var catalyst := int(payment.get("catalyst", BattleSurfaceState.Element.NONE))
	controller._emit_log("%s 消耗元素调制%s爆瓶（催化剂：%s）。" % [
		user.get_display_name(),
		BattleSurfaceState.label(blend),
		BattleSurfaceState.label(catalyst),
	])

	var damage_context := {
		"controller": controller,
		"source": card,
		"card": card,
		"resolved_damage_type": CardEnums.DamageType.AGILITY,
	}
	var damage_bonus := user.get_damage_bonus(damage_context)
	var ambush_multiplier := controller.consume_ranger_stealth_for_attack(user)
	_apply_bottle_damage(controller, user, target_cell, center_base_damage, damage_bonus, ambush_multiplier, "异域爆瓶中心")
	for adjacent_cell in BattleHexGrid.neighbors(target_cell):
		if controller.map_data.is_valid_cell(adjacent_cell):
			_apply_bottle_damage(controller, user, adjacent_cell, adjacent_base_damage, damage_bonus, ambush_multiplier, "异域爆瓶波及")
	user.remove_expired_statuses()

	controller.apply_advanced_surface(target_cell, blend, {
		"source": user,
		"source_cell": user.cell,
		"source_card": card,
	})
	for adjacent_cell in BattleHexGrid.neighbors(target_cell):
		if controller.map_data.is_valid_cell(adjacent_cell):
			controller.apply_advanced_surface(adjacent_cell, blend, {
				"source": user,
				"source_cell": target_cell,
				"source_card": card,
			})


func _apply_bottle_damage(controller: BattleController, user: BattleUnitState, cell: Vector2i, base_damage: int, damage_bonus: int, multiplier: float, label: String) -> void:
	var total := maxi(0, ceili(float(base_damage + damage_bonus) * multiplier))
	var target := controller.get_unit_at_cell(cell)
	if target != null and target.faction != user.faction and target.is_alive():
		controller.apply_damage(user, target, total, label, {
			"source_card": null,
			"area": true,
			"agility_damage": true,
		})
	var battle_object := controller.get_battle_object_at_cell(cell)
	if battle_object != null:
		controller.apply_object_damage(user, battle_object, total, label, {
			"area": true,
			"source_cell": user.cell,
		})


func _resolve_payment(context: Dictionary, user: BattleUnitState) -> Dictionary:
	var selected_blend := _resolve_advanced_element(context.get("selected_blend", BattleSurfaceState.Element.NONE))
	var selected_catalyst := _resolve_base_element(context.get("selected_catalyst", BattleSurfaceState.Element.NONE))
	if ADVANCED_ELEMENTS.has(selected_blend) and BattleSurfaceState.BASE_ELEMENTS.has(selected_catalyst):
		var costs: Array[int] = BattleSurfaceState.new().get_component_elements(selected_blend)
		costs.append(selected_catalyst)
		if user.ranger_state.can_pay_elements(costs):
			return {"blend": selected_blend, "catalyst": selected_catalyst, "costs": costs}
	return {}


func _has_any_payment(user: BattleUnitState) -> bool:
	for blend in ADVANCED_ELEMENTS:
		if not _payment_for_blend(user, blend, BattleSurfaceState.Element.NONE).is_empty():
			return true
	return false


func _payment_for_blend(user: BattleUnitState, blend: int, preferred_catalyst: int) -> Dictionary:
	var ingredients: Array[int] = BattleSurfaceState.new().get_component_elements(blend)
	if ingredients.size() != 2:
		return {}
	var catalysts: Array[int] = []
	if BattleSurfaceState.BASE_ELEMENTS.has(preferred_catalyst):
		catalysts.append(preferred_catalyst)
	for element in BattleSurfaceState.BASE_ELEMENTS:
		if not catalysts.has(element):
			catalysts.append(element)
	for catalyst in catalysts:
		var costs: Array[int] = ingredients.duplicate()
		costs.append(catalyst)
		if user.ranger_state.can_pay_elements(costs):
			return {"blend": blend, "catalyst": catalyst, "costs": costs}
	return {}


func _resolve_advanced_element(value: Variant) -> int:
	if value is int or value is float:
		return int(value)
	match str(value).to_lower():
		"steam": return BattleSurfaceState.Element.STEAM
		"lava": return BattleSurfaceState.Element.LAVA
		"blaze": return BattleSurfaceState.Element.BLAZE
		"poison_bog", "poison bog": return BattleSurfaceState.Element.POISON_BOG
		"ice": return BattleSurfaceState.Element.ICE
		"sandstorm": return BattleSurfaceState.Element.SANDSTORM
		_: return BattleSurfaceState.Element.NONE


func _resolve_base_element(value: Variant) -> int:
	if value is int or value is float:
		return int(value)
	match str(value).to_lower():
		"fire": return BattleSurfaceState.Element.FIRE
		"water": return BattleSurfaceState.Element.WATER
		"earth": return BattleSurfaceState.Element.EARTH
		"air": return BattleSurfaceState.Element.AIR
		_: return BattleSurfaceState.Element.NONE
