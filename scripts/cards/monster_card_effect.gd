extends CardEffect
class_name MonsterCardEffect

const TEMPORARY_JINX_PATH := "res://resources/cards/monster_cards/temporary_jinx.tres"

enum Kind {
	APPROACH_BITE,
	DRAG_TEAR,
	PACK_HUNT,
	HUNKER_HIDE,
	SEWAGE_SPIT,
	SUBMERGE,
	GUARD_HISS,
	EMPTY_EYE,
	LASHING_TENTACLE,
	BLOOD_MOUTH,
	EXTRA_LIMBS,
	SCORCH_SAC,
	ENLIGHTENED_TUMOR,
	NIGHT_MEMBRANE,
	IRRADIATED_GLAND,
	STAMPEDING_FEET,
	TEMPORARY_JINX,
}

@export var kind: int = Kind.APPROACH_BITE


func can_play(context: Dictionary = {}) -> bool:
	var user := context.get("user") as BattleUnitState
	return kind != Kind.TEMPORARY_JINX and user != null and user.faction == BattleUnitState.Faction.ENEMY


func is_unit_target_allowed(context: Dictionary = {}, target: BattleUnitState = null) -> bool:
	var user := context.get("user") as BattleUnitState
	if user == null or target == null or not target.is_alive():
		return false
	if kind == Kind.GUARD_HISS:
		return target.faction == user.faction
	if kind in [Kind.HUNKER_HIDE, Kind.EMPTY_EYE, Kind.ENLIGHTENED_TUMOR, Kind.TEMPORARY_JINX]:
		return target == user
	return target.faction != user.faction


func are_targets_valid(context: Dictionary = {}, targets: Array = [], _write_log: bool = true) -> bool:
	var controller := context.get("controller") as BattleController
	var user := context.get("user") as BattleUnitState
	if controller == null or user == null:
		return false
	if kind in [Kind.HUNKER_HIDE, Kind.EMPTY_EYE, Kind.ENLIGHTENED_TUMOR, Kind.STAMPEDING_FEET, Kind.TEMPORARY_JINX]:
		return targets.is_empty() or (targets.size() == 1 and targets[0] == user)
	if kind == Kind.SUBMERGE:
		return targets.size() == 1 and targets[0] is Vector2i and _is_valid_water_cell(controller, user, targets[0])
	if targets.size() != 1 or not (targets[0] is BattleUnitState):
		return false
	var target := targets[0] as BattleUnitState
	if not is_unit_target_allowed(context, target):
		return false
	var card := context.get("card") as CardData
	var allowed_range := card.get_effective_range(user, str(context.get("equipment_slot", ""))) if card != null else user.get_attack_range()
	if kind == Kind.APPROACH_BITE:
		allowed_range += 1
	return user.cell_distance_to(target) <= allowed_range


func provides_area_target_cells() -> bool:
	return kind == Kind.SUBMERGE


func get_area_target_cells(context: Dictionary = {}) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var controller := context.get("controller") as BattleController
	var user := context.get("user") as BattleUnitState
	if controller == null or user == null:
		return result
	for cell in controller.map_data.get_cells_in_range(user.cell, 4):
		if _is_valid_water_cell(controller, user, cell):
			result.append(cell)
	return result


