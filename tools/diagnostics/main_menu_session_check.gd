extends Node

var failures := 0

class FailingStore extends AdventureSaveStore:
	func save_run(_run: PartyRunState) -> Error:
		return ERR_CANT_CREATE

func _ready() -> void:
	var session := AdventureSessionService.new()
	session.save_store = AdventureSaveStore.new("main_menu_diagnostic_session", "main_menu_diagnostic_legacy")
	session.save_store.delete_save()
	if not session.has_method("get_menu_state"):
		_check(false, "menu lifecycle API is missing")
	else:
		_check_lifecycle(session)
	session.save_store.delete_save()
	session.free()
	print("MAIN_MENU_SESSION: %s" % ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)

func _check_lifecycle(session: AdventureSessionService) -> void:
	var state: Dictionary = session.call("get_menu_state")
	_check(not state.can_continue and state.can_start, "empty slot allows only new game")
	_check(session.current_run == null and not session.save_store.has_save(), "query has no creation side effect")
	var result: Dictionary = session.call("start_new_game", 777, false)
	_check(result.ok, "first game saved")
	if not result.ok:
		return
	var original := session.current_run
	var bytes := FileAccess.get_file_as_string(session.save_store.save_path)
	result = session.call("start_new_game", 888, false)
	_check(not result.ok and session.current_run == original, "overwrite requires confirmation")
	_check(FileAccess.get_file_as_string(session.save_store.save_path) == bytes, "cancel keeps saved run")
	state = session.call("get_menu_state")
	_check(state.can_continue and state.requires_confirmation, "valid unfinished run is continuable")
	original.run_failed = true
	_check(not session.call("get_menu_state").can_continue, "failed run cannot continue")
	original.run_failed = false
	original.run_complete = true
	_check(not session.call("get_menu_state").can_continue, "completed run cannot continue")
	original.run_complete = false
	var store := session.save_store
	var bad_store := FailingStore.new("main_menu_diagnostic_session", "main_menu_diagnostic_legacy")
	session.save_store = bad_store
	result = session.call("start_new_game", 999, true)
	_check(not result.ok and session.current_run == original, "failed save never publishes new run")
	result = session.call("prepare_return_to_menu", false)
	_check(not result.ok, "map return refuses failed save")
	session.save_store = store
	_check(FileAccess.get_file_as_string(store.save_path) == bytes, "failed operations keep disk bytes")
	_check_checkpoint(session)
	# Unknown backups must protect even a valid primary and a stale load_status.
	_write(store.backup_path, '{"version":999}')
	_check(not session.call("get_menu_state").can_start, "future backup protects new-game entry")
	result = session.call("start_new_game", 123, true)
	_check(not result.ok, "confirmed overwrite cannot replace future backup")
	_check(FileAccess.get_file_as_string(store.backup_path) == '{"version":999}', "future backup preserved")
	store.delete_save()
	_write(store.save_path, "broken")
	session.current_run = store.load_run()
	state = session.call("get_menu_state")
	_check(not state.can_continue and state.requires_confirmation, "corrupt slot requires explicit rebuilding")
	_check(not session.call("start_new_game", 123, false).ok, "corrupt save cannot silently be replaced")
	_check(session.call("start_new_game", 123, true).ok, "confirmed corrupt slot can start fresh")
	store.delete_save()
	_write(store.legacy_save_path, '{"version":6}')
	session.current_run = store.load_run()
	_check(not session.call("start_new_game", 123, false).ok, "legacy requires explicit new slot")
	_check(session.call("start_new_game", 123, true).ok, "legacy allows confirmed new slot")
	_check(FileAccess.get_file_as_string(store.legacy_save_path) == '{"version":6}', "legacy file untouched")
	DirAccess.remove_absolute(store.legacy_save_path)
	# Make valid backup then corrupt primary; restoration remains continuable.
	store.save_run(session.current_run)
	_write(store.save_path, "broken")
	session.current_run = store.load_run()
	_check(session.current_run != null and session.call("get_menu_state").can_continue, "valid backup can continue")

func _check_checkpoint(session: AdventureSessionService) -> void:
	var run := session.current_run
	var room := run.floor_state.get_adjacent_rooms(run.floor_state.current_room_id)[0]
	room.room_type = AdventureEnums.RoomType.NORMAL_BATTLE
	var payload := AdventureBattleSetupService.create_payload(run, room, AdventureEnums.EncounterTier.WEAK)
	run.begin_transaction(AdventureEnums.TransactionType.BATTLE, "battle_test", payload)
	_check(session.save_store.save_run(run) == OK, "battle fixture saved")
	var health := run.party[0].current_health
	var gold := run.gold
	var rng := run.shop_rng_state
	var bytes := FileAccess.get_file_as_string(session.save_store.save_path)
	run.party[0].current_health = 1
	run.gold = 999
	var result: Dictionary = session.call("prepare_return_to_menu", true)
	_check(result.ok, "battle returns by reload")
	_check(session.current_run != run and session.current_run.party[0] != run.party[0], "fresh hero references")
	_check(session.current_run.party[0].current_health == health and session.current_run.gold == gold, "midbattle changes discarded")
	_check(session.current_run.shop_rng_state == rng, "shop RNG unchanged")
	_check(FileAccess.get_file_as_string(session.save_store.save_path) == bytes, "battle return never writes partial state")
	result = session.call("prepare_continue")
	_check(result.ok and result.scene_path == AdventureSessionService.BATTLE_SCENE_PATH, "continue routes checkpoint to battle")
	_check(session.pending_battle_scenario != null, "battle scenario rebuilt")
	_check(JSON.stringify(session.current_run.pending_transaction.payload.danger_snapshot) == JSON.stringify(JSON.parse_string(JSON.stringify(payload.danger_snapshot))), "danger snapshot locked")
	# Committed result on disk wins over stale battle memory.
	var saved := session.save_store.load_run()
	saved.commit_transaction()
	saved.adventure_flags["interfloor_camp"] = true
	session.save_store.save_run(saved)
	result = session.call("prepare_return_to_menu", true)
	_check(result.ok and not session.has_pending_battle(), "submitted result cannot revive battle")
	result = session.call("prepare_continue")
	_check(result.ok and result.scene_path == AdventureSessionService.MAP_SCENE_PATH, "postbattle continues on map")

func _write(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(value)
	file.close()

func _check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		printerr("MAIN_MENU_SESSION: " + label)
