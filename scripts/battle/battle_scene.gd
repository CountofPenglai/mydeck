extends Control
class_name BattleScene

const HAND_CARD_SLOT_TEXTURE := preload("res://assets/art/ui/hand_card_slot.png")
const AP_ORB_FULL_TEXTURE := preload("res://assets/art/ui/ap_orb_full.png")
const DEFAULT_SCENARIO := preload("res://resources/battle/sample_battle_scenario.tres")
const AP_ORB_SLOT_X := [0.158, 0.384, 0.614, 0.842]
const AP_ORB_SLOT_Y := 0.49
const AP_ORB_SIZE_RATIO := 0.66

enum InputMode {
	NONE,
	MOVE,
	BASIC_ATTACK_TARGET,
	CARD_TARGET,
}

@export var scenario: BattleScenario

var controller := BattleController.new()
var selected_deploy_unit: BattleUnitState
var input_mode: int = InputMode.NONE
var pending_card: CardData
var pending_play_mode: int = CardEnums.CardPlayMode.NORMAL
var pending_equipment_slot: String = ""
var pending_extra_context: Dictionary = {}
var _weapon_choice_popup: PopupPanel
var _weapon_choice_list: VBoxContainer
var _weapon_choice_next_mode: int = InputMode.NONE
var _weapon_choice_card: CardData
var _weapon_choice_play_mode: int = CardEnums.CardPlayMode.NORMAL
var _weapon_choice_extra_context: Dictionary = {}
var _play_choice_popup: PopupPanel
var _play_choice_list: VBoxContainer
var _play_choice_card: CardData
var _discard_popup: PopupPanel
var _discard_list: VBoxContainer
var _draw_choice_popup: PopupPanel
var _draw_choice_list: VBoxContainer
var _draw_choice_card: CardData
var _draw_choice_play_mode: int = CardEnums.CardPlayMode.NORMAL
var _ordered_discard_popup: PopupPanel
var _ordered_discard_list: VBoxContainer
var _ordered_discard_selected_label: Label
var _ordered_discard_card: CardData
var _ordered_discard_play_mode: int = CardEnums.CardPlayMode.NORMAL
var _ordered_discard_extra_context: Dictionary = {}
var _ordered_discard_selected_cards: Array[CardData] = []
var _ordered_discard_max_count: int = 0
var _ordered_discard_min_count: int = 0
var _ordered_discard_confirm_button: Button
var _ap_orb_layer: Control
var _druid_prepare_hand_choice_active: bool = false

@onready var map_view: BattleMapView = %MapView
@onready var phase_label: Label = %PhaseLabel
@onready var current_label: Label = %CurrentLabel
@onready var class_resource_list: VBoxContainer = %ClassResourceList
@onready var deploy_list: VBoxContainer = %DeployList
@onready var hand_list: HBoxContainer = %HandList
@onready var start_button: Button = %StartButton
@onready var end_turn_button: Button = %EndTurnButton
@onready var move_button: TextureButton = %MoveButton
@onready var attack_button: TextureButton = %AttackButton
@onready var deck_button: TextureButton = %DeckButton
@onready var discard_button: TextureButton = %DiscardButton
@onready var discard_label: Label = %DiscardLabel
@onready var ap_label: Label = %APLabel
@onready var log_label: RichTextLabel = %LogLabel


func _ready() -> void:
	controller.log_message.connect(_append_log)
	controller.state_changed.connect(_refresh)
	map_view.setup(self, controller)
	start_button.pressed.connect(_on_start_pressed)
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	move_button.pressed.connect(_on_move_pressed)
	attack_button.pressed.connect(_on_attack_pressed)
	deck_button.pressed.connect(_on_deck_pressed)
	discard_button.pressed.connect(_on_discard_pressed)
	_create_ap_orb_layer()
	_create_weapon_choice_popup()
	_create_play_choice_popup()
	_create_discard_popup()
	_create_draw_choice_popup()
	_create_ordered_discard_choice_popup()
	var startup_scenario := scenario
	if startup_scenario == null:
		startup_scenario = DEFAULT_SCENARIO
	controller.setup(startup_scenario)
	selected_deploy_unit = controller.get_first_undeployed_player()
	_refresh()


func handle_map_click(position: Vector2) -> void:
	if _actions_locked():
		return

	if controller.phase == BattleController.Phase.DEPLOYMENT:
		_handle_deployment_click(position)
		return

	if controller.phase != BattleController.Phase.BATTLE:
		return
	if controller.current_unit == null or controller.current_unit.faction != BattleUnitState.Faction.PLAYER:
		return

	var clicked_unit := controller.get_unit_at_position(position)
	match input_mode:
		InputMode.BASIC_ATTACK_TARGET:
			_handle_basic_attack_target(clicked_unit)
		InputMode.CARD_TARGET:
			_handle_card_target(position, clicked_unit)
		InputMode.MOVE:
			if controller.move_current_unit_to(position):
				_clear_input()
		_:
			_append_log("请选择移动、攻击或一张手牌。")
	_refresh()


func get_map_preview_context() -> Dictionary:
	return {
		"input_mode": input_mode,
		"selected_deploy_unit": selected_deploy_unit,
		"pending_card": pending_card,
		"pending_play_mode": pending_play_mode,
		"pending_equipment_slot": pending_equipment_slot,
		"pending_extra_context": pending_extra_context.duplicate(),
		"pending_target_type": _get_pending_card_target_type(),
	}


