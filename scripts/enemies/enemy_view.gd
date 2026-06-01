extends Control
class_name EnemyView

var _enemy_state: EnemyState

@export var enemy_state: EnemyState:
	get:
		return _enemy_state
	set(value):
		_enemy_state = value
		if is_inside_tree():
			_refresh()

@onready var portrait_rect: TextureRect = %PortraitRect
@onready var battle_rect: TextureRect = %BattleRect
@onready var name_label: Label = %NameLabel
@onready var rank_label: Label = %RankLabel
@onready var health_label: Label = %HealthLabel
@onready var attack_label: Label = %AttackLabel
@onready var speed_label: Label = %SpeedLabel
@onready var behavior_label: Label = %BehaviorLabel
@onready var rule_summary_label: Label = %RuleSummaryLabel
@onready var deck_summary_label: Label = %DeckSummaryLabel
@onready var deck_list: VBoxContainer = %DeckList

func _ready() -> void:
	_refresh()


func setup(state: EnemyState) -> void:
	_enemy_state = state
	_refresh()


func _refresh() -> void:
	if not is_inside_tree():
		return

	if _enemy_state == null or _enemy_state.enemy_data == null:
		_show_empty_state()
		return

	_enemy_state.ensure_initialized()

	var data := _enemy_state.enemy_data
	name_label.text = _enemy_state.get_enemy_name()
	rank_label.text = "类别：" + _enemy_state.get_rank_label()
	health_label.text = "生命：%d/%d" % [_enemy_state.current_health, _enemy_state.get_max_health()]
	attack_label.text = "攻击：%d" % _enemy_state.get_attack()
	speed_label.text = "速度：%d" % _enemy_state.get_speed()
	behavior_label.text = "战斗逻辑：" + _enemy_state.get_behavior_label()
	portrait_rect.texture = data.portrait
	battle_rect.texture = data.battle_sprite
	_refresh_deck_summary(data)
	_refresh_deck_list()


func _show_empty_state() -> void:
	name_label.text = "未绑定敌人"
	rank_label.text = "类别：-"
	health_label.text = "生命：-"
	attack_label.text = "攻击：-"
	speed_label.text = "速度：-"
	behavior_label.text = "战斗逻辑：-"
	rule_summary_label.text = "卡组规则：-"
	deck_summary_label.text = "本场卡组：-"
	portrait_rect.texture = null
	battle_rect.texture = null
	_clear_deck_list()


func _refresh_deck_summary(data: EnemyData) -> void:
	if data.deck_rule == null:
		rule_summary_label.text = "卡组规则：未配置"
	else:
		rule_summary_label.text = "卡组规则：固定 %d 张，随机池 %d 张，抽取 %d 张" % [
			data.deck_rule.get_fixed_card_count(),
			data.deck_rule.get_random_pool_card_count(),
			data.deck_rule.random_pick_count,
		]

	deck_summary_label.text = "本场卡组：%d 张 / %d 种" % [
		_enemy_state.get_deck_card_count(),
		_enemy_state.deck.size(),
	]


func _refresh_deck_list() -> void:
	_clear_deck_list()

	for stack in _enemy_state.deck:
		if stack == null:
			continue

		var label := Label.new()
		label.text = stack.get_display_name()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		deck_list.add_child(label)

	if deck_list.get_child_count() == 0:
		var empty_label := Label.new()
		empty_label.text = "本场卡组为空"
		deck_list.add_child(empty_label)


func _clear_deck_list() -> void:
	for child in deck_list.get_children():
		deck_list.remove_child(child)
		child.queue_free()
