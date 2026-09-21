extends RefCounted
class_name AdventureShopService

const RESULTS_KEY := "shop_operation_results"

static func initialize_map(run: PartyRunState) -> bool:
	if run == null or run.floor_state == null or run.shop_rng_seed.is_empty() or run.shop_rng_state.is_empty():
		return false
	var shops: Array[AdventureRoomState] = []
	for room in run.floor_state.rooms:
		if room != null and room.room_type == AdventureEnums.RoomType.SHOP and not room.shop_initialized:
			shops.append(room)
	shops.sort_custom(func(a: AdventureRoomState, b: AdventureRoomState): return a.room_id < b.room_id)
	var rng := _rng(run)
	var generated := {}
	for room in shops:
		var stock := AdventureShopStockFactory.initial_stock(run, rng)
		if stock.is_empty():
			push_error("AdventureShopService: initial shop stock has no valid candidates")
			return false
		generated[room.room_id] = stock
	for room in shops:
		room.shop_stock = (generated[room.room_id] as Array).duplicate(true)
		room.shop_initialized = true
	run.shop_rng_state = str(rng.state)
	return true

static func get_stock(room: AdventureRoomState) -> Array[Dictionary]:
	if room == null:
		return []
	return room.shop_stock.duplicate(true)

static func prepare_restock(run: PartyRunState, tile_id: String, operation_id: String) -> Dictionary:
	if run == null or run.floor_state == null or operation_id.is_empty():
		return _failure("无效的商店重访。")
	var previous: Dictionary = run.adventure_flags.get(RESULTS_KEY, {})
	if previous.has(operation_id):
		var duplicate: Dictionary = previous[operation_id].duplicate(true)
		duplicate["duplicate"] = true
		return duplicate
	if run.pending_transaction != null and not run.pending_transaction.committed:
		return _failure("请先完成当前事务。")
	var room := run.floor_state.get_room(tile_id)
	if room == null or run.floor_state.current_room_id != tile_id or room.room_type != AdventureEnums.RoomType.SHOP \
			or not bool(room.runtime_data.get("shop_revisit_available", false)) or room.shop_restock_count >= 2:
		return _failure("当前不能补货。")
	var rng := _rng(run)
	var item := AdventureShopStockFactory.restock_item(run, rng)
	if item.is_empty():
		return _failure("没有可用商品。")
	var after := AdventureFloorState.from_dict(run.floor_state.to_dict())
	var after_room := after.get_room(tile_id)
	after_room.shop_stock.append(item.duplicate(true))
	after_room.shop_restock_count += 1
	after_room.runtime_data["shop_revisit_available"] = false
	var danger_change := AdventureDangerService.advance(after, tile_id)
	var result := {
		"ok": true, "operation_id": operation_id, "danger": after.danger,
		"danger_change": danger_change, "item": item.duplicate(true),
	}
	run.begin_transaction(AdventureEnums.TransactionType.SHOP, operation_id, {
		"floor_after": after.to_dict(), "rng_after": str(rng.state), "result": result,
	})
	return result.duplicate(true)

static func apply_pending_restock(run: PartyRunState) -> Dictionary:
	if run == null or run.pending_transaction == null \
			or run.pending_transaction.transaction_type != AdventureEnums.TransactionType.SHOP \
			or run.pending_transaction.committed:
		return _failure("没有待恢复的商店事务。")
	var pending := run.pending_transaction
	var previous: Dictionary = run.adventure_flags.get(RESULTS_KEY, {})
	if previous.has(pending.transaction_id):
		return previous[pending.transaction_id].duplicate(true)
	var floor_data: Dictionary = pending.payload.get("floor_after", {})
	var result: Dictionary = pending.payload.get("result", {})
	if floor_data.is_empty() or result.is_empty():
		return _failure("商店事务数据不完整。")
	run.floor_state = AdventureFloorState.from_dict(floor_data)
	run.shop_rng_state = str(pending.payload.get("rng_after", run.shop_rng_state))
	previous[pending.transaction_id] = result.duplicate(true)
	run.adventure_flags[RESULTS_KEY] = previous
	run.commit_transaction()
	return result.duplicate(true)

static func restock(run: PartyRunState, tile_id: String, operation_id: String) -> Dictionary:
	var prepared := prepare_restock(run, tile_id, operation_id)
	if not bool(prepared.get("ok", false)) or bool(prepared.get("duplicate", false)):
		return prepared
	return apply_pending_restock(run)

static func _rng(run: PartyRunState) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(run.shop_rng_seed)
	rng.state = int(run.shop_rng_state)
	return rng
static func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}
