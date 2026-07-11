extends Resource
class_name BattleUnitState

enum Faction {
	PLAYER,
	ENEMY,
}

var unit_id: int = -1
var turn_order_index: int = 0
var faction: int = Faction.PLAYER
var character_state: CharacterState
var enemy_state: EnemyState
var position: Vector2 = Vector2.ZERO
var radius: float = 24.0
var is_deployed: bool = false
var current_ap: int = 0
var draw_pile: Array[CardData] = []
var hand: Array[CardData] = []
var discard_pile: Array[CardData] = []
var exiled_pile: Array[CardData] = []
var mana_zone: Array[CardData] = []
var enchant_zone: Array[CardData] = []
var curse_zone: Array[CardData] = []
var statuses: Array[StatusEffect] = []
var battle_action_flags := {}
var card_runtime_states: Dictionary = {}
var turn_serial: int = 0
var druid_transformed: bool = false
var druid_prepare_used: bool = false
var druid_temporary_mana: int = 0

func setup_player(id: int, state: CharacterState, unit_radius: float) -> void:
	unit_id = id
	turn_order_index = id
	faction = Faction.PLAYER
	character_state = state
	enemy_state = null
	radius = _resolve_collision_radius(unit_radius)
	is_deployed = false
	battle_action_flags.clear()
	card_runtime_states.clear()
	turn_serial = 0
	_reset_druid_state()


func setup_enemy(id: int, state: EnemyState, unit_radius: float, start_position: Vector2) -> void:
	unit_id = id
	turn_order_index = id
	faction = Faction.ENEMY
	character_state = null
	enemy_state = state
	radius = _resolve_collision_radius(unit_radius)
	position = start_position
	is_deployed = true
	battle_action_flags.clear()
	card_runtime_states.clear()
	turn_serial = 0
	_reset_druid_state()


func ensure_initialized(config: BattleConfig, rng: RandomNumberGenerator) -> void:
	if character_state != null:
		character_state.ensure_initialized()
		_prepare_deck(character_state.deck, rng, get_starting_hand_size(config))
	elif enemy_state != null:
		enemy_state.ensure_initialized()
		_prepare_deck(enemy_state.deck, rng, get_starting_hand_size(config))


func start_turn(config: BattleConfig) -> void:
	turn_serial += 1
	current_ap = get_max_ap(config)
	druid_prepare_used = false
	druid_temporary_mana = 0


func get_display_name() -> String:
	if character_state != null:
		return character_state.get_character_name()
	if enemy_state != null:
		return enemy_state.get_enemy_name()

	return "未知单位"


func get_current_health() -> int:
	if character_state != null:
		return character_state.current_health
	if enemy_state != null:
		return enemy_state.current_health

	return 0


func set_current_health(value: int) -> void:
	if character_state != null:
		character_state.current_health = clampi(value, 0, get_max_health())
	elif enemy_state != null:
		enemy_state.current_health = clampi(value, 0, get_max_health())


func apply_damage(amount: int) -> int:
	var actual := maxi(0, amount)
	set_current_health(get_current_health() - actual)
	return actual


func is_alive() -> bool:
	return get_current_health() > 0


func get_max_health() -> int:
	if character_state != null:
		return character_state.get_max_health()
	if enemy_state != null:
		return enemy_state.get_max_health()

	return 0


func get_attack() -> int:
	var profile := build_strike_profile_object()
	return profile.primary_power + profile.damage_bonus


func get_damage_bonus(context: Dictionary = {}) -> int:
	var merged_context := context.duplicate()
	merged_context["unit"] = self
	if character_state != null:
		return character_state.get_damage_bonus(merged_context)
	if enemy_state != null:
		return enemy_state.get_damage_bonus(merged_context)

	return 0


func get_damage_reduction(context: Dictionary = {}) -> int:
	var merged_context := context.duplicate()
	merged_context["unit"] = self
	if character_state != null:
		return character_state.get_damage_reduction() + get_status_damage_reduction(merged_context) + get_zone_damage_reduction(merged_context)
	if enemy_state != null:
		return enemy_state.get_damage_reduction() + get_status_damage_reduction(merged_context) + get_zone_damage_reduction(merged_context)

	return get_status_damage_reduction(merged_context) + get_zone_damage_reduction(merged_context)


