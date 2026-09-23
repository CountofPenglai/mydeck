class_name BattleChoicePopupLayout
extends RefCounted


const POPUP_MIN_WIDTH := 384
const POPUP_CHROME_HEIGHT := 48
const POPUP_MAX_VIEWPORT_HEIGHT_RATIO := 0.72


static func size_for(popup: Window, scroll: ScrollContainer, content: Control) -> Vector2i:
	var viewport_size := _host_viewport_size(popup)
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return Vector2i(POPUP_MIN_WIDTH, POPUP_CHROME_HEIGHT)
	var content_size := _natural_content_size(content)
	var max_height := int(floor(viewport_size.y * POPUP_MAX_VIEWPORT_HEIGHT_RATIO))
	var content_height := mini(int(ceil(content_size.y)), maxi(1, max_height - POPUP_CHROME_HEIGHT))
	scroll.custom_minimum_size = Vector2(360, content_height)
	var popup_width := mini(maxi(POPUP_MIN_WIDTH, int(ceil(content_size.x)) + 24), int(floor(viewport_size.x * 0.9)))
	return Vector2i(popup_width, content_height + POPUP_CHROME_HEIGHT)


static func resize_and_center(popup: Window, desired_size: Vector2i) -> void:
	var viewport_size := _host_viewport_size(popup)
	popup.size = desired_size
	popup.position = Vector2i((viewport_size - Vector2(desired_size)) * 0.5)


static func _host_viewport_size(popup: Window) -> Vector2:
	var parent := popup.get_parent()
	if parent != null:
		return parent.get_viewport().get_visible_rect().size
	return popup.get_viewport().get_visible_rect().size


static func _natural_content_size(content: Control) -> Vector2:
	var width := content.get_combined_minimum_size().x
	var height := 0.0
	var control_count := 0
	for child in content.get_children():
		if child is Control:
			var control := child as Control
			width = maxf(width, control.get_combined_minimum_size().x)
			height += control.get_combined_minimum_size().y
			control_count += 1
	if control_count > 1:
		height += float(content.get_theme_constant("separation")) * float(control_count - 1)
	return Vector2(width, height)
