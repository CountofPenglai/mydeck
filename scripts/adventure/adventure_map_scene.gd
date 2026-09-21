extends Control
class_name AdventureMapScene

var session: AdventureSessionService
var navigation: GameNavigationService
var menu_return_feedback: Label
var run_state: PartyRunState
var selected_room_id: String = ""

var floor_label: Label
var gold_label: Label
var camp_label: Label
var ritual_label: Label
var danger_label: Label
var seed_edit: LineEdit
var enemy_health_spin_box: SpinBox
var status_label: Label
var map_view: AdventureMapView
var detail_title: Label
var detail_body: RichTextLabel
var action_list: VBoxContainer
var party_list: HBoxContainer
var modal_layer: ColorRect
var modal_title: Label
var modal_body: VBoxContainer
var inventory_hero_id: String = ""
var curse_hero_id: String = ""
var syncing_enemy_health_control: bool = false
var event_altar_controls: Dictionary = {}
var event_card_controls: Dictionary = {}
var event_nature_controls: Dictionary = {}
var event_modal_feedback: Label


func _ready() -> void:
	if navigation == null:
		navigation = get_node_or_null("/root/GameNavigation") as GameNavigationService
	if session == null:
		session = get_node_or_null("/root/AdventureSession") as AdventureSessionService
	if session == null:
		push_error("AdventureSession autoload is missing.")
		return
	_build_ui()
	session.state_changed.connect(_refresh)
	session.status_message.connect(_show_status)
	run_state = session.ensure_run()
	if run_state == null:
		_show_start_required()
		return
	selected_room_id = run_state.floor_state.current_room_id
	_refresh()
	_show_pending_state()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("#191a18")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var root_margin := MarginContainer.new()
	root_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_margin.add_theme_constant_override("margin_left", 14)
	root_margin.add_theme_constant_override("margin_top", 12)
	root_margin.add_theme_constant_override("margin_right", 14)
	root_margin.add_theme_constant_override("margin_bottom", 12)
	add_child(root_margin)
	var root_stack := VBoxContainer.new()
	root_stack.add_theme_constant_override("separation", 10)
	root_margin.add_child(root_stack)
	root_stack.add_child(_build_top_bar())
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	root_stack.add_child(body)
	var map_panel := PanelContainer.new()
	map_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(map_panel)
	map_view = AdventureMapView.new()
	map_view.custom_minimum_size = Vector2(360.0, 280.0)
	map_view.room_selected.connect(_on_room_selected)
	map_view.room_hovered.connect(_on_room_hovered)
	map_panel.add_child(map_view)
	body.add_child(_build_detail_panel())
	root_stack.add_child(_build_party_bar())
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	status_label = Label.new()
	status_label.custom_minimum_size = Vector2(0.0, 26.0)
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_label.add_theme_color_override("font_color", Color("#d7c797"))
	footer.add_child(status_label)
	footer.add_child(_build_test_controls())
	root_stack.add_child(footer)
	_build_modal_layer()


func _build_top_bar() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0.0, 54.0)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 12)
	row.add_theme_constant_override("v_separation", 6)
	margin.add_child(row)
	floor_label = _top_label()
	gold_label = _top_label()
	camp_label = _top_label()
	ritual_label = _top_label()
	danger_label = _top_label()
	for label in [floor_label, gold_label, camp_label, ritual_label, danger_label]:
		row.add_child(label)
	seed_edit = LineEdit.new()
	seed_edit.custom_minimum_size = Vector2(130.0, 34.0)
	seed_edit.placeholder_text = "冒险种子"
	seed_edit.tooltip_text = "输入整数种子后开始新的 Demo 冒险"
	row.add_child(seed_edit)
	var copy_button := Button.new()
	copy_button.text = "复制种子"
	copy_button.tooltip_text = "复制当前冒险种子"
	copy_button.pressed.connect(_copy_seed)
	row.add_child(copy_button)
	var new_button := Button.new()
	new_button.text = "使用种子"
	new_button.pressed.connect(_start_new_run)
	row.add_child(new_button)
	var random_button := Button.new()
	random_button.text = "随机新冒险"
	random_button.pressed.connect(_start_random_run)
	row.add_child(random_button)
	var menu_button := Button.new()
	menu_button.name = "MainMenuButton"
	menu_button.text = "主菜单"
	menu_button.pressed.connect(_return_to_main_menu)
	row.add_child(menu_button)
	return panel


func _build_test_controls() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.text = "测试：怪物生命"
	label.tooltip_text = "只影响之后锁定的战斗，默认 100%"
	row.add_child(label)
	enemy_health_spin_box = SpinBox.new()
	enemy_health_spin_box.min_value = 1.0
	enemy_health_spin_box.max_value = 1000.0
	enemy_health_spin_box.step = 1.0
	enemy_health_spin_box.value = 100.0
	enemy_health_spin_box.suffix = "%"
	enemy_health_spin_box.custom_minimum_size = Vector2(96.0, 32.0)
	enemy_health_spin_box.tooltip_text = "调整之后进入战斗的所有怪物最大生命"
	enemy_health_spin_box.value_changed.connect(_on_enemy_health_percent_changed)
	row.add_child(enemy_health_spin_box)
	return row


func _build_detail_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(300.0, 0.0)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	margin.add_child(stack)
	detail_title = Label.new()
	detail_title.add_theme_font_size_override("font_size", 24)
	detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(detail_title)
	detail_body = RichTextLabel.new()
	detail_body.bbcode_enabled = true
	detail_body.fit_content = false
	detail_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_body.custom_minimum_size = Vector2(0.0, 140.0)
	stack.add_child(detail_body)
	var separator := HSeparator.new()
	stack.add_child(separator)
	var action_scroll := ScrollContainer.new()
	action_scroll.custom_minimum_size = Vector2(0.0, 120.0)
	action_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(action_scroll)
	action_list = VBoxContainer.new()
	action_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_list.add_theme_constant_override("separation", 7)
	action_scroll.add_child(action_list)
	return panel


func _build_party_bar() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0.0, 86.0)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	party_list = HBoxContainer.new()
	party_list.add_theme_constant_override("separation", 8)
	margin.add_child(party_list)
	return panel


