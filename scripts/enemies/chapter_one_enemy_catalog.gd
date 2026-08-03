extends RefCounted
class_name ChapterOneEnemyCatalog

const BASIC_CARDS := [
	"res://resources/cards/monster_cards/approach_bite.tres",
	"res://resources/cards/monster_cards/drag_tear.tres",
	"res://resources/cards/monster_cards/pack_hunt.tres",
	"res://resources/cards/monster_cards/hunker_hide.tres",
	"res://resources/cards/monster_cards/sewage_spit.tres",
	"res://resources/cards/monster_cards/submerge.tres",
	"res://resources/cards/monster_cards/guard_hiss.tres",
	"res://resources/cards/monster_cards/empty_eye.tres",
]
const MUTATION_CARDS := [
	"res://resources/cards/monster_cards/lashing_tentacle.tres",
	"res://resources/cards/monster_cards/blood_mouth.tres",
	"res://resources/cards/monster_cards/extra_limbs.tres",
	"res://resources/cards/monster_cards/scorch_sac.tres",
	"res://resources/cards/monster_cards/enlightened_tumor.tres",
	"res://resources/cards/monster_cards/night_membrane.tres",
	"res://resources/cards/monster_cards/irradiated_gland.tres",
	"res://resources/cards/monster_cards/stampeding_feet.tres",
]
const MONSTER_CARD_ART := "res://assets/art/cards/monster_card_basic.svg"
const ENEMY_ART := {
	&"hungry_fish": {"portrait": "res://assets/art/portraits/chapter_one/hungry_fish_portrait.png", "battle": "res://assets/art/battle_units/chapter_one/hungry_fish_battle.png"},
	&"harpoon_fish": {"portrait": "res://assets/art/portraits/chapter_one/harpoon_fish_portrait.png", "battle": "res://assets/art/battle_units/chapter_one/harpoon_fish_battle.png"},
	&"bandit_blade": {"portrait": "res://assets/art/portraits/chapter_one/bandit_blade_portrait.png", "battle": "res://assets/art/battle_units/chapter_one/bandit_blade_battle.png"},
	&"bandit_bow": {"portrait": "res://assets/art/portraits/chapter_one/bandit_bow_portrait.png", "battle": "res://assets/art/battle_units/chapter_one/bandit_bow_battle.png"},
	&"fish_priest": {"portrait": "res://assets/art/portraits/chapter_one/fish_priest_portrait.png", "battle": "res://assets/art/battle_units/chapter_one/fish_priest_battle.png"},
	&"unclean_one": {"portrait": "res://assets/art/portraits/chapter_one/unclean_one_portrait.png", "battle": "res://assets/art/battle_units/chapter_one/unclean_one_battle.png"},
	&"fish_champion": {"portrait": "res://assets/art/portraits/chapter_one/fish_champion_portrait.png", "battle": "res://assets/art/battle_units/chapter_one/fish_champion_battle.png"},
	&"kraken": {"portrait": "res://assets/art/portraits/chapter_one/kraken_portrait.png", "battle": "res://assets/art/battle_units/chapter_one/kraken_battle.png"},
	&"high_priest": {"portrait": "res://assets/art/portraits/chapter_one/high_priest_portrait.png", "battle": "res://assets/art/battle_units/chapter_one/high_priest_battle.png"},
	&"abyss_scale": {"portrait": "res://assets/art/portraits/chapter_one/abyss_scale_portrait.png", "battle": "res://assets/art/battle_units/chapter_one/abyss_scale_battle.png"},
}

