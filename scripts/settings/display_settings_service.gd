extends Node
class_name DisplaySettingsService

signal settings_changed
signal preview_changed

const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const DEFAULTS := {"fullscreen": false, "resolution": Vector2i(1280, 720)}

var config_path := "user://display_settings.cfg"
var backend: DisplaySettingsBackend
var confirmation_timer: Timer
var preview_active := false
var _confirmed: Dictionary = DEFAULTS.duplicate()
var _candidate: Dictionary = {}


func _ready() -> void:
	if self == get_node_or_null("/root/DisplaySettings") and OS.get_cmdline_user_args().has("--main-menu-diagnostics"):
		config_path = "user://main_menu_diagnostic_display_autoload.cfg"
	if backend == null:
		backend = DisplaySettingsBackend.new()
	confirmation_timer = Timer.new()
	confirmation_timer.wait_time = 15.0
	confirmation_timer.one_shot = true
	confirmation_timer.timeout.connect(cancel_preview)
	add_child(confirmation_timer)
	load_settings()


func _exit_tree() -> void:
	if preview_active:
		cancel_preview()


func get_settings() -> Dictionary:
	return _confirmed.duplicate()


func reset_draft() -> Dictionary:
	return DEFAULTS.duplicate()


func load_settings() -> Dictionary:
	if preview_active:
		cancel_preview()
	var config := ConfigFile.new()
	var loaded := {}
	if config.load(config_path) == OK:
		var width: Variant = config.get_value("display", "width", null)
		var height: Variant = config.get_value("display", "height", null)
		if width is int and height is int:
			loaded = _validated({
				"fullscreen": config.get_value("display", "fullscreen", null),
				"resolution": Vector2i(width, height),
			})
	_confirmed = DEFAULTS.duplicate() if loaded.is_empty() else loaded
	backend.apply(_confirmed)
	settings_changed.emit()
	return get_settings()


func preview(settings: Dictionary) -> Dictionary:
	var validated := _validated(settings)
	if validated.is_empty():
		return {"ok": false, "message": "请选择支持的显示模式与分辨率。"}
	_candidate = validated
	preview_active = true
	backend.apply(_candidate)
	confirmation_timer.start()
	preview_changed.emit()
	return {"ok": true, "message": ""}


func confirm_preview() -> Dictionary:
	if not preview_active:
		return {"ok": false, "message": "没有待确认的显示设置。"}
	var config := ConfigFile.new()
	config.set_value("display", "fullscreen", _candidate.fullscreen)
	config.set_value("display", "width", _candidate.resolution.x)
	config.set_value("display", "height", _candidate.resolution.y)
	var temporary := config_path + ".tmp"
	var error := config.save(temporary)
	if error == OK:
		error = DirAccess.rename_absolute(temporary, config_path)
	if error != OK:
		cancel_preview()
		return {"ok": false, "message": "保存显示设置失败，已恢复原设置：%s" % error_string(error)}
	_confirmed = _candidate.duplicate()
	_candidate.clear()
	preview_active = false
	confirmation_timer.stop()
	settings_changed.emit()
	preview_changed.emit()
	return {"ok": true, "message": "显示设置已保存。"}


func cancel_preview() -> void:
	if not preview_active:
		return
	preview_active = false
	confirmation_timer.stop()
	_candidate.clear()
	backend.apply(_confirmed)
	preview_changed.emit()


func _validated(settings: Dictionary) -> Dictionary:
	if not (settings.get("fullscreen") is bool) or not (settings.get("resolution") is Vector2i):
		return {}
	if not RESOLUTIONS.has(settings.resolution):
		return {}
	return {"fullscreen": settings.fullscreen, "resolution": settings.resolution}
