extends CurseEffect
class_name CoreCurseEffect

const BattleHexGrid = preload("res://scripts/battle/battle_hex_grid.gd")
const DISEASE_CARD := preload("res://resources/cards/curse_disease.tres")
const ALL_ACTION_CATEGORIES: Array[int] = [
	CardEnums.ActionCategory.MOVE,
	CardEnums.ActionCategory.ATTACK_CARD,
	CardEnums.ActionCategory.SKILL_CARD,
	CardEnums.ActionCategory.ENCHANTMENT_CARD,
	CardEnums.ActionCategory.CURSE_CARD,
]

@export var curse_id: String = ""


func on_battle_started(owner: BattleUnitState, curse: CurseInstance, context: Dictionary = {}) -> void:
	match curse_id:
		"disease":
			_inject_diseases(owner, curse.depth, context)
		"counterfeit":
			_state(owner, curse)["counterfeit_draws_left"] = curse.depth
		"unrest":
			_state(owner, curse)["unrest_used"] = false
		"universal_love":
			_state(owner, curse)["intercept_used"] = false
		"preservation":
			_state(owner, curse)["counter_used"] = false
		"offspring":
			_spawn_battle_root(owner, curse, context)
		_:
			pass


func on_draw_phase_before(owner: BattleUnitState, curse: CurseInstance, context: Dictionary = {}) -> void:
	if curse_id == "passing" and curse.state == CurseInstance.State.REPORT:
		owner.mill_cards(curse.depth, context.merged({"reason": "passing_report"}))


func on_before_reshuffle(owner: BattleUnitState, curse: CurseInstance, context: Dictionary = {}) -> void:
	if curse_id != "passing" or curse.state != CurseInstance.State.REPORT:
		return
	var controller := _controller(context, owner)
	if controller == null:
		return
	controller.lose_life(owner, owner, 2 + curse.depth, "遗逝之报")
	owner.gain_curse_wave(curse.depth, context)


func on_action_phase_started(owner: BattleUnitState, curse: CurseInstance, context: Dictionary = {}) -> void:
	match curse_id:
		"possession":
			_start_possession_turn(owner, curse, context)
		"unbound":
			_start_unbound_phase(owner, curse, context)
		_:
			pass


func on_card_drawn(owner: BattleUnitState, curse: CurseInstance, card: CardData, context: Dictionary = {}) -> void:
	if curse_id != "counterfeit" or curse.state != CurseInstance.State.REPORT:
		return
	if str(context.get("draw_source", "")) == "draw_phase":
		return
	var state := _state(owner, curse)
	var remaining := int(state.get("counterfeit_draws_left", 0))
	if remaining <= 0:
		return
	state["counterfeit_draws_left"] = remaining - 1
	owner.get_card_runtime_state(card)["exile_on_leave_hand"] = true


func on_draw_action_completed(owner: BattleUnitState, curse: CurseInstance, _cards: Array[CardData], context: Dictionary = {}) -> void:
	if curse_id != "greed" or curse.state != CurseInstance.State.REPORT:
		return
	if str(context.get("draw_source", "")) == "draw_phase":
		return
	var controller := _controller(context, owner)
	for _index in range(mini(curse.depth, owner.hand.size())):
		if owner.hand.is_empty():
			break
		var choice_index := controller.rng.randi_range(0, owner.hand.size() - 1) if controller != null else owner.hand.size() - 1
		var chosen: CardData = owner.hand[choice_index]
		owner.discard_card(chosen, context.merged({"reason": "greed_report"}))


func on_card_play_submitted(owner: BattleUnitState, curse: CurseInstance, card: CardData, context: Dictionary = {}) -> void:
	if curse_id == "cripple" and curse.state == CurseInstance.State.REPORT:
		owner.gain_curse_wave(curse.depth, context)


func on_after_card_played(owner: BattleUnitState, curse: CurseInstance, card: CardData, _context: Dictionary = {}) -> void:
	if curse_id == "counterfeit" and curse.state == CurseInstance.State.FRUIT and not card.is_curse_card():
		_state(owner, curse)["last_noncurse_card"] = card


func on_card_discarded(owner: BattleUnitState, curse: CurseInstance, _card: CardData, context: Dictionary = {}) -> void:
	if curse_id == "greed" and curse.state == CurseInstance.State.FRUIT:
		owner.gain_curse_wave(1, context)


