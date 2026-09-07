extends RefCounted
class_name EnemyIntentPlanner

const MAX_STEPS := 4
const BEAM_WIDTH := 6


static func build_plan(controller: BattleController, unit: BattleUnitState, round_number: int) -> EnemyIntentPlan:
	var plan := EnemyIntentPlan.new()
	if controller == null or unit == null or unit.enemy_state == null:
		return plan
	var profile := _get_profile(unit)
	var intents := _select_intents(controller, unit, profile)
	plan.configure(intents.primary, intents.fallback, round_number)
	if unit.enemy_state.enemy_data.archetype_id == &"fish_champion" and unit.enemy_state.active_weapon_index == 0:
		var switch_target := controller.get_nearest_opponent(unit)
		var projected_momentum := mini(5, int(unit.enemy_state.runtime_state.get("momentum", 0)) + 1)
		plan.forced_steps.push_front({
			"type": "switch",
			"label": "切换长枪",
			"target_id": switch_target.unit_id if switch_target != null else -1,
			"ap": 0,
			"projected_bonus": projected_momentum * 2,
		})
	ChapterTwoEnemyRules.decorate_intent_plan(controller, unit, plan)
	_plan_manifestations(unit, plan)
	return plan


static func _get_profile(unit: BattleUnitState) -> EnemyAIProfile:
	if unit != null and unit.enemy_state != null and unit.enemy_state.enemy_data != null \
			and unit.enemy_state.enemy_data.ai_profile != null:
		return unit.enemy_state.enemy_data.ai_profile
	return EnemyAIProfile.create_preset(EnemyAIProfile.Preset.BALANCED)


static func _select_intents(controller: BattleController, unit: BattleUnitState, profile: EnemyAIProfile) -> Dictionary:
	var scored: Array[Dictionary] = []
	for category in range(EnemyIntentCategory.COUNT):
		scored.append({"category": category, "score": _score_intent(controller, unit, profile, category)})
	var primary := PackedInt32Array()
	var primary_count := clampi(profile.primary_intent_count, 1, 6)
	for slot in range(primary_count):
		var primary_scores := scored.duplicate(true)
		for entry in primary_scores:
			if slot == 0:
				match int(entry.category):
					EnemyIntentCategory.Type.APPROACH, EnemyIntentCategory.Type.DEFEND, EnemyIntentCategory.Type.UTILITY:
						entry.score = float(entry.score) + 3.0
					EnemyIntentCategory.Type.RETREAT:
						entry.score = float(entry.score) + 2.0
					_:
						pass
			else:
				var occurrences := 0
				for selected in primary:
					if selected == int(entry.category):
						occurrences += 1
				entry.score = float(entry.score) - 3.0 * occurrences
		_sort_intent_scores(primary_scores)
		primary.append(int(primary_scores[0].category))
	var fallback_scores := scored.duplicate(true)
	for entry in fallback_scores:
		var occurrences := 0
		for selected in primary:
			if selected == int(entry.category):
				occurrences += 1
		entry.score = float(entry.score) - 5.0 * occurrences
	_sort_intent_scores(fallback_scores)
	return {"primary": primary, "fallback": int(fallback_scores[0].category)}


static func _score_intent(controller: BattleController, unit: BattleUnitState, profile: EnemyAIProfile, category: int) -> float:
	var score := profile.get_intent_weight(category)
	score += _score_hand_support(unit, category)
	var health_ratio := float(unit.get_current_health()) / float(maxi(1, unit.get_max_health()))
	if health_ratio <= profile.low_health_ratio:
		score += profile.get_low_health_modifier(category)
	var nearest := controller.get_nearest_opponent(unit)
	var distance := unit.cell_distance_to(nearest) if nearest != null else 99
	match category:
		EnemyIntentCategory.Type.APPROACH:
			score += 6.0 if nearest != null and distance > unit.get_attack_range() else -4.0
		EnemyIntentCategory.Type.ATTACK:
			score += 7.0 if nearest != null and distance <= controller.get_effective_attack_range_against(unit, nearest) else -2.0
		EnemyIntentCategory.Type.DEFEND:
			score += (1.0 - health_ratio) * 6.0
		EnemyIntentCategory.Type.RETREAT:
			if not _uses_ranged_weapon(unit):
				score = -100.0
			elif distance < profile.preferred_range_min:
				score += 9.0
			else:
				score -= 5.0
		EnemyIntentCategory.Type.HARVEST:
			score = score + 12.0 if _has_harvest_target(controller, unit, profile.harvest_health_ratio) else -100.0
		_:
			pass
	return score


