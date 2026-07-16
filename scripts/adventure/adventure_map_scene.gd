extends Control
class_name AdventureMapScene

var session: AdventureSessionService
var run_state: PartyRunState
var selected_room_id: String = ""

var floor_label: Label
var gold_label: Label
var provisions_label: Label
var camp_label: Label
var ritual_label: Label
var ambush_label: Label
var seed_edit: LineEdit
var status_label: Label
var map_view: AdventureMapView
var detail_title: Label
var detail_body: RichTextLabel
var action_list: VBoxContainer
var party_list: HBoxContainer
var modal_layer: ColorRect
var modal_title: Label
var modal_body: VBoxContainer


func _ready() -> void:
	session = get_node_or_null("/root/AdventureSession") as AdventureSessionService
	if session == null:
		push_error("AdventureSession autoload is missing.")
		return
	_build_ui()
	session.state_changed.connect(_refresh)
	session.status_message.connect(_show_status)
	run_state = session.ensure_run()
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
	map_view.custom_minimum_size = Vector2(640.0, 420.0)
	map_view.room_selected.connect(_on_room_selected)
	map_view.room_hovered.connect(_on_room_hovered)
	map_panel.add_child(map_view)
	body.add_child(_build_detail_panel())
	root_stack.add_child(_build_party_bar())
	status_label = Label.new()
	status_label.custom_minimum_size = Vector2(0.0, 26.0)
	status_label.add_theme_color_override("font_color", Color("#d7c797"))
	root_stack.add_child(status_label)
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
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	margin.add_child(row)
	floor_label = _top_label()
	gold_label = _top_label()
	provisions_label = _top_label()
	camp_label = _top_label()
	ritual_label = _top_label()
	ambush_label = _top_label()
	for label in [floor_label, gold_label, provisions_label, camp_label, ritual_label, ambush_label]:
		row.add_child(label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	seed_edit = LineEdit.new()
	seed_edit.custom_minimum_size = Vector2(150.0, 34.0)
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
	return panel


func _build_detail_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(330.0, 0.0)
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
	detail_body.custom_minimum_size = Vector2(0.0, 180.0)
	stack.add_child(detail_body)
	var separator := HSeparator.new()
	stack.add_child(separator)
	var action_scroll := ScrollContainer.new()
	action_scroll.custom_minimum_size = Vector2(0.0, 180.0)
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
	panel.custom_minimum_size = Vector2(620.0, 420.0)
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


func _refresh() -> void:
	run_state = session.ensure_run()
	if run_state.floor_state == null:
		return
	floor_label.text = "第 %d/%d 层" % [run_state.floor_index + 1, run_state.floor_count]
	gold_label.text = "金币 %d" % run_state.gold
	provisions_label.text = "补给 %d" % run_state.provisions
	camp_label.text = "扎营 %d" % run_state.camp_points
	ritual_label.text = "仪式 %d" % run_state.ritual_points
	ambush_label.text = "伏击 %s" % ("免判定" if run_state.floor_state.watch_protection else "%d%%" % run_state.floor_state.ambush_chance)
	seed_edit.text = str(run_state.run_seed)
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
	var title := room.get_display_name()
	if room.room_type == AdventureEnums.RoomType.SHELTER:
		title = AdventureContentCatalog.get_shelter_name(room.shelter_type)
	elif room.room_type == AdventureEnums.RoomType.EVENT and room.content_revealed:
		title = str(session.get_event_definition(room).get("title", title))
	detail_title.text = title
	var state_text := "当前房间" if room.room_id == run_state.floor_state.current_room_id else ("已完成" if room.completed else ("已访问" if room.visited else "未访问"))
	var lines := PackedStringArray([
		"[color=#b9aa83]位置[/color]  (%d, %d)" % [room.cell.x, room.cell.y],
		"[color=#b9aa83]状态[/color]  %s" % state_text,
	])
	if room.room_type == AdventureEnums.RoomType.NORMAL_BATTLE:
		lines.append("[color=#b9aa83]怪池[/color]  %s" % AdventureEnums.encounter_tier_label(session.get_current_encounter_tier()))
	elif room.room_type == AdventureEnums.RoomType.EVENT:
		if room.content_revealed:
			var event := session.get_event_definition(room)
			lines.append("[color=#b9aa83]风险[/color]  %s" % str(event.get("risk", "未知")))
			lines.append("[color=#b9aa83]回报[/color]  %s" % str(event.get("reward", "未知")))
			lines.append("\n%s" % str(event.get("summary", "")))
		else:
			lines.append("具体事件进入房间后揭示。")
	if displayed_room_id != selected_room_id:
		lines.append("\n点击房间后可确认移动。")
	elif room.room_id != run_state.floor_state.current_room_id:
		if run_state.floor_state.are_connected(run_state.floor_state.current_room_id, room.room_id):
			lines.append("\n移动消耗 1 补给。")
			if run_state.provisions <= 0:
				var chance := 20 if run_state.floor_state.ambush_chance <= 0 else run_state.floor_state.ambush_chance
				lines.append("[color=#c45b52]本次伏击概率 %d%%[/color]" % chance)
			_add_action("前往此处", _move_to_selected)
		else:
			lines.append("\n该房间当前不可直接到达。")
	elif not room.completed:
		_build_current_room_actions(room)
	elif room.room_type in [AdventureEnums.RoomType.SHELTER, AdventureEnums.RoomType.SHOP]:
		_build_current_room_actions(room)
	detail_body.text = "\n".join(lines)


func _build_current_room_actions(room: AdventureRoomState) -> void:
	match room.room_type:
		AdventureEnums.RoomType.NORMAL_BATTLE, AdventureEnums.RoomType.ELITE_BATTLE, AdventureEnums.RoomType.BOSS_BATTLE:
			_add_action("开始战斗", _start_battle)
		AdventureEnums.RoomType.SHELTER:
			_add_action("免费休息", _rest, room.rest_used)
			_add_action("包扎选中角色 (2)", _camp_action.bind("bandage"))
			_add_action("战术推演 (2)", _camp_action.bind("tactics"))
			_add_action("侦察 (1)", _camp_action.bind("scout"))
			_add_action("守夜 (2)", _camp_action.bind("watch"))
			_add_action("战士：磨砺兵锋 (3)", _camp_action.bind("sharpen"))
			_add_action("游侠：挖掘宝藏 (2)", _camp_action.bind("ranger_dig"))
			_add_action("德鲁伊：自然灌注 (3)", _show_infusion_cards)
			_add_action("兑换扎营物资", _exchange_supply, run_state.camp_supplies <= 0)
			_build_ritual_actions()
		AdventureEnums.RoomType.SHOP:
			_build_shop_actions()
		AdventureEnums.RoomType.EVENT:
			var event := session.get_event_definition(room)
			for option_data in event.get("options", []):
				if option_data is Dictionary:
					_add_action(str(option_data.get("label", "选择")), _resolve_event.bind(str(option_data.get("id", "leave"))))
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
	_add_action("购买补给  5 金", _buy_provision)
	_add_action("购买扎营物资  15 金", _buy_camp_supply)
	var room := run_state.floor_state.get_current_room()
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
		party_list.add_child(panel)


func _show_pending_state() -> void:
	if run_state.run_failed:
		_show_simple_modal("冒险失败", "小队已经覆灭。", "以同一种子重开", session.restart_same_seed)
	elif run_state.run_complete:
		_show_simple_modal("Demo 通关", "第二层首领已被击败，本次冒险完成。", "关闭", _hide_modal)
	elif session.has_pending_reward():
		_show_reward_modal()
	elif run_state.pending_transaction != null and run_state.pending_transaction.transaction_type == AdventureEnums.TransactionType.BATTLE:
		_show_simple_modal("伏击或战斗待处理", "遭遇已经锁定，继续后不会重新生成敌群。", "进入战斗", session.resume_pending_battle)
	elif bool(run_state.adventure_flags.get("interfloor_camp", false)):
		_show_simple_modal("层间营地", "队伍将在离开时休息并获得 4 点扎营点。", "进入下一层", _enter_next_floor)


func _show_reward_modal() -> void:
	modal_layer.visible = true
	modal_title.text = "战斗奖励"
	_clear_children(modal_body)
	var reward := session.get_pending_reward()
	var fixed := Label.new()
	fixed.text = "金币 +%d   补给 +%d   仪式点 +%d   扎营物资 +%d" % [
		int(reward.get("gold", 0)), int(reward.get("provisions", 0)), int(reward.get("ritual_points", 0)), int(reward.get("camp_supplies", 0)),
	]
	modal_body.add_child(fixed)
	for card_data in reward.get("cards", []):
		if card_data is Dictionary:
			var button := Button.new()
			button.text = "%s · %s" % [str(card_data.get("name", "卡牌")), _hero_name(str(card_data.get("hero_id", "")))]
			button.disabled = (reward.get("claimed_cards", []) as Array).has(str(card_data.get("id", "")))
			button.pressed.connect(_claim_reward.bind(str(card_data.get("id", ""))))
			modal_body.add_child(button)
	for equipment_data in reward.get("equipment", []):
		if equipment_data is Dictionary:
			var button := Button.new()
			button.text = "装备 · %s" % str(equipment_data.get("name", "装备"))
			button.disabled = (reward.get("claimed_equipment", []) as Array).has(str(equipment_data.get("id", "")))
			button.pressed.connect(_claim_reward.bind(str(equipment_data.get("id", ""))))
			modal_body.add_child(button)
	var finish := Button.new()
	finish.text = "完成奖励选择"
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
			if stack == null or stack.card_data == null or stack.card_data.is_curse_card() \
				or hero.card_adventure_modifiers.has(stack.stack_id):
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


func _add_action(label: String, callback: Callable, disabled: bool = false) -> void:
	var button := Button.new()
	button.text = label
	button.disabled = disabled
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
		if bool(result.get("ambush", false)):
			_show_pending_state()


func _start_battle() -> void:
	session.start_current_battle()


func _rest() -> void:
	session.rest_at_current_shelter()


func _camp_action(activity_id: String) -> void:
	var hero_id := run_state.party[0].adventure_character_id if not run_state.party.is_empty() else ""
	if activity_id == "sharpen":
		hero_id = _first_hero_id_for_class(CardEnums.CardClass.WARRIOR)
	elif activity_id == "ranger_dig":
		hero_id = _first_hero_id_for_class(CardEnums.CardClass.RANGER)
	session.use_camp_activity(activity_id, hero_id)


func _exchange_supply() -> void:
	session.exchange_camp_supply()


func _buy_stock(index: int) -> void:
	session.buy_shop_entry(index)


func _buy_provision() -> void:
	session.buy_provision()


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


func _ritual_seal(hero_id: String, curse_id: String) -> void:
	session.seal_curse_at_camp(hero_id, curse_id)


func _ritual_unseal(hero_id: String) -> void:
	session.unseal_curse_at_camp(hero_id)


func _ritual_transfer(source_id: String, curse_id: String, target_id: String) -> void:
	session.transfer_curse_at_camp(source_id, curse_id, target_id)


func _resolve_event(option_id: String) -> void:
	var hero_id := run_state.party[0].adventure_character_id if not run_state.party.is_empty() else ""
	var result := session.resolve_current_event(option_id, hero_id)
	_show_status(str(result.get("message", "")))
	_refresh()


func _claim_reward(candidate_id: String) -> void:
	session.claim_reward_candidate(candidate_id)
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
	var seed_value := int(seed_edit.text) if seed_edit.text.is_valid_int() else 0
	_show_new_run_confirmation(seed_value)


func _start_random_run() -> void:
	_show_new_run_confirmation(0)


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
	session.start_new_demo(seed_value)
	run_state = session.current_run
	selected_room_id = run_state.floor_state.current_room_id
	_hide_modal()
	_refresh()


func _copy_seed() -> void:
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
