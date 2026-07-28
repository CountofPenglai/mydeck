extends CardEffect
class_name ChapterTwoEnemyCardEffect

enum Kind {
	FORMATION_ADVANCE,
	SHIELD_WALL,
	COORDINATED_THRUST,
	FORTRESS_VOLLEY,
	RALLY_LINE,
	FORCED_MARCH,
	PUNITIVE_ORDER,
	WATCHFUL_STANCE,
	ARC_BOLT,
	ARCANE_WARD,
	BLOOD_HEX,
	DARK_BARGAIN,
	EVASIVE_STEP,
	AIMED_SHOT,
	GOSPEL,
}

@export var kind: int = Kind.FORMATION_ADVANCE


func can_play(context: Dictionary = {}) -> bool:
	var user := context.get("user") as BattleUnitState
	return user != null and user.faction == BattleUnitState.Faction.ENEMY


func is_unit_target_allowed(context: Dictionary = {}, target: BattleUnitState = null) -> bool:
	var user := context.get("user") as BattleUnitState
	if user == null or target == null or not target.is_alive():
		return false
	if kind in [Kind.RALLY_LINE]:
		return target.faction == user.faction
	return target.faction != user.faction


func are_targets_valid(context: Dictionary = {}, targets: Array = [], _write_log: bool = true) -> bool:
	var controller := context.get("controller") as BattleController
	var user := context.get("user") as BattleUnitState
	if controller == null or user == null:
		return false
	if kind in [Kind.SHIELD_WALL, Kind.FORCED_MARCH, Kind.WATCHFUL_STANCE, Kind.ARCANE_WARD, Kind.DARK_BARGAIN, Kind.EVASIVE_STEP, Kind.GOSPEL]:
		return targets.is_empty() or (targets.size() == 1 and targets[0] == user)
	if targets.size() != 1 or not (targets[0] is BattleUnitState):
		return false
	var target := targets[0] as BattleUnitState
	if not is_unit_target_allowed(context, target):
		return false
	var card := context.get("card") as CardData
	var allowed_range := card.get_effective_range(user) if card != null else user.get_attack_range()
	return user.cell_distance_to(target) <= allowed_range


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller := context.get("controller") as BattleController
	var user := context.get("user") as BattleUnitState
	var card := context.get("card") as CardData
	if controller == null or user == null:
		return
	var target := targets[0] as BattleUnitState if targets.size() == 1 and targets[0] is BattleUnitState else null
	match kind:
		Kind.FORMATION_ADVANCE:
			_move_toward(controller, user, target, 1 + (1 if ChapterTwoEnemyRules.is_in_formation(controller, user) else 0))
			if target != null and target.is_alive() and user.cell_distance_to(target) <= user.get_attack_range():
				controller.perform_strike(user, target, card, "军阵推进")
		Kind.SHIELD_WALL:
			user.gain_armor(6 if ChapterTwoEnemyRules.is_in_formation(controller, user) else 4, _context(controller, user, card))
		Kind.COORDINATED_THRUST:
			controller.perform_strike_with_modifier(user, target, card, 2 if ChapterTwoEnemyRules.is_in_formation(controller, user) else 0, "协同突刺")
		Kind.FORTRESS_VOLLEY:
			if _deal_typed_damage(controller, user, target, card, 3, CardEnums.DamageType.AGILITY, "要塞齐射") > 0 and target != null:
				target.gain_curse_wave(2 if ChapterTwoEnemyRules.is_in_formation(controller, user) else 1, _context(controller, user, card))
		Kind.RALLY_LINE:
			if target != null:
				target.gain_armor(5 if ChapterTwoEnemyRules.is_in_formation(controller, user) else 3, _context(controller, user, card))
				target.draw_cards(1, controller.rng, _context(controller, user, card))
		Kind.FORCED_MARCH:
			user.enemy_state.runtime_state["forced_march_move_bonus"] = 2 if ChapterTwoEnemyRules.is_in_formation(controller, user) else 1
		Kind.PUNITIVE_ORDER:
			controller.perform_strike_with_modifier(user, target, card, 2 if target != null and target.curse_wave > 0 else 0, "刑罚令")
		Kind.WATCHFUL_STANCE:
			user.gain_armor(2, _context(controller, user, card))
			user.move_hand_card_to_enchant(card, _context(controller, user, card))
		Kind.ARC_BOLT:
			_deal_typed_damage(controller, user, target, card, 3, CardEnums.DamageType.INTELLIGENCE, "秘法弹")
		Kind.ARCANE_WARD:
			user.gain_armor(5, _context(controller, user, card))
		Kind.BLOOD_HEX:
			if _deal_typed_damage(controller, user, target, card, 2, CardEnums.DamageType.INTELLIGENCE, "血咒") > 0 and target != null:
				target.gain_curse_wave(2, _context(controller, user, card))
		Kind.DARK_BARGAIN:
			controller.lose_life(user, user, 2, "黑暗交易")
			user.draw_cards(2, controller.rng, _context(controller, user, card))
		Kind.EVASIVE_STEP:
			_move_away(controller, user, controller.get_nearest_opponent(user), 2)
			user.gain_armor(2, _context(controller, user, card))
		Kind.AIMED_SHOT:
			_deal_typed_damage(controller, user, target, card, 4, CardEnums.DamageType.AGILITY, "瞄准射击")
		Kind.GOSPEL:
			ChapterTwoEnemyRules.resolve_gospel(controller, user, card)