static func _score_hand_support(unit: BattleUnitState, category: int) -> float:
	if unit == null or unit.enemy_state == null or unit.enemy_state.enemy_data == null:
		return 0.0
	var rule := unit.enemy_state.enemy_data.deck_rule
	if rule == null:
		return 0.0
	var matching_ratings: Array[EnemyCardIntentRating] = []
	for card in unit.hand:
		var entry := rule.find_tactical_entry(card)
		var rating := entry.get_intent_rating(category) if entry != null else null
		if rating != null:
			matching_ratings.append(rating)
	var score := mini(4, matching_ratings.size()) * 1.5
	if matching_ratings.is_empty() and category in [
		EnemyIntentCategory.Type.DEFEND,
		EnemyIntentCategory.Type.UTILITY,
		EnemyIntentCategory.Type.CURSE,
	]:
		score -= 8.0
	if category != EnemyIntentCategory.Type.UTILITY:
		return score
	for setup_rating in matching_ratings:
		if setup_rating.provided_tags.is_empty():
			continue
		for card in unit.hand:
			var followup_entry := rule.find_tactical_entry(card)
			var followup := followup_entry.get_intent_rating(EnemyIntentCategory.Type.ATTACK) if followup_entry != null else null
			if followup != null and _tags_overlap(setup_rating.provided_tags, followup.preferred_tags):
				score += 5.0 + followup.combo_bonus
				return score
	return score


static func _sort_intent_scores(values: Array[Dictionary]) -> void:
	values.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_score := float(a.score)
		var b_score := float(b.score)
		return a_score > b_score if not is_equal_approx(a_score, b_score) else int(a.category) < int(b.category)
	)


static func _uses_ranged_weapon(unit: BattleUnitState) -> bool:
	var weapon: EquipmentData = unit.get_active_weapon_equipment()
	return weapon != null and weapon.range_type == EquipmentData.WeaponRangeType.RANGED


static func _has_harvest_target(controller: BattleController, unit: BattleUnitState, threshold: float) -> bool:
	for target in controller.get_opposing_units(unit):
		if target != null and target.is_alive() \
				and float(target.get_current_health()) / float(maxi(1, target.get_max_health())) <= threshold:
			return true
	return false


static func _plan_manifestations(unit: BattleUnitState, plan: EnemyIntentPlan) -> void:
	plan.expected_decay_life = unit.distortion_state.manifested_cards.size()
	var candidates: Array[CardData] = []
	for card in unit.hand:
		if card != null and card.has_mutation_fields():
			candidates.append(card)
	var projected_draw_count := unit.preview_distortion_draw_count()
	var available_draws := mini(projected_draw_count, unit.draw_pile.size())
	for index in range(available_draws):
		var draw_index := unit.draw_pile.size() - 1 - index
		var drawn_card: CardData = unit.draw_pile[draw_index]
		if drawn_card != null and drawn_card.has_mutation_fields():
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


