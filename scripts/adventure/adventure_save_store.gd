extends RefCounted
class_name AdventureSaveStore

var save_path: String
var temp_path: String
var backup_path: String


func _init(slot_name: String = "adventure_run") -> void:
	var safe_slot := slot_name.validate_filename()
	save_path = "user://%s.json" % safe_slot
	temp_path = "user://%s.tmp" % safe_slot
	backup_path = "user://%s.backup.json" % safe_slot


func save_run(run_state: PartyRunState) -> Error:
	if run_state == null:
		return ERR_INVALID_PARAMETER
	var payload := _serialize_run(run_state)
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(payload, "\t"))
	file.flush()
	file.close()
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(backup_path)
	if FileAccess.file_exists(save_path):
		var backup_error := DirAccess.rename_absolute(save_path, backup_path)
		if backup_error != OK:
			return backup_error
	var commit_error := DirAccess.rename_absolute(temp_path, save_path)
	if commit_error != OK and FileAccess.file_exists(backup_path):
		DirAccess.rename_absolute(backup_path, save_path)
	return commit_error


func load_run() -> PartyRunState:
	var result := _load_path(save_path)
	if result == null:
		result = _load_path(backup_path)
	return result


func has_save() -> bool:
	return FileAccess.file_exists(save_path) or FileAccess.file_exists(backup_path)


