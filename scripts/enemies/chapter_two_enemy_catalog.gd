extends RefCounted
class_name ChapterTwoEnemyCatalog

const MUTATION_CARDS := ChapterOneEnemyCatalog.MUTATION_CARDS
const REUSED_MONSTER_CARDS := [
	"res://resources/cards/monster_cards/hunker_hide.tres",
	"res://resources/cards/monster_cards/guard_hiss.tres",
	"res://resources/cards/monster_cards/empty_eye.tres",
]
const MONSTER_ATLAS := "res://assets/art/enemies/chapter_two_monsters.svg"

const WEAK_ENCOUNTERS := [
	{"id": "shield_spear", "enemies": [&"gray_shield_guard", &"holy_spearman"]},
	{"id": "shield_crossbow", "enemies": [&"gray_shield_guard", &"fortress_crossbow"]},
	{"id": "spear_crossbow", "enemies": [&"holy_spearman", &"fortress_crossbow"]},
	{"id": "shield_priest", "enemies": [&"gray_shield_guard", &"field_priest"]},
]
const MIXED_ENCOUNTERS := [
	{"id": "formation_trio", "enemies": [&"gray_shield_guard", &"holy_spearman", &"fortress_crossbow"]},
	{"id": "chaplain_line", "enemies": [&"gray_shield_guard", &"field_priest", &"holy_spearman"]},
	{"id": "punishment_wall", "enemies": [&"punishment_knight", &"gray_shield_guard"]},
	{"id": "banner_fireteam", "enemies": [&"standard_bearer", &"holy_spearman", &"fortress_crossbow"]},
]
const STRONG_ENCOUNTERS := [
	{"id": "banner_spearhead", "enemies": [&"standard_bearer", &"gray_shield_guard", &"holy_spearman"]},
	{"id": "penitent_wall", "enemies": [&"punishment_knight", &"field_priest", &"gray_shield_guard"]},
	{"id": "crossbow_square", "enemies": [&"standard_bearer", &"gray_shield_guard", &"fortress_crossbow", &"fortress_crossbow"]},
	{"id": "creation_patrol", "enemies": [&"creation_shard", &"gray_shield_guard", &"holy_spearman"]},
	{"id": "punishment_banner", "enemies": [&"punishment_knight", &"standard_bearer", &"fortress_crossbow"]},
]
const COMMANDER_ESCORTS := [
	[&"gray_shield_guard", &"holy_spearman"],
	[&"gray_shield_guard", &"fortress_crossbow"],
	[&"holy_spearman", &"fortress_crossbow"],
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
	data.chapter = 2
	data.unit_tags = PackedStringArray(spec.get("tags", []))
	data.permanent_distortion_fields = PackedStringArray(spec.get("fields", []))
	data.class_profile = int(spec.get("class_profile", CardEnums.CardClass.NEUTRAL))
	data.trait_summary = str(spec.get("trait", ""))
	data.weapon_equipment = _make_weapon(spec.weapon as Dictionary)
	if spec.has("reserve"):
		data.reserve_weapon_equipment = _make_weapon(spec.reserve as Dictionary)
	data.innate_base_damage = data.weapon_equipment.base_damage
	data.innate_damage_type = data.weapon_equipment.damage_type
	data.base_attack_range = data.weapon_equipment.attack_range
	data.deck_rule = _make_deck_rule(spec)
	data.behavior = TacticalEnemyBehavior.new()
	data.behavior.behavior_label = "第二章公开意图"
	var texture := _make_atlas_texture(int(spec.art_index))
	data.portrait = texture
	data.battle_sprite = texture
	var state := EnemyState.new()
	state.enemy_data = data
	if spec.has("fixed_max_health"):
		state.runtime_state["max_health_override"] = int(spec.fixed_max_health)
	state.generate_deck(seed)
	state.current_health = state.get_max_health()
	return state


static func pick_encounter(tier: int, seed: int, last_id: String = "") -> Dictionary:
	return (draw_encounter(tier, seed, [], last_id).get("encounter", {}) as Dictionary).duplicate(true)


static func draw_encounter(tier: int, seed: int, remaining_ids: Array, last_id: String = "") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	if tier == AdventureEnums.EncounterTier.ELITE:
		if absi(seed) % 2 != 0:
			return {"encounter": {"id": "blood_construct_elite", "enemies": [&"blood_construct"]}, "remaining_ids": []}
		var escorts: Array = COMMANDER_ESCORTS[rng.randi_range(0, COMMANDER_ESCORTS.size() - 1)]
		return {
			"encounter": {
				"id": "holy_bastion_commander_elite",
				"enemies": [&"holy_bastion_commander"] + escorts,
			},
			"remaining_ids": [],
		}
	if tier == AdventureEnums.EncounterTier.BOSS:
		if absi(seed) % 2 == 0:
			return {"encounter": {"id": "corrupt_heart_veil_boss", "enemies": [&"corrupt_heart_veil"]}, "remaining_ids": []}
		return {"encounter": {"id": "gray_bastion_paladin_boss", "enemies": [&"gray_bastion_paladin", &"triumph_statue"]}, "remaining_ids": []}
	var pool := _get_encounter_pool(tier)
	if pool.is_empty():
		return {"encounter": {}, "remaining_ids": []}
	var available: Array = remaining_ids.duplicate()
	if available.is_empty():
		for entry in pool:
			available.append(str(entry.id))
	var chosen_index := rng.randi_range(0, available.size() - 1)
	if available.size() > 1 and str(available[chosen_index]) == last_id:
		chosen_index = (chosen_index + 1) % available.size()
	var chosen_id := str(available.pop_at(chosen_index))
	for entry in pool:
		if str(entry.id) == chosen_id:
			return {"encounter": (entry as Dictionary).duplicate(true), "remaining_ids": available}
	return {"encounter": (pool[0] as Dictionary).duplicate(true), "remaining_ids": available}


static func create_gospel_card() -> CardData:
	return _make_card(
		"福音",
		"对所有其他单位造成智力伤害并散播咒波与临时咒害。",
		0,
		CardEnums.TargetType.NONE,
		CardEnums.CardType.CURSE,
		CardEnums.DamageType.INTELLIGENCE,
		ChapterTwoEnemyCardEffect.Kind.GOSPEL,
		6
	)


static func create_variant_card(pool_id: String, seed: int) -> CardData:
	var variants := _variant_cards()
	var pool: Array = variants.get(pool_id, variants.get("monster", []))
	if pool.is_empty():
		return null
	return (pool[absi(seed) % pool.size()] as CardData).duplicate(true) as CardData


static func _get_encounter_pool(tier: int) -> Array:
	if tier in [AdventureEnums.EncounterTier.MIXED, AdventureEnums.EncounterTier.AMBUSH]:
		return MIXED_ENCOUNTERS
	if tier == AdventureEnums.EncounterTier.STRONG:
		return STRONG_ENCOUNTERS
	return WEAK_ENCOUNTERS


static func _make_deck_rule(spec: Dictionary) -> EnemyDeckRule:
	var rule := EnemyDeckRule.new()
	var military_count := int(spec.get("military", 0))
	if military_count > 0:
		rule.category_slots.append(_make_card_slot("军事公共牌", military_count, _military_cards()))
	var mutation_count := int(spec.get("mutation", 0))
	if mutation_count > 0:
		rule.category_slots.append(_make_path_slot("畸变牌", mutation_count, MUTATION_CARDS))
	var reused_count := int(spec.get("reused", 0))
	if reused_count > 0:
		rule.category_slots.append(_make_path_slot("怪物基础牌", reused_count, REUSED_MONSTER_CARDS))
	for card in spec.get("fixed_cards", []):
		_append_fixed_card(rule, card as CardData)
	var variant_counts := spec.get("variant_counts", {}) as Dictionary
	for pool_id in spec.get("variant_pools", []):
		var pool: Array = _variant_cards().get(str(pool_id), [])
		var pick_count := mini(int(variant_counts.get(str(pool_id), pool.size())), pool.size())
		for index in range(pick_count):
			_append_fixed_card(rule, pool[index] as CardData)
	for pool_id in spec.get("variant_extra", []):
		var pool: Array = _variant_cards().get(str(pool_id), [])
		if not pool.is_empty():
			_append_fixed_card(rule, pool[0] as CardData)
	for path in spec.get("curse_cards", []):
		_append_fixed_card(rule, load(str(path)) as CardData)
	return rule


static func _append_fixed_card(rule: EnemyDeckRule, card: CardData) -> void:
	if card == null:
		return
	var runtime_card := card.duplicate(true) as CardData
	runtime_card.reward_eligible = false
	var stack := CardStack.new()
	stack.card_data = runtime_card
	stack.count = 1
	rule.fixed_cards.append(stack)


static func _make_card_slot(label: String, count: int, cards: Array) -> EnemyDeckSlot:
	var slot := EnemyDeckSlot.new()
	slot.slot_label = label
	slot.pick_count = mini(count, cards.size())
	for card in cards:
		var entry := EnemyCardPoolEntry.new()
		entry.card = card
		entry.max_copies = 1
		entry.base_score = 10
		slot.entries.append(entry)
	return slot


static func _make_path_slot(label: String, count: int, paths: Array) -> EnemyDeckSlot:
	var cards: Array[CardData] = []
	for path in paths:
		var card := load(str(path)) as CardData
		if card != null:
			cards.append(card)
	return _make_card_slot(label, count, cards)


static func _military_cards() -> Array[CardData]:
	return [
		_make_card("列阵推进", "移动至多1格并打击；军阵中移动距离+1。", 1, CardEnums.TargetType.SINGLE, CardEnums.CardType.ATTACK, CardEnums.DamageType.STRENGTH, ChapterTwoEnemyCardEffect.Kind.FORMATION_ADVANCE, 4),
		_make_card("盾墙", "获得4护甲；军阵中改为6护甲。", 1, CardEnums.TargetType.SELF, CardEnums.CardType.SKILL, CardEnums.DamageType.STRENGTH, ChapterTwoEnemyCardEffect.Kind.SHIELD_WALL),
		_make_card("协同突刺", "武器打击；军阵中获得+2伤害加值。", 2, CardEnums.TargetType.SINGLE, CardEnums.CardType.ATTACK, CardEnums.DamageType.STRENGTH, ChapterTwoEnemyCardEffect.Kind.COORDINATED_THRUST, 4),
		_make_card("要塞齐射", "造成3点敏捷伤害并施加咒波；军阵中施加量提高。", 2, CardEnums.TargetType.SINGLE, CardEnums.CardType.ATTACK, CardEnums.DamageType.AGILITY, ChapterTwoEnemyCardEffect.Kind.FORTRESS_VOLLEY, 4),
		_make_card("整队号令", "友军获得护甲并抽1；军阵中护甲提高。", 1, CardEnums.TargetType.SINGLE, CardEnums.CardType.SKILL, CardEnums.DamageType.INTELLIGENCE, ChapterTwoEnemyCardEffect.Kind.RALLY_LINE, 3),
		_make_card("强行军", "下一次移动距离提高；军阵中提高2。", 1, CardEnums.TargetType.SELF, CardEnums.CardType.SKILL, CardEnums.DamageType.AGILITY, ChapterTwoEnemyCardEffect.Kind.FORCED_MARCH),
		_make_card("刑罚令", "武器打击；目标具有咒波时获得+2伤害加值。", 2, CardEnums.TargetType.SINGLE, CardEnums.CardType.ATTACK, CardEnums.DamageType.STRENGTH, ChapterTwoEnemyCardEffect.Kind.PUNITIVE_ORDER, 4),
		_make_card("公开戒备", "进入附魔区并获得2护甲。", 1, CardEnums.TargetType.SELF, CardEnums.CardType.ENCHANTMENT, CardEnums.DamageType.STRENGTH, ChapterTwoEnemyCardEffect.Kind.WATCHFUL_STANCE),
	]


static func _variant_cards() -> Dictionary:
	return {
		"mage": [
			_make_card("裂片·秘法弹", "造成3点智力伤害。", 1, CardEnums.TargetType.SINGLE, CardEnums.CardType.ATTACK, CardEnums.DamageType.INTELLIGENCE, ChapterTwoEnemyCardEffect.Kind.ARC_BOLT, 4),
			_make_card("裂片·秘法护盾", "获得5护甲。", 1, CardEnums.TargetType.SELF, CardEnums.CardType.SKILL, CardEnums.DamageType.INTELLIGENCE, ChapterTwoEnemyCardEffect.Kind.ARCANE_WARD),
		],
		"warlock": [
			_make_card("裂片·血咒", "造成2点智力伤害并施加2咒波。", 1, CardEnums.TargetType.SINGLE, CardEnums.CardType.ATTACK, CardEnums.DamageType.INTELLIGENCE, ChapterTwoEnemyCardEffect.Kind.BLOOD_HEX, 4),
			_make_card("裂片·黑暗交易", "失去2生命，抽2。", 0, CardEnums.TargetType.SELF, CardEnums.CardType.SKILL, CardEnums.DamageType.INTELLIGENCE, ChapterTwoEnemyCardEffect.Kind.DARK_BARGAIN),
		],
		"ranger": [
			_make_card("裂片·闪避步", "远离最近敌人2格并获得2护甲。", 1, CardEnums.TargetType.SELF, CardEnums.CardType.SKILL, CardEnums.DamageType.AGILITY, ChapterTwoEnemyCardEffect.Kind.EVASIVE_STEP),
			_make_card("裂片·瞄准射击", "造成4点敏捷伤害。", 2, CardEnums.TargetType.SINGLE, CardEnums.CardType.ATTACK, CardEnums.DamageType.AGILITY, ChapterTwoEnemyCardEffect.Kind.AIMED_SHOT, 5),
		],
		"monster": _military_cards(),
	}


static func _make_card(card_name: String, description: String, ap: int, target_type: int, card_type: int, damage_type: int, effect_kind: int, card_range: int = 0) -> CardData:
	var card := CardData.new()
	card.card_name = card_name
	card.description = description
	card.ap_cost = ap
	card.target_type = target_type
	card.card_type = card_type
	card.damage_type = damage_type
	card.override_range = card_range > 0
	card.card_range = card_range
	card.reward_eligible = false
	card.card_class = CardEnums.CardClass.NEUTRAL
	var effect := ChapterTwoEnemyCardEffect.new()
	effect.kind = effect_kind
	card.effect = effect
	return card


static func _make_weapon(spec: Dictionary) -> EquipmentData:
	var weapon := EquipmentData.new()
	weapon.item_name = str(spec.name)
	weapon.description = "第二章敌人的真实武器。"
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
	var military := ["military"]
	var specs := {
		&"gray_shield_guard": {"name": "灰垒盾卫", "base_health": 17, "strength": 3, "agility": 2, "intelligence": 1, "weapon": {"name": "灰垒重盾", "damage": 2, "range": 1}, "military": 6, "mutation": 1, "fields": ["rock_scale"], "tags": military, "art_index": 0, "trait": "军阵：回合开始获得4护甲。"},
		&"holy_spearman": {"name": "圣枪兵", "base_health": 13, "strength": 3, "agility": 4, "intelligence": 1, "weapon": {"name": "圣垒长枪", "damage": 3, "range": 2}, "military": 6, "mutation": 1, "fields": ["lashing"], "tags": military, "art_index": 1, "trait": "军阵：每回合首次极限距离打击+2伤害加值。"},
		&"fortress_crossbow": {"name": "要塞弩手", "base_health": 15, "strength": 1, "agility": 5, "intelligence": 2, "weapon": {"name": "要塞重弩", "damage": 3, "range": 4, "damage_type": CardEnums.DamageType.AGILITY, "range_type": EquipmentData.WeaponRangeType.RANGED}, "military": 6, "mutation": 1, "fields": ["scorch_throat"], "tags": military, "art_index": 2, "trait": "军阵：首次远程生命伤害施加2咒波。"},
		&"field_priest": {"name": "战地司祭", "base_health": 17, "strength": 1, "agility": 3, "intelligence": 4, "weapon": {"name": "战地圣杖", "damage": 2, "range": 3, "damage_type": CardEnums.DamageType.INTELLIGENCE, "range_type": EquipmentData.WeaponRangeType.RANGED}, "military": 6, "mutation": 1, "fields": ["mud_lung"], "tags": military, "art_index": 3, "trait": "军阵：回合开始治疗相邻军阵友军。"},
		&"punishment_knight": {"name": "刑罚骑士", "base_health": 16, "strength": 4, "agility": 4, "intelligence": 1, "weapon": {"name": "刑罚巨刃", "damage": 4, "range": 1}, "military": 6, "mutation": 2, "fields": ["stampede"], "tags": military, "art_index": 4, "trait": "从军阵开始行动时，下一次移动距离+2。"},
		&"standard_bearer": {"name": "执旗官", "base_health": 17, "strength": 2, "agility": 3, "intelligence": 3, "weapon": {"name": "圣旗辉光", "damage": 2, "range": 2, "damage_type": CardEnums.DamageType.INTELLIGENCE}, "military": 6, "mutation": 1, "fields": ["enlightenment"], "tags": military, "art_index": 5, "trait": "回合开始令一名相邻军阵友军抽1并获得3护甲。"},
		&"holy_bastion_commander": {"name": "圣垒军团长", "rank": EnemyEnums.EnemyRank.ELITE, "base_health": 28, "strength": 4, "agility": 4, "intelligence": 2, "weapon": {"name": "军团长战戟", "damage": 4, "range": 2}, "military": 6, "mutation": 2, "fields": ["empty_eye"], "tags": military + ["commander"], "art_index": 6, "trait": "公开锁定固守或推进；相邻随从提供至多2点伤害减免。"},
		&"creation_shard": {"name": "造物裂片", "base_health": 11, "strength": 3, "agility": 3, "intelligence": 5, "weapon": {"name": "造物射线", "damage": 2, "range": 3, "damage_type": CardEnums.DamageType.INTELLIGENCE, "range_type": EquipmentData.WeaponRangeType.RANGED}, "variant_pools": ["mage", "warlock", "ranger", "monster"], "variant_counts": {"monster": 2}, "tags": ["aberration"], "art_index": 7, "trait": "公开换牌与过载；过载获得+3伤害加值并在行动阶段结束时死亡。"},
		&"blood_construct": {"name": "魔血构造体", "rank": EnemyEnums.EnemyRank.ELITE, "base_health": 14, "strength": 2, "agility": 3, "intelligence": 3, "weapon": {"name": "魔血脉冲", "damage": 2, "range": 2, "damage_type": CardEnums.DamageType.INTELLIGENCE}, "reserve": {"name": "血肉巨爪", "damage": 4, "range": 1}, "military": 4, "variant_pools": ["warlock"], "variant_extra": ["warlock"], "curse_cards": ["res://resources/cards/curse_industry_blood.tres"], "tags": ["aberration"], "art_index": 8, "trait": "可倒转显化、召唤血肉衍生物、吞噬友军并发动往生。"},
		&"corrupt_heart_veil": {"name": "腐心帷幕", "rank": EnemyEnums.EnemyRank.BOSS, "base_health": 126, "strength": 3, "agility": 0, "intelligence": 1, "weapon": {"name": "腐心福音", "damage": 2, "range": 6, "damage_type": CardEnums.DamageType.INTELLIGENCE, "range_type": EquipmentData.WeaponRangeType.RANGED}, "military": 4, "variant_pools": ["warlock"], "variant_counts": {"warlock": 2}, "variant_extra": ["warlock", "warlock"], "curse_cards": ["res://resources/cards/curse_industry_blood.tres", "res://resources/cards/curse_industry_greed.tres", "res://resources/cards/curse_industry_cripple.tres", "res://resources/cards/curse_industry_disease.tres"], "tags": ["boss", "aberration"], "art_index": 9, "trait": "一阶段控制外圈；福音后转入近战二阶段。"},
		&"gray_bastion_paladin": {"name": "灰垒圣骑", "rank": EnemyEnums.EnemyRank.BOSS, "base_health": 45, "strength": 5, "agility": 4, "intelligence": 2, "weapon": {"name": "圣骑重剑", "damage": 4, "range": 1}, "military": 8, "tags": military + ["boss"], "art_index": 10, "trait": "与凯旋圣像共同作战；首次致命伤害后合体。"},
		&"triumph_statue": {"name": "凯旋圣像", "rank": EnemyEnums.EnemyRank.BOSS, "base_health": 40, "strength": 0, "agility": 0, "intelligence": 0, "weapon": {"name": "静默圣徽", "damage": 0, "range": 0}, "tags": ["support", "statue", "boss"], "art_index": 11, "trait": "可攻击但不能行动；圣徽随生命阈值依次熄灭。"},
		&"military_god_remains": {"name": "军神圣骸", "rank": EnemyEnums.EnemyRank.BOSS, "base_health": 60, "strength": 6, "agility": 5, "intelligence": 3, "weapon": {"name": "军神巨刃", "damage": 5, "range": 2}, "reserve": {"name": "圣骸辉光", "damage": 3, "range": 4, "damage_type": CardEnums.DamageType.INTELLIGENCE, "range_type": EquipmentData.WeaponRangeType.RANGED}, "military": 8, "tags": military + ["boss"], "art_index": 10, "trait": "消耗残存圣徽发动一次性奇迹，并可公开切换武器。"},
		&"flesh_spawn": {"name": "血肉衍生物", "base_health": 1, "fixed_max_health": 1, "strength": 2, "agility": 3, "intelligence": 2, "weapon": {"name": "血肉齿爪", "damage": 1, "range": 1}, "tags": ["summon"], "art_index": 8, "trait": "与魔血构造体共享牌库和弃牌堆。"},
	}
	return (specs.get(id, {}) as Dictionary).duplicate(true)