func _handle_deployment_click(position: Vector2) -> void:
	if selected_deploy_unit == null:
		selected_deploy_unit = controller.get_first_undeployed_player()
	if selected_deploy_unit != null and controller.deploy_player_unit(selected_deploy_unit, position):
		selected_deploy_unit = controller.get_first_undeployed_player()
	_refresh()


func _handle_basic_attack_target(clicked_unit: BattleUnitState) -> void:
	if clicked_unit != null and clicked_unit.faction == BattleUnitState.Faction.ENEMY:
		controller.basic_attack(controller.current_unit, clicked_unit, pending_equipment_slot)
		_clear_input()
	else:
		_append_log("请选择一个敌方目标进行普通攻击。")


func _handle_card_target(position: Vector2, clicked_unit: BattleUnitState) -> void:
	if pending_card == null:
		_clear_input()
		return

	var played := false
	var target_type := _get_pending_card_target_type()
	var play_context := pending_extra_context.duplicate()
	play_context["equipment_slot"] = pending_equipment_slot
	if target_type == CardEnums.TargetType.AREA:
		played = controller.play_card(controller.current_unit, pending_card, [position], play_context, pending_play_mode)
	elif clicked_unit != null and clicked_unit.faction == BattleUnitState.Faction.ENEMY:
		played = controller.play_card(controller.current_unit, pending_card, [clicked_unit], play_context, pending_play_mode)
	else:
		_append_log("请选择一个敌方目标打出卡牌。")

	if played:
		_clear_input()
		_hide_discard_popup()


func _on_start_pressed() -> void:
	if _actions_locked():
		return
	controller.start_battle()
	_refresh()


func _on_move_pressed() -> void:
	if _actions_locked():
		return
	_clear_input()
	input_mode = InputMode.MOVE
	_append_log("请选择移动位置。")
	_refresh()


func _on_attack_pressed() -> void:
	if _actions_locked():
		return
	_clear_input()
	if _needs_weapon_choice(controller.current_unit):
		_show_weapon_choice(InputMode.BASIC_ATTACK_TARGET)
	else:
		input_mode = InputMode.BASIC_ATTACK_TARGET
		_append_log("请选择普通攻击目标。")
	_refresh()


func _on_deck_pressed() -> void:
	if _actions_locked():
		return

	var unit := controller.current_unit
	if unit == null or unit.faction != BattleUnitState.Faction.PLAYER:
		_append_log("当前没有可查看牌库的玩家单位。")
		return

	var preview: PackedStringArray = []
	for card in unit.draw_pile:
		if card != null:
			preview.append(card.card_name)

	var preview_text := "无"
	if not preview.is_empty():
		var visible_preview := PackedStringArray()
		for i in range(mini(preview.size(), 8)):
			visible_preview.append(preview[i])
		preview_text = "、".join(visible_preview)
		if preview.size() > 8:
			preview_text += "……"

	_append_log("牌库 %d / 手牌 %d / 弃牌 %d：%s" % [
		unit.draw_pile.size(),
		unit.hand.size(),
		unit.discard_pile.size(),
		preview_text,
	])


func _on_discard_pressed() -> void:
	if _actions_locked():
		return
	if _discard_popup == null:
		return
	if _discard_popup.visible:
		_hide_discard_popup()
		return

	var visible_size := get_viewport_rect().size
	var popup_size := Vector2i(
		maxi(260, mini(360, int(visible_size.x) - 32)),
		maxi(220, mini(320, int(visible_size.y) - 96))
	)
	var popup_position := Vector2i(
		16,
		maxi(16, int(visible_size.y) - popup_size.y - 80)
	)
	_discard_popup.popup(Rect2i(popup_position, popup_size))
	_refresh_discard_popup()


func _on_end_turn_pressed() -> void:
	if _actions_locked():
		return
	_clear_input()
	controller.end_current_turn()
	_refresh()


func _select_deploy_unit(unit: BattleUnitState) -> void:
	if _actions_locked():
		return
	selected_deploy_unit = unit
	_append_log("选择部署：%s。" % unit.get_display_name())
	_refresh()


func _on_class_resource_pressed(unit: BattleUnitState, resource_name: String) -> void:
	if _actions_locked():
		return
	if resource_name == BattleController.WARRIOR_MOMENTUM_RESOURCE:
		controller.use_warrior_momentum(unit)
	_refresh()


func _on_druid_prepare_transform_pressed(unit: BattleUnitState) -> void:
	if _actions_locked():
		return

	_clear_input()
	if unit == null or unit != controller.current_unit:
		return
	if not controller.can_use_druid_prepare_transform(unit):
		return
	_druid_prepare_hand_choice_active = true
	_append_log("选择一张手牌逆置置入法力区。")
	_refresh()


func _on_druid_prepare_untransform_pressed(unit: BattleUnitState) -> void:
	if _actions_locked():
		return

	_clear_input()
	controller.use_druid_prepare_untransform(unit)
	_refresh()


func _select_discard_card(card: CardData) -> void:
	if _actions_locked():
		return

	_clear_input()
	_hide_discard_popup()
	if card == null:
		return

	var play_mode := CardEnums.CardPlayMode.MOMENTUM
	if _needs_draw_pile_choice(card, play_mode):
		_show_draw_pile_choice(card, play_mode)
		_refresh()
		return
	if _needs_ordered_discard_choice(card, play_mode):
		_show_ordered_discard_choice(card, play_mode)
		_refresh()
		return

	if card.requires_weapon_choice({"controller": controller, "user": controller.current_unit, "card": card, "play_mode": play_mode}) and _needs_weapon_choice(controller.current_unit):
		_show_weapon_choice(InputMode.CARD_TARGET, card, play_mode)
		_refresh()
		return

	if _is_direct_card_target(card, play_mode):
		_play_direct_card(card, play_mode)
		_refresh()
		return

	_begin_card_targeting(card, play_mode)
	_refresh()