func get_character_class() -> int:
	if character_state != null and character_state.character_data != null:
		return character_state.character_data.character_class

	return CardEnums.CardClass.NEUTRAL


func get_class_resource(resource_name: String) -> ResourcePoolState:
	if character_state != null:
		return character_state.get_class_resource(resource_name)

	return null


func get_class_resource_value(resource_name: String) -> int:
	if character_state != null:
		return character_state.get_class_resource_value(resource_name)

	return 0


func gain_class_resource(resource_name: String, amount: int) -> int:
	if character_state != null:
		return character_state.gain_class_resource(resource_name, amount)

	return 0


func consume_class_resource(resource_name: String, amount: int) -> bool:
	if character_state != null:
		return character_state.consume_class_resource(resource_name, amount)

	return false


func get_card_ap_cost(card: CardData, context: Dictionary = {}) -> int:
	if card == null:
		return 0

	var merged_context := context.duplicate()
	merged_context["user"] = self
	merged_context["unit"] = self
	merged_context["card"] = card
	if not merged_context.has("druid_orientation"):
		merged_context["druid_orientation"] = get_druid_card_orientation(card)
	var cost := card.get_ap_cost_for_context(merged_context)
	var runtime_state := get_card_runtime_state(card, false)
	if not runtime_state.is_empty():
		cost += int(runtime_state.get("ap_delta", 0))
	for status in statuses:
		if status != null and status.has_method("modify_card_ap_cost"):
			cost = status.modify_card_ap_cost(self, card, cost, merged_context)

	return maxi(0, cost)


func notify_card_ap_cost_paid(card: CardData, context: Dictionary = {}) -> void:
	var event_context := _with_unit_context(context)
	_notify_status_effects("on_card_ap_cost_paid", [card], event_context)
	_notify_zone_card_effects("on_zone_owner_card_ap_cost_paid", [card], event_context)


func get_status_damage_bonus(context: Dictionary = {}) -> int:
	var bonus := 0
	for status in statuses:
		if status != null and status.has_method("get_damage_bonus"):
			bonus += status.get_damage_bonus(self, context)

	return bonus


func get_status_damage_reduction(context: Dictionary = {}) -> int:
	var reduction := 0
	for status in statuses:
		if status != null and status.has_method("get_damage_reduction"):
			reduction += status.get_damage_reduction(self, context)

	return reduction


func get_zone_damage_reduction(context: Dictionary = {}) -> int:
	var reduction := 0
	for zone_name in ["mana", "enchant", "curse"]:
		var cards := _get_special_zone(zone_name)
		for zone_card in cards.duplicate():
			if zone_card == null or zone_card.effect == null:
				continue
			var event_context := _with_zone_context(zone_name, zone_card, context)
			reduction += maxi(0, zone_card.effect.get_zone_owner_damage_reduction(self, zone_card, event_context))
	return reduction


func modify_incoming_damage(damage_context: DamageContext) -> void:
	if damage_context == null:
		return
	for status in statuses.duplicate():
		if status != null:
			status.modify_incoming_damage(self, damage_context)
	remove_expired_statuses()


func get_status_strike_power_bonus(context: Dictionary = {}) -> int:
	var bonus := 0
	for status in statuses:
		if status != null and status.has_method("get_strike_power_bonus"):
			bonus += status.get_strike_power_bonus(self, context)

	return bonus


func get_agility() -> int:
	if character_state != null:
		return character_state.get_agility()
	if enemy_state != null:
		return enemy_state.get_agility()

	return 0


func get_strength() -> int:
	if is_druid() and druid_transformed:
		if character_state != null:
			return character_state.get_intelligence()
		if enemy_state != null:
			return enemy_state.get_intelligence()
	if character_state != null:
		return character_state.get_strength()
	if enemy_state != null:
		return enemy_state.get_strength()

	return 0


func get_intelligence() -> int:
	if is_druid() and druid_transformed:
		if character_state != null:
			return character_state.get_strength()
		if enemy_state != null:
			return enemy_state.get_strength()
	if character_state != null:
		return character_state.get_intelligence()
	if enemy_state != null:
		return enemy_state.get_intelligence()

	return 0