func _build_modal_layer() -> void:
	modal_layer = ColorRect.new()
	modal_layer.color = Color(0.04, 0.04, 0.035, 0.82)
	modal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_layer.visible = false
	add_child(modal_layer)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_layer.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(700.0, 500.0)
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	margin.add_child(stack)
	modal_title = Label.new()
	modal_title.add_theme_font_size_override("font_size", 25)
	stack.add_child(modal_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(scroll)
	modal_body = VBoxContainer.new()
	modal_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modal_body.add_theme_constant_override("separation", 7)
	scroll.add_child(modal_body)
	var menu_button := Button.new()
	menu_button.name = "ModalMainMenuButton"
	menu_button.text = "保存并回到主菜单"
	menu_button.pressed.connect(_return_to_main_menu)
	stack.add_child(menu_button)
	menu_return_feedback = Label.new()
	menu_return_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(menu_return_feedback)


func _return_to_main_menu() -> void:
	if navigation == null:
		return
	var result := navigation.return_to_menu(false)
	if not result.ok:
		_show_status(result.message)
		menu_return_feedback.text = result.message


func _refresh() -> void:
	run_state = session.ensure_run()
	if run_state == null:
		_show_start_required()
		return
	if run_state.floor_state == null:
		return
	floor_label.text = "第 %d/%d 层" % [run_state.floor_index + 1, run_state.floor_count]
	gold_label.text = "金币 %d" % run_state.gold
	camp_label.text = "扎营 %d" % run_state.camp_points
	ritual_label.text = "仪式 %d" % run_state.ritual_points
	danger_label.text = "危险 %d" % run_state.floor_state.danger
	seed_edit.text = str(run_state.run_seed)
	if enemy_health_spin_box != null:
		syncing_enemy_health_control = true
		enemy_health_spin_box.value = float(run_state.enemy_health_percent)
		syncing_enemy_health_control = false
	map_view.set_floor_state(run_state.floor_state)
	if run_state.floor_state.get_room(selected_room_id) == null:
		selected_room_id = run_state.floor_state.current_room_id
	map_view.set_selected_room(selected_room_id)
	_refresh_detail()
	_refresh_party()


func _refresh_detail(preview_room_id: String = "") -> void:
	_clear_children(action_list)
	var displayed_room_id := selected_room_id if preview_room_id.is_empty() else preview_room_id
	var room := run_state.floor_state.get_room(displayed_room_id)
	if room == null:
		detail_title.text = "未选择房间"
		detail_body.text = ""
		return
	var presentation := AdventureMapPresentation.for_room(run_state.floor_state, room, selected_room_id)
	detail_title.text = str(presentation.get("title", "未知图格"))
	var state_text := "当前房间" if room.room_id == run_state.floor_state.current_room_id else ("已完成" if room.completed else ("已访问" if room.visited else "未访问"))
	var lines := PackedStringArray([
		"[color=#b9aa83]位置[/color]  (%d, %d)" % [room.cell.x, room.cell.y],
		"[color=#b9aa83]状态[/color]  %s" % state_text,
	])
	if not room.content_revealed:
		lines.append("\n内容将在首次进入时揭示。")
		if room.high_value_marked:
			lines.append("[color=#d7c797]侦察标记：高价值地点[/color]")
	elif room.is_combat_room():
		_append_encounter_preview(lines, room)
	elif room.room_type == AdventureEnums.RoomType.SHELTER:
		lines.append("\n[color=#d7c797]扎营活动[/color]")
		for activity_id in ["bandage", "tactics", "scout", "sharpen", "ranger_dig", "druid_infusion"]:
			lines.append("• %s" % _camp_activity_description(activity_id))
		var ranger_id := _first_hero_id_for_class(CardEnums.CardClass.RANGER)
		if not ranger_id.is_empty():
			var progress := int(run_state.adventure_flags.get("ranger_dig_%s" % ranger_id, 0))
			lines.append("[color=#b9aa83]挖掘进度[/color]  %d/3" % progress)
		if room.camp_visit_closed:
			lines.append("[color=#b9aa83]已离开，休整关闭。[/color]")
	elif room.room_type == AdventureEnums.RoomType.EVENT:
		var event := session.get_event_definition(room)
		lines.append("[color=#b9aa83]风险[/color]  %s" % str(event.get("risk", "未知")))
		lines.append("[color=#b9aa83]回报[/color]  %s" % str(event.get("reward", "未知")))
		lines.append("\n%s" % str(event.get("summary", "")))
		var rules := str(event.get("rules", ""))
		if not rules.is_empty():
			lines.append("\n[color=#d7c797]结算规则[/color]\n%s" % rules)
		_append_encounter_preview(lines, room)
		var event_options := session.get_current_event_options(room)
		if not event_options.is_empty():
			lines.append("\n[color=#d7c797]可选行动[/color]")
			for option in event_options:
				var option_line := "• [b]%s[/b]：%s" % [str(option.get("label", "选择")), str(option.get("preview", ""))]
				if not bool(option.get("available", true)):
					option_line += " [color=#d57568]不可用：%s[/color]" % str(option.get("reason", "条件不足"))
				lines.append(option_line)
	if displayed_room_id != selected_room_id:
		lines.append("\n点击房间后可确认移动。")
	elif room.room_id != run_state.floor_state.current_room_id:
		if not AdventureTravelService.plan(run_state.floor_state, room.room_id).is_empty():
			lines.append("\n沿已探索路线前往；首次探索会增加 1 点危险。")
			_add_action("前往此处", _move_to_selected)
		else:
			lines.append("\n该房间当前不可直接到达。")
	elif room.content_revealed and not room.completed:
		_build_current_room_actions(room)
	elif room.content_revealed and room.room_type in [AdventureEnums.RoomType.SHELTER, AdventureEnums.RoomType.SHOP]:
		_build_current_room_actions(room)
	detail_body.text = "\n".join(lines)


func _build_current_room_actions(room: AdventureRoomState) -> void:
	match room.room_type:
		AdventureEnums.RoomType.NORMAL_BATTLE, AdventureEnums.RoomType.ELITE_BATTLE, AdventureEnums.RoomType.BOSS_BATTLE:
			_add_action("开始战斗", _start_battle)
		AdventureEnums.RoomType.SHELTER:
			if room.camp_visit_closed:
				return
			_add_action("免费休息", _rest, room.rest_used)
			if session.can_deliver_adventurer_remains():
				_add_action("交付冒险者遗骨 · 本层装备三选一", _begin_remains_delivery, false, "选择装备和接收者后，遗骨任务物品消失。")
			_add_action("包扎选中角色 (2)", _camp_action.bind("bandage"), false, _camp_activity_description("bandage"))
			_add_action("战术推演 (2)", _camp_action.bind("tactics"), false, _camp_activity_description("tactics"))
			_add_action("侦察 (1)", _show_scout_picker, false, _camp_activity_description("scout"))
			_add_action("战士：磨砺兵锋 (3)", _camp_action.bind("sharpen"), false, _camp_activity_description("sharpen"))
			var ranger_id := _first_hero_id_for_class(CardEnums.CardClass.RANGER)
			var dig_progress := int(run_state.adventure_flags.get("ranger_dig_%s" % ranger_id, 0)) if not ranger_id.is_empty() else 0
			_add_action(
				"游侠：挖掘宝藏 (2) · %d/3" % dig_progress,
				_camp_action.bind("ranger_dig"),
				ranger_id.is_empty() or dig_progress >= 3,
				_camp_activity_description("ranger_dig")
			)
			_add_action(
				"德鲁伊：自然灌注 (3)",
				_show_infusion_cards,
				_first_hero_id_for_class(CardEnums.CardClass.DRUID).is_empty() or run_state.camp_points < 3,
				_camp_activity_description("druid_infusion")
			)
			_add_action("兑换扎营物资", _exchange_supply, run_state.camp_supplies <= 0)
			_build_ritual_actions()
		AdventureEnums.RoomType.SHOP:
			_build_shop_actions()
		AdventureEnums.RoomType.EVENT:
			for option_data in session.get_current_event_options(room):
				var option_id := str(option_data.get("id", "leave"))
				var tooltip := str(option_data.get("preview", ""))
				if not bool(option_data.get("available", true)):
					tooltip = "%s\n不可用：%s" % [tooltip, str(option_data.get("reason", "条件不足"))]
				_add_action(str(option_data.get("label", "选择")), _begin_event_option.bind(option_id), not bool(option_data.get("available", true)), tooltip)
			if room.content_id == "wilderness_merchant":
				_build_shop_actions()


func _build_shop_actions() -> void:
	var stock := session.get_shop_stock()
	for index in range(stock.size()):
		var entry := stock[index]
		var label := "%s  %d 金" % [str(entry.get("name", "物品")), int(entry.get("price", 0))]
		if bool(entry.get("sold", false)):
			label = "%s  [售罄]" % str(entry.get("name", "物品"))
		_add_action(label, _buy_stock.bind(index), bool(entry.get("sold", false)))
	var room := run_state.floor_state.get_current_room()
	if room != null and room.content_id == "wilderness_merchant":
		return
	_add_action("购买扎营物资  15 金", _buy_camp_supply)
	var may_restock := room != null \
		and room.shop_restock_count < 2 \
		and bool(room.runtime_data.get("shop_revisit_available", false))
	_add_action("重访补货 · 危险 +1", _request_shop_restock, not may_restock, "每个商店最多补货两次；需完成一次实际重访。")
	var removal_price := session.definition.get_economy().get_card_removal_price(run_state.card_removals_used)
	_add_action("删牌服务  %d 金" % removal_price, _show_card_removal, bool(room.runtime_data.get("card_removal_used", false)))


func _build_ritual_actions() -> void:
	for hero in run_state.party:
		if hero == null:
			continue
		if not hero.sealed_curse_id.is_empty():
			_add_action("解除 %s 的封印 (1扎营)" % hero.get_character_name(), _ritual_unseal.bind(hero.adventure_character_id))
		for curse in hero.curse_instances:
			if curse == null or curse.state == CurseInstance.State.INDUSTRY:
				continue
			if hero.sealed_curse_id.is_empty():
				_add_action("封印：%s / %s (2+2)" % [hero.get_character_name(), curse.get_display_name()], _ritual_seal.bind(hero.adventure_character_id, curse.get_curse_id()))
			var target_id := _first_transfer_target(hero, curse)
			if not target_id.is_empty():
				_add_action("转移：%s / %s (1+1)" % [hero.get_character_name(), curse.get_display_name()], _ritual_transfer.bind(hero.adventure_character_id, curse.get_curse_id(), target_id))


func _refresh_party() -> void:
	_clear_children(party_list)
	for hero in run_state.party:
		if hero == null:
			continue
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 10)
		margin.add_theme_constant_override("margin_right", 10)
		margin.add_theme_constant_override("margin_top", 6)
		margin.add_theme_constant_override("margin_bottom", 6)
		panel.add_child(margin)
		var stack := VBoxContainer.new()
		margin.add_child(stack)
		var name_label := Label.new()
		name_label.text = "%s · %s" % [hero.get_character_name(), hero.get_class_label()]
		name_label.add_theme_font_size_override("font_size", 16)
		stack.add_child(name_label)
		var state_label := Label.new()
		state_label.text = "生命 %d/%d   负荷 %d/%d%s" % [
			hero.current_health, hero.get_max_health(), hero.get_curse_load(), hero.get_curse_load_limit(),
			"   无法参战" if hero.is_curse_overloaded() or hero.current_health <= 0 else "",
		]
		stack.add_child(state_label)
		var equipment_button := Button.new()
		equipment_button.text = "装备与背包"
		equipment_button.tooltip_text = "在战斗外整理背包并更换装备"
		equipment_button.custom_minimum_size = Vector2(0.0, 28.0)
		equipment_button.pressed.connect(_show_inventory.bind(hero.adventure_character_id))
		stack.add_child(equipment_button)
		var curse_button := Button.new()
		var has_reward := hero.has_pending_distortion_reward()
		curse_button.text = "诅咒与畸变%s" % (" · 奖励待选" if has_reward else "")
		curse_button.tooltip_text = "查看诅咒区、封印状态与永久畸变"
		curse_button.custom_minimum_size = Vector2(0.0, 28.0)
		curse_button.pressed.connect(_show_curse_zone.bind(hero.adventure_character_id))
		if has_reward:
			curse_button.add_theme_color_override("font_color", Color("#ffe09a"))
			curse_button.add_theme_color_override("font_hover_color", Color("#fff1c2"))
			var highlight := StyleBoxFlat.new()
			highlight.bg_color = Color("#493a20")
			highlight.border_color = Color("#d9a441")
			highlight.set_border_width_all(2)
			highlight.corner_radius_top_left = 4
			highlight.corner_radius_top_right = 4
			highlight.corner_radius_bottom_left = 4
			highlight.corner_radius_bottom_right = 4
			curse_button.add_theme_stylebox_override("normal", highlight)
		stack.add_child(curse_button)
		party_list.add_child(panel)


