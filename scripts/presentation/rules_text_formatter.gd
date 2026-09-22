extends RefCounted
class_name RulesTextFormatter


static func format_card(card: CardData, context: Dictionary = {}) -> String:
	if card == null:
		return ""
	if card.is_druid_dual_card and not context.has("druid_orientation") and context.get("user") == null:
		return _format_dual_card(card)
	return _format_card_orientation(card, context)


static func format_card_summary(card: CardData, context: Dictionary = {}) -> String:
	if card == null:
		return ""
	return _card_header(card, context)


static func format_equipment(equipment: EquipmentData) -> String:
	if equipment == null:
		return ""
	var header := PackedStringArray([equipment.get_rarity_label(), equipment.get_equip_slot_label()])
	var lines := PackedStringArray([" | ".join(header)])
	var visited := {}
	_append_equipment_face(lines, equipment, "正位" if equipment.back_face != null else "", visited)
	if equipment.back_face != null:
		_append_equipment_face(lines, equipment.back_face, "逆位", visited)
	var bonuses := PackedStringArray()
	if equipment.damage_bonus != 0:
		bonuses.append("伤害加值 %+d" % equipment.damage_bonus)
	if equipment.damage_reduction != 0:
		bonuses.append("伤害减免 %+d" % equipment.damage_reduction)
	if equipment.curse_load_limit_bonus != 0:
		bonuses.append("负荷上限 %+d" % equipment.curse_load_limit_bonus)
	if not bonuses.is_empty():
		lines.append("固定加值：%s" % " | ".join(bonuses))
	var display_tags := equipment.get_display_tags()
	if not display_tags.is_empty():
		lines.append("标签：%s" % "、".join(display_tags))
	return "\n".join(lines)


static func format_equipment_summary(equipment: EquipmentData) -> String:
	if equipment == null:
		return ""
	var parts := PackedStringArray([equipment.get_rarity_label(), equipment.get_equip_slot_label()])
	if equipment.is_weapon():
		parts.append(equipment.get_equip_category_label())
		parts.append("基础伤害 %d" % equipment.base_damage)
		parts.append("范围 %d" % equipment.attack_range)
		if equipment.paired_component != null:
			parts.append("副组件 %d伤/%d范围" % [
				equipment.paired_component.base_damage,
				equipment.paired_component.attack_range,
			])
	elif equipment.damage_reduction != 0:
		parts.append("伤害减免 %+d" % equipment.damage_reduction)
	return " | ".join(parts)


static func format_item(item: ItemData) -> String:
	if item == null:
		return ""
	if item is EquipmentData:
		return format_equipment(item as EquipmentData)
	return item.description.strip_edges()


static func format_curse(curse: CurseInstance) -> String:
	if curse == null or curse.definition == null:
		return ""
	var definition := curse.definition
	var lines := PackedStringArray(["%s | D=%d" % [curse.get_summary(), curse.depth]])
	if not definition.hex_keywords.is_empty():
		lines.append("邪术关键词：%s" % "、".join(definition.hex_keywords))
	if curse.sealed:
		lines.append("封印中：本牌效果停用，负荷为 0。")
	var body := definition.get_description_for_state(curse.state).strip_edges()
	if not body.is_empty():
		lines.append("")
		lines.append(body)
	return "\n".join(lines)


static func format_enemy_data(data: EnemyData) -> String:
	if data == null:
		return ""
	var lines := PackedStringArray([
		"%s | 生命 %d | 力量 %d | 敏捷 %d | 智力 %d" % [
			data.get_rank_label(),
			data.base_max_health + data.base_strength * 3,
			data.base_strength,
			data.base_agility,
			data.base_intelligence,
		],
	])
	_append_enemy_weapon(lines, "武器", data.weapon_equipment)
	_append_enemy_weapon(lines, "备用武器", data.reserve_weapon_equipment)
	if not data.permanent_distortion_fields.is_empty():
		var fields := PackedStringArray()
		for field_id in data.permanent_distortion_fields:
			fields.append(str(CardData.MUTATION_FIELD_LABELS.get(field_id, field_id)))
		lines.append("永久畸变：%s" % "、".join(fields))
	_append_enemy_deck_summary(lines, data.deck_rule)
	if not data.trait_summary.strip_edges().is_empty():
		lines.append("")
		lines.append(data.trait_summary.strip_edges())
	return "\n".join(lines)


