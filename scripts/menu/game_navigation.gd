extends Node
class_name GameNavigationService

signal transition_changed

var session: AdventureSessionService
var scene_switcher: Callable
var transitioning := false


func _ready() -> void:
	if session == null:
		session = get_node_or_null("/root/AdventureSession") as AdventureSessionService
	if not scene_switcher.is_valid():
		scene_switcher = get_tree().change_scene_to_file
	get_tree().scene_changed.connect(_scene_changed)


func start_game(confirmed: bool = false) -> Dictionary:
	if transitioning or session == null:
		return _failure("正在切换场景，请稍候。")
	return _route(session.start_new_game(0, confirmed))


func continue_game() -> Dictionary:
	if transitioning or session == null:
		return _failure("正在切换场景，请稍候。")
	return _route(session.prepare_continue())


func return_to_menu(from_battle: bool) -> Dictionary:
	if transitioning or session == null:
		return _failure("正在切换场景，请稍候。")
	return _route(session.prepare_return_to_menu(from_battle))


func switch_to(scene_path: String) -> Dictionary:
	if transitioning:
		return _failure("正在切换场景，请稍候。")
	if not ResourceLoader.exists(scene_path) or not scene_switcher.is_valid():
		return _failure("无法找到目标页面。")
	transitioning = true
	transition_changed.emit()
	var error: Error = scene_switcher.call(scene_path)
	if error != OK:
		transitioning = false
		transition_changed.emit()
		return _failure("无法打开页面：%s" % error_string(error))
	return {"ok": true, "message": "", "scene_path": scene_path}


func _route(result: Dictionary) -> Dictionary:
	return switch_to(str(result.scene_path)) if result.ok else result


func _scene_changed() -> void:
	transitioning = false
	transition_changed.emit()


func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message, "scene_path": ""}
