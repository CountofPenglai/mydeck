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
	CARD_LANDING,
	CURSE_TARGET,
	CURSE_CELL,
}

@export var scenario: BattleScenario

var controller := BattleController.new()
var selected_deploy_unit: BattleUnitState
var input_mode: int = InputMode.NONE
var pending_card: CardData
var pending_play_mode: int = CardEnums.CardPlayMode.NORMAL
var pending_equipment_slot: String = ""
var pending_extra_context: Dictionary = {}
var pending_unit_target: BattleUnitState
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
var _ordered_discard_is_ranger_debt: bool = false
var _ordered_discard_is_discard_activation: bool = false
var _ordered_discard_is_pending_ranger: bool = false
var _ranger_blend_popup: PopupPanel
var _ranger_blend_list: VBoxContainer
var _ranger_recipe_card: CardData
var _ranger_recipe_play_mode: int = CardEnums.CardPlayMode.NORMAL
var _ranger_enemy_hand_target: BattleUnitState
var _ap_orb_layer: Control
var _druid_prepare_hand_choice_active: bool = false
var _curse_popup: PopupPanel
var _curse_list: VBoxContainer
var _curse_choice_popup: PopupPanel
var _curse_choice_list: VBoxContainer
var _curse_choice_card: CardData
var _curse_choice_play_mode: int = CardEnums.CardPlayMode.NORMAL
var _curse_choice_extra_context: Dictionary = {}
var _manifest_popup: PopupPanel
var _manifest_list: VBoxContainer
var _manifest_selected: Array[CardData] = []
var _pending_curse: CurseInstance
var _pending_curse_action_id: String = ""
var _adventure_result: BattleResult
var _return_to_map_button: Button
var _refresh_scheduled := false
var inspected_enemy: BattleUnitState

@onready var map_view: BattleMapView = %MapView
@onready var phase_label: Label = %PhaseLabel
@onready var current_label: Label = %CurrentLabel
@onready var class_resource_list: VBoxContainer = %ClassResourceList
@onready var equipment_list: VBoxContainer = %EquipmentList
@onready var deploy_list: VBoxContainer = %DeployList
@onready var hand_list: HBoxContainer = %HandList
@onready var start_button: Button = %StartButton
@onready var end_turn_button: Button = %EndTurnButton
@onready var move_button: TextureButton = %MoveButton
@onready var attack_button: TextureButton = %AttackButton
@onready var deck_button: TextureButton = %DeckButton
@onready var discard_button: TextureButton = %DiscardButton
@onready var discard_label: Label = %DiscardLabel
@onready var curse_button: Button = %CurseButton
@onready var menu_button: Button = %MenuButton
@onready var ap_label: Label = %APLabel
@onready var log_label: RichTextLabel = %LogLabel
@onready var enemy_inspect_panel: EnemyInspectPanel = %EnemyInspectPanel
@onready var battle_menu: Control = %BattleMenu
@onready var resume_battle_button: Button = %ResumeBattleButton
@onready var restart_battle_button: Button = %RestartBattleButton
@onready var restart_confirmation: ConfirmationDialog = %RestartConfirmation


func _ready() -> void:
	controller.log_message.connect(_append_log)
	controller.state_changed.connect(_schedule_refresh)
	controller.battle_finished.connect(_on_battle_finished)
	map_view.setup(self, controller)
	start_button.pressed.connect(_on_start_pressed)
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	move_button.pressed.connect(_on_move_pressed)
	attack_button.pressed.connect(_on_attack_pressed)
	deck_button.pressed.connect(_on_deck_pressed)
	discard_button.pressed.connect(_on_discard_pressed)
	curse_button.pressed.connect(_show_curse_popup)
	menu_button.pressed.connect(_open_battle_menu)
	resume_battle_button.pressed.connect(_close_battle_menu)
	restart_battle_button.pressed.connect(_request_battle_restart)
	restart_confirmation.confirmed.connect(_restart_current_battle)
	enemy_inspect_panel.close_requested.connect(_clear_enemy_inspection)
	_create_ap_orb_layer()
	_create_weapon_choice_popup()
	_create_play_choice_popup()
	_create_discard_popup()
	_create_draw_choice_popup()
	_create_ordered_discard_choice_popup()
	_create_ranger_blend_popup()
	_create_curse_popup()
	_create_curse_choice_popup()
	_create_manifest_popup()
	_create_return_to_map_button()
	var startup_scenario := scenario
	var adventure_session := get_node_or_null("/root/AdventureSession")
	if adventure_session != null and adventure_session.has_method("consume_pending_battle_scenario"):
		var pending_scenario = adventure_session.call("consume_pending_battle_scenario")
		if pending_scenario is BattleScenario:
			startup_scenario = pending_scenario as BattleScenario
	if startup_scenario == null:
		startup_scenario = DEFAULT_SCENARIO
	if startup_scenario == DEFAULT_SCENARIO:
		startup_scenario = DEFAULT_SCENARIO.duplicate(true) as BattleScenario
		startup_scenario.enemies.clear()
		startup_scenario.enemies.append(ChapterOneEnemyCatalog.create_enemy(&"hungry_fish", 1001))
		startup_scenario.enemies.append(ChapterOneEnemyCatalog.create_enemy(&"harpoon_fish", 1002))
	controller.setup(startup_scenario)
	selected_deploy_unit = controller.get_first_undeployed_player()
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if restart_confirmation.visible:
		restart_confirmation.hide()
	else:
		_set_battle_menu_visible(not battle_menu.visible)
	get_viewport().set_input_as_handled()


func _open_battle_menu() -> void:
	_set_battle_menu_visible(true)


func _close_battle_menu() -> void:
	_set_battle_menu_visible(false)


