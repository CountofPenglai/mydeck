extends Node

const DIAGNOSTIC_SLOT := "adventure_hex_save_check_current"
const LEGACY_DIAGNOSTIC_SLOT := "adventure_hex_save_check_legacy"
const LARGE_RNG_VALUE := "9223372036854775806"

var failures := 0


func _ready() -> void:
	_check_default_slot_and_legacy_isolation()
	_check_unsupported_schema_is_rejected()
	_check_unknown_backup_is_not_overwritten()
	_check_only_backup_is_preserved_when_saving()
	_check_numeric_rng_fields_are_rejected()
	_check_current_schema_round_trip_preserves_rng_strings()
	_check_missing_primary_restores_compatible_backup()
	_check_unreadable_primary_restores_compatible_backup()
	_check_corrupt_current_primary_restores_compatible_backup()
	_check_invalid_initialized_shop_stock_restores_compatible_backup()
	_check_invalid_pending_move_or_shop_restores_compatible_backup()
	_check_recovered_backup_is_preserved_when_saving()
	print("HEX_SAVE: %s" % ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)


func _check_default_slot_and_legacy_isolation() -> void:
	var default_store := AdventureSaveStore.new()
	_check(default_store.save_path == "user://adventure_hex_run.json", "new save slot must be adventure_hex_run")
	var legacy_store := AdventureSaveStore.new(LEGACY_DIAGNOSTIC_SLOT)
	legacy_store.delete_save()
	_write_text(legacy_store.save_path, '{"version":6,"legacy":"primary"}')
	_write_text(legacy_store.backup_path, '{"version":6,"legacy":"backup"}')
	var primary_before := _read_text(legacy_store.save_path)
	var backup_before := _read_text(legacy_store.backup_path)
	var store := AdventureSaveStore.new(DIAGNOSTIC_SLOT, LEGACY_DIAGNOSTIC_SLOT)
	store.delete_save()
	var loaded := store.load_run()
	_check(loaded == null, "legacy slot must not deserialize into the new run")
	_check(store.legacy_save_detected, "legacy save availability must be exposed")
	_check(store.load_status == AdventureSaveSchema.LoadStatus.LEGACY_SAVE_DETECTED, "legacy-only load must report legacy detection")
	_check(_read_text(legacy_store.save_path) == primary_before, "legacy primary bytes must remain untouched")
	_check(_read_text(legacy_store.backup_path) == backup_before, "legacy backup bytes must remain untouched")
	store.delete_save()
	legacy_store.delete_save()


func _check_unsupported_schema_is_rejected() -> void:
	var store := AdventureSaveStore.new(DIAGNOSTIC_SLOT, LEGACY_DIAGNOSTIC_SLOT)
	store.delete_save()
	for version in [AdventureSaveSchema.VERSION - 1, AdventureSaveSchema.VERSION + 1]:
		var unknown_payload := JSON.stringify({"version": version, "floor": "must-not-deserialize"})
		_write_text(store.save_path, unknown_payload)
		_check(store.load_run() == null, "unsupported schema %d must not load" % version)
		_check(store.load_status == AdventureSaveSchema.LoadStatus.UNSUPPORTED_SCHEMA, "unsupported schema must be reported")
		_check(store.save_run(PartyRunState.new()) == ERR_FILE_UNRECOGNIZED, "unsupported schema must not be overwritten")
		_check(_read_text(store.save_path) == unknown_payload, "unsupported schema bytes must remain untouched")
		store.delete_save()


func _check_current_schema_round_trip_preserves_rng_strings() -> void:
	var store := AdventureSaveStore.new(DIAGNOSTIC_SLOT, LEGACY_DIAGNOSTIC_SLOT)
	store.delete_save()
	var run := _make_complete_run(1234)
	run.shop_rng_seed = LARGE_RNG_VALUE
	run.shop_rng_state = LARGE_RNG_VALUE
	var serialized := store._serialize_run(run)
	_check(AdventureSaveSchema._is_valid_floor(serialized.get("floor", null)), "complete round-trip fixture must satisfy floor structure")
	_check(AdventureSaveSchema._is_valid_pending(serialized.get("pending", null)), "complete round-trip fixture must satisfy pending structure")
	_check(AdventureSaveSchema.get_payload_status(serialized) == AdventureSaveSchema.PayloadStatus.CURRENT, "complete round-trip fixture must satisfy current schema")
	_check(store.save_run(run) == OK, "complete current-schema save must succeed")
	var loaded := store.load_run()
	_check(loaded != null, "complete current-schema save must load")
	if loaded != null:
		_check(loaded.shop_rng_seed == LARGE_RNG_VALUE and loaded.shop_rng_state == LARGE_RNG_VALUE, "shop RNG strings must survive exactly")
		_check(loaded.floor_state != null and loaded.floor_state.danger == 12, "floor danger must survive the round trip")
		var room := loaded.floor_state.get_room("runtime_shop") if loaded.floor_state != null else null
		_check(room != null and room.shop_initialized and room.shop_restock_count == 1, "room shop state must survive the round trip")
		_check(room != null and room.runtime_data.get("marker", "") == "runtime", "room runtime data must survive the round trip")
		_check(loaded.pending_transaction != null and not loaded.pending_transaction.committed and loaded.pending_transaction.transaction_id == "shop_pending", "pending transaction must survive the round trip")
		_check(loaded.adventure_flags.get("round_trip", "") == "kept", "run flags must survive the round trip")
	store.delete_save()


