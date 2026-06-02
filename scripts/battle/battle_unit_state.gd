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
var statuses: Array[StatusEffect] = []

func setup_player(id: int, state: CharacterState, unit_radius: float) -> void:
	unit_id = id
	turn_order_index = id
	faction = Faction.PLAYER
	character_state = state
	enemy_state = null
	radius = unit_radius
	is_deployed = false


func setup_enemy(id: int, state: EnemyState, unit_radius: float, start_position: Vector2) -> void:
	unit_id = id
	turn_order_index = id
	faction = Faction.ENEMY
	character_state = null
	enemy_state = state
	radius = unit_radius
	position = start_position
	is_deployed = true


func ensure_initialized(config: BattleConfig, rng: RandomNumberGenerator) -> void:
	if character_state != null:
		character_state.ensure_initialized()
		_prepare_deck(character_state.deck, rng, config.starting_hand_size)
	elif enemy_state != null:
		enemy_state.ensure_initialized()
		_prepare_deck(enemy_state.deck, rng, config.starting_hand_size)


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
	if character_state != null:
		return character_state.get_attack()
	if enemy_state != null:
		return enemy_state.get_attack()

	return 0


func get_speed() -> int:
	if character_state != null:
		return character_state.get_speed()
	if enemy_state != null:
		return enemy_state.get_speed()

	return 0


func get_attack_range() -> float:
	if character_state != null:
		return character_state.get_attack_range()
	if enemy_state != null:
		return enemy_state.get_attack_range()

	return 0.0


func has_equipment_tag(tag: String) -> bool:
	if character_state != null:
		return character_state.has_equipment_tag(tag)

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
	return config.move_distance_per_ap + float(get_speed()) * config.move_distance_per_speed


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

		hand.append(draw_pile.pop_back())
		drawn += 1

	return drawn


func discard_card(card: CardData) -> void:
	var index := hand.find(card)
	if index >= 0:
		hand.remove_at(index)
		discard_pile.append(card)


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
		var status := statuses[i]
		if status != null and status.status_id == status_id:
			statuses.remove_at(i)


func remove_expired_statuses() -> void:
	for i in range(statuses.size() - 1, -1, -1):
		var status := statuses[i]
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
		var temp := cards[i]
		cards[i] = cards[j]
		cards[j] = temp