static func choose_action(
	controller: BattleController,
	unit: BattleUnitState,
	category: int,
	ap_budget: int,
	combo_tags: PackedStringArray = PackedStringArray()
) -> EnemyIntentAction:
	if controller == null or unit == null or unit.enemy_state == null or ap_budget < 0:
		return null
	var candidates: Array[EnemyIntentAction] = []
	_add_card_candidates(candidates, controller, unit, category, ap_budget, combo_tags)
	if category in [EnemyIntentCategory.Type.ATTACK, EnemyIntentCategory.Type.HARVEST]:
		_add_basic_attack_candidates(candidates, controller, unit, category, ap_budget)
	if category == EnemyIntentCategory.Type.APPROACH:
		_add_movement_candidate(candidates, controller, unit, category, ap_budget, false)
	elif category == EnemyIntentCategory.Type.RETREAT:
		_add_movement_candidate(candidates, controller, unit, category, ap_budget, true)
	if candidates.is_empty():
		return null
	_filter_to_highest_hostile_threat(candidates, unit)
	candidates.sort_custom(func(a: EnemyIntentAction, b: EnemyIntentAction) -> bool:
		return a.score > b.score if not is_equal_approx(a.score, b.score) else a.ap_cost < b.ap_cost
	)
	return candidates[0]


static func has_legal_action(
	controller: BattleController,
	unit: BattleUnitState,
	category: int,
	ap_budget: int,
	combo_tags: PackedStringArray = PackedStringArray()
) -> bool:
	return choose_action(controller, unit, category, ap_budget, combo_tags) != null


static func _add_card_candidates(
	result: Array[EnemyIntentAction],
	controller: BattleController,
	unit: BattleUnitState,
	category: int,
	ap_budget: int,
	combo_tags: PackedStringArray
) -> void:
	for card in unit.hand:
		if card == null or not card.can_play({"controller": controller, "user": unit, "card": card}):
			continue
		var entry := _find_pool_entry(unit, card)
		var rating := entry.get_intent_rating(category) if entry != null else null
		if rating == null or not _has_required_tags(rating.required_tags, combo_tags):
			continue
		var cost := controller.get_card_ap_cost(unit, card)
		if cost > ap_budget:
			continue
		for targets in _get_target_options(controller, unit, card):
			var action := EnemyIntentAction.new()
			action.kind = EnemyIntentAction.Kind.CARD
			action.label = card.card_name
			action.card = card
			action.targets = targets
			action.ap_cost = cost
			action.provided_tags = rating.provided_tags.duplicate()
			action.score = _score_card_action(controller, unit, entry, rating, targets, category, combo_tags)
			action.score += _score_followup(unit, card, category, rating.provided_tags)
			result.append(action)


static func _get_target_options(controller: BattleController, unit: BattleUnitState, card: CardData) -> Array:
	var result: Array = []
	var context := {"controller": controller, "user": unit, "card": card}
	var target_type := card.get_target_type_for_mode(CardEnums.CardPlayMode.NORMAL, context)
	if target_type in [CardEnums.TargetType.NONE, CardEnums.TargetType.ALL]:
		var empty: Array = []
		if controller._targets_are_valid(unit, card, empty, false):
			result.append(empty)
		return result
	if target_type == CardEnums.TargetType.SELF:
		var self_targets: Array = [unit]
		if controller._targets_are_valid(unit, card, self_targets, false):
			result.append(self_targets)
		return result
	if target_type == CardEnums.TargetType.AREA and card.effect != null and card.effect.provides_area_target_cells():
		var cells: Array[Vector2i] = card.effect.get_area_target_cells(context)
		for cell in cells.slice(0, mini(6, cells.size())):
			var cell_targets: Array = [cell]
			if controller._targets_are_valid(unit, card, cell_targets, false):
				result.append(cell_targets)
		return result
	for target in controller.units:
		if target != null and target.is_alive() and controller._targets_are_valid(unit, card, [target], false):
			result.append([target])
	for target in controller.get_hostile_target_candidates(unit):
		if target is BattleObjectState and controller._targets_are_valid(unit, card, [target], false):
			result.append([target])
	return result


static func _filter_to_highest_hostile_threat(candidates: Array[EnemyIntentAction], unit: BattleUnitState) -> void:
	var highest := -1
	for action in candidates:
		if action == null or action.targets.size() != 1:
			continue
		var target = action.targets[0]
		if not _is_hostile_target(target, unit):
			continue
		var threat: int = target.get_threat_level() if target.has_method("get_threat_level") else 0
		highest = maxi(highest, threat)
	if highest < 0:
		return
	for index in range(candidates.size() - 1, -1, -1):
		var action := candidates[index]
		if action == null or action.targets.size() != 1:
			continue
		var target = action.targets[0]
		if _is_hostile_target(target, unit):
			var threat: int = target.get_threat_level() if target.has_method("get_threat_level") else 0
			if threat < highest:
				candidates.remove_at(index)