func _check_unknown_backup_is_not_overwritten() -> void:
	var store := AdventureSaveStore.new(DIAGNOSTIC_SLOT, LEGACY_DIAGNOSTIC_SLOT)
	for version in [AdventureSaveSchema.VERSION - 1, AdventureSaveSchema.VERSION + 1]:
		store.delete_save()
		var unknown_backup := JSON.stringify({"version": version, "floor": "unknown-backup"})
		_write_text(store.backup_path, unknown_backup)
		_check(store.save_run(PartyRunState.new()) == ERR_FILE_UNRECOGNIZED, "unknown backup schema must not be overwritten")
		_check(store.load_status == AdventureSaveSchema.LoadStatus.UNSUPPORTED_SCHEMA, "unknown backup schema must be reported")
		_check(_read_text(store.backup_path) == unknown_backup, "unknown backup bytes must remain untouched")
		store.delete_save()


func _check_only_backup_is_preserved_when_saving() -> void:
	var store := AdventureSaveStore.new(DIAGNOSTIC_SLOT, LEGACY_DIAGNOSTIC_SLOT)
	store.delete_save()
	var backup_run := _make_complete_run(3456)
	backup_run.gold = 71
	_write_text(store.backup_path, JSON.stringify(store._serialize_run(backup_run)))
	var backup_before := _read_text(store.backup_path)
	var replacement := _make_complete_run(4567)
	replacement.gold = 72
	_check(store.save_run(replacement) == OK, "saving beside a compatible backup must succeed")
	_check(_read_text(store.backup_path) == backup_before, "saving with only a backup must preserve backup bytes")
	var loaded := store.load_run()
	_check(loaded != null and loaded.gold == 72, "new primary must load after a backup-preserving save")
	store.delete_save()


func _check_numeric_rng_fields_are_rejected() -> void:
	var store := AdventureSaveStore.new(DIAGNOSTIC_SLOT, LEGACY_DIAGNOSTIC_SLOT)
	for rng_key in ["shop_rng_seed", "shop_rng_state"]:
		store.delete_save()
		var run := PartyRunState.new()
		run.initialize_adventure(4321, [], AdventureDefinition.new())
		var numeric_payload := store._serialize_run(run)
		numeric_payload[rng_key] = 9223372036854775806
		_write_text(store.save_path, JSON.stringify(numeric_payload))
		_check(store.load_run() == null, "%s must reject a numeric RNG value" % rng_key)
		_check(store.load_status == AdventureSaveSchema.LoadStatus.CORRUPT_SAVE, "%s must report corrupt schema data" % rng_key)
		store.delete_save()
	var run := _make_complete_run(1234)
	run.shop_rng_seed = LARGE_RNG_VALUE
	run.shop_rng_state = LARGE_RNG_VALUE
	_check(store.save_run(run) == OK, "current-schema save must succeed")
	var loaded := store.load_run()
	_check(loaded != null, "current-schema save must load")
	if loaded != null:
		_check(loaded.shop_rng_seed == LARGE_RNG_VALUE, "shop RNG seed must survive as an exact string")
		_check(loaded.shop_rng_state == LARGE_RNG_VALUE, "shop RNG state must survive as an exact string")
		_check(store.load_status == AdventureSaveSchema.LoadStatus.LOADED_PRIMARY, "primary load must report success")
	store.delete_save()