func on_movement_completed(owner: BattleUnitState, curse: CurseInstance, context: Dictionary = {}) -> void:
	if curse_id != "cripple" or curse.state != CurseInstance.State.REPORT:
		return
	if bool(context.get("forced", false)):
		return
	var controller := _controller(context, owner)
	if controller == null:
		return
	var loss := curse.depth + ceili(float(owner.curse_wave) / 3.0)
	controller.lose_life(owner, owner, loss, "跛行之报")
	owner.consume_curse_wave(curse.depth, context)


func on_after_life_lost(owner: BattleUnitState, curse: CurseInstance, _amount: int, context: Dictionary = {}) -> void:
	if curse_id != "blood" or curse.state != CurseInstance.State.REPORT or not bool(context.get("is_damage", false)):
		return
	var damage_context := context.get("damage_context") as DamageContext
	if damage_context != null and _source_is_curse(damage_context.metadata.get("source_card")):
		return
	var state := _state(owner, curse)
	var action_id := int(context.get("action_id", -1))
	if int(state.get("blood_last_action", -2)) == action_id:
		return
	state["blood_last_action"] = action_id
	var controller := _controller(context, owner)
	if controller != null and owner.is_alive():
		controller.lose_life(owner, owner, curse.depth + 1, "鲜血之报追加损失", {"curse_source": true})


func on_kill(owner: BattleUnitState, curse: CurseInstance, _target: BattleUnitState, context: Dictionary = {}) -> void:
	if curse_id != "gluttony" or curse.state != CurseInstance.State.REPORT:
		return
	owner.consume_curse_wave(curse.depth + 2, context)


func on_death(owner: BattleUnitState, curse: CurseInstance, _context: Dictionary = {}) -> void:
	if curse_id == "unrest" and curse.state == CurseInstance.State.REPORT:
		curse.persistent_data["transfer_after_battle"] = true


func on_turn_end(owner: BattleUnitState, curse: CurseInstance, context: Dictionary = {}) -> void:
	match curse_id:
		"gluttony":
			owner.gain_curse_wave(curse.depth, context)
		"universal_love":
			_resolve_universal_love_turn_end(owner, curse, context)
		"offspring":
			_resolve_hostile_root_attack(owner, curse, context)
		_:
			pass


func on_battle_finished(owner: BattleUnitState, curse: CurseInstance, victory: bool, _context: Dictionary = {}) -> void:
	if curse_id != "unrest" or curse.state != CurseInstance.State.FRUIT or owner.character_state == null:
		return
	if bool(_state(owner, curse).get("unrest_triggered_this_battle", false)) and not bool(curse.persistent_data.get("max_health_penalty_pending", false)):
		owner.character_state.persistent_max_health_modifier -= 2 * curse.depth
		curse.persistent_data["max_health_penalty_pending"] = true
	elif victory and bool(curse.persistent_data.get("max_health_penalty_pending", false)):
		owner.character_state.persistent_max_health_modifier += 2 * curse.depth
		curse.persistent_data.erase("max_health_penalty_pending")


func modify_healing_received(owner: BattleUnitState, curse: CurseInstance, amount: int, context: Dictionary = {}) -> int:
	if curse_id != "blood" or amount <= 0:
		return amount
	owner.gain_armor(amount, context.merged({"reason": "blood_curse_healing"}))
	var controller := _controller(context, owner)
	if controller != null:
		controller._emit_log("%s 的鲜血诅咒将 %d 点治疗转化为护甲。" % [owner.get_display_name(), amount])
	return 0


func modify_damage_bonus(owner: BattleUnitState, curse: CurseInstance, _context: Dictionary = {}) -> int:
	if curse_id != "gluttony":
		return 0
	var divisor := 5 if curse.state == CurseInstance.State.FRUIT else 3
	return -int(floor(float(owner.curse_wave) / float(divisor)))


func modify_damage_reduction(owner: BattleUnitState, curse: CurseInstance, _context: Dictionary = {}) -> int:
	if curse_id != "gluttony":
		return 0
	var divisor := 5 if curse.state == CurseInstance.State.FRUIT else 3
	return -int(floor(float(owner.curse_wave) / float(divisor)))


