extends Node
class NoSceneSession extends AdventureSessionService:
	func _enter_pending_battle_scene() -> bool:
		return pending_battle_scenario != null

var failures := 0

func _ready() -> void:
	var session := NoSceneSession.new()
	session.save_store = AdventureSaveStore.new("hex_diagnostic_session_v7")
	session.start_new_demo(20260921)
	var floor := session.current_run.floor_state
	var origin := floor.get_current_room()
	var target := floor.get_adjacent_rooms(origin.room_id)[0]
	target.room_type = AdventureEnums.RoomType.EVENT
	target.content_id = "hermit_house"
	target.runtime_data.clear()
	AdventureEncounterContent.populate(floor)
	floor.danger = 17
	var before_gold := session.current_run.gold
	var result := session.request_move(target.room_id)
	_check(result.ok, "entry accepted")
	_check(session.current_run.floor_state.danger == 18, "first entry danger")
	_check(session.has_pending_battle(), "danger18 event battle begins immediately")
	_check(session.current_run.pending_transaction.payload.get("reward_mode", "") == "cards_only", "danger variant reward fixed")
	_check(not session.resolve_current_event("leave").ok, "danger battle prevents original event choice")
	_check(not session.request_move(origin.room_id).ok, "unresolved battle blocks travel")
	_check(session.current_run.gold == before_gold, "entry grants no original reward")
	var pending := session.current_run.pending_transaction.to_dict()
	session.start_event_battle(target.content_id)
	_check(session.current_run.pending_transaction.to_dict() == pending, "battle button reuses locked danger event")
	session._rebuild_pending_battle_scenario()
	_check(session.current_run.pending_transaction.to_dict() == pending, "battle reconstruction never changes snapshot")
	session.save_store.delete_save()
	session.free()
	var legacy := AdventureSessionService.new()
	legacy.save_store = AdventureSaveStore.new("hex_diagnostic_startup_v7")
	legacy.save_store.load_status = AdventureSaveSchema.LoadStatus.LEGACY_SAVE_DETECTED
	_check(legacy.ensure_run() == null, "legacy detection cannot silently start new run")
	legacy.save_store.delete_save()
	legacy.free()
	_check_camp_and_event()
	_check_shop_and_recovery()
	_check_forced_event_options()
	print("HEX_SESSION: %s" % ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("HEX_SESSION: "+message)

func _check_camp_and_event() -> void:
	var session := AdventureSessionService.new()
	session.save_store = AdventureSaveStore.new("hex_diagnostic_camp_v7")
	session.start_new_demo(777)
	var floor := session.current_run.floor_state
	var origin_id := floor.current_room_id
	var target := floor.get_adjacent_rooms(origin_id)[0]
	target.room_type = AdventureEnums.RoomType.EVENT
	target.content_id = "alchemy"
	_check(session.request_move(target.room_id).ok, "normal event entry")
	session.current_run.adventure_flags["pending_event_reward"] = {"event_id": "test", "room_id": target.room_id}
	_check(not session.resolve_current_event("leave").ok, "unresolved event reward prevents new choice")
	session.current_run.adventure_flags.erase("pending_event_reward")
	_check(session.resolve_current_event("leave").ok, "normal event leave")
	_check(session.request_move(origin_id).ok, "event leave unlocks movement")
	floor = session.current_run.floor_state
	target = floor.get_room(target.room_id)
	target.room_type = AdventureEnums.RoomType.SHELTER
	target.visited = false
	_check(session.request_move(target.room_id).ok, "camp entry")
	floor = session.current_run.floor_state
	var before_points := session.current_run.camp_points
	var before_danger := floor.danger
	if session.has_method("request_scout"):
		var invalid: Array[String] = []
		_check(not session.call("request_scout", invalid).ok, "cancel scout no effect")
		_check(session.current_run.camp_points == before_points, "cancel scout no cost")
		var ids: Array[String] = session.call("get_scout_candidates")
		var selected: Array[String] = [ids[0], ids[1]]
		_check(session.call("request_scout", selected).ok, "choose two scouting tiles")
		_check(session.current_run.camp_points == before_points - 1, "scout costs one point")
		_check(floor.danger == before_danger and not floor.get_room(ids[0]).visited, "scout not exploration")
	else:
		_check(false, "selection scout API missing")
	_check(session.request_move(origin_id).ok, "leave camp")
	_check(session.request_move(target.room_id).ok, "revisit camp")
	_check(not session.use_camp_activity("tactics"), "closed camp rejects activity")
	_check(not session.rest_at_current_shelter(), "closed camp rejects rest")
	session.save_store.delete_save()
	session.free()

func _check_forced_event_options() -> void:
	var session := AdventureSessionService.new()
	session.save_store = AdventureSaveStore.new("hex_review_event_options")
	session.start_new_demo(779)
	var floor := session.current_run.floor_state
	var origin_id := floor.current_room_id
	var target := floor.get_adjacent_rooms(origin_id)[0]
	target.room_type = AdventureEnums.RoomType.EVENT
	target.content_id = "nature_blessing"
	_check(session.request_move(target.room_id).ok, "forced event entry")
	var before := session.current_run.pending_transaction.to_dict()
	_check(not session.resolve_current_event("leave").ok, "no-leave event rejects fabricated exit")
	_check(not session.resolve_current_event("gamble").ok, "event rejects another event's action")
	_check(session.current_run.pending_transaction.to_dict() == before, "invalid event action preserves pending decision")
	_check(not session.request_move(origin_id).ok, "invalid exit cannot unlock travel")
	_check(session.resolve_current_event("nature_resolve").ok, "declared forced event action still resolves")
	_check(session.request_move(origin_id).ok, "resolved forced event unlocks travel")
	session.save_store.delete_save()
	session.free()

func _check_shop_and_recovery() -> void:
	var session := AdventureSessionService.new()
	session.save_store = AdventureSaveStore.new("hex_diagnostic_recovery_v7")
	session.start_new_demo(778)
	var run := session.current_run
	for room in run.floor_state.rooms:
		if room.room_type == AdventureEnums.RoomType.SHOP:
			_check(room.shop_initialized and not room.shop_stock.is_empty(), "new run initializes both shops")
	var target := run.floor_state.get_adjacent_rooms(run.floor_state.current_room_id)[0]
	target.room_type = AdventureEnums.RoomType.START
	var initial_danger := run.floor_state.danger
	AdventureMapOperationService.prepare_move(run, target.room_id, "crash_move")
	session.save_store.save_run(run)
	session._ready()
	_check(session.current_run.floor_state.current_room_id == target.room_id, "reload recovers prepared move")
	_check(session.current_run.floor_state.danger == initial_danger + 1, "recovered move charged once")
	session._ready()
	_check(session.current_run.floor_state.danger == initial_danger + 1, "second reload cannot repeat move")
	if session.has_method("request_shop_restock"):
		run = session.current_run
		var shop: AdventureRoomState
		for room in run.floor_state.rooms:
			if room.room_type == AdventureEnums.RoomType.SHOP:
				shop = room
				break
		run.floor_state.current_room_id = shop.room_id
		shop.visited = true
		shop.runtime_data["shop_revisit_available"] = true
		var before_size := shop.shop_stock.size()
		var before_rng := run.shop_rng_state
		_check(session.call("request_shop_restock", "restock_session").ok, "explicit restock succeeds")
		_check(run.floor_state.get_current_room().shop_stock.size() == before_size + 1, "restock adds one")
		_check(session.call("request_shop_restock", "restock_session").ok, "duplicate restock is idempotent")
		_check(run.shop_rng_state != before_rng, "restock advances shop stream")
		var after_rng := run.shop_rng_state
		var after_danger := run.floor_state.danger
		session._ready()
		_check(session.current_run.shop_rng_state == after_rng and session.current_run.floor_state.danger == after_danger, "reload preserves shop result")
	else:
		_check(false, "explicit shop restock API missing")
	session.save_store.delete_save()
	session.free()
