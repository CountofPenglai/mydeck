extends VBoxContainer
class_name AdventureScoutPicker

signal confirmed(room_ids: Array[String])

var _choices: Array[CheckBox] = []


func configure(floor: AdventureFloorState, candidate_ids: Array[String]) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_choices.clear()
	var hint := Label.new()
	hint.text = "选择时仅显示背面；确认后揭示所选正面，但不视为探索。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)
	for room_id in candidate_ids:
		var room := floor.get_room(room_id)
		if room == null:
			continue
		var choice := CheckBox.new()
		choice.text = "%s  (%d, %d)" % [AdventureEnums.back_type_label(room.back_type), room.cell.x, room.cell.y]
		choice.set_meta("room_id", room_id)
		add_child(choice)
		_choices.append(choice)
	var confirm := Button.new()
	confirm.text = "确认侦察"
	confirm.pressed.connect(_confirm)
	add_child(confirm)


func _confirm() -> void:
	var room_ids: Array[String] = []
	for choice in _choices:
		if choice.button_pressed:
			room_ids.append(str(choice.get_meta("room_id", "")))
	confirmed.emit(room_ids)