func modify_move_ap_cost(_owner: BattleUnitState, curse: CurseInstance, current_cost: int, _context: Dictionary = {}) -> int:
	if curse_id == "cripple" and curse.state == CurseInstance.State.FRUIT:
		return current_cost + 1
	return current_cost


func get_lethal_health_floor(owner: BattleUnitState, curse: CurseInstance, _context: Dictionary = {}) -> int:
	if curse_id != "unrest" or curse.state != CurseInstance.State.FRUIT:
		return 0
	var incoming := int(_context.get("amount", 0))
	var damage_context := _context.get("damage_context") as DamageContext
	if damage_context != null:
		incoming = damage_context.amount
	if incoming < owner.get_current_health():
		return 0
	var state := _state(owner, curse)
	if bool(state.get("unrest_used", false)):
		return 0
	state["unrest_used"] = true
	state["unrest_triggered_this_battle"] = true
	owner.gain_armor(3 * curse.depth, {"reason": "unrest_fruit"})
	owner.gain_curse_wave(curse.depth)
	return 1


func can_be_friendly_target(_owner: BattleUnitState, curse: CurseInstance, _source: BattleUnitState, _context: Dictionary = {}) -> bool:
	return not (curse_id == "preservation" and curse.is_active_in_curse_zone())


func should_exile_discarded_card(_owner: BattleUnitState, curse: CurseInstance, _card: CardData, _context: Dictionary = {}) -> bool:
	return curse_id == "preservation" and curse.state == CurseInstance.State.REPORT


func can_auto_reshuffle(_owner: BattleUnitState, curse: CurseInstance, _context: Dictionary = {}) -> bool:
	return not (curse_id == "passing" and curse.state == CurseInstance.State.FRUIT)


func should_counter_card(owner: BattleUnitState, curse: CurseInstance, _source: BattleUnitState, _card: CardData, context: Dictionary = {}) -> bool:
	if curse_id != "preservation" or curse.state != CurseInstance.State.FRUIT:
		return false
	var state := _state(owner, curse)
	var controller := _controller(context, owner)
	var round := controller.battle_round if controller != null else 0
	if int(state.get("preservation_counter_round", -1)) == round:
		return false
	var paid := false
	if str(state.get("preservation_mode", "discard")) == "wave":
		paid = owner.consume_curse_wave(3 * curse.depth, context) == 3 * curse.depth
	elif not owner.hand.is_empty():
		paid = owner.discard_card(owner.hand.back(), context.merged({"reason": "preservation_counter"}))
	if paid:
		state["preservation_counter_round"] = round
	return paid


func get_damage_redirect(owner: BattleUnitState, curse: CurseInstance, original_target: BattleUnitState, context: Dictionary = {}) -> Dictionary:
	if curse_id != "universal_love" or original_target == owner or original_target.faction != owner.faction:
		return {}
	if str(_state(owner, curse).get("love_mode", "share")) != "redirect" or owner.cell_distance_to(original_target) > 3:
		return {}
	var controller := _controller(context, owner)
	var round := controller.battle_round if controller != null else 0
	var state := _state(owner, curse)
	if int(state.get("love_redirect_round", -1)) != round:
		state["love_redirect_round"] = round
		state["love_redirect_count"] = 0
	var count := int(state.get("love_redirect_count", 0))
	if count >= curse.depth:
		return {}
	state["love_redirect_count"] = count + 1
	return {"target": owner, "reduction": curse.depth if curse.state == CurseInstance.State.FRUIT else 0}


func can_intercept_report(owner: BattleUnitState, curse: CurseInstance, new_owner: BattleUnitState, incoming: CurseInstance, context: Dictionary = {}) -> bool:
	if curse_id != "universal_love" or curse.state != CurseInstance.State.FRUIT or new_owner == owner or incoming == null:
		return false
	var controller := _controller(context, owner)
	var round := controller.battle_round if controller != null else 0
	var state := _state(owner, curse)
	if int(state.get("love_intercept_round", -1)) == round:
		return false
	if owner.character_state == null or owner.character_state.get_curse(incoming.get_curse_id()) != null:
		return false
	state["love_intercept_round"] = round
	return true