func _set_battle_menu_visible(value: bool) -> void:
	battle_menu.visible = value
	if value:
		resume_battle_button.grab_focus()
	else:
		menu_button.grab_focus()


func _request_battle_restart() -> void:
	restart_confirmation.popup_centered(Vector2i(420, 180))


func _restart_current_battle() -> void:
	restart_battle_button.disabled = true
	resume_battle_button.disabled = true
	var adventure_session := get_node_or_null("/root/AdventureSession")
	if adventure_session != null and adventure_session.has_method("restart_pending_battle"):
		var restarted := bool(adventure_session.call("restart_pending_battle"))
		if restarted:
			return
	get_tree().reload_current_scene()


func _schedule_refresh() -> void:
	if _refresh_scheduled:
		return
	_refresh_scheduled = true
	call_deferred("_run_scheduled_refresh")


func _run_scheduled_refresh() -> void:
	if not _refresh_scheduled:
		return
	_refresh_scheduled = false
	_refresh()


func _create_return_to_map_button() -> void:
	_return_to_map_button = Button.new()
	_return_to_map_button.text = "选择战斗奖励"
	_return_to_map_button.tooltip_text = "结算战斗并进入卡牌奖励选择"
	_return_to_map_button.visible = false
	_return_to_map_button.set_anchors_preset(Control.PRESET_CENTER)
	_return_to_map_button.offset_left = -120.0
	_return_to_map_button.offset_top = -26.0
	_return_to_map_button.offset_right = 120.0
	_return_to_map_button.offset_bottom = 26.0
	_return_to_map_button.pressed.connect(_on_return_to_map_pressed)
	add_child(_return_to_map_button)


func _on_battle_finished(result: BattleResult) -> void:
	_adventure_result = result
	var adventure_session := get_node_or_null("/root/AdventureSession")
	var has_pending_battle := adventure_session != null and adventure_session.has_method("has_pending_battle") \
		and bool(adventure_session.call("has_pending_battle"))
	_return_to_map_button.visible = has_pending_battle
	var grants_reward := result.victory and adventure_session != null \
		and adventure_session.has_method("pending_battle_grants_reward") \
		and bool(adventure_session.call("pending_battle_grants_reward"))
	_return_to_map_button.text = "选择战斗奖励" if grants_reward else "返回大地图"
	_return_to_map_button.tooltip_text = "结算战斗并进入卡牌奖励选择" if grants_reward else "提交战斗结果并返回冒险地图"


func _on_return_to_map_pressed() -> void:
	if _adventure_result == null:
		return
	var adventure_session := get_node_or_null("/root/AdventureSession")
	if adventure_session == null or not adventure_session.has_method("complete_pending_battle"):
		return
	_return_to_map_button.disabled = true
	adventure_session.call("complete_pending_battle", _adventure_result)


func handle_map_click(position: Vector2) -> void:
	if _actions_locked():
		return
	var cell := controller.map_data.map_to_cell(position)

	if controller.phase == BattleController.Phase.DEPLOYMENT:
		_handle_deployment_click(cell)
		return

	if controller.phase != BattleController.Phase.BATTLE:
		return
	var clicked_unit := controller.get_unit_at_cell(cell)
	var clicked_object := controller.get_battle_object_at_cell(cell)
	if input_mode == InputMode.NONE and clicked_unit != null and clicked_unit.faction == BattleUnitState.Faction.ENEMY:
		_inspect_enemy(clicked_unit)
		_refresh()
		return
	if controller.current_unit == null or controller.current_unit.faction != BattleUnitState.Faction.PLAYER:
		return
	match input_mode:
		InputMode.BASIC_ATTACK_TARGET:
			_handle_basic_attack_target(clicked_unit, clicked_object)
		InputMode.CARD_TARGET:
			_handle_card_target(cell, clicked_unit, clicked_object)
		InputMode.CARD_LANDING:
			_handle_card_landing(cell)
		InputMode.MOVE:
			if controller.move_current_unit_to_cell(cell):
				_clear_input()
		InputMode.CURSE_TARGET:
			_resolve_pending_curse_action({"target": clicked_unit})
		InputMode.CURSE_CELL:
			_resolve_pending_curse_action({"target_cell": cell})
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
		"pending_unit_target": pending_unit_target,
		"pending_target_type": _get_pending_card_target_type(),
	}


func _handle_deployment_click(cell: Vector2i) -> void:
	if selected_deploy_unit == null:
		selected_deploy_unit = controller.get_first_undeployed_player()
	if selected_deploy_unit != null and controller.deploy_player_unit_at_cell(selected_deploy_unit, cell):
		selected_deploy_unit = controller.get_first_undeployed_player()
	_refresh()


func _handle_basic_attack_target(
	clicked_unit: BattleUnitState,
	clicked_object: BattleObjectState = null
) -> void:
	if clicked_unit != null and clicked_unit.faction == BattleUnitState.Faction.ENEMY:
		controller.basic_attack(controller.current_unit, clicked_unit, pending_equipment_slot)
		_clear_input()
	elif clicked_object != null and clicked_object.is_targetable():
		controller.basic_attack_object(controller.current_unit, clicked_object, pending_equipment_slot)
		_clear_input()
	else:
		_append_log("请选择一个敌方目标或可破坏对象进行普通攻击。")


