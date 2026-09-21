extends Control
class_name SettingsPanel

signal back_requested

var service: DisplaySettingsService
var fullscreen: CheckButton
var resolution: OptionButton
var feedback: Label
var confirmation: ConfirmationDialog


func _ready() -> void:
	theme = MenuTheme.create_theme()
	if service == null:
		service = get_node_or_null("/root/DisplaySettings") as DisplaySettingsService
	var stack := VBoxContainer.new()
	MenuTheme.margin(self, 48).add_child(stack)
	var header := HBoxContainer.new()
	stack.add_child(header)
	var title := MenuTheme.label("设置", 32)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var back := MenuTheme.button("返回主菜单")
	back.pressed.connect(_back)
	header.add_child(back)
	stack.add_child(MenuTheme.label("显示设置单独保存，不影响冒险进度。", 18))
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 620
	center.add_child(panel)
	var form := VBoxContainer.new()
	form.add_theme_constant_override("separation", 22)
	panel.add_child(form)
	form.add_child(MenuTheme.label("画面与窗口", 26))
	fullscreen = CheckButton.new()
	fullscreen.text = "全屏显示"
	fullscreen.toggled.connect(func(enabled: bool) -> void: resolution.disabled = enabled)
	form.add_child(fullscreen)
	form.add_child(MenuTheme.label("窗口分辨率"))
	resolution = OptionButton.new()
	for value in DisplaySettingsService.RESOLUTIONS:
		resolution.add_item("%d × %d" % [value.x, value.y])
	form.add_child(resolution)
	var note := MenuTheme.label("应用后请在 15 秒内确认；未确认将自动恢复。", 17)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form.add_child(note)
	var actions := HBoxContainer.new()
	form.add_child(actions)
	var apply_button := MenuTheme.button("应用设置")
	apply_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apply_button.pressed.connect(_apply)
	actions.add_child(apply_button)
	var defaults := MenuTheme.button("恢复默认")
	defaults.pressed.connect(func() -> void: _set_draft(service.reset_draft()))
	actions.add_child(defaults)
	feedback = MenuTheme.label("")
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(feedback)
	confirmation = ConfirmationDialog.new()
	confirmation.title = "保留显示设置？"
	confirmation.ok_button_text = "保留并保存"
	confirmation.cancel_button_text = "恢复原设置"
	confirmation.confirmed.connect(_confirm)
	confirmation.canceled.connect(service.cancel_preview)
	add_child(confirmation)
	service.preview_changed.connect(_preview_changed)
	_set_draft(service.get_settings())
	apply_button.grab_focus()


func _exit_tree() -> void:
	if service != null:
		service.cancel_preview()


func _set_draft(settings: Dictionary) -> void:
	fullscreen.set_pressed_no_signal(settings.fullscreen)
	resolution.select(DisplaySettingsService.RESOLUTIONS.find(settings.resolution))
	resolution.disabled = settings.fullscreen


func _apply() -> void:
	var result := service.preview({
		"fullscreen": fullscreen.button_pressed,
		"resolution": DisplaySettingsService.RESOLUTIONS[resolution.selected],
	})
	feedback.text = result.message
	if result.ok:
		confirmation.popup_centered(Vector2i(520, 190))


func _confirm() -> void:
	var result := service.confirm_preview()
	feedback.text = result.message


func _preview_changed() -> void:
	if not service.preview_active:
		confirmation.hide()
		_set_draft(service.get_settings())


func _process(_delta: float) -> void:
	if confirmation != null and confirmation.visible and service.preview_active:
		confirmation.dialog_text = "是否保留当前显示设置？\n%d 秒后自动恢复原设置。" % ceili(service.confirmation_timer.time_left)


func _back() -> void:
	service.cancel_preview()
	back_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if service.preview_active:
			service.cancel_preview()
		else:
			_back()