const WEAK_ENCOUNTERS := [
	{"id": "double_hungry", "enemies": [&"hungry_fish", &"hungry_fish"]},
	{"id": "harpoon_patrol", "enemies": [&"hungry_fish", &"harpoon_fish"]},
	{"id": "bandit_pair", "enemies": [&"bandit_blade", &"bandit_bow"]},
]
const MIXED_ENCOUNTERS := [
	{"id": "priest_school", "enemies": [&"fish_priest", &"hungry_fish", &"hungry_fish"]},
	{"id": "unclean_feeder", "enemies": [&"unclean_one", &"hungry_fish"]},
	{"id": "champion_guard", "enemies": [&"fish_champion", &"hungry_fish"]},
	{"id": "bandit_school", "enemies": [&"bandit_blade", &"bandit_bow", &"hungry_fish"]},
]
const STRONG_ENCOUNTERS := [
	{"id": "flooded_rite", "enemies": [&"fish_priest", &"harpoon_fish", &"hungry_fish"]},
	{"id": "unclean_pack", "enemies": [&"unclean_one", &"hungry_fish", &"hungry_fish"]},
	{"id": "champion_spearhead", "enemies": [&"fish_champion", &"harpoon_fish"]},
	{"id": "bandit_corruption", "enemies": [&"bandit_blade", &"bandit_bow", &"unclean_one"]},
]


static func create_enemy(archetype: StringName, seed: int = -1) -> EnemyState:
	var spec := _get_spec(archetype)
	if spec.is_empty():
		return null
	var data := EnemyData.new()
	data.enemy_name = str(spec.name)
	data.enemy_rank = int(spec.get("rank", EnemyEnums.EnemyRank.NORMAL))
	data.base_max_health = int(spec.base_health)
	data.base_strength = int(spec.strength)
	data.base_agility = int(spec.agility)
	data.base_intelligence = int(spec.intelligence)
	data.archetype_id = archetype
	data.class_profile = int(spec.get("class_profile", CardEnums.CardClass.NEUTRAL))
	data.trait_summary = str(spec.get("trait", ""))
	data.weapon_equipment = _make_weapon(spec.weapon as Dictionary)
	if spec.has("reserve"):
		data.reserve_weapon_equipment = _make_weapon(spec.reserve as Dictionary)
	data.innate_base_damage = data.weapon_equipment.base_damage
	data.innate_damage_type = data.weapon_equipment.damage_type
	data.base_attack_range = data.weapon_equipment.attack_range
	data.deck_rule = _make_deck_rule(int(spec.get("basic", 8)), int(spec.get("mutation", 0)), spec.get("class_cards", []), spec.get("curse_cards", []))
	data.ai_profile = EnemyTacticalCardCatalog.create_profile(int(spec.get("ai_profile", EnemyAIProfile.Preset.BALANCED)))
	data.behavior = TacticalEnemyBehavior.new()
	data.behavior.behavior_label = "公开意图战术"
	data.portrait = _load_enemy_art(archetype, "portrait")
	data.battle_sprite = _load_enemy_art(archetype, "battle")
	var state := EnemyState.new()
	state.enemy_data = data
	state.generate_deck(seed)
	state.current_health = state.get_max_health()
	return state


static func get_art_texture(archetype: StringName, art_kind: String) -> Texture2D:
	return _load_enemy_art(archetype, art_kind)


static func pick_encounter(tier: int, seed: int, last_id: String = "") -> Dictionary:
	return (draw_encounter(tier, seed, [], last_id).get("encounter", {}) as Dictionary).duplicate(true)


static func draw_encounter(tier: int, seed: int, remaining_ids: Array, last_id: String = "") -> Dictionary:
	if tier == AdventureEnums.EncounterTier.ELITE:
		return {"encounter": {"id": "kraken_elite", "enemies": [&"kraken"]}, "remaining_ids": []}
	if tier == AdventureEnums.EncounterTier.BOSS:
		if absi(seed) % 2 == 0:
			return {"encounter": {"id": "high_priest_boss", "enemies": [&"high_priest", &"harpoon_fish", &"hungry_fish", &"hungry_fish"]}, "remaining_ids": []}
		return {"encounter": {"id": "abyss_scale_boss", "enemies": [&"abyss_scale"]}, "remaining_ids": []}
	var pool := _get_encounter_pool(tier)
	var available: Array = remaining_ids.duplicate()
	if available.is_empty():
		for entry in pool:
			available.append(str(entry.id))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var chosen_index := rng.randi_range(0, available.size() - 1)
	if available.size() > 1 and str(available[chosen_index]) == last_id:
		chosen_index = (chosen_index + 1) % available.size()
	var chosen_id := str(available.pop_at(chosen_index))
	for entry in pool:
		if str(entry.id) == chosen_id:
			return {"encounter": (entry as Dictionary).duplicate(true), "remaining_ids": available}
	return {"encounter": (pool[0] as Dictionary).duplicate(true), "remaining_ids": available}