func get_starting_hand_size(config: BattleConfig) -> int:
	if config == null:
		return 0

	var hand_size := config.starting_hand_size
	if config.intelligence_per_starting_hand_card > 0:
		hand_size += floori(float(get_intelligence()) / float(config.intelligence_per_starting_hand_card))

	return maxi(0, hand_size)


func get_attack_range(equipment_slot: String = "") -> float:
	if character_state != null:
		return character_state.get_attack_range(equipment_slot)
	if enemy_state != null:
		return enemy_state.get_attack_range(equipment_slot)

	return 0.0


func build_strike_profile_object(equipment_slot: String = "", context: Dictionary = {}) -> StrikeProfile:
	var merged_context := context.duplicate()
	merged_context["unit"] = self
	if character_state != null:
		return character_state.build_strike_profile_object(equipment_slot, merged_context)
	if enemy_state != null:
		return enemy_state.build_strike_profile_object(equipment_slot, merged_context)

	var profile := StrikeProfile.new()
	profile.primary_slot = "unarmed"
	profile.primary_equipment = null
	profile.primary_power = 1
	profile.primary_range = 0.0
	profile.primary_range_type = EquipmentData.WeaponRangeType.MELEE
	profile.primary_damage_type = CardEnums.DamageType.STRENGTH
	profile.damage_bonus = 0
	profile.add_offhand = false
	profile.offhand_equipment = null
	profile.offhand_power = 0
	return profile


func needs_weapon_choice() -> bool:
	if character_state != null:
		return character_state.needs_weapon_choice()

	return false


func get_attack_weapon_options() -> Array:
	if character_state != null:
		return character_state.get_attack_weapon_options()

	return []


func has_equipment_subcategory(subcategory: String) -> bool:
	if character_state != null:
		return character_state.has_equipment_subcategory(subcategory)

	return false


func get_battle_texture() -> Texture2D:
	if character_state != null and character_state.character_data != null:
		return character_state.character_data.battle_sprite
	if enemy_state != null and enemy_state.enemy_data != null:
		return enemy_state.enemy_data.battle_sprite

	return null


func get_max_ap(config: BattleConfig) -> int:
	if character_state != null:
		return character_state.get_max_ap(config)
	if enemy_state != null:
		return enemy_state.get_max_ap(config)

	return config.base_ap


func get_move_distance_per_ap(config: BattleConfig, agility_modifier: int = 0) -> float:
	var effective_agility := maxi(0, get_agility() + agility_modifier)
	var distance := config.move_distance_per_ap + float(effective_agility) * config.move_distance_per_agility
	var context := {
		"config": config,
		"agility_modifier": agility_modifier,
		"effective_agility": effective_agility,
	}
	for status in statuses:
		if status != null and status.has_method("modify_move_distance_per_ap"):
			distance = status.modify_move_distance_per_ap(self, distance, context)

	return maxf(1.0, distance)


func get_move_ap_cost(distance: float, config: BattleConfig) -> int:
	var move_per_ap := get_move_distance_per_ap(config)
	var cost := ceili(distance / move_per_ap)
	var context := {
		"config": config,
		"distance": distance,
		"move_distance_per_ap": move_per_ap,
	}
	for status in statuses:
		if status != null and status.has_method("modify_move_ap_cost"):
			cost = status.modify_move_ap_cost(self, cost, context)

	return maxi(0, cost)


func notify_move_ap_cost_paid(context: Dictionary = {}) -> void:
	for status in statuses.duplicate():
		if status != null and status.has_method("on_move_ap_cost_paid"):
			status.on_move_ap_cost_paid(self, context)

	remove_expired_statuses()


func distance_to(other: BattleUnitState) -> float:
	return maxf(0.0, position.distance_to(other.position) - radius - other.radius)


func draw_cards(count: int, rng: RandomNumberGenerator, context: Dictionary = {}) -> int:
	return draw_cards_detailed(count, rng, context).size()


