extends Control
class_name BattleBottomHud

signal card_pressed(card: CardData)
signal card_hovered(card: CardData)
signal card_unhovered(card: CardData)
signal move_pressed
signal end_turn_pressed
signal deck_pressed
signal discard_pressed
signal curse_pressed
signal enchant_pressed
signal equipment_pressed
signal class_action_pressed(action_id: StringName, unit: BattleUnitState)

const HAND_CARD_SLOT_TEXTURE := preload("res://assets/art/ui/hand_card_slot.png")
const AP_SLOT_FRAME_TEXTURE := preload("res://assets/art/ui/ap_slot_frame.png")
const AP_ORB_FULL_TEXTURE := preload("res://assets/art/ui/ap_orb_full.png")
const BattleSurfaceState = preload("res://scripts/battle/battle_surface_state.gd")
const AP_SLOT_LIMIT := 8
const AP_BANK_SIZE := Vector2(94.0, 30.0)
const AP_BANK_GAP := 3.0
const AP_ORB_SIZE := Vector2(22.0, 22.0)
const AP_SLOT_CENTER_RATIOS: Array[float] = [0.207, 0.408, 0.609, 0.811]
const STATUS_GROUP_GAP := 4.0
const STANDARD_VITALS_SIZE := Vector2(286.0, 92.0)
const COMPACT_VITALS_SIZE := Vector2(270.0, 92.0)
const ALLY_ACCENT := Color(0.22, 0.84, 0.49, 1.0)
const ENCHANT_ACCENT := Color(0.22, 0.82, 0.88, 1.0)
const EQUIPMENT_ACCENT := Color(0.94, 0.65, 0.22, 1.0)
const CURSE_ACCENT := Color(0.86, 0.25, 0.72, 1.0)
const PARCHMENT_TEXT := Color(0.16, 0.09, 0.035, 1.0)

var bound_unit: BattleUnitState
var bound_controller: BattleController
var _compact_mode := false

@onready var portrait_rect: TextureRect = %PortraitRect
@onready var name_label: Label = %BoundUnitLabel
@onready var health_bar: ProgressBar = %HealthBar
@onready var health_label: Label = %HealthLabel
@onready var ap_label: Label = %APLabel
@onready var ap_orb_layer: Control = %APOrbLayer
@onready var status_row: Control = %StatusRow
@onready var left_status_group: HBoxContainer = %LeftStatusGroup
@onready var right_status_group: HBoxContainer = %RightStatusGroup
@onready var vitals_region: PanelContainer = %VitalsRegion
@onready var equipment_region: PanelContainer = %EquipmentRegion
@onready var enchant_region: PanelContainer = %EnchantRegion
@onready var curse_region: PanelContainer = %CurseRegion
@onready var command_region: PanelContainer = %CommandRegion
@onready var character_resource_region: PanelContainer = %CharacterResourceRegion
@onready var status_region: PanelContainer = %StatusRegion
@onready var character_resource_label: Label = %CharacterResourceLabel
@onready var status_label: Label = %StatusLabel
@onready var resource_action_list: HBoxContainer = %ResourceActionList
@onready var equipment_label: Label = %EquipmentLabel
@onready var enchant_label: Label = %EnchantLabel
@onready var curse_label: Label = %CurseLabel
@onready var hand_list: HBoxContainer = %HandList
@onready var move_button: Button = %HudMoveButton
@onready var end_turn_button: Button = %HudEndTurnButton
@onready var equipment_button: Button = %EquipmentButton
@onready var enchant_button: Button = %EnchantButton
@onready var curse_button: Button = %HudCurseButton
@onready var deck_button: TextureButton = %HudDeckButton
@onready var discard_button: TextureButton = %HudDiscardButton