func _select_card(card: CardData) -> void:
	if _actions_locked():
		return

	if _druid_prepare_hand_choice_active:
		_select_druid_prepare_card(card)
		return

	_clear_input()
	var play_modes := _available_hand_play_modes(card)
	if play_modes.is_empty():
		_append_log("%s 当前无法打出。" % card.card_name)
		return
	if play_modes.size() > 1:
		_show_play_choice(card, play_modes)
		return

	_select_card_with_mode(card, int(play_modes[0]))


func _select_card_with_mode(card: CardData, play_mode: int) -> void:
	if _actions_locked():
		return

	_clear_input()
	if _needs_draw_pile_choice(card, play_mode):
		_show_draw_pile_choice(card, play_mode)
		_refresh()
		return
	if _needs_ordered_discard_choice(card, play_mode):
		_show_ordered_discard_choice(card, play_mode)
		_refresh()
		return

	if card.requires_weapon_choice({"controller": controller, "user": controller.current_unit, "card": card, "play_mode": play_mode}) and _needs_weapon_choice(controller.current_unit):
		_show_weapon_choice(InputMode.CARD_TARGET, card, play_mode)
		_refresh()
		return

	if _is_direct_card_target(card, play_mode):
		_play_direct_card(card, play_mode)
		_refresh()
		return

	_begin_card_targeting(card, play_mode)
	_refresh()


func _begin_card_targeting(card: CardData, play_mode: int = CardEnums.CardPlayMode.NORMAL) -> void:
	pending_card = card
	pending_play_mode = play_mode
	input_mode = InputMode.CARD_TARGET
	var target_type := _get_card_target_type(card, play_mode)
	_append_log("选择%s：%s，请点击%s。" % [CardEnums.play_mode_label(play_mode), card.card_name, "位置" if target_type == CardEnums.TargetType.AREA else "目标"])


func _clear_input() -> void:
	input_mode = InputMode.NONE
	pending_card = null
	pending_play_mode = CardEnums.CardPlayMode.NORMAL
	pending_equipment_slot = ""
	pending_extra_context.clear()
	_druid_prepare_hand_choice_active = false


func _select_druid_prepare_card(card: CardData) -> void:
	var unit := controller.current_unit
	if unit == null or card == null:
		_clear_input()
		_refresh()
		return
	if not controller.use_druid_prepare_transform(unit, card):
		_append_log("%s 无法作为准备动作置入法力区。" % card.card_name)
		return

	_clear_input()
	_refresh()


func _actions_locked() -> bool:
	return controller != null and controller.is_resolving_actions()


func _hide_action_popups() -> void:
	if _weapon_choice_popup != null:
		_weapon_choice_popup.hide()
	if _play_choice_popup != null:
		_play_choice_popup.hide()
	if _draw_choice_popup != null:
		_draw_choice_popup.hide()
	if _ordered_discard_popup != null:
		_ordered_discard_popup.hide()


func _create_ap_orb_layer() -> void:
	var ap_slot := ap_label.get_parent() as Control
	if ap_slot == null:
		return

	ap_label.visible = false
	_ap_orb_layer = Control.new()
	_ap_orb_layer.name = "APOrbLayer"
	_ap_orb_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ap_slot.add_child(_ap_orb_layer)
	_ap_orb_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _refresh_ap_orbs(current_ap: int, max_ap: int) -> void:
	if _ap_orb_layer == null:
		return

	_clear_children(_ap_orb_layer)
	var slot_count := mini(maxi(max_ap, 0), AP_ORB_SLOT_X.size())
	if slot_count <= 0:
		return

	var layer_size := _ap_orb_layer.size
	if layer_size.x <= 0.0 or layer_size.y <= 0.0:
		var ap_slot := _ap_orb_layer.get_parent() as Control
		if ap_slot != null:
			layer_size = ap_slot.size
	if layer_size.x <= 0.0 or layer_size.y <= 0.0:
		return

	var filled_count := mini(maxi(current_ap, 0), slot_count)
	var orb_size := minf(layer_size.y * AP_ORB_SIZE_RATIO, layer_size.x * 0.18)
	for index in range(filled_count):
		var orb := TextureRect.new()
		orb.texture = AP_ORB_FULL_TEXTURE
		orb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		orb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		orb.custom_minimum_size = Vector2(orb_size, orb_size)
		orb.size = Vector2(orb_size, orb_size)
		orb.tooltip_text = "AP %d/%d" % [current_ap, max_ap]
		var center := Vector2(layer_size.x * float(AP_ORB_SLOT_X[index]), layer_size.y * AP_ORB_SLOT_Y)
		orb.position = center - Vector2(orb_size, orb_size) * 0.5
		_ap_orb_layer.add_child(orb)


