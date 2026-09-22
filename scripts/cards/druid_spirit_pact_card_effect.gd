extends CardEffect
class_name DruidSpiritPactCardEffect


const ASSIST_STATUS := preload("res://scripts/status/druid_assist_status.gd")


func _init() -> void:
	uses_strike = true


func requires_weapon_choice(context: Dictionary = {}) -> bool:
	return _is_inverted(context)


func requires_preplay_configuration(context: Dictionary = {}) -> bool:
	return not _is_inverted(context)


func get_preplay_configuration(_context: Dictionary = {}) -> Dictionary:
	return {
		"title": "灵契：选择效果与共鸣",
		"options": ["抽2张牌", "最近敌人吸血打击", "获得6点护甲"],
		"minimum": 1,
		"maximum": 3,
		"resonance_cost": 2,
	}


func is_unit_target_allowed(context: Dictionary = {}, target: BattleUnitState = null) -> bool:
	var user := context.get("user") as BattleUnitState
	if user == null or target == null:
		return false
	return target.faction != user.faction if _is_inverted(context) else target.faction == user.faction


func can_pay_play_cost(context: Dictionary = {}) -> bool:
	var choices := _choice_indices(context)
	if _is_inverted(context):
		return true
	if choices.is_empty() or choices.size() > 3:
		return false
	for choice in choices:
		if choice < 0 or choice > 2:
			return false
	if choices.size() != choices.duplicate().size():
		return false
	if choices.size() > 1 and not bool(context.get("pay_resonance", false)):
		return false
	var user := context.get("user") as BattleUnitState
	var card := context.get("card") as CardData
	return user != null and card != null and (not bool(context.get("pay_resonance", false)) or user.can_pay_mana(user.get_card_resonance_cost(card, context)))


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller := context.get("controller") as BattleController
	var user := context.get("user") as BattleUnitState
	var card := context.get("card") as CardData
	if controller == null or user == null or card == null or targets.size() != 1 or not (targets[0] is BattleUnitState):
		return
	var target := targets[0] as BattleUnitState
	if _is_inverted(context):
		controller.perform_unit_strike_with_after_effects(
			user, target, card, "协猎", str(context.get("equipment_slot", "")),
			Callable(self, "_grant_assist").bind(controller, user)
		)
		return
	for choice in _choice_indices(context):
		match choice:
			0:
				target.draw_cards(2, controller.rng, context)
			1:
				var strike := controller.druid_battle_rules.get_automatic_strike(target)
				if not strike.is_empty():
					var actual := controller.perform_strike_with_options(target, strike["target"] as BattleUnitState, card, 0, 1.0, "灵契：吸血打击", str(strike["equipment_slot"]), {})
					if actual > 0:
						controller.heal_unit(target, target, actual, "灵契吸血")
			2:
				target.gain_armor(6, context)


func _grant_assist(controller: BattleController, user: BattleUnitState) -> void:
	if controller == null or user == null or not user.is_alive():
		return
	var previous := user.get_status("druid_assist") as DruidAssistStatus
	var status := ASSIST_STATUS.new()
	status.source_unit_id = user.unit_id
	status.expires_on_source_turn = user.turn_serial + 1
	if previous != null:
		status.last_used_active_turn_serial = previous.last_used_active_turn_serial
	user.remove_status(status.status_id)
	user.add_status(status)


func _choice_indices(context: Dictionary) -> Array[int]:
	var result: Array[int] = []
	for raw in context.get("choice_indices", []):
		var choice := int(raw)
		if result.has(choice):
			return []
		result.append(choice)
	result.sort()
	return result


func _is_inverted(context: Dictionary) -> bool:
	return int(context.get("druid_orientation", CardEnums.DruidOrientation.UPRIGHT)) == CardEnums.DruidOrientation.INVERTED