func _handle_card_target(
	cell: Vector2i,
	clicked_unit: BattleUnitState,
	clicked_object: BattleObjectState = null
) -> void:
	if pending_card == null:
		_clear_input()
		return

	var played := false
	var target_type := _get_pending_card_target_type()
	var play_context := pending_extra_context.duplicate()
	play_context["equipment_slot"] = pending_equipment_slot
	if target_type == CardEnums.TargetType.AREA:
		played = controller.play_card(controller.current_unit, pending_card, [cell], play_context, pending_play_mode)
	elif clicked_unit != null:
		if pending_card.effect is RangerCrossHuntStepCardEffect and not play_context.has("landing_cell"):
			pending_unit_target = clicked_unit
			input_mode = InputMode.CARD_LANDING
			_append_log("选择交错猎步的落点。")
			_refresh()
			return
		if pending_card.effect is RangerStealPlanCardEffect and not play_context.has("selected_enemy_card") and not clicked_unit.hand.is_empty():
			_show_ranger_enemy_hand_choice(clicked_unit)
			return
		played = controller.play_card(controller.current_unit, pending_card, [clicked_unit], play_context, pending_play_mode)
	elif clicked_object != null and pending_card.can_target_objects():
		played = controller.play_card(
			controller.current_unit,
			pending_card,
			[clicked_object],
			play_context,
			pending_play_mode
		)
	else:
		_append_log("请选择一个合法单位或战场对象打出卡牌。")

	if played:
		_clear_input()
		_hide_discard_popup()


func _handle_card_landing(cell: Vector2i) -> void:
	if pending_card == null or pending_unit_target == null:
		_clear_input()
		return
	var play_context := pending_extra_context.duplicate()
	play_context["equipment_slot"] = pending_equipment_slot
	play_context["landing_cell"] = cell
	if controller.play_card(controller.current_unit, pending_card, [pending_unit_target], play_context, pending_play_mode):
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
	map_view.invalidate_preview_cache()
	map_view.queue_redraw()


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
	var unit := controller.current_unit
	if unit != null and unit.is_ranger() and unit.ranger_state.discard_debt > 0 and not unit.hand.is_empty():
		_show_ranger_discard_debt(unit)
		return
	controller.end_current_turn()
	_refresh()


func _select_deploy_unit(unit: BattleUnitState) -> void:
	if _actions_locked():
		return
	selected_deploy_unit = unit
	_append_log("选择部署：%s。" % unit.get_display_name())
	_refresh()


func _on_equipment_action_pressed(unit: BattleUnitState, effect: EquipmentEffect, action_id: String = "default") -> void:
	if _actions_locked():
		return
	controller.activate_equipment_action(unit, effect, action_id)
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
	var discard_choice_context := _build_card_choice_context(card, play_mode)
	if card.requires_curse_choice(discard_choice_context):
		_show_curse_choice(card, play_mode, {})
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


func _activate_discard_action(card: CardData) -> void:
	if _actions_locked() or controller.current_unit == null or card == null:
		return
	var context := {
		"controller": controller,
		"user": controller.current_unit,
		"card": card,
		"ranger_discard_activation": true,
	}
	_hide_discard_popup()
	if card.requires_ordered_discard_choice(context):
		_ordered_discard_is_discard_activation = true
		_show_ordered_discard_choice(card, CardEnums.CardPlayMode.NORMAL, context)
		return
	controller.activate_discard_card(controller.current_unit, card, context)
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
	var choice_context := {
		"controller": controller,
		"user": controller.current_unit,
		"card": card,
		"play_mode": play_mode,
	}
	if card.requires_ranger_recipe_choice(choice_context):
		_show_ranger_card_recipe_popup(card, play_mode, choice_context)
		_refresh()
		return
	if _needs_draw_pile_choice(card, play_mode):
		_show_draw_pile_choice(card, play_mode)
		_refresh()
		return
	if card.requires_curse_choice(choice_context):
		_show_curse_choice(card, play_mode, {})
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
	pending_unit_target = null
	_druid_prepare_hand_choice_active = false
	_pending_curse = null
	_pending_curse_action_id = ""


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
	if _curse_choice_popup != null:
		_curse_choice_popup.hide()


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
	_refresh_scheduled = false
	if not is_inside_tree():
		return

	if _actions_locked():
		_hide_action_popups()

	phase_label.text = _phase_text()
	if controller.scene_prototype != null:
		phase_label.text += " | " + controller.scene_prototype.get_display_title()

	var display_unit := _get_equipment_panel_unit()
	if display_unit == null:
		current_label.text = "当前单位：无"
	else:
		current_label.text = "当前角色：%s\n生命 %d/%d | 敏捷 %d" % [
			display_unit.get_display_name(),
			display_unit.get_current_health(),
			display_unit.get_max_health(),
			display_unit.get_agility(),
		]

	if controller.current_unit == null:
		ap_label.text = "AP -"
		_refresh_ap_orbs(0, controller.config.base_ap)
	else:
		ap_label.text = "AP %d / %d" % [
			controller.current_unit.current_ap,
			controller.current_unit.get_max_ap(controller.config),
		]
		_refresh_ap_orbs(controller.current_unit.current_ap, controller.current_unit.get_max_ap(controller.config))

	var actions_locked := _actions_locked()
	start_button.disabled = actions_locked or controller.phase != BattleController.Phase.DEPLOYMENT or not controller.can_start_battle()
	var is_player_turn := not actions_locked and controller.phase == BattleController.Phase.BATTLE \
			and controller.turn_flow_state == BattleController.TurnFlowState.ACTIVE \
			and controller.current_unit != null \
			and controller.current_unit.faction == BattleUnitState.Faction.PLAYER
	move_button.disabled = not is_player_turn
	attack_button.disabled = not is_player_turn
	deck_button.disabled = not is_player_turn
	discard_button.disabled = not is_player_turn
	curse_button.disabled = controller.current_unit == null
	end_turn_button.disabled = not is_player_turn
	_refresh_deploy_list()
	_refresh_class_resource_list()
	_refresh_equipment_list()
	_refresh_hand_list(is_player_turn)
	_refresh_discard_button()
	_refresh_discard_popup()
	_refresh_curse_button()
	_refresh_curse_popup()
	_refresh_manifest_popup()
	if inspected_enemy != null and inspected_enemy.is_alive():
		enemy_inspect_panel.bind_unit(inspected_enemy)
	else:
		_clear_enemy_inspection()
	map_view.invalidate_preview_cache()
	map_view.queue_redraw()
	var current := controller.current_unit
	if not _actions_locked() and current != null and current.is_ranger() \
			and current.ranger_state.pending_hand_discard_count > 0 \
			and (_ordered_discard_popup == null or not _ordered_discard_popup.visible):
		_show_ranger_pending_hand_discard(current)


