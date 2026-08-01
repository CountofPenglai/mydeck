extends RefCounted
class_name AdventureRewardService

var _card_pool: Array[CardData] = []
var _equipment_pool: Array[EquipmentData] = []
var _consumable_pool: Array[ConsumableData] = []


func create_battle_reward(run_state: PartyRunState, room: AdventureRoomState, encounter_tier: int) -> Dictionary:
	_ensure_catalog()
	var rng := RandomNumberGenerator.new()
	rng.seed = AdventureMapGenerator.derive_seed(run_state.run_seed, "reward", room.room_id.hash() + run_state.floor_index * 1000)
	var reward := {
		"room_id": room.room_id,
		"cards": [],
		"equipment": [],
		"claimed_cards": [],
		"claimed_equipment": [],
		"max_cards": 2,
		"max_equipment": 0,
		"gold": 0,
		"provisions": 0,
		"ritual_points": 0,
		"camp_supplies": 0,
		"settled": false,
	}
	if room.room_type == AdventureEnums.RoomType.NORMAL_BATTLE:
		_add_normal_card_candidates(reward, run_state.get_active_party(), encounter_tier, rng)
		reward["provisions"] = 1 if rng.randf() < 0.2 else 0
	elif room.room_type == AdventureEnums.RoomType.ELITE_BATTLE:
		_add_elite_card_candidates(reward, run_state.get_active_party(), rng, 1)
		reward["equipment"] = _equipment_candidates(
			run_state, rng, 3, -1, "battle:%s" % room.room_id
		)
		reward["max_equipment"] = 1
		reward["ritual_points"] = 1 if rng.randf() < 0.25 else 0
	elif room.room_type == AdventureEnums.RoomType.BOSS_BATTLE:
		_add_elite_card_candidates(reward, run_state.get_active_party(), rng, 2)
		if run_state.floor_index < run_state.floor_count - 1:
			reward["equipment"] = _equipment_candidates(
				run_state,
				rng,
				3,
				run_state.floor_index + 1,
				"battle:%s" % room.room_id
			)
			reward["max_equipment"] = 1
			reward["ritual_points"] = 1
			reward["camp_supplies"] = 1
	return reward


func get_shop_stock(run_state: PartyRunState, room: AdventureRoomState) -> Array[Dictionary]:
	_ensure_catalog()
	var existing = room.runtime_data.get("shop_stock", [])
	if existing is Array and not existing.is_empty():
		var sanitized := _sanitize_shop_stock(existing as Array)
		room.runtime_data["shop_stock"] = sanitized.duplicate(true)
		return sanitized
	var rng := RandomNumberGenerator.new()
	rng.seed = AdventureMapGenerator.derive_seed(run_state.run_seed, "shop", room.room_id.hash() + run_state.floor_index * 1000)
	var stock: Array[Dictionary] = []
	for hero in run_state.party:
		if hero == null or hero.character_data == null:
			continue
		var candidates := _cards_for_class(hero.character_data.character_class)
		_shuffle(candidates, rng)
		for index in range(mini(2, candidates.size())):
			var card := candidates[index]
			stock.append(_stock_entry("card", card.resource_path, card.card_name, _card_price(card.rarity), hero.adventure_character_id))
	for equipment in _pick_shop_equipment(run_state, rng, 2):
		stock.append(_stock_entry("equipment", equipment.resource_path, equipment.item_name, _equipment_price(equipment.rarity)))
	var consumables: Array[ConsumableData] = _consumable_pool.duplicate()
	_shuffle(consumables, rng)
	for index in range(mini(3, consumables.size())):
		var consumable: ConsumableData = consumables[index]
		stock.append(_stock_entry("consumable", consumable.resource_path, consumable.item_name, 12))
	room.runtime_data["shop_stock"] = stock.duplicate(true)
	return stock


