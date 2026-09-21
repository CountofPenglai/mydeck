extends RefCounted
class_name AdventureMapOperationService

const RESULTS_KEY := "map_operation_results"

## Stages the exact floor result without applying it; Session saves before apply.
static func prepare_move(run: PartyRunState, target_id: String, operation_id: String) -> Dictionary:
	if run == null or run.floor_state == null or operation_id.is_empty():
		return _failure("无效的移动请求。")
	var previous: Dictionary = run.adventure_flags.get(RESULTS_KEY, {})
	if previous.has(operation_id):
		var duplicate: Dictionary = previous[operation_id].duplicate(true)
		duplicate["duplicate"] = true
		return duplicate
	if run.pending_transaction != null and not run.pending_transaction.committed:
		return _failure("请先完成当前事件或奖励。")
	var path := AdventureTravelService.plan(run.floor_state, target_id)
	if path.is_empty():
		return _failure("只能经已探索区域到达相邻新图格。")
	var after := AdventureFloorState.from_dict(run.floor_state.to_dict())
	var origin := after.get_current_room()
	var target := after.get_room(target_id)
	var first_visit := not target.visited
	if origin.room_type == AdventureEnums.RoomType.SHELTER:
		origin.camp_visit_closed = true
	if origin.room_type == AdventureEnums.RoomType.SHOP:
		origin.runtime_data["shop_revisit_available"] = false
	var danger_change: Dictionary = {}
	if first_visit:
		danger_change = AdventureDangerService.advance(after, target_id)
	after.current_room_id = target_id
	target.visited = true
	target.content_revealed = true
	if target.room_type == AdventureEnums.RoomType.SHOP:
		target.runtime_data["shop_revisit_available"] = not first_visit
		target.runtime_data["shop_visit_serial"] = int(target.runtime_data.get("shop_visit_serial", 0)) + 1
	var result := {
		"ok": true, "target_id": target_id, "first_visit": first_visit,
		"danger": after.danger, "danger_change": danger_change,
		"path": path, "operation_id": operation_id,
	}
	run.begin_transaction(AdventureEnums.TransactionType.MOVE, operation_id, {
		"floor_after": after.to_dict(), "result": result,
	})
	return result.duplicate(true)

## Reapplying the saved snapshot cannot charge again. Does not consume the transaction.
static func apply_pending_move(run: PartyRunState) -> Dictionary:
	if run == null or run.pending_transaction == null:
		return _failure("没有待恢复的移动。")
	var pending := run.pending_transaction
	if pending.transaction_type != AdventureEnums.TransactionType.MOVE or pending.committed:
		return _failure("当前事务不是移动。")
	var floor_data: Dictionary = pending.payload.get("floor_after", {})
	var result: Dictionary = pending.payload.get("result", {})
	if floor_data.is_empty() or result.is_empty():
		return _failure("移动事务数据不完整。")
	var previous: Dictionary = run.adventure_flags.get(RESULTS_KEY, {})
	if previous.has(pending.transaction_id):
		return previous[pending.transaction_id].duplicate(true)
	run.floor_state = AdventureFloorState.from_dict(floor_data)
	previous[pending.transaction_id] = result.duplicate(true)
	run.adventure_flags[RESULTS_KEY] = previous
	return result.duplicate(true)

static func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}