func _show_curse_zone(hero_id: String) -> void:
	curse_hero_id = hero_id
	_refresh_curse_zone_modal()


func _refresh_curse_zone_modal() -> void:
	var hero := _get_hero_state(curse_hero_id)
	if hero == null:
		_hide_modal()
		return
	modal_layer.visible = true
	modal_title.text = "%s · 诅咒与畸变" % hero.get_character_name()
	_clear_children(modal_body)
	_add_curse_hero_selector()

	var overview := Label.new()
	overview.text = "负荷 %d/%d   畸变进度 %d   恩典 %d 次" % [
		hero.get_curse_load(),
		hero.get_curse_load_limit(),
		hero.distortion_progress,
		hero.distortion_grace_count,
	]
	overview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overview.add_theme_font_size_override("font_size", 18)
	if hero.is_curse_overloaded():
		overview.add_theme_color_override("font_color", Color("#e47b6c"))
	modal_body.add_child(overview)

	var track := Label.new()
	var track_parts: PackedStringArray = []
	var pending_index := hero.get_pending_distortion_milestone()
	var next_index := hero.get_next_unclaimed_distortion_milestone()
	for milestone_index in range(DistortionCatalog.MILESTONES.size()):
		var base_threshold: int = DistortionCatalog.MILESTONES[milestone_index]
		if hero.claimed_distortion_milestones.has(milestone_index):
			track_parts.append("%d 已领取" % base_threshold)
		elif milestone_index == pending_index:
			track_parts.append("%d 待选择" % hero.get_effective_distortion_threshold(milestone_index))
		elif milestone_index == next_index:
			track_parts.append("%d 进行中" % hero.get_effective_distortion_threshold(milestone_index))
		else:
			track_parts.append("%d 未解锁" % base_threshold)
	track.text = "里程碑  " + "  |  ".join(track_parts)
	track.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	track.add_theme_color_override(
		"font_color",
		Color("#ffe09a") if pending_index >= 0 else Color("#c9c1ad"),
	)
	modal_body.add_child(track)
	modal_body.add_child(HSeparator.new())

	var curse_heading := Label.new()
	curse_heading.text = "诅咒区"
	curse_heading.add_theme_font_size_override("font_size", 19)
	modal_body.add_child(curse_heading)
	if hero.curse_instances.is_empty():
		var empty_curses := Label.new()
		empty_curses.text = "当前没有永久诅咒。"
		empty_curses.add_theme_color_override("font_color", Color("#aaa69b"))
		modal_body.add_child(empty_curses)
	else:
		for curse in hero.curse_instances:
			if curse == null or curse.definition == null:
				continue
			var curse_label := Label.new()
			curse_label.text = RulesTextFormatter.format_curse(curse)
			curse_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			curse_label.add_theme_color_override(
				"font_color",
				Color("#8e8a81") if curse.sealed else Color("#ded7c5"),
			)
			modal_body.add_child(curse_label)

	modal_body.add_child(HSeparator.new())
	var field_heading := Label.new()
	field_heading.text = "永久畸变"
	field_heading.add_theme_font_size_override("font_size", 19)
	modal_body.add_child(field_heading)
	if hero.selected_distortion_fields.is_empty():
		var empty_fields := Label.new()
		empty_fields.text = "尚未选择永久畸变。"
		empty_fields.add_theme_color_override("font_color", Color("#aaa69b"))
		modal_body.add_child(empty_fields)
	else:
		for field_id in hero.selected_distortion_fields:
			var field_label := Label.new()
			field_label.text = "%s\n%s" % [
				DistortionCatalog.get_display_name(field_id),
				DistortionCatalog.get_description(field_id),
			]
			field_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			modal_body.add_child(field_label)

	if pending_index >= 0:
		modal_body.add_child(HSeparator.new())
		var reward_heading := Label.new()
		reward_heading.text = "畸变奖励待选择"
		reward_heading.add_theme_font_size_override("font_size", 20)
		reward_heading.add_theme_color_override("font_color", Color("#ffe09a"))
		modal_body.add_child(reward_heading)
		var reward_hint := Label.new()
		reward_hint.text = "选择一项永久畸变；也可以放弃三项并获得恩典。领取不会关闭或替代战斗后的选牌奖励。"
		reward_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		modal_body.add_child(reward_hint)
		var reward_state := session.get_distortion_reward_state(hero.adventure_character_id)
		for option_value in reward_state.get("options", []):
			if not (option_value is Dictionary):
				continue
			var option := option_value as Dictionary
			_add_distortion_reward_button(hero, option)
		var grace := reward_state.get("grace", {}) as Dictionary
		if not grace.is_empty():
			_add_distortion_reward_button(hero, grace)

	var close_button := Button.new()
	close_button.text = "关闭"
	close_button.pressed.connect(_hide_modal)
	modal_body.add_child(close_button)


func _add_curse_hero_selector() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for hero in run_state.party:
		if hero == null:
			continue
		var button := Button.new()
		button.text = "%s%s" % [
			hero.get_character_name(),
			" · 待选" if hero.has_pending_distortion_reward() else "",
		]
		button.disabled = hero.adventure_character_id == curse_hero_id
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_show_curse_zone.bind(hero.adventure_character_id))
		if hero.has_pending_distortion_reward():
			button.add_theme_color_override("font_color", Color("#ffe09a"))
		row.add_child(button)
	modal_body.add_child(row)


func _add_distortion_reward_button(hero: CharacterState, reward: Dictionary) -> void:
	var reward_id := str(reward.get("id", ""))
	if reward_id.is_empty():
		return
	var button := Button.new()
	button.text = "%s\n%s" % [
		str(reward.get("name", reward_id)),
		str(reward.get("description", "")),
	]
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.custom_minimum_size = Vector2(0.0, 62.0)
	button.pressed.connect(_choose_distortion_reward.bind(hero.adventure_character_id, reward_id))
	modal_body.add_child(button)


func _choose_distortion_reward(hero_id: String, reward_id: String) -> void:
	if not session.choose_distortion_reward(hero_id, reward_id):
		_show_status("畸变奖励已失效或不在本次候选中。")
	_refresh_curse_zone_modal()


func _show_inventory(hero_id: String) -> void:
	inventory_hero_id = hero_id
	_refresh_inventory_modal()


func _refresh_inventory_modal() -> void:
	var hero := _get_hero_state(inventory_hero_id)
	if hero == null:
		_hide_modal()
		return
	hero.ensure_adventure_instance_ids()
	modal_layer.visible = true
	modal_title.text = "%s · 装备与背包" % hero.get_character_name()
	_clear_children(modal_body)
	_add_inventory_hero_selector()

	var equipment_heading := Label.new()
	equipment_heading.text = "装备栏"
	equipment_heading.add_theme_font_size_override("font_size", 19)
	modal_body.add_child(equipment_heading)
	_add_equipment_slot_row(hero, "武器", CharacterEquipmentModel.SLOT_WEAPON, hero.weapon_equipment)
	if _is_warrior(hero):
		_add_equipment_slot_row(
			hero,
			tr("备战武器"),
			CharacterEquipmentModel.SLOT_RESERVE_WEAPON,
			hero.reserve_weapon_equipment
		)
	_add_equipment_slot_row(hero, "防具", CharacterEquipmentModel.SLOT_ARMOR, hero.armor_equipment)
	_add_equipment_slot_row(hero, "饰品 1", CharacterEquipmentModel.SLOT_ACCESSORY_1, hero.accessory_equipment_1)
	_add_equipment_slot_row(hero, "饰品 2", CharacterEquipmentModel.SLOT_ACCESSORY_2, hero.accessory_equipment_2)
	modal_body.add_child(HSeparator.new())

	var inventory_header := HBoxContainer.new()
	var inventory_heading := Label.new()
	inventory_heading.text = "背包  %d/%d" % [hero.get_inventory_item_count(), CharacterState.INVENTORY_LIMIT]
	inventory_heading.add_theme_font_size_override("font_size", 19)
	inventory_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_header.add_child(inventory_heading)
	var sort_button := Button.new()
	sort_button.text = "整理"
	sort_button.tooltip_text = "按装备位、品质和名称排序"
	sort_button.disabled = hero.inventory.size() < 2
	sort_button.pressed.connect(_sort_inventory.bind(hero.adventure_character_id))
	inventory_header.add_child(sort_button)
	modal_body.add_child(inventory_header)

	var has_items := false
	for item_stack in hero.inventory:
		if item_stack == null or item_stack.item_data == null:
			continue
		has_items = true
		_add_inventory_item_row(hero, item_stack)
	if not has_items:
		var empty_label := Label.new()
		empty_label.text = "背包为空。"
		empty_label.add_theme_color_override("font_color", Color("#aaa69b"))
		modal_body.add_child(empty_label)

	var close_button := Button.new()
	close_button.text = "关闭"
	close_button.pressed.connect(_hide_modal)
	modal_body.add_child(close_button)