func _ready() -> void:
	left_status_group.move_child(curse_region, 0)
	move_button.pressed.connect(func() -> void: move_pressed.emit())
	end_turn_button.pressed.connect(func() -> void: end_turn_pressed.emit())
	deck_button.pressed.connect(func() -> void: deck_pressed.emit())
	discard_button.pressed.connect(func() -> void: discard_pressed.emit())
	curse_button.pressed.connect(func() -> void: curse_pressed.emit())
	enchant_button.pressed.connect(func() -> void: enchant_pressed.emit())
	equipment_button.pressed.connect(func() -> void: equipment_pressed.emit())
	status_row.resized.connect(_queue_status_layout)
	_queue_status_layout()


func bind_unit(unit: BattleUnitState, controller: BattleController, interactive: bool) -> void:
	bound_unit = unit
	bound_controller = controller
	if unit == null:
		name_label.text = "等待行动单位"
		health_label.text = "生命 -"
		health_bar.max_value = 1.0
		health_bar.value = 0.0
		ap_label.text = "AP"
		portrait_rect.texture = null
		character_resource_label.text = "无角色资源"
		status_label.text = "力 -  敏 -  智 -"
		equipment_label.text = "未选择装备"
		enchant_label.text = "附魔 0"
		curse_label.text = "诅咒 0"
		_refresh_ap_orbs(0, 0)
		_refresh_class_actions(null, controller, false)
		_set_interactive(false)
		return

	name_label.text = unit.get_display_name()
	var max_health := maxi(1, unit.get_max_health())
	health_bar.max_value = float(max_health)
	health_bar.value = float(clampi(unit.get_current_health(), 0, max_health))
	health_label.text = "%d/%d  护甲 %d" % [unit.get_current_health(), max_health, unit.get_armor_stacks()]
	var shared_armor := unit.get_shared_armor_stacks()
	if shared_armor > 0:
		health_label.text += "  共有 %d" % shared_armor
	var max_ap := unit.get_max_ap(controller.config) if controller != null else 0
	ap_label.text = "AP"
	_refresh_ap_orbs(unit.current_ap, max_ap)
	portrait_rect.texture = _get_portrait(unit)
	character_resource_label.text = _build_resource_summary(unit)
	status_label.text = _build_status_summary(unit)
	_refresh_class_actions(unit, controller, interactive)
	equipment_label.text = _build_equipment_summary(unit, controller)
	enchant_label.text = _build_zone_summary("附魔", unit.enchant_zone)
	curse_label.text = "%s\n咒波 %d" % [_build_zone_summary("诅咒", unit.curse_zone, false), unit.curse_wave]
	_set_interactive(interactive)
	deck_button.call("set_pile", "牌库", unit.draw_pile.size(), ALLY_ACCENT)
	discard_button.call("set_pile", "弃牌", unit.discard_pile.size(), EQUIPMENT_ACCENT)


func bind_hand(cards: Array[CardData], costs: Array[int], interactive: bool) -> void:
	_clear_children(hand_list)
	for index in range(cards.size()):
		var card := cards[index]
		if card == null:
			continue
		var cost := costs[index] if index < costs.size() else card.ap_cost
		hand_list.add_child(_create_card_button(card, cost, interactive))
	if cards.is_empty():
		var empty_label := Label.new()
		empty_label.custom_minimum_size = Vector2(220.0, 86.0)
		empty_label.text = "当前没有可显示的手牌"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hand_list.add_child(empty_label)


func set_compact(compact: bool) -> void:
	_compact_mode = compact
	character_resource_label.add_theme_font_size_override("font_size", 10 if compact else 11)
	status_label.add_theme_font_size_override("font_size", 10 if compact else 11)
	equipment_label.add_theme_font_size_override("font_size", 11 if compact else 13)
	vitals_region.custom_minimum_size = COMPACT_VITALS_SIZE if compact else STANDARD_VITALS_SIZE
	equipment_region.custom_minimum_size = Vector2(100.0 if compact else 136.0, 76.0)
	enchant_region.custom_minimum_size = Vector2(104.0 if compact else 108.0, 76.0)
	curse_region.custom_minimum_size = Vector2(104.0 if compact else 108.0, 76.0)
	command_region.custom_minimum_size = Vector2(42.0, 76.0)
	character_resource_region.custom_minimum_size = Vector2(112.0 if compact else 132.0, 76.0)
	status_region.custom_minimum_size = character_resource_region.custom_minimum_size
	_queue_status_layout()