func get_alternate_range_origins(owner: BattleUnitState, curse: CurseInstance, _context: Dictionary = {}) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if curse_id != "offspring" or curse.state != CurseInstance.State.FRUIT or owner.battle_controller == null:
		return result
	for root in owner.battle_controller.get_curse_roots(owner, false):
		result.append(root.cell)
	return result


func can_use_action_category(owner: BattleUnitState, curse: CurseInstance, category: int, _context: Dictionary = {}) -> bool:
	var state := _state(owner, curse)
	if curse_id == "possession":
		return category not in (state.get("disabled_categories", []) as Array)
	if curse_id != "unbound":
		return true
	if curse.state == CurseInstance.State.REPORT:
		return category not in (state.get("unbound_locked", []) as Array)
	var used := state.get("unbound_current", []) as Array
	var previous := state.get("unbound_previous", []) as Array
	return category in used or (used.size() < 2 and category not in previous)


func on_action_category_used(owner: BattleUnitState, curse: CurseInstance, category: int, context: Dictionary = {}) -> void:
	if curse_id != "unbound":
		return
	var state := _state(owner, curse)
	if curse.state == CurseInstance.State.REPORT:
		var locked := state.get("unbound_locked", []) as Array
		if category not in locked:
			locked.append(category)
		state["unbound_locked"] = locked
		return
	var current := state.get("unbound_current", []) as Array
	if category in current:
		return
	current.append(category)
	state["unbound_current"] = current
	owner.gain_curse_wave(curse.depth, context)
	if current.size() == 2:
		owner.current_ap += 2


func has_pending_choice(owner: BattleUnitState, curse: CurseInstance, _context: Dictionary = {}) -> bool:
	return curse_id == "greed" and curse.state == CurseInstance.State.FRUIT and owner.hand.size() > maxi(0, 6 - curse.depth)


func get_active_actions(owner: BattleUnitState, curse: CurseInstance, _context: Dictionary = {}) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	match curse_id:
		"blood":
			if curse.state == CurseInstance.State.FRUIT and not bool(_state(owner, curse).get("turn_blood_fury", false)):
				actions.append(_action("blood_fury", "鲜血：燃命强攻", "none"))
		"greed":
			if curse.state == CurseInstance.State.FRUIT:
				if owner.hand.size() > maxi(0, 6 - curse.depth):
					actions.append(_action("greed_trim", "贪欲：选择超量手牌弃置", "hand"))
				if owner.curse_wave > 0:
					actions.append(_action("greed_heal", "贪欲：咒波治疗", "none"))
					actions.append(_action("greed_armor", "贪欲：咒波护甲", "none"))
		"cripple":
			if curse.state == CurseInstance.State.FRUIT and owner.curse_wave > 0 and not bool(_state(owner, curse).get("turn_cripple_step", false)):
				actions.append(_action("cripple_step", "跛行：咒步", "cell"))
		"disease":
			if curse.state == CurseInstance.State.FRUIT and _find_disease(owner) != null and not bool(_state(owner, curse).get("turn_disease_purge", false)):
				actions.append(_action("disease_purge", "痼病：放逐病症", "hand_disease"))
		"passing":
			if curse.state == CurseInstance.State.FRUIT and not owner.discard_pile.is_empty() and not bool(_state(owner, curse).get("turn_passing_recall", false)):
				actions.append(_action("passing_recall", "遗逝：追忆", "discard"))
		"possession":
			if curse.state == CurseInstance.State.FRUIT and not bool(_state(owner, curse).get("turn_possession_selected", false)):
				for category in ALL_ACTION_CATEGORIES:
					actions.append(_action("possession_%d" % category, "凭依：禁用%s" % CardEnums.action_category_label(category), "none"))
		"counterfeit":
			if curse.state == CurseInstance.State.FRUIT and _state(owner, curse).get("last_noncurse_card") is CardData and owner.curse_wave >= 2 * curse.depth and not bool(_state(owner, curse).get("turn_counterfeit_copy", false)):
				actions.append(_action("counterfeit_copy", "赝作：复制上一张牌", "none"))
		"gluttony":
			if curse.state == CurseInstance.State.FRUIT and owner.curse_wave >= 5 and not bool(_state(owner, curse).get("gluttony_used", false)):
				actions.append(_action("gluttony_devour", "饕餮：吞噬", "enemy"))
		"preservation":
			if curse.state == CurseInstance.State.FRUIT:
				actions.append(_action("preservation_discard", "守成：弃牌反制", "none"))
				actions.append(_action("preservation_wave", "守成：咒波反制", "none"))
		"universal_love":
			actions.append(_action("love_share", "兼爱：回合末共享", "none"))
			actions.append(_action("love_redirect", "兼爱：代受伤害", "none"))
		_:
			pass
	return actions


