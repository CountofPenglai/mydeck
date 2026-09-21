extends Node

const OUTPUT := "res://docs/superpowers/reports/main-menu"
var failures := 0

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("MAIN_MENU_VISUAL: requires a rendered viewport")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var session := AdventureSessionService.new()
	session.save_store = AdventureSaveStore.new("main_menu_diagnostic_visual", "main_menu_diagnostic_visual_legacy")
	session.save_store.delete_save()
	var navigation := GameNavigationService.new()
	navigation.session = session
	add_child(navigation)
	navigation.scene_switcher = func(_path: String) -> Error: return OK
	var menu := preload("res://scenes/main_menu_scene.tscn").instantiate() as MainMenuScene
	menu.session = session
	menu.navigation = navigation
	add_child(menu)
	await _capture("main-menu-1280.png", Vector2i(1280, 720))
	_check(_fits(menu.find_child("QuitGameButton", true, false)), "all five actions fit at baseline")
	_check(session.start_new_game(20260921).ok, "visual fixture starts a fresh isolated run")
	await _capture("main-menu-1920.png", Vector2i(1920, 1080))
	menu.encyclopedia_button.pressed.emit()
	await _capture("encyclopedia-1280.png", Vector2i(1280, 720))
	var encyclopedia := menu.page as CardEncyclopedia
	_check(_fits(encyclopedia.card_list), "catalog list fits")
	await _capture("encyclopedia-1920.png", Vector2i(1920, 1080))
	_check(_fits(encyclopedia.card_list), "catalog list fits wide viewport")
	encyclopedia.show_card(load("res://resources/cards/druid_bloodwood_covenant.tres"), true)
	await _capture("encyclopedia-reverse-1280.png", Vector2i(1280, 720))
	_check(_fits(encyclopedia.detail_title), "reverse title fits")
	encyclopedia.back_requested.emit()
	await get_tree().process_frame
	menu.settings_button.pressed.emit()
	await _capture("settings-1280.png", Vector2i(1280, 720))
	var settings := menu.page as SettingsPanel
	await _capture("settings-1920.png", Vector2i(1920, 1080))
	_check(_fits(settings.resolution), "settings fit wide viewport")
	settings._apply()
	await _capture("settings-confirm-1280.png", Vector2i(1280, 720))
	_check(settings.confirmation.visible, "display preview asks confirmation")
	settings.service.cancel_preview()
	settings.back_requested.emit()
	await get_tree().process_frame
	menu.free()
	var map := preload("res://scenes/adventure_map_scene.tscn").instantiate() as AdventureMapScene
	map.session = session
	map.navigation = navigation
	add_child(map)
	await _capture("map-return-1280.png", Vector2i(1280, 720))
	_check(_fits(map.find_child("MainMenuButton", true, false)), "map return fits")
	await _capture("map-return-1920.png", Vector2i(1920, 1080))
	_check(_fits(map.find_child("MainMenuButton", true, false)), "map return fits wide viewport")
	map.free()
	# Bind the battle scene to an isolated, saved encounter rather than a sample-only route.
	var global_session := get_node("/root/AdventureSession") as AdventureSessionService
	var old_store := global_session.save_store
	global_session.save_store = session.save_store
	global_session.current_run = session.current_run
	var room := session.current_run.floor_state.get_adjacent_rooms(session.current_run.floor_state.current_room_id)[0]
	room.room_type = AdventureEnums.RoomType.NORMAL_BATTLE
	var payload := AdventureBattleSetupService.create_payload(session.current_run, room, AdventureEnums.EncounterTier.WEAK)
	session.current_run.begin_transaction(AdventureEnums.TransactionType.BATTLE, "visual_battle", payload)
	session.save_store.save_run(session.current_run)
	global_session.prepare_continue()
	var battle := preload("res://scenes/battle_scene.tscn").instantiate() as BattleScene
	add_child(battle)
	await get_tree().process_frame
	battle._open_battle_menu()
	await _capture("battle-menu-1280.png", Vector2i(1280, 720))
	_check(_fits(battle._menu_return.return_button), "battle return button fits")
	await _capture("battle-menu-1920.png", Vector2i(1920, 1080))
	_check(_fits(battle._menu_return.return_button), "battle return fits wide viewport")
	battle._menu_return.request_return()
	await _capture("battle-return-confirm-1280.png", Vector2i(1280, 720))
	_check(battle._menu_return.confirmation.visible, "battle restart boundary explained")
	battle.free()
	global_session.current_run = null
	global_session.pending_battle_scenario = null
	global_session.save_store = old_store
	session.save_store.delete_save()
	session.free()
	navigation.free()
	print("MAIN_MENU_VISUAL: %s" % ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)

func _capture(filename: String, dimensions: Vector2i) -> void:
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = dimensions
	get_window().content_scale_size = dimensions
	for frame in range(5):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var screenshot := get_viewport().get_texture().get_image()
	_check(screenshot.save_png(OUTPUT.path_join(filename)) == OK, "screenshot " + filename)

func _fits(control: Control) -> bool:
	var rect := control.get_global_rect()
	return rect.position.x >= 0 and rect.position.y >= 0 and rect.end.x <= get_viewport().get_visible_rect().size.x + 1 and rect.end.y <= get_viewport().get_visible_rect().size.y + 1

func _check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		printerr("MAIN_MENU_VISUAL: " + label)