func play(context: Dictionary = {}, targets: Array = []) -> void:
	var controller := context.get("controller") as BattleController
	var user := context.get("user") as BattleUnitState
	var card := context.get("card") as CardData
	if controller == null or user == null:
		return
	var target := targets[0] as BattleUnitState if targets.size() == 1 and targets[0] is BattleUnitState else null
	match kind:
		Kind.APPROACH_BITE:
			_move_into_weapon_range(controller, user, target, 1)
			if target != null and target.is_alive() and user.cell_distance_to(target) <= controller.get_effective_attack_range_against(user, target):
				controller.perform_strike(user, target, card, "逼近啃咬")
		Kind.DRAG_TEAR:
			if controller.perform_strike(user, target, card, "拖曳撕扯") > 0 and target != null and target.is_alive():
				controller.force_move_toward(target, user.cell, 1, user)
		Kind.PACK_HUNT:
			controller.perform_strike_with_modifier(user, target, card, 2 if _has_adjacent_ally(controller, user, target) else 0, "群猎")
		Kind.HUNKER_HIDE:
			user.gain_armor(5, {"controller": controller, "source_card": card})
		Kind.SEWAGE_SPIT:
			_deal_typed_damage(controller, user, target, card, 2, CardEnums.DamageType.INTELLIGENCE, "污水喷吐")
			if target != null:
				controller.apply_base_surface_element(target.cell, BattleSurfaceState.Element.WATER)
		Kind.SUBMERGE:
			if targets.size() == 1 and targets[0] is Vector2i:
				controller.apply_card_movement_to_cell(user, targets[0], "潜泥")
				user.gain_armor(3, {"controller": controller, "source_card": card})
		Kind.GUARD_HISS:
			if target != null:
				target.gain_armor(4, {"controller": controller, "source": user, "source_card": card})
				target.draw_cards(1, controller.rng, {"controller": controller, "reason": "护群嘶鸣"})
		Kind.EMPTY_EYE:
			_choose_from_top_three(user)
		Kind.LASHING_TENTACLE:
			controller.perform_strike(user, target, card, "鞭笞触腕")
			_apply_stun(target, 2)
		Kind.BLOOD_MOUTH:
			var dealt := controller.perform_strike(user, target, card, "觅血口器")
			if dealt > 0:
				controller.heal_unit(user, user, dealt, "觅血口器吸血")
		Kind.EXTRA_LIMBS:
			_deal_even_segments(controller, user, card, 3)
		Kind.SCORCH_SAC:
			_deal_typed_damage(controller, user, target, card, 3, CardEnums.DamageType.INTELLIGENCE, "灼喉囊")
			if target != null:
				controller.apply_base_surface_element(target.cell, BattleSurfaceState.Element.FIRE)
		Kind.ENLIGHTENED_TUMOR:
			_manifest_from_draw_pile(controller, user, card)
		Kind.NIGHT_MEMBRANE:
			var released: int = user.release_all_manifestations({
				"controller": controller,
				"source_card": card,
				"reason": "night_membrane",
			})
			if target != null and released > 0:
				controller.lose_life(user, target, released * 2, "披夜薄膜", {"fixed_damage": true})
		Kind.IRRADIATED_GLAND:
			_discard_random_other(user, card, controller)
			_add_temporary_jinx(target, controller)
		Kind.STAMPEDING_FEET:
			_strike_all_in_range(controller, user, card, "奔踏畸足")
		Kind.TEMPORARY_JINX:
			pass


func _deal_typed_damage(controller: BattleController, user: BattleUnitState, target: BattleUnitState, card: CardData, base: int, damage_type: int, label: String) -> int:
	if target == null:
		return 0
	var total := base + user.get_damage_bonus({"controller": controller, "card": card, "target": target, "resolved_damage_type": damage_type})
	return controller.apply_damage(user, target, total, label, {"source_card": card, "resolved_damage_type": damage_type})


func _move_into_weapon_range(controller: BattleController, user: BattleUnitState, target: BattleUnitState, max_steps: int) -> void:
	if target == null or user.cell_distance_to(target) <= user.get_attack_range():
		return
	var best := BattleHexGrid.INVALID_CELL
	var best_distance := user.cell_distance_to(target)
	for cell in controller.map_data.get_cells_in_range(user.cell, max_steps):
		if not controller.targeting.is_unit_cell_clear(user, cell, false):
			continue
		var distance := controller.map_data.get_distance(cell, target.cell)
		if distance < best_distance:
			best = cell
			best_distance = distance
	if best != BattleHexGrid.INVALID_CELL:
		controller.apply_card_path_movement_to_cell(user, best, -1, true, "逼近啃咬")