func draw_cards_detailed(count: int, rng: RandomNumberGenerator, context: Dictionary = {}) -> Array[CardData]:
	var drawn_cards: Array[CardData] = []
	for _i in range(maxi(0, count)):
		if draw_pile.is_empty() and not discard_pile.is_empty():
			draw_pile = discard_pile.duplicate()
			discard_pile.clear()
			_shuffle_cards(draw_pile, rng)

		if draw_pile.is_empty():
			break

		var drawn_card: CardData = draw_pile.pop_back() as CardData
		hand.append(drawn_card)
		drawn_cards.append(drawn_card)
		_notify_card_drawn(drawn_card, context)

	return drawn_cards


func mill_cards(count: int, context: Dictionary = {}) -> Array[CardData]:
	var milled: Array[CardData] = []
	for _i in range(maxi(0, count)):
		if draw_pile.is_empty():
			break

		var card: CardData = draw_pile.pop_back() as CardData
		if card == null:
			continue
		discard_pile.append(card)
		milled.append(card)
		var discard_context := context.duplicate()
		discard_context["reason"] = "mill"
		_notify_card_discarded(card, discard_context)

	return milled


func preview_discard_after_mill(count: int) -> Array[CardData]:
	var result: Array[CardData] = discard_pile.duplicate()
	var available := mini(maxi(0, count), draw_pile.size())
	for index in range(available):
		var draw_index := draw_pile.size() - 1 - index
		var card: CardData = draw_pile[draw_index]
		if card != null:
			result.append(card)

	return result


func discard_card(card: CardData, context: Dictionary = {}) -> bool:
	var index := hand.find(card)
	if index < 0:
		return false

	hand.remove_at(index)
	discard_pile.append(card)
	_notify_card_discarded(card, context)
	return true


func add_card_to_mana_zone(card: CardData, context: Dictionary = {}) -> void:
	if card == null:
		return

	mana_zone.append(card)
	_notify_card_entered_special_zone(card, "mana", context)
	_notify_mana_gained(1, context)


func add_card_to_enchant_zone(card: CardData, context: Dictionary = {}) -> void:
	if card == null:
		return

	enchant_zone.append(card)
	_notify_card_entered_special_zone(card, "enchant", context)


func move_enchant_card_to_discard(card: CardData, context: Dictionary = {}) -> bool:
	var index := enchant_zone.find(card)
	if index < 0:
		return false

	enchant_zone.remove_at(index)
	discard_pile.append(card)
	clear_card_runtime_state(card)
	_notify_card_discarded(card, context)
	return true


func add_card_to_curse_zone(card: CardData, context: Dictionary = {}) -> void:
	if card == null:
		return

	curse_zone.append(card)
	_notify_card_entered_special_zone(card, "curse", context)


func move_hand_card_to_mana(card: CardData, context: Dictionary = {}) -> bool:
	var index := hand.find(card)
	if index < 0:
		return false

	hand.remove_at(index)
	add_card_to_mana_zone(card, context)
	return true


func move_hand_card_to_enchant(card: CardData, context: Dictionary = {}) -> bool:
	var index := hand.find(card)
	if index < 0:
		return false

	hand.remove_at(index)
	add_card_to_enchant_zone(card, context)
	return true


func move_hand_card_to_curse(card: CardData, context: Dictionary = {}) -> bool:
	var index := hand.find(card)
	if index < 0:
		return false

	hand.remove_at(index)
	add_card_to_curse_zone(card, context)
	return true


func get_available_mana() -> int:
	return mana_zone.size() + maxi(0, druid_temporary_mana)


func can_pay_mana(amount: int) -> bool:
	return amount <= 0 or get_available_mana() >= amount


func can_pay_mana_excluding_card(amount: int, excluded_card: CardData) -> bool:
	if amount <= 0:
		return true

	var available := get_available_mana()
	if excluded_card != null and mana_zone.find(excluded_card) >= 0:
		available -= 1
	return available >= amount


func pay_mana(amount: int) -> bool:
	if amount <= 0:
		return true
	if not can_pay_mana(amount):
		return false

	var remaining := amount
	var temporary_paid := mini(druid_temporary_mana, remaining)
	druid_temporary_mana -= temporary_paid
	remaining -= temporary_paid
	while remaining > 0 and not mana_zone.is_empty():
		mana_zone.pop_back()
		remaining -= 1

	return remaining <= 0