func _refresh() -> void:
	if not is_inside_tree():
		return

	if _actions_locked():
		_hide_action_popups()

	phase_label.text = _phase_text()
	if controller.scene_prototype != null:
		phase_label.text += " | " + controller.scene_prototype.get_display_title()

	if controller.current_unit == null:
		current_label.text = "当前单位：无"
		ap_label.text = "AP -"
		_refresh_ap_orbs(0, controller.config.base_ap)
	else:
		current_label.text = "当前单位：%s | 生命 %d/%d | 敏捷 %d%s" % [
			controller.current_unit.get_display_name(),
			controller.current_unit.get_current_health(),
			controller.current_unit.get_max_health(),
			controller.current_unit.get_agility(),
			_current_unit_weapon_summary(controller.current_unit),
		]
		ap_label.text = "AP %d / %d" % [
			controller.current_unit.current_ap,
			controller.current_unit.get_max_ap(controller.config),
		]
		_refresh_ap_orbs(controller.current_unit.current_ap, controller.current_unit.get_max_ap(controller.config))

	var actions_locked := _actions_locked()
	start_button.disabled = actions_locked or controller.phase != BattleController.Phase.DEPLOYMENT or not controller.can_start_battle()
	var is_player_turn := not actions_locked and controller.phase == BattleController.Phase.BATTLE and controller.current_unit != null and controller.current_unit.faction == BattleUnitState.Faction.PLAYER
	move_button.disabled = not is_player_turn
	attack_button.disabled = not is_player_turn
	deck_button.disabled = not is_player_turn
	discard_button.disabled = not is_player_turn
	end_turn_button.disabled = not is_player_turn
	_refresh_deploy_list()
	_refresh_class_resource_list()
	_refresh_hand_list(is_player_turn)
	_refresh_discard_button()
	_refresh_discard_popup()
	map_view.queue_redraw()


func _refresh_deploy_list() -> void:
	_clear_children(deploy_list)
	for unit in controller.player_units:
		var button := Button.new()
		button.text = "%s %s" % [unit.get_display_name(), "(已部署)" if unit.is_deployed else "(待部署)"]
		button.disabled = _actions_locked() or controller.phase != BattleController.Phase.DEPLOYMENT
		button.pressed.connect(_select_deploy_unit.bind(unit))
		deploy_list.add_child(button)


func _refresh_class_resource_list() -> void:
	_clear_children(class_resource_list)

	var has_resources := false
	for unit in controller.player_units:
		if unit == null or unit.character_state == null:
			continue

		if unit.is_druid():
			has_resources = true
			var druid_label := Label.new()
			druid_label.text = "%s：法力 %d | 附魔 %d | 诅咒 %d | %s" % [
				unit.get_display_name(),
				unit.get_available_mana(),
				unit.enchant_zone.size(),
				unit.curse_zone.size(),
				"变身" if unit.druid_transformed else "正位",
			]
			class_resource_list.add_child(druid_label)

			if controller.can_use_druid_prepare_transform(unit) or controller.can_use_druid_prepare_untransform(unit):
				var druid_button := Button.new()
				if controller.can_use_druid_prepare_transform(unit):
					druid_button.text = "准备：逆置首张手牌并变身"
					druid_button.tooltip_text = "每回合限一次。将最左侧手牌逆置置入法力区，然后进入变身状态。"
					druid_button.pressed.connect(_on_druid_prepare_transform_pressed.bind(unit))
				else:
					druid_button.text = "准备：支付1法力解除变身"
					druid_button.tooltip_text = "每回合限一次。支付 1 点法力，解除变身状态。"
					druid_button.pressed.connect(_on_druid_prepare_untransform_pressed.bind(unit))
				druid_button.disabled = _actions_locked()
				class_resource_list.add_child(druid_button)

		for pool_state in unit.character_state.class_resources:
			if pool_state == null:
				continue

			has_resources = true
			var button := Button.new()
			button.text = "%s：%s" % [unit.get_display_name(), pool_state.get_display_text()]
			button.disabled = true

			if pool_state.get_resource_name() == BattleController.WARRIOR_MOMENTUM_RESOURCE:
				button.tooltip_text = "消耗 1 点势，获得本次一次性的 +2 伤害加值。每回合限一次。"
				button.disabled = _actions_locked() or not controller.can_use_warrior_momentum(unit)
				if not button.disabled:
					button.text += "  使用"
				button.pressed.connect(_on_class_resource_pressed.bind(unit, pool_state.get_resource_name()))

			class_resource_list.add_child(button)

	if not has_resources:
		var label := Label.new()
		label.text = "无职业资源"
		class_resource_list.add_child(label)


func _refresh_hand_list(is_player_turn: bool) -> void:
	_clear_children(hand_list)
	if not is_player_turn:
		var label := Label.new()
		label.text = "等待玩家单位行动"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.custom_minimum_size = Vector2(220, 120)
		hand_list.add_child(label)
		return

	for card in controller.current_unit.hand:
		var context := {
			"controller": controller,
			"user": controller.current_unit,
			"card": card,
		}
		var display_ap_cost := controller.get_card_ap_cost(controller.current_unit, card, context)
		var button := TextureButton.new()
		button.texture_normal = HAND_CARD_SLOT_TEXTURE
		button.ignore_texture_size = true
		button.stretch_mode = 0
		button.custom_minimum_size = Vector2(112, 138)
		button.tooltip_text = _build_card_tooltip(card)
		button.disabled = _actions_locked()
		button.pressed.connect(_select_card.bind(card))

		var label := Label.new()
		if _druid_prepare_hand_choice_active:
			label.text = "%s\n置入法力区" % card.get_display_name_for_context(context)
		else:
			label.text = "%s\n%dAP\n射程 %.0f" % [
				card.get_display_name_for_context(context),
				display_ap_cost,
				card.get_effective_range(controller.current_unit, pending_equipment_slot),
			]
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color(0.09, 0.055, 0.025))
		button.add_child(label)
		hand_list.add_child(button)

	if controller.current_unit.hand.is_empty():
		var label := Label.new()
		label.text = "手牌为空"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.custom_minimum_size = Vector2(220, 120)
		hand_list.add_child(label)