func _inspect_enemy(unit: BattleUnitState) -> void:
	inspected_enemy = unit
	enemy_inspect_panel.bind_unit(unit)
	map_view.inspected_enemy = unit
	map_view.queue_redraw()


func _clear_enemy_inspection() -> void:
	inspected_enemy = null
	if enemy_inspect_panel != null:
		enemy_inspect_panel.clear()
	if map_view != null:
		map_view.inspected_enemy = null
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
			druid_label.text = "%s：法力 %d/%d | 附魔 %d | 诅咒 %d | %s" % [
				unit.get_display_name(),
				unit.get_available_mana(),
				unit.get_mana_capacity(),
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

		if unit.is_ranger():
			has_resources = true
			var ranger_label := Label.new()
			var stealth_text := "潜行" if unit.is_stealthed() else "显形"
			var combo_text := "可连击" if unit.ranger_state.combo_window_open else "连击关闭"
			ranger_label.text = "%s：%s | 连击 %d（%s）| 元素 %s" % [
				unit.get_display_name(),
				stealth_text,
				unit.ranger_state.combo_points,
				combo_text,
				unit.ranger_state.get_summary(),
			]
			class_resource_list.add_child(ranger_label)
			if unit == controller.current_unit and unit.is_stealthed() and unit.ranger_state.prepared_blend == BattleSurfaceState.Element.NONE:
				var blend_button := Button.new()
				blend_button.text = "调配特调"
				blend_button.tooltip_text = "消耗两枚不同基础元素，为近战或远程模式装填一份特调。"
				blend_button.disabled = _actions_locked() or unit.ranger_state.get_element_type_count() < 2
				blend_button.pressed.connect(_show_ranger_blend_popup.bind(unit))
				class_resource_list.add_child(blend_button)
			elif unit.ranger_state.prepared_blend != BattleSurfaceState.Element.NONE:
				var prepared_label := Label.new()
				prepared_label.text = "已装填：%s（%s）" % [
					BattleSurfaceState.label(unit.ranger_state.prepared_blend),
					"近战" if unit.ranger_state.prepared_weapon_slot == "weapon" else "远程",
				]
				class_resource_list.add_child(prepared_label)

		for pool_state in unit.character_state.class_resources:
			if pool_state == null:
				continue

			has_resources = true
			var button := Button.new()
			button.text = "%s：%s" % [unit.get_display_name(), pool_state.get_display_text()]
			button.disabled = true
			class_resource_list.add_child(button)

	if not has_resources:
		var label := Label.new()
		label.text = "无职业资源"
		class_resource_list.add_child(label)


func _refresh_equipment_list() -> void:
	_clear_children(equipment_list)
	var unit := _get_equipment_panel_unit()
	if unit == null or unit.character_state == null:
		_add_equipment_label("未选择角色")
		return

	_add_equipment_label(unit.character_state.get_main_hand_label())
	_add_equipment_label(unit.character_state.get_off_hand_label())
	var runtime_summary := unit.get_equipment_runtime_summary({"controller": controller, "unit": unit})
	if not runtime_summary.is_empty():
		_add_equipment_label("战斗状态：%s" % runtime_summary)

	var phase_name := "deployment" if controller.phase == BattleController.Phase.DEPLOYMENT else "battle"
	var action_context := {"controller": controller, "unit": unit, "phase": phase_name}
	var actions := unit.get_equipment_actions(action_context)
	if actions.is_empty():
		_add_equipment_label("当前无可用装备行动")
		return
	for action in actions:
		var action_button := Button.new()
		action_button.text = str(action.get("label", "装备行动"))
		action_button.tooltip_text = "执行当前角色的装备主动效果"
		var effect := action.get("effect") as EquipmentEffect
		var action_id := str(action.get("action_id", "default"))
		action_button.disabled = _actions_locked() or not controller.can_activate_equipment_action(unit, effect, action_id)
		action_button.pressed.connect(_on_equipment_action_pressed.bind(unit, effect, action_id))
		equipment_list.add_child(action_button)


func _get_equipment_panel_unit() -> BattleUnitState:
	if controller.current_unit != null:
		return controller.current_unit
	if selected_deploy_unit != null:
		return selected_deploy_unit
	if not controller.player_units.is_empty():
		return controller.player_units[0]
	return null


func _add_equipment_label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	equipment_list.add_child(label)


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


func _refresh_curse_button() -> void:
	var unit := controller.current_unit
	if unit == null:
		curse_button.text = "诅咒区"
		return
	var load_text := "-"
	if unit.character_state != null:
		load_text = "%d/%d" % [unit.character_state.get_curse_load(), unit.character_state.get_curse_load_limit()]
	curse_button.text = "诅咒 %d · 畸变 %d · 负荷 %s · 咒波 %d" % [
		_get_display_curses(unit).size(),
		unit.get_active_distortion_fields().size(),
		load_text,
		unit.curse_wave,
	]


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
			var can_discard_action := controller.can_activate_discard_card(unit, card)
			button.text = card.get_discard_action_label({"controller": controller, "user": unit, "card": card}) if can_discard_action else _discard_card_button_text(card)
			button.tooltip_text = _build_card_tooltip(card)
			button.disabled = _actions_locked() or (not can_discard_action and not controller.can_play_card_with_mode(unit, card, CardEnums.CardPlayMode.MOMENTUM))
			if not button.disabled:
				if can_discard_action:
					button.pressed.connect(_activate_discard_action.bind(card))
				else:
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
	return " | 攻击伤害 %d" % unit.get_attack()


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
	var text := "主手：基础伤害 %d / 伤害加值 %d" % [
		profile.primary_base_damage,
		profile.primary_damage_bonus,
	]
	if profile.add_offhand:
		text += " / 副手：基础伤害 %d / 伤害加值 %d" % [profile.offhand_base_damage, profile.offhand_damage_bonus]
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

	var cancel_button := Button.new()
	cancel_button.text = "取消"
	cancel_button.pressed.connect(_cancel_ordered_discard_choice)
	controls.add_child(cancel_button)

	_ordered_discard_confirm_button = Button.new()
	_ordered_discard_confirm_button.text = "确认"
	_ordered_discard_confirm_button.pressed.connect(_confirm_ordered_discard_choice)
	controls.add_child(_ordered_discard_confirm_button)


func _create_ranger_blend_popup() -> void:
	_ranger_blend_popup = PopupPanel.new()
	_ranger_blend_popup.title = "调配特调"
	_ranger_blend_popup.exclusive = true
	add_child(_ranger_blend_popup)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_ranger_blend_popup.add_child(margin)

	_ranger_blend_list = VBoxContainer.new()
	_ranger_blend_list.custom_minimum_size = Vector2(360, 0)
	_ranger_blend_list.add_theme_constant_override("separation", 8)
	margin.add_child(_ranger_blend_list)


func _show_ranger_blend_popup(unit: BattleUnitState) -> void:
	if unit == null or unit != controller.current_unit or not unit.is_ranger():
		return
	_clear_children(_ranger_blend_list)
	var title := Label.new()
	title.text = "选择配方与装填武器"
	_ranger_blend_list.add_child(title)
	for blend in [
		BattleSurfaceState.Element.STEAM,
		BattleSurfaceState.Element.LAVA,
		BattleSurfaceState.Element.BLAZE,
		BattleSurfaceState.Element.POISON_BOG,
		BattleSurfaceState.Element.ICE,
		BattleSurfaceState.Element.SANDSTORM,
	]:
		var ingredients: Array[int] = controller.surface_state.get_component_elements(blend)
		if not unit.ranger_state.can_pay_elements(ingredients):
			continue
		var row := HBoxContainer.new()
		var recipe_label := Label.new()
		recipe_label.text = BattleSurfaceState.label(blend)
		recipe_label.custom_minimum_size.x = 100
		row.add_child(recipe_label)
		for slot in ["weapon", "paired"]:
			var button := Button.new()
			button.text = "近战" if slot == "weapon" else "远程"
			button.disabled = not unit.can_use_attack_mode(slot)
			button.pressed.connect(_on_ranger_blend_selected.bind(unit, blend, slot))
			row.add_child(button)
		_ranger_blend_list.add_child(row)
	_ranger_blend_popup.popup_centered()


func _on_ranger_blend_selected(unit: BattleUnitState, blend: int, equipment_slot: String) -> void:
	_ranger_blend_popup.hide()
	controller.prepare_ranger_blend(unit, blend, equipment_slot)
	_refresh()


func _show_ranger_card_recipe_popup(card: CardData, play_mode: int, context: Dictionary) -> void:
	_ranger_recipe_card = card
	_ranger_recipe_play_mode = play_mode
	_clear_children(_ranger_blend_list)
	var title := Label.new()
	title.text = "%s：选择配方与催化剂" % card.card_name
	_ranger_blend_list.add_child(title)
	for option in card.get_ranger_recipe_options(context):
		var button := Button.new()
		button.text = str(option.get("label", "配方"))
		button.pressed.connect(_on_ranger_card_recipe_selected.bind(option))
		_ranger_blend_list.add_child(button)
	_ranger_blend_popup.popup_centered()


func _on_ranger_card_recipe_selected(option: Dictionary) -> void:
	var card := _ranger_recipe_card
	var play_mode := _ranger_recipe_play_mode
	_ranger_recipe_card = null
	_ranger_recipe_play_mode = CardEnums.CardPlayMode.NORMAL
	_ranger_blend_popup.hide()
	if card == null:
		return
	pending_extra_context = option.duplicate(true)
	if _is_direct_card_target(card, play_mode):
		_play_direct_card(card, play_mode, pending_extra_context)
	else:
		_begin_card_targeting(card, play_mode)
	_refresh()


func _show_ranger_enemy_hand_choice(target: BattleUnitState) -> void:
	if pending_card == null or target == null:
		return
	_ranger_enemy_hand_target = target
	_clear_children(_ranger_blend_list)
	var title := Label.new()
	title.text = "窃取预案：选择 %s 的一张手牌" % target.get_display_name()
	_ranger_blend_list.add_child(title)
	var effect := pending_card.effect as RangerStealPlanCardEffect
	var context := pending_extra_context.duplicate()
	context["controller"] = controller
	context["user"] = controller.current_unit
	context["card"] = pending_card
	var copyable := effect.get_copyable_enemy_cards(context, target)
	var dagger_mode := pending_equipment_slot != "paired"
	for enemy_card in target.hand:
		if enemy_card == null:
			continue
		var button := Button.new()
		button.text = enemy_card.card_name
		button.tooltip_text = _build_card_tooltip(enemy_card)
		button.disabled = dagger_mode and not copyable.has(enemy_card)
		button.pressed.connect(_on_ranger_enemy_hand_selected.bind(enemy_card))
		_ranger_blend_list.add_child(button)
	_ranger_blend_popup.popup_centered()


func _on_ranger_enemy_hand_selected(enemy_card: CardData) -> void:
	var target := _ranger_enemy_hand_target
	_ranger_enemy_hand_target = null
	_ranger_blend_popup.hide()
	if pending_card == null or target == null or enemy_card == null:
		return
	var play_context := pending_extra_context.duplicate()
	play_context["equipment_slot"] = pending_equipment_slot
	play_context["selected_enemy_card"] = enemy_card
	if controller.play_card(controller.current_unit, pending_card, [target], play_context, pending_play_mode):
		_clear_input()
		_hide_discard_popup()
	_refresh()


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
	_ordered_discard_is_ranger_debt = false
	_ordered_discard_is_discard_activation = bool(extra_context.get("ranger_discard_activation", false))
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


func _show_ranger_discard_debt(unit: BattleUnitState) -> void:
	if unit == null or not unit.is_ranger():
		return
	_ordered_discard_card = null
	_ordered_discard_is_ranger_debt = true
	_ordered_discard_selected_cards.clear()
	_ordered_discard_max_count = mini(unit.ranger_state.discard_debt, unit.hand.size())
	_ordered_discard_min_count = _ordered_discard_max_count
	_clear_children(_ordered_discard_list)
	var title := Label.new()
	title.text = "支付弃牌债务：选择 %d 张手牌弃置" % _ordered_discard_max_count
	_ordered_discard_list.add_child(title)
	for choice in unit.hand:
		if choice == null:
			continue
		var button := Button.new()
		button.text = "%s | %s" % [choice.card_name, choice.get_card_type_label()]
		button.tooltip_text = _build_card_tooltip(choice)
		button.pressed.connect(_add_ordered_discard_choice.bind(choice))
		_ordered_discard_list.add_child(button)
	_refresh_ordered_discard_selected_label()
	_ordered_discard_popup.popup_centered()


func _show_ranger_pending_hand_discard(unit: BattleUnitState) -> void:
	if unit == null or not unit.is_ranger() or unit.hand.is_empty():
		return
	_ordered_discard_card = null
	_ordered_discard_is_ranger_debt = false
	_ordered_discard_is_discard_activation = false
	_ordered_discard_is_pending_ranger = true
	_ordered_discard_selected_cards.clear()
	_ordered_discard_max_count = mini(unit.ranger_state.pending_hand_discard_count, unit.hand.size())
	_ordered_discard_min_count = _ordered_discard_max_count
	_clear_children(_ordered_discard_list)
	var title := Label.new()
	title.text = "选择 %d 张手牌弃置" % _ordered_discard_max_count
	_ordered_discard_list.add_child(title)
	for choice in unit.hand:
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


func _cancel_ordered_discard_choice() -> void:
	if _ordered_discard_is_pending_ranger:
		return
	_ordered_discard_card = null
	_ordered_discard_is_ranger_debt = false
	_ordered_discard_is_discard_activation = false
	_ordered_discard_is_pending_ranger = false
	_ordered_discard_play_mode = CardEnums.CardPlayMode.NORMAL
	_ordered_discard_extra_context.clear()
	_ordered_discard_selected_cards.clear()
	_ordered_discard_max_count = 0
	_ordered_discard_min_count = 0
	_ordered_discard_popup.hide()


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

	if _ordered_discard_is_ranger_debt:
		var unit := controller.current_unit
		var selected_cards := _ordered_discard_selected_cards.duplicate()
		_ordered_discard_is_ranger_debt = false
		_ordered_discard_selected_cards.clear()
		_ordered_discard_min_count = 0
		_ordered_discard_max_count = 0
		_ordered_discard_popup.hide()
		if unit != null and unit.is_ranger():
			for selected_card in selected_cards:
				unit.discard_card(selected_card, {
					"controller": controller,
					"source": unit,
					"reason": "ranger_discard_debt",
				})
			unit.ranger_state.discard_debt = 0
		controller.end_current_turn()
		_refresh()
		return
	if _ordered_discard_is_pending_ranger:
		var pending_unit := controller.current_unit
		var pending_cards := _ordered_discard_selected_cards.duplicate()
		_ordered_discard_is_pending_ranger = false
		_ordered_discard_selected_cards.clear()
		_ordered_discard_min_count = 0
		_ordered_discard_max_count = 0
		_ordered_discard_popup.hide()
		if pending_unit != null and pending_unit.is_ranger():
			for selected_card in pending_cards:
				pending_unit.discard_card(selected_card, {
					"controller": controller,
					"source": pending_unit,
					"reason": "ranger_pending_hand_discard",
				})
			pending_unit.ranger_state.pending_hand_discard_count = 0
		_refresh()
		return
	if _ordered_discard_is_discard_activation:
		var discard_action_card := _ordered_discard_card
		var discard_context := _ordered_discard_extra_context.duplicate()
		discard_context["ordered_discard_cards"] = _ordered_discard_selected_cards.duplicate()
		_ordered_discard_is_discard_activation = false
		_ordered_discard_card = null
		_ordered_discard_extra_context.clear()
		_ordered_discard_selected_cards.clear()
		_ordered_discard_min_count = 0
		_ordered_discard_max_count = 0
		_ordered_discard_popup.hide()
		controller.activate_discard_card(controller.current_unit, discard_action_card, discard_context)
		_refresh()
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
	if card.requires_curse_choice(_build_card_choice_context(card, play_mode, extra_context)) and not extra_context.has("selected_curse"):
		_show_curse_choice(card, play_mode, extra_context)
		_refresh()
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


func _build_card_choice_context(card: CardData, play_mode: int, extra_context: Dictionary = {}) -> Dictionary:
	var context := extra_context.duplicate()
	context["controller"] = controller
	context["user"] = controller.current_unit
	context["card"] = card
	context["play_mode"] = play_mode
	context["equipment_slot"] = pending_equipment_slot
	return context


func _create_curse_choice_popup() -> void:
	_curse_choice_popup = PopupPanel.new()
	_curse_choice_popup.title = "选择诅咒"
	_curse_choice_popup.exclusive = true
	add_child(_curse_choice_popup)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_curse_choice_popup.add_child(margin)
	_curse_choice_list = VBoxContainer.new()
	_curse_choice_list.custom_minimum_size = Vector2(340, 120)
	_curse_choice_list.add_theme_constant_override("separation", 6)
	margin.add_child(_curse_choice_list)


func _show_curse_choice(card: CardData, play_mode: int, extra_context: Dictionary) -> void:
	_curse_choice_card = card
	_curse_choice_play_mode = play_mode
	_curse_choice_extra_context = extra_context.duplicate()
	_clear_children(_curse_choice_list)
	var context := _build_card_choice_context(card, play_mode, extra_context)
	var title := Label.new()
	title.text = card.get_curse_choice_prompt(context)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_curse_choice_list.add_child(title)
	for curse in card.get_curse_choice_options(context):
		var button := Button.new()
		button.text = curse.get_summary()
		button.tooltip_text = curse.definition.get_description_for_state(curse.state) if curse.definition != null else ""
		button.pressed.connect(_on_curse_choice_selected.bind(curse))
		_curse_choice_list.add_child(button)
	_curse_choice_popup.popup_centered()


func _on_curse_choice_selected(curse: CurseInstance) -> void:
	var card := _curse_choice_card
	var play_mode := _curse_choice_play_mode
	var extra_context := _curse_choice_extra_context.duplicate()
	extra_context["selected_curse"] = curse
	_curse_choice_card = null
	_curse_choice_play_mode = CardEnums.CardPlayMode.NORMAL
	_curse_choice_extra_context.clear()
	_curse_choice_popup.hide()
	_continue_card_with_extra_context(card, play_mode, extra_context)


func _create_curse_popup() -> void:
	_curse_popup = PopupPanel.new()
	_curse_popup.title = "诅咒区"
	_curse_popup.exclusive = false
	add_child(_curse_popup)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_curse_popup.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 420)
	margin.add_child(scroll)
	_curse_list = VBoxContainer.new()
	_curse_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_curse_list)


