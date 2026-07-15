extends CardEffect
class_name CurseIndustryCardEffect

const BattleHexGrid = preload("res://scripts/battle/battle_hex_grid.gd")
const DISEASE_CARD := preload("res://resources/cards/curse_disease.tres")

@export var curse_id: String = ""


func can_play(context: Dictionary = {}) -> bool:
	var user := context.get("user") as BattleUnitState
	if user == null:
		return false
	match curse_id:
		"counterfeit":
			return not get_curse_choice_options(context).is_empty() and not get_ordered_discard_choice_cards(context).is_empty()
		"preservation":
			return not get_curse_choice_options(context).is_empty()
		_:
			return true


func can_pay_play_cost(context: Dictionary = {}) -> bool:
	var user := context.get("user") as BattleUnitState
	var card := context.get("card") as CardData
	if user == null:
		return false
	match curse_id:
		"blood":
			return user.get_current_health() > 3 + 2 * _depth(card)
		"counterfeit", "preservation":
			return context.get("selected_curse") is CurseInstance or not get_curse_choice_options(context).is_empty()
		_:
			return true


func pay_play_cost(context: Dictionary = {}) -> bool:
	var user := context.get("user") as BattleUnitState
	var card := context.get("card") as CardData
	var controller := context.get("controller") as BattleController
	if user == null or controller == null:
		return false
	var depth := _depth(card)
	match curse_id:
		"blood":
			return controller.lose_life(user, user, 3 + 2 * depth, "鲜血之业代价", {"curse_source": true}) > 0
		"disease":
			controller.lose_life(user, user, user.hand.size(), "痼病之业代价", {"curse_source": true})
		"passing", "universal_love":
			for other in user.hand.duplicate():
				if other != card:
					user.discard_card(other, {"controller": controller, "reason": "%s_industry_cost" % curse_id})
		"unrest":
			user.set_current_health(1)
		"counterfeit", "preservation":
			var selected := context.get("selected_curse") as CurseInstance
			if selected == null or not selected.deepen():
				return false
	return true


func requires_curse_choice(context: Dictionary = {}) -> bool:
	return curse_id in ["counterfeit", "preservation"] and not context.has("selected_curse")


func get_curse_choice_options(context: Dictionary = {}) -> Array[CurseInstance]:
	var user := context.get("user") as BattleUnitState
	var source_card := context.get("card") as CardData
	var result: Array[CurseInstance] = []
	if user == null or user.character_state == null:
		return result
	for curse in user.character_state.curse_instances:
		if curse == null or curse == source_card.bound_curse_instance or curse.depth >= 3:
			continue
		result.append(curse)
	return result


func get_curse_choice_prompt(_context: Dictionary = {}) -> String:
	return "选择一张未满深度的其他诅咒加深"


func requires_ordered_discard_choice(context: Dictionary = {}) -> bool:
	return curse_id in ["greed", "passing", "counterfeit"] and not context.has("ordered_discard_cards")


func get_ordered_discard_choice_cards(context: Dictionary = {}) -> Array[CardData]:
	var user := context.get("user") as BattleUnitState
	var source_card := context.get("card") as CardData
	if user == null:
		return []
	match curse_id:
		"greed", "passing":
			var choices: Array[CardData] = []
			for unit in user.battle_controller.units:
				choices.append_array(unit.discard_pile)
			if curse_id == "greed":
				choices.append_array(user.draw_pile)
			return choices
		"counterfeit":
			var hand_choices: Array[CardData] = []
			for hand_card in user.hand:
				if hand_card != source_card and not hand_card.is_curse_card():
					hand_choices.append(hand_card)
			return hand_choices
	return []


func get_ordered_discard_choice_max_count(context: Dictionary = {}) -> int:
	var card := context.get("card") as CardData
	if curse_id == "greed":
		return mini(2 + _depth(card), get_ordered_discard_choice_cards(context).size())
	if curse_id == "passing":
		return mini(1 + _depth(card), get_ordered_discard_choice_cards(context).size())
	return 1


func get_ordered_discard_choice_min_count(context: Dictionary = {}) -> int:
	if curse_id == "greed":
		return get_ordered_discard_choice_max_count(context)
	if curse_id == "counterfeit":
		return 1
	return 0


func get_ordered_discard_choice_prompt(_context: Dictionary = {}) -> String:
	match curse_id:
		"greed":
			return "选择要从弃牌堆加入手牌的牌"
		"passing":
			return "选择要生成临时副本的弃牌"
		"counterfeit":
			return "选择要复制的非诅咒手牌"
	return "选择牌"