func _has_adjacent_ally(controller: BattleController, user: BattleUnitState, target: BattleUnitState) -> bool:
	if target == null:
		return false
	for ally in controller.units:
		if ally != null and ally != user and ally.is_alive() and ally.faction == user.faction and ally.cell_distance_to(target) <= 1:
			return true
	return false


func _is_valid_water_cell(controller: BattleController, user: BattleUnitState, cell: Vector2i) -> bool:
	return controller.map_data.is_valid_cell(cell) \
		and controller.map_data.get_distance(user.cell, cell) <= 4 \
		and controller.surface_state.get_readable_elements(cell).has(BattleSurfaceState.Element.WATER) \
		and controller.targeting.is_unit_cell_clear(user, cell, false)


func _choose_from_top_three(user: BattleUnitState) -> void:
	var count := mini(3, user.draw_pile.size())
	if count <= 0:
		return
	var top: Array[CardData] = []
	for _i in range(count):
		top.append(user.draw_pile.pop_back())
	var chosen: CardData = top.pop_front() as CardData
	user.hand.append(chosen)
	for card in top:
		user.draw_pile.push_front(card)


func _apply_stun(target: BattleUnitState, amount: int) -> void:
	if target == null:
		return
	var stun := StunStatus.new()
	stun.stacks = amount
	target.add_status(stun)


func _deal_even_segments(controller: BattleController, user: BattleUnitState, card: CardData, segment_count: int) -> void:
	var targets := controller.get_opposing_units(user)
	var attack_range := user.get_attack_range()
	targets = targets.filter(func(target: BattleUnitState) -> bool: return user.cell_distance_to(target) <= attack_range)
	if targets.is_empty():
		return
	targets.sort_custom(func(a: BattleUnitState, b: BattleUnitState) -> bool:
		var da := user.cell_distance_to(a)
		var db := user.cell_distance_to(b)
		if da != db:
			return da < db
		if a.get_current_health() != b.get_current_health():
			return a.get_current_health() < b.get_current_health()
		return a.turn_order_index < b.turn_order_index
	)
	var damage_type := user.build_strike_profile_object().primary_damage_type
	for index in range(segment_count):
		var target := targets[index % targets.size()]
		if target.is_alive():
			_deal_typed_damage(controller, user, target, card, 1, damage_type, "增生附肢")


func _manifest_from_draw_pile(controller: BattleController, user: BattleUnitState, source_card: CardData) -> void:
	var candidate: CardData
	for card in user.draw_pile:
		if card != source_card and card.has_mutation_fields():
			candidate = card
			break
	if candidate == null:
		return
	var manifested: CardData = user.manifest_card_from_draw_pile(candidate, {
		"controller": controller,
		"source_card": source_card,
		"reason": "enlightened_tumor",
	}) as CardData
	if manifested != null:
		controller._emit_log("%s 显化了%s。" % [user.get_display_name(), manifested.card_name])


func _discard_random_other(user: BattleUnitState, source_card: CardData, controller: BattleController) -> void:
	var candidates: Array[CardData] = []
	for card in user.hand:
		if card != source_card:
			candidates.append(card)
	if not candidates.is_empty():
		user.discard_card(candidates[controller.rng.randi_range(0, candidates.size() - 1)], {"controller": controller, "reason": "辐照腺体"})


func _add_temporary_jinx(target: BattleUnitState, controller: BattleController) -> void:
	if target == null:
		return
	var template := load(TEMPORARY_JINX_PATH) as CardData
	if template == null:
		return
	var card := template.duplicate(true) as CardData
	target.draw_pile.append(card)
	target.mark_temporary_card(card, 0, false, false)
	target.shuffle_draw_pile(controller.rng)


func _strike_all_in_range(controller: BattleController, user: BattleUnitState, card: CardData, label: String) -> void:
	for target in controller.get_opposing_units(user):
		if target.is_alive() and user.cell_distance_to(target) <= controller.get_effective_attack_range_against(user, target):
			controller.perform_strike(user, target, card, label)
