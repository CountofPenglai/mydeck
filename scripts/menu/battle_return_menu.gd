extends VBoxContainer
class_name BattleReturnMenu

signal returned

var navigation: GameNavigationService
var safety_probe: Callable
var confirmation: ConfirmationDialog
var return_button: Button
var feedback: Label


func _ready() -> void:
	if navigation == null:
		navigation = get_node_or_null("/root/GameNavigation") as GameNavigationService
	return_button = Button.new()
	return_button.name = "ReturnToMainMenuButton"
	return_button.text = "返回主菜单"
	return_button.custom_minimum_size.y = 44
	return_button.pressed.connect(request_return)
	add_child(return_button)
	feedback = Label.new()
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback.add_theme_font_size_override("font_size", 16)
	add_child(feedback)
	confirmation = ConfirmationDialog.new()
	confirmation.title = "返回主菜单"
	confirmation.ok_button_text = "返回主菜单"
	confirmation.cancel_button_text = "留在战斗"
	confirmation.confirmed.connect(_confirm_return)
	add_child(confirmation)


func _process(_delta: float) -> void:
	if is_visible_in_tree() and safety_probe.is_valid():
		var state: Dictionary = safety_probe.call()
		return_button.disabled = not state.ok or navigation == null or navigation.transitioning
		return_button.tooltip_text = state.message
		if not state.ok:
			feedback.text = state.message


func request_return() -> void:
	if not safety_probe.is_valid() or navigation == null or navigation.transitioning:
		return
	var state: Dictionary = safety_probe.call()
	if not state.ok:
		feedback.text = state.message
		return
	confirmation.dialog_text = "返回后，本场战斗中的进度将不保留。\n继续游戏将从本场战斗开始恢复，敌群、危险度和词缀保持不变。"
	if state.get("standalone", false):
		confirmation.dialog_text = "这是独立测试战斗，没有对应的冒险检查点。\n返回后无法继续本场战斗。已有冒险存档不受影响。"
	confirmation.popup_centered(Vector2i(640, 210))


func _confirm_return() -> void:
	if not safety_probe.is_valid() or navigation == null or navigation.transitioning:
		return
	var state: Dictionary = safety_probe.call()
	if not state.ok:
		feedback.text = state.message
		return
	var result := navigation.switch_to(AdventureRunLifecycle.MAIN_MENU_PATH) if state.get("standalone", false) else navigation.return_to_menu(true)
	if result.ok:
		returned.emit()
	else:
		feedback.text = result.message