static func _is_hostile_target(target, unit: BattleUnitState) -> bool:
	if target is BattleUnitState:
		return (target as BattleUnitState).faction != unit.faction
	if target is BattleObjectState:
		return (target as BattleObjectState).is_trap and (target as BattleObjectState).owner_faction != unit.faction
	return false


static func _find_pool_entry(unit: BattleUnitState, card: CardData) -> EnemyCardPoolEntry:
	var rule := unit.enemy_state.enemy_data.deck_rule if unit.enemy_state != null and unit.enemy_state.enemy_data != null else null
	return rule.find_tactical_entry(card) if rule != null else null


static func _score_card_action(
	controller: BattleController,
	unit: BattleUnitState,
	entry: EnemyCardPoolEntry,
	rating: EnemyCardIntentRating,
	targets: Array,
	category: int,
	combo_tags: PackedStringArray
) -> float:
	var score := float(rating.base_score)
	if not rating.preferred_tags.is_empty() and _has_required_tags(rating.preferred_tags, combo_tags):
		score += rating.combo_bonus
	score += rating.damage_value
	score += rating.defense_value * (1.0 + _missing_health_ratio(unit))
	score += mini(rating.healing_value, unit.get_max_health() - unit.get_current_health()) * 1.5
	score += rating.draw_value * 2.5
	score += rating.movement_value * 2.0
	score += rating.control_value * 3.0
	score += rating.curse_value * 2.5
	score += rating.utility_value * 2.0
	var target := targets[0] as BattleUnitState if targets.size() == 1 and targets[0] is BattleUnitState else null
	if target != null:
		var target_preference := rating.target_preference if rating.target_preference >= 0 else entry.target_preference
		score += _score_target_preference(unit, target, target_preference)
		if target_preference == EnemyCardPoolEntry.TargetPreference.ALLY and target.faction == unit.faction:
			score += mini(rating.healing_value, target.get_max_health() - target.get_current_health()) * 1.5
		if target.faction != unit.faction and rating.damage_value > 0:
			var projected := rating.damage_value + unit.get_damage_bonus({"controller": controller, "target": target})
			if projected >= target.get_current_health():
				score += 30.0 if category == EnemyIntentCategory.Type.HARVEST else 14.0
	return score


static func _score_followup(unit: BattleUnitState, source_card: CardData, category: int, provided_tags: PackedStringArray) -> float:
	if provided_tags.is_empty() or unit.enemy_state == null or unit.enemy_state.enemy_data == null:
		return 0.0
	var best := 0.0
	var rule := unit.enemy_state.enemy_data.deck_rule
	if rule == null:
		return 0.0
	for card in unit.hand:
		if card == null or card == source_card:
			continue
		var entry := rule.find_tactical_entry(card)
		var rating := entry.get_intent_rating(category) if entry != null else null
		if rating != null and (_matches_nonempty_requirement(rating.required_tags, provided_tags) \
				or _matches_nonempty_requirement(rating.preferred_tags, provided_tags)):
			best = maxf(best, float(rating.combo_bonus) * 0.5)
	return best


static func _add_basic_attack_candidates(
	result: Array[EnemyIntentAction],
	controller: BattleController,
	unit: BattleUnitState,
	category: int,
	ap_budget: int
) -> void:
	var cost := controller.config.basic_attack_ap_cost
	if cost > ap_budget:
		return
	var profile := _get_profile(unit)
	for target in controller.get_hostile_target_candidates(unit):
		if not controller.can_basic_attack_target(unit, target):
			continue
		if category == EnemyIntentCategory.Type.HARVEST \
				and (not target is BattleUnitState or float(target.get_current_health()) / float(maxi(1, target.get_max_health())) > profile.harvest_health_ratio):
			continue
		var action := EnemyIntentAction.new()
		action.kind = EnemyIntentAction.Kind.BASIC_ATTACK
		action.label = "武器打击"
		action.targets = [target]
		action.ap_cost = cost
		var target_health: int = target.get_current_health() if target is BattleUnitState else target.current_health
		action.score = 8.0 + unit.get_attack() + (20.0 if unit.get_attack() >= target_health else 0.0)
		result.append(action)