func _check_corrupt_current_primary_restores_compatible_backup() -> void:
	var store := AdventureSaveStore.new(DIAGNOSTIC_SLOT, LEGACY_DIAGNOSTIC_SLOT)
	for malformed_kind in ["wrong_floor_type", "empty_floor", "malformed_rooms", "invalid_current_room"]:
		store.delete_save()
		var backup_run := _make_complete_run(5678)
		backup_run.gold = 77
		_write_text(store.backup_path, JSON.stringify(store._serialize_run(backup_run)))
		var corrupt_run := _make_complete_run(5679)
		var corrupt_payload := store._serialize_run(corrupt_run)
		match malformed_kind:
			"wrong_floor_type":
				corrupt_payload["floor"] = "corrupt"
			"empty_floor":
				corrupt_payload["floor"] = {}
			"malformed_rooms":
				(corrupt_payload["floor"] as Dictionary)["rooms"] = "not-an-array"
			"invalid_current_room":
				(corrupt_payload["floor"] as Dictionary)["current_room_id"] = "missing_room"
		_write_text(store.save_path, JSON.stringify(corrupt_payload))
		var loaded := store.load_run()
		_check(loaded != null and loaded.gold == 77, "compatible backup must restore a %s current primary" % malformed_kind)
		_check(store.load_status == AdventureSaveSchema.LoadStatus.RESTORED_BACKUP, "%s recovery must be reported" % malformed_kind)
		store.delete_save()


func _check_invalid_initialized_shop_stock_restores_compatible_backup() -> void:
	var store := AdventureSaveStore.new(DIAGNOSTIC_SLOT, LEGACY_DIAGNOSTIC_SLOT)
	for malformed_kind in ["empty_stock", "missing_kind", "wrong_price_type", "unknown_kind"]:
		store.delete_save()
		var backup_run := _make_complete_run(5681)
		backup_run.gold = 81
		_write_text(store.backup_path, JSON.stringify(store._serialize_run(backup_run)))
		var corrupt_payload := store._serialize_run(_make_complete_run(5682))
		var room := ((corrupt_payload["floor"] as Dictionary)["rooms"] as Array)[0] as Dictionary
		match malformed_kind:
			"empty_stock":
				room["shop_stock"] = []
			"missing_kind":
				((room["shop_stock"] as Array)[0] as Dictionary).erase("kind")
			"wrong_price_type":
				((room["shop_stock"] as Array)[0] as Dictionary)["price"] = "12"
			"unknown_kind":
				((room["shop_stock"] as Array)[0] as Dictionary)["kind"] = "artifact"
		_write_text(store.save_path, JSON.stringify(corrupt_payload))
		var loaded := store.load_run()
		_check(loaded != null and loaded.gold == 81, "compatible backup must restore %s initialized shop stock" % malformed_kind)
		_check(store.load_status == AdventureSaveSchema.LoadStatus.RESTORED_BACKUP, "%s shop stock must mark primary corrupt" % malformed_kind)
		store.delete_save()


func _check_invalid_pending_move_or_shop_restores_compatible_backup() -> void:
	var store := AdventureSaveStore.new(DIAGNOSTIC_SLOT, LEGACY_DIAGNOSTIC_SLOT)
	for transaction_type in [AdventureEnums.TransactionType.MOVE, AdventureEnums.TransactionType.SHOP]:
		for malformed_kind in ["empty_payload", "bad_result"]:
			store.delete_save()
			var backup_run := _make_complete_run(5683)
			backup_run.gold = 82
			_write_text(store.backup_path, JSON.stringify(store._serialize_run(backup_run)))
			var corrupt_payload := store._serialize_run(_make_complete_run(5684))
			var pending := corrupt_payload["pending"] as Dictionary
			pending["type"] = transaction_type
			pending["committed"] = false
			if malformed_kind == "empty_payload":
				pending["id"] = "malformed_pending"
				pending["payload"] = {}
			else:
				(pending["payload"] as Dictionary)["result"] = {"message": "bad"}
			_write_text(store.save_path, JSON.stringify(corrupt_payload))
			var loaded := store.load_run()
			_check(loaded != null and loaded.gold == 82, "compatible backup must restore %s %d pending transaction" % [malformed_kind, transaction_type])
			_check(store.load_status == AdventureSaveSchema.LoadStatus.RESTORED_BACKUP, "%s %d pending transaction must mark primary corrupt" % [malformed_kind, transaction_type])
			store.delete_save()