func _add_inventory_hero_selector() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for hero in run_state.party:
		if hero == null:
			continue
		var button := Button.new()
		button.text = hero.get_character_name()
		button.disabled = hero.adventure_character_id == inventory_hero_id
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_show_inventory.bind(hero.adventure_character_id))
		row.add_child(button)
	modal_body.add_child(row)


func _add_equipment_slot_row(hero: CharacterState, label_text: String, slot: String, equipment: EquipmentData) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	var instance_id := str(hero.equipment_instance_ids.get(slot, ""))
	var modifiers := hero.equipment_adventure_modifiers.get(instance_id, {}) as Dictionary
	label.text = "%s  %s" % [label_text, _equipment_summary(equipment, modifiers)]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size = Vector2(430.0, 34.0)
	row.add_child(label)
	var detail_button := Button.new()
	detail_button.text = "详情"
	detail_button.disabled = equipment == null
	detail_button.pressed.connect(_show_equipment_detail.bind(equipment, modifiers, "inventory"))
	row.add_child(detail_button)
	var unequip_button := Button.new()
	unequip_button.text = "卸下"
	unequip_button.disabled = equipment == null
	unequip_button.tooltip_text = "将当前装备放回背包"
	unequip_button.pressed.connect(_unequip_item.bind(hero.adventure_character_id, slot))
	row.add_child(unequip_button)
	modal_body.add_child(row)


func _add_inventory_item_row(hero: CharacterState, item_stack: InventoryStack) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.text = _inventory_item_summary(hero, item_stack)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size = Vector2(350.0, 38.0)
	row.add_child(label)

	var equipment := item_stack.item_data as EquipmentData
	if equipment != null:
		var modifiers := hero.equipment_adventure_modifiers.get(item_stack.stack_id, {}) as Dictionary
		var detail_button := Button.new()
		detail_button.text = "详情"
		detail_button.pressed.connect(_show_equipment_detail.bind(equipment, modifiers, "inventory"))
		row.add_child(detail_button)
		var class_allowed := hero.character_data == null or equipment.is_available_to_class(hero.character_data.character_class)
		if equipment.is_accessory():
			_add_equip_button(row, hero, item_stack, CharacterEquipmentModel.SLOT_ACCESSORY_1, "饰品 1", class_allowed)
			_add_equip_button(row, hero, item_stack, CharacterEquipmentModel.SLOT_ACCESSORY_2, "饰品 2", class_allowed)
		elif equipment.is_weapon() and _is_warrior(hero):
			_add_equip_button(
				row, hero, item_stack, CharacterEquipmentModel.SLOT_WEAPON, tr("装备为当前"), class_allowed
			)
			_add_equip_button(
				row,
				hero,
				item_stack,
				CharacterEquipmentModel.SLOT_RESERVE_WEAPON,
				tr("装备为备战"),
				class_allowed
			)
		else:
			var slot := CharacterEquipmentModel.SLOT_WEAPON if equipment.is_weapon() else CharacterEquipmentModel.SLOT_ARMOR
			_add_equip_button(row, hero, item_stack, slot, "装备", class_allowed)
		var transfer_menu := MenuButton.new()
		transfer_menu.text = "转交"
		var receivers: Array[String] = []
		for target in run_state.party:
			if target == null or target == hero:
				continue
			receivers.append(target.adventure_character_id)
			var receiver_label := "%s（背包 %d/%d）" % [
				target.get_character_name(),
				target.get_inventory_item_count(),
				CharacterState.INVENTORY_LIMIT,
			]
			transfer_menu.get_popup().add_item(receiver_label)
			transfer_menu.get_popup().set_item_disabled(
				transfer_menu.get_popup().item_count - 1,
				target.get_inventory_item_count() >= CharacterState.INVENTORY_LIMIT
			)
		transfer_menu.disabled = receivers.is_empty()
		transfer_menu.tooltip_text = "将这件背包装备转交给另一名冒险者；已装备物品需要先卸下。"
		transfer_menu.get_popup().id_pressed.connect(
			_transfer_inventory_item.bind(hero.adventure_character_id, item_stack.stack_id, receivers)
		)
		row.add_child(transfer_menu)
	modal_body.add_child(row)
	modal_body.add_child(HSeparator.new())


func _add_equip_button(row: HBoxContainer, hero: CharacterState, item_stack: InventoryStack, slot: String, text: String, allowed: bool) -> void:
	var button := Button.new()
	button.text = text if allowed else "职业不符"
	button.disabled = not allowed
	button.pressed.connect(_equip_inventory_item.bind(hero.adventure_character_id, item_stack.stack_id, slot))
	row.add_child(button)


func _equipment_summary(equipment: EquipmentData, adventure_modifiers: Dictionary = {}) -> String:
	if equipment == null:
		return "空"
	var adventure_bonus := int(adventure_modifiers.get("damage_bonus", 0))
	if equipment.is_weapon():
		var weapon_summary := "%s · 基础伤害 %d · 范围 %d · %s" % [
			equipment.item_name, equipment.base_damage, equipment.attack_range, equipment.get_damage_type_label(),
		]
		if adventure_bonus != 0:
			weapon_summary += " · 冒险伤害 %+d" % adventure_bonus
		return weapon_summary
	var bonuses := PackedStringArray()
	if equipment.damage_bonus != 0:
		bonuses.append("伤害加值 %+d" % equipment.damage_bonus)
	if equipment.damage_reduction != 0:
		bonuses.append("伤害减免 %+d" % equipment.damage_reduction)
	if adventure_bonus != 0:
		bonuses.append("冒险伤害 %+d" % adventure_bonus)
	var suffix := " · %s" % " · ".join(bonuses) if not bonuses.is_empty() else ""
	return "%s%s" % [equipment.item_name, suffix]


func _inventory_item_summary(hero: CharacterState, item_stack: InventoryStack) -> String:
	var item := item_stack.item_data
	var equipment := item as EquipmentData
	var count_text := " x%d" % item_stack.count if item_stack.count > 1 else ""
	if equipment == null:
		return "%s%s\n%s" % [item.item_name, count_text, RulesTextFormatter.format_item(item)]
	var modifier_text := ""
	var modifiers := hero.equipment_adventure_modifiers.get(item_stack.stack_id, {}) as Dictionary
	var adventure_bonus := int(modifiers.get("damage_bonus", 0))
	if adventure_bonus != 0:
		modifier_text = " · 冒险伤害 %+d" % adventure_bonus
	return "%s%s\n%s%s" % [
		equipment.item_name, count_text, RulesTextFormatter.format_equipment_summary(equipment), modifier_text,
	]


func _equip_inventory_item(hero_id: String, stack_id: String, slot: String) -> void:
	var result := session.equip_inventory_item(hero_id, stack_id, slot)
	var message := str(result.get("message", ""))
	if not message.is_empty():
		_show_status(message)
	_refresh_inventory_modal()


func _unequip_item(hero_id: String, slot: String) -> void:
	var result := session.unequip_item(hero_id, slot)
	var message := str(result.get("message", ""))
	if not message.is_empty():
		_show_status(message)
	_refresh_inventory_modal()


func _is_warrior(hero: CharacterState) -> bool:
	return hero != null \
		and hero.character_data != null \
		and hero.character_data.character_class == CardEnums.CardClass.WARRIOR


func _sort_inventory(hero_id: String) -> void:
	session.sort_inventory(hero_id)
	_refresh_inventory_modal()


func _transfer_inventory_item(
	menu_id: int,
	source_id: String,
	stack_id: String,
	receiver_ids: Array[String]
) -> void:
	if menu_id < 0 or menu_id >= receiver_ids.size():
		return
	var result := session.transfer_inventory_item(source_id, stack_id, receiver_ids[menu_id])
	if not bool(result.get("ok", false)):
		_show_status(str(result.get("message", "转交装备失败。")))
	_refresh_inventory_modal()


func _show_equipment_detail(
	equipment: EquipmentData,
	adventure_modifiers: Dictionary = {},
	return_mode: String = "inventory"
) -> void:
	if equipment == null:
		return
	modal_layer.visible = true
	modal_title.text = equipment.item_name
	_clear_children(modal_body)
	var details := Label.new()
	details.text = _equipment_detail_text(equipment, adventure_modifiers)
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.custom_minimum_size = Vector2(0.0, 180.0)
	modal_body.add_child(details)
	var back := Button.new()
	back.text = "返回"
	match return_mode:
		"reward":
			back.pressed.connect(_show_reward_modal)
		"event_reward":
			back.pressed.connect(_show_event_battle_reward_modal)
		_:
			back.pressed.connect(_refresh_inventory_modal)
	modal_body.add_child(back)


func _equipment_detail_text(
	equipment: EquipmentData,
	adventure_modifiers: Dictionary = {}
) -> String:
	var lines := PackedStringArray([RulesTextFormatter.format_equipment(equipment)])
	var adventure_bonus := int(adventure_modifiers.get("damage_bonus", 0))
	if adventure_bonus != 0:
		lines.append("\n本次冒险伤害加值 %+d" % adventure_bonus)
	return "\n".join(lines)


