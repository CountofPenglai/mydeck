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
const MONSTER_ATLAS := "res://assets/art/enemies/chapter_one_monsters.svg"
const MONSTER_CARD_ART := "res://assets/art/cards/monster_card_basic.svg"

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
	var texture := _make_atlas_texture(int(spec.art_index))
	data.portrait = texture
	data.battle_sprite = texture
	var state := EnemyState.new()
	state.enemy_data = data
	state.generate_deck(seed)
	state.current_health = state.get_max_health()
	return state


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
		"slam": ["猛击", "武器打击；自身有护甲时施加眩晕1。", 2, CardEnums.TargetType.SINGLE, CardEnums.CardType.ATTACK, CardEnums.DamageType.WEAPON, ChapterOneEnemyClassCardEffect.Kind.SLAM, 0],
		"charge": ["冲锋", "向目标移动至多2格，随后武器打击。", 2, CardEnums.TargetType.SINGLE, CardEnums.CardType.ATTACK, CardEnums.DamageType.WEAPON, ChapterOneEnemyClassCardEffect.Kind.CHARGE, 4],
		"defensive_stance": ["防御架势", "获得6护甲。", 2, CardEnums.TargetType.NONE, CardEnums.CardType.SKILL, CardEnums.DamageType.STRENGTH, ChapterOneEnemyClassCardEffect.Kind.DEFENSIVE_STANCE, 0],
		"perilous_assault": ["险步突袭", "武器打击；近战命中后尝试后退1格。", 1, CardEnums.TargetType.SINGLE, CardEnums.CardType.ATTACK, CardEnums.DamageType.WEAPON, ChapterOneEnemyClassCardEffect.Kind.PERILOUS_ASSAULT, 0],
		"crossbow_tether": ["弩索牵引", "远程武器打击；目标存活则拉近1格。", 2, CardEnums.TargetType.SINGLE, CardEnums.CardType.ATTACK, CardEnums.DamageType.WEAPON, ChapterOneEnemyClassCardEffect.Kind.CROSSBOW_TETHER, 4],
		"verdant_strike": ["苍翠打击", "武器打击；按当前手牌数获得护甲，至多5。", 2, CardEnums.TargetType.SINGLE, CardEnums.CardType.ATTACK, CardEnums.DamageType.WEAPON, ChapterOneEnemyClassCardEffect.Kind.VERDANT_STRIKE, 0],
		"moonlight": ["月光", "对敌人造成4点智力伤害，或令友军回复4生命。", 1, CardEnums.TargetType.SINGLE, CardEnums.CardType.SKILL, CardEnums.DamageType.INTELLIGENCE, ChapterOneEnemyClassCardEffect.Kind.MOONLIGHT, 3],
		"rooted_insight": ["根系洞察", "抽2张牌。", 1, CardEnums.TargetType.NONE, CardEnums.CardType.SKILL, CardEnums.DamageType.INTELLIGENCE, ChapterOneEnemyClassCardEffect.Kind.ROOTED_INSIGHT, 0],
		"canopy_shape": ["蓄翠化形", "获得6护甲并抽1张牌。", 2, CardEnums.TargetType.NONE, CardEnums.CardType.SKILL, CardEnums.DamageType.INTELLIGENCE, ChapterOneEnemyClassCardEffect.Kind.CANOPY_SHAPE, 0],
		"wild_shape": ["野性变形", "本回合获得+2伤害加值并抽1张牌。", 1, CardEnums.TargetType.NONE, CardEnums.CardType.SKILL, CardEnums.DamageType.INTELLIGENCE, ChapterOneEnemyClassCardEffect.Kind.WILD_SHAPE, 0],
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
	weapon.subcategories = PackedStringArray(["怪物武器"])
	return weapon


static func _make_atlas_texture(index: int) -> Texture2D:
	var atlas := load(MONSTER_ATLAS) as Texture2D
	if atlas == null:
		return null
	var texture := AtlasTexture.new()
	texture.atlas = atlas
	texture.region = Rect2(index * 128, 0, 128, 128)
	return texture