func _refresh_discard_button() -> void:
	var unit := controller.current_unit
	var discard_count := 0
	var exile_count := 0
	var enchant_count := 0
	if unit != null:
		discard_count = unit.discard_pile.size()
		exile_count = unit.exiled_pile.size()
		enchant_count = unit.enchant_zone.size()
	discard_label.text = "弃牌 %d\n放逐 %d · 附魔 %d" % [discard_count, exile_count, enchant_count]


func _refresh_discard_popup() -> void:
	if _discard_popup == null or _discard_list == null or not _discard_popup.visible:
		return

	_clear_children(_discard_list)
	var unit := controller.current_unit
	if unit == null:
		return

	var discard_title := Label.new()
	discard_title.text = "弃牌堆"
	_discard_list.add_child(discard_title)

	if unit.discard_pile.is_empty():
		var label := Label.new()
		label.text = "为空"
		_discard_list.add_child(label)
	else:
		for card in unit.discard_pile:
			if card == null:
				continue
			var button := Button.new()
			button.text = _discard_card_button_text(card)
			button.tooltip_text = _build_card_tooltip(card)
			button.disabled = _actions_locked() or not controller.can_play_card_with_mode(unit, card, CardEnums.CardPlayMode.MOMENTUM)
			if not button.disabled:
				button.pressed.connect(_select_discard_card.bind(card))
			_discard_list.add_child(button)

	var separator := HSeparator.new()
	_discard_list.add_child(separator)

	var exile_title := Label.new()
	exile_title.text = "放逐区"
	_discard_list.add_child(exile_title)

	if unit.exiled_pile.is_empty():
		var exile_empty := Label.new()
		exile_empty.text = "为空"
		_discard_list.add_child(exile_empty)
	else:
		for exiled_card in unit.exiled_pile:
			if exiled_card == null:
				continue
			var exile_button := Button.new()
			exile_button.text = _exiled_card_button_text(unit, exiled_card)
			exile_button.tooltip_text = _build_card_tooltip(exiled_card)
			exile_button.disabled = _actions_locked() or not controller.can_activate_exiled_card(unit, exiled_card)
			if not exile_button.disabled:
				exile_button.pressed.connect(_activate_exiled_card.bind(exiled_card))
			_discard_list.add_child(exile_button)

	_discard_list.add_child(HSeparator.new())
	var enchant_title := Label.new()
	enchant_title.text = "附魔区"
	_discard_list.add_child(enchant_title)
	if unit.enchant_zone.is_empty():
		var enchant_empty := Label.new()
		enchant_empty.text = "为空"
		_discard_list.add_child(enchant_empty)
	else:
		for enchant_card in unit.enchant_zone:
			if enchant_card == null:
				continue
			var enchant_button := Button.new()
			enchant_button.text = _enchant_card_button_text(unit, enchant_card)
			enchant_button.tooltip_text = _build_card_tooltip(enchant_card)
			enchant_button.disabled = _actions_locked() or not controller.can_activate_enchant_card(unit, enchant_card)
			if not enchant_button.disabled:
				enchant_button.pressed.connect(_activate_enchant_card.bind(enchant_card))
			_discard_list.add_child(enchant_button)


func _discard_card_button_text(card: CardData) -> String:
	var text := "%s | %s" % [card.card_name, card.get_card_type_label()]
	if card.has_momentum:
		text += "\n余势：%s" % card.get_special_condition_text(CardEnums.CardPlayMode.MOMENTUM)
	return text


func _exiled_card_button_text(unit: BattleUnitState, card: CardData) -> String:
	var text := "%s | 放逐" % card.card_name
	var context := {
		"controller": controller,
		"user": unit,
		"card": card,
	}
	var action_label := card.get_exile_action_label(context)
	if not action_label.is_empty():
		text += "\n%s" % action_label
	return text


func _activate_exiled_card(card: CardData) -> void:
	if _actions_locked():
		return
	if controller.current_unit == null or card == null:
		return

	if controller.activate_exiled_card(controller.current_unit, card):
		_clear_input()
		_hide_discard_popup()
	_refresh()


func _enchant_card_button_text(unit: BattleUnitState, card: CardData) -> String:
	var text := "%s | 附魔" % card.card_name
	var context := {
		"controller": controller,
		"user": unit,
		"card": card,
		"zone_name": "enchant",
	}
	var action_label := card.get_enchant_action_label(context)
	if not action_label.is_empty():
		text += "\n%s" % action_label
	return text


func _activate_enchant_card(card: CardData) -> void:
	if _actions_locked():
		return
	if controller.current_unit == null or card == null:
		return
	if controller.activate_enchant_card(controller.current_unit, card):
		_clear_input()
		_hide_discard_popup()
	_refresh()


func _available_hand_play_modes(card: CardData) -> Array[int]:
	var result: Array[int] = []
	var unit := controller.current_unit
	if unit == null or card == null:
		return result

	if controller.can_play_card_with_mode(unit, card, CardEnums.CardPlayMode.NORMAL):
		result.append(CardEnums.CardPlayMode.NORMAL)
	if controller.can_play_card_with_mode(unit, card, CardEnums.CardPlayMode.COMBO):
		result.append(CardEnums.CardPlayMode.COMBO)

	return result


