extends Node

var failures := 0
const CONFIG := "user://main_menu_diagnostic_display.cfg"

func _ready() -> void:
	if not ResourceLoader.exists("res://scripts/settings/display_settings_service.gd"):
		_check(false, "display settings service missing")
	else:
		await _exercise_settings()
	print("DISPLAY_SETTINGS: %s" % ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)

func _exercise_settings() -> void:
	if FileAccess.file_exists(CONFIG):
		DirAccess.remove_absolute(CONFIG)
	var service: Node = load("res://scripts/settings/display_settings_service.gd").new()
	service.config_path = CONFIG
	add_child(service)
	var initial: Dictionary = service.get_settings()
	_check(initial == {"fullscreen": false, "resolution": Vector2i(1280, 720)}, "safe missing-file default")
	service.preview({"fullscreen": true, "resolution": Vector2i(1600, 900)})
	_check(not FileAccess.file_exists(CONFIG), "preview does not persist")
	service.cancel_preview()
	_check(service.get_settings() == initial and not service.preview_active, "cancel restores confirmed state")
	service.confirmation_timer.wait_time = 0.02
	service.preview({"fullscreen": true, "resolution": Vector2i(1920, 1080)})
	await get_tree().create_timer(0.08).timeout
	_check(not service.preview_active and service.get_settings() == initial, "timeout reverts")
	service.preview({"fullscreen": false, "resolution": Vector2i(1600, 900)})
	_check(service.confirm_preview().ok, "confirmed preview persists")
	var bytes := FileAccess.get_file_as_string(CONFIG)
	service.preview({"fullscreen": true, "resolution": Vector2i(1920, 1080)})
	service.preview({"fullscreen": false, "resolution": Vector2i(1280, 720)})
	service.cancel_preview()
	_check(service.get_settings().resolution == Vector2i(1600, 900), "multiple previews keep original confirmed state")
	_check(FileAccess.get_file_as_string(CONFIG) == bytes, "cancel never writes")
	service.load_settings()
	_check(service.get_settings().resolution == Vector2i(1600, 900), "restart reads confirmed choice")
	_check(not service.preview({"fullscreen": "yes", "resolution": Vector2i(12, 34)}).ok, "invalid draft rejected")
	var page: Control = load("res://scenes/ui/settings_panel.tscn").instantiate()
	page.service = service
	add_child(page)
	service.preview({"fullscreen": true, "resolution": Vector2i(1920, 1080)})
	page.free()
	_check(not service.preview_active and service.get_settings().resolution == Vector2i(1600, 900), "leaving page cancels preview")
	service.config_path = "user://main_menu_diagnostic_nonexistent_folder/settings.cfg"
	service.preview({"fullscreen": true, "resolution": Vector2i(1920, 1080)})
	_check(not service.confirm_preview().ok, "failed write rejected")
	_check(not service.preview_active and not service.get_settings().fullscreen, "failed save rolls back")
	_check(FileAccess.get_file_as_string(CONFIG) == bytes, "failed save preserves valid config")
	service.config_path = CONFIG
	var config := ConfigFile.new()
	config.set_value("display", "fullscreen", 12)
	config.set_value("display", "width", -100)
	config.set_value("display", "height", 0)
	config.save(CONFIG)
	service.load_settings()
	_check(service.get_settings() == initial, "corrupt values safely default")
	service.free()
	DirAccess.remove_absolute(CONFIG)

func _check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		printerr("DISPLAY_SETTINGS: " + label)
