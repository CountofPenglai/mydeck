extends PopupPanel
class_name BattleUnitTargetPicker

signal target_submitted(target: BattleUnitState)
signal selection_cancelled

var _list := VBoxContainer.new()
var _scroll := ScrollContainer.new()
var _choice

func _ready() -> void:
	title = "选择打击目标"
	exclusive = true
	popup_hide.connect(_on_popup_hidden)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)
	_list.custom_minimum_size = Vector2(360, 0)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(_scroll)
	_scroll.add_child(_list)

func show_choice(choice) -> void:
	_choice = choice
	if _choice == null:
		hide()
		return
	_clear()
	var label := Label.new()
	label.text = str(_choice.prompt)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list.add_child(label)
	for target in _choice.get_live_targets():
		var button := Button.new()
		button.text = target.get_display_name()
		button.pressed.connect(_submit.bind(target))
		_list.add_child(button)
	var stop := Button.new()
	stop.text = "结束"
	stop.pressed.connect(_submit.bind(null))
	_list.add_child(stop)
	_present_choice()


func _present_choice() -> void:
	if not visible:
		popup_centered(BattleChoicePopupLayout.size_for(self, _scroll, _list))
	call_deferred("_resize_and_center")


func _resize_and_center() -> void:
	if _choice == null:
		return
	BattleChoicePopupLayout.resize_and_center(self, BattleChoicePopupLayout.size_for(self, _scroll, _list))

func _submit(target: BattleUnitState = null) -> void:
	# The submission signal can synchronously resume the action and request its
	# next target. Keep the active choice intact until BattleScene refreshes us,
	# otherwise this callback can erase or hide the successor popup.
	target_submitted.emit(target)

func _on_popup_hidden() -> void:
	if _choice != null:
		_choice = null
		selection_cancelled.emit()

func _clear() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
