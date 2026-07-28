extends RefCounted
class_name EnemyIntentPlanner

const MAX_STEPS := 4
const BEAM_WIDTH := 6


static func build_plan(controller: BattleController, unit: BattleUnitState, round_number: int) -> EnemyIntentPlan:
	var plan := EnemyIntentPlan.new()
	plan.round_locked = round_number
	if controller == null or unit == null or unit.enemy_state == null:
		return plan
	var candidates := _build_candidates(controller, unit)
	var beams: Array[Dictionary] = [{"steps": [], "used": {}, "ap": 0, "score": 0}]
	var ap_budget := unit.get_max_ap(controller.config)
	for _depth in range(MAX_STEPS):
		var expanded: Array[Dictionary] = beams.duplicate(true)
		for beam in beams:
			for candidate in candidates:
				var card := candidate.get("card") as CardData
				if card == null or beam.used.has(card.get_instance_id()):
					continue
				var cost := int(candidate.get("ap", 0))
				if int(beam.ap) + cost > ap_budget:
					continue
				var next := beam.duplicate(true)
				next.steps.append(candidate)
				next.used[card.get_instance_id()] = true
				next.ap = int(beam.ap) + cost
				next.score = int(beam.score) + int(candidate.get("score", 0))
				expanded.append(next)
		expanded.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.score) > int(b.score))
		beams.assign(expanded.slice(0, mini(BEAM_WIDTH, expanded.size())))
	var best: Dictionary = beams[0] if not beams.is_empty() else {}
	for step in best.get("steps", []):
		plan.steps.append(step)
		plan.attack_total += int(step.get("attack", 0))
		plan.defense_total += int(step.get("defense", 0))
	if unit.enemy_state.enemy_data.archetype_id == &"fish_champion" and unit.enemy_state.active_weapon_index == 0:
		var switch_target := controller.get_nearest_opponent(unit)
		var projected_momentum := mini(5, int(unit.enemy_state.runtime_state.get("momentum", 0)) + 1)
		plan.steps.push_front({
			"type": "switch",
			"label": "切换长枪",
			"target_id": switch_target.unit_id if switch_target != null else -1,
			"ap": 0,
			"attack": projected_momentum * 2,
			"defense": 0,
		})
	ChapterTwoEnemyRules.decorate_intent_plan(controller, unit, plan)
	_append_public_fallback(controller, unit, plan, ap_budget - int(best.get("ap", 0)))
	_plan_manifestations(unit, plan)
	return plan


static func _plan_manifestations(unit: BattleUnitState, plan: EnemyIntentPlan) -> void:
	plan.expected_decay_life = unit.distortion_state.manifested_cards.size()
	var reserved_card_ids := PackedInt64Array()
	for step in plan.steps:
		var step_card := step.get("card") as CardData
		if step_card != null:
			reserved_card_ids.append(step_card.get_instance_id())
	var candidates: Array[CardData] = []
	for card in unit.hand:
		if card != null and card.has_mutation_fields() and not reserved_card_ids.has(card.get_instance_id()):
			candidates.append(card)
	var projected_draw_count := unit.preview_distortion_draw_count()
	var available_draws := mini(projected_draw_count, unit.draw_pile.size())
	for index in range(available_draws):
		var draw_index := unit.draw_pile.size() - 1 - index
		var drawn_card: CardData = unit.draw_pile[draw_index]
		if drawn_card != null and drawn_card.has_mutation_fields() and not reserved_card_ids.has(drawn_card.get_instance_id()):
			candidates.append(drawn_card)
	var planned_fields := unit.get_active_distortion_fields()
	for card in candidates:
		var adds_field := false
		for field_id in card.mutation_fields:
			if not planned_fields.has(field_id):
				planned_fields.append(field_id)
				plan.planned_manifest_fields.append(DistortionCatalog.get_display_name(field_id))
				adds_field = true
		if adds_field:
			plan.planned_manifest_card_ids.append(card.get_instance_id())
		if plan.planned_manifest_card_ids.size() >= 2:
			break