func _check_recovered_backup_is_preserved_when_saving() -> void:
	var store := AdventureSaveStore.new(DIAGNOSTIC_SLOT, LEGACY_DIAGNOSTIC_SLOT)
	store.delete_save()
	var backup_run := _make_complete_run(5680)
	backup_run.gold = 78
	_write_text(store.backup_path, JSON.stringify(store._serialize_run(backup_run)))
	var backup_before := _read_text(store.backup_path)
	_write_text(store.save_path, JSON.stringify({"version": AdventureSaveSchema.VERSION, "floor": {}}))
	var recovered := store.load_run()
	_check(recovered != null and recovered.gold == 78, "compatible backup must recover before replacement save")
	_check(store.load_status == AdventureSaveSchema.LoadStatus.RESTORED_BACKUP, "recovered primary must report backup restoration")
	if recovered != null:
		recovered.gold = 79
		_check(store.save_run(recovered) == OK, "saving a recovered run must succeed")
		_check(_read_text(store.backup_path) == backup_before, "saving over a corrupt primary must retain the compatible backup bytes")
		var loaded := store.load_run()
		_check(loaded != null and loaded.gold == 79, "replacement primary must load after retaining backup")
	store.delete_save()


func _check_missing_primary_restores_compatible_backup() -> void:
	var store := AdventureSaveStore.new(DIAGNOSTIC_SLOT, LEGACY_DIAGNOSTIC_SLOT)
	store.delete_save()
	var backup_run := _make_complete_run(6789)
	backup_run.gold = 88
	_write_text(store.backup_path, JSON.stringify(store._serialize_run(backup_run)))
	var loaded := store.load_run()
	_check(loaded != null and loaded.gold == 88, "compatible backup must restore when an interrupted save has no primary")
	_check(store.load_status == AdventureSaveSchema.LoadStatus.RESTORED_BACKUP, "missing-primary backup recovery must be reported")
	store.delete_save()


func _check_unreadable_primary_restores_compatible_backup() -> void:
	var store := AdventureSaveStore.new(DIAGNOSTIC_SLOT, LEGACY_DIAGNOSTIC_SLOT)
	store.delete_save()
	var backup_run := _make_complete_run(7890)
	backup_run.gold = 99
	_write_text(store.backup_path, JSON.stringify(store._serialize_run(backup_run)))
	_write_text(store.save_path, "{truncated")
	var loaded := store.load_run()
	_check(loaded != null and loaded.gold == 99, "compatible backup must restore an unreadable primary")
	_check(store.load_status == AdventureSaveSchema.LoadStatus.RESTORED_BACKUP, "unreadable-primary backup recovery must be reported")
	store.delete_save()


func _make_complete_run(seed: int) -> PartyRunState:
	var run := PartyRunState.new()
	run.initialize_adventure(seed, [], AdventureDefinition.new())
	run.gold = 63
	run.adventure_flags["round_trip"] = "kept"
	run.equipment_reward_drawn_paths = PackedStringArray(["res://round_trip_item.tres"])
	run.equipment_reward_offers = {"round_trip": [{"path": "res://round_trip_item.tres", "reward_class": 0}]}
	run.equipment_class_miss_streaks = {"0": 2}
	var floor := AdventureFloorState.new()
	floor.floor_index = 1
	floor.floor_seed = 9001
	floor.grid_size = Vector2i(2, 1)
	floor.danger = 12
	floor.triggered_thresholds = PackedInt32Array([6, 12])
	var room := AdventureRoomState.new()
	room.room_id = "runtime_shop"
	room.cell = Vector2i(1, 0)
	room.back_type = AdventureEnums.BackType.MYSTERY
	room.room_type = AdventureEnums.RoomType.SHOP
	room.content_id = "shop_hidden"
	room.visited = true
	room.content_revealed = true
	room.high_value = true
	room.high_value_marked = true
	room.danger_variant_id = "danger_18"
	room.shop_stock = [{
		"kind": "consumable",
		"path": "res://resources/items/healing_potion.tres",
		"name": "治疗药剂",
		"price": 12,
		"hero_id": "",
		"sold": false,
	}]
	room.shop_initialized = true
	room.shop_restock_count = 1
	room.camp_visit_closed = true
	room.runtime_data = {"marker": "runtime"}
	floor.rooms = [room]
	floor.current_room_id = room.room_id
	run.floor_state = floor
	run.begin_transaction(AdventureEnums.TransactionType.SHOP, "shop_pending", {
		"floor_after": floor.to_dict(),
		"rng_after": run.shop_rng_state,
		"result": {
			"ok": true,
			"operation_id": "shop_pending",
			"danger": floor.danger,
			"danger_change": {},
			"item": room.shop_stock[0].duplicate(true),
		},
	})
	return run


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check(false, "unable to write temporary diagnostic save")
		return
	file.store_string(text)
	file.close()


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _check(value: bool, message: String) -> void:
	if value:
		return
	failures += 1
	printerr("HEX_SAVE: " + message)