func _get_card_target_type(card: CardData, play_mode: int) -> int:
	if card == null:
		return CardEnums.TargetType.NONE

	var context := {
		"controller": controller,
		"user": controller.current_unit,
		"card": card,
		"equipment_slot": pending_equipment_slot,
		"play_mode": play_mode,
	}
	if controller.current_unit != null and controller.current_unit.has_method("get_druid_card_orientation"):
		context["druid_orientation"] = controller.current_unit.get_druid_card_orientation(card)
	return card.get_target_type_for_mode(play_mode, context)


func _get_pending_card_target_type() -> int:
	return _get_card_target_type(pending_card, pending_play_mode)


func _is_direct_card_target(card: CardData, play_mode: int) -> bool:
	var target_type := _get_card_target_type(card, play_mode)
	return target_type == CardEnums.TargetType.NONE or target_type == CardEnums.TargetType.SELF or target_type == CardEnums.TargetType.ALL


func _needs_draw_pile_choice(card: CardData, play_mode: int) -> bool:
	if card == null:
		return false

	return card.requires_draw_pile_choice({
		"controller": controller,
		"user": controller.current_unit,
		"card": card,
		"equipment_slot": pending_equipment_slot,
		"play_mode": play_mode,
	})


func _needs_ordered_discard_choice(card: CardData, play_mode: int, extra_context: Dictionary = {}) -> bool:
	if card == null or extra_context.has("ordered_discard_cards"):
		return false

	var context := extra_context.duplicate()
	context["controller"] = controller
	context["user"] = controller.current_unit
	context["card"] = card
	context["equipment_slot"] = pending_equipment_slot
	context["play_mode"] = play_mode
	return card.requires_ordered_discard_choice(context)


func _play_direct_card(card: CardData, play_mode: int, extra_context: Dictionary = {}) -> bool:
	if controller.current_unit == null or card == null:
		return false

	var targets := []
	if _get_card_target_type(card, play_mode) == CardEnums.TargetType.SELF:
		targets.append(controller.current_unit)

	var play_context := extra_context.duplicate()
	play_context["equipment_slot"] = pending_equipment_slot
	var played := controller.play_card(controller.current_unit, card, targets, play_context, play_mode)
	if played:
		_clear_input()
		_hide_discard_popup()
	return played


func _append_log(message: String) -> void:
	log_label.append_text(message + "\n")


func _phase_text() -> String:
	match controller.phase:
		BattleController.Phase.DEPLOYMENT:
			return "阶段：部署"
		BattleController.Phase.BATTLE:
			return "阶段：战斗"
		BattleController.Phase.ENDED:
			return "阶段：结束"
		_:
			return "阶段：未知"


func _current_unit_weapon_summary(unit: BattleUnitState) -> String:
	if unit == null:
		return ""
	if unit.faction == BattleUnitState.Faction.PLAYER:
		return " | %s" % _strike_preview_text(unit)
	return " | 威力 %d" % unit.get_attack()


func _build_card_tooltip(card: CardData) -> String:
	var parts := PackedStringArray()
	var context := {
		"controller": controller,
		"user": controller.current_unit,
		"card": card,
	}
	if controller.current_unit != null and controller.current_unit.has_method("get_druid_card_orientation"):
		context["druid_orientation"] = controller.current_unit.get_druid_card_orientation(card)
	parts.append(card.get_display_name_for_context(context))
	if controller.current_unit != null:
		parts.append("%dAP" % controller.get_card_ap_cost(controller.current_unit, card, context))
	else:
		parts.append("%dAP" % card.ap_cost)
	if card.is_druid_dual_card:
		parts.append(card.get_druid_orientation_label(context))
	parts.append(card.get_card_type_label())
	parts.append(card.get_play_timing_label())
	if card.has_momentum:
		parts.append("余势：%s" % card.get_special_condition_text(CardEnums.CardPlayMode.MOMENTUM))
	if card.has_combo:
		parts.append("连击：%s" % card.get_special_condition_text(CardEnums.CardPlayMode.COMBO))
	parts.append("射程 %.0f" % card.get_effective_range(controller.current_unit, pending_equipment_slot))
	var description := card.get_description_for_context(context)
	if not description.is_empty():
		parts.append(description)
	if controller.current_unit != null and card.requires_weapon_choice(context):
		parts.append(_strike_preview_text(controller.current_unit))
	return " | ".join(parts)


func _strike_preview_text(unit: BattleUnitState) -> String:
	var profile := unit.build_strike_profile_object(pending_equipment_slot)
	var text := "伤害加值 %d / 武器威力 %d" % [
		profile.damage_bonus,
		profile.primary_power,
	]
	if profile.add_offhand:
		text += " / 额外段威力 %d" % profile.offhand_power
	return text


func _clear_children(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _needs_weapon_choice(unit: BattleUnitState) -> bool:
	return unit != null and unit.faction == BattleUnitState.Faction.PLAYER and unit.needs_weapon_choice()


func _create_weapon_choice_popup() -> void:
	_weapon_choice_popup = PopupPanel.new()
	_weapon_choice_popup.title = "选择武器"
	_weapon_choice_popup.exclusive = true
	add_child(_weapon_choice_popup)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_weapon_choice_popup.add_child(margin)

	_weapon_choice_list = VBoxContainer.new()
	_weapon_choice_list.custom_minimum_size = Vector2(240, 0)
	margin.add_child(_weapon_choice_list)


func _create_play_choice_popup() -> void:
	_play_choice_popup = PopupPanel.new()
	_play_choice_popup.title = "选择打出方式"
	_play_choice_popup.exclusive = true
	add_child(_play_choice_popup)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_play_choice_popup.add_child(margin)

	_play_choice_list = VBoxContainer.new()
	_play_choice_list.custom_minimum_size = Vector2(260, 0)
	margin.add_child(_play_choice_list)


func _create_discard_popup() -> void:
	_discard_popup = PopupPanel.new()
	_discard_popup.title = "弃牌堆"
	_discard_popup.exclusive = false
	add_child(_discard_popup)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_discard_popup.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(280, 220)
	margin.add_child(scroll)

	_discard_list = VBoxContainer.new()
	_discard_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_discard_list)