static func format_enemy_unit(unit: BattleUnitState) -> String:
	if unit == null or unit.enemy_state == null or unit.enemy_state.enemy_data == null:
		return ""
	var data := unit.enemy_state.enemy_data
	var lines := PackedStringArray([
		"%s | 生命 %d/%d | 力量 %d | 敏捷 %d | 智力 %d" % [
			data.get_rank_label(),
			unit.get_current_health(),
			unit.get_max_health(),
			unit.get_strength(),
			unit.get_agility(),
			unit.get_intelligence(),
		],
	])
	_append_enemy_weapon(lines, "当前武器", unit.get_active_weapon_equipment())
	var reserve := data.reserve_weapon_equipment
	if unit.get_active_weapon_equipment() == reserve:
		reserve = data.weapon_equipment
	_append_enemy_weapon(lines, "备用武器", reserve)
	if not data.permanent_distortion_fields.is_empty():
		var fields := PackedStringArray()
		for field_id in data.permanent_distortion_fields:
			fields.append(str(CardData.MUTATION_FIELD_LABELS.get(field_id, field_id)))
		lines.append("永久畸变：%s" % "、".join(fields))
	_append_enemy_deck_summary(lines, data.deck_rule)
	if not data.trait_summary.strip_edges().is_empty():
		lines.append("")
		lines.append(data.trait_summary.strip_edges())
	return "\n".join(lines)


static func format_battle_object(object_state: BattleObjectState) -> String:
	if object_state == null or object_state.definition == null:
		return ""
	var definition := object_state.definition
	var lines := PackedStringArray([
		"生命 %d/%d | %s | %s" % [
			object_state.current_health,
			object_state.get_max_health(),
			"可破坏" if definition.destructible else "不可破坏",
			"可指定" if definition.targetable else "不可指定",
		],
	])
	var blocking := PackedStringArray()
	if definition.blocks_movement:
		blocking.append("阻挡移动")
	if definition.blocks_line_of_sight:
		blocking.append("阻挡视线")
	if blocking.is_empty():
		blocking.append("不阻挡移动或视线")
	lines.append("阻挡：%s" % "、".join(blocking))
	if definition.persistent_element != BattleSurfaceState.Element.NONE:
		lines.append("永久元素源：%s" % BattleSurfaceState.label(definition.persistent_element))
	if not definition.description.strip_edges().is_empty():
		lines.append("")
		lines.append(definition.description.strip_edges())
	return "\n".join(lines)


static func _format_dual_card(card: CardData) -> String:
	var upright := {"druid_orientation": CardEnums.DruidOrientation.UPRIGHT}
	var inverted := {"druid_orientation": CardEnums.DruidOrientation.INVERTED}
	return "正位\n%s\n\n逆位\n%s" % [
		_format_card_orientation(card, upright),
		_format_card_orientation(card, inverted),
	]


static func _format_card_orientation(card: CardData, context: Dictionary) -> String:
	var lines := PackedStringArray([_card_header(card, context)])
	var tags := _card_tag_line(card)
	if not tags.is_empty():
		lines.append(tags)
	var body := card.get_description_for_context(context).strip_edges()
	if not body.is_empty():
		lines.append("")
		lines.append(body)
	return "\n".join(lines)


static func _card_header(card: CardData, context: Dictionary) -> String:
	var target_type := card.get_target_type_for_mode(CardEnums.CardPlayMode.NORMAL, context)
	var ap_cost := card.get_ap_cost_for_context(context)
	if context.has("effective_ap_cost"):
		ap_cost = int(context["effective_ap_cost"])
	else:
		var user = context.get("user")
		if user != null and user.has_method("get_card_ap_cost"):
			ap_cost = user.get_card_ap_cost(card, context)
	return " | ".join(PackedStringArray([
		card.get_rarity_label(),
		card.get_class_label(),
		card.get_card_type_label(),
		"%d AP" % ap_cost,
		CardEnums.target_label(target_type),
		_card_range_label(card, context, target_type),
		"%s类型" % card.get_damage_type_label(),
	]))


static func _card_range_label(card: CardData, context: Dictionary, target_type: int) -> String:
	if target_type in [CardEnums.TargetType.NONE, CardEnums.TargetType.SELF]:
		return "无需范围"
	var user = context.get("user")
	if user != null:
		return "范围 %d" % card.get_effective_range(user, str(context.get("equipment_slot", "")))
	var inverted := int(context.get("druid_orientation", CardEnums.DruidOrientation.UPRIGHT)) == CardEnums.DruidOrientation.INVERTED
	if inverted and card.inverted_override_range:
		return "固定范围 %d" % card.inverted_card_range
	if not inverted and card.override_range:
		return "固定范围 %d" % card.card_range
	var modifier := card.inverted_range_modifier if inverted else card.range_modifier
	if modifier == 0:
		return "武器范围"
	return "武器范围 %s%d" % ["+" if modifier > 0 else "", modifier]