func can_activate_action(owner: BattleUnitState, curse: CurseInstance, action_id: String, context: Dictionary = {}) -> bool:
	if owner == null or curse == null or owner != owner.battle_controller.current_unit:
		return false
	if owner.battle_controller.turn_flow_state != BattleController.TurnFlowState.ACTIVE:
		return false
	match action_id:
		"blood_fury":
			return owner.get_current_health() > 2 * curse.depth and not bool(_state(owner, curse).get("turn_blood_fury", false))
		"greed_heal", "greed_armor":
			return owner.curse_wave > 0 and not bool(_state(owner, curse).get("turn_greed_spent", false))
		"greed_trim":
			return context.get("selected_card") is CardData and owner.hand.size() > maxi(0, 6 - curse.depth)
		"cripple_step":
			return owner.curse_wave > 0 and context.get("target_cell") is Vector2i and not bool(_state(owner, curse).get("turn_cripple_step", false))
		"disease_purge":
			return context.get("selected_card") is CardData and not bool(_state(owner, curse).get("turn_disease_purge", false))
		"passing_recall":
			return context.get("selected_card") is CardData and not bool(_state(owner, curse).get("turn_passing_recall", false))
		"counterfeit_copy":
			return owner.curse_wave >= 2 * curse.depth and not bool(_state(owner, curse).get("turn_counterfeit_copy", false))
		"gluttony_devour":
			return context.get("target") is BattleUnitState and not bool(_state(owner, curse).get("gluttony_used", false))
		_:
			return action_id.begins_with("possession_") or action_id.begins_with("preservation_") or action_id.begins_with("love_")


func activate_action(owner: BattleUnitState, curse: CurseInstance, action_id: String, context: Dictionary = {}) -> bool:
	if not can_activate_action(owner, curse, action_id, context):
		return false
	var controller := owner.battle_controller
	match action_id:
		"blood_fury":
			controller.lose_life(owner, owner, 2 * curse.depth, "鲜血之果")
			owner.gain_next_attack_damage_bonus(2 * curse.depth, true)
			_state(owner, curse)["turn_blood_fury"] = true
		"greed_heal", "greed_armor":
			var spent := owner.consume_curse_wave(mini(owner.curse_wave, curse.depth + 2), context)
			_state(owner, curse)["turn_greed_spent"] = true
			if action_id == "greed_heal":
				controller.heal_unit(owner, owner, spent, "贪欲之果")
			else:
				owner.gain_armor(spent * 2, context)
		"greed_trim":
			var excess_card := context.get("selected_card") as CardData
			if excess_card == null or not owner.discard_card(excess_card, context.merged({"reason": "greed_hand_limit"})):
				return false
		"disease_purge":
			var disease := context.get("selected_card") as CardData
			if disease == null or not owner.move_card_to_exile(disease):
				return false
			owner.draw_cards(1, controller.rng, context.merged({"reason": "disease_fruit"}))
			owner.gain_armor(2 * curse.depth, context)
			_state(owner, curse)["turn_disease_purge"] = true
		"passing_recall":
			var recalled := context.get("selected_card") as CardData
			if recalled == null or not owner.move_discard_card_to_hand(recalled):
				return false
			owner.mark_temporary_card(recalled, -1, true, true)
			var cost := curse.depth
			if owner.curse_wave >= cost:
				owner.consume_curse_wave(cost, context)
			else:
				controller.lose_life(owner, owner, 2 * curse.depth, "遗逝之果")
			_state(owner, curse)["turn_passing_recall"] = true
		"counterfeit_copy":
			var source_card := _state(owner, curse).get("last_noncurse_card") as CardData
			if source_card == null:
				return false
			owner.consume_curse_wave(2 * curse.depth, context)
			var copy := source_card.duplicate(true) as CardData
			owner.hand.append(copy)
			owner.mark_temporary_card(copy, -1, true, true)
			_state(owner, curse)["turn_counterfeit_copy"] = true
		"gluttony_devour":
			var target := context.get("target") as BattleUnitState
			if target == null or target.faction == owner.faction or target.get_current_health() > owner.curse_wave * 2:
				return false
			var consumed := owner.consume_curse_wave(owner.curse_wave, context)
			controller.lose_life(owner, target, target.get_current_health(), "饕餮处决")
			_resolve_gluttony_rewards(owner, curse, consumed, context)
			_state(owner, curse)["gluttony_used"] = true
		"cripple_step":
			return _activate_cripple_step(owner, curse, context)
		_:
			if action_id.begins_with("possession_"):
				var category := action_id.trim_prefix("possession_").to_int()
				_state(owner, curse)["disabled_categories"] = [category]
				owner.gain_curse_wave(2 * curse.depth, context)
				owner.current_ap += 2
				_state(owner, curse)["turn_possession_selected"] = true
			elif action_id == "preservation_discard":
				_state(owner, curse)["preservation_mode"] = "discard"
			elif action_id == "preservation_wave":
				_state(owner, curse)["preservation_mode"] = "wave"
			elif action_id == "love_share":
				_state(owner, curse)["love_mode"] = "share"
			elif action_id == "love_redirect":
				_state(owner, curse)["love_mode"] = "redirect"
			else:
				return false
	controller.state_changed.emit()
	return true