static func _get_encounter_pool(tier: int) -> Array:
	if tier in [AdventureEnums.EncounterTier.MIXED, AdventureEnums.EncounterTier.AMBUSH]:
		return MIXED_ENCOUNTERS
	if tier == AdventureEnums.EncounterTier.STRONG:
		return STRONG_ENCOUNTERS
	return WEAK_ENCOUNTERS


static func _make_deck_rule(basic_count: int, mutation_count: int, class_cards: Array, curse_cards: Array) -> EnemyDeckRule:
	var rule := EnemyDeckRule.new()
	if basic_count > 0:
		rule.category_slots.append(_make_slot("怪物基础牌", basic_count, BASIC_CARDS))
	if mutation_count > 0:
		rule.category_slots.append(_make_slot("畸变牌", mutation_count, MUTATION_CARDS))
	for card_id in class_cards:
		var card := _make_enemy_class_card(str(card_id))
		_append_fixed_card(rule, card)
	for card_path in curse_cards:
		var template := load(str(card_path)) as CardData
		var card := template.duplicate(true) as CardData if template != null else null
		if card != null:
			card.reward_eligible = false
		_append_fixed_card(rule, card)
	return rule


static func _append_fixed_card(rule: EnemyDeckRule, card: CardData) -> void:
	if card == null:
		return
	var stack := CardStack.new()
	stack.card_data = card
	stack.count = 1
	rule.fixed_cards.append(stack)
	rule.tactical_entries.append(EnemyTacticalCardCatalog.create_entry(card))


