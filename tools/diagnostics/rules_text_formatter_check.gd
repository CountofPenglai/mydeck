extends Node

var _exit_code := 0


class FormatterUser:
	extends RefCounted

	func get_attack_range(_equipment_slot: String = "") -> int:
		return 5

	func get_card_ap_cost(_card: CardData, _context: Dictionary = {}) -> int:
		return 0


func _ready() -> void:
	_test_card_text()
	_test_equipment_text()
	_test_enemy_text()
	_test_curse_text()
	_test_dynamic_enemy_text()
	_test_resource_corpus()
	if _exit_code == 0:
		print("RULES_TEXT_FORMATTER_CHECK: PASS")
	get_tree().quit(_exit_code)


func _test_card_text() -> void:
	var card := load("res://resources/cards/relentless.tres") as CardData
	var card_text := RulesTextFormatter.format_card(card)
	_expect(card_text.contains("史诗 | 战士 | 技能 | 1 AP"), "card metadata")
	_expect(card_text.contains("余势："), "momentum prose")
	_expect(not card_text.contains("打出："), "ordinary effect has no play prefix")
	var contextual_card := CardData.new()
	contextual_card.card_name = "上下文测试"
	contextual_card.card_type = CardEnums.CardType.ATTACK
	contextual_card.target_type = CardEnums.TargetType.SINGLE
	contextual_card.ap_cost = 3
	contextual_card.range_modifier = 2
	contextual_card.is_choice_one_card = true
	contextual_card.description = "造成1点伤害。"
	var contextual_text := RulesTextFormatter.format_card(contextual_card, {
		"user": FormatterUser.new(),
		"effective_ap_cost": 1,
	})
	_expect(contextual_text.contains("1 AP"), "card uses effective AP context")
	_expect(contextual_text.contains("范围 7"), "card uses effective runtime range")
	_expect(contextual_text.contains("选择一项"), "choice-one structured tag")


func _test_equipment_text() -> void:
	var equipment := load("res://resources/items/ranger_dagger_crossbow.tres") as EquipmentData
	var equipment_text := RulesTextFormatter.format_equipment(equipment)
	_expect(equipment_text.contains("标签：单手"), "paired select-one weapon keeps one-hand rule tag")
	_expect(equipment_text.contains("近战组件"), "paired melee component")
	_expect(equipment_text.contains("远程组件"), "paired ranged component")
	_expect(equipment_text.count("乌狼猎刀") == 1, "paired primary component appears once")
	_expect(equipment_text.count("寻迹短弓") == 1, "paired secondary component appears once")
	_expect(equipment_text.contains(equipment.paired_component.description), "paired component rules body")
	var shield := EquipmentData.new()
	shield.item_name = "诊断护甲"
	shield.equip_slot = EquipmentData.EquipSlot.ARMOR
	shield.damage_reduction = 1
	var shield_text := RulesTextFormatter.format_equipment(shield)
	_expect(shield_text.contains("伤害减免 +1"), "armor numeric bonus")
	_expect(not shield_text.contains("单手") and not shield_text.contains("副手"), "non-weapon hides weapon category")
	var druid_weapon := load("res://resources/items/druid_brute_bear.tres") as EquipmentData
	var druid_text := RulesTextFormatter.format_equipment(druid_weapon)
	_expect(druid_text.contains("正位效果") and druid_text.contains("逆位效果"), "dual equipment renders both effects")
	_expect(druid_text.contains("标签：单手"), "druid weapon keeps its hand rule tag")
	_expect(not druid_text.contains("druid_weapon") and not druid_text.contains("德鲁伊武器") and not druid_text.contains("T0"), "druid and tier metadata are not rendered as tags")
	var sword_shield := load("res://resources/items/ceremonial_sword_shield.tres") as EquipmentData
	var sword_shield_text := RulesTextFormatter.format_equipment(sword_shield)
	_expect(sword_shield_text.contains("标签：单手、盾牌"), "sword-shield keeps hand and shield rule tags")
	_expect(not sword_shield_text.contains("T0"), "equipment tier is not rendered as a tag")
	var dual_wield := load("res://resources/items/clockwork_gear_pair.tres") as EquipmentData
	var dual_wield_text := RulesTextFormatter.format_equipment(dual_wield)
	_expect(dual_wield_text.contains("标签：单手、双持"), "dual-wield keeps hand and dual-wield rule tags")
	_expect(not dual_wield_text.contains("T2"), "dual-wield tier is not rendered as a tag")