func _resolve_universal_love_turn_end(owner: BattleUnitState, curse: CurseInstance, context: Dictionary) -> void:
	var controller := _controller(context, owner)
	if controller == null:
		return
	var mode := str(_state(owner, curse).get("love_mode", "share"))
	var allies := controller.get_units_by_filter(owner, BattleController.UnitFilter.ALLIES)
	allies.erase(owner)
	if mode == "share":
		var discard_count := 1 if curse.state == CurseInstance.State.FRUIT else curse.depth
		if owner.hand.size() < discard_count:
			return
		for _index in range(discard_count):
			owner.discard_card(owner.hand.back(), context.merged({"reason": "universal_love"}))
		var draw_count := curse.depth if curse.state == CurseInstance.State.FRUIT else 1
		for ally in allies:
			ally.draw_cards(draw_count, controller.rng, context.merged({"reason": "universal_love"}))


func _resolve_hostile_root_attack(owner: BattleUnitState, curse: CurseInstance, context: Dictionary) -> void:
	if curse.state != CurseInstance.State.REPORT:
		return
	var controller := _controller(context, owner)
	if controller == null:
		return
	for root in controller.get_curse_roots(owner, true):
		var targets := controller.get_units_by_filter(root, BattleController.UnitFilter.OPPONENTS)
		var closest: BattleUnitState
		for target in targets:
			if closest == null or root.cell_distance_to(target) < root.cell_distance_to(closest):
				closest = target
		if closest != null:
			controller.apply_damage(root, closest, root.get_attack(), "敌方活根攻击", {"curse_source": true})


func _spawn_battle_root(owner: BattleUnitState, curse: CurseInstance, context: Dictionary) -> void:
	if curse.state == CurseInstance.State.INDUSTRY:
		return
	var controller := _controller(context, owner)
	if controller == null:
		return
	var friendly := curse.state == CurseInstance.State.FRUIT
	var target_cell := _find_open_root_cell(owner, controller, friendly)
	if target_cell == BattleHexGrid.INVALID_CELL:
		return
	controller.spawn_curse_root(owner, target_cell, 10 + 5 * curse.depth, friendly, friendly, curse.depth)


func _find_open_root_cell(owner: BattleUnitState, controller: BattleController, friendly: bool) -> Vector2i:
	var anchor := owner.cell
	if not friendly:
		var opponents := controller.get_units_by_filter(owner, BattleController.UnitFilter.OPPONENTS)
		if not opponents.is_empty():
			anchor = opponents[0].cell
	for candidate in controller.map_data.get_cells_in_range(anchor, 2):
		if controller.targeting.is_unit_cell_clear(null, candidate, false):
			return candidate
	return BattleHexGrid.INVALID_CELL