static func _make_enemy_class_card(card_id: String) -> CardData:
	var specs := {
		"slam": ["猛击", "使用者对目标进行一次武器打击。结算后，若目标仍存活且使用者有护甲，向目标施加 1 层眩晕。", 2, CardEnums.TargetType.SINGLE, CardEnums.CardType.ATTACK, CardEnums.DamageType.WEAPON, ChapterOneEnemyClassCardEffect.Kind.SLAM, 0],
		"charge": ["冲锋", "使用者向目标移动至多 2 格。移动后，若目标仍存活且位于使用者的有效攻击范围内，对其进行一次武器打击；否则不进行打击。", 2, CardEnums.TargetType.SINGLE, CardEnums.CardType.ATTACK, CardEnums.DamageType.WEAPON, ChapterOneEnemyClassCardEffect.Kind.CHARGE, 4],
		"defensive_stance": ["防御架势", "使用者获得 6 护甲。", 2, CardEnums.TargetType.NONE, CardEnums.CardType.SKILL, CardEnums.DamageType.STRENGTH, ChapterOneEnemyClassCardEffect.Kind.DEFENSIVE_STANCE, 0],
		"perilous_assault": ["险步突袭", "使用者对目标进行一次武器打击。结算后，若使用者与目标相邻，使用者远离目标移动 1 格；该移动不要求打击命中或造成伤害。", 1, CardEnums.TargetType.SINGLE, CardEnums.CardType.ATTACK, CardEnums.DamageType.WEAPON, ChapterOneEnemyClassCardEffect.Kind.PERILOUS_ASSAULT, 0],
		"crossbow_tether": ["弩索牵引", "使用者对目标进行一次武器打击。若该打击造成正数伤害且目标仍存活，将目标向使用者拉近 1 格。", 2, CardEnums.TargetType.SINGLE, CardEnums.CardType.ATTACK, CardEnums.DamageType.WEAPON, ChapterOneEnemyClassCardEffect.Kind.CROSSBOW_TETHER, 4],
		"verdant_strike": ["苍翠打击", "使用者对目标进行一次武器打击，然后按结算时的手牌数获得等量护甲，至多 5 护甲；手牌数包括本牌。", 2, CardEnums.TargetType.SINGLE, CardEnums.CardType.ATTACK, CardEnums.DamageType.WEAPON, ChapterOneEnemyClassCardEffect.Kind.VERDANT_STRIKE, 0],
		"moonlight": ["月光", "若目标是友方单位，使其回复 4 生命；否则对目标造成 4 点智力伤害。", 1, CardEnums.TargetType.SINGLE, CardEnums.CardType.SKILL, CardEnums.DamageType.INTELLIGENCE, ChapterOneEnemyClassCardEffect.Kind.MOONLIGHT, 3],
		"rooted_insight": ["根系洞察", "使用者抽 2 张牌。", 1, CardEnums.TargetType.NONE, CardEnums.CardType.SKILL, CardEnums.DamageType.INTELLIGENCE, ChapterOneEnemyClassCardEffect.Kind.ROOTED_INSIGHT, 0],
		"canopy_shape": ["蓄翠化形", "使用者获得 6 护甲，然后抽 1 张牌。", 2, CardEnums.TargetType.NONE, CardEnums.CardType.SKILL, CardEnums.DamageType.INTELLIGENCE, ChapterOneEnemyClassCardEffect.Kind.CANOPY_SHAPE, 0],
		"wild_shape": ["野性变形", "使用者本回合获得 +2 伤害加值，然后抽 1 张牌。", 1, CardEnums.TargetType.NONE, CardEnums.CardType.SKILL, CardEnums.DamageType.INTELLIGENCE, ChapterOneEnemyClassCardEffect.Kind.WILD_SHAPE, 0],
	}
	var spec := specs.get(card_id, []) as Array
	if spec.is_empty():
		return null
	var card := CardData.new()
	card.card_name = str(spec[0])
	card.description = str(spec[1])
	card.ap_cost = int(spec[2])
	card.target_type = int(spec[3])
	card.card_type = int(spec[4])
	card.damage_type = int(spec[5])
	card.reward_eligible = false
	card.rarity = CardEnums.Rarity.BASIC
	card.card_class = CardEnums.CardClass.NEUTRAL
	card.artwork = load(MONSTER_CARD_ART) as Texture2D
	var range_value := int(spec[7])
	if range_value > 0:
		card.override_range = true
		card.card_range = range_value
	var effect := ChapterOneEnemyClassCardEffect.new()
	effect.kind = int(spec[6])
	card.effect = effect
	return card


static func _make_slot(label: String, count: int, paths: Array) -> EnemyDeckSlot:
	var slot := EnemyDeckSlot.new()
	slot.slot_label = label
	slot.pick_count = mini(count, paths.size())
	for path in paths:
		var card := load(str(path)) as CardData
		if card == null:
			continue
		var entry := EnemyTacticalCardCatalog.create_entry(card)
		slot.entries.append(entry)
	return slot


static func _base_card_score(card_name: String) -> int:
	match card_name:
		"蜷缩硬皮", "护群嘶鸣": return 8
		"空目择食", "启明之瘤": return 12
		"披夜薄膜": return 5
		_: return 10


static func _make_weapon(spec: Dictionary) -> EquipmentData:
	var weapon := EquipmentData.new()
	weapon.item_name = str(spec.name)
	weapon.description = str(spec.get("description", "怪物的真实武器。"))
	weapon.base_damage = int(spec.damage)
	weapon.attack_range = int(spec.range)
	weapon.damage_type = int(spec.get("damage_type", CardEnums.DamageType.STRENGTH))
	weapon.range_type = int(spec.get("range_type", EquipmentData.WeaponRangeType.MELEE))
	weapon.equip_slot = EquipmentData.EquipSlot.WEAPON
	weapon.equip_category = EquipmentData.EquipCategory.TWO_HAND
	return weapon