func _queue_status_layout() -> void:
	if not is_inside_tree():
		return
	call_deferred("_layout_status_groups")


func _layout_status_groups() -> void:
	if not is_instance_valid(status_row) or status_row.size.x <= 0.0:
		return
	var vitals_size := vitals_region.custom_minimum_size
	vitals_region.offset_left = -vitals_size.x * 0.5
	vitals_region.offset_top = -vitals_size.y
	vitals_region.offset_right = vitals_size.x * 0.5
	vitals_region.offset_bottom = 0.0

	var left_size := left_status_group.get_combined_minimum_size()
	var right_size := right_status_group.get_combined_minimum_size()
	left_status_group.size = left_size
	right_status_group.size = right_size
	var vitals_rect := vitals_region.get_rect()
	left_status_group.position = Vector2(
		vitals_rect.position.x - STATUS_GROUP_GAP - left_size.x,
		status_row.size.y - left_size.y
	)
	right_status_group.position = Vector2(
		vitals_rect.end.x + STATUS_GROUP_GAP,
		status_row.size.y - right_size.y
	)


func set_equipment_actions(action_count: int, direct_label: String = "", direct_enabled: bool = true) -> void:
	# EquipmentLabel is the sole text layer inside this button. Drawing Button.text
	# as well makes both labels occupy the same rectangle.
	equipment_button.text = ""
	var equipment_summary := _build_equipment_summary(bound_unit, bound_controller) if bound_unit != null else "未选择装备"
	var preserve_warrior_summary := bound_unit != null \
		and bound_unit.get_character_class() == CardEnums.CardClass.WARRIOR
	if action_count <= 0:
		equipment_label.text = equipment_summary
		equipment_button.tooltip_text = "查看当前装备详情"
		equipment_button.disabled = bound_unit == null
		return
	if action_count == 1:
		equipment_label.text = equipment_summary if preserve_warrior_summary else _format_equipment_action_summary(direct_label)
		equipment_button.tooltip_text = "直接执行：%s" % direct_label
		equipment_button.disabled = not direct_enabled
		return
	equipment_label.text = equipment_summary if preserve_warrior_summary else "装备动作 %d 项\n点击展开" % action_count
	equipment_button.tooltip_text = "展开 %d 个装备动作" % action_count
	equipment_button.disabled = false


func _format_equipment_action_summary(action_label: String) -> String:
	var separator_index := action_label.find("：")
	if separator_index < 0:
		return action_label
	return "%s\n%s" % [
		action_label.left(separator_index + 1),
		action_label.substr(separator_index + 1).strip_edges(),
	]


func get_bound_unit() -> BattleUnitState:
	return bound_unit


func get_class_action_count() -> int:
	return resource_action_list.get_child_count()


func _create_card_button(card: CardData, cost: int, interactive: bool) -> TextureButton:
	var button := TextureButton.new()
	button.texture_normal = HAND_CARD_SLOT_TEXTURE
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.custom_minimum_size = Vector2(96.0, 116.0)
	button.tooltip_text = "%s\n%s" % [card.card_name, RulesTextFormatter.format_card(card, {
		"user": bound_unit,
		"effective_ap_cost": cost,
	})]
	button.disabled = not interactive
	button.set_meta("card", card)
	button.pressed.connect(func() -> void: card_pressed.emit(card))
	button.mouse_entered.connect(func() -> void: card_hovered.emit(card))
	button.mouse_exited.connect(func() -> void: card_unhovered.emit(card))

	var label := Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.text = "%s\n%d AP" % [card.card_name, cost]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", PARCHMENT_TEXT)
	button.add_child(label)
	return button