static func _build_candidates(controller: BattleController, unit: BattleUnitState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for card in unit.hand:
		if card == null or not card.can_play({"controller": controller, "user": unit, "card": card}):
			continue
		var targets: Variant = _pick_targets(controller, unit, card)
		if targets == null:
			continue
		var entry := _find_pool_entry(unit, card)
		var estimate := _estimate_card(unit, card)
		result.append({
			"type": "card",
			"label": card.card_name,
			"card": card,
			"card_id": card.get_instance_id(),
			"targets": targets,
			"ap": controller.get_card_ap_cost(unit, card),
			"score": (entry.base_score if entry != null else 10) + int(estimate.attack) + int(estimate.defense),
			"attack": estimate.attack,
			"defense": estimate.defense,
		})
	return result


static func _pick_targets(controller: BattleController, unit: BattleUnitState, card: CardData) -> Variant:
	var context := {"controller": controller, "user": unit, "card": card}
	var target_type := card.get_target_type_for_mode(CardEnums.CardPlayMode.NORMAL, context)
	if target_type in [CardEnums.TargetType.NONE, CardEnums.TargetType.SELF, CardEnums.TargetType.ALL]:
		var empty: Array = []
		return empty if controller._targets_are_valid(unit, card, empty, false) else null
	if target_type == CardEnums.TargetType.AREA and card.effect != null and card.effect.provides_area_target_cells():
		var cells := card.effect.get_area_target_cells(context)
		return [cells[0]] if not cells.is_empty() else null
	var candidates: Array[BattleUnitState] = []
	for target in controller.units:
		if target != null and target.is_alive() and controller._targets_are_valid(unit, card, [target], false):
			candidates.append(target)
	if candidates.is_empty():
		return null
	candidates.sort_custom(func(a: BattleUnitState, b: BattleUnitState) -> bool:
		var da := unit.cell_distance_to(a)
		var db := unit.cell_distance_to(b)
		return da < db if da != db else a.get_current_health() < b.get_current_health()
	)
	return [candidates[0]]


static func _find_pool_entry(unit: BattleUnitState, card: CardData) -> EnemyCardPoolEntry:
	var rule := unit.enemy_state.enemy_data.deck_rule if unit.enemy_state != null and unit.enemy_state.enemy_data != null else null
	if rule == null:
		return null
	for slot in rule.category_slots:
		if slot == null:
			continue
		for entry in slot.entries:
			if entry != null and entry.card == card:
				return entry
	return null


static func _estimate_card(unit: BattleUnitState, card: CardData) -> Dictionary:
	var attack := 0
	var defense := 0
	if card.effect is MonsterCardEffect:
		var effect := card.effect as MonsterCardEffect
		match effect.kind:
			MonsterCardEffect.Kind.HUNKER_HIDE: defense = 5
			MonsterCardEffect.Kind.GUARD_HISS: defense = 4
			MonsterCardEffect.Kind.SEWAGE_SPIT: attack = 2 + unit.get_intelligence()
			MonsterCardEffect.Kind.SCORCH_SAC: attack = 3 + unit.get_intelligence()
			MonsterCardEffect.Kind.EXTRA_LIMBS: attack = 3 * (1 + unit.get_damage_bonus())
			MonsterCardEffect.Kind.NIGHT_MEMBRANE: attack = unit.enchant_zone.size() * 2
			_:
				if card.is_attack_card():
					attack = unit.get_attack()
	return {"attack": attack, "defense": defense}


static func _append_public_fallback(controller: BattleController, unit: BattleUnitState, plan: EnemyIntentPlan, remaining_ap: int) -> void:
	if remaining_ap < controller.config.basic_attack_ap_cost:
		return
	var target := controller.get_nearest_opponent(unit)
	if target == null:
		return
	if unit.cell_distance_to(target) <= controller.get_effective_attack_range_against(unit, target):
		plan.steps.append({"type": "basic_attack", "label": "基础打击", "target_id": target.unit_id, "ap": controller.config.basic_attack_ap_cost, "attack": unit.get_attack(), "defense": 0})
		plan.attack_total += unit.get_attack()
		return
	var best_cell := BattleHexGrid.INVALID_CELL
	var best_distance := unit.cell_distance_to(target)
	for cell in controller.get_reachable_cells_for_ap(unit, remaining_ap):
		if cell == unit.cell:
			continue
		var distance := controller.map_data.get_distance(cell, target.cell)
		if distance < best_distance:
			best_distance = distance
			best_cell = cell
	if best_cell != BattleHexGrid.INVALID_CELL:
		plan.steps.append({"type": "move", "label": "逼近", "cell": best_cell, "ap": remaining_ap, "attack": 0, "defense": 0})