func is_unit_target_allowed(context: Dictionary = {}, target: BattleUnitState = null) -> bool:
	var user := context.get("user") as BattleUnitState
	return user != null and target != null and target.faction != user.faction


func are_targets_valid(context: Dictionary = {}, targets: Array = [], _write_log: bool = true) -> bool:
	if curse_id == "cripple":
		var user := context.get("user") as BattleUnitState
		var card := context.get("card") as CardData
		if user == null or targets.size() != 1 or not (targets[0] is Vector2i):
			return false
		return BattleHexGrid.distance(user.cell, targets[0]) <= 3 + _depth(card)
	return true


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var user := context.get("user") as BattleUnitState
	var card := context.get("card") as CardData
	var controller := context.get("controller") as BattleController
	if user == null or card == null or controller == null:
		return
	var depth := _depth(card)
	match curse_id:
		"blood":
			_play_blood(user, depth, controller, context)
		"greed":
			_play_greed(user, depth, controller, context)
		"cripple":
			_play_cripple(user, depth, controller, targets, context)
		"disease":
			_play_disease(user, depth, controller, targets, context)
		"passing":
			_play_passing(user, controller, context)
		"possession":
			_play_possession(user, depth, controller, targets, card)
		"unrest":
			_play_unrest(user, depth, controller, context)
		"counterfeit":
			_play_counterfeit(user, depth, context)
		"universal_love":
			_play_universal_love(user, depth, controller, context)
		"gluttony":
			_play_gluttony(user, depth, controller, targets)
		"offspring":
			_play_offspring(user, depth, controller, targets)
		"preservation":
			_play_preservation(user, depth, controller, targets, context)
		"unbound":
			controller.activate_unbound_industry(user, depth)


func _play_blood(user: BattleUnitState, depth: int, controller: BattleController, context: Dictionary) -> void:
	for target in controller.get_units_in_range(user, 3, BattleController.UnitFilter.OPPONENTS):
		var actual := controller.apply_damage(user, target, 8 + 4 * depth, "鲜血之业", {"source_card": context.get("card"), "fixed_damage": true})
		if actual > 0:
			controller.heal_unit(user, user, actual, "鲜血之业吸血")


func _play_greed(user: BattleUnitState, _depth: int, _controller: BattleController, context: Dictionary) -> void:
	while not user.draw_pile.is_empty():
		user.move_draw_card_to_discard(user.draw_pile.back(), context.merged({"reason": "greed_industry_mill"}))
	for selected_value in context.get("ordered_discard_cards", []) as Array:
		var selected := selected_value as CardData
		if selected == null:
			continue
		for unit in user.battle_controller.units:
			if unit.move_discard_card_to_hand(selected):
				if unit != user:
					unit.hand.erase(selected)
					user.hand.append(selected)
				break


func _play_cripple(user: BattleUnitState, depth: int, controller: BattleController, targets: Array, context: Dictionary) -> void:
	var stun := StunStatus.new()
	stun.stacks = 4
	user.add_status(stun)
	var destination: Vector2i = targets[0] if targets.size() == 1 and targets[0] is Vector2i else user.cell
	if controller.map_data.is_valid_cell(destination) and controller.targeting.is_unit_cell_clear(user, destination, false):
		user.set_hex_cell(destination, controller.map_data)
	user.current_ap += 2 + depth
	controller.state_changed.emit()


func _play_disease(_user: BattleUnitState, depth: int, controller: BattleController, targets: Array, context: Dictionary) -> void:
	var target := targets[0] as BattleUnitState if targets.size() == 1 else null
	if target == null:
		return
	for _index in range(depth + 2):
		target.draw_pile.append(DISEASE_CARD.duplicate(true) as CardData)
	target.shuffle_draw_pile(controller.rng)
	target.draw_cards(depth, controller.rng, context.merged({"reason": "disease_industry"}))


func _play_passing(user: BattleUnitState, controller: BattleController, context: Dictionary) -> void:
	for selected_value in context.get("ordered_discard_cards", []) as Array:
		var source := selected_value as CardData
		if source == null:
			continue
		var copy := source.duplicate(true) as CardData
		user.hand.append(copy)
		user.mark_temporary_card(copy, -copy.ap_cost, true, true)
	controller.state_changed.emit()