func _show_pending_state() -> void:
	if run_state.run_failed:
		_show_simple_modal("冒险失败", "小队已经覆灭。", "以同一种子重开", session.restart_same_seed)
	elif session.has_pending_reward():
		_show_reward_modal()
	elif session.has_pending_event_reward():
		_show_event_battle_reward_modal()
	elif run_state.run_complete:
		_show_simple_modal("Demo 通关", "第二层首领已被击败，本次冒险完成。", "关闭", _hide_modal)
	elif run_state.pending_transaction != null and run_state.pending_transaction.transaction_type == AdventureEnums.TransactionType.BATTLE:
		_show_simple_modal("战斗待处理", "遭遇已经锁定，继续后不会重新生成敌群。", "进入战斗", session.resume_pending_battle)
	elif bool(run_state.adventure_flags.get("interfloor_camp", false)):
		_show_simple_modal("层间营地", "队伍将在离开时休息并获得 4 点扎营点。", "进入下一层", _enter_next_floor)


func _show_reward_modal() -> void:
	modal_layer.visible = true
	_clear_children(modal_body)
	var reward := session.get_pending_reward()
	var claimed_cards := reward.get("claimed_cards", []) as Array
	var max_cards := int(reward.get("max_cards", 0))
	modal_title.text = "选择卡牌奖励 · %d/%d" % [claimed_cards.size(), max_cards]
	var fixed := Label.new()
	fixed.text = "金币 +%d   仪式点 +%d   扎营物资 +%d" % [
		int(reward.get("gold", 0)), int(reward.get("ritual_points", 0)), int(reward.get("camp_supplies", 0)),
	]
	modal_body.add_child(fixed)
	var hint := Label.new()
	hint.text = "全队最多选择 %d 张卡牌，可以集中交给同一名角色，也可以跳过。" % max_cards
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color("#d7c797"))
	modal_body.add_child(hint)
	var card_heading := Label.new()
	card_heading.text = "候选卡牌"
	card_heading.add_theme_font_size_override("font_size", 19)
	modal_body.add_child(card_heading)
	var card_count := 0
	for card_data in reward.get("cards", []):
		if card_data is Dictionary:
			card_count += 1
			var candidate_id := str(card_data.get("id", ""))
			var selected := claimed_cards.has(candidate_id)
			var button := Button.new()
			button.text = "%s[%s] %s · %s" % [
				"已选择 · " if selected else "",
				CardEnums.rarity_label(int(card_data.get("rarity", CardEnums.Rarity.COMMON))),
				str(card_data.get("name", "卡牌")),
				_hero_name(str(card_data.get("hero_id", ""))),
			]
			button.disabled = selected or claimed_cards.size() >= max_cards
			var card_path := str(card_data.get("path", ""))
			var card := load(card_path) as CardData if ResourceLoader.exists(card_path) else null
			if card != null:
				button.tooltip_text = RulesTextFormatter.format_card(card)
			button.pressed.connect(_claim_reward.bind(candidate_id))
			modal_body.add_child(button)
	if card_count == 0:
		var empty_cards := Label.new()
		empty_cards.text = "没有生成可选卡牌，请查看诊断日志。"
		empty_cards.add_theme_color_override("font_color", Color("#d57568"))
		modal_body.add_child(empty_cards)
	var equipment_entries := reward.get("equipment", []) as Array
	if not equipment_entries.is_empty():
		var equipment_heading := Label.new()
		equipment_heading.text = "装备奖励"
		equipment_heading.add_theme_font_size_override("font_size", 19)
		modal_body.add_child(equipment_heading)
	for equipment_data in equipment_entries:
		if equipment_data is Dictionary:
			var candidate_id := str(equipment_data.get("id", ""))
			var claimed := (reward.get("claimed_equipment", []) as Array).has(candidate_id)
			var equipment_path := str(equipment_data.get("path", ""))
			var equipment := load(equipment_path) as EquipmentData if ResourceLoader.exists(equipment_path) else null
			var heading := HBoxContainer.new()
			var name_label := Label.new()
			name_label.text = "%s%s" % [
				"已选择 · " if claimed else "",
				str(equipment_data.get("name", "装备")),
			]
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			heading.add_child(name_label)
			var detail_button := Button.new()
			detail_button.text = "详情"
			detail_button.disabled = equipment == null
			detail_button.pressed.connect(_show_equipment_detail.bind(equipment, {}, "reward"))
			heading.add_child(detail_button)
			modal_body.add_child(heading)
			if not claimed:
				var receiver_row := HBoxContainer.new()
				receiver_row.add_theme_constant_override("separation", 6)
				for hero in run_state.party:
					if hero == null:
						continue
					var receive_button := Button.new()
					receive_button.text = "交给 %s\n背包 %d/%d" % [
						hero.get_character_name(),
						hero.get_inventory_item_count(),
						CharacterState.INVENTORY_LIMIT,
					]
					receive_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
					receive_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					receive_button.disabled = hero.get_inventory_item_count() >= CharacterState.INVENTORY_LIMIT
					receive_button.pressed.connect(
						_claim_reward.bind(candidate_id, hero.adventure_character_id)
					)
					receiver_row.add_child(receive_button)
				modal_body.add_child(receiver_row)
	if bool(reward.get("gospel_offer", false)):
		var gospel_heading := Label.new()
		gospel_heading.text = "首领诅咒 · 福音"
		gospel_heading.add_theme_font_size_override("font_size", 19)
		gospel_heading.add_theme_color_override("font_color", Color("#d6a0c7"))
		modal_body.add_child(gospel_heading)
		var receiver_id := str(reward.get("gospel_receiver", ""))
		var declined := bool(reward.get("gospel_declined", false))
		var gospel_hint := Label.new()
		gospel_hint.text = "可选择一名冒险者获得深度1「福音」之业，也可以放弃。业不占负荷，成功打出后转为报。"
		gospel_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		modal_body.add_child(gospel_hint)
		if receiver_id.is_empty() and not declined:
			for hero in run_state.party:
				if hero == null:
					continue
				var gospel_button := Button.new()
				gospel_button.text = "%s 接受福音" % hero.get_character_name()
				gospel_button.pressed.connect(_claim_gospel_reward.bind(hero.adventure_character_id))
				modal_body.add_child(gospel_button)
			var decline_button := Button.new()
			decline_button.text = "放弃福音"
			decline_button.pressed.connect(_decline_gospel_reward)
			modal_body.add_child(decline_button)
		else:
			var result_label := Label.new()
			result_label.text = "已放弃" if declined else "%s 已接受" % _hero_name(receiver_id)
			modal_body.add_child(result_label)
	var finish := Button.new()
	finish.text = "完成奖励选择 · 已选 %d/%d" % [claimed_cards.size(), max_cards]
	finish.pressed.connect(_settle_reward)
	modal_body.add_child(finish)


func _show_card_removal() -> void:
	modal_layer.visible = true
	modal_title.text = "选择要移除的牌"
	_clear_children(modal_body)
	for hero in run_state.party:
		if hero == null or hero.deck.size() <= 1:
			continue
		for stack in hero.deck:
			if stack == null or stack.card_data == null or stack.card_data.is_curse_card():
				continue
			var button := Button.new()
			button.text = "%s · %s" % [hero.get_character_name(), stack.card_data.card_name]
			button.pressed.connect(_remove_shop_card.bind(hero.adventure_character_id, stack.stack_id))
			modal_body.add_child(button)
	_add_modal_close_button()


func _show_infusion_cards() -> void:
	var druid_id := _first_hero_id_for_class(CardEnums.CardClass.DRUID)
	if druid_id.is_empty():
		return
	modal_layer.visible = true
	modal_title.text = "选择自然灌注目标"
	_clear_children(modal_body)
	for hero in run_state.party:
		if hero == null:
			continue
		for stack in hero.deck:
			var modifier := hero.card_adventure_modifiers.get(stack.stack_id, {}) as Dictionary if stack != null else {}
			if stack == null or stack.card_data == null or stack.card_data.is_curse_card() \
				or modifier.has("element"):
				continue
			var button := Button.new()
			button.text = "%s · %s" % [hero.get_character_name(), stack.card_data.card_name]
			button.pressed.connect(_show_infusion_elements.bind(druid_id, hero.adventure_character_id, stack.stack_id))
			modal_body.add_child(button)
	_add_modal_close_button()


func _show_infusion_elements(druid_id: String, target_id: String, stack_id: String) -> void:
	modal_title.text = "选择基础元素"
	_clear_children(modal_body)
	for element in BattleSurfaceState.BASE_ELEMENTS:
		var button := Button.new()
		button.text = BattleSurfaceState.label(element)
		button.pressed.connect(_apply_infusion.bind(druid_id, target_id, stack_id, element))
		modal_body.add_child(button)
	_add_modal_close_button()


func _add_modal_close_button() -> void:
	var close_button := Button.new()
	close_button.text = "取消"
	close_button.pressed.connect(_hide_modal)
	modal_body.add_child(close_button)