func _create_manifest_popup() -> void:
	_manifest_popup = PopupPanel.new()
	_manifest_popup.title = "选择显化牌"
	_manifest_popup.exclusive = true
	add_child(_manifest_popup)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	_manifest_popup.add_child(margin)
	_manifest_list = VBoxContainer.new()
	_manifest_list.custom_minimum_size = Vector2(480, 260)
	_manifest_list.add_theme_constant_override("separation", 8)
	margin.add_child(_manifest_list)


func _refresh_manifest_popup() -> void:
	if _manifest_popup == null or _manifest_list == null:
		return
	var unit := controller.current_unit
	var waiting := controller.phase == BattleController.Phase.BATTLE \
			and controller.turn_flow_state == BattleController.TurnFlowState.MANIFEST_PENDING \
			and unit != null and unit.faction == BattleUnitState.Faction.PLAYER
	if not waiting:
		_manifest_selected.clear()
		_manifest_popup.hide()
		return
	var eligible := unit.get_manifestable_hand_cards()
	for selected in _manifest_selected.duplicate():
		if not eligible.has(selected):
			_manifest_selected.erase(selected)
	_clear_children(_manifest_list)
	var title := Label.new()
	title.text = "%s · 显化 0–2 张" % unit.get_display_name()
	title.add_theme_font_size_override("font_size", 18)
	_manifest_list.add_child(title)
	for card in eligible:
		var toggle := CheckBox.new()
		toggle.text = "%s · %s" % [card.card_name, card.get_mutation_label()]
		toggle.tooltip_text = card.description
		toggle.button_pressed = _manifest_selected.has(card)
		toggle.disabled = _manifest_selected.size() >= 2 and not toggle.button_pressed
		toggle.toggled.connect(_on_manifest_card_toggled.bind(card))
		_manifest_list.add_child(toggle)
	var confirm := Button.new()
	confirm.text = "确认显化" if not _manifest_selected.is_empty() else "跳过显化"
	confirm.pressed.connect(_confirm_manifest_selection)
	_manifest_list.add_child(confirm)
	if not _manifest_popup.visible:
		_manifest_popup.popup_centered()


