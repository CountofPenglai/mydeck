extends RefCounted
class_name AdventureSaveSchema

const SLOT_NAME := "adventure_hex_run"
const LEGACY_SLOT_NAME := "adventure_run"
const VERSION := 7

enum LoadStatus {
	NONE,
	LOADED_PRIMARY,
	RESTORED_BACKUP,
	LEGACY_SAVE_DETECTED,
	UNSUPPORTED_SCHEMA,
	CORRUPT_SAVE,
}

enum PayloadStatus {
	CURRENT,
	UNSUPPORTED,
	CORRUPT,
}


static func get_payload_status(payload: Dictionary) -> PayloadStatus:
	var raw_version = payload.get("version", null)
	if not (raw_version is int or raw_version is float):
		return PayloadStatus.CORRUPT
	if int(raw_version) != raw_version:
		return PayloadStatus.CORRUPT
	if int(raw_version) != VERSION:
		return PayloadStatus.UNSUPPORTED
	for key in ["adventure_flags", "equipment_reward_offers", "equipment_class_miss_streaks"]:
		if not (payload.get(key, null) is Dictionary):
			return PayloadStatus.CORRUPT
	for key in ["party", "equipment_reward_drawn_paths"]:
		if not (payload.get(key, null) is Array):
			return PayloadStatus.CORRUPT
	for key in ["shop_rng_seed", "shop_rng_state"]:
		if not _is_rng_string(payload.get(key, null)):
			return PayloadStatus.CORRUPT
	if not _is_valid_floor(payload.get("floor", null)) or not _is_valid_pending(payload.get("pending", null)):
		return PayloadStatus.CORRUPT
	return PayloadStatus.CURRENT


static func get_version_status(payload: Dictionary) -> PayloadStatus:
	var raw_version = payload.get("version", null)
	if not (raw_version is int or raw_version is float):
		return PayloadStatus.CORRUPT
	if int(raw_version) != raw_version:
		return PayloadStatus.CORRUPT
	return PayloadStatus.CURRENT if int(raw_version) == VERSION else PayloadStatus.UNSUPPORTED


static func _is_rng_string(value: Variant) -> bool:
	return value is String and not (value as String).is_empty() and (value as String).is_valid_int()


static func _is_valid_floor(value: Variant) -> bool:
	if not (value is Dictionary):
		return false
	var floor := value as Dictionary
	for key in ["floor_index", "floor_seed", "grid_size", "rooms", "current_room_id", "danger", "triggered_thresholds", "normal_battle_victories"]:
		if not floor.has(key):
			return false
	if not _is_integer(floor["floor_index"]) or not _is_integer(floor["floor_seed"]) or not _is_integer(floor["danger"]):
		return false
	if not _is_integer(floor["normal_battle_victories"]):
		return false
	if not (floor["grid_size"] is Array) or (floor["grid_size"] as Array).size() != 2:
		return false
	for coordinate in floor["grid_size"] as Array:
		if not _is_integer(coordinate):
			return false
	if not (floor["triggered_thresholds"] is Array) or not (floor["rooms"] is Array) or (floor["rooms"] as Array).is_empty():
		return false
	if not (floor["current_room_id"] is String) or (floor["current_room_id"] as String).is_empty():
		return false
	var room_ids := {}
	var cells := {}
	for room_value in floor["rooms"] as Array:
		if not _is_valid_room(room_value, room_ids, cells):
			return false
	return room_ids.has(floor["current_room_id"])


