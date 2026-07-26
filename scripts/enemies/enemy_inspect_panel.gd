extends PanelContainer
class_name EnemyInspectPanel

signal close_requested

var bound_unit: BattleUnitState

@onready var portrait_rect: TextureRect = %PortraitRect
@onready var name_label: Label = %NameLabel
@onready var health_label: Label = %HealthLabel
@onready var trait_label: Label = %TraitLabel
@onready var intent_headline: Label = %IntentHeadline
@onready var intent_summary: Label = %IntentSummary
@onready var intent_steps: VBoxContainer = %IntentSteps
@onready var recipe_label: Label = %RecipeLabel
@onready var zone_label: Label = %ZoneLabel
@onready var seen_cards: VBoxContainer = %SeenCards
@onready var close_button: Button = %CloseButton


func _ready() -> void:
	close_button.pressed.connect(func() -> void: close_requested.emit())
	visible = false


func bind_unit(unit: BattleUnitState) -> void:
	bound_unit = unit
	visible = unit != null and unit.is_alive() and unit.enemy_state != null and unit.enemy_state.enemy_data != null
	if not visible:
		return
	var state := unit.enemy_state
	var data := state.enemy_data
	portrait_rect.texture = data.portrait
	name_label.text = data.enemy_name
	health_label.text = "生命 %d/%d  护甲 %d  敏捷 %d" % [unit.get_current_health(), unit.get_max_health(), unit.get_armor_stacks(), unit.get_agility()]
	trait_label.text = data.trait_summary
	var plan := state.intent_plan
	intent_headline.text = plan.get_headline() if plan != null else "观望"
	intent_summary.text = plan.get_summary() if plan != null else "无伤害预告"
	_refresh_steps(plan)
	var rule := data.deck_rule
	var recipe := rule.get_recipe_summary() if rule != null else ""
	recipe_label.text = "配方  %s" % (recipe if not recipe.is_empty() else "固定牌组")
	zone_label.text = "牌库 %d  手牌 %d  弃牌 %d  显化 %d  放逐 %d" % [unit.draw_pile.size(), unit.hand.size(), unit.discard_pile.size(), unit.enchant_zone.size(), unit.exiled_pile.size()]
	_refresh_seen_cards(state.seen_card_names)


func clear() -> void:
	bound_unit = null
	visible = false


func _refresh_steps(plan: EnemyIntentPlan) -> void:
	_clear_children(intent_steps)
	if plan == null or plan.steps.is_empty():
		_add_text_row(intent_steps, "观望", "本轮没有已锁定行动")
		if plan != null:
			_add_manifest_rows(plan)
		return
	for index in range(plan.steps.size()):
		var step: Dictionary = plan.steps[index]
		var detail := "%d AP" % int(step.get("ap", 0))
		var attack := int(step.get("attack", 0))
		var defense := int(step.get("defense", 0))
		if attack > 0:
			detail += "  预计攻 %d" % attack
		if defense > 0:
			detail += "  预计防 %d" % defense
		_add_text_row(intent_steps, "%d. %s" % [index + 1, str(step.get("label", "行动"))], detail)
	_add_manifest_rows(plan)


func _add_manifest_rows(plan: EnemyIntentPlan) -> void:
	if plan.expected_decay_life > 0:
		_add_text_row(intent_steps, "畸变衰退", "预计失去 %d 点生命" % plan.expected_decay_life)
	if not plan.planned_manifest_fields.is_empty():
		_add_text_row(intent_steps, "计划显化", "、".join(plan.planned_manifest_fields))


func _refresh_seen_cards(names: PackedStringArray) -> void:
	_clear_children(seen_cards)
	if names.is_empty():
		var empty := Label.new()
		empty.text = "尚未公开卡牌"
		empty.modulate = Color(0.72, 0.72, 0.68)
		seen_cards.add_child(empty)
		return
	for card_name in names:
		var label := Label.new()
		label.text = "• %s" % card_name
		seen_cards.add_child(label)


func _add_text_row(parent: VBoxContainer, title: String, detail: String) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 1)
	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 14)
	var detail_label := Label.new()
	detail_label.text = detail
	detail_label.modulate = Color(0.74, 0.78, 0.74)
	detail_label.add_theme_font_size_override("font_size", 12)
	row.add_child(title_label)
	row.add_child(detail_label)
	parent.add_child(row)


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
