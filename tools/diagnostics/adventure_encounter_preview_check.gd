extends Node

const CARD_ONLY_EVENTS := ["hermit_house", "adventurer_remains", "nature_blessing"]

var failures := 0


func _ready() -> void:
	_test_hidden_preview_is_empty_and_revealed_preview_is_pure()
	_test_normal_threshold_previews_match_session_entry()
	_test_danger_event_previews_match_session_entry()
	_test_locked_payload_stays_authoritative_after_floor_changes()
	print("ENCOUNTER_PREVIEW: %s" % ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)


func _test_hidden_preview_is_empty_and_revealed_preview_is_pure() -> void:
	var run := PartyRunState.new()
	run.initialize_adventure(8888, [], AdventureDefinition.new())
	run.floor_state = AdventureMapGenerator.new().generate(8888, 0)
	var room := _first_room_of_type(run.floor_state, AdventureEnums.RoomType.NORMAL_BATTLE)
	_check(room != null and AdventureEncounterPreviewService.describe(run, room).is_empty(), "hidden encounter must not leak")
	if room == null:
		return
	room.content_revealed = true
	var before := JSON.stringify(run.floor_state.to_dict()) + run.shop_rng_state + JSON.stringify(run.adventure_flags)
	var preview := AdventureEncounterPreviewService.describe(run, room)
	_check(not preview.is_empty() and int(preview.get("predicted_danger", -1)) == run.floor_state.danger + 1, "first visit predicts danger cost")
	_check("首次探索 +1" in str(preview.get("text", "")), "text labels first-entry danger")
	_check(before == JSON.stringify(run.floor_state.to_dict()) + run.shop_rng_state + JSON.stringify(run.adventure_flags), "preview must be pure")


func _test_normal_threshold_previews_match_session_entry() -> void:
	for before_danger in [5, 11, 17]:
		var session := _new_session(901000 + before_danger, "normal_%d" % before_danger)
		var room := _configure_adjacent_room(session, AdventureEnums.RoomType.NORMAL_BATTLE, "normal_battle", before_danger)
		if room == null:
			_release_session(session)
			continue
		var preview := AdventureEncounterPreviewService.describe(session.current_run, room)
		var result := session.request_move(room.room_id, "preview_normal_%d" % before_danger)
		_check(bool(result.get("ok", false)), "normal %d to %d session entry succeeds" % [before_danger, before_danger + 1])
		_check(not preview.is_empty(), "normal %d to %d produces a preview" % [before_danger, before_danger + 1])
		_check(int(preview.get("predicted_danger", -1)) == before_danger + 1, "normal %d to %d preview uses entry danger" % [before_danger, before_danger + 1])
		_assert_preview_matches_pending_payload(preview, session.current_run.pending_transaction, "normal %d to %d" % [before_danger, before_danger + 1])
		_release_session(session)


func _test_danger_event_previews_match_session_entry() -> void:
	for event_id in CARD_ONLY_EVENTS:
		var session := _new_session(902000 + event_id.hash(), "event_%s" % event_id)
		var room := _configure_adjacent_room(session, AdventureEnums.RoomType.EVENT, event_id, 17)
		if room == null:
			_release_session(session)
			continue
		var preview := AdventureEncounterPreviewService.describe(session.current_run, room)
		var result := session.request_move(room.room_id, "preview_event_%s" % event_id)
		_check(bool(result.get("ok", false)), "%s danger 17 to 18 session entry succeeds" % event_id)
		_check(not preview.is_empty(), "%s danger 17 to 18 must expose its fixed battle preview" % event_id)
		_check(int(preview.get("predicted_danger", -1)) == 18, "%s preview uses danger 18" % event_id)
		_check(str(session.current_run.pending_transaction.payload.get("reward_mode", "")) == "cards_only", "%s entry locks cards-only danger battle" % event_id)
		_assert_preview_matches_pending_payload(preview, session.current_run.pending_transaction, "%s danger 17 to 18" % event_id)
		_release_session(session)


