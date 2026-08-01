extends PanelContainer
class_name BattleDetailPanel

signal lock_changed(locked: bool)

var _preview_model: Dictionary = {}
var _locked_model: Dictionary = {}

@onready var art_rect: TextureRect = %DetailArt
@onready var title_label: Label = %DetailTitle
@onready var subtitle_label: Label = %DetailSubtitle
@onready var body_label: RichTextLabel = %DetailBody
@onready var close_button: Button = %DetailCloseButton


func _ready() -> void:
	close_button.pressed.connect(clear_lock)
	visible = false


func preview_card(card: CardData, context: Dictionary = {}) -> void:
	if card == null:
		clear_preview()
		return
	_show_preview({
		"kind": "card",
		"identity": card,
		"title": card.get_display_name_for_context(context),
		"subtitle": card.get_druid_orientation_label(context) if card.is_druid_dual_card else "卡牌",
		"art": card.artwork,
		"body": RulesTextFormatter.format_card(card, context),
	})


func preview_equipment(equipment: EquipmentData, unit: BattleUnitState = null) -> void:
	if equipment == null:
		clear_preview()
		return
	var body := RulesTextFormatter.format_equipment(equipment)
	if unit != null:
		var runtime := unit.get_equipment_runtime_summary({"unit": unit})
		if not runtime.is_empty():
			body += "\n\n战斗状态：" + runtime
	_show_preview({
		"kind": "equipment",
		"identity": equipment,
		"title": equipment.item_name,
		"subtitle": "%s · %s" % [equipment.get_rarity_label(), equipment.get_range_type_label()],
		"art": equipment.icon,
		"body": body,
	})


func preview_unit(unit: BattleUnitState) -> void:
	if unit == null:
		clear_preview()
		return
	var body := "生命 %d/%d\n护甲 %d · AP %d\n力量 %d · 敏捷 %d · 智力 %d" % [
		unit.get_current_health(), unit.get_max_health(), unit.get_armor_stacks(), unit.current_ap,
		unit.get_strength(), unit.get_agility(), unit.get_intelligence(),
	]
	var subtitle := "友方单位" if unit.faction == BattleUnitState.Faction.PLAYER else "敌方单位"
	if unit.enemy_state != null and unit.enemy_state.enemy_data != null:
		var data := unit.enemy_state.enemy_data
		subtitle = data.get_rank_label()
		body = RulesTextFormatter.format_enemy_unit(unit)
		body += "\n护甲 %d | AP %d" % [unit.get_armor_stacks(), unit.current_ap]
		body += _build_enemy_intent(unit)
		body += "\n\n牌区\n牌库 %d · 手牌 %d · 弃牌 %d · 显化 %d · 放逐 %d" % [
			unit.draw_pile.size(), unit.hand.size(), unit.discard_pile.size(), unit.enchant_zone.size(), unit.exiled_pile.size(),
		]
	var shared_armor := unit.get_shared_armor_stacks()
	if shared_armor > 0:
		body += "\n共有护甲 %d（全队共享）" % shared_armor
	_show_preview({
		"kind": "unit",
		"identity": unit,
		"title": unit.get_display_name(),
		"subtitle": subtitle,
		"art": _get_unit_portrait(unit),
		"body": body,
	})


func preview_object(object_state: BattleObjectState) -> void:
	if object_state == null:
		clear_preview()
		return
	_show_preview({
		"kind": "object",
		"identity": object_state,
		"title": object_state.get_display_name(),
		"subtitle": "战场对象",
		"art": null,
		"body": RulesTextFormatter.format_battle_object(object_state),
	})


func preview_terrain(cell: Vector2i, detail_text: String) -> void:
	_show_preview({
		"kind": "terrain",
		"identity": cell,
		"title": "地形 (%d, %d)" % [cell.x, cell.y],
		"subtitle": "地形 · 地面 · 空气 · 元素",
		"art": null,
		"body": detail_text,
	})


func lock_current() -> void:
	if _preview_model.is_empty():
		return
	_locked_model = _preview_model.duplicate()
	lock_changed.emit(true)
	_render(_locked_model)


func clear_preview() -> void:
	_preview_model.clear()
	if _locked_model.is_empty():
		visible = false
	else:
		_render(_locked_model)


func clear_lock() -> void:
	_locked_model.clear()
	lock_changed.emit(false)
	if _preview_model.is_empty():
		visible = false
	else:
		_render(_preview_model)


func is_locked() -> bool:
	return not _locked_model.is_empty()


func get_display_title() -> String:
	return title_label.text


func _show_preview(model: Dictionary) -> void:
	_preview_model = model
	_render(model)


func _render(model: Dictionary) -> void:
	if model.is_empty():
		visible = false
		return
	visible = true
	title_label.text = str(model.get("title", "详情"))
	subtitle_label.text = str(model.get("subtitle", ""))
	art_rect.texture = model.get("art") as Texture2D
	art_rect.visible = art_rect.texture != null
	body_label.text = str(model.get("body", ""))


func _build_enemy_intent(unit: BattleUnitState) -> String:
	var plan := unit.enemy_state.intent_plan
	if plan == null:
		return "\n\n意图\n观望"
	var lines := PackedStringArray([
		"",
		"意图",
		"主要：%s" % plan.get_headline(),
		"备用：%s" % EnemyIntentCategory.get_label(plan.fallback_intent),
	])
	if not plan.is_finished():
		var current_category := plan.get_current_category()
		lines.append("当前：%s" % EnemyIntentCategory.get_label(current_category))
		lines.append(EnemyIntentCategory.get_description(current_category))
	if not plan.forced_steps.is_empty():
		var special_labels := PackedStringArray()
		for step in plan.forced_steps:
			special_labels.append(str(step.get("label", "特殊行动")))
		lines.append("特殊：%s" % " → ".join(special_labels))
	if not plan.planned_manifest_fields.is_empty():
		lines.append("显化：%s" % "、".join(plan.planned_manifest_fields))
	if plan.expected_decay_life > 0:
		lines.append("预计衰退：失去%d生命" % plan.expected_decay_life)
	return "\n".join(lines)


func _get_unit_portrait(unit: BattleUnitState) -> Texture2D:
	if unit.character_state != null and unit.character_state.character_data != null:
		return unit.character_state.character_data.portrait
	if unit.enemy_state != null and unit.enemy_state.enemy_data != null:
		return unit.enemy_state.enemy_data.portrait
	return null
