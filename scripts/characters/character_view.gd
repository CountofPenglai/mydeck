extends Control
class_name CharacterView

var _character_state: CharacterState

@export var character_state: CharacterState:
	get:
		return _character_state
	set(value):
		_character_state = value
		if is_inside_tree():
			_refresh()

@onready var portrait_rect: TextureRect = %PortraitRect
@onready var battle_rect: TextureRect = %BattleRect
@onready var name_label: Label = %NameLabel
@onready var class_label: Label = %ClassLabel
@onready var health_label: Label = %HealthLabel
@onready var attack_label: Label = %AttackLabel
@onready var speed_label: Label = %SpeedLabel
@onready var main_hand_label: Label = %MainHandLabel
@onready var off_hand_label: Label = %OffHandLabel
@onready var deck_label: Label = %DeckLabel
@onready var inventory_label: Label = %InventoryLabel
@onready var resource_list: VBoxContainer = %ResourceList

func _ready() -> void:
	_refresh()


func setup(state: CharacterState) -> void:
	_character_state = state
	_refresh()


func _refresh() -> void:
	if not is_inside_tree():
		return

	if _character_state == null or _character_state.character_data == null:
		_show_empty_state()
		return

	_character_state.ensure_initialized()

	var data := _character_state.character_data
	name_label.text = _character_state.get_character_name()
	class_label.text = "职业：" + _character_state.get_class_label()
	health_label.text = "生命：%d/%d" % [_character_state.current_health, _character_state.get_max_health()]
	attack_label.text = "力量：%d" % _character_state.get_strength()
	speed_label.text = "敏捷：%d" % _character_state.get_agility()
	main_hand_label.text = _character_state.get_main_hand_label()
	off_hand_label.text = _character_state.get_off_hand_label()
	deck_label.text = "当前卡组：%d 张 / %d 种" % [_character_state.get_deck_card_count(), _character_state.deck.size()]
	inventory_label.text = "背包：%d 件 / %d 种" % [_character_state.get_inventory_item_count(), _character_state.inventory.size()]
	portrait_rect.texture = data.portrait
	battle_rect.texture = data.battle_sprite
	_refresh_resource_list()


func _show_empty_state() -> void:
	name_label.text = "未绑定角色"
	class_label.text = "职业：-"
	health_label.text = "生命：-"
	attack_label.text = "力量：-"
	speed_label.text = "敏捷：-"
	main_hand_label.text = "主手：-"
	off_hand_label.text = "副手：-"
	deck_label.text = "当前卡组：-"
	inventory_label.text = "背包：-"
	portrait_rect.texture = null
	battle_rect.texture = null
	_clear_resource_list()


func _refresh_resource_list() -> void:
	_clear_resource_list()

	for pool_state in _character_state.class_resources:
		if pool_state == null:
			continue

		var label := Label.new()
		label.text = pool_state.get_display_text()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		resource_list.add_child(label)

	if resource_list.get_child_count() == 0:
		var empty_label := Label.new()
		empty_label.text = "职业资源：无"
		resource_list.add_child(empty_label)


func _clear_resource_list() -> void:
	for child in resource_list.get_children():
		resource_list.remove_child(child)
		child.queue_free()