func _on_manifest_card_toggled(enabled: bool, card: CardData) -> void:
	if enabled:
		if not _manifest_selected.has(card) and _manifest_selected.size() < 2:
			_manifest_selected.append(card)
	else:
		_manifest_selected.erase(card)
	_refresh_manifest_popup()


func _confirm_manifest_selection() -> void:
	var unit := controller.current_unit
	var selected: Array[CardData] = []
	selected.assign(_manifest_selected)
	if controller.submit_manifestation_selection(unit, selected):
		_manifest_selected.clear()
		_manifest_popup.hide()
		_refresh()


func _show_curse_popup() -> void:
	_refresh_curse_popup(true)
	_curse_popup.popup_centered()


func _refresh_curse_popup(force: bool = false) -> void:
	if _curse_popup == null or _curse_list == null or (not force and not _curse_popup.visible):
		return
	_clear_children(_curse_list)
	for unit in controller.units:
		if unit == null:
			continue
		var display_curses := _get_display_curses(unit)
		var distortion_fields := unit.get_active_distortion_fields()
		if display_curses.is_empty() and unit.curse_wave <= 0 and distortion_fields.is_empty():
			continue
		var heading := Label.new()
		var load_text := ""
		if unit.character_state != null:
			load_text = " · 负荷 %d/%d" % [unit.character_state.get_curse_load(), unit.character_state.get_curse_load_limit()]
		heading.text = "%s%s · 咒波 %d" % [unit.get_display_name(), load_text, unit.curse_wave]
		heading.add_theme_font_size_override("font_size", 17)
		_curse_list.add_child(heading)
		if display_curses.is_empty():
			var empty := Label.new()
			empty.text = "无常驻诅咒"
			_curse_list.add_child(empty)
		if not distortion_fields.is_empty():
			var mutation_summary := Label.new()
			mutation_summary.text = "畸变：%s" % unit.get_active_distortion_summary()
			mutation_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			mutation_summary.add_theme_color_override("font_color", Color("#d9a96e"))
			_curse_list.add_child(mutation_summary)
			for card in unit.distortion_state.manifested_cards:
				if card == null:
					continue
				var source_label := Label.new()
				source_label.text = "显化牌 · %s · %s" % [card.card_name, card.get_mutation_label()]
				source_label.modulate = Color(0.78, 0.72, 0.66)
				_curse_list.add_child(source_label)
		for curse in display_curses:
			if curse == null:
				continue
			var summary := Label.new()
			summary.text = curse.get_summary()
			summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_curse_list.add_child(summary)
			var description := Label.new()
			description.text = curse.definition.get_description_for_state(curse.state) if curse.definition != null else ""
			description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			description.modulate = Color(0.82, 0.82, 0.82)
			_curse_list.add_child(description)
	if controller.current_unit != null and controller.current_unit.faction == BattleUnitState.Faction.PLAYER:
		var actions := controller.current_unit.get_curse_actions({"controller": controller, "phase": "action"})
		if not actions.is_empty():
			var action_title := Label.new()
			action_title.text = "诅咒行动"
			action_title.add_theme_font_size_override("font_size", 16)
			_curse_list.add_child(action_title)
			for action in actions:
				var curse := action.get("curse") as CurseInstance
				var action_id := str(action.get("id", ""))
				var button := Button.new()
				button.text = str(action.get("label", "诅咒行动"))
				button.disabled = controller.turn_flow_state != BattleController.TurnFlowState.ACTIVE or _actions_locked()
				button.pressed.connect(_on_curse_action_pressed.bind(curse, action_id, str(action.get("selection", "none"))))
				_curse_list.add_child(button)
		var distortion_actions := controller.current_unit.get_distortion_actions()
		if not distortion_actions.is_empty():
			var distortion_title := Label.new()
			distortion_title.text = "畸变行动"
			distortion_title.add_theme_font_size_override("font_size", 16)
			_curse_list.add_child(distortion_title)
			for action in distortion_actions:
				var distortion_button := Button.new()
				distortion_button.text = str(action.get("label", "畸变行动"))
				distortion_button.disabled = controller.turn_flow_state != BattleController.TurnFlowState.ACTIVE or _actions_locked()
				distortion_button.pressed.connect(_on_distortion_action_pressed.bind(str(action.get("id", ""))))
				_curse_list.add_child(distortion_button)


