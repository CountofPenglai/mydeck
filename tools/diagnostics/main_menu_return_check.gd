extends Node

var failures := 0

func _ready() -> void:
	if not ResourceLoader.exists("res://scripts/battle/battle_navigation_guard.gd"):
		_check(false, "battle return guard missing")
	else:
		_check_guard()
		await _check_return_menu()
		await _check_map_roundtrip()
	print("MAIN_MENU_RETURN: %s" % ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)

func _check_guard() -> void:
	var guard: Script = load("res://scripts/battle/battle_navigation_guard.gd")
	var controller := BattleController.new()
	controller.setup(load("res://resources/battle/sample_battle_scenario.tres").duplicate(true))
	_check(guard.check(controller, false).ok, "deployment can return")
	_check(not guard.check(controller, true).ok, "forced choice blocks return")
	var runner := controller.resolution_runner
	runner.action_active = true
	_check(not guard.check(controller, false).ok, "AP action not fully resolved")
	runner.action_active = false
	runner.is_draining_actions = true
	_check(not guard.check(controller, false).ok, "queue drain blocks return")
	runner.is_draining_actions = false
	runner.begin_attack_scope()
	_check(not guard.check(controller, false).ok, "attack aftermath blocks return")
	runner.end_attack_scope()
	runner.action_queue.append(BattleActionFrame.new())
	_check(not guard.check(controller, false).ok, "queued action blocks return")
	runner.action_queue.clear()
	controller.phase = BattleController.Phase.BATTLE
	controller.current_unit = BattleUnitState.new()
	controller.current_unit.faction = BattleUnitState.Faction.ENEMY
	_check(not guard.check(controller, false).ok, "enemy turn blocks return")
	controller.current_unit = controller.player_units[0]
	controller.current_unit.ranger_state.pending_hand_discard_count = 1
	_check(not guard.check(controller, false).ok, "unpaid forced discard blocks even without popup")
	controller.current_unit.ranger_state.pending_hand_discard_count = 0
	controller.phase = BattleController.Phase.DEPLOYMENT

func _check_return_menu() -> void:
	var session := AdventureSessionService.new()
	session.save_store = AdventureSaveStore.new("main_menu_diagnostic_return_menu")
	session.save_store.delete_save()
	var navigation := GameNavigationService.new()
	navigation.session = session
	add_child(navigation)
	var paths: Array[String] = []
	navigation.scene_switcher = func(path: String) -> Error:
		paths.append(path)
		return OK
	var gate := {"ok": true, "message": "", "standalone": true}
	var menu: Control = load("res://scenes/ui/battle_return_menu.tscn").instantiate()
	menu.navigation = navigation
	menu.safety_probe = func() -> Dictionary: return gate
	add_child(menu)
	menu.request_return()
	_check(menu.confirmation.visible, "return always asks confirmation")
	gate.ok = false
	gate.message = "选择未完成"
	menu.confirmation.confirmed.emit()
	_check(paths.is_empty(), "safety rechecked on confirm")
	gate.ok = true
	menu.confirmation.confirmed.emit()
	_check(paths == ["res://scenes/main_menu_scene.tscn"] and not session.save_store.has_save(), "standalone exit creates no save")
	menu.free()
	navigation.free()
	session.free()
	await get_tree().process_frame

func _check_map_roundtrip() -> void:
	var session := AdventureSessionService.new()
	session.save_store = AdventureSaveStore.new("main_menu_diagnostic_map_return")
	session.save_store.delete_save()
	session.start_new_game(821)
	var navigation := GameNavigationService.new()
	navigation.session = session
	add_child(navigation)
	navigation.scene_switcher = func(_path: String) -> Error: return OK
	var scene := load("res://scenes/adventure_map_scene.tscn").instantiate() as AdventureMapScene
	scene.session = session
	scene.set("navigation", navigation)
	add_child(scene)
	await get_tree().process_frame
	_check(scene.find_child("MainMenuButton", true, false) != null, "map offers return")
	_check(scene.find_child("ModalMainMenuButton", true, false) != null, "forced modal also offers return")
	var danger := session.current_run.floor_state.danger
	var rng := session.current_run.shop_rng_state
	var room_id := session.current_run.floor_state.current_room_id
	for transaction_type in [AdventureEnums.TransactionType.EVENT, AdventureEnums.TransactionType.REWARD]:
		session.current_run.begin_transaction(transaction_type, "held_choice", {"room_id": room_id})
		var before := JSON.stringify(session.current_run.pending_transaction.to_dict())
		_check(session.prepare_return_to_menu(false).ok, "save pending choice on return")
		_check(session.prepare_continue().ok, "continue pending choice")
		_check(JSON.stringify(session.current_run.pending_transaction.to_dict()) == before, "pending choice survives")
		_check(session.current_run.floor_state.danger == danger and session.current_run.shop_rng_state == rng, "return is not exploration")
	scene.free()
	navigation.free()
	session.save_store.delete_save()
	session.free()

func _check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		printerr("MAIN_MENU_RETURN: " + label)