static func _get_spec(id: StringName) -> Dictionary:
	var specs := {
		&"hungry_fish": {"name": "饥饿鱼人", "base_health": 9, "strength": 1, "agility": 3, "intelligence": 1, "weapon": {"name": "裂口爪", "damage": 2, "range": 2}, "basic": 8, "art_index": 0, "trait": "首次死亡后逆位；最终死亡眩晕最近冒险者。"},
		&"harpoon_fish": {"name": "鱼叉鱼人", "base_health": 12, "strength": 1, "agility": 5, "intelligence": 1, "weapon": {"name": "潮锈鱼叉", "damage": 3, "range": 2}, "basic": 8, "art_index": 2, "trait": "水中敏捷+3；跨越水域边界每回合获得2 AP。"},
		&"bandit_blade": {"name": "流寇刀手", "base_health": 8, "strength": 2, "agility": 6, "intelligence": 1, "weapon": {"name": "流寇弯刀", "damage": 2, "range": 1}, "basic": 6, "class_profile": CardEnums.CardClass.WARRIOR, "class_cards": ["slam", "charge"], "ai_profile": EnemyAIProfile.Preset.LOW_HEALTH_BERSERK, "art_index": 3, "trait": "与弩手协同，以破口标记强化远程同伴。"},
		&"bandit_bow": {"name": "流寇弩手", "base_health": 8, "strength": 1, "agility": 7, "intelligence": 1, "weapon": {"name": "流寇轻弩", "damage": 2, "range": 4, "range_type": EquipmentData.WeaponRangeType.RANGED}, "basic": 6, "class_profile": CardEnums.CardClass.RANGER, "class_cards": ["perilous_assault", "crossbow_tether"], "ai_profile": EnemyAIProfile.Preset.RANGED_CONTROL, "art_index": 3, "trait": "与刀手协同，以压制标记强化近战同伴。"},
		&"fish_priest": {"name": "鱼人祭司", "base_health": 17, "strength": 1, "agility": 4, "intelligence": 3, "weapon": {"name": "引潮杖", "damage": 1, "range": 3, "damage_type": CardEnums.DamageType.INTELLIGENCE, "range_type": EquipmentData.WeaponRangeType.RANGED}, "basic": 8, "class_profile": CardEnums.CardClass.DRUID, "class_cards": ["verdant_strike", "moonlight"], "ai_profile": EnemyAIProfile.Preset.RANGED_CONTROL, "art_index": 4, "trait": "公开引潮；水中怪物获得伤害与治疗光环。"},
		&"unclean_one": {"name": "不洁者", "base_health": 13, "strength": 2, "agility": 3, "intelligence": 2, "weapon": {"name": "污化肢体", "damage": 1, "range": 1}, "basic": 8, "curse_cards": ["res://resources/cards/curse_industry_blood.tres"], "art_index": 5, "trait": "每次打出业牌获得污化，永久提高本场伤害与最大生命。"},
		&"fish_champion": {"name": "鱼人冠军", "base_health": 13, "strength": 3, "agility": 3, "intelligence": 1, "weapon": {"name": "潮痕大剑", "damage": 3, "range": 2}, "reserve": {"name": "浪脊长枪", "damage": 1, "range": 3}, "basic": 5, "class_profile": CardEnums.CardClass.WARRIOR, "class_cards": ["slam", "charge", "defensive_stance"], "ai_profile": EnemyAIProfile.Preset.LOW_HEALTH_BERSERK, "art_index": 6, "trait": "大剑积累势；切换长枪时消耗势突进并强化打击。"},
		&"kraken": {"name": "克拉肯", "rank": EnemyEnums.EnemyRank.ELITE, "base_health": 39, "strength": 2, "agility": 1, "intelligence": 2, "weapon": {"name": "群腕", "damage": 1, "range": 2}, "basic": 8, "mutation": 2, "art_index": 7, "trait": "按生命区间获得3/2/1组行动资源。"},
		&"high_priest": {"name": "大湖主祭", "rank": EnemyEnums.EnemyRank.BOSS, "base_health": 54, "strength": 2, "agility": 4, "intelligence": 3, "weapon": {"name": "大湖权杖", "damage": 1, "range": 4, "damage_type": CardEnums.DamageType.INTELLIGENCE, "range_type": EquipmentData.WeaponRangeType.RANGED}, "basic": 5, "mutation": 1, "class_profile": CardEnums.CardClass.DRUID, "class_cards": ["verdant_strike", "moonlight", "rooted_insight", "canopy_shape", "wild_shape"], "curse_cards": ["res://resources/cards/curse_industry_blood.tres", "res://resources/cards/curse_industry_universal_love.tres"], "art_index": 8, "trait": "固定护卫；友军最终死亡时失去5生命并清空战斗资源。"},
		&"abyss_scale": {"name": "渊鳞", "rank": EnemyEnums.EnemyRank.BOSS, "base_health": 68, "strength": 4, "agility": 10, "intelligence": 2, "weapon": {"name": "渊鳞长躯", "damage": 2, "range": 3}, "reserve": {"name": "深渊利齿", "damage": 3, "range": 1}, "basic": 6, "mutation": 4, "art_index": 9, "trait": "共有护甲、牌组替换与全图深渊二阶段。"},
	}
	return (specs.get(id, {}) as Dictionary).duplicate(true)
