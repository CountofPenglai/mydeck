extends Control

const ENTRIES := [
	[&"gray_shield_guard", &"base"],
	[&"holy_spearman", &"base"],
	[&"fortress_crossbow", &"base"],
	[&"field_priest", &"base"],
	[&"punishment_knight", &"base"],
	[&"standard_bearer", &"base"],
	[&"holy_bastion_commander", &"base"],
	[&"creation_shard", &"base"],
	[&"blood_construct", &"base"],
	[&"blood_construct", &"inverted"],
	[&"flesh_spawn", &"base"],
	[&"corrupt_heart_veil", &"base"],
	[&"corrupt_heart_veil", &"phase_two"],
	[&"gray_bastion_paladin", &"base"],
	[&"triumph_statue", &"base"],
	[&"military_god_remains", &"base"],
]
const MIN_CAPTURE_SIZE := Vector2i(1232, 896)

var _exit_code := 0


func _ready() -> void:
	_build_contact_sheet()
	await get_tree().process_frame
	await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		_fail("viewport capture is empty")
	elif image.get_width() < MIN_CAPTURE_SIZE.x or image.get_height() < MIN_CAPTURE_SIZE.y:
		_fail("viewport capture is too small: %dx%d, expected at least %dx%d" % [
			image.get_width(),
			image.get_height(),
			MIN_CAPTURE_SIZE.x,
			MIN_CAPTURE_SIZE.y,
		])
	else:
		var error := image.save_png("user://chapter_two_enemy_art_preview.png")
		if error != OK:
			_fail("could not save preview: %s" % error_string(error))
	print("CHAPTER_TWO_ENEMY_ART_VISUAL: completed")
	get_tree().quit(_exit_code)


func _build_contact_sheet() -> void:
	var background := ColorRect.new()
	background.color = Color("171311")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	background.add_child(grid)
	for entry in ENTRIES:
		_add_entry(grid, entry[0] as StringName, entry[1] as StringName)


func _add_entry(grid: GridContainer, archetype: StringName, variant: StringName) -> void:
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(296, 212)
	grid.add_child(panel)
	var label := Label.new()
	label.text = "%s\n%s" % [String(archetype).replace("_", " "), variant]
	label.custom_minimum_size = Vector2(288, 36)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(label)
	var art_row := HBoxContainer.new()
	art_row.add_theme_constant_override("separation", 8)
	panel.add_child(art_row)
	for kind in ["portrait", "battle"]:
		var texture := ChapterTwoEnemyCatalog.get_art_texture(archetype, kind, variant)
		if texture == null:
			_fail("missing %s/%s/%s" % [archetype, variant, kind])
		var rect := TextureRect.new()
		rect.custom_minimum_size = Vector2(140, 170)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.texture = texture
		art_row.add_child(rect)


func _fail(message: String) -> void:
	_exit_code = 1
	push_error("CHAPTER_TWO_ENEMY_ART_VISUAL: " + message)
