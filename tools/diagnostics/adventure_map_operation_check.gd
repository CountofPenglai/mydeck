extends Node
var failures := 0

func _ready() -> void:
	var path := "res://scripts/adventure/adventure_map_operation_service.gd"
	if not ResourceLoader.exists(path):
		printerr("HEX_MAP_OPERATION: operation service missing")
		get_tree().quit(1)
		return
	var operations: Script = load(path)
	var run := PartyRunState.new()
	run.initialize_adventure(91, [], AdventureDefinition.new())
	run.floor_state = AdventureFloorState.new()
	run.floor_state.floor_seed = 91
	run.floor_state.current_room_id = "start"
	for data in [
		{"id":"start","cell":[0,0],"type":AdventureEnums.RoomType.START,"visited":true,"completed":true,"content_revealed":true},
		{"id":"camp","cell":[1,0],"type":AdventureEnums.RoomType.SHELTER},
		{"id":"shop","cell":[2,0],"type":AdventureEnums.RoomType.SHOP},
		{"id":"far","cell":[3,0],"type":AdventureEnums.RoomType.EVENT},
	]:
		run.floor_state.rooms.append(AdventureRoomState.from_dict(data))
	var result: Dictionary = operations.prepare_move(run, "camp", "move1")
	_check(result.ok, "prepare adjacent move")
	_check(run.floor_state.current_room_id == "start" and run.floor_state.danger == 0, "prepare cannot apply")
	_check(run.pending_transaction.transaction_type == AdventureEnums.TransactionType.MOVE, "staged transaction")
	# Restore the prepared snapshot as if process died before application.
	run.pending_transaction = PendingAdventureTransaction.from_dict(run.pending_transaction.to_dict())
	_check(operations.apply_pending_move(run).ok, "apply restored move")
	_check(run.floor_state.current_room_id == "camp" and run.floor_state.danger == 1, "first entry charged once")
	_check(operations.apply_pending_move(run).ok and run.floor_state.danger == 1, "duplicate application idempotent")
	run.commit_transaction()
	_check(operations.prepare_move(run, "camp", "move1").get("duplicate", false), "duplicate request returns prior result")
	_check(run.floor_state.danger == 1, "duplicate request free")
	_check(not operations.prepare_move(run, "far", "invalid").ok, "cannot traverse unexplored shop")
	_check(run.floor_state.danger == 1 and run.pending_transaction.committed, "invalid no pending side effect")
	_check(operations.prepare_move(run, "shop", "move2").ok, "next entry")
	operations.apply_pending_move(run)
	run.commit_transaction()
	_check(run.floor_state.get_room("camp").camp_visit_closed, "departure closes camp")
	_check(not run.floor_state.get_room("shop").runtime_data.get("shop_revisit_available", true), "first shop visit not restock")
	operations.prepare_move(run, "camp", "move3")
	operations.apply_pending_move(run)
	run.commit_transaction()
	operations.prepare_move(run, "shop", "move4")
	operations.apply_pending_move(run)
	run.commit_transaction()
	_check(run.floor_state.danger == 2, "visited travel free")
	_check(run.floor_state.get_room("shop").runtime_data.get("shop_revisit_available", false), "physical revisit eligible for explicit restock")
	print("HEX_MAP_OPERATION: %s" % ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("HEX_MAP_OPERATION: "+message)
