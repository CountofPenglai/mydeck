extends Control
class_name MainMenuScene

var session: AdventureSessionService
var navigation: GameNavigationService
var new_game_confirmation: ConfirmationDialog
var start_button: Button
var continue_button: Button
var encyclopedia_button: Button
var settings_button: Button
var status_label: Label
var summary_label: Label
var home: Control
var page: Control


func _ready() -> void:
	if session == null:
		session = get_node_or_null("/root/AdventureSession") as AdventureSessionService
	if navigation == null:
		navigation = get_node_or_null("/root/GameNavigation") as GameNavigationService
	theme = MenuTheme.create_theme()
	MenuTheme.background(self)
	_build_home()
	new_game_confirmation = ConfirmationDialog.new()
	new_game_confirmation.title = "开始新的冒险"
	new_game_confirmation.dialog_text = "开始新冒险将替换当前新版存档。\n旧版独立存档不会删除。是否继续？"
	new_game_confirmation.ok_button_text = "开始新冒险"
	new_game_confirmation.cancel_button_text = "保留进度"
	new_game_confirmation.confirmed.connect(_confirm_start)
	add_child(new_game_confirmation)
	if session != null:
		session.state_changed.connect(refresh_state)
	if navigation != null:
		navigation.transition_changed.connect(refresh_state)
	refresh_state()
	(continue_button if not continue_button.disabled else start_button).grab_focus()


func _build_home() -> void:
	home = MenuTheme.margin(self, 48)
	var stack := VBoxContainer.new()
	home.add_child(stack)
	var eyebrow := MenuTheme.label("牌组构筑  /  六边形冒险", 16)
	eyebrow.add_theme_color_override("font_color", MenuTheme.MUTED)
	stack.add_child(eyebrow)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 70)
	stack.add_child(body)
	var actions := VBoxContainer.new()
	actions.custom_minimum_size.x = 350
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(actions)
	var title := MenuTheme.label("my_deck", 64)
	actions.add_child(title)
	var subtitle := MenuTheme.label("一手牌，一段旅程。", 20)
	subtitle.add_theme_color_override("font_color", MenuTheme.MUTED)
	actions.add_child(subtitle)
	actions.add_child(HSeparator.new())
	start_button = MenuTheme.button("开始游戏", "StartGameButton")
	continue_button = MenuTheme.button("继续游戏", "ContinueGameButton")
	encyclopedia_button = MenuTheme.button("卡牌图鉴", "CardEncyclopediaButton")
	settings_button = MenuTheme.button("设置", "SettingsButton")
	var quit_button := MenuTheme.button("退出游戏", "QuitGameButton")
	for button in [start_button, continue_button, encyclopedia_button, settings_button, quit_button]:
		actions.add_child(button)
	start_button.pressed.connect(_request_start)
	continue_button.pressed.connect(func() -> void: _show_result(navigation.continue_game()))
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	encyclopedia_button.pressed.connect(func() -> void: _open_page(preload("res://scenes/ui/card_encyclopedia.tscn"), encyclopedia_button))
	settings_button.pressed.connect(func() -> void: _open_page(preload("res://scenes/ui/settings_panel.tscn"), settings_button))
	var journey := VBoxContainer.new()
	journey.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	journey.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(journey)
	var emblem := TextureRect.new()
	emblem.texture = preload("res://assets/art/adventure/hex_tiles/symbols/start.svg")
	emblem.custom_minimum_size = Vector2(200, 190)
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.modulate = Color("#39372d")
	journey.add_child(emblem)
	var caption := MenuTheme.label("旅 程 记 录", 22)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	journey.add_child(caption)
	summary_label = MenuTheme.label("")
	summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	journey.add_child(summary_label)
	status_label = MenuTheme.label("")
	status_label.name = "StatusLabel"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size.y = 50
	stack.add_child(status_label)
	var footer := MenuTheme.label("探索 · 构筑 · 生存", 15)
	footer.add_theme_color_override("font_color", MenuTheme.MUTED)
	stack.add_child(footer)


func refresh_state() -> void:
	if session == null or start_button == null:
		return
	var state := session.get_menu_state()
	var busy := navigation == null or navigation.transitioning
	start_button.disabled = busy or not state.can_start
	continue_button.disabled = busy or not state.can_continue
	encyclopedia_button.disabled = busy
	settings_button.disabled = busy
	continue_button.tooltip_text = state.reason
	start_button.tooltip_text = state.reason if not state.can_start else ""
	summary_label.text = state.summary if not state.summary.is_empty() else "旅程尚未开启"
	status_label.text = "正在打开旅程……" if busy else state.reason


func _request_start() -> void:
	var state := session.get_menu_state()
	if not state.can_start:
		status_label.text = state.reason
	elif state.requires_confirmation:
		new_game_confirmation.popup_centered(Vector2i(500, 200))
	else:
		_show_result(navigation.start_game())


func _confirm_start() -> void:
	_show_result(navigation.start_game(true))


func _show_result(result: Dictionary) -> void:
	if not result.ok:
		refresh_state()
		status_label.text = result.message


func _open_page(packed: PackedScene, source: Button) -> void:
	if page != null or navigation.transitioning:
		return
	page = packed.instantiate() as Control
	page.connect("back_requested", func() -> void:
		page.queue_free()
		page = null
		home.show()
		source.grab_focus()
	)
	home.hide()
	add_child(page)