func pay_mana_excluding_card(amount: int, excluded_card: CardData) -> bool:
	if amount <= 0:
		return true
	if not can_pay_mana_excluding_card(amount, excluded_card):
		return false

	var remaining := amount
	var temporary_paid := mini(druid_temporary_mana, remaining)
	druid_temporary_mana -= temporary_paid
	remaining -= temporary_paid
	for i in range(mana_zone.size() - 1, -1, -1):
		if remaining <= 0:
			break
		var mana_card: CardData = mana_zone[i]
		if mana_card == excluded_card:
			continue
		mana_zone.remove_at(i)
		remaining -= 1

	return remaining <= 0


func gain_temporary_mana(amount: int, context: Dictionary = {}) -> void:
	var actual := maxi(0, amount)
	if actual <= 0:
		return

	druid_temporary_mana = maxi(0, druid_temporary_mana + actual)
	_notify_mana_gained(actual, context)


func is_druid() -> bool:
	return get_character_class() == CardEnums.CardClass.DRUID


func is_druid_transformed() -> bool:
	return is_druid() and druid_transformed


func set_druid_transformed(value: bool) -> void:
	druid_transformed = value if is_druid() else false


func get_druid_card_orientation(card: CardData) -> int:
	if is_druid_transformed() and card != null and card.is_druid_dual_card:
		return CardEnums.DruidOrientation.INVERTED

	return CardEnums.DruidOrientation.UPRIGHT


func discard_all_hand(context: Dictionary = {}) -> int:
	var count := hand.size()
	for card in hand:
		if card != null:
			discard_pile.append(card)
			_notify_card_discarded(card, context)
	hand.clear()
	return count


func move_draw_card_to_discard(card: CardData) -> bool:
	var index := draw_pile.find(card)
	if index < 0:
		return false

	draw_pile.remove_at(index)
	discard_pile.append(card)
	return true


func move_discard_card_to_hand(card: CardData) -> bool:
	var index := discard_pile.find(card)
	if index < 0:
		return false

	discard_pile.remove_at(index)
	hand.append(card)
	return true


func banish_discard_card(card: CardData) -> bool:
	var index := discard_pile.find(card)
	if index < 0:
		return false

	discard_pile.remove_at(index)
	exiled_pile.append(card)
	return true


func move_exiled_card_to_discard(card: CardData) -> bool:
	var index := exiled_pile.find(card)
	if index < 0:
		return false

	exiled_pile.remove_at(index)
	discard_pile.append(card)
	return true


func banish_discard_cards(count: int, excluded_card: CardData = null) -> Array[CardData]:
	var banished: Array[CardData] = []
	if count <= 0:
		return banished

	for card in discard_pile.duplicate():
		if banished.size() >= count:
			break
		if card == null or card == excluded_card:
			continue
		if banish_discard_card(card):
			banished.append(card)

	return banished


func count_discard_cards_excluding(excluded_card: CardData = null) -> int:
	var count := 0
	for card in discard_pile:
		if card != null and card != excluded_card:
			count += 1

	return count


func shuffle_exiled_into_draw_pile(rng: RandomNumberGenerator) -> int:
	if exiled_pile.is_empty():
		return 0

	var returned_count := exiled_pile.size()
	for card in exiled_pile:
		if card != null:
			draw_pile.append(card)
	exiled_pile.clear()
	_shuffle_cards(draw_pile, rng)
	return returned_count


func move_discard_cards_to_draw_top(cards_in_top_order: Array[CardData], max_count: int = 3) -> Array[CardData]:
	var moved: Array[CardData] = []
	for card in cards_in_top_order:
		if moved.size() >= max_count:
			break
		if card == null:
			continue
		var index := discard_pile.find(card)
		if index < 0:
			continue
		discard_pile.remove_at(index)
		moved.append(card)

	for i in range(moved.size() - 1, -1, -1):
		draw_pile.append(moved[i])

	return moved


func has_card_in_hand(card: CardData) -> bool:
	return hand.find(card) >= 0