func _show_simple_modal(title: String, body: String, action_text: String, callback: Callable) -> void:
	modal_layer.visible = true
	modal_title.text = title
	_clear_children(modal_body)
	var label := Label.new()
	label.text = body
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	modal_body.add_child(label)
	var button := Button.new()
	button.text = action_text
	button.pressed.connect(callback)
	modal_body.add_child(button)


func _add_action(label: String, callback: Callable, disabled: bool = false, tooltip: String = "") -> void:
	var button := Button.new()
	button.text = label
	button.disabled = disabled
	button.tooltip_text = tooltip
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.custom_minimum_size = Vector2(0.0, 38.0)
	button.pressed.connect(callback)
	action_list.add_child(button)


func _on_room_selected(room_id: String) -> void:
	selected_room_id = room_id
	map_view.set_selected_room(room_id)
	_refresh_detail()


func _on_room_hovered(room_id: String) -> void:
	_refresh_detail(room_id)


func _move_to_selected() -> void:
	var result := session.request_move(selected_room_id)
	if bool(result.get("ok", false)):
		selected_room_id = run_state.floor_state.current_room_id
		_refresh()
		if bool(result.get("battle", false)):
			session.start_current_battle()
		else:
			_show_pending_state()


func _start_battle() -> void:
	session.start_current_battle()


func _rest() -> void:
	session.rest_at_current_shelter()


func _show_scout_picker() -> void:
	var candidate_ids: Array[String] = session.get_scout_candidates()
	if candidate_ids.is_empty():
		_show_status("范围 3 内没有可侦察的未揭示图格。")
		return
	modal_layer.visible = true
	modal_title.text = "侦察图格 · 最多选择 2 个"
	_clear_children(modal_body)
	var picker := AdventureScoutPicker.new()
	picker.configure(run_state.floor_state, candidate_ids)
	picker.confirmed.connect(_submit_scout)
	modal_body.add_child(picker)
	_add_modal_close_button()


func _submit_scout(selected_ids: Array[String]) -> void:
	if selected_ids.is_empty() or selected_ids.size() > 2:
		_show_status("请选择一至两个图格。")
		return
	var result := session.request_scout(selected_ids)
	if not bool(result.get("ok", false)):
		_show_status(str(result.get("message", "侦察未完成。")))
		return
	_hide_modal()
	_refresh()


func _request_shop_restock() -> void:
	var result := session.request_shop_restock()
	if not bool(result.get("ok", false)):
		_show_status(str(result.get("message", "商店无法补货。")))
		return
	_refresh()


func _append_encounter_preview(lines: PackedStringArray, room: AdventureRoomState) -> void:
	var preview := AdventureEncounterPreviewService.describe(run_state, room)
	if preview.is_empty():
		return
	lines.append("[color=#b9aa83]%s[/color]" % str(preview.get("text", "")))
	var snapshot: Dictionary = preview.get("danger_snapshot", {}) as Dictionary
	var bonus_percent := int(snapshot.get("bonus_percent", 0))
	if bonus_percent > 0:
		lines.append("[color=#c45b52]危险修正：敌人生命与伤害 +%d%%[/color]" % bonus_percent)
	for enemy_data in preview.get("enemies", []) as Array:
		if not enemy_data is Dictionary:
			continue
		var enemy := enemy_data as Dictionary
		var mutations := PackedStringArray(enemy.get("mutations", PackedStringArray()))
		var suffix := ""
		if not mutations.is_empty():
			suffix = " · " + "、".join(mutations)
		lines.append("• %s  HP %d%s" % [str(enemy.get("name", "敌人")), int(enemy.get("max_health", 0)), suffix])


func _camp_action(activity_id: String) -> void:
	var hero_id := run_state.party[0].adventure_character_id if not run_state.party.is_empty() else ""
	if activity_id == "sharpen":
		hero_id = _first_hero_id_for_class(CardEnums.CardClass.WARRIOR)
	elif activity_id == "ranger_dig":
		hero_id = _first_hero_id_for_class(CardEnums.CardClass.RANGER)
	if not session.use_camp_activity(activity_id, hero_id):
		_show_status("当前无法执行该扎营活动：请检查扎营点、次数限制与目标条件。")
	_refresh()
	if session.has_pending_event_reward():
		_show_event_battle_reward_modal()


func _camp_activity_description(activity_id: String) -> String:
	match activity_id:
		"bandage":
			return "包扎（2）：所选角色恢复 20% 最大生命；每座避难所每名角色一次。"
		"tactics":
			return "战术推演（2）：全队下一场战斗起始手牌 +1。"
		"scout":
			return "侦察（1）：选择距离 3 内至多两个尚未揭示的图格。"
		"sharpen":
			return "磨砺兵锋（3）：战士当前武器在本次冒险永久获得 +1 伤害加值；每次冒险一次。"
		"ranger_dig":
			return "挖掘宝藏（2）：前两次各获得 2 枚基础元素；第三次获得当前楼层装备三选一。最多三次。"
		"druid_infusion":
			return "自然灌注（3）：为一张非诅咒牌附加基础元素；本次冒险首次打出时施加该元素。"
	return "未知扎营活动。"


func _exchange_supply() -> void:
	session.exchange_camp_supply()


func _begin_remains_delivery() -> void:
	var result := session.begin_adventurer_remains_delivery()
	if not bool(result.get("ok", false)):
		_show_status(str(result.get("message", "当前无法交付遗骨。")))
		return
	_show_event_battle_reward_modal()


func _buy_stock(index: int) -> void:
	session.buy_shop_entry(index)


func _buy_camp_supply() -> void:
	session.buy_camp_supply()


func _remove_shop_card(hero_id: String, stack_id: String) -> void:
	if session.remove_shop_card(hero_id, stack_id):
		_hide_modal()
		_refresh()


func _apply_infusion(druid_id: String, target_id: String, stack_id: String, element: int) -> void:
	if session.infuse_card(druid_id, target_id, stack_id, element):
		_hide_modal()
		_refresh()
		return
	_hide_modal()
	_show_status("自然灌注未完成：请检查扎营点、目标牌和该牌是否已被元素灌注。")
	_refresh()


func _ritual_seal(hero_id: String, curse_id: String) -> void:
	session.seal_curse_at_camp(hero_id, curse_id)


func _ritual_unseal(hero_id: String) -> void:
	session.unseal_curse_at_camp(hero_id)


func _ritual_transfer(source_id: String, curse_id: String, target_id: String) -> void:
	session.transfer_curse_at_camp(source_id, curse_id, target_id)


func _begin_event_option(option_id: String) -> void:
	if option_id == "leave":
		_resolve_event_selection(option_id, {})
		return
	var selection := session.get_event_selection(option_id)
	match str(selection.get("kind", "none")):
		"hero":
			_show_event_hero_choice(option_id, selection)
		"hero_item":
			_show_event_hero_item_choice(option_id, selection)
		"altar":
			_show_event_altar_choice(option_id, selection)
		"cards":
			_show_event_card_choice(option_id, selection)
		"nature":
			_show_event_nature_choice(option_id, selection)
		_:
			_resolve_event_selection(option_id, {})


func _prepare_event_modal(title: String, intro: String) -> void:
	modal_layer.visible = true
	modal_title.text = title
	_clear_children(modal_body)
	event_altar_controls.clear()
	event_card_controls.clear()
	event_nature_controls.clear()
	var intro_label := Label.new()
	intro_label.text = intro
	intro_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro_label.add_theme_color_override("font_color", Color("#d7c797"))
	modal_body.add_child(intro_label)
	event_modal_feedback = Label.new()
	event_modal_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	event_modal_feedback.add_theme_color_override("font_color", Color("#d57568"))
	modal_body.add_child(event_modal_feedback)


func _show_event_hero_choice(option_id: String, selection: Dictionary) -> void:
	_prepare_event_modal(str(selection.get("title", "选择角色")), "选择后会立即锁定并结算该事件分支。")
	for hero_data in selection.get("heroes", []):
		if not (hero_data is Dictionary):
			continue
		var entry := hero_data as Dictionary
		var button := Button.new()
		button.text = "%s · 生命 %d/%d · 负荷 %d/%d" % [str(entry.get("name", "角色")), int(entry.get("health", 0)), int(entry.get("max_health", 0)), int(entry.get("load", 0)), int(entry.get("load_limit", 0))]
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.disabled = not bool(entry.get("available", true)) \
			or (option_id == "accept_fall" and int(entry.get("curse_capacity", 0)) < 2) \
			or (option_id == "share" and int(entry.get("curse_capacity", 0)) < 1)
		button.tooltip_text = "还能获得 %d 个普通业。" % int(entry.get("curse_capacity", 0))
		button.pressed.connect(_resolve_event_selection.bind(option_id, {"hero_id": str(entry.get("id", ""))}))
		modal_body.add_child(button)
	_add_modal_close_button()