func _create_draw_choice_popup() -> void:
	_draw_choice_popup = PopupPanel.new()
	_draw_choice_popup.title = "选择牌库牌"
	_draw_choice_popup.exclusive = true
	add_child(_draw_choice_popup)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_draw_choice_popup.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 260)
	margin.add_child(scroll)

	_draw_choice_list = VBoxContainer.new()
	_draw_choice_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_draw_choice_list)


func _create_ordered_discard_choice_popup() -> void:
	_ordered_discard_popup = PopupPanel.new()
	_ordered_discard_popup.title = "选择弃牌堆牌"
	_ordered_discard_popup.exclusive = true
	add_child(_ordered_discard_popup)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_ordered_discard_popup.add_child(margin)

	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(340, 300)
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	_ordered_discard_selected_label = Label.new()
	_ordered_discard_selected_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_ordered_discard_selected_label)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(320, 220)
	root.add_child(scroll)

	_ordered_discard_list = VBoxContainer.new()
	_ordered_discard_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_ordered_discard_list)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	root.add_child(controls)

	var clear_button := Button.new()
	clear_button.text = "清空"
	clear_button.pressed.connect(_clear_ordered_discard_selection)
	controls.add_child(clear_button)

	_ordered_discard_confirm_button = Button.new()
	_ordered_discard_confirm_button.text = "确认"
	_ordered_discard_confirm_button.pressed.connect(_confirm_ordered_discard_choice)
	controls.add_child(_ordered_discard_confirm_button)


func _show_draw_pile_choice(card: CardData, play_mode: int) -> void:
	var unit := controller.current_unit
	if unit == null or card == null:
		return
	if unit.draw_pile.is_empty():
		_append_log("牌库为空，无法打出 %s。" % card.card_name)
		return

	_draw_choice_card = card
	_draw_choice_play_mode = play_mode
	_clear_children(_draw_choice_list)

	var title := Label.new()
	title.text = "%s：选择一张牌库牌置入弃牌堆" % card.card_name
	_draw_choice_list.add_child(title)

	for draw_card in unit.draw_pile:
		if draw_card == null:
			continue
		var button := Button.new()
		button.text = "%s | %s" % [draw_card.card_name, draw_card.get_card_type_label()]
		button.tooltip_text = _build_card_tooltip(draw_card)
		button.pressed.connect(_on_draw_pile_choice_pressed.bind(draw_card))
		_draw_choice_list.add_child(button)

	_draw_choice_popup.popup_centered()


func _show_ordered_discard_choice(card: CardData, play_mode: int, extra_context: Dictionary = {}) -> void:
	var unit := controller.current_unit
	if unit == null or card == null:
		return

	var context := extra_context.duplicate()
	context["controller"] = controller
	context["user"] = unit
	context["card"] = card
	context["equipment_slot"] = pending_equipment_slot
	context["play_mode"] = play_mode
	var choices := card.get_ordered_discard_choice_cards(context)
	_ordered_discard_card = card
	_ordered_discard_play_mode = play_mode
	_ordered_discard_extra_context = extra_context.duplicate()
	_ordered_discard_selected_cards.clear()
	_ordered_discard_max_count = card.get_ordered_discard_choice_max_count(context)
	_ordered_discard_min_count = card.get_ordered_discard_choice_min_count(context)
	_clear_children(_ordered_discard_list)

	var title := Label.new()
	title.text = card.get_ordered_discard_choice_prompt(context)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ordered_discard_list.add_child(title)

	if choices.is_empty():
		var empty_label := Label.new()
		empty_label.text = "无可选择牌。" if _ordered_discard_min_count > 0 else "无可选择牌，可以直接确认。"
		_ordered_discard_list.add_child(empty_label)
	else:
		for choice in choices:
			if choice == null:
				continue
			var button := Button.new()
			button.text = "%s | %s" % [choice.card_name, choice.get_card_type_label()]
			button.tooltip_text = _build_card_tooltip(choice)
			button.pressed.connect(_add_ordered_discard_choice.bind(choice))
			_ordered_discard_list.add_child(button)

	_refresh_ordered_discard_selected_label()
	_ordered_discard_popup.popup_centered()


func _add_ordered_discard_choice(card: CardData) -> void:
	if _actions_locked() or card == null:
		return
	if _ordered_discard_selected_cards.size() >= _ordered_discard_max_count:
		return
	if _ordered_discard_selected_cards.has(card):
		return

	_ordered_discard_selected_cards.append(card)
	_refresh_ordered_discard_selected_label()


func _clear_ordered_discard_selection() -> void:
	if _actions_locked():
		return

	_ordered_discard_selected_cards.clear()
	_refresh_ordered_discard_selected_label()


func _refresh_ordered_discard_selected_label() -> void:
	if _ordered_discard_selected_label == null:
		return

	var names := PackedStringArray()
	for card in _ordered_discard_selected_cards:
		if card != null:
			names.append(card.card_name)

	var selected_text := "无"
	if not names.is_empty():
		selected_text = " -> ".join(names)
	_ordered_discard_selected_label.text = "已选 %d/%d：%s" % [
		_ordered_discard_selected_cards.size(),
		_ordered_discard_max_count,
		selected_text,
	]
	if _ordered_discard_confirm_button != null:
		_ordered_discard_confirm_button.disabled = _ordered_discard_selected_cards.size() < _ordered_discard_min_count