func has_card_in_discard(card: CardData) -> bool:
	return discard_pile.find(card) >= 0


func has_card_in_exile(card: CardData) -> bool:
	return exiled_pile.find(card) >= 0


func has_card_in_enchant(card: CardData) -> bool:
	return enchant_zone.find(card) >= 0


func get_card_runtime_state(card: CardData, create_if_missing: bool = true) -> Dictionary:
	if card == null:
		return {}
	if card_runtime_states.has(card):
		return card_runtime_states[card] as Dictionary
	if not create_if_missing:
		return {}

	var state: Dictionary = {}
	card_runtime_states[card] = state
	return state


func clear_card_runtime_state(card: CardData) -> void:
	if card != null:
		card_runtime_states.erase(card)


func mark_temporary_card(card: CardData, ap_delta: int, exile_after_play: bool, exile_at_turn_end: bool) -> void:
	var state := get_card_runtime_state(card)
	state["ap_delta"] = ap_delta
	state["exile_after_play"] = exile_after_play
	state["exile_at_turn_end"] = exile_at_turn_end
	state["expire_turn_serial"] = turn_serial


func should_exile_card_after_play(card: CardData) -> bool:
	var state := get_card_runtime_state(card, false)
	return bool(state.get("exile_after_play", false))


func move_card_to_exile(card: CardData) -> bool:
	if card == null:
		return false
	if exiled_pile.find(card) >= 0:
		clear_card_runtime_state(card)
		return true

	var zones: Array = [hand, draw_pile, discard_pile, mana_zone, enchant_zone, curse_zone]
	for zone_value in zones:
		var zone: Array = zone_value as Array
		var index: int = zone.find(card)
		if index >= 0:
			zone.remove_at(index)
			exiled_pile.append(card)
			clear_card_runtime_state(card)
			return true
	return false


func exile_expiring_temporary_cards(controller: BattleController) -> int:
	var exiled_count := 0
	for card_value in card_runtime_states.keys().duplicate():
		var card: CardData = card_value as CardData
		var state := get_card_runtime_state(card, false)
		if not bool(state.get("exile_at_turn_end", false)):
			continue
		if int(state.get("expire_turn_serial", -1)) > turn_serial:
			continue
		if move_card_to_exile(card):
			exiled_count += 1
			if controller != null:
				controller._emit_log("%s 的临时牌 %s 在回合结束时被放逐。" % [get_display_name(), card.card_name])
		else:
			clear_card_runtime_state(card)
	return exiled_count


func has_used_battle_action(action_id: String) -> bool:
	return bool(battle_action_flags.get(action_id, false))


func mark_battle_action_used(action_id: String) -> void:
	if action_id.is_empty():
		return
	battle_action_flags[action_id] = true


func notify_after_damage_dealt(context: Dictionary = {}) -> void:
	var event_context := _with_unit_context(context)
	_notify_status_effects("on_after_damage_dealt", [], event_context)
	_notify_zone_card_effects("on_zone_owner_after_damage_dealt", [], event_context)


func notify_after_damage_taken(context: Dictionary = {}) -> void:
	var event_context := _with_unit_context(context)
	_notify_status_effects("on_after_damage_taken", [], event_context)
	_notify_zone_card_effects("on_zone_owner_after_damage_taken", [], event_context)


func notify_after_heal_given(context: Dictionary = {}) -> void:
	var event_context := _with_unit_context(context)
	_notify_status_effects("on_after_heal_given", [], event_context)
	_notify_zone_card_effects("on_zone_owner_after_heal_given", [], event_context)


func notify_after_heal_received(context: Dictionary = {}) -> void:
	var event_context := _with_unit_context(context)
	_notify_status_effects("on_after_heal_received", [], event_context)
	_notify_zone_card_effects("on_zone_owner_after_heal_received", [], event_context)


func notify_after_strike(context: Dictionary = {}) -> void:
	var event_context := _with_unit_context(context)
	_notify_status_effects("on_after_strike", [], event_context)
	_notify_zone_card_effects("on_zone_owner_after_strike", [], event_context)