static func _load_enemy_art(archetype: StringName, art_kind: String) -> Texture2D:
	var entry := ENEMY_ART.get(archetype, {}) as Dictionary
	var path := str(entry.get(art_kind, ""))
	return load(path) as Texture2D if not path.is_empty() else null


static func _get_spec(id: StringName) -> Dictionary:
	var specs := {
		&"hungry_fish": {"name": "饥饿鱼人", "base_health": 9, "strength": 2, "agility": 4, "intelligence": 2, "weapon": {"name": "裂口爪", "damage": 3, "range": 2}, "basic": 8, "art_index": 0, "trait": "首次受到致命伤害时，饥饿鱼人不会死亡，而是在原地变为逆位鱼人：清除全部护甲和状态，将生命上限改为 7、力量改为 0、敏捷改为 2、武器基础伤害改为 3、攻击范围改为 1，并将当前生命恢复至上限。逆位鱼人最终死亡时，若最近的冒险者位于其当前攻击范围内，向该冒险者施加 2 层眩晕；否则不触发。"},
		&"harpoon_fish": {"name": "鱼叉鱼人", "base_health": 13, "strength": 2, "agility": 6, "intelligence": 2, "weapon": {"name": "潮锈鱼叉", "damage": 4, "range": 2}, "basic": 8, "art_index": 2, "trait": "鱼叉鱼人位于水元素格时，敏捷 +3。每个自身回合至多一次，完成非强制移动后，若起点和终点中恰有一处是水元素格，获得 2 AP。"},
		&"bandit_blade": {"name": "流寇刀手", "base_health": 9, "strength": 3, "agility": 7, "intelligence": 2, "weapon": {"name": "流寇弯刀", "damage": 3, "range": 1}, "basic": 6, "class_profile": CardEnums.CardClass.WARRIOR, "class_cards": ["slam", "charge"], "ai_profile": EnemyAIProfile.Preset.LOW_HEALTH_BERSERK, "art_index": 3, "trait": ""},
		&"bandit_bow": {"name": "流寇弩手", "base_health": 8, "strength": 2, "agility": 8, "intelligence": 2, "weapon": {"name": "流寇轻弩", "damage": 3, "range": 4, "range_type": EquipmentData.WeaponRangeType.RANGED}, "basic": 6, "class_profile": CardEnums.CardClass.RANGER, "class_cards": ["perilous_assault", "crossbow_tether"], "ai_profile": EnemyAIProfile.Preset.RANGED_CONTROL, "art_index": 3, "trait": ""},
		&"fish_priest": {"name": "鱼人祭司", "base_health": 19, "strength": 2, "agility": 5, "intelligence": 4, "weapon": {"name": "引潮杖", "damage": 2, "range": 3, "damage_type": CardEnums.DamageType.INTELLIGENCE, "range_type": EquipmentData.WeaponRangeType.RANGED}, "basic": 8, "class_profile": CardEnums.CardClass.DRUID, "class_cards": ["verdant_strike", "moonlight"], "ai_profile": EnemyAIProfile.Preset.RANGED_CONTROL, "art_index": 4, "trait": "鱼人祭司的回合开始时，向其所在格施加水元素。只要战场上存在存活的鱼人祭司或大湖主祭，所有位于水元素格的敌方单位获得 +1 伤害加值，并在各自回合开始时回复 2 生命；多个祭司不会叠加该效果。"},
		&"unclean_one": {"name": "不洁者", "base_health": 15, "strength": 3, "agility": 4, "intelligence": 3, "weapon": {"name": "污化肢体", "damage": 2, "range": 1}, "basic": 8, "curse_cards": ["res://resources/cards/curse_industry_blood.tres"], "art_index": 5, "trait": "每当不洁者打出诅咒牌后，若污化少于 4 层，获得 1 层污化：本场战斗的生命上限提高 2，永久获得 +1 伤害加值，然后回复 2 生命。污化最多 4 层。"},
		&"fish_champion": {"name": "鱼人冠军", "base_health": 16, "strength": 4, "agility": 4, "intelligence": 2, "weapon": {"name": "潮痕大剑", "damage": 4, "range": 2}, "reserve": {"name": "浪脊长枪", "damage": 2, "range": 3}, "basic": 5, "class_profile": CardEnums.CardClass.WARRIOR, "class_cards": ["slam", "charge", "defensive_stance"], "ai_profile": EnemyAIProfile.Preset.LOW_HEALTH_BERSERK, "art_index": 6, "trait": "回合开始时，若鱼人冠军当前使用潮痕大剑，获得 1 势，最多 5 势。锁定意图时若仍使用大剑，则下次行动开始先切换为浪脊长枪并消耗全部势；若存在锁定目标且消耗至少 1 势，向该目标移动至多等同于势的格数，并使下一次攻击获得每点势 +2 伤害加值。没有锁定目标时仍切换武器并清空势，但不移动且不获得伤害加值。"},
		&"kraken": {"name": "克拉肯", "rank": EnemyEnums.EnemyRank.ELITE, "base_health": 48, "strength": 3, "agility": 2, "intelligence": 3, "weapon": {"name": "群腕", "damage": 2, "range": 2}, "basic": 8, "mutation": 2, "art_index": 7, "trait": "回合开始时，若克拉肯当前生命高于生命上限的 66%，将当前 AP 乘 3；否则若高于 33%，将当前 AP 乘 2；否则当前 AP 不变。"},
		&"high_priest": {"name": "大湖主祭", "rank": EnemyEnums.EnemyRank.BOSS, "base_health": 66, "strength": 3, "agility": 5, "intelligence": 4, "weapon": {"name": "大湖权杖", "damage": 2, "range": 4, "damage_type": CardEnums.DamageType.INTELLIGENCE, "range_type": EquipmentData.WeaponRangeType.RANGED}, "basic": 5, "mutation": 1, "class_profile": CardEnums.CardClass.DRUID, "class_cards": ["verdant_strike", "moonlight", "rooted_insight", "canopy_shape", "wild_shape"], "curse_cards": ["res://resources/cards/curse_industry_blood.tres", "res://resources/cards/curse_industry_universal_love.tres"], "art_index": 8, "trait": "大湖主祭的回合开始时，向其所在格施加水元素。只要战场上存在存活的鱼人祭司或大湖主祭，所有位于水元素格的敌方单位获得 +1 伤害加值，并在各自回合开始时回复 2 生命。每当除大湖主祭外的敌方单位最终死亡时，大湖主祭清除全部状态、全部咒波和全部敌人运行时状态，然后失去 5 生命。"},
		&"abyss_scale": {"name": "渊鳞", "rank": EnemyEnums.EnemyRank.BOSS, "base_health": 85, "strength": 5, "agility": 11, "intelligence": 3, "weapon": {"name": "渊鳞长躯", "damage": 3, "range": 3}, "reserve": {"name": "深渊利齿", "damage": 4, "range": 1}, "basic": 6, "mutation": 4, "art_index": 9, "trait": "战斗开始时，为所有存活冒险者建立一个共享的 16 点共有护甲池。冒险者受到伤害时，抵挡、伤害减免和个人护甲先结算，共有护甲再吸收剩余伤害；忽略护甲的伤害不消耗该池。护甲池归零时，渊鳞进入第二阶段：切换为深渊利齿，并将战场所有地形改为深渊。渊鳞每个回合结束时先失去 3 生命；若仍存活且处于第二阶段，再获得 3 护甲。"},
	}
	return (specs.get(id, {}) as Dictionary).duplicate(true)
