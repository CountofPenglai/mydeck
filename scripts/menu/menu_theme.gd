extends RefCounted
class_name MenuTheme

const PAPER := preload("res://assets/art/adventure/hex_tiles/parchment_base.png")
const INK := Color("#24231f")
const MUTED := Color("#615a49")
const ACCENT := Color("#7f402b")


static func create_theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 19
	for type in ["Label", "RichTextLabel", "Button", "OptionButton", "LineEdit", "CheckButton"]:
		result.set_color("font_color", type, INK)
		result.set_color("font_hover_color", type, INK)
		result.set_color("font_pressed_color", type, INK)
		result.set_color("font_focus_color", type, INK)
		result.set_color("font_disabled_color", type, Color("#8c8371"))
	for type in ["Button", "OptionButton"]:
		result.set_stylebox("normal", type, box(Color("#ded0aa"), Color("#514b3b")))
		result.set_stylebox("hover", type, box(Color("#f5e6bd"), INK))
		result.set_stylebox("pressed", type, box(Color("#c8b482"), ACCENT))
		result.set_stylebox("disabled", type, box(Color("#c4b99e"), Color("#9c9179")))
		var focus := box(Color.TRANSPARENT, ACCENT, 3)
		result.set_stylebox("focus", type, focus)
	result.set_stylebox("normal", "LineEdit", box(Color("#f2e4c0"), MUTED))
	result.set_stylebox("focus", "LineEdit", box(Color.TRANSPARENT, ACCENT, 2))
	result.set_color("caret_color", "LineEdit", INK)
	result.set_color("font_placeholder_color", "LineEdit", MUTED)
	result.set_color("default_color", "RichTextLabel", INK)
	result.set_stylebox("panel", "PanelContainer", box(Color("#e3d4ad"), Color("#5c5340")))
	result.set_stylebox("panel", "PopupMenu", box(Color("#eadbb8"), INK))
	result.set_color("font_color", "PopupMenu", INK)
	result.set_stylebox("panel", "AcceptDialog", box(Color("#eadbb8"), INK))
	result.set_constant("separation", "VBoxContainer", 12)
	result.set_constant("separation", "HBoxContainer", 18)
	return result


static func box(fill: Color, border: Color, width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(3)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


static func background(parent: Control) -> void:
	var texture := TextureRect.new()
	texture.texture = PAPER
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	texture.modulate = Color("#cfbd94")
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(texture)


static func margin(parent: Control, padding: int = 32) -> MarginContainer:
	var result := MarginContainer.new()
	result.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		result.add_theme_constant_override("margin_" + edge, padding)
	parent.add_child(result)
	return result


static func label(text: String, font_size: int = 19) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	return result


static func button(text: String, node_name: String = "") -> Button:
	var result := Button.new()
	result.text = text
	if not node_name.is_empty():
		result.name = node_name
	result.custom_minimum_size.y = 48
	return result