func delete_save() -> void:
	for path in [save_path, temp_path, backup_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _load_path(path: String) -> PartyRunState:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return null
	return _deserialize_run(parsed as Dictionary)


func _serialize_run(run_state: PartyRunState) -> Dictionary:
	var party_data: Array[Dictionary] = []
	for hero in run_state.party:
		if hero != null:
			party_data.append(_serialize_character(hero))
	return {
		"version": PartyRunState.SAVE_VERSION,
		"run_seed": run_state.run_seed,
		"floor_index": run_state.floor_index,
		"floor_count": run_state.floor_count,
		"gold": run_state.gold,
		"provisions": run_state.provisions,
		"camp_points": run_state.camp_points,
		"camp_supplies": run_state.camp_supplies,
		"ritual_points": run_state.ritual_points,
		"card_removals_used": run_state.card_removals_used,
		"enemy_health_percent": run_state.enemy_health_percent,
		"run_complete": run_state.run_complete,
		"run_failed": run_state.run_failed,
		"adventure_flags": run_state.adventure_flags.duplicate(true),
		"equipment_reward_drawn_paths": Array(run_state.equipment_reward_drawn_paths),
		"equipment_reward_offers": run_state.equipment_reward_offers.duplicate(true),
		"equipment_class_miss_streaks": run_state.equipment_class_miss_streaks.duplicate(true),
		"party": party_data,
		"floor": run_state.floor_state.to_dict() if run_state.floor_state != null else {},
		"pending": run_state.pending_transaction.to_dict() if run_state.pending_transaction != null else {},
	}


func _deserialize_run(data: Dictionary) -> PartyRunState:
	var source_version := int(data.get("version", 0))
	if source_version < 3 or source_version > PartyRunState.SAVE_VERSION:
		return null
	var result := PartyRunState.new()
	result.save_version = PartyRunState.SAVE_VERSION
	result.run_seed = int(data.get("run_seed", 0))
	result.floor_index = int(data.get("floor_index", 0))
	result.floor_count = int(data.get("floor_count", 2))
	result.gold = int(data.get("gold", 40))
	result.provisions = int(data.get("provisions", 14))
	result.camp_points = int(data.get("camp_points", 0))
	result.camp_supplies = int(data.get("camp_supplies", 0))
	result.ritual_points = int(data.get("ritual_points", PartyRunState.STARTING_RITUAL_POINTS))
	result.card_removals_used = int(data.get("card_removals_used", 0))
	result.enemy_health_percent = clampi(int(data.get("enemy_health_percent", 100)), 1, 1000)
	result.run_complete = bool(data.get("run_complete", false))
	result.run_failed = bool(data.get("run_failed", false))
	result.adventure_flags = (data.get("adventure_flags", {}) as Dictionary).duplicate(true)
	result.equipment_reward_drawn_paths = PackedStringArray(data.get("equipment_reward_drawn_paths", []))
	result.equipment_reward_offers = _deserialize_equipment_reward_offers(
		data.get("equipment_reward_offers", {}) as Dictionary
	)
	result.equipment_class_miss_streaks = _deserialize_equipment_class_misses(
		data.get("equipment_class_miss_streaks", {}) as Dictionary
	)
	for hero_data in data.get("party", []):
		if hero_data is Dictionary:
			var hero := _deserialize_character(hero_data)
			if hero != null:
				result.party.append(hero)
	var floor_data := data.get("floor", {}) as Dictionary
	if not floor_data.is_empty():
		result.floor_state = AdventureFloorState.from_dict(floor_data)
	var pending_data := data.get("pending", {}) as Dictionary
	result.pending_transaction = PendingAdventureTransaction.from_dict(pending_data)
	return result


func _deserialize_equipment_reward_offers(raw: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for source_value in raw:
		var source_id := str(source_value)
		var records: Array[Dictionary] = []
		var raw_records = raw[source_value]
		if raw_records is Array:
			for record_value in raw_records as Array:
				if not (record_value is Dictionary):
					continue
				var record := record_value as Dictionary
				records.append({
					"path": str(record.get("path", "")),
					"reward_class": int(record.get("reward_class", CardEnums.CardClass.NEUTRAL)),
				})
		result[source_id] = records
	return result


func _deserialize_equipment_class_misses(raw: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key_value in raw:
		result[str(key_value)] = maxi(0, int(raw[key_value]))
	return result


func _serialize_character(hero: CharacterState) -> Dictionary:
	var deck_data: Array[Dictionary] = []
	for stack in hero.deck:
		if stack != null and stack.card_data != null:
			deck_data.append({
				"card": stack.card_data.resource_path,
				"count": stack.count,
				"id": stack.stack_id,
			})
	var inventory_data: Array[Dictionary] = []
	for stack in hero.inventory:
		if stack != null and stack.item_data != null:
			inventory_data.append({
				"item": stack.item_data.resource_path,
				"count": stack.count,
				"id": stack.stack_id,
			})
	var curse_data: Array[Dictionary] = []
	for curse in hero.curse_instances:
		if curse != null and curse.definition != null:
			curse_data.append({
				"definition": curse.definition.resource_path,
				"state": curse.state,
				"depth": curse.depth,
				"maturity": curse.maturity,
				"sealed": curse.sealed,
				"persistent_data": curse.persistent_data.duplicate(true),
			})
	var pool_values := {}
	for pool in hero.class_resources:
		if pool != null:
			pool_values[pool.get_resource_name()] = pool.current_value
	return {
		"source": hero.adventure_source_path,
		"id": hero.adventure_character_id,
		"health": hero.current_health,
		"level": hero.level,
		"weapon": _resource_path(hero.weapon_equipment),
		"weapon_face": hero.weapon_face,
		"armor": _resource_path(hero.armor_equipment),
		"accessory_1": _resource_path(hero.accessory_equipment_1),
		"accessory_2": _resource_path(hero.accessory_equipment_2),
		"equipment_ids": hero.equipment_instance_ids.duplicate(true),
		"equipment_modifiers": hero.equipment_adventure_modifiers.duplicate(true),
		"card_modifiers": hero.card_adventure_modifiers.duplicate(true),
		"deck": deck_data,
		"inventory": inventory_data,
		"class_resources": pool_values,
		"ranger_elements": hero.ranger_element_inventory.duplicate(true),
		"extra_ap_bonus": hero.extra_ap_bonus,
		"curses": curse_data,
		"base_curse_load_limit": hero.base_curse_load_limit,
		"curse_load_limit_bonus": hero.curse_load_limit_bonus,
		"sealed_curse_id": hero.sealed_curse_id,
		"distortion_progress": hero.distortion_progress,
		"selected_distortion_fields": Array(hero.selected_distortion_fields),
		"claimed_distortion_milestones": Array(hero.claimed_distortion_milestones),
		"distortion_grace_count": hero.distortion_grace_count,
		"strength_bonus": hero.strength_bonus,
		"agility_bonus": hero.agility_bonus,
		"intelligence_bonus": hero.intelligence_bonus,
		"persistent_max_health_modifier": hero.persistent_max_health_modifier,
		"adventure_damage_bonus": hero.adventure_damage_bonus,
	}


func _deserialize_character(data: Dictionary) -> CharacterState:
	var source_path := str(data.get("source", ""))
	var template := load(source_path) as CharacterState if not source_path.is_empty() else null
	if template == null:
		return null
	var hero := template.duplicate(true) as CharacterState
	hero.adventure_source_path = source_path
	hero.adventure_character_id = str(data.get("id", ""))
	hero.level = int(data.get("level", 1))
	hero.weapon_equipment = _load_equipment(str(data.get("weapon", "")))
	hero.weapon_face = int(data.get("weapon_face", 0))
	hero.armor_equipment = _load_equipment(str(data.get("armor", "")))
	hero.accessory_equipment_1 = _load_equipment(str(data.get("accessory_1", "")))
	hero.accessory_equipment_2 = _load_equipment(str(data.get("accessory_2", "")))
	hero.equipment_instance_ids = (data.get("equipment_ids", {}) as Dictionary).duplicate(true)
	hero.equipment_adventure_modifiers = (data.get("equipment_modifiers", {}) as Dictionary).duplicate(true)
	hero.card_adventure_modifiers = (data.get("card_modifiers", {}) as Dictionary).duplicate(true)
	hero.deck.clear()
	for stack_data in data.get("deck", []):
		if not (stack_data is Dictionary):
			continue
		var card_path := str(stack_data.get("card", ""))
		if card_path.is_empty() or not ResourceLoader.exists(card_path):
			continue
		var card := load(card_path) as CardData
		if card == null:
			continue
		var stack := CardStack.new()
		stack.card_data = card
		stack.count = int(stack_data.get("count", 1))
		stack.stack_id = str(stack_data.get("id", ""))
		hero.deck.append(stack)
	hero.inventory.clear()
	for stack_data in data.get("inventory", []):
		if not (stack_data is Dictionary):
			continue
		var item := load(str(stack_data.get("item", ""))) as ItemData
		if item == null:
			continue
		var stack := InventoryStack.new()
		stack.item_data = item
		stack.count = int(stack_data.get("count", 1))
		stack.stack_id = str(stack_data.get("id", ""))
		hero.inventory.append(stack)
	hero.curse_instances.clear()
	for curse_data in data.get("curses", []):
		if not (curse_data is Dictionary):
			continue
		var definition := load(str(curse_data.get("definition", ""))) as CurseDefinition
		if definition == null:
			continue
		var curse := CurseInstance.new()
		curse.definition = definition
		curse.state = int(curse_data.get("state", CurseInstance.State.INDUSTRY))
		curse.depth = int(curse_data.get("depth", 1))
		curse.maturity = int(curse_data.get("maturity", 0))
		curse.sealed = bool(curse_data.get("sealed", false))
		curse.persistent_data = (curse_data.get("persistent_data", {}) as Dictionary).duplicate(true)
		hero.curse_instances.append(curse)
	hero.ranger_element_inventory = _integer_key_dictionary(data.get("ranger_elements", {}) as Dictionary)
	hero.extra_ap_bonus = int(data.get("extra_ap_bonus", 0))
	hero.base_curse_load_limit = int(data.get("base_curse_load_limit", 3))
	hero.curse_load_limit_bonus = int(data.get("curse_load_limit_bonus", 0))
	hero.sealed_curse_id = str(data.get("sealed_curse_id", ""))
	hero.distortion_progress = int(data.get("distortion_progress", 0))
	hero.selected_distortion_fields = PackedStringArray(data.get("selected_distortion_fields", []))
	hero.claimed_distortion_milestones = PackedInt32Array(data.get("claimed_distortion_milestones", []))
	hero.distortion_grace_count = int(data.get("distortion_grace_count", 0))
	hero.strength_bonus = int(data.get("strength_bonus", hero.strength_bonus))
	hero.agility_bonus = int(data.get("agility_bonus", hero.agility_bonus))
	hero.intelligence_bonus = int(data.get("intelligence_bonus", hero.intelligence_bonus))
	hero.persistent_max_health_modifier = int(data.get("persistent_max_health_modifier", 0))
	hero.adventure_damage_bonus = int(data.get("adventure_damage_bonus", 0))
	hero.ensure_initialized()
	var pool_values := data.get("class_resources", {}) as Dictionary
	for pool in hero.class_resources:
		if pool != null and pool_values.has(pool.get_resource_name()):
			pool.current_value = clampi(int(pool_values[pool.get_resource_name()]), 0, pool.get_max_value())
	hero.current_health = clampi(int(data.get("health", hero.get_max_health())), 0, hero.get_max_health())
	hero.ensure_adventure_instance_ids()
	return hero


func _load_equipment(path: String) -> EquipmentData:
	return load(path) as EquipmentData if not path.is_empty() else null


func _resource_path(resource: Resource) -> String:
	return resource.resource_path if resource != null else ""


func _integer_key_dictionary(source: Dictionary) -> Dictionary:
	var result := {}
	for key in source:
		result[int(key)] = int(source[key])
	return result
