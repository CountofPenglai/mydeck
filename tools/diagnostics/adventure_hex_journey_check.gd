extends Node
var failures := 0

func _ready() -> void:
	for seed in [20260921, 777]:
		_run_journey(seed)
	print("HEX_JOURNEY: %s" % ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)

func _run_journey(seed: int) -> void:
	var session := AdventureSessionService.new()
	session.save_store = AdventureSaveStore.new("hex_diagnostic_journey_v7")
	session.start_new_demo(seed)
	for chapter_index in range(2):
		var run := session.current_run
		_check(run.floor_state.danger == 0, "each map resets danger")
		_check(run.floor_index == chapter_index, "chapter advances")
		var initial_shop_rng := run.shop_rng_state
		var shop_seed := run.shop_rng_seed
		var saw_scout := false
		var restocked := false
		# Explore a deterministic frontier, settling actual generated content.
		for step in range(46):
			run = session.current_run
			var target: AdventureRoomState
			for room in run.floor_state.rooms:
				if room.visited or room.room_type == AdventureEnums.RoomType.BOSS_BATTLE:
					continue
				if not AdventureTravelService.plan(run.floor_state, room.room_id).is_empty():
					target = room
					break
			if target == null:
				break
			var before := run.floor_state.danger
			_check(session.request_move(target.room_id).get("ok", false), "frontier move")
			_check(run.floor_state.danger == before + 1, "explore charges once")
			_settle(session)
			var room := run.floor_state.get_current_room()
			if room.room_type == AdventureEnums.RoomType.SHELTER and not saw_scout:
				var candidates := session.get_scout_candidates()
				if not candidates.is_empty():
					var selected: Array[String] = [candidates[0]]
					_check(session.request_scout(selected).get("ok", false), "camp scouts")
					saw_scout = true
			if room.room_type == AdventureEnums.RoomType.SHOP and not restocked:
				var shop_id := room.room_id
				var neighbor: AdventureRoomState
				for adjacent in run.floor_state.get_adjacent_rooms(shop_id):
					if adjacent.visited:
						neighbor = adjacent
						break
				if neighbor != null:
					_check(session.request_move(neighbor.room_id).get("ok", false), "leave shop")
					_settle(session)
					var danger := run.floor_state.danger
					_check(session.request_move(shop_id).get("ok", false), "physically revisit shop")
					_check(run.floor_state.danger == danger, "shop arrival itself free")
					_check(session.request_shop_restock().get("ok", false), "confirm paid restock")
					_check(run.floor_state.danger == danger + 1, "explicit restock dangerous")
					restocked = true
		run = session.current_run
		_check(run.floor_state.danger >= 24, "journey reaches final danger tier")
		_check(run.floor_state.triggered_thresholds.has(6) and run.floor_state.triggered_thresholds.has(12), "both value markers triggered")
		_check(saw_scout and restocked, "journey includes camp and shop")
		_check(run.shop_rng_state != initial_shop_rng, "shop stream progresses")
		var boss: AdventureRoomState
		for room in run.floor_state.rooms:
			if room.room_type == AdventureEnums.RoomType.BOSS_BATTLE:
				boss = room
				break
		# Expose an explored route naturally, without changing topology.
		for step in range(48):
			if not AdventureTravelService.plan(run.floor_state, boss.room_id).is_empty():
				break
			var closest: AdventureRoomState
			for room in run.floor_state.rooms:
				if room.visited or AdventureTravelService.plan(run.floor_state, room.room_id).is_empty():
					continue
				if closest == null or BattleHexGrid.distance(room.cell, boss.cell) < BattleHexGrid.distance(closest.cell, boss.cell):
					closest = room
			_check(closest != null, "boss reachable frontier")
			if closest == null:
				break
			session.request_move(closest.room_id)
			_settle(session)
		_check(session.request_move(boss.room_id).get("ok", false), "boss entered")
		_check(session.has_pending_battle(), "boss immediately starts")
		_check(int(run.pending_transaction.payload.danger_snapshot.bonus_percent) == 60, "boss uses capped danger")
		_settle(session)
		if chapter_index == 0:
			var rng_before_next := run.shop_rng_state
			_check(session.enter_next_floor(), "boss reward allows next map")
			_check(run.shop_rng_state != rng_before_next and run.shop_rng_seed == shop_seed, "next-map stocks continue global stream")
		else:
			_check(run.run_complete, "second boss completes run")
	session.save_store.delete_save()
	session.free()

func _settle(session: AdventureSessionService) -> void:
	var run := session.current_run
	if session.has_pending_battle():
		var payload := run.pending_transaction.payload.duplicate(true)
		session._save_only()
		var restored := session.save_store.load_run()
		# JSON restores numeric values as floats and StringName as String.
		var normalized: Dictionary = JSON.parse_string(JSON.stringify(payload))
		_check(restored != null and restored.pending_transaction.payload == normalized, "battle snapshot roundtrip")
		var result := BattleResult.new()
		result.victory = true
		_check(session.resolve_pending_battle_result(result), "battle victory processed")
		session.settle_pending_reward()
	elif run.pending_transaction.transaction_type == AdventureEnums.TransactionType.EVENT:
		var room := run.floor_state.get_current_room()
		var option := "nature_resolve" if room.content_id == "nature_blessing" else "leave"
		_check(session.resolve_current_event(option).get("ok", false), "declared event choice resolved before travel")

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("HEX_JOURNEY: " + label)
