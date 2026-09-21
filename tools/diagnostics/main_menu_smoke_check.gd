extends Node

var failures := 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	if not OS.get_cmdline_user_args().has("--main-menu-diagnostics"):
		printerr("MAIN_MENU_SMOKE: isolated diagnostic flag required")
		get_tree().quit(1)
		return
	# Keep the driver outside current_scene while testing real scene replacement.
	get_tree().current_scene = null
	var session := get_node("/root/AdventureSession") as AdventureSessionService
	var navigation := get_node("/root/GameNavigation") as GameNavigationService
	session.save_store.delete_save()
	session.current_run = session.save_store.load_run()
	navigation.switch_to(AdventureRunLifecycle.MAIN_MENU_PATH)
	await get_tree().scene_changed
	var menu := get_tree().current_scene as MainMenuScene
	_check(menu != null and menu.continue_button.disabled, "boots main menu without creating game")
	menu.start_button.pressed.emit()
	await get_tree().scene_changed
	var map := get_tree().current_scene as AdventureMapScene
	_check(map != null and session.current_run != null, "start button enters saved adventure")
	var run := session.current_run
	var room := run.floor_state.get_adjacent_rooms(run.floor_state.current_room_id)[0]
	room.room_type = AdventureEnums.RoomType.NORMAL_BATTLE
	_check(session.request_move(room.room_id).ok, "enter combat tile")
	var bytes := FileAccess.get_file_as_string(session.save_store.save_path)
	var health := session.current_run.party[0].current_health
	_check(session.resume_pending_battle(), "actual encounter scene opens")
	await get_tree().scene_changed
	var battle := get_tree().current_scene as BattleScene
	_check(battle != null and battle.get_menu_return_state().ok, "battle return available at deployment")
	battle.controller.player_units[0].character_state.current_health = 7
	battle._open_battle_menu()
	battle._menu_return.request_return()
	battle._menu_return.confirmation.confirmed.emit()
	await get_tree().scene_changed
	menu = get_tree().current_scene as MainMenuScene
	_check(menu != null and not menu.continue_button.disabled, "battle returns to continuable menu")
	_check(FileAccess.get_file_as_string(session.save_store.save_path) == bytes, "return leaves checkpoint bytes intact")
	menu.continue_button.pressed.emit()
	await get_tree().scene_changed
	battle = get_tree().current_scene as BattleScene
	_check(battle != null and battle.controller.player_units[0].get_current_health() == health, "continue restores pre-battle health")
	battle._menu_return.request_return()
	battle._menu_return.confirmation.confirmed.emit()
	await get_tree().scene_changed
	menu = get_tree().current_scene as MainMenuScene
	_check(menu != null, "second return still works")
	session.save_store.delete_save()
	print("MAIN_MENU_SMOKE: %s" % ("PASS" if failures == 0 else "FAIL"))
	if failures > 0:
		get_tree().quit(1)
	else:
		menu.find_child("QuitGameButton", true, false).pressed.emit()

func _check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		printerr("MAIN_MENU_SMOKE: " + label)