func _refresh_ap_orbs(current_ap: int, max_ap: int) -> void:
	_clear_children(ap_orb_layer)
	var available := clampi(current_ap, 0, AP_SLOT_LIMIT)
	var capacity := clampi(maxi(max_ap, available), 0, AP_SLOT_LIMIT)
	for bank_index in range(2):
		var bank := TextureRect.new()
		bank.position = Vector2(bank_index * (AP_BANK_SIZE.x + AP_BANK_GAP), 0.0)
		bank.size = AP_BANK_SIZE
		bank.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bank.texture = AP_SLOT_FRAME_TEXTURE
		bank.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bank.stretch_mode = TextureRect.STRETCH_SCALE
		bank.set_meta("ap_bank", bank_index)
		ap_orb_layer.add_child(bank)

	for index in range(AP_SLOT_LIMIT):
		var slot := Control.new()
		var bank_index: int = index / 4
		var slot_in_bank: int = index % 4
		var center_x: float = AP_BANK_SIZE.x * AP_SLOT_CENTER_RATIOS[slot_in_bank]
		slot.position = Vector2(
			bank_index * (AP_BANK_SIZE.x + AP_BANK_GAP) + center_x - AP_ORB_SIZE.x * 0.5,
			(AP_BANK_SIZE.y - AP_ORB_SIZE.y) * 0.5
		)
		slot.size = AP_ORB_SIZE
		var state := "filled" if index < available else ("empty" if index < capacity else "locked")
		slot.set_meta("ap_state", state)
		slot.tooltip_text = "可用 AP" if state == "filled" else ("空 AP 槽" if state == "empty" else "未解锁 AP 槽")
		if state != "empty":
			var orb := TextureRect.new()
			orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			orb.texture = AP_ORB_FULL_TEXTURE
			orb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			orb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			orb.modulate = Color.WHITE if state == "filled" else Color(0.14, 0.13, 0.12, 0.82)
			slot.add_child(orb)
			orb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ap_orb_layer.add_child(slot)


func _set_interactive(interactive: bool) -> void:
	move_button.disabled = not interactive
	end_turn_button.disabled = not interactive
	deck_button.disabled = not interactive
	discard_button.disabled = not interactive
	curse_button.disabled = bound_unit == null
	enchant_button.disabled = bound_unit == null
	equipment_button.disabled = bound_unit == null


func _refresh_class_actions(unit: BattleUnitState, controller: BattleController, interactive: bool) -> void:
	_clear_children(resource_action_list)
	if unit == null or controller == null:
		return
	for hand_card in unit.hand:
		if hand_card != null and hand_card.get_twin_spell_face() >= 0:
			var twin_hint := Label.new()
			twin_hint.text = "双生入区：从手牌点选双生法术，可免费置入法力区并检索相反牌面。"
			twin_hint.tooltip_text = "仅实际查看牌库时洗牌；只查看弃牌堆不洗牌。"
			twin_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			resource_action_list.add_child(twin_hint)
			break
	if interactive and controller.can_use_druid_prepare_transform(unit):
		_add_class_action(
			&"druid_transform",
			"变形" if _compact_mode else "准备变形",
			"选择一张手牌逆置置入法力区，然后进入变形状态。",
			unit,
			true
		)
	elif interactive and controller.can_use_druid_prepare_untransform(unit):
		_add_class_action(
			&"druid_untransform",
			"复原" if _compact_mode else "准备复原",
			"支付 1 点法力解除变形状态。",
			unit,
			true
		)
	if unit.is_ranger() and unit.is_alive() \
			and unit.ranger_state.prepared_blend == BattleSurfaceState.Element.NONE:
		var can_prepare_blend := controller.can_prepare_ranger_blend(unit)
		var blend_tooltip := "每回合一次：在自己的自由时间消耗两枚不同基础元素，为近战或远程模式装填一份特调。只有实际进入潜行（从非潜行转变）才会刷新这次机会。"
		if not can_prepare_blend:
			blend_tooltip += "\n当前不能调配：调配机会可能已用尽，或不在自己的自由时间，或元素不足。"
		_add_class_action(
			&"ranger_blend",
			"特调",
			blend_tooltip,
			unit,
			can_prepare_blend
		)