func notify_equipment_switched(switch_result: Dictionary, context: Dictionary = {}) -> void:
	var event_context := _with_unit_context(context)
	event_context["switch_result"] = switch_result
	_notify_zone_card_effects("on_zone_owner_equipment_switched", [switch_result], event_context)


func get_armor_stacks() -> int:
	var armor := get_status("armor")
	return armor.stacks if armor != null else 0


func gain_armor(amount: int, context: Dictionary = {}) -> int:
	var actual := maxi(0, amount)
	if actual <= 0:
		return 0
	var previous := get_armor_stacks()
	var armor := get_status("armor")
	if armor == null:
		armor = ArmorStatus.new()
		armor.stacks = actual
		add_status(armor)
	else:
		armor.add_stacks(actual)
	notify_armor_changed(previous, get_armor_stacks(), context)
	return actual


func clear_armor(context: Dictionary = {}) -> int:
	var armor := get_status("armor")
	if armor == null or armor.stacks <= 0:
		return 0
	var previous := armor.stacks
	armor.stacks = 0
	notify_armor_changed(previous, 0, context)
	remove_expired_statuses()
	return previous


func notify_armor_changed(previous: int, current: int, context: Dictionary = {}) -> void:
	if previous == current:
		return
	var event_context := _with_unit_context(context)
	event_context["previous_armor"] = previous
	event_context["current_armor"] = current
	_notify_status_effects("on_armor_changed", [previous, current], event_context)
	_notify_zone_card_effects("on_zone_owner_armor_changed", [previous, current], event_context)


func _reset_druid_state() -> void:
	mana_zone.clear()
	enchant_zone.clear()
	curse_zone.clear()
	druid_transformed = false
	druid_prepare_used = false
	druid_temporary_mana = 0


func add_status(status: StatusEffect) -> void:
	if status == null or status.status_id.is_empty() or status.stacks <= 0:
		return

	var existing := get_status(status.status_id)
	if existing != null:
		existing.add_stacks(status.stacks)
		return

	statuses.append(status if status.resource_path.is_empty() else status.duplicate(true))


func get_status(status_id: String) -> StatusEffect:
	for status in statuses:
		if status != null and status.status_id == status_id:
			return status

	return null


func has_status(status_id: String) -> bool:
	return get_status(status_id) != null


func remove_status(status_id: String) -> void:
	for i in range(statuses.size() - 1, -1, -1):
		var status: StatusEffect = statuses[i]
		if status != null and status.status_id == status_id:
			statuses.remove_at(i)


func remove_expired_statuses() -> void:
	for i in range(statuses.size() - 1, -1, -1):
		var status: StatusEffect = statuses[i]
		if status == null or status.should_remove():
			statuses.remove_at(i)


func _notify_card_drawn(card: CardData, context: Dictionary = {}) -> void:
	var event_context := _with_unit_context(context)
	event_context["drawn_card"] = card
	_notify_status_effects("on_card_drawn", [card], event_context)
	_notify_zone_card_effects("on_zone_owner_card_drawn", [card], event_context)


func _notify_card_discarded(card: CardData, context: Dictionary = {}) -> void:
	var event_context := _with_unit_context(context)
	event_context["discarded_card"] = card
	_notify_status_effects("on_card_discarded", [card], event_context)
	_notify_zone_card_effects("on_zone_owner_card_discarded", [card], event_context)


func _notify_card_entered_special_zone(card: CardData, zone_name: String, context: Dictionary = {}) -> void:
	var event_context := _with_unit_context(context)
	event_context["entered_card"] = card
	event_context["zone_name"] = zone_name
	_notify_status_effects("on_card_entered_special_zone", [card, zone_name], event_context)
	_notify_zone_card_effects("on_zone_card_entered_special_zone", [card, zone_name], event_context)


func _notify_mana_gained(amount: int, context: Dictionary = {}) -> void:
	var actual := maxi(0, amount)
	if actual <= 0:
		return

	var event_context := _with_unit_context(context)
	event_context["mana_gained"] = actual
	_notify_status_effects("on_mana_gained", [actual], event_context)
	_notify_zone_card_effects("on_zone_owner_mana_gained", [actual], event_context)