func get_wilderness_merchant_stock(run_state: PartyRunState, room: AdventureRoomState) -> Array[Dictionary]:
	_ensure_catalog()
	var existing = room.runtime_data.get("shop_stock", [])
	if existing is Array and not existing.is_empty():
		var sanitized := _sanitize_shop_stock(existing as Array)
		room.runtime_data["shop_stock"] = sanitized.duplicate(true)
		return sanitized
	var rng := RandomNumberGenerator.new()
	rng.seed = AdventureMapGenerator.derive_seed(run_state.run_seed, "wilderness_merchant", room.room_id.hash() + run_state.floor_index * 1000)
	var stock: Array[Dictionary] = []
	var consumables: Array[ConsumableData] = _consumable_pool.duplicate()
	_shuffle(consumables, rng)
	if not consumables.is_empty():
		for index in range(3):
			var consumable: ConsumableData = consumables[index % consumables.size()]
			stock.append(_stock_entry("consumable", consumable.resource_path, consumable.item_name, 12))
	for equipment in _pick_shop_equipment(run_state, rng, 2):
		stock.append(_stock_entry("equipment", equipment.resource_path, equipment.item_name, _equipment_price(equipment.rarity)))
	stock.append(_stock_entry("camp_supply", "", "扎营物资", 15))
	room.runtime_data["shop_stock"] = stock.duplicate(true)
	return stock


func create_card_stack(card_path: String, stack_id: String, card_class: int = -1) -> CardStack:
	var card := load(card_path) as CardData
	if card == null or not card.can_appear_in_rewards():
		return null
	if card_class >= 0 and not card.is_available_to_class(card_class):
		return null
	var stack := CardStack.new()
	stack.card_data = card
	stack.count = 1
	stack.stack_id = stack_id
	return stack


func create_item_stack(item_path: String, stack_id: String) -> InventoryStack:
	var item := load(item_path) as ItemData
	if item == null:
		return null
	var stack := InventoryStack.new()
	stack.item_data = item
	stack.count = 1
	stack.stack_id = stack_id
	return stack


func get_random_consumable(run_seed: int, salt: int) -> ConsumableData:
	_ensure_catalog()
	if _consumable_pool.is_empty():
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = AdventureMapGenerator.derive_seed(run_seed, "consumable", salt)
	return _consumable_pool[rng.randi_range(0, _consumable_pool.size() - 1)]


func get_random_card(card_class: int, rarity: int, run_seed: int, salt: int) -> CardData:
	_ensure_catalog()
	var candidates: Array[CardData] = []
	for card in _card_pool:
		if card.can_appear_in_rewards() and card.rarity == rarity and card.is_available_to_class(card_class):
			candidates.append(card)
	if candidates.is_empty():
		candidates = _cards_for_class(card_class)
	if candidates.is_empty():
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = AdventureMapGenerator.derive_seed(run_seed, "event_card", salt)
	return candidates[rng.randi_range(0, candidates.size() - 1)]


func get_consumable_candidates(run_seed: int, salt: int, count: int = 3) -> Array[Dictionary]:
	_ensure_catalog()
	var candidates: Array[ConsumableData] = _consumable_pool.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = AdventureMapGenerator.derive_seed(run_seed, "event_consumables", salt)
	_shuffle(candidates, rng)
	var result: Array[Dictionary] = []
	for index in range(mini(maxi(0, count), candidates.size())):
		var item: ConsumableData = candidates[index]
		result.append({"id": "consumable_%02d" % index, "path": item.resource_path, "name": item.item_name, "description": RulesTextFormatter.format_item(item)})
	return result


func get_card_candidates(card_class: int, rarity: int, run_seed: int, salt: int, count: int = 3) -> Array[Dictionary]:
	_ensure_catalog()
	var candidates: Array[CardData] = []
	for card in _card_pool:
		if card.can_appear_in_rewards() and card.rarity == rarity and card.is_available_to_class(card_class):
			candidates.append(card)
	if candidates.is_empty():
		candidates = _cards_for_class(card_class)
	var rng := RandomNumberGenerator.new()
	rng.seed = AdventureMapGenerator.derive_seed(run_seed, "event_cards", salt)
	_shuffle(candidates, rng)
	var result: Array[Dictionary] = []
	for index in range(mini(maxi(0, count), candidates.size())):
		var card: CardData = candidates[index]
		result.append({
			"id": "card_%02d" % index,
			"path": card.resource_path,
			"name": card.card_name,
			"description": RulesTextFormatter.format_card(card),
			"ap": card.ap_cost,
			"rarity": card.rarity,
		})
	return result


