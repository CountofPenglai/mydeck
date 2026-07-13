extends CardEffect
class_name RangerHunterThreeActsCardEffect


func requires_weapon_choice(_context: Dictionary = {}) -> bool:
	return true


func is_unit_target_allowed(context: Dictionary = {}, target: BattleUnitState = null) -> bool:
	var user: BattleUnitState = context.get("user") as BattleUnitState
	return user != null and target != null and target.is_alive() and target.faction != user.faction


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	var target: BattleUnitState = targets[0] as BattleUnitState if targets.size() == 1 else null
	if controller == null or user == null or card == null or target == null:
		return
	var runtime := user.get_card_runtime_state(card)
	runtime["ranger_three_acts_target"] = target
	runtime["ranger_three_acts_slot"] = str(context.get("equipment_slot", ""))
	runtime["ranger_three_acts_index"] = 0
	if user.move_hand_card_to_enchant(card, context):
		controller._emit_log("%s 对 %s 布置猎手三幕。" % [user.get_display_name(), target.get_display_name()])


func on_zone_owner_after_card_played(owner: BattleUnitState, zone_card: CardData, played_card: CardData, context: Dictionary = {}) -> void:
	if owner == null or zone_card == null or played_card == zone_card:
		return
	var controller: BattleController = context.get("controller") as BattleController
	if controller == null:
		return
	var runtime := owner.get_card_runtime_state(zone_card)
	var act_index := int(runtime.get("ranger_three_acts_index", 0)) + 1
	runtime["ranger_three_acts_index"] = act_index
	var target: BattleUnitState = runtime.get("ranger_three_acts_target") as BattleUnitState
	var equipment_slot := str(runtime.get("ranger_three_acts_slot", ""))
	match act_index:
		1:
			controller.enqueue_effect(Callable(self, "_resolve_first_act"), [controller, target], 0, "猎手三幕：扰乱")
		2:
			controller.enqueue_effect(Callable(self, "_resolve_second_act"), [controller, owner, target, zone_card, equipment_slot], 0, "猎手三幕：追猎")
		_:
			controller.enqueue_effect(Callable(self, "_resolve_third_act"), [controller, owner, zone_card], 0, "猎手三幕：隐没")


func on_zone_owner_turn_end(owner: BattleUnitState, zone_card: CardData, context: Dictionary = {}) -> void:
	if owner == null or zone_card == null or not owner.has_card_in_enchant(zone_card):
		return
	owner.move_enchant_card_to_discard(zone_card, {
		"controller": context.get("controller"),
		"source": owner,
		"reason": "ranger_three_acts_turn_end",
	})


func _resolve_first_act(controller: BattleController, target: BattleUnitState) -> void:
	if target == null or not target.is_alive() or target.hand.is_empty():
		return
	var index := controller.rng.randi_range(0, target.hand.size() - 1)
	var discarded: CardData = target.hand[index]
	target.discard_card(discarded, {"controller": controller, "source": target, "reason": "ranger_three_acts"})
	controller._emit_log("猎手三幕令 %s 随机弃置 %s。" % [target.get_display_name(), discarded.card_name])


func _resolve_second_act(controller: BattleController, owner: BattleUnitState, target: BattleUnitState, zone_card: CardData, equipment_slot: String) -> void:
	if owner == null or target == null or not owner.is_alive() or not target.is_alive():
		return
	if owner.cell_distance_to(target) > controller.get_effective_attack_range_against(owner, target, equipment_slot):
		return
	controller.perform_strike(owner, target, zone_card, "猎手三幕", equipment_slot)


func _resolve_third_act(controller: BattleController, owner: BattleUnitState, zone_card: CardData) -> void:
	if owner == null:
		return
	if owner.is_alive():
		controller.enter_ranger_stealth(owner, "猎手三幕")
	owner.move_enchant_card_to_discard(zone_card, {
		"controller": controller,
		"source": owner,
		"reason": "ranger_three_acts_complete",
	})