func _test_enemy_text() -> void:
	var enemy := ChapterOneEnemyCatalog.create_enemy(&"abyss_scale", 1)
	var enemy_text := RulesTextFormatter.format_enemy_data(enemy.enemy_data)
	_expect(enemy_text.contains("首领"), "enemy rank")
	_expect(enemy_text.contains("力量"), "enemy stats")
	_expect(enemy_text.contains("牌组配方"), "enemy deck recipe")
	var object_state := BattleObjectState.create(1, BattleObjectDefinition.Kind.EXPLOSIVE_BARREL, Vector2i.ZERO)
	var object_text := RulesTextFormatter.format_battle_object(object_state)
	_expect(object_text.contains("生命 4/4"), "battle object health")
	_expect(object_text.contains("阻挡移动"), "battle object blocking")
	_expect(object_text.contains("距离 1"), "battle object rules body")


func _test_curse_text() -> void:
	var definition := load("res://resources/curses/blood.tres") as CurseDefinition
	var curse := CurseInstance.new()
	curse.definition = definition
	curse.state = CurseInstance.State.REPORT
	curse.depth = 2
	curse.maturity = 1
	var curse_text := RulesTextFormatter.format_curse(curse)
	_expect(curse_text.contains("报") and curse_text.contains("D=2"), "curse metadata")
	_expect(curse_text.contains(definition.report_description), "curse current-state rules body")
	curse.sealed = true
	var sealed_text := RulesTextFormatter.format_curse(curse)
	_expect(sealed_text.contains("效果停用") and sealed_text.contains("负荷为 0"), "sealed curse state")


func _test_dynamic_enemy_text() -> void:
	var chapter_one_ids := [
		&"hungry_fish", &"harpoon_fish", &"bandit_blade", &"bandit_bow", &"fish_priest",
		&"unclean_one", &"fish_champion", &"kraken", &"high_priest", &"abyss_scale",
	]
	var chapter_two_ids := [
		&"gray_shield_guard", &"holy_spearman", &"fortress_crossbow", &"field_priest",
		&"punishment_knight", &"standard_bearer", &"holy_bastion_commander", &"creation_shard",
		&"blood_construct", &"corrupt_heart_veil", &"gray_bastion_paladin", &"triumph_statue",
		&"military_god_remains", &"flesh_spawn",
	]
	for enemy_id in chapter_one_ids:
		_check_generated_enemy(ChapterOneEnemyCatalog.create_enemy(enemy_id, 1701), "chapter_one:%s" % enemy_id)
	for enemy_id in chapter_two_ids:
		_check_generated_enemy(ChapterTwoEnemyCatalog.create_enemy(enemy_id, 2701), "chapter_two:%s" % enemy_id)
	_check_rules_body("chapter_two:gospel", ChapterTwoEnemyCatalog.create_gospel_card().description, "description")


func _check_generated_enemy(enemy: EnemyState, label: String) -> void:
	_expect(enemy != null and enemy.enemy_data != null, "%s can be created" % label)
	if enemy == null or enemy.enemy_data == null:
		return
	var trait_text := enemy.enemy_data.trait_summary.strip_edges()
	if not trait_text.is_empty():
		_check_rules_body(label, trait_text, "trait_summary")
	for stack in enemy.deck:
		if stack != null and stack.card_data != null:
			_check_rules_body("%s:%s" % [label, stack.card_data.card_name], stack.card_data.description, "description")