func get_equipment_candidates(run_state: PartyRunState, salt: int, count: int = 3, floor_override: int = -1) -> Array[Dictionary]:
	_ensure_catalog()
	var rng := RandomNumberGenerator.new()
	rng.seed = AdventureMapGenerator.derive_seed(run_state.run_seed, "event_equipment", salt)
	return _equipment_candidates(
		run_state,
		rng,
		count,
		floor_override,
		"event:%d:%d" % [salt, floor_override]
	)


func _add_normal_card_candidates(reward: Dictionary, party: Array[CharacterState], tier: int, rng: RandomNumberGenerator) -> void:
	for hero in party:
		_add_card_candidate(reward, hero, _roll_normal_rarity(tier, rng), rng)
	var bonus_heroes := party.duplicate()
	_shuffle(bonus_heroes, rng)
	for index in range(mini(2, bonus_heroes.size())):
		_add_card_candidate(reward, bonus_heroes[index], _roll_normal_rarity(tier, rng), rng)


func _add_elite_card_candidates(reward: Dictionary, party: Array[CharacterState], rng: RandomNumberGenerator, per_hero: int) -> void:
	for hero in party:
		for _index in range(per_hero):
			_add_card_candidate(reward, hero, CardEnums.Rarity.EPIC if rng.randf() < 0.25 else CardEnums.Rarity.RARE, rng)
	if per_hero == 1:
		var bonus_heroes := party.duplicate()
		_shuffle(bonus_heroes, rng)
		for index in range(mini(2, bonus_heroes.size())):
			_add_card_candidate(reward, bonus_heroes[index], CardEnums.Rarity.EPIC if rng.randf() < 0.25 else CardEnums.Rarity.RARE, rng)


func _add_card_candidate(reward: Dictionary, hero: CharacterState, rarity: int, rng: RandomNumberGenerator) -> void:
	if hero == null or hero.character_data == null:
		return
	var candidates: Array[CardData] = []
	for card in _card_pool:
		if card.can_appear_in_rewards() and card.rarity == rarity and card.is_available_to_class(hero.character_data.character_class):
			candidates.append(card)
	if candidates.is_empty():
		candidates = _cards_for_class(hero.character_data.character_class)
	if candidates.is_empty():
		return
	var card := candidates[rng.randi_range(0, candidates.size() - 1)]
	var cards := reward["cards"] as Array
	cards.append({
		"id": "card_%03d" % cards.size(),
		"hero_id": hero.adventure_character_id,
		"path": card.resource_path,
		"name": card.card_name,
		"rarity": card.rarity,
	})


func _equipment_candidates(
	run_state: PartyRunState,
	rng: RandomNumberGenerator,
	count: int,
	floor_override: int = -1,
	source_id: String = ""
) -> Array[Dictionary]:
	var resolved_source := source_id if not source_id.is_empty() else "anonymous:%d" % rng.seed
	if run_state.equipment_reward_offers.has(resolved_source):
		var cached = run_state.equipment_reward_offers.get(resolved_source, [])
		return _equipment_candidate_entries(cached as Array, resolved_source) if cached is Array else []
	var equipment := _pick_reward_equipment(run_state, rng, count, floor_override)
	var offer_records: Array[Dictionary] = []
	for entry in equipment:
		var item := entry.get("equipment") as EquipmentData
		if item == null:
			continue
		offer_records.append({
			"path": item.resource_path,
			"reward_class": int(entry.get("reward_class", CardEnums.CardClass.NEUTRAL)),
		})
	run_state.equipment_reward_offers[resolved_source] = offer_records.duplicate(true)
	return _equipment_candidate_entries(offer_records, resolved_source)