func _show_event_hero_item_choice(option_id: String, selection: Dictionary) -> void:
	_prepare_event_modal(str(selection.get("title", "选择物品")), "每个按钮同时确定获得的消耗品与收入背包的角色。")
	for item_data in selection.get("items", []):
		if not (item_data is Dictionary):
			continue
		var item := item_data as Dictionary
		var heading := Label.new()
		heading.text = "%s\n%s" % [str(item.get("name", "消耗品")), str(item.get("description", ""))]
		heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		heading.add_theme_font_size_override("font_size", 17)
		modal_body.add_child(heading)
		var row := HBoxContainer.new()
		for hero_data in selection.get("heroes", []):
			if not (hero_data is Dictionary):
				continue
			var hero := hero_data as Dictionary
			var button := Button.new()
			button.text = "交给 %s · 空位 %d" % [str(hero.get("name", "角色")), int(hero.get("inventory_space", 0))]
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.disabled = not bool(hero.get("available", true))
			button.pressed.connect(_resolve_event_selection.bind(option_id, {"hero_id": str(hero.get("id", "")), "item_path": str(item.get("path", ""))}))
			row.add_child(button)
		modal_body.add_child(row)
	_add_modal_close_button()


func _show_event_altar_choice(option_id: String, selection: Dictionary) -> void:
	_prepare_event_modal(str(selection.get("title", "分配献祭")), "每个 x 恢复 10 点生命并获得 1 个随机普通业。选择 0 不影响其他角色。")
	for hero_data in selection.get("heroes", []):
		if not (hero_data is Dictionary):
			continue
		var hero := hero_data as Dictionary
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s · 生命 %d/%d · 负荷 %d/%d" % [str(hero.get("name", "角色")), int(hero.get("health", 0)), int(hero.get("max_health", 0)), int(hero.get("load", 0)), int(hero.get("load_limit", 0))]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = mini(3, int(hero.get("curse_capacity", 0)))
		spin.step = 1
		spin.value = 0
		spin.suffix = " 个业"
		spin.custom_minimum_size = Vector2(130.0, 34.0)
		row.add_child(spin)
		event_altar_controls[str(hero.get("id", ""))] = spin
		modal_body.add_child(row)
	var confirm := Button.new()
	confirm.text = "确认全队献祭选择"
	confirm.pressed.connect(_confirm_event_altar.bind(option_id))
	modal_body.add_child(confirm)
	_add_modal_close_button()


func _confirm_event_altar(option_id: String) -> void:
	var counts := {}
	for hero_id in event_altar_controls:
		var spin := event_altar_controls[hero_id] as SpinBox
		counts[hero_id] = roundi(spin.value) if spin != null else 0
	_resolve_event_selection(option_id, {"curse_counts": counts})


func _show_event_card_choice(option_id: String, selection: Dictionary) -> void:
	_prepare_event_modal(str(selection.get("title", "选择牌")), "只能选择同一名角色的 1 至 2 张牌。每移除 1 张，该角色获得 1 个随机普通业。")
	for hero_data in selection.get("heroes", []):
		if not (hero_data is Dictionary):
			continue
		var hero := hero_data as Dictionary
		var heading := Label.new()
		heading.text = "%s · 最多选择 %d 张 · 可承担 %d 个业" % [str(hero.get("name", "角色")), int(hero.get("max_count", 1)), int(hero.get("curse_capacity", 0))]
		heading.add_theme_font_size_override("font_size", 17)
		modal_body.add_child(heading)
		var controls: Array[Dictionary] = []
		for card_data in hero.get("cards", []):
			if not (card_data is Dictionary):
				continue
			var card := card_data as Dictionary
			var check := CheckBox.new()
			check.text = "%s · %s" % [str(card.get("name", "卡牌")), str(card.get("description", ""))]
			check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			controls.append({"button": check, "stack_id": str(card.get("id", ""))})
			modal_body.add_child(check)
		event_card_controls[str(hero.get("id", ""))] = controls
	var confirm := Button.new()
	confirm.text = "确认焚毁所选牌"
	confirm.pressed.connect(_confirm_event_cards.bind(option_id))
	modal_body.add_child(confirm)
	_add_modal_close_button()


func _confirm_event_cards(option_id: String) -> void:
	var selected_hero_id := ""
	var selected_stack_ids: Array[String] = []
	for hero_id in event_card_controls:
		var hero_selected: Array[String] = []
		for control_data in event_card_controls[hero_id]:
			var button := control_data.get("button") as CheckBox
			if button != null and button.button_pressed:
				hero_selected.append(str(control_data.get("stack_id", "")))
		if hero_selected.is_empty():
			continue
		if not selected_hero_id.is_empty():
			_set_event_feedback("只能选择同一名角色的牌。")
			return
		selected_hero_id = str(hero_id)
		selected_stack_ids = hero_selected
	if selected_stack_ids.size() < 1 or selected_stack_ids.size() > 2:
		_set_event_feedback("请选择 1 至 2 张牌。")
		return
	_resolve_event_selection(option_id, {"hero_id": selected_hero_id, "stack_ids": selected_stack_ids})


func _show_event_nature_choice(option_id: String, selection: Dictionary) -> void:
	_prepare_event_modal(str(selection.get("title", "大自然的恩惠")), "负荷达到上限者失去 10% 最大生命；请为其选择移除一个业或令一个报成熟 +1。")
	for hero_data in selection.get("heroes", []):
		if not (hero_data is Dictionary):
			continue
		var hero := hero_data as Dictionary
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = str(hero.get("name", "角色"))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var options := OptionButton.new()
		for choice_data in hero.get("choices", []):
			if choice_data is Dictionary:
				options.add_item(str(choice_data.get("label", "处理诅咒")))
				options.set_item_metadata(options.item_count - 1, str(choice_data.get("id", "")))
		if options.item_count == 0:
			options.add_item("没有可处理的业或报")
			options.set_item_metadata(0, "")
			options.disabled = true
		row.add_child(options)
		event_nature_controls[str(hero.get("id", ""))] = options
		modal_body.add_child(row)
	var confirm := Button.new()
	confirm.text = "确认接受恩惠"
	confirm.pressed.connect(_confirm_event_nature.bind(option_id))
	modal_body.add_child(confirm)
	_add_modal_close_button()


func _confirm_event_nature(option_id: String) -> void:
	var actions := {}
	for hero_id in event_nature_controls:
		var options := event_nature_controls[hero_id] as OptionButton
		actions[hero_id] = str(options.get_item_metadata(options.selected)) if options != null and options.item_count > 0 else ""
	_resolve_event_selection(option_id, {"curse_actions": actions})


func _resolve_event_selection(option_id: String, selection: Dictionary) -> void:
	var room := run_state.floor_state.get_current_room()
	var event_title := str(session.get_event_definition(room).get("title", "事件"))
	var result := session.resolve_current_event(option_id, selection)
	if bool(result.get("battle", false)):
		return
	if not bool(result.get("ok", false)):
		_set_event_feedback(str(result.get("message", "当前无法执行该选择。")))
		return
	_refresh()
	if bool(result.get("pending_event_reward", false)):
		_show_event_battle_reward_modal()
		return
	_show_event_result(event_title, str(result.get("message", "事件完成结算。")), bool(result.get("completed", false)))


func _show_event_result(event_title: String, message: String, completed: bool) -> void:
	modal_layer.visible = true
	modal_title.text = "%s · %s" % [event_title, "结算完成" if completed else "暂缓处理"]
	_clear_children(modal_body)
	var label := Label.new()
	label.text = message
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 17)
	modal_body.add_child(label)
	var close_button := Button.new()
	close_button.text = "返回地图"
	close_button.pressed.connect(_hide_modal)
	modal_body.add_child(close_button)


func _set_event_feedback(message: String) -> void:
	if event_modal_feedback != null and is_instance_valid(event_modal_feedback):
		event_modal_feedback.text = message
	else:
		_show_status(message)


