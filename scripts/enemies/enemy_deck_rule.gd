extends Resource
class_name EnemyDeckRule

@export var fixed_cards: Array[CardStack] = []
@export var random_pool: Array[CardStack] = []
@export_range(0, 99, 1) var random_pick_count: int = 0
@export var category_slots: Array[EnemyDeckSlot] = []
@export var tactical_entries: Array[EnemyCardPoolEntry] = []


func find_tactical_entry(card: CardData) -> EnemyCardPoolEntry:
	for entry in tactical_entries:
		if entry != null and entry.matches_card(card):
			return entry
	for slot in category_slots:
		if slot == null:
			continue
		for entry in slot.entries:
			if entry != null and entry.matches_card(card):
				return entry
	return null

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
		var stack: CardStack = pool[index]
		_add_stack(result, stack)
		pool.remove_at(index)

	var copy_counts := {}
	for slot in category_slots:
		if slot == null:
			continue
		for _pick in range(slot.pick_count):
			var entry := _pick_weighted_entry(slot.get_valid_entries(), copy_counts, rng)
			if entry == null:
				break
			_add_card(result, entry.card)
			copy_counts[entry.card] = int(copy_counts.get(entry.card, 0)) + 1

	return result


func get_recipe_summary() -> String:
	var parts := PackedStringArray()
	for slot in category_slots:
		if slot != null and slot.pick_count > 0:
			parts.append("%s×%d" % [slot.slot_label, slot.pick_count])
	return "、".join(parts)


func _pick_weighted_entry(entries: Array[EnemyCardPoolEntry], copy_counts: Dictionary, rng: RandomNumberGenerator) -> EnemyCardPoolEntry:
	var candidates: Array[EnemyCardPoolEntry] = []
	var total_weight := 0
	for entry in entries:
		if int(copy_counts.get(entry.card, 0)) >= entry.max_copies:
			continue
		candidates.append(entry)
		total_weight += entry.weight
	if candidates.is_empty() or total_weight <= 0:
		return null
	var roll := rng.randi_range(1, total_weight)
	for entry in candidates:
		roll -= entry.weight
		if roll <= 0:
			return entry
	return candidates.back()


func _add_card(deck: Array[CardStack], card: CardData) -> void:
	if card == null:
		return
	var stack := CardStack.new()
	stack.card_data = card
	stack.count = 1
	_add_stack(deck, stack)


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