static func _add_movement_candidate(
	result: Array[EnemyIntentAction],
	controller: BattleController,
	unit: BattleUnitState,
	category: int,
	ap_budget: int,
	move_away: bool
) -> void:
	if ap_budget <= 0:
		return
	var opponents := controller.get_highest_threat_targets(controller.get_hostile_target_candidates(unit))
	if opponents.is_empty():
		return
	var profile := _get_profile(unit)
	var best_cell := BattleHexGrid.INVALID_CELL
	var best_score := -INF
	var best_cost := 0
	for cell in controller.get_reachable_cells_for_ap(unit, ap_budget):
		if cell == unit.cell:
			continue
		var nearest_distance := 999
		var can_attack := false
		for target in opponents:
			if target == null or (target is BattleUnitState and not target.is_alive()) \
					or (target is BattleObjectState and not target.is_targetable()):
				continue
			var distance := controller.map_data.get_distance(cell, target.cell)
			nearest_distance = mini(nearest_distance, distance)
			can_attack = can_attack or distance <= unit.get_attack_range()
		var cell_score := float(nearest_distance * 5) if move_away else float(-nearest_distance * 4)
		if not move_away and can_attack:
			cell_score += 30.0
		if move_away and nearest_distance >= profile.preferred_range_min \
				and nearest_distance <= profile.preferred_range_max:
			cell_score += 12.0
		var path := controller.get_movement_path(unit, cell)
		var movement_cost := controller._get_path_movement_cost(unit, path)
		var ap_cost := unit.get_move_ap_cost(movement_cost, controller.config)
		cell_score -= ap_cost * 0.5
		if cell_score > best_score:
			best_score = cell_score
			best_cell = cell
			best_cost = ap_cost
	if best_cell == BattleHexGrid.INVALID_CELL:
		return
	var action := EnemyIntentAction.new()
	action.kind = EnemyIntentAction.Kind.MOVE
	action.label = EnemyIntentCategory.get_label(category)
	action.cell = best_cell
	action.ap_cost = best_cost
	action.score = best_score
	result.append(action)


static func _score_target_preference(unit: BattleUnitState, target: BattleUnitState, preference: int) -> float:
	match preference:
		EnemyCardPoolEntry.TargetPreference.LOWEST_HEALTH:
			return -float(target.get_current_health()) * 0.25
		EnemyCardPoolEntry.TargetPreference.HIGHEST_HEALTH:
			return float(target.get_current_health()) * 0.1
		EnemyCardPoolEntry.TargetPreference.SELF:
			return 5.0 if target == unit else -5.0
		EnemyCardPoolEntry.TargetPreference.ALLY:
			return 5.0 if target.faction == unit.faction else -5.0
		EnemyCardPoolEntry.TargetPreference.OPPONENT:
			return 5.0 if target.faction != unit.faction else -5.0
		_:
			return -float(unit.cell_distance_to(target)) * 0.5


static func _has_required_tags(required: PackedStringArray, available: PackedStringArray) -> bool:
	for tag in required:
		if not available.has(tag):
			return false
	return true


static func _matches_nonempty_requirement(required: PackedStringArray, available: PackedStringArray) -> bool:
	return not required.is_empty() and _has_required_tags(required, available)


static func _tags_overlap(first: PackedStringArray, second: PackedStringArray) -> bool:
	for tag in first:
		if second.has(tag):
			return true
	return false


static func _missing_health_ratio(unit: BattleUnitState) -> float:
	return 1.0 - float(unit.get_current_health()) / float(maxi(1, unit.get_max_health()))
