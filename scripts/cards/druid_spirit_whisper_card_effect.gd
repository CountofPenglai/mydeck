extends CardEffect
class_name DruidSpiritWhisperCardEffect


const ROOT_STATUS := preload("res://scripts/status/druid_root_status.gd")


class NextWeaponStrikeStatus extends StatusEffect:
	func _init(amount: int = 0) -> void:
		status_id = "druid_spirit_whisper_next_strike"
		display_name = "万灵低语"
		stacks = maxi(0, amount)

	func modify_strike_context(unit: BattleUnitState, context: Dictionary = {}) -> void:
		if stacks <= 0 or unit == null or unit.character_state == null \
				or unit.character_state.weapon_equipment == null:
			return
		context["druid_spirit_whisper_next_strike_bonus"] = int(context.get("druid_spirit_whisper_next_strike_bonus", 0)) + stacks
		stacks = 0

	func on_turn_end(_unit: BattleUnitState, _context: Dictionary = {}) -> void:
		stacks = 0


func play(context: Dictionary = {}, _targets: Array = []) -> void:
	var controller := context.get("controller") as BattleController
	var user := context.get("user") as BattleUnitState
	var card := context.get("card") as CardData
	if controller == null or user == null or card == null:
		return
	var discarded_count := 0
	controller.resolution_runner.begin_descendant_scope()
	for hand_card in user.hand.duplicate():
		if hand_card != null and hand_card != card and user.discard_card(hand_card, {
			"controller": controller,
			"source": user,
			"source_card": card,
			"reason": "druid_spirit_whisper_discard",
		}):
			discarded_count += 1
	controller.resolution_runner.end_descendant_scope()
	if not user.is_alive() or not user.has_card_in_hand(card):
		return
	var revealed_cards := user.reveal_top_cards(discarded_count, controller.rng, {
		"controller": controller,
		"source": user,
		"source_card": card,
		"reason": "druid_spirit_whisper_reveal",
	})
	var attack_bonus := 0
	var heal_events := 0
	var ap_gain := 0
	for revealed_card in revealed_cards:
		if revealed_card.card_type == CardEnums.CardType.ATTACK:
			attack_bonus += 4
		if revealed_card.upright_is_transformation or revealed_card.inverted_is_transformation:
			heal_events += 1
		if revealed_card.get_twin_spell_face() >= 0:
			ap_gain += 1
	if attack_bonus > 0:
		user.add_status(NextWeaponStrikeStatus.new(attack_bonus))
	for _heal_index in range(heal_events):
		var heal_target := _get_lowest_wounded_ally(controller, user)
		if heal_target != null:
			controller.heal_unit(user, heal_target, 4, "万灵低语")
	user.current_ap += ap_gain
	user.add_revealed_cards_to_hand(revealed_cards, {
		"controller": controller,
		"source": user,
		"source_card": card,
	})


func on_zone_owner_targeted(owner: BattleUnitState, zone_card: CardData, context: Dictionary = {}) -> void:
	var controller := context.get("controller") as BattleController
	var source := context.get("source") as BattleUnitState
	if controller == null or owner == null or not owner.is_alive() or not owner.is_deployed or zone_card == null or source == null \
			or source.faction == owner.faction or not owner.mana_zone.has(zone_card):
		return
	var response_key := "druid_spirit_whisper_response_%d" % zone_card.get_instance_id()
	if bool(owner.battle_action_flags.get(response_key, false)):
		return
	owner.battle_action_flags[response_key] = true
	for candidate_value in controller.units:
		var candidate := candidate_value as BattleUnitState
		if candidate != null and candidate.is_alive() and candidate.is_deployed and candidate.faction != owner.faction \
				and owner.get_range_distance_to(candidate, {"controller": controller}) <= 3:
			candidate.add_status(ROOT_STATUS.new())
	var rooted_count := controller.druid_battle_rules.get_rooted_units(owner, 3).size()
	owner.gain_armor(rooted_count * 3, {
		"controller": controller,
		"source": owner,
		"source_card": zone_card,
		"action_id": int(context.get("action_id", 0)),
	})
	if owner.remove_card_from_mana_zone(zone_card):
		owner.add_card_to_discard(zone_card, {
			"controller": controller,
			"source": owner,
			"source_card": zone_card,
			"reason": "druid_spirit_whisper_response",
		})
	# This is a reentrancy lock, not a once-per-battle marker.  A physical card
	# that later returns to mana is a valid response again; queued duplicates are
	# instead rejected by the live-zone check in BattleUnitState.
	owner.battle_action_flags.erase(response_key)


func _get_lowest_wounded_ally(controller: BattleController, user: BattleUnitState) -> BattleUnitState:
	var result: BattleUnitState
	for candidate_value in controller.units:
		var candidate := candidate_value as BattleUnitState
		if candidate == null or not candidate.is_alive() or not candidate.is_deployed or candidate.faction != user.faction \
				or candidate.get_current_health() >= candidate.get_max_health():
			continue
		if result == null or candidate.get_current_health() < result.get_current_health() \
				or (candidate.get_current_health() == result.get_current_health() and candidate.unit_id < result.unit_id):
			result = candidate
	return result
