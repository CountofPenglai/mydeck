extends Control
class_name BattleScene

const HAND_CARD_SLOT_TEXTURE := preload("res://assets/art/ui/hand_card_slot.png")

@export var scenario: BattleScenario

var controller := BattleController.new()
var selected_deploy_unit: BattleUnitState
var selected_card: CardData
var pending_basic_attack := false
var pending_move := false

@onready var map_view: BattleMapView = %MapView
@onready var phase_label: Label = %PhaseLabel
@onready var current_label: Label = %CurrentLabel
@onready var deploy_list: VBoxContainer = %DeployList
@onready var hand_list: HBoxContainer = %HandList
@onready var start_button: Button = %StartButton
@onready var end_turn_button: Button = %EndTurnButton
@onready var move_button: TextureButton = %MoveButton
@onready var attack_button: TextureButton = %AttackButton
@onready var deck_button: TextureButton = %DeckButton
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
	controller.setup(scenario)
	selected_deploy_unit = controller.get_first_undeployed_player()
	_refresh()


func handle_map_click(position: Vector2) -> void:
	if controller.phase == BattleController.Phase.DEPLOYMENT:
		if selected_deploy_unit == null:
			selected_deploy_unit = controller.get_first_undeployed_player()
		if selected_deploy_unit != null and controller.deploy_player_unit(selected_deploy_unit, position):
			selected_deploy_unit = controller.get_first_undeployed_player()
		_refresh()
		return

	if controller.phase != BattleController.Phase.BATTLE:
		return

	if controller.current_unit == null or controller.current_unit.faction != BattleUnitState.Faction.PLAYER:
		return

	var clicked_unit := controller.get_unit_at_position(position)
	if pending_basic_attack:
		if clicked_unit != null and clicked_unit.faction == BattleUnitState.Faction.ENEMY:
			controller.basic_attack(controller.current_unit, clicked_unit)
			pending_basic_attack = false
		else:
			_append_log("请选择一个敌方目标进行普通攻击。")
		_refresh()
		return

	if selected_card != null:
		if clicked_unit != null and clicked_unit.faction == BattleUnitState.Faction.ENEMY:
			if controller.play_card(controller.current_unit, selected_card, [clicked_unit]):
				selected_card = null
		else:
			_append_log("请选择一个敌方目标打出卡牌。")
		_refresh()
		return

	if pending_move:
		if controller.move_current_unit_to(position):
			pending_move = false
		_refresh()
		return

	_append_log("请选择移动、攻击或一张手牌。")
	_refresh()


func _on_start_pressed() -> void:
	controller.start_battle()
	_refresh()


func _on_move_pressed() -> void:
	selected_card = null
	pending_basic_attack = false
	pending_move = true
	_append_log("请选择移动位置。")
	_refresh()


func _on_attack_pressed() -> void:
	selected_card = null
	pending_move = false
	pending_basic_attack = true
	_append_log("请选择普通攻击目标。")
	_refresh()


func _on_deck_pressed() -> void:
	var unit := controller.current_unit
	if unit == null or unit.faction != BattleUnitState.Faction.PLAYER:
		_append_log("当前没有可查看牌库的玩家单位。")
		return

	var preview: PackedStringArray = []
	for card in unit.draw_pile:
		if card == null:
			continue
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


func _on_end_turn_pressed() -> void:
	selected_card = null
	pending_basic_attack = false
	pending_move = false
	controller.end_current_turn()
	_refresh()


func _select_deploy_unit(unit: BattleUnitState) -> void:
	selected_deploy_unit = unit
	_append_log("选择部署：%s。" % unit.get_display_name())
	_refresh()


func _select_card(card: CardData) -> void:
	selected_card = card
	pending_move = false
	pending_basic_attack = false
	_append_log("选择卡牌：%s，请点击目标。" % card.card_name)
	_refresh()


func _refresh() -> void:
	if not is_inside_tree():
		return

	phase_label.text = _phase_text()
	if controller.scene_prototype != null:
		phase_label.text += " | " + controller.scene_prototype.get_display_title()

	if controller.current_unit == null:
		current_label.text = "当前单位：无"
		ap_label.text = "AP -"
	else:
		current_label.text = "当前单位：%s | 生命 %d/%d | 速度 %d" % [
			controller.current_unit.get_display_name(),
			controller.current_unit.get_current_health(),
			controller.current_unit.get_max_health(),
			controller.current_unit.get_speed(),
		]
		ap_label.text = "AP %d / %d" % [
			controller.current_unit.current_ap,
			controller.current_unit.get_max_ap(controller.config),
		]

	start_button.disabled = controller.phase != BattleController.Phase.DEPLOYMENT or not controller.can_start_battle()
	var is_player_turn := controller.phase == BattleController.Phase.BATTLE and controller.current_unit != null and controller.current_unit.faction == BattleUnitState.Faction.PLAYER
	move_button.disabled = not is_player_turn
	attack_button.disabled = not is_player_turn
	deck_button.disabled = not is_player_turn
	end_turn_button.disabled = not is_player_turn
	_refresh_deploy_list()
	_refresh_hand_list(is_player_turn)
	map_view.queue_redraw()


func _refresh_deploy_list() -> void:
	_clear_children(deploy_list)
	for unit in controller.player_units:
		var button := Button.new()
		button.text = "%s %s" % [unit.get_display_name(), "(已部署)" if unit.is_deployed else "(待部署)"]
		button.disabled = controller.phase != BattleController.Phase.DEPLOYMENT
		button.pressed.connect(_select_deploy_unit.bind(unit))
		deploy_list.add_child(button)


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
		var button := TextureButton.new()
		button.texture_normal = HAND_CARD_SLOT_TEXTURE
		button.ignore_texture_size = true
		button.stretch_mode = 0
		button.custom_minimum_size = Vector2(112, 138)
		button.tooltip_text = "%s | %dAP | %s | 射程 %.0f" % [
			card.card_name,
			card.ap_cost,
			card.get_play_timing_label(),
			card.get_effective_range(controller.current_unit),
		]
		button.pressed.connect(_select_card.bind(card))

		var label := Label.new()
		label.text = "%s\n%dAP\n射程 %.0f" % [
			card.card_name,
			card.ap_cost,
			card.get_effective_range(controller.current_unit),
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


func _clear_children(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