func _play_possession(user: BattleUnitState, depth: int, controller: BattleController, targets: Array, card: CardData) -> void:
	var possessed := targets[0] as BattleUnitState if targets.size() == 1 else null
	if possessed == null:
		return
	var candidates := controller.get_units_by_filter(possessed, BattleController.UnitFilter.ALLIES)
	candidates.erase(possessed)
	var closest: BattleUnitState
	for candidate in candidates:
		if candidate == null or not candidate.is_alive():
			continue
		if closest == null or possessed.cell_distance_to(candidate) < possessed.cell_distance_to(closest):
			closest = candidate
	if closest != null:
		controller.perform_strike_with_modifier(possessed, closest, card, 2 * depth, "凭依之业")
	else:
		controller.apply_damage(possessed, possessed, possessed.get_attack(), "凭依反噬", {"source_card": card})
	var state := user.get_curse_runtime_state(card.bound_curse_instance)
	state["industry_disable_next_turn"] = mini(2, depth)


func _play_unrest(user: BattleUnitState, depth: int, controller: BattleController, context: Dictionary) -> void:
	var status := CurseUndyingStatus.new()
	status.expires_turn_serial = user.turn_serial
	user.add_status(status)
	user.current_ap += 2 + depth
	user.draw_cards(depth, controller.rng, context.merged({"reason": "unrest_industry"}))


func _play_counterfeit(user: BattleUnitState, depth: int, context: Dictionary) -> void:
	var selected_values := context.get("ordered_discard_cards", []) as Array
	if selected_values.is_empty():
		return
	var selected := selected_values[0] as CardData
	if selected == null:
		return
	var copy := selected.duplicate(true) as CardData
	user.hand.append(copy)
	user.mark_temporary_card(copy, -depth, true, true)


func _play_universal_love(user: BattleUnitState, depth: int, controller: BattleController, context: Dictionary) -> void:
	var allies := controller.get_units_by_filter(user, BattleController.UnitFilter.ALLIES)
	allies.erase(user)
	var total := allies.size() + depth
	for _index in range(total):
		var recipient := _least_hand_ally(allies)
		if recipient != null:
			recipient.draw_cards(1, controller.rng, context.merged({"reason": "universal_love_industry"}))
	for ally in allies:
		ally.gain_armor(2 * depth, context)


func _play_gluttony(user: BattleUnitState, depth: int, controller: BattleController, targets: Array) -> void:
	var target := targets[0] as BattleUnitState if targets.size() == 1 else null
	if target == null:
		return
	if target.get_current_health() > user.get_current_health() + 5 * (depth - 1):
		controller.lose_life(user, user, user.get_current_health(), "饕餮反噬", {"curse_source": true})
		return
	var actual := controller.lose_life(user, target, target.get_current_health(), "饕餮处决")
	if actual > 0:
		controller.heal_unit(user, user, actual, "饕餮吸血")


func _play_offspring(user: BattleUnitState, depth: int, controller: BattleController, targets: Array) -> void:
	var destination: Vector2i = targets[0] if targets.size() == 1 and targets[0] is Vector2i else user.cell
	var root := controller.spawn_curse_root(user, destination, 10 + 5 * depth, true)
	if root == null:
		return
	var origins: Array[BattleUnitState] = controller.get_units_by_filter(user, BattleController.UnitFilter.ALLIES)
	origins.append(root)
	var total_lifesteal := 0
	for origin in origins:
		for target in controller.get_units_in_range(origin, 1, BattleController.UnitFilter.OPPONENTS):
			total_lifesteal += controller.apply_damage(user, target, 3 + depth, "孽生之业", {"fixed_damage": true})
	if total_lifesteal > 0:
		controller.heal_unit(user, user, total_lifesteal, "孽生之业吸血")


func _play_preservation(_user: BattleUnitState, depth: int, controller: BattleController, targets: Array, context: Dictionary) -> void:
	var target := targets[0] as BattleUnitState if targets.size() == 1 else null
	if target == null:
		return
	var stun := StunStatus.new()
	stun.stacks = 2 + depth
	for enemy in controller.enemy_units:
		if enemy != target and enemy.is_alive():
			enemy.add_status(stun.duplicate(true) as StatusEffect)
	var selected := context.get("selected_curse") as CurseInstance
	if selected != null:
		controller.apply_temporary_curse_report(target, selected, target.turn_serial + 1)


func _least_hand_ally(allies: Array[BattleUnitState]) -> BattleUnitState:
	var result: BattleUnitState
	for ally in allies:
		if ally != null and ally.is_alive() and (result == null or ally.hand.size() < result.hand.size()):
			result = ally
	return result


func _depth(card: CardData) -> int:
	if card != null and card.bound_curse_instance != null:
		return card.bound_curse_instance.depth
	return 1
