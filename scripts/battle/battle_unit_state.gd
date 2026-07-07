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
var statuses: Array[StatusEffect] = []
var battle_action_flags := {}

func setup_player(id: int, state: CharacterState, unit_radius: float) -> void:
	unit_id = id
	turn_order_index = id
	faction = Faction.PLAYER
	character_state = state
	enemy_state = null
	radius = _resolve_collision_radius(unit_radius)
	is_deployed = false
	battle_action_flags.clear()


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


func ensure_initialized(config: BattleConfig, rng: RandomNumberGenerator) -> void:
	if character_state != null:
		character_state.ensure_initialized()
		_prepare_deck(character_state.deck, rng, get_starting_hand_size(config))
	elif enemy_state != null:
		enemy_state.ensure_initialized()
		_prepare_deck(enemy_state.deck, rng, get_starting_hand_size(config))


func start_turn(config: BattleConfig) -> void:
	current_ap = get_max_ap(config)


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
		return character_state.get_damage_reduction() + get_status_damage_reduction(merged_context)
	if enemy_state != null:
		return enemy_state.get_damage_reduction() + get_status_damage_reduction(merged_context)

	return get_status_damage_reduction(merged_context)


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

	var cost := card.ap_cost
	for status in statuses:
		if status != null and status.has_method("modify_card_ap_cost"):
			cost = status.modify_card_ap_cost(self, card, cost, context)

	return maxi(0, cost)


func notify_card_ap_cost_paid(card: CardData, context: Dictionary = {}) -> void:
	for status in statuses.duplicate():
		if status != null and status.has_method("on_card_ap_cost_paid"):
			status.on_card_ap_cost_paid(self, card, context)

	remove_expired_statuses()


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
	if character_state != null:
		return character_state.get_strength()
	if enemy_state != null:
		return enemy_state.get_strength()

	return 0


func get_intelligence() -> int:
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


func get_move_distance_per_ap(config: BattleConfig) -> float:
	var distance := config.move_distance_per_ap + float(get_agility()) * config.move_distance_per_agility
	var context := {
		"config": config,
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


func draw_cards(count: int, rng: RandomNumberGenerator) -> int:
	var drawn := 0
	for _i in range(maxi(0, count)):
		if draw_pile.is_empty() and not discard_pile.is_empty():
			draw_pile = discard_pile.duplicate()
			discard_pile.clear()
			_shuffle_cards(draw_pile, rng)

		if draw_pile.is_empty():
			break

		var drawn_card: CardData = draw_pile.pop_back() as CardData
		hand.append(drawn_card)
		drawn += 1

	return drawn


func mill_cards(count: int) -> Array[CardData]:
	var milled: Array[CardData] = []
	for _i in range(maxi(0, count)):
		if draw_pile.is_empty():
			break

		var card: CardData = draw_pile.pop_back() as CardData
		if card == null:
			continue
		discard_pile.append(card)
		milled.append(card)

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


func discard_card(card: CardData) -> void:
	var index := hand.find(card)
	if index >= 0:
		hand.remove_at(index)
		discard_pile.append(card)


func discard_all_hand() -> int:
	var count := hand.size()
	for card in hand:
		if card != null:
			discard_pile.append(card)
	hand.clear()
	return count


func move_draw_card_to_discard(card: CardData) -> bool:
	var index := draw_pile.find(card)
	if index < 0:
		return false

	draw_pile.remove_at(index)
	discard_pile.append(card)
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


func has_used_battle_action(action_id: String) -> bool:
	return bool(battle_action_flags.get(action_id, false))


func mark_battle_action_used(action_id: String) -> void:
	if action_id.is_empty():
		return
	battle_action_flags[action_id] = true


func add_status(status: StatusEffect) -> void:
	if status == null or status.status_id.is_empty() or status.stacks <= 0:
		return

	var existing := get_status(status.status_id)
	if existing != null:
		existing.add_stacks(status.stacks)
		return

	statuses.append(status.duplicate(true))


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


func _prepare_deck(stacks: Array[CardStack], rng: RandomNumberGenerator, starting_hand_size: int) -> void:
	if not draw_pile.is_empty() or not hand.is_empty() or not discard_pile.is_empty():
		return

	for stack in stacks:
		if stack == null or stack.card_data == null:
			continue
		for _i in range(stack.count):
			draw_pile.append(stack.card_data)

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
