extends PanelContainer
class_name BattleBottomHud

signal card_pressed(card: CardData)
signal card_hovered(card: CardData)
signal card_unhovered(card: CardData)
signal move_pressed
signal attack_pressed
signal end_turn_pressed
signal deck_pressed
signal discard_pressed
signal curse_pressed
signal enchant_pressed
signal equipment_pressed

const HAND_CARD_SLOT_TEXTURE := preload("res://assets/art/ui/hand_card_slot.png")
const AP_ORB_FULL_TEXTURE := preload("res://assets/art/ui/ap_orb_full.png")
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
@onready var health_label: Label = %HealthLabel
@onready var ap_label: Label = %APLabel
@onready var ap_orb_layer: HBoxContainer = %APOrbLayer
@onready var resource_label: Label = %ResourceLabel
@onready var equipment_label: Label = %EquipmentLabel
@onready var enchant_label: Label = %EnchantLabel
@onready var curse_label: Label = %CurseLabel
@onready var hand_list: HBoxContainer = %HandList
@onready var move_button: Button = %HudMoveButton
@onready var attack_button: Button = %HudAttackButton
@onready var end_turn_button: Button = %HudEndTurnButton
@onready var equipment_button: Button = %EquipmentButton
@onready var enchant_button: Button = %EnchantButton
@onready var curse_button: Button = %HudCurseButton
@onready var deck_button: TextureButton = %HudDeckButton
@onready var discard_button: TextureButton = %HudDiscardButton


func _ready() -> void:
	move_button.pressed.connect(func() -> void: move_pressed.emit())
	attack_button.pressed.connect(func() -> void: attack_pressed.emit())
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
		ap_label.text = "AP -"
		portrait_rect.texture = null
		resource_label.text = "无角色资源"
		equipment_label.text = "未选择装备"
		enchant_label.text = "附魔 0"
		curse_label.text = "诅咒 0"
		_refresh_ap_orbs(0, 0)
		_set_interactive(false)
		return

	name_label.text = unit.get_display_name()
	health_label.text = "生命 %d / %d   护甲 %d" % [unit.get_current_health(), unit.get_max_health(), unit.get_armor_stacks()]
	var max_ap := unit.get_max_ap(controller.config) if controller != null else 0
	ap_label.text = "AP %d / %d" % [unit.current_ap, max_ap]
	_refresh_ap_orbs(unit.current_ap, max_ap)
	portrait_rect.texture = _get_portrait(unit)
	resource_label.text = _build_resource_summary(unit)
	equipment_label.text = _build_equipment_summary(unit, controller)
	enchant_label.text = "附魔 %d" % unit.enchant_zone.size()
	curse_label.text = "诅咒 %d\n咒波 %d" % [unit.curse_zone.size(), unit.curse_wave]
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


func _create_card_button(card: CardData, cost: int, interactive: bool) -> TextureButton:
	var button := TextureButton.new()
	button.texture_normal = HAND_CARD_SLOT_TEXTURE
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.custom_minimum_size = Vector2(112.0, 138.0)
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
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", PARCHMENT_TEXT)
	button.add_child(label)
	return button


func _refresh_ap_orbs(current_ap: int, max_ap: int) -> void:
	_clear_children(ap_orb_layer)
	var visible_slots := clampi(max_ap, 0, 6)
	for index in range(visible_slots):
		var slot := TextureRect.new()
		slot.custom_minimum_size = Vector2(22.0, 22.0)
		slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if index < current_ap:
			slot.texture = AP_ORB_FULL_TEXTURE
		else:
			slot.modulate = Color(0.28, 0.25, 0.2, 0.7)
		ap_orb_layer.add_child(slot)


func _set_interactive(interactive: bool) -> void:
	move_button.disabled = not interactive
	attack_button.disabled = not interactive
	end_turn_button.disabled = not interactive
	deck_button.disabled = not interactive
	discard_button.disabled = not interactive
	curse_button.disabled = bound_unit == null
	enchant_button.disabled = bound_unit == null
	equipment_button.disabled = bound_unit == null


func _build_resource_summary(unit: BattleUnitState) -> String:
	var parts := PackedStringArray()
	parts.append("力 %d  敏 %d  智 %d" % [unit.get_strength(), unit.get_agility(), unit.get_intelligence()])
	if unit.is_druid():
		parts.append("法力 %d/%d  %s" % [unit.get_available_mana(), unit.get_mana_capacity(), "变身" if unit.druid_transformed else "正位"])
	if unit.is_ranger():
		parts.append("连击 %d  %s" % [unit.ranger_state.combo_points, "潜行" if unit.is_stealthed() else "显形"])
	if unit.curse_wave > 0:
		parts.append("咒波 %d" % unit.curse_wave)
	return "\n".join(parts)


func _build_equipment_summary(unit: BattleUnitState, controller: BattleController) -> String:
	if unit.character_state == null:
		return "天生武器"
	var parts := PackedStringArray([
		unit.character_state.get_main_hand_label(),
		unit.character_state.get_off_hand_label(),
	])
	var runtime := unit.get_equipment_runtime_summary({"controller": controller, "unit": unit})
	if not runtime.is_empty():
		parts.append(runtime)
	return "\n".join(parts)


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