func _show_event_battle_reward_modal() -> void:
	var reward := session.get_pending_event_reward()
	if reward.is_empty():
		return
	modal_layer.visible = true
	modal_title.text = "%s · 奖励选择" % str(reward.get("title", "事件战"))
	_clear_children(modal_body)
	var instructions := Label.new()
	instructions.text = str(reward.get("instructions", "请选择事件奖励。"))
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instructions.add_theme_color_override("font_color", Color("#d7c797"))
	modal_body.add_child(instructions)
	event_modal_feedback = Label.new()
	event_modal_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	event_modal_feedback.add_theme_color_override("font_color", Color("#d57568"))
	modal_body.add_child(event_modal_feedback)
	var kind := str(reward.get("kind", ""))
	if kind == "sealed_reliquary":
		_add_event_reward_hero_buttons("封印圣匣", "sealed_reliquary", "")
		return
	if kind == "arcanist":
		var load_heading := Label.new()
		load_heading.text = "方案一 · 本次冒险负荷上限 +2"
		load_heading.add_theme_font_size_override("font_size", 18)
		modal_body.add_child(load_heading)
		_add_event_reward_hero_buttons("负荷上限 +2", "arcanist_load", "")
		var pendant_heading := Label.new()
		pendant_heading.text = "方案二 · 获得奥能坠饰（装备后智力 +2）"
		pendant_heading.add_theme_font_size_override("font_size", 18)
		modal_body.add_child(pendant_heading)
		_add_event_reward_hero_buttons("奥能坠饰", "arcanist_pendant", "")
		return
	if kind == "remains_curse":
		_add_event_reward_hero_buttons("承受普通业", "remains_curse", "")
		return
	var equipment_entries := reward.get("equipment", []) as Array
	if not equipment_entries.is_empty():
		var claimed_equipment := str(reward.get("claimed_equipment", ""))
		var equipment_heading := Label.new()
		equipment_heading.text = "下一档装备 · %s" % ("已锁定" if not claimed_equipment.is_empty() else "选择 1 件")
		equipment_heading.add_theme_font_size_override("font_size", 18)
		modal_body.add_child(equipment_heading)
		for equipment_data in equipment_entries:
			if not (equipment_data is Dictionary):
				continue
			var equipment := equipment_data as Dictionary
			var item_row := HBoxContainer.new()
			var item_label := Label.new()
			item_label.text = "%s%s" % [str(equipment.get("name", "装备")), " · 已选择" if claimed_equipment == str(equipment.get("id", "")) else ""]
			item_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			item_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			item_row.add_child(item_label)
			var equipment_path := str(equipment.get("path", ""))
			var equipment_resource := load(equipment_path) as EquipmentData if ResourceLoader.exists(equipment_path) else null
			var detail_button := Button.new()
			detail_button.text = "详情"
			detail_button.disabled = equipment_resource == null
			detail_button.pressed.connect(
				_show_equipment_detail.bind(equipment_resource, {}, "event_reward")
			)
			item_row.add_child(detail_button)
			modal_body.add_child(item_row)
			if claimed_equipment.is_empty():
				_add_event_reward_hero_buttons("接收", "equipment", str(equipment.get("id", "")))
	if kind in ["chaos", "single_card"]:
		var claimed_cards := reward.get("claimed_cards", {}) as Dictionary
		for hero in run_state.party:
			if hero == null:
				continue
			var heading := Label.new()
			heading.text = "%s · 职业牌%s" % [hero.get_character_name(), " · 已锁定" if claimed_cards.has(hero.adventure_character_id) else ""]
			heading.add_theme_font_size_override("font_size", 18)
			modal_body.add_child(heading)
			for card_data in reward.get("cards", []):
				if not (card_data is Dictionary) or str(card_data.get("hero_id", "")) != hero.adventure_character_id:
					continue
				var card := card_data as Dictionary
				var button := Button.new()
				button.text = "[%s] %s · %d AP\n%s" % [CardEnums.rarity_label(int(card.get("rarity", CardEnums.Rarity.RARE))), str(card.get("name", "卡牌")), int(card.get("ap", 0)), str(card.get("description", ""))]
				button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				button.disabled = claimed_cards.has(hero.adventure_character_id)
				button.pressed.connect(_claim_event_battle_reward.bind("card", hero.adventure_character_id, str(card.get("id", ""))))
				modal_body.add_child(button)
	var finish := Button.new()
	finish.text = "确认所选奖励%s" % ("并立即进入战斗" if bool(reward.get("starts_battle", false)) else "")
	finish.pressed.connect(_settle_event_battle_reward)
	modal_body.add_child(finish)


func _add_event_reward_hero_buttons(prefix: String, action_id: String, candidate_id: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for hero in run_state.party:
		if hero == null:
			continue
		var button := Button.new()
		button.text = "%s：%s\n背包 %d/%d · 负荷 %d/%d" % [prefix, hero.get_character_name(), hero.get_inventory_item_count(), CharacterState.INVENTORY_LIMIT, hero.get_curse_load(), hero.get_curse_load_limit()]
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = action_id in ["sealed_reliquary", "arcanist_pendant", "equipment"] and hero.get_inventory_item_count() >= CharacterState.INVENTORY_LIMIT
		button.pressed.connect(_claim_event_battle_reward.bind(action_id, hero.adventure_character_id, candidate_id))
		row.add_child(button)
	modal_body.add_child(row)


func _claim_event_battle_reward(action_id: String, hero_id: String, candidate_id: String) -> void:
	var result := session.claim_pending_event_reward(action_id, hero_id, candidate_id)
	if not bool(result.get("ok", false)):
		_set_event_feedback(str(result.get("message", "无法领取该奖励。")))
		return
	_refresh()
	if session.has_pending_event_reward():
		_show_event_battle_reward_modal()
	else:
		_show_event_result("事件战", str(result.get("message", "奖励结算完成。")), true)


func _settle_event_battle_reward() -> void:
	var result := session.settle_pending_event_reward()
	if not bool(result.get("ok", false)):
		_set_event_feedback(str(result.get("message", "奖励尚未选择完整。")))
		return
	if bool(result.get("battle", false)):
		return
	_hide_modal()
	_refresh()


func _claim_reward(candidate_id: String, receiver_id: String = "") -> void:
	if not session.claim_reward_candidate(candidate_id, receiver_id):
		_show_status("无法领取该奖励，请检查接收者背包和奖励状态。")
	_show_reward_modal()


func _claim_gospel_reward(hero_id: String) -> void:
	session.claim_gospel_reward(hero_id)
	_show_reward_modal()


func _decline_gospel_reward() -> void:
	session.decline_gospel_reward()
	_show_reward_modal()


func _settle_reward() -> void:
	session.settle_pending_reward()
	_hide_modal()
	_refresh()
	_show_pending_state()


func _enter_next_floor() -> void:
	if session.enter_next_floor():
		selected_room_id = session.current_run.floor_state.current_room_id
		_hide_modal()
		_refresh()


func _start_new_run() -> void:
	if not _can_start_new_demo():
		_show_status("该存档版本不受支持，不能新建以免覆盖。")
		return
	var seed_value := int(seed_edit.text) if seed_edit.text.is_valid_int() else 0
	_show_new_run_confirmation(seed_value)


func _start_random_run() -> void:
	if not _can_start_new_demo():
		_show_status("该存档版本不受支持，不能新建以免覆盖。")
		return
	_show_new_run_confirmation(0)


func _on_enemy_health_percent_changed(value: float) -> void:
	if syncing_enemy_health_control or session == null:
		return
	session.set_enemy_health_percent(roundi(value))


func _show_new_run_confirmation(seed_value: int) -> void:
	modal_layer.visible = true
	modal_title.text = "开始新冒险"
	_clear_children(modal_body)
	var label := Label.new()
	label.text = "当前继续进度会被覆盖。%s" % ("" if seed_value == 0 else "\n新冒险种子：%d" % seed_value)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	modal_body.add_child(label)
	var confirm := Button.new()
	confirm.text = "确认覆盖"
	confirm.pressed.connect(_confirm_new_run.bind(seed_value))
	modal_body.add_child(confirm)
	_add_modal_close_button()


func _confirm_new_run(seed_value: int) -> void:
	var new_run := session.start_new_demo(seed_value)
	if new_run == null:
		_show_status("不能开始新冒险：当前存档受保护。")
		return
	run_state = new_run
	selected_room_id = run_state.floor_state.current_room_id
	_hide_modal()
	_refresh()


func _show_start_required() -> void:
	if modal_layer == null:
		return
	var load_status := session.save_store.load_status
	if load_status == AdventureSaveSchema.LoadStatus.UNSUPPORTED_SCHEMA:
		_show_simple_modal(
			"未来版本存档受保护",
			"检测到不受支持的新版本存档；不会读取或覆盖它。请使用兼容版本打开。",
			"关闭",
			_hide_modal
		)
		return
	var description := "当前新存档无法继续加载。"
	if load_status == AdventureSaveSchema.LoadStatus.LEGACY_SAVE_DETECTED:
		description = "检测到旧版 adventure_run 存档，已隔离且不会被读取或改写。"
	elif load_status == AdventureSaveSchema.LoadStatus.CORRUPT_SAVE:
		description = "当前新存档损坏且没有可用备份；可开始一个全新的 Demo。"
	_show_simple_modal(
		"需要开始新的冒险",
		description,
		"开始新的 Demo",
		_begin_new_run_from_gate
	)


func _begin_new_run_from_gate() -> void:
	var new_run := session.start_new_demo()
	if new_run == null:
		_show_status("不能开始新冒险：当前存档受保护。")
		return
	run_state = new_run
	selected_room_id = run_state.floor_state.current_room_id
	_hide_modal()
	_refresh()


func _can_start_new_demo() -> bool:
	return session != null and session.save_store != null \
		and session.save_store.load_status != AdventureSaveSchema.LoadStatus.UNSUPPORTED_SCHEMA


func _copy_seed() -> void:
	if run_state == null:
		_show_status("尚未开始可复制种子的冒险。")
		return
	DisplayServer.clipboard_set(str(run_state.run_seed))
	_show_status("种子已复制。")


func _hide_modal() -> void:
	modal_layer.visible = false


func _show_status(message: String) -> void:
	if status_label != null:
		status_label.text = message


func _hero_name(hero_id: String) -> String:
	for hero in run_state.party:
		if hero != null and hero.adventure_character_id == hero_id:
			return hero.get_character_name()
	return "未知角色"


func _get_hero_state(hero_id: String) -> CharacterState:
	for hero in run_state.party:
		if hero != null and hero.adventure_character_id == hero_id:
			return hero
	return null


func _first_hero_id_for_class(card_class: int) -> String:
	for hero in run_state.party:
		if hero != null and hero.character_data != null and hero.character_data.character_class == card_class:
			return hero.adventure_character_id
	return ""


func _first_transfer_target(source: CharacterState, curse: CurseInstance) -> String:
	for hero in run_state.party:
		if hero != null and hero != source and hero.get_curse(curse.get_curse_id()) == null:
			return hero.adventure_character_id
	return ""


func _top_label() -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 15)
	return label


func _clear_children(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