func _test_resource_corpus() -> void:
	for root in ["res://resources/cards", "res://resources/items", "res://resources/curses"]:
		for path in _collect_resource_paths(root):
			var resource := load(path)
			_expect(resource != null, "%s loads successfully" % path)
			if resource == null:
				continue
			_expect(_is_expected_resource_for_root(root, resource), "%s has an expected resource type" % path)
			if resource is CardData:
				var card := resource as CardData
				_check_rules_body(path, card.description, "description")
				_check_special_condition_sentence(path, card, CardEnums.CardPlayMode.COMBO, "连击")
				_check_special_condition_sentence(path, card, CardEnums.CardPlayMode.MOMENTUM, "余势")
				if card.is_druid_dual_card and card.allow_inverted_play:
					_check_rules_body(path, card.inverted_description, "inverted_description")
			elif resource is ItemData:
				_check_rules_body(path, (resource as ItemData).description, "description")
				if resource is EquipmentData and (resource as EquipmentData).is_weapon():
					_check_weapon_rule_tags(path, resource as EquipmentData)
			elif resource is CurseDefinition:
				var curse := resource as CurseDefinition
				_check_rules_body(path, curse.industry_description, "industry_description")
				_check_rules_body(path, curse.report_description, "report_description")
				_check_rules_body(path, curse.fruit_description, "fruit_description")


func _is_expected_resource_for_root(root: String, resource: Resource) -> bool:
	if root.ends_with("/cards"):
		return resource is CardData or resource is CardEffect or resource is CardPlayCondition or resource is CardStack
	if root.ends_with("/items"):
		return resource is ItemData or resource is EquipmentEffect or resource is InventoryStack
	if root.ends_with("/curses"):
		return resource is CurseDefinition
	return false


func _check_weapon_rule_tags(path: String, equipment: EquipmentData) -> void:
	var allowed_display_tags := PackedStringArray(["单手", "双手", "双持", "盾牌"])
	for tag in equipment.get_display_tags():
		_expect(allowed_display_tags.has(tag), "%s renders non-rule weapon tag '%s'" % [path, tag])
	var faces: Array[EquipmentData] = [equipment]
	if equipment.back_face != null:
		faces.append(equipment.back_face)
	for face in faces:
		for component in face.get_active_components():
			for tag in component.subcategories:
				_expect(tag in ["双持", "盾牌"], "%s stores non-rule weapon tag '%s'" % [path, tag])


func _check_rules_body(path: String, body: String, field_name: String) -> void:
	var text := body.strip_edges()
	_expect(not text.is_empty(), "%s has empty %s" % [path, field_name])
	if text.is_empty():
		return
	_expect(not text.contains("威力"), "%s uses legacy power term in %s" % [path, field_name])
	_expect(not text.contains("打出："), "%s uses ordinary play prefix in %s" % [path, field_name])
	_expect(text.ends_with("。") or text.ends_with("！") or text.ends_with("？"),
		"%s has incomplete ending in %s" % [path, field_name])


func _check_special_condition_sentence(path: String, card: CardData, play_mode: int, label: String) -> void:
	var enabled := card.has_combo if play_mode == CardEnums.CardPlayMode.COMBO else card.has_momentum
	if not enabled:
		return
	var conditions := card.get_special_conditions(play_mode)
	if conditions.is_empty():
		var prefix_index := card.description.find("%s：" % label)
		var sentence_end := card.description.find("。", prefix_index + label.length() + 1) if prefix_index >= 0 else -1
		_expect(prefix_index >= 0 and sentence_end > prefix_index,
			"%s requires an explicit %s condition sentence" % [path, label])
		return
	var expected := "%s：%s。" % [label, card.get_special_condition_text(play_mode)]
	_expect(card.description.contains(expected), "%s requires condition sentence '%s'" % [path, expected])


func _collect_resource_paths(root: String) -> PackedStringArray:
	var result := PackedStringArray()
	var directory := DirAccess.open(root)
	if directory == null:
		return result
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if directory.current_is_dir():
			result.append_array(_collect_resource_paths(root.path_join(entry)))
		elif entry.ends_with(".tres"):
			result.append(root.path_join(entry))
		entry = directory.get_next()
	directory.list_dir_end()
	return result


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_exit_code = 1
	push_error("RULES_TEXT_FORMATTER_CHECK: %s" % label)