func _context(controller: BattleController, user: BattleUnitState, card: CardData) -> Dictionary:
	return {"controller": controller, "source": user, "source_card": card}


func _deal_typed_damage(controller: BattleController, user: BattleUnitState, target: BattleUnitState, card: CardData, base: int, damage_type: int, label: String) -> int:
	if target == null:
		return 0
	if user.enemy_state != null and user.enemy_state.enemy_data != null \
			and user.enemy_state.enemy_data.archetype_id == &"corrupt_heart_veil" \
			and int(user.enemy_state.runtime_state.get("phase", 1)) == 1:
		var total_dealt := 0
		for expanded_target in controller.units:
			if expanded_target == null or expanded_target == user or not expanded_target.is_alive() \
					or user.cell_distance_to(expanded_target) <= 1:
				continue
			var expanded_bonus := user.get_damage_bonus({
				"controller": controller,
				"card": card,
				"target": expanded_target,
				"resolved_damage_type": damage_type,
			})
			var dealt := controller.apply_damage(user, expanded_target, base + expanded_bonus, label, {
				"source_card": card,
				"resolved_damage_type": damage_type,
				"veil_outer_expansion": true,
			})
			if dealt > 0:
				expanded_target.gain_curse_wave(2, {"controller": controller, "reason": "veil_outer_expansion"})
				total_dealt += dealt
		return total_dealt
	var bonus := user.get_damage_bonus({
		"controller": controller,
		"card": card,
		"target": target,
		"resolved_damage_type": damage_type,
	})
	return controller.apply_damage(user, target, base + bonus, label, {
		"source_card": card,
		"resolved_damage_type": damage_type,
	})


func _move_toward(controller: BattleController, user: BattleUnitState, target: BattleUnitState, distance: int) -> void:
	if target == null:
		return
	var best := user.cell
	var best_distance := user.cell_distance_to(target)
	for cell in controller.map_data.get_cells_in_range(user.cell, distance):
		if not controller.targeting.is_unit_cell_clear(user, cell, false):
			continue
		var candidate_distance := controller.map_data.get_distance(cell, target.cell)
		if candidate_distance < best_distance:
			best = cell
			best_distance = candidate_distance
	if best != user.cell:
		controller.apply_card_path_movement_to_cell(user, best, -1, true, "军阵推进")


func _move_away(controller: BattleController, user: BattleUnitState, target: BattleUnitState, distance: int) -> void:
	if target == null:
		return
	var best := user.cell
	var best_distance := user.cell_distance_to(target)
	for cell in controller.map_data.get_cells_in_range(user.cell, distance):
		if not controller.targeting.is_unit_cell_clear(user, cell, false):
			continue
		var candidate_distance := controller.map_data.get_distance(cell, target.cell)
		if candidate_distance > best_distance:
			best = cell
			best_distance = candidate_distance
	if best != user.cell:
		controller.apply_card_path_movement_to_cell(user, best, -1, true, "闪避步")
