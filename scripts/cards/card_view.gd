extends Control
class_name CardView

signal play_requested(card_data: CardData)

var _card_data: CardData

@export var card_data: CardData:
	get:
		return _card_data
	set(value):
		_card_data = value
		if is_inside_tree():
			_refresh()

@export var play_context: Dictionary = {}
@export var selected_targets: Array = []

@onready var name_label: Label = %NameLabel
@onready var rarity_label: Label = %RarityLabel
@onready var artwork_rect: TextureRect = %ArtworkRect
@onready var description_label: Label = %DescriptionLabel
@onready var class_label: Label = %ClassLabel
@onready var target_label: Label = %TargetLabel
@onready var target_hint_label: Label = %TargetHintLabel
@onready var play_button: Button = %PlayButton

func _ready() -> void:
	play_button.pressed.connect(_on_play_button_pressed)
	_refresh()


func setup(data: CardData) -> void:
	_card_data = data
	_refresh()


func _refresh() -> void:
	if not is_inside_tree():
		return

	if _card_data == null:
		_show_empty_state()
		return

	name_label.text = _card_data.card_name
	rarity_label.text = _card_data.get_rarity_label()
	description_label.text = _card_data.description
	class_label.text = "职业：" + _card_data.get_class_label()
	target_label.text = "目标：" + _card_data.get_target_label()
	target_hint_label.text = _target_hint_text(_card_data.target_type)
	play_button.text = _card_data.get_action_label()
	play_button.disabled = not _card_data.can_play(play_context)

	if _card_data.artwork != null:
		artwork_rect.texture = _card_data.artwork
	else:
		artwork_rect.texture = null


func _show_empty_state() -> void:
	name_label.text = "未绑定卡牌"
	rarity_label.text = "-"
	description_label.text = "在 Inspector 中绑定 CardData Resource。"
	class_label.text = "职业：-"
	target_label.text = "目标：-"
	target_hint_label.text = "等待卡牌数据"
	play_button.text = "打出"
	play_button.disabled = true
	artwork_rect.texture = null


func _on_play_button_pressed() -> void:
	if _card_data == null:
		return

	if not _card_data.can_play(play_context):
		play_button.disabled = true
		return

	_card_data.play(play_context, selected_targets)
	play_requested.emit(_card_data)


func _target_hint_text(target_type: int) -> String:
	match target_type:
		CardEnums.TargetType.NONE:
			return "无需选择目标，点击即可打出。"
		CardEnums.TargetType.SINGLE:
			return "需要选择一个合法目标。"
		CardEnums.TargetType.MULTI:
			return "需要选择多个合法目标。"
		CardEnums.TargetType.AREA:
			return "需要选择一个范围。"
		CardEnums.TargetType.SELF:
			return "目标固定为自己。"
		CardEnums.TargetType.ALL:
			return "会影响所有合法目标。"
		_:
			return "目标类型未定义。"