func _confirm_ordered_discard_choice() -> void:
	if _actions_locked():
		return
	if _ordered_discard_selected_cards.size() < _ordered_discard_min_count:
		return

	var card := _ordered_discard_card
	var play_mode := _ordered_discard_play_mode
	var extra_context := _ordered_discard_extra_context.duplicate()
	extra_context["ordered_discard_cards"] = _ordered_discard_selected_cards.duplicate()
	_ordered_discard_card = null
	_ordered_discard_play_mode = CardEnums.CardPlayMode.NORMAL
	_ordered_discard_extra_context.clear()
	_ordered_discard_selected_cards.clear()
	_ordered_discard_min_count = 0
	_ordered_discard_popup.hide()
	_continue_card_with_extra_context(card, play_mode, extra_context)


func _on_draw_pile_choice_pressed(draw_card: CardData) -> void:
	if _actions_locked():
		return

	var card := _draw_choice_card
	var play_mode := _draw_choice_play_mode
	_draw_choice_card = null
	_draw_choice_play_mode = CardEnums.CardPlayMode.NORMAL
	_draw_choice_popup.hide()
	if card == null or draw_card == null:
		return

	_continue_card_with_extra_context(card, play_mode, {"selected_draw_card": draw_card})


func _continue_card_with_extra_context(card: CardData, play_mode: int, extra_context: Dictionary = {}) -> void:
	if card == null:
		return

	if _needs_ordered_discard_choice(card, play_mode, extra_context):
		_show_ordered_discard_choice(card, play_mode, extra_context)
		_refresh()
		return

	if card.requires_weapon_choice({"controller": controller, "user": controller.current_unit, "card": card, "play_mode": play_mode}) and _needs_weapon_choice(controller.current_unit):
		_show_weapon_choice(InputMode.CARD_TARGET, card, play_mode, extra_context)
		_refresh()
		return

	if _is_direct_card_target(card, play_mode):
		_play_direct_card(card, play_mode, extra_context)
		_refresh()
		return

	pending_extra_context = extra_context.duplicate()
	_begin_card_targeting(card, play_mode)
	_refresh()


func _show_play_choice(card: CardData, play_modes: Array[int]) -> void:
	_play_choice_card = card
	_clear_children(_play_choice_list)

	var title := Label.new()
	title.text = card.card_name
	_play_choice_list.add_child(title)

	for play_mode in play_modes:
		var button := Button.new()
		button.text = _play_choice_button_text(card, play_mode)
		button.pressed.connect(_on_play_choice_pressed.bind(play_mode))
		_play_choice_list.add_child(button)

	_play_choice_popup.popup_centered()


func _play_choice_button_text(card: CardData, play_mode: int) -> String:
	match play_mode:
		CardEnums.CardPlayMode.NORMAL:
			return "普通打出：%d AP" % controller.get_card_ap_cost(controller.current_unit, card)
		CardEnums.CardPlayMode.COMBO:
			return "连击打出：0 AP；%s" % card.get_special_condition_text(play_mode)
		_:
			return CardEnums.play_mode_label(play_mode)


func _on_play_choice_pressed(play_mode: int) -> void:
	if _actions_locked():
		return

	var card := _play_choice_card
	_play_choice_card = null
	_play_choice_popup.hide()
	if card != null:
		_select_card_with_mode(card, play_mode)


func _hide_discard_popup() -> void:
	if _discard_popup != null:
		_discard_popup.hide()


func _show_weapon_choice(next_mode: int, card: CardData = null, play_mode: int = CardEnums.CardPlayMode.NORMAL, extra_context: Dictionary = {}) -> void:
	if controller.current_unit == null:
		return

	_weapon_choice_next_mode = next_mode
	_weapon_choice_card = card
	_weapon_choice_play_mode = play_mode
	_weapon_choice_extra_context = extra_context.duplicate()
	_clear_children(_weapon_choice_list)

	var title := Label.new()
	title.text = "选择本次打击使用的武器"
	_weapon_choice_list.add_child(title)

	for option in controller.current_unit.get_attack_weapon_options():
		var button := Button.new()
		button.text = str(option.get("label", "武器"))
		button.pressed.connect(_on_weapon_choice_pressed.bind(str(option.get("slot", ""))))
		_weapon_choice_list.add_child(button)

	_weapon_choice_popup.popup_centered()


func _on_weapon_choice_pressed(slot: String) -> void:
	if _actions_locked():
		return

	pending_equipment_slot = slot
	_weapon_choice_popup.hide()
	input_mode = _weapon_choice_next_mode
	if input_mode == InputMode.BASIC_ATTACK_TARGET:
		_append_log("请选择普通攻击目标。")
	elif input_mode == InputMode.CARD_TARGET and _weapon_choice_card != null:
		if _is_direct_card_target(_weapon_choice_card, _weapon_choice_play_mode):
			_play_direct_card(_weapon_choice_card, _weapon_choice_play_mode, _weapon_choice_extra_context)
		else:
			pending_extra_context = _weapon_choice_extra_context.duplicate()
			_begin_card_targeting(_weapon_choice_card, _weapon_choice_play_mode)

	_weapon_choice_next_mode = InputMode.NONE
	_weapon_choice_card = null
	_weapon_choice_play_mode = CardEnums.CardPlayMode.NORMAL
	_weapon_choice_extra_context.clear()
	_refresh()