static func _is_valid_room(value: Variant, room_ids: Dictionary, cells: Dictionary) -> bool:
	if not (value is Dictionary):
		return false
	var room := value as Dictionary
	for key in ["id", "cell", "back_type", "type", "content_id", "visited", "completed", "content_revealed", "high_value", "high_value_marked", "danger_variant_id", "shop_stock", "shop_initialized", "shop_restock_count", "camp_visit_closed", "shelter_type", "rest_used", "local_event_resolved", "runtime_data"]:
		if not room.has(key):
			return false
	if not (room["id"] is String) or (room["id"] as String).is_empty() or room_ids.has(room["id"]):
		return false
	if not (room["cell"] is Array) or (room["cell"] as Array).size() != 2:
		return false
	var cell_values := room["cell"] as Array
	if not _is_integer(cell_values[0]) or not _is_integer(cell_values[1]):
		return false
	var cell_id := "%d,%d" % [int(cell_values[0]), int(cell_values[1])]
	if cells.has(cell_id):
		return false
	if not _is_integer(room["back_type"]) or not _is_integer(room["type"]) or not _is_integer(room["shop_restock_count"]) or not _is_integer(room["shelter_type"]):
		return false
	if not (room["content_id"] is String) or (room["content_id"] as String).is_empty() or not (room["danger_variant_id"] is String):
		return false
	for key in ["visited", "completed", "content_revealed", "high_value", "high_value_marked", "shop_initialized", "camp_visit_closed", "rest_used", "local_event_resolved"]:
		if not (room[key] is bool):
			return false
	if not (room["shop_stock"] is Array) or not (room["runtime_data"] is Dictionary):
		return false
	if bool(room["shop_initialized"]) and (room["shop_stock"] as Array).is_empty():
		return false
	for stock_value in room["shop_stock"] as Array:
		if not _is_valid_shop_stock_entry(stock_value):
			return false
	room_ids[room["id"]] = true
	cells[cell_id] = true
	return true


static func _is_valid_shop_stock_entry(value: Variant) -> bool:
	if not (value is Dictionary):
		return false
	var entry := value as Dictionary
	for key in ["kind", "path", "name", "price", "hero_id", "sold"]:
		if not entry.has(key):
			return false
	if str(entry["kind"]) not in ["card", "equipment", "consumable", "camp_supply"]:
		return false
	return entry["kind"] is String and entry["path"] is String and entry["name"] is String \
		and _is_integer(entry["price"]) and int(entry["price"]) >= 0 \
		and entry["hero_id"] is String and entry["sold"] is bool


static func _is_valid_pending(value: Variant) -> bool:
	if not (value is Dictionary):
		return false
	var pending := value as Dictionary
	for key in ["type", "id", "payload", "committed"]:
		if not pending.has(key):
			return false
	if not _is_integer(pending["type"]) or not (pending["id"] is String) \
			or not (pending["payload"] is Dictionary) or not (pending["committed"] is bool):
		return false
	if bool(pending["committed"]):
		return true
	var payload := pending["payload"] as Dictionary
	var transaction_type := int(pending["type"])
	var operation_id := str(pending["id"])
	if transaction_type == AdventureEnums.TransactionType.MOVE:
		return _is_valid_map_operation_payload(payload, operation_id, true)
	if transaction_type == AdventureEnums.TransactionType.SHOP:
		var result: Variant = payload.get("result", null)
		return _is_valid_map_operation_payload(payload, operation_id, false) \
			and _is_rng_string(payload.get("rng_after", null)) \
			and result is Dictionary and _is_valid_shop_stock_entry((result as Dictionary).get("item", null))
	return true


static func _is_valid_map_operation_payload(payload: Dictionary, operation_id: String, is_move: bool) -> bool:
	var floor_after = payload.get("floor_after", null)
	var result = payload.get("result", null)
	if not (floor_after is Dictionary) or not _is_valid_floor(floor_after as Dictionary) \
			or not (result is Dictionary):
		return false
	var result_data := result as Dictionary
	if not (result_data.get("ok", null) is bool) or not bool(result_data["ok"]) \
			or not (result_data.get("operation_id", null) is String) \
			or str(result_data["operation_id"]).is_empty() \
			or str(result_data["operation_id"]) != operation_id \
			or not _is_integer(result_data.get("danger", null)) or int(result_data["danger"]) < 0:
		return false
	if not is_move:
		return true
	return result_data.get("target_id", null) is String and not str(result_data["target_id"]).is_empty() \
		and str(result_data["target_id"]) == str((floor_after as Dictionary)["current_room_id"])


static func _is_integer(value: Variant) -> bool:
	return (value is int or value is float) and int(value) == value
