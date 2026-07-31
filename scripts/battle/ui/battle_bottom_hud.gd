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
const AP_SLOT_LIMIT := 8
const AP_BANK_SIZE := Vector2(78.0, 24.0)
const AP_BANK_GAP := 3.0
const AP_ORB_SIZE := Vector2(17.0, 17.0)
const AP_SLOT_CENTER_RATIOS: Array[float] = [0.207, 0.408, 0.609, 0.811]
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
@onready var resource_label: Label = %ResourceLabel
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
	move_button.pressed.connect(func() -> void: move_pressed.emit())
	end_turn_button.pressed.connect(func() -> void: end_turn_pressed.emit())
	deck_button.pressed.connect(func() -> void: deck_pressed.emit())
	discard_button.pressed.connect(func() -> void: discard_pressed.emit())
	curse_button.pressed.connect(func() -> void: curse_pressed.emit())
	enchant_button.pressed.connect(func() -> void: enchant_pressed.emit())
	equipment_button.pressed.connect(func() -> void: equipment_pressed.emit())


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
		resource_label.text = "无角色资源"
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
	var max_ap := unit.get_max_ap(controller.config) if controller != null else 0
	ap_label.text = "AP"
	_refresh_ap_orbs(unit.current_ap, max_ap)
	portrait_rect.texture = _get_portrait(unit)
	resource_label.text = _build_resource_summary(unit)
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
	resource_label.add_theme_font_size_override("font_size", 11 if compact else 13)
	equipment_label.add_theme_font_size_override("font_size", 11 if compact else 13)


func set_equipment_actions(action_count: int, direct_label: String = "", direct_enabled: bool = true) -> void:
	if action_count <= 0:
		equipment_button.text = ""
		equipment_button.tooltip_text = "查看当前装备详情"
		equipment_button.disabled = bound_unit == null
		return
	if action_count == 1:
		equipment_button.text = direct_label
		equipment_button.tooltip_text = "直接执行：%s" % direct_label
		equipment_button.disabled = not direct_enabled
		return
	equipment_button.text = "展开  +%d" % action_count
	equipment_button.tooltip_text = "展开 %d 个装备动作" % action_count
	equipment_button.disabled = false


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
	button.tooltip_text = "%s\n%s" % [card.card_name, card.description]
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
	if unit == null or controller == null or not interactive:
		return
	if controller.can_use_druid_prepare_transform(unit):
		_add_class_action(
			&"druid_transform",
			"变形" if _compact_mode else "准备变形",
			"选择一张手牌逆置置入法力区，然后进入变身状态。",
			unit,
			true
		)
	elif controller.can_use_druid_prepare_untransform(unit):
		_add_class_action(
			&"druid_untransform",
			"复原" if _compact_mode else "准备复原",
			"支付 1 点法力解除变身状态。",
			unit,
			true
		)
	if unit.is_ranger() and unit.is_stealthed() \
			and unit.ranger_state.prepared_blend == BattleSurfaceState.Element.NONE:
		_add_class_action(
			&"ranger_blend",
			"特调",
			"消耗两枚不同基础元素，为近战或远程模式装填一份特调。",
			unit,
			unit.ranger_state.get_element_type_count() >= 2
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
	parts.append("力 %d  敏 %d  智 %d" % [unit.get_strength(), unit.get_agility(), unit.get_intelligence()])
	if unit.is_druid():
		parts.append("法力 %d/%d  %s" % [unit.get_available_mana(), unit.get_mana_capacity(), "变身" if unit.druid_transformed else "正位"])
	if unit.is_ranger():
		parts.append("连击 %d  %s" % [unit.ranger_state.combo_points, "潜行" if unit.is_stealthed() else "显形"])
	if unit.curse_wave > 0:
		parts.append("咒波 %d" % unit.curse_wave)
	return (" · " if _compact_mode else "\n").join(parts)


func _build_equipment_summary(unit: BattleUnitState, controller: BattleController) -> String:
	if unit.character_state == null:
		return "天生武器"
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