static func _card_tag_line(card: CardData) -> String:
	var tags := PackedStringArray()
	if (card.card_tags & CardEnums.CardTag.PHYSICAL) != 0:
		tags.append("物理")
	if (card.card_tags & CardEnums.CardTag.MAGICAL) != 0:
		tags.append("魔法")
	if (card.element_tags & CardEnums.ElementTag.FIRE) != 0:
		tags.append("火")
	if (card.element_tags & CardEnums.ElementTag.WATER) != 0:
		tags.append("水")
	if (card.element_tags & CardEnums.ElementTag.EARTH) != 0:
		tags.append("土")
	if (card.element_tags & CardEnums.ElementTag.AIR) != 0:
		tags.append("气")
	if card.has_combo:
		tags.append("连击")
	if card.has_momentum:
		tags.append("余势")
	if card.is_choice_one_card:
		tags.append("选择一项")
	var twin_face := card.get_twin_spell_face()
	if twin_face >= 0:
		tags.append("双生法术（%s）" % ("正位" if twin_face == CardEnums.DruidOrientation.UPRIGHT else "逆位"))
		tags.append("自由入区：免费；检索至多1张相反牌面（查阅牌库才洗牌）")
	if card.upright_play_ignores_form:
		tags.append("正位不受形态影响")
	if not card.mutation_fields.is_empty():
		tags.append(card.get_mutation_label())
	return "标签：%s" % "、".join(tags) if not tags.is_empty() else ""


static func _append_equipment_face(lines: PackedStringArray, face: EquipmentData, face_label: String, visited: Dictionary) -> void:
	if face == null or visited.has(face.get_instance_id()):
		return
	visited[face.get_instance_id()] = true
	if face.paired_component != null:
		var face_prefix := "%s·" % face_label if not face_label.is_empty() else ""
		var primary_label := "%s%s组件" % [face_prefix, face.get_range_type_label()]
		var paired_label := "%s%s组件" % [face_prefix, face.paired_component.get_range_type_label()]
		lines.append("%s：%s | 基础伤害 %d | 范围 %d | %s类型" % [
			primary_label, _primary_component_name(face), face.base_damage, face.attack_range, face.get_damage_type_label(),
		])
		if not face.description.strip_edges().is_empty():
			lines.append("%s效果：%s" % [primary_label, face.description.strip_edges()])
		lines.append("%s：%s | 基础伤害 %d | 范围 %d | %s类型" % [
			paired_label,
			face.paired_component.item_name,
			face.paired_component.base_damage,
			face.paired_component.attack_range,
			face.paired_component.get_damage_type_label(),
		])
		if not face.paired_component.description.strip_edges().is_empty():
			lines.append("%s效果：%s" % [paired_label, face.paired_component.description.strip_edges()])
	elif face.is_weapon():
		var prefix := "%s：" % face_label if not face_label.is_empty() else ""
		lines.append("%s%s | 基础伤害 %d | 范围 %d | %s类型 | %s" % [
			prefix,
			face.item_name,
			face.base_damage,
			face.attack_range,
			face.get_damage_type_label(),
			face.get_range_type_label(),
		])
		if not face.description.strip_edges().is_empty():
			lines.append("%s%s" % ["%s效果：" % face_label if not face_label.is_empty() else "", face.description.strip_edges()])
	elif not face.description.strip_edges().is_empty():
		lines.append("%s%s" % ["%s效果：" % face_label if not face_label.is_empty() else "", face.description.strip_edges()])


static func _primary_component_name(face: EquipmentData) -> String:
	if face == null or face.paired_component == null:
		return face.item_name if face != null else ""
	var separator_index := face.item_name.find(" / ")
	return face.item_name.left(separator_index) if separator_index >= 0 else face.item_name


static func _append_enemy_weapon(lines: PackedStringArray, label: String, weapon: EquipmentData) -> void:
	if weapon == null:
		return
	lines.append("%s：%s，基础伤害 %d，范围 %d，%s类型，%s" % [
		label,
		weapon.item_name,
		weapon.base_damage,
		weapon.attack_range,
		weapon.get_damage_type_label(),
		weapon.get_range_type_label(),
	])


static func _append_enemy_deck_summary(lines: PackedStringArray, deck_rule: EnemyDeckRule) -> void:
	if deck_rule == null:
		return
	var parts := PackedStringArray()
	var recipe := deck_rule.get_recipe_summary()
	if not recipe.is_empty():
		parts.append(recipe)
	var fixed_count := deck_rule.get_fixed_card_count()
	if fixed_count > 0:
		parts.append("固定牌×%d" % fixed_count)
	if not parts.is_empty():
		lines.append("牌组配方：%s" % "、".join(parts))
