extends RefCounted
class_name DisplaySettingsBackend


func get_usable_size() -> Vector2i:
	if DisplayServer.get_name() == "headless":
		return Vector2i(1920, 1080)
	return DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen()).size


func apply(settings: Dictionary) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if bool(settings.fullscreen):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var requested: Vector2i = settings.resolution
	var fitted := Vector2i(mini(requested.x, usable.size.x), mini(requested.y, usable.size.y))
	DisplayServer.window_set_size(fitted)
	DisplayServer.window_set_position(usable.position + (usable.size - fitted) / 2)