func _start_possession_turn(owner: BattleUnitState, curse: CurseInstance, context: Dictionary) -> void:
	if curse.state != CurseInstance.State.REPORT:
		return
	var controller := _controller(context, owner)
	var count := mini(2, curse.depth)
	var pool := ALL_ACTION_CATEGORIES.duplicate()
	var disabled: Array[int] = []
	for _index in range(count):
		var pick := controller.rng.randi_range(0, pool.size() - 1) if controller != null else 0
		disabled.append(int(pool.pop_at(pick)))
	_state(owner, curse)["disabled_categories"] = disabled
	if curse.depth >= 3:
		owner.current_ap = maxi(0, owner.current_ap - 1)


func _start_unbound_phase(owner: BattleUnitState, curse: CurseInstance, _context: Dictionary) -> void:
	var state := _state(owner, curse)
	if curse.state == CurseInstance.State.REPORT:
		var locked := state.get("unbound_locked", []) as Array
		if locked.size() >= ALL_ACTION_CATEGORIES.size():
			state["unbound_locked"] = []
			owner.current_ap = maxi(0, owner.current_ap - curse.depth)
	else:
		state["unbound_previous"] = (state.get("unbound_current", []) as Array).duplicate()
		state["unbound_current"] = []


func _inject_diseases(owner: BattleUnitState, count: int, context: Dictionary) -> void:
	if DISEASE_CARD == null:
		return
	for _index in range(maxi(0, count)):
		owner.draw_pile.append(DISEASE_CARD.duplicate(true) as CardData)
	var controller := _controller(context, owner)
	if controller != null:
		owner.shuffle_draw_pile(controller.rng)
		controller._emit_log("%s 的牌库被洗入 %d 张病症。" % [owner.get_display_name(), count])


func _find_disease(owner: BattleUnitState) -> CardData:
	for card in owner.hand:
		if card != null and card.card_name == "病症":
			return card
	return null


func _resolve_gluttony_rewards(owner: BattleUnitState, curse: CurseInstance, spent: int, context: Dictionary) -> void:
	var controller := _controller(context, owner)
	if controller == null:
		return
	if spent >= 5:
		controller.heal_unit(owner, owner, 5 * curse.depth, "饕餮之果")
	if spent >= 10:
		owner.draw_cards(2, controller.rng, context.merged({"reason": "gluttony_fruit"}))
	if spent >= 15:
		owner.current_ap += 2
	if spent >= 20 and owner.character_state != null and not bool(curse.persistent_data.get("permanent_damage_awarded_%d" % curse.depth, false)):
		owner.character_state.adventure_damage_bonus += 1
		curse.persistent_data["permanent_damage_awarded_%d" % curse.depth] = true


func _activate_cripple_step(owner: BattleUnitState, curse: CurseInstance, context: Dictionary) -> bool:
	var cell_value: Variant = context.get("target_cell")
	if not (cell_value is Vector2i):
		return false
	var distance := BattleHexGrid.distance(owner.cell, cell_value as Vector2i)
	var spend := mini(distance, curse.depth + 1)
	if distance <= 0 or spend != distance or owner.curse_wave < spend:
		return false
	var controller := owner.battle_controller
	if not controller.targeting.is_unit_cell_clear(owner, cell_value as Vector2i, false):
		return false
	owner.consume_curse_wave(spend, context)
	_state(owner, curse)["turn_cripple_step"] = true
	owner.set_hex_cell(cell_value as Vector2i, controller.map_data)
	owner.draw_cards(1, controller.rng, context.merged({"reason": "cripple_fruit"}))
	if not owner.hand.is_empty():
		owner.discard_card(owner.hand.back(), context.merged({"reason": "cripple_fruit"}))
	return true


func _source_is_curse(source: Variant) -> bool:
	return source is CardData and (source as CardData).is_curse_card()


func _state(owner: BattleUnitState, curse: CurseInstance) -> Dictionary:
	return owner.get_curse_runtime_state(curse)


func _controller(context: Dictionary, owner: BattleUnitState) -> BattleController:
	var result := context.get("controller") as BattleController
	return result if result != null else owner.battle_controller


func _action(action_id: String, label: String, selection: String) -> Dictionary:
	return {"id": action_id, "label": label, "selection": selection}