func _add_class_action(
		action_id: StringName,
		label: String,
		tooltip: String,
		unit: BattleUnitState,
		enabled: bool
) -> void:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0.0, 18.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.text = label
	button.tooltip_text = tooltip
	button.disabled = not enabled
	button.flat = true
	button.add_theme_font_size_override("font_size", 10)
	button.pressed.connect(func() -> void: class_action_pressed.emit(action_id, unit))
	resource_action_list.add_child(button)


func _build_resource_summary(unit: BattleUnitState) -> String:
	var parts := PackedStringArray()
	if unit.get_character_class() == CardEnums.CardClass.WARRIOR:
		parts.append("势 %d/5" % unit.get_class_resource_value(BattleController.WARRIOR_MOMENTUM_RESOURCE))
	if unit.is_druid():
		parts.append("法力 %d  法力区 %d张\n%s" % [unit.get_available_mana(), unit.mana_zone.size(), "变形：回合结束支付1法力" if unit.druid_transformed else "人形：回合开始产法，结束清空"])
	if unit.is_ranger():
		parts.append("元素 %s" % unit.ranger_state.get_summary())
		parts.append("连击 %d  %s" % [unit.ranger_state.combo_points, "潜行" if unit.is_stealthed() else "显形"])
	if unit.is_mage_adventurer():
		var mana_parts := PackedStringArray()
		for element in BattleSurfaceState.BASE_ELEMENTS:
			mana_parts.append("%s%d" % [BattleSurfaceState.label(element), unit.mage_state.get_mana(element)])
		parts.append("法术力 %s" % " ".join(mana_parts))
	if unit.is_warlock_adventurer():
		parts.append("术士法力 %d" % unit.warlock_state.get_mana())
	return "\n".join(parts) if not parts.is_empty() else "无特色资源"


func _build_status_summary(unit: BattleUnitState) -> String:
	return "力量 %d\n敏捷 %d\n智力 %d" % [
		unit.get_strength(),
		unit.get_agility(),
		unit.get_intelligence(),
	]


func _build_equipment_summary(unit: BattleUnitState, controller: BattleController) -> String:
	if unit.character_state == null:
		return "天生武器"
	if unit.get_character_class() == CardEnums.CardClass.WARRIOR:
		var current_weapon := unit.get_active_weapon_equipment()
		var reserve_weapon := unit.character_state.reserve_weapon_equipment
		if reserve_weapon != null:
			reserve_weapon = reserve_weapon.get_face(unit.character_state.reserve_weapon_face)
		return "%s\n%s" % [
			tr("当前：%s") % (current_weapon.item_name if current_weapon != null else tr("徒手")),
			tr("备战：%s") % (reserve_weapon.item_name if reserve_weapon != null else tr("无")),
		]
	var parts := PackedStringArray([unit.character_state.get_main_hand_label()])
	var off_hand := unit.character_state.get_off_hand_label()
	if not off_hand.is_empty() and off_hand != parts[0]:
		parts.append(off_hand)
	var runtime := unit.get_equipment_runtime_summary({"controller": controller, "unit": unit})
	if not runtime.is_empty():
		parts.append(runtime)
	return " · ".join(parts)


func _build_zone_summary(title: String, entries: Array, include_title_line: bool = true) -> String:
	var names := PackedStringArray()
	for entry in entries:
		if entry is CardData:
			names.append((entry as CardData).card_name)
		elif entry is CurseInstance:
			names.append((entry as CurseInstance).get_display_name())
		if names.size() >= 3:
			break
	var heading := "%s %d" % [title, entries.size()]
	if names.is_empty():
		return heading
	var name_line := " · ".join(names)
	if entries.size() > names.size():
		name_line += " +%d" % (entries.size() - names.size())
	return "%s\n%s" % [heading, name_line] if include_title_line else "%s · %s" % [heading, name_line]


func _get_portrait(unit: BattleUnitState) -> Texture2D:
	if unit.character_state != null and unit.character_state.character_data != null:
		return unit.character_state.character_data.portrait
	if unit.enemy_state != null and unit.enemy_state.enemy_data != null:
		return unit.enemy_state.enemy_data.portrait
	return null


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
