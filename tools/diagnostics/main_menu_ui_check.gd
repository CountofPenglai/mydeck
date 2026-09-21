extends Node

var failures := 0

func _ready() -> void:
	if not ResourceLoader.exists("res://scenes/main_menu_scene.tscn"):
		_check(false, "main menu entry missing")
	else:
		await _exercise_menu()
	print("MAIN_MENU_UI: %s" % ("PASS" if failures == 0 else "FAIL"))
	if failures == 0 and OS.get_cmdline_user_args().has("--test-menu-quit"):
		var menu: Control = load("res://scenes/main_menu_scene.tscn").instantiate()
		add_child(menu)
		menu.find_child("QuitGameButton", true, false).pressed.emit()
		return
	get_tree().quit(0 if failures == 0 else 1)

func _exercise_menu() -> void:
	var session := AdventureSessionService.new()
	session.save_store = AdventureSaveStore.new("main_menu_diagnostic_ui", "main_menu_diagnostic_ui_legacy")
	session.save_store.delete_save()
	var navigation: Node = load("res://scripts/menu/game_navigation.gd").new()
	navigation.session = session
	add_child(navigation)
	var paths: Array[String] = []
	navigation.scene_switcher = func(path: String) -> Error:
		paths.append(path)
		return OK
	var scene: Control = load("res://scenes/main_menu_scene.tscn").instantiate()
	scene.session = session
	scene.navigation = navigation
	add_child(scene)
	await get_tree().process_frame
	for button_name in ["StartGameButton", "ContinueGameButton", "CardEncyclopediaButton", "SettingsButton", "QuitGameButton"]:
		_check(scene.find_child(button_name, true, false) != null, "entry exists: " + button_name)
	var resume := scene.find_child("ContinueGameButton", true, false) as Button
	_check(resume.disabled, "no save disables continue")
	_check(session.current_run == null and not session.save_store.has_save(), "opening menu never creates run")
	session.start_new_game(444)
	scene.refresh_state()
	_check(not resume.disabled, "valid run enables continue")
	var bytes := FileAccess.get_file_as_string(session.save_store.save_path)
	scene.find_child("StartGameButton", true, false).pressed.emit()
	_check(scene.new_game_confirmation.visible, "existing save asks confirmation")
	scene.new_game_confirmation.canceled.emit()
	scene.new_game_confirmation.hide()
	_check(FileAccess.get_file_as_string(session.save_store.save_path) == bytes, "cancel preserves progress")
	resume.pressed.emit()
	var result: Dictionary = navigation.start_game(true)
	_check(not result.ok and paths.size() == 1, "repeated transition cannot overwrite game")
	_check(FileAccess.get_file_as_string(session.save_store.save_path) == bytes, "duplicate start has no save side effect")
	get_tree().scene_changed.emit()
	navigation.scene_switcher = func(_path: String) -> Error: return ERR_CANT_OPEN
	result = navigation.continue_game()
	_check(not result.ok and not navigation.transitioning, "failed switch unlocks controls")
	scene.free()
	navigation.free()
	session.save_store.delete_save()
	session.free()

func _check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		printerr("MAIN_MENU_UI: " + label)
