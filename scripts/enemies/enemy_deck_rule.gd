extends Resource
class_name EnemyDeckRule

@export var fixed_cards: Array[CardStack] = []
@export var random_pool: Array[CardStack] = []
@export_range(0, 99, 1) var random_pick_count: int = 0

func generate_deck(seed: int = -1) -> Array[CardStack]:
	var result: Array[CardStack] = []

	for stack in fixed_cards:
		_add_stack(result, stack)

	var pool := random_pool.duplicate()
	var rng := RandomNumberGenerator.new()
	if seed >= 0:
		rng.seed = seed
	else:
		rng.randomize()

	var picks := mini(random_pick_count, pool.size())
	for _i in range(picks):
		if pool.is_empty():
			break

		var index := rng.randi_range(0, pool.size() - 1)
		var stack = pool[index]
		_add_stack(result, stack)
		pool.remove_at(index)

	return result


func get_fixed_card_count() -> int:
	return _count_cards(fixed_cards)


func get_random_pool_card_count() -> int:
	return _count_cards(random_pool)


func _count_cards(stacks: Array[CardStack]) -> int:
	var total := 0
	for stack in stacks:
		if stack != null:
			total += stack.count

	return total


func _add_stack(deck: Array[CardStack], source_stack: CardStack) -> void:
	if source_stack == null or source_stack.card_data == null or source_stack.count <= 0:
		return

	for stack in deck:
		if stack != null and stack.card_data == source_stack.card_data:
			stack.count += source_stack.count
			return

	var copy := CardStack.new()
	copy.card_data = source_stack.card_data
	copy.count = source_stack.count
	deck.append(copy)