func _on_distortion_action_pressed(action_id: String) -> void:
	var unit := controller.current_unit
	if unit != null and controller.turn_flow_state == BattleController.TurnFlowState.ACTIVE:
		unit.activate_distortion_action(action_id)
	_refresh_curse_popup(true)


func _get_display_curses(unit: BattleUnitState) -> Array[CurseInstance]:
	var result: Array[CurseInstance] = []
	if unit == null:
		return result
	if unit.character_state != null:
		for curse in unit.character_state.curse_instances:
			if curse != null and curse.state != CurseInstance.State.INDUSTRY:
				result.append(curse)
	else:
		result.append_array(unit.curse_zone)
	return result


func _on_curse_action_pressed(curse: CurseInstance, action_id: String, selection: String) -> void:
	var unit := controller.current_unit
	if unit == null or curse == null:
		return
	match selection:
		"enemy":
			_pending_curse = curse
			_pending_curse_action_id = action_id
			input_mode = InputMode.CURSE_TARGET
			_curse_popup.hide()
			_append_log("选择诅咒行动的敌方目标。")
		"cell":
			_pending_curse = curse
			_pending_curse_action_id = action_id
			input_mode = InputMode.CURSE_CELL
			_curse_popup.hide()
			_append_log("选择诅咒行动的目标格。")
		"hand_disease":
			var diseases: Array[CardData] = []
			for card in unit.hand:
				if card != null and card.card_name == "病症":
					diseases.append(card)
			_show_curse_action_card_choices(curse, action_id, diseases)
		"hand":
			_show_curse_action_card_choices(curse, action_id, unit.hand)
		"discard":
			_show_curse_action_card_choices(curse, action_id, unit.discard_pile)
		_:
			controller.activate_curse_action(unit, curse, action_id)
			_refresh()


