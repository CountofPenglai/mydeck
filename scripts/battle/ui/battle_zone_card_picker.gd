extends PopupPanel
class_name BattleZoneCardPicker


signal selection_submitted(selected: Array[CardData])
signal selection_cancelled
signal zone_browsed(zone: String)

var _list := VBoxContainer.new()
var _selected: Array[CardData] = []
var _choice
var _active_zone: String = ""


func _ready() -> void:
	title = "选择卡牌"
	exclusive = true
	popup_hide.connect(_on_popup_hidden)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)
	_list.custom_minimum_size = Vector2(360, 0)
	margin.add_child(_list)


func show_choice(choice) -> void:
	if choice != _choice:
		_selected.clear()
		_active_zone = "discard" if choice != null and choice.zones.has("discard") else (str(choice.zones[0]) if choice != null and not choice.zones.is_empty() else "")
	_choice = choice
	if _choice == null:
		hide()
		return
	var live_cards: Array[CardData] = _choice.get_live_cards()
	var visible_cards: Array[CardData] = _cards_for_zone(_active_zone)
	for card in _selected.duplicate():
		if not live_cards.has(card):
			_selected.erase(card)
	_clear_list()
	var prompt := Label.new()
	prompt.text = str(_choice.prompt)
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list.add_child(prompt)
	if _choice.zones.size() > 1:
		for zone in _choice.zones:
			var browse := Button.new()
			browse.text = "查看牌库" if zone == "draw" else "查看弃牌堆"
			browse.disabled = zone == _active_zone
			browse.pressed.connect(_browse_zone.bind(str(zone)))
			_list.add_child(browse)
	for card in visible_cards:
		var toggle := CheckBox.new()
		toggle.text = "%s | %s" % [card.card_name, card.get_card_type_label()]
		toggle.button_pressed = _selected.has(card)
		toggle.disabled = _selected.size() >= int(_choice.max_count) and not toggle.button_pressed
		toggle.toggled.connect(_on_card_toggled.bind(card))
		_list.add_child(toggle)
	var confirm := Button.new()
	confirm.text = "确认"
	confirm.disabled = _selected.size() < int(_choice.min_count)
	confirm.pressed.connect(_submit_selection)
	_list.add_child(confirm)
	if int(_choice.min_count) == 0:
		var skip := Button.new()
		skip.text = "跳过"
		skip.pressed.connect(_skip_selection)
		_list.add_child(skip)
	var cancel := Button.new()
	cancel.text = "取消"
	cancel.pressed.connect(_cancel_selection)
	_list.add_child(cancel)
	if not visible:
		popup_centered()


func _on_card_toggled(pressed: bool, card: CardData) -> void:
	if pressed and not _selected.has(card):
		_selected.append(card)
	elif not pressed:
		_selected.erase(card)
	show_choice(_choice)


func _submit_selection() -> void:
	var selected: Array[CardData] = []
	selected.assign(_selected)
	_selected.clear()
	_choice = null
	selection_submitted.emit(selected)


func _skip_selection() -> void:
	var selected: Array[CardData] = []
	_selected.clear()
	_choice = null
	selection_submitted.emit(selected)


func _browse_zone(zone: String) -> void:
	_active_zone = zone
	if zone == "draw":
		zone_browsed.emit(zone)
	show_choice(_choice)


func _cancel_selection() -> void:
	_selected.clear()
	_choice = null
	selection_cancelled.emit()


func _cards_for_zone(zone: String) -> Array[CardData]:
	var cards: Array[CardData] = []
	if _choice == null or _choice.owner == null:
		return cards
	match zone:
		"hand": cards.assign(_choice.owner.hand)
		"draw": cards.assign(_choice.owner.draw_pile)
		"discard": cards.assign(_choice.owner.discard_pile)
		"mana": cards.assign(_choice.owner.mana_zone)
	var live_cards: Array[CardData] = _choice.get_live_cards()
	for card in cards.duplicate():
		if not live_cards.has(card): cards.erase(card)
	return cards


func _on_popup_hidden() -> void:
	if _choice == null:
		return
	_selected.clear()
	_choice = null
	selection_cancelled.emit()


func _clear_list() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