func _notify_status_effects(method_name: String, extra_args: Array = [], context: Dictionary = {}) -> void:
	for status in statuses.duplicate():
		if status == null or not _script_defines_method(status, method_name):
			continue
		var args := [self]
		args.append_array(extra_args)
		args.append(context)
		_dispatch_trigger(
			Callable(self, "_invoke_status_hook"),
			[status, method_name, args],
			status.effect_priority,
			"%s.%s" % [status.display_name, method_name],
			context
		)


func _invoke_status_hook(status: StatusEffect, method_name: String, args: Array) -> void:
	if status == null or not statuses.has(status) or status.should_remove():
		return
	status.callv(method_name, args)
	remove_expired_statuses()


func _notify_zone_card_effects(method_name: String, extra_args: Array = [], context: Dictionary = {}) -> void:
	_notify_zone_card_effects_in_zone(mana_zone, "mana", method_name, extra_args, context)
	_notify_zone_card_effects_in_zone(enchant_zone, "enchant", method_name, extra_args, context)
	_notify_zone_card_effects_in_zone(curse_zone, "curse", method_name, extra_args, context)


func _notify_zone_card_effects_in_zone(cards: Array[CardData], zone_name: String, method_name: String, extra_args: Array = [], context: Dictionary = {}) -> void:
	for zone_card in cards.duplicate():
		if zone_card == null or zone_card.effect == null or not _script_defines_method(zone_card.effect, method_name):
			continue

		var event_context := _with_zone_context(zone_name, zone_card, context)
		var args := [self, zone_card]
		args.append_array(extra_args)
		args.append(event_context)
		_dispatch_trigger(
			Callable(zone_card.effect, method_name),
			args,
			zone_card.effect.effect_priority,
			"%s.%s" % [zone_card.card_name, method_name],
			event_context
		)


func _dispatch_trigger(callback: Callable, args: Array, priority: int, label: String, context: Dictionary) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	if controller != null and controller.get_current_action_id() > 0:
		controller.enqueue_trigger(callback, args, priority, label, context)
	else:
		callback.callv(args)


func _script_defines_method(resource: Resource, method_name: String) -> bool:
	if resource == null or resource.get_script() == null:
		return false
	for method in resource.get_script().get_script_method_list():
		if str(method.get("name", "")) == method_name:
			return true
	return false


func _with_zone_context(zone_name: String, zone_card: CardData, context: Dictionary = {}) -> Dictionary:
	var event_context := context.duplicate()
	event_context["zone_owner"] = self
	event_context["zone_card"] = zone_card
	event_context["zone_name"] = zone_name
	return event_context


func _get_special_zone(zone_name: String) -> Array[CardData]:
	match zone_name:
		"mana":
			return mana_zone
		"enchant":
			return enchant_zone
		"curse":
			return curse_zone
		_:
			return []


func _with_unit_context(context: Dictionary = {}) -> Dictionary:
	var event_context := context.duplicate()
	event_context["unit"] = self
	event_context["owner"] = self
	return event_context


func _prepare_deck(stacks: Array[CardStack], rng: RandomNumberGenerator, starting_hand_size: int) -> void:
	if not draw_pile.is_empty() or not hand.is_empty() or not discard_pile.is_empty():
		return

	for stack in stacks:
		if stack == null or stack.card_data == null:
			continue
		for _i in range(stack.count):
			var runtime_card := stack.card_data.duplicate() as CardData
			if runtime_card != null:
				draw_pile.append(runtime_card)

	_shuffle_cards(draw_pile, rng)
	draw_cards(starting_hand_size, rng)


func _shuffle_cards(cards: Array[CardData], rng: RandomNumberGenerator) -> void:
	if cards.size() < 2:
		return

	for i in range(cards.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var temp: CardData = cards[i]
		cards[i] = cards[j]
		cards[j] = temp


func _resolve_collision_radius(default_radius: float) -> float:
	var data_radius := 0.0
	if character_state != null:
		data_radius = character_state.get_collision_radius()
	elif enemy_state != null:
		data_radius = enemy_state.get_collision_radius()

	if data_radius > 0.0:
		return data_radius

	return default_radius