func _equipment_candidate_entries(offer_records: Array, source_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record_value in offer_records:
		if not (record_value is Dictionary):
			continue
		var record := record_value as Dictionary
		var equipment := load(str(record.get("path", ""))) as EquipmentData
		if equipment == null:
			continue
		var index := result.size()
		result.append({
			"id": "equipment_%s_%03d" % [abs(source_id.hash()), index],
			"path": equipment.resource_path,
			"name": equipment.item_name,
			"rarity": equipment.rarity,
			"reward_class": int(record.get("reward_class", CardEnums.CardClass.NEUTRAL)),
		})
	return result


func _pick_reward_equipment(
	run_state: PartyRunState,
	rng: RandomNumberGenerator,
	count: int,
	floor_override: int = -1
) -> Array[Dictionary]:
	var floor_index := run_state.floor_index if floor_override < 0 else floor_override
	var target_rarity := CardEnums.Rarity.RARE if floor_index <= 0 else CardEnums.Rarity.EPIC
	var party_classes := _get_party_classes(run_state)
	var class_buckets: Dictionary = {}
	for card_class in party_classes:
		class_buckets[int(card_class)] = []
	for equipment in _equipment_pool:
		if equipment.rarity != target_rarity \
				or run_state.equipment_reward_drawn_paths.has(equipment.resource_path):
			continue
		for card_class in party_classes:
			if equipment.is_available_to_class(int(card_class)):
				(class_buckets[int(card_class)] as Array).append(equipment)

	var eligible_classes: Array[int] = []
	for card_class in party_classes:
		if not (class_buckets[int(card_class)] as Array).is_empty():
			eligible_classes.append(int(card_class))
	var appeared: Dictionary = {}
	var selected_paths: Dictionary = {}
	var result: Array[Dictionary] = []
	for _index in range(maxi(0, count)):
		var available_classes: Array[int] = []
		for card_class in eligible_classes:
			if _bucket_has_unselected(class_buckets[card_class] as Array, selected_paths):
				available_classes.append(card_class)
		if available_classes.is_empty():
			break
		var selected_class := _pick_weighted_equipment_class(
			available_classes, run_state.equipment_class_miss_streaks, rng
		)
		var available_items: Array[EquipmentData] = []
		for item in class_buckets[selected_class] as Array:
			if item is EquipmentData and not selected_paths.has((item as EquipmentData).resource_path):
				available_items.append(item as EquipmentData)
		if available_items.is_empty():
			continue
		var selected := available_items[rng.randi_range(0, available_items.size() - 1)]
		selected_paths[selected.resource_path] = true
		appeared[selected_class] = true
		result.append({"equipment": selected, "reward_class": selected_class})

	for card_class in eligible_classes:
		var key := str(card_class)
		if appeared.has(card_class):
			run_state.equipment_class_miss_streaks[key] = 0
		else:
			run_state.equipment_class_miss_streaks[key] = int(
				run_state.equipment_class_miss_streaks.get(key, 0)
			) + 1
	return result


func _pick_shop_equipment(
	run_state: PartyRunState,
	rng: RandomNumberGenerator,
	count: int,
	floor_override: int = -1
) -> Array[EquipmentData]:
	var floor_index := run_state.floor_index if floor_override < 0 else floor_override
	var target_rarity := CardEnums.Rarity.RARE if floor_index <= 0 else CardEnums.Rarity.EPIC
	var candidates: Array[EquipmentData] = []
	for equipment in _equipment_pool:
		if equipment.rarity != target_rarity:
			continue
		for card_class in _get_party_classes(run_state):
			if equipment.is_available_to_class(int(card_class)):
				candidates.append(equipment)
				break
	_shuffle(candidates, rng)
	return candidates.slice(0, mini(maxi(0, count), candidates.size())) as Array[EquipmentData]


func _get_party_classes(run_state: PartyRunState) -> Array[int]:
	var result: Array[int] = []
	for hero in run_state.party:
		if hero == null or hero.character_data == null:
			continue
		var card_class := hero.character_data.character_class
		if not result.has(card_class):
			result.append(card_class)
	return result


func _bucket_has_unselected(bucket: Array, selected_paths: Dictionary) -> bool:
	for value in bucket:
		if value is EquipmentData and not selected_paths.has((value as EquipmentData).resource_path):
			return true
	return false


func _pick_weighted_equipment_class(
	classes: Array[int],
	miss_streaks: Dictionary,
	rng: RandomNumberGenerator
) -> int:
	var total_weight := 0.0
	for card_class in classes:
		total_weight += 1.0 + float(maxi(0, int(miss_streaks.get(str(card_class), 0))))
	var roll := rng.randf() * total_weight
	for card_class in classes:
		roll -= 1.0 + float(maxi(0, int(miss_streaks.get(str(card_class), 0))))
		if roll <= 0.0:
			return card_class
	return classes.back()


func _cards_for_class(card_class: int) -> Array[CardData]:
	var result: Array[CardData] = []
	for card in _card_pool:
		if card.can_appear_in_rewards() and card.is_available_to_class(card_class):
			result.append(card)
	return result


func _roll_normal_rarity(tier: int, rng: RandomNumberGenerator) -> int:
	var roll := rng.randf()
	match tier:
		AdventureEnums.EncounterTier.MIXED:
			return CardEnums.Rarity.COMMON if roll < 0.60 else (CardEnums.Rarity.RARE if roll < 0.95 else CardEnums.Rarity.EPIC)
		AdventureEnums.EncounterTier.STRONG:
			return CardEnums.Rarity.COMMON if roll < 0.40 else (CardEnums.Rarity.RARE if roll < 0.90 else CardEnums.Rarity.EPIC)
		_:
			return CardEnums.Rarity.COMMON if roll < 0.80 else CardEnums.Rarity.RARE


func _stock_entry(kind: String, path: String, name: String, price: int, hero_id: String = "") -> Dictionary:
	return {"kind": kind, "path": path, "name": name, "price": price, "hero_id": hero_id, "sold": false}


func _sanitize_shop_stock(stock: Array) -> Array[Dictionary]:
	var sanitized: Array[Dictionary] = []
	for entry_data in stock:
		if not (entry_data is Dictionary):
			continue
		var entry := entry_data as Dictionary
		if str(entry.get("kind", "")) == "card":
			var card := load(str(entry.get("path", ""))) as CardData
			if card == null or not card.can_appear_in_rewards():
				continue
		sanitized.append(entry.duplicate(true))
	return sanitized


func _card_price(rarity: int) -> int:
	match rarity:
		CardEnums.Rarity.RARE:
			return 30
		CardEnums.Rarity.EPIC:
			return 60
		_:
			return 15


func _equipment_price(rarity: int) -> int:
	match rarity:
		CardEnums.Rarity.RARE:
			return 70
		CardEnums.Rarity.EPIC:
			return 120
		_:
			return 35


func _ensure_catalog() -> void:
	if not _card_pool.is_empty() or not _equipment_pool.is_empty() or not _consumable_pool.is_empty():
		return
	for file_name in DirAccess.get_files_at("res://resources/cards"):
		if not file_name.ends_with(".tres") or file_name.ends_with("_stack.tres"):
			continue
		var resource := load("res://resources/cards/%s" % file_name)
		if resource is CardData:
			var card := resource as CardData
			if card.can_appear_in_rewards():
				_card_pool.append(card)
	for file_name in DirAccess.get_files_at("res://resources/items"):
		if not file_name.ends_with(".tres") or file_name.ends_with("_stack.tres"):
			continue
		var resource := load("res://resources/items/%s" % file_name)
		if resource is EquipmentData:
			var equipment := resource as EquipmentData
			if not equipment.has_tag("事件"):
				_equipment_pool.append(equipment)
		elif resource is ConsumableData:
			_consumable_pool.append(resource as ConsumableData)


func _shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var other_index := rng.randi_range(0, index)
		var temporary = values[index]
		values[index] = values[other_index]
		values[other_index] = temporary