func _test_locked_payload_stays_authoritative_after_floor_changes() -> void:
	var session := _new_session(903000, "locked")
	var room := _configure_adjacent_room(session, AdventureEnums.RoomType.NORMAL_BATTLE, "normal_battle", 5)
	if room == null:
		_release_session(session)
		return
	var entry_result := session.request_move(room.room_id, "preview_locked")
	_check(bool(entry_result.get("ok", false)), "locked preview session entry succeeds")
	var payload: Dictionary = session.current_run.pending_transaction.payload.duplicate(true)
	var expected_healths := _runtime_healths(session.current_run, payload)
	session.current_run.floor_state.danger = 24
	var preview := AdventureEncounterPreviewService.describe(session.current_run, room)
	_check(bool(preview.get("locked", false)), "pending battle preview is locked")
	_check("本场锁定危险 6" in str(preview.get("text", "")), "locked preview labels its original danger")
	_check((preview.get("danger_snapshot", {}) as Dictionary) == (payload.get("danger_snapshot", {}) as Dictionary), "locked preview retains the persisted snapshot after floor danger changes")
	_check(_preview_healths(preview) == expected_healths, "locked preview health remains the runtime health from its persisted payload")
	_release_session(session)


func _new_session(seed: int, suffix: String) -> AdventureSessionService:
	var session := AdventureSessionService.new()
	session.save_store = AdventureSaveStore.new("encounter_preview_%s" % suffix)
	session.save_store.delete_save()
	session.start_new_demo(seed)
	return session


func _release_session(session: AdventureSessionService) -> void:
	if session == null:
		return
	session.save_store.delete_save()
	session.free()


func _configure_adjacent_room(session: AdventureSessionService, room_type: int, content_id: String, danger: int) -> AdventureRoomState:
	if session == null or session.current_run == null or session.current_run.floor_state == null:
		_check(false, "preview fixture requires a generated run")
		return null
	var floor := session.current_run.floor_state
	var adjacent := floor.get_adjacent_rooms(floor.current_room_id)
	if adjacent.is_empty():
		_check(false, "preview fixture requires a room adjacent to the start")
		return null
	var room := adjacent[0]
	room.room_type = room_type
	room.content_id = content_id
	room.runtime_data.clear()
	room.visited = false
	room.content_revealed = true
	room.completed = false
	floor.danger = danger
	AdventureEncounterContent.populate(floor)
	return room


func _assert_preview_matches_pending_payload(preview: Dictionary, pending: PendingAdventureTransaction, label: String) -> void:
	if pending == null:
		_check(false, "%s must create a pending battle payload" % label)
		return
	var payload: Dictionary = pending.payload
	var snapshot: Dictionary = payload.get("danger_snapshot", {}) as Dictionary
	_check(pending.transaction_type == AdventureEnums.TransactionType.BATTLE, "%s creates a battle transaction" % label)
	_check((preview.get("danger_snapshot", {}) as Dictionary).get("initial_assignments", []) == snapshot.get("initial_assignments", []), "%s preview assignments match Session payload" % label)
	_check(int(preview.get("damage_bonus_percent", -1)) == int(snapshot.get("bonus_percent", -2)), "%s preview exposes the locked damage bonus" % label)
	_check(_preview_healths(preview) == _runtime_healths(null, payload), "%s preview health matches real battle payload" % label)


func _runtime_healths(run: PartyRunState, payload: Dictionary) -> Array[int]:
	var effective_run := run
	if effective_run == null:
		# The payload itself is sufficient for enemy construction; retain a lightweight run for the builder fallback.
		effective_run = PartyRunState.new()
		effective_run.initialize_adventure(1, [], AdventureDefinition.new())
	var scenario := AdventureBattleScenarioBuilder.build(effective_run, payload)
	var result: Array[int] = []
	if scenario == null:
		return result
	for index in range(scenario.enemies.size()):
		var enemy := scenario.enemies[index] as EnemyState
		if enemy == null:
			continue
		AdventureBattleDangerService.apply_enemy(enemy, scenario.danger_snapshot, index)
		result.append(enemy.get_max_health())
	return result


func _preview_healths(preview: Dictionary) -> Array[int]:
	var result: Array[int] = []
	for enemy_data in preview.get("enemies", []) as Array:
		if enemy_data is Dictionary:
			result.append(int((enemy_data as Dictionary).get("max_health", -1)))
	return result


func _first_room_of_type(floor: AdventureFloorState, room_type: int) -> AdventureRoomState:
	if floor == null:
		return null
	for room in floor.rooms:
		if room != null and room.room_type == room_type:
			return room
	return null


func _check(value: bool, message: String) -> void:
	if value:
		return
	failures += 1
	printerr("ENCOUNTER_PREVIEW: " + message)