func _show_curse_action_card_choices(curse: CurseInstance, action_id: String, cards: Array[CardData]) -> void:
	_clear_children(_curse_list)
	var title := Label.new()
	title.text = "选择一张牌"
	_curse_list.add_child(title)
	for card in cards:
		var button := Button.new()
		button.text = card.card_name
		button.tooltip_text = _build_card_tooltip(card)
		button.pressed.connect(_on_curse_action_card_selected.bind(curse, action_id, card))
		_curse_list.add_child(button)


func _on_curse_action_card_selected(curse: CurseInstance, action_id: String, card: CardData) -> void:
	controller.activate_curse_action(controller.current_unit, curse, action_id, {"selected_card": card})
	_refresh_curse_popup(true)


func _resolve_pending_curse_action(context: Dictionary) -> void:
	if _pending_curse == null or _pending_curse_action_id.is_empty():
		_clear_input()
		return
	if controller.activate_curse_action(controller.current_unit, _pending_curse, _pending_curse_action_id, context):
		_clear_input()
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

	var options := controller.current_unit.get_attack_weapon_options()
	if options.size() == 1:
		_on_weapon_choice_pressed(str(options[0].get("slot", "")))
		return
	if options.is_empty():
		_append_log("当前没有可用的武器模式。")
		return
	for option in options:
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
