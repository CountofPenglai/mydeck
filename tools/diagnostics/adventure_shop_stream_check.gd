extends Node

var failures := 0

func _ready() -> void:
	var run := _fixture()
	_check(run.shop_rng_seed != str(run.run_seed), "shop seed has its own fixed domain")
	_check(AdventureShopService.initialize_map(run), "initialize both shops")
	var shops := _shops(run)
	var before := run.shop_rng_state
	var stock := AdventureShopService.get_stock(shops[0])
	stock.clear()
	_check(not shops[0].shop_stock.is_empty() and run.shop_rng_state == before, "getter is an immutable pure read")
	_check(AdventureShopService.initialize_map(run) and run.shop_rng_state == before, "opening initialized shops does not draw")
	_check(not AdventureShopService.restock(run, "missing", "invalid").ok and run.shop_rng_state == before, "invalid request does not advance")
	_test_order_and_independence()
	_test_restock_recovery_and_limit()
	_test_cross_map_stream()
	_test_restock_variety()
	print("SHOP_STREAM: %s" % ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)

func _fixture() -> PartyRunState:
	var run := PartyRunState.new()
	var hero := (load("res://resources/characters/battle_warrior_state.tres") as CharacterState).duplicate(true) as CharacterState
	hero.adventure_source_path = "res://resources/characters/battle_warrior_state.tres"
	hero.ensure_initialized()
	run.initialize_adventure(2468, [hero], AdventureDefinition.new())
	run.floor_state = AdventureMapGenerator.new().generate(2468, 0)
	return run

func _shops(run: PartyRunState) -> Array[AdventureRoomState]:
	var result: Array[AdventureRoomState] = []
	for room in run.floor_state.rooms:
		if room.room_type == AdventureEnums.RoomType.SHOP:
			result.append(room)
	result.sort_custom(func(a: AdventureRoomState, b: AdventureRoomState): return a.room_id < b.room_id)
	return result

func _visit(run: PartyRunState, id: String) -> void:
	run.floor_state.current_room_id = id
	var room := run.floor_state.get_room(id)
	room.visited = true
	room.content_revealed = true
	room.runtime_data["shop_revisit_available"] = true

func _test_order_and_independence() -> void:
	var first := _fixture()
	var second := _fixture()
	second.floor_state.rooms.reverse()
	AdventureShopService.initialize_map(first)
	AdventureShopService.initialize_map(second)
	var shops := _shops(first)
	_check(first.shop_rng_state == second.shop_rng_state, "initialization order independent of room array")
	for shop in shops:
		_check(shop.shop_stock == second.floor_state.get_room(shop.room_id).shop_stock, "same initial stock by stable id")
	var before := first.shop_rng_state
	var candidates := AdventureRevealService.get_candidates(first.floor_state, first.floor_state.current_room_id, 3)
	var selected: Array[String] = [candidates[0]]
	AdventureRevealService.reveal(first.floor_state, selected)
	for room in first.floor_state.rooms:
		if room.is_combat_room():
			AdventureBattleSetupService.create_payload(first, room, AdventureEnums.EncounterTier.WEAK)
			break
	_check(first.shop_rng_state == before, "scouting and battle RNG do not advance shop stream")
	_visit(first, shops[0].room_id)
	_visit(second, shops[1].room_id)
	var a := AdventureShopService.restock(first, shops[0].room_id, "a")
	var b := AdventureShopService.restock(second, shops[1].room_id, "b")
	_check(a.ok and b.ok and a.item == b.item and first.shop_rng_state == second.shop_rng_state, "first restock uses next global item regardless of shop")
	_visit(first, shops[1].room_id)
	_visit(second, shops[0].room_id)
	a = AdventureShopService.restock(first, shops[1].room_id, "a2")
	b = AdventureShopService.restock(second, shops[0].room_id, "b2")
	_check(a.item == b.item and first.shop_rng_state == second.shop_rng_state, "AB and BA preserve global draw order")

func _test_restock_recovery_and_limit() -> void:
	var run := _fixture()
	AdventureShopService.initialize_map(run)
	var shop := _shops(run)[0]
	var id := shop.room_id
	shop.shop_stock[0]["sold"] = true
	var original := shop.shop_stock.duplicate(true)
	_visit(run, id)
	var before_rng := run.shop_rng_state
	var before_danger := run.floor_state.danger
	_check(AdventureShopService.prepare_restock(run, id, "recover").ok, "prepare restock")
	_check(run.shop_rng_state == before_rng and shop.shop_stock == original, "prepare has no effect")
	var store := AdventureSaveStore.new("hex_diagnostic_shop_recovery")
	_check(store.save_run(run) == OK, "prepared restock saved")
	var restored := store.load_run()
	_check(restored != null, "prepared restock restored")
	if restored == null:
		store.delete_save()
		return
	_check(restored.shop_rng_state == before_rng, "64-bit RNG state roundtrips exactly")
	_check(AdventureShopService.apply_pending_restock(restored).ok, "prepared restock resumes")
	var after := restored.shop_rng_state
	_check(AdventureShopService.restock(restored, id, "recover").ok and restored.shop_rng_state == after, "duplicate operation cannot reroll")
	var room := restored.floor_state.get_room(id)
	_check(room.shop_stock.size() == original.size() + 1 and bool(room.shop_stock[0].sold), "restock retains old and sold entries")
	_check(restored.floor_state.danger == before_danger + 1 and room.shop_restock_count == 1, "one danger and count")
	_check(not AdventureShopService.restock(restored, id, "same_visit").ok, "UI reopening does not allow another restock")
	_visit(restored, id)
	_check(AdventureShopService.restock(restored, id, "second").ok, "second physical revisit restocks")
	_visit(restored, id)
	after = restored.shop_rng_state
	_check(not AdventureShopService.restock(restored, id, "third").ok and restored.shop_rng_state == after, "third restock rejected without draw")
	_check(AdventureShopService.get_stock(restored.floor_state.get_room(id)).size() == original.size() + 2, "old stock remains accessible after limit")
	store.delete_save()

func _test_cross_map_stream() -> void:
	var run := _fixture()
	AdventureShopService.initialize_map(run)
	var seed := run.shop_rng_seed
	var prior_state := run.shop_rng_state
	var store := AdventureSaveStore.new("unused_shop_serialization")
	var restored := store._deserialize_run(JSON.parse_string(JSON.stringify(store._serialize_run(run))))
	run.floor_index = 1
	restored.floor_index = 1
	run.floor_state = AdventureMapGenerator.new().generate(run.run_seed, 1)
	restored.floor_state = AdventureMapGenerator.new().generate(restored.run_seed, 1)
	AdventureShopService.initialize_map(run)
	AdventureShopService.initialize_map(restored)
	_check(run.shop_rng_seed == seed and run.shop_rng_state != prior_state, "cross-map generation continues stream")
	_check(run.shop_rng_state == restored.shop_rng_state, "reload then next map uses identical sequence")
	for shop in _shops(run):
		_check(shop.shop_stock == restored.floor_state.get_room(shop.room_id).shop_stock, "next-map stock stable after reload")

func _test_restock_variety() -> void:
	var run := _fixture()
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var kinds := {}
	for index in range(40):
		var entry := AdventureShopStockFactory.restock_item(run, rng)
		kinds[str(entry.get("kind", ""))] = true
	_check(kinds.has("card") and kinds.has("equipment") and kinds.has("consumable"), "restock draws from all existing merchandise kinds")

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("SHOP_STREAM: " + message)
