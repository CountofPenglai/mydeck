extends CardEffect
class_name DruidOvergrowthGraftCardEffect


const ROOT_STATUS := preload("res://scripts/status/druid_root_status.gd")


func _init() -> void:
	uses_strike = true


func requires_weapon_choice(context: Dictionary = {}) -> bool:
	return not _is_upright(context)


func is_unit_target_allowed(context: Dictionary = {}, target: BattleUnitState = null) -> bool:
	var user := context.get("user") as BattleUnitState
	if user == null or target == null:
		return false
	return true if _is_upright(context) else target.faction != user.faction


func are_targets_valid(context: Dictionary = {}, targets: Array = [], _write_log: bool = true) -> bool:
	return targets.size() == 1 and targets[0] is BattleUnitState and is_unit_target_allowed(context, targets[0] as BattleUnitState)


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller := context.get("controller") as BattleController
	var user := context.get("user") as BattleUnitState
	var card := context.get("card") as CardData
	if controller == null or user == null or card == null or targets.size() != 1 or not (targets[0] is BattleUnitState):
		return
	var target := targets[0] as BattleUnitState
	if _is_upright(context):
		target.add_status(ROOT_STATUS.new())
		controller.mark_played_card_to_mana(context)
		return
	var equipment_slot := str(context.get("equipment_slot", ""))
	controller.perform_unit_strike_with_after_effects(
		user, target, card, "血潮连击", equipment_slot,
		Callable(self, "_after_first_strike").bind(context, controller, user, target, card, equipment_slot)
	)


func get_mana_production(_owner: BattleUnitState, _zone_card: CardData, context: Dictionary = {}) -> int:
	var controller := context.get("controller") as BattleController
	if controller == null:
		return 0
	var rooted := 0
	for candidate_value in controller.units:
		var candidate := candidate_value as BattleUnitState
		if candidate != null and candidate.is_alive() and candidate.has_status("druid_root"):
			rooted += 1
	return rooted


func _after_first_strike(context: Dictionary, controller: BattleController, user: BattleUnitState, target: BattleUnitState, card: CardData, equipment_slot: String) -> void:
	if not _can_follow_up(controller, user, target, card, equipment_slot) or not user.pay_mana(2, context):
		return
	controller.perform_unit_strike_with_after_effects(
		user, target, card, "血潮连击：第二击", equipment_slot,
		Callable(self, "_after_second_strike").bind(controller, user, target, card, equipment_slot)
	)


func _after_second_strike(controller: BattleController, user: BattleUnitState, target: BattleUnitState, card: CardData, equipment_slot: String) -> void:
	if not _can_follow_up(controller, user, target, card, equipment_slot):
		return
	var root_target := _nearest_root_in_weapon_range(controller, user, equipment_slot)
	if root_target == null:
		return
	root_target.remove_status("druid_root")
	controller.resolution_runner.begin_attack_scope()
	var actual := controller.perform_strike(user, target, card, "血潮连击：吸血第三击", equipment_slot)
	controller.resolution_runner.end_attack_scope()
	if actual > 0:
		controller.heal_unit(user, user, actual, "血潮连击吸血")


func _can_follow_up(controller: BattleController, user: BattleUnitState, target: BattleUnitState, card: CardData, equipment_slot: String) -> bool:
	return controller != null and user != null and target != null and user.is_alive() and user.is_deployed \
		and target.is_alive() and target.is_deployed and target.faction != user.faction \
		and user.can_use_attack_mode(equipment_slot, {"controller": controller, "target": target, "card": card}) \
		and controller._targets_are_valid(user, card, [target], false, equipment_slot, CardEnums.CardPlayMode.NORMAL, {"druid_orientation": CardEnums.DruidOrientation.INVERTED})


func _nearest_root_in_weapon_range(controller: BattleController, user: BattleUnitState, equipment_slot: String) -> BattleUnitState:
	var best: BattleUnitState = null
	var best_distance := 999999
	for candidate_value in controller.units:
		var candidate := candidate_value as BattleUnitState
		if candidate == null or not candidate.is_alive() or not candidate.has_status("druid_root"):
			continue
		var distance := user.get_range_distance_to(candidate, {"controller": controller, "equipment_slot": equipment_slot})
		if distance > controller.get_effective_attack_range_against(user, candidate, equipment_slot):
			continue
		if distance < best_distance or (distance == best_distance and (best == null or candidate.unit_id < best.unit_id)):
			best = candidate
			best_distance = distance
	return best


func _is_upright(context: Dictionary) -> bool:
	return int(context.get("druid_orientation", CardEnums.DruidOrientation.UPRIGHT)) == CardEnums.DruidOrientation.UPRIGHT
