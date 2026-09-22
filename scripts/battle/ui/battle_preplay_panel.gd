extends PopupPanel
class_name BattlePreplayPanel

signal configuration_confirmed(configuration: Dictionary)
signal configuration_cancelled

var _list := VBoxContainer.new()
var _indices: Array[int] = []
var _option_values: Array = []
var _element: int = BattleSurfaceState.Element.FIRE
var _resonance := false
var _minimum := 0
var _maximum := 0
var _configuration_active := false


func _ready() -> void:
	title = "配置卡牌效果"
	exclusive = true
	popup_hide.connect(_on_popup_hidden)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)
	_list.custom_minimum_size = Vector2(340, 0)
	margin.add_child(_list)


func show_configuration(spec: Dictionary) -> void:
	_configuration_active = true
	_indices.clear()
	_option_values = spec.get("option_values", []) as Array
	_element = BattleSurfaceState.Element.FIRE
	_resonance = false
	_minimum = int(spec.get("minimum", 0))
	_maximum = int(spec.get("maximum", 0))
	_clear_children()
	var heading := Label.new()
	heading.text = str(spec.get("title", "配置卡牌效果"))
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list.add_child(heading)
	if bool(spec.get("requires_element", false)):
		var element_picker := OptionButton.new()
		for base_element in BattleSurfaceState.BASE_ELEMENTS:
			element_picker.add_item(BattleSurfaceState.label(base_element), int(base_element))
		element_picker.item_selected.connect(func(index: int) -> void: _element = element_picker.get_item_id(index))
		_list.add_child(element_picker)
	var options: Array = spec.get("options", []) as Array
	for index in range(options.size()):
		var toggle := CheckBox.new()
		toggle.text = str(options[index])
		toggle.toggled.connect(_on_option_toggled.bind(index))
		_list.add_child(toggle)
	var resonance_cost := int(spec.get("resonance_cost", 0))
	if resonance_cost > 0:
		var resonance := CheckBox.new()
		resonance.text = "支付%d点法力共鸣（可多选）" % resonance_cost
		resonance.toggled.connect(func(enabled: bool) -> void: _resonance = enabled)
		_list.add_child(resonance)
	var confirm := Button.new()
	confirm.text = "确认"
	confirm.pressed.connect(_submit)
	_list.add_child(confirm)
	var cancel := Button.new()
	cancel.text = "取消"
	cancel.pressed.connect(_cancel)
	_list.add_child(cancel)
	popup_centered()


func _on_option_toggled(enabled: bool, index: int) -> void:
	if enabled and not _indices.has(index):
		_indices.append(index)
	elif not enabled:
		_indices.erase(index)


func _submit() -> void:
	var maximum := _maximum if _resonance else mini(1, _maximum)
	if _indices.size() < _minimum or _indices.size() > maximum:
		return
	var selected_values: Array = []
	for index in _indices:
		if index >= 0 and index < _option_values.size():
			selected_values.append(_option_values[index])
	var configuration := {
		"choice_indices": _indices.duplicate(),
		"selected_option_values": selected_values,
		"selected_element": _element,
		"pay_resonance": _resonance,
	}
	_configuration_active = false
	hide()
	configuration_confirmed.emit(configuration)


func _cancel() -> void:
	_configuration_active = false
	hide()
	configuration_cancelled.emit()


func _on_popup_hidden() -> void:
	_indices.clear()
	if _configuration_active:
		_configuration_active = false
		configuration_cancelled.emit()


func _clear_children() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
