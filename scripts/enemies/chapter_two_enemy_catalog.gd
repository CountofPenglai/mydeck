extends RefCounted
class_name ChapterTwoEnemyCatalog

const MUTATION_CARDS := ChapterOneEnemyCatalog.MUTATION_CARDS
const REUSED_MONSTER_CARDS := [
	"res://resources/cards/monster_cards/hunker_hide.tres",
	"res://resources/cards/monster_cards/guard_hiss.tres",
	"res://resources/cards/monster_cards/empty_eye.tres",
]
const ENEMY_ART := {
	&"gray_shield_guard": {&"base": {"portrait": "res://assets/art/portraits/chapter_two/gray_shield_guard_portrait.png", "battle": "res://assets/art/battle_units/chapter_two/gray_shield_guard_battle.png"}},
	&"holy_spearman": {&"base": {"portrait": "res://assets/art/portraits/chapter_two/holy_spearman_portrait.png", "battle": "res://assets/art/battle_units/chapter_two/holy_spearman_battle.png"}},
	&"fortress_crossbow": {&"base": {"portrait": "res://assets/art/portraits/chapter_two/fortress_crossbow_portrait.png", "battle": "res://assets/art/battle_units/chapter_two/fortress_crossbow_battle.png"}},
	&"field_priest": {&"base": {"portrait": "res://assets/art/portraits/chapter_two/field_priest_portrait.png", "battle": "res://assets/art/battle_units/chapter_two/field_priest_battle.png"}},
	&"punishment_knight": {&"base": {"portrait": "res://assets/art/portraits/chapter_two/punishment_knight_portrait.png", "battle": "res://assets/art/battle_units/chapter_two/punishment_knight_battle.png"}},
	&"standard_bearer": {&"base": {"portrait": "res://assets/art/portraits/chapter_two/standard_bearer_portrait.png", "battle": "res://assets/art/battle_units/chapter_two/standard_bearer_battle.png"}},
	&"holy_bastion_commander": {&"base": {"portrait": "res://assets/art/portraits/chapter_two/holy_bastion_commander_portrait.png", "battle": "res://assets/art/battle_units/chapter_two/holy_bastion_commander_battle.png"}},
	&"creation_shard": {&"base": {"portrait": "res://assets/art/portraits/chapter_two/creation_shard_portrait.png", "battle": "res://assets/art/battle_units/chapter_two/creation_shard_battle.png"}},
	&"blood_construct": {
		&"base": {"portrait": "res://assets/art/portraits/chapter_two/blood_construct_portrait.png", "battle": "res://assets/art/battle_units/chapter_two/blood_construct_battle.png"},
		&"inverted": {"portrait": "res://assets/art/portraits/chapter_two/blood_construct_inverted_portrait.png", "battle": "res://assets/art/battle_units/chapter_two/blood_construct_inverted_battle.png"},
	},
	&"flesh_spawn": {&"base": {"portrait": "res://assets/art/portraits/chapter_two/flesh_spawn_portrait.png", "battle": "res://assets/art/battle_units/chapter_two/flesh_spawn_battle.png"}},
	&"corrupt_heart_veil": {
		&"base": {"portrait": "res://assets/art/portraits/chapter_two/corrupt_heart_veil_portrait.png", "battle": "res://assets/art/battle_units/chapter_two/corrupt_heart_veil_battle.png"},
		&"phase_two": {"portrait": "res://assets/art/portraits/chapter_two/corrupt_heart_veil_phase_two_portrait.png", "battle": "res://assets/art/battle_units/chapter_two/corrupt_heart_veil_phase_two_battle.png"},
	},
	&"gray_bastion_paladin": {&"base": {"portrait": "res://assets/art/portraits/chapter_two/gray_bastion_paladin_portrait.png", "battle": "res://assets/art/battle_units/chapter_two/gray_bastion_paladin_battle.png"}},
	&"triumph_statue": {&"base": {"portrait": "res://assets/art/portraits/chapter_two/triumph_statue_portrait.png", "battle": "res://assets/art/battle_units/chapter_two/triumph_statue_battle.png"}},
	&"military_god_remains": {&"base": {"portrait": "res://assets/art/portraits/chapter_two/military_god_remains_portrait.png", "battle": "res://assets/art/battle_units/chapter_two/military_god_remains_battle.png"}},
}

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
	data.ai_profile = EnemyTacticalCardCatalog.create_profile(int(spec.get("ai_profile", EnemyAIProfile.Preset.BALANCED)))
	data.behavior = TacticalEnemyBehavior.new()
	data.behavior.behavior_label = "第二章公开意图"
	data.portrait = get_art_texture(archetype, "portrait")
	data.battle_sprite = get_art_texture(archetype, "battle")
	var state := EnemyState.new()
	state.enemy_data = data
	if spec.has("fixed_max_health"):
		state.runtime_state["max_health_override"] = int(spec.fixed_max_health)
	state.generate_deck(seed)
	state.current_health = state.get_max_health()
	return state


static func get_art_texture(
		archetype: StringName,
		art_kind: String,
		variant: StringName = &"base"
) -> Texture2D:
	if art_kind != "portrait" and art_kind != "battle":
		return null
	var variants := ENEMY_ART.get(archetype, {}) as Dictionary
	if variants.is_empty():
		return null
	var selected := variants.get(variant, variants.get(&"base", {})) as Dictionary
	var path := str(selected.get(art_kind, ""))
	if path.is_empty():
		return null
	var resource := ResourceLoader.load(path)
	return resource as Texture2D if resource is Texture2D else null


static func apply_art_variant(state: EnemyState, variant: StringName) -> bool:
	if state == null or state.enemy_data == null:
		return false
	var variants := ENEMY_ART.get(state.enemy_data.archetype_id, {}) as Dictionary
	if not variants.has(variant):
		return false
	var portrait := get_art_texture(state.enemy_data.archetype_id, "portrait", variant)
	var battle := get_art_texture(state.enemy_data.archetype_id, "battle", variant)
	if portrait == null or battle == null:
		return false
	state.enemy_data.portrait = portrait
	state.enemy_data.battle_sprite = battle
	state.runtime_state["art_variant"] = variant
	return true


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
		"使用者对所有其他存活单位分别造成基础伤害 6 的智力伤害。每名实际受到正数伤害的单位获得 1 点咒波，并将 1 张辐照咒害洗入其牌库。然后使用者进入第二阶段：力量改为 6、敏捷改为 3、智力改为 1、生命上限改为 169、武器基础伤害改为 5、攻击范围改为 2，并将当前 AP 改为 0；当前生命不会因生命上限变化而回复。",
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
	rule.tactical_entries.append(EnemyTacticalCardCatalog.create_entry(runtime_card))


static func _make_card_slot(label: String, count: int, cards: Array) -> EnemyDeckSlot:
	var slot := EnemyDeckSlot.new()
	slot.slot_label = label
	slot.pick_count = mini(count, cards.size())
	for card in cards:
		var entry := EnemyTacticalCardCatalog.create_entry(card)
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
		_make_card("列阵推进", "使用者向目标移动至多 1 格；若处于军阵，改为至多 2 格。移动后若目标仍存活且位于当前武器范围内，对其进行一次武器打击。", 1, CardEnums.TargetType.SINGLE, CardEnums.CardType.ATTACK, CardEnums.DamageType.STRENGTH, ChapterTwoEnemyCardEffect.Kind.FORMATION_ADVANCE, 4),
		_make_card("盾墙", "使用者获得 4 护甲；若处于军阵，改为获得 6 护甲。", 1, CardEnums.TargetType.SELF, CardEnums.CardType.SKILL, CardEnums.DamageType.STRENGTH, ChapterTwoEnemyCardEffect.Kind.SHIELD_WALL),
		_make_card("协同突刺", "使用者对目标进行一次武器打击；若处于军阵，该打击获得 +2 伤害加值。", 2, CardEnums.TargetType.SINGLE, CardEnums.CardType.ATTACK, CardEnums.DamageType.STRENGTH, ChapterTwoEnemyCardEffect.Kind.COORDINATED_THRUST, 4),
		_make_card("要塞齐射", "使用者对目标造成 3 点敏捷伤害。若造成正数伤害，向目标施加 1 点咒波；若使用者处于军阵，改为 2 点咒波。", 2, CardEnums.TargetType.SINGLE, CardEnums.CardType.ATTACK, CardEnums.DamageType.AGILITY, ChapterTwoEnemyCardEffect.Kind.FORTRESS_VOLLEY, 4),
		_make_card("整队号令", "目标友方单位获得 3 护甲并抽 1 张牌；若使用者处于军阵，改为获得 5 护甲。", 1, CardEnums.TargetType.SINGLE, CardEnums.CardType.SKILL, CardEnums.DamageType.INTELLIGENCE, ChapterTwoEnemyCardEffect.Kind.RALLY_LINE, 3),
		_make_card("强行军", "使使用者下一次非强制移动的移动距离 +1；若处于军阵，改为 +2。该加值在完成该次移动后移除，未移动时不会到期。", 1, CardEnums.TargetType.SELF, CardEnums.CardType.SKILL, CardEnums.DamageType.AGILITY, ChapterTwoEnemyCardEffect.Kind.FORCED_MARCH),
		_make_card("刑罚令", "使用者对目标进行一次武器打击；若目标当前拥有咒波，该打击获得 +2 伤害加值。", 2, CardEnums.TargetType.SINGLE, CardEnums.CardType.ATTACK, CardEnums.DamageType.STRENGTH, ChapterTwoEnemyCardEffect.Kind.PUNITIVE_ORDER, 4),
		_make_card("公开戒备", "使用者获得 2 护甲，然后将本牌从手牌移入附魔区。", 1, CardEnums.TargetType.SELF, CardEnums.CardType.ENCHANTMENT, CardEnums.DamageType.STRENGTH, ChapterTwoEnemyCardEffect.Kind.WATCHFUL_STANCE),
	]


static func _variant_cards() -> Dictionary:
	return {
		"mage": [
			_make_card("裂片·秘法弹", "使用者对目标造成 3 点智力伤害。", 1, CardEnums.TargetType.SINGLE, CardEnums.CardType.ATTACK, CardEnums.DamageType.INTELLIGENCE, ChapterTwoEnemyCardEffect.Kind.ARC_BOLT, 4),
			_make_card("裂片·秘法护盾", "使用者获得 5 护甲。", 1, CardEnums.TargetType.SELF, CardEnums.CardType.SKILL, CardEnums.DamageType.INTELLIGENCE, ChapterTwoEnemyCardEffect.Kind.ARCANE_WARD),
		],
		"warlock": [
			_make_card("裂片·血咒", "使用者对目标造成 2 点智力伤害；若造成正数伤害，向目标施加 2 点咒波。", 1, CardEnums.TargetType.SINGLE, CardEnums.CardType.ATTACK, CardEnums.DamageType.INTELLIGENCE, ChapterTwoEnemyCardEffect.Kind.BLOOD_HEX, 4),
			_make_card("裂片·黑暗交易", "使用者先失去 2 生命，然后抽 2 张牌。", 0, CardEnums.TargetType.SELF, CardEnums.CardType.SKILL, CardEnums.DamageType.INTELLIGENCE, ChapterTwoEnemyCardEffect.Kind.DARK_BARGAIN),
		],
		"ranger": [
			_make_card("裂片·闪避步", "使用者向远离最近敌人的方向移动至多 2 格，然后获得 2 护甲。没有存活敌人或没有更远的可用格时不移动，但仍获得护甲。", 1, CardEnums.TargetType.SELF, CardEnums.CardType.SKILL, CardEnums.DamageType.AGILITY, ChapterTwoEnemyCardEffect.Kind.EVASIVE_STEP),
			_make_card("裂片·瞄准射击", "使用者对目标造成 4 点敏捷伤害。", 2, CardEnums.TargetType.SINGLE, CardEnums.CardType.ATTACK, CardEnums.DamageType.AGILITY, ChapterTwoEnemyCardEffect.Kind.AIMED_SHOT, 5),
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
	return weapon


static func _get_spec(id: StringName) -> Dictionary:
	var military := ["military"]
	var specs := {
		&"gray_shield_guard": {"name": "灰垒盾卫", "base_health": 21, "strength": 4, "agility": 3, "intelligence": 2, "weapon": {"name": "灰垒重盾", "damage": 3, "range": 1}, "military": 6, "mutation": 1, "fields": ["rock_scale"], "tags": military, "ai_profile": EnemyAIProfile.Preset.LOW_HEALTH_GUARD, "art_index": 0, "trait": "回合开始时，若灰垒盾卫处于军阵，获得 4 护甲。"},
		&"holy_spearman": {"name": "圣枪兵", "base_health": 16, "strength": 4, "agility": 5, "intelligence": 2, "weapon": {"name": "圣垒长枪", "damage": 4, "range": 2}, "military": 6, "mutation": 1, "fields": ["lashing"], "tags": military, "art_index": 1, "trait": "每回合第一次武器打击结算前，若圣枪兵处于军阵，且目标与圣枪兵的距离等于其当前攻击范围，该打击获得 +2 伤害加值。无论是否满足条件，本回合后续武器打击均不再触发。"},
		&"fortress_crossbow": {"name": "要塞弩手", "base_health": 17, "strength": 2, "agility": 6, "intelligence": 3, "weapon": {"name": "要塞重弩", "damage": 4, "range": 4, "damage_type": CardEnums.DamageType.AGILITY, "range_type": EquipmentData.WeaponRangeType.RANGED}, "military": 6, "mutation": 1, "fields": ["scorch_throat"], "tags": military, "ai_profile": EnemyAIProfile.Preset.RANGED_CONTROL, "art_index": 2, "trait": "每个自身回合至多一次，要塞弩手在军阵中造成正数伤害后，向该次伤害的目标施加 2 点咒波。离开军阵时造成的伤害不会消耗本回合次数。"},
		&"field_priest": {"name": "战地司祭", "base_health": 19, "strength": 2, "agility": 4, "intelligence": 5, "weapon": {"name": "战地圣杖", "damage": 3, "range": 3, "damage_type": CardEnums.DamageType.INTELLIGENCE, "range_type": EquipmentData.WeaponRangeType.RANGED}, "military": 6, "mutation": 1, "fields": ["mud_lung"], "tags": military, "art_index": 3, "trait": "回合开始时，若战地司祭处于军阵，使每名与其相邻的存活军事友军回复 2 生命。没有合法友军时不执行。"},
		&"punishment_knight": {"name": "刑罚骑士", "base_health": 20, "strength": 5, "agility": 5, "intelligence": 2, "weapon": {"name": "刑罚巨刃", "damage": 5, "range": 1}, "military": 6, "mutation": 2, "fields": ["stampede"], "tags": military, "ai_profile": EnemyAIProfile.Preset.LOW_HEALTH_BERSERK, "art_index": 4, "trait": "回合开始时，若刑罚骑士处于军阵，使其下一次非强制移动的移动距离 +2。该加值在完成该次移动后移除；未移动时不会自动到期。"},
		&"standard_bearer": {"name": "执旗官", "base_health": 20, "strength": 3, "agility": 4, "intelligence": 4, "weapon": {"name": "圣旗辉光", "damage": 3, "range": 2, "damage_type": CardEnums.DamageType.INTELLIGENCE}, "military": 6, "mutation": 1, "fields": ["enlightenment"], "tags": military, "art_index": 5, "trait": "回合开始时，从相邻的存活军事友军中选择当前生命最低的一名；该友军获得 3 护甲并抽 1 张牌。没有合法友军时不执行。"},
		&"holy_bastion_commander": {"name": "圣垒军团长", "rank": EnemyEnums.EnemyRank.ELITE, "base_health": 35, "strength": 5, "agility": 5, "intelligence": 3, "weapon": {"name": "军团长战戟", "damage": 5, "range": 2}, "military": 6, "mutation": 2, "fields": ["empty_eye"], "tags": military + ["commander"], "art_index": 6, "trait": "锁定意图时，圣垒军团长依战斗轮次交替公开“固守”或“推进”，并在下次行动开始时先执行。固守：军团长及所有处于军阵的存活军事友军各获得 4 护甲。推进：这些单位的下一次移动距离加值至少变为 +1，并使其下一次攻击获得 +2 伤害加值。每有一名与军团长相邻的存活军事友军，军团长获得 1 点伤害减免，至多 2 点。"},
		&"creation_shard": {"name": "造物裂片", "base_health": 13, "strength": 4, "agility": 4, "intelligence": 6, "weapon": {"name": "造物射线", "damage": 3, "range": 3, "damage_type": CardEnums.DamageType.INTELLIGENCE, "range_type": EquipmentData.WeaponRangeType.RANGED}, "variant_pools": ["mage", "warlock", "ranger", "monster"], "variant_counts": {"monster": 2}, "tags": ["aberration"], "art_index": 7, "trait": "每次行动开始时，造物裂片随机放逐 1 张手牌，然后随机生成 1 张怪物化职业牌并加入手牌；没有手牌时不执行换牌。锁定意图时若当前生命不高于生命上限的一半，先进入过载：本回合获得 +3 伤害加值，并在回合结束时失去等同于当前生命的生命。"},
		&"blood_construct": {"name": "魔血构造体", "rank": EnemyEnums.EnemyRank.ELITE, "base_health": 16, "strength": 3, "agility": 4, "intelligence": 4, "weapon": {"name": "魔血脉冲", "damage": 3, "range": 2, "damage_type": CardEnums.DamageType.INTELLIGENCE}, "reserve": {"name": "血肉巨爪", "damage": 5, "range": 1}, "military": 4, "variant_pools": ["warlock"], "variant_extra": ["warlock"], "curse_cards": ["res://resources/cards/curse_industry_blood.tres"], "tags": ["aberration"], "art_index": 8, "trait": "魔血构造体每打出一张诅咒牌，获得 2 点咒波。正位且拥有咒波时，优先消耗全部咒波并倒转：切换为血肉巨爪，将力量改为 4、敏捷改为 1、智力改为 4，并按消耗前咒波显化至多 4 张临时畸变牌。正位、生命高于 5 且战场上没有存活血肉衍生物时，尝试在相邻空格召唤血肉衍生物；成功时失去 5 生命，没有空格时不失去生命且不召唤。逆位时，若有相邻存活非首领友军，优先吞噬单位列表中的第一名：目标死亡，构造体的生命上限和当前生命各提高目标原当前生命，并永久获得等同于目标当前武器基础伤害的伤害加值。逆位、咒波为 0、没有吞噬目标且本场尚未发动往生时，回复 10 生命，将 1 张血之业洗入牌库；往生每场战斗限一次。"},
		&"corrupt_heart_veil": {"name": "腐心帷幕", "rank": EnemyEnums.EnemyRank.BOSS, "base_health": 157, "strength": 4, "agility": 1, "intelligence": 2, "weapon": {"name": "腐心福音", "damage": 3, "range": 6, "damage_type": CardEnums.DamageType.INTELLIGENCE, "range_type": EquipmentData.WeaponRangeType.RANGED}, "military": 4, "variant_pools": ["warlock"], "variant_counts": {"warlock": 2}, "variant_extra": ["warlock", "warlock"], "curse_cards": ["res://resources/cards/curse_industry_blood.tres", "res://resources/cards/curse_industry_greed.tres", "res://resources/cards/curse_industry_cripple.tres", "res://resources/cards/curse_industry_disease.tres"], "tags": ["boss", "aberration"], "art_index": 9, "trait": "第一阶段中，腐心帷幕由第二章怪物牌直接造成的属性伤害改为攻击距离自身超过 1 格的所有其他存活单位；每名实际受到正数伤害的单位额外获得 2 点咒波。第一阶段回合结束时，将所有相邻冒险者推开至多 3 格；从第 3 轮起标记福音，并在下次行动开始时先结算福音。福音结算后进入第二阶段。第二阶段回合开始时，将最远的冒险者拉近至多 3 格；并列时优先当前生命较低、行动顺序较早者。腐心帷幕每次造成正数伤害后，对该行动中的每个目标至多触发一次额外固定伤害，数值等于目标当前咒波且不消耗咒波。第二阶段回合结束时，对距离 2 内每名冒险者造成等同于其诅咒区牌数的固定伤害。"},
		&"gray_bastion_paladin": {"name": "灰垒圣骑", "rank": EnemyEnums.EnemyRank.BOSS, "base_health": 57, "strength": 6, "agility": 5, "intelligence": 3, "weapon": {"name": "圣骑重剑", "damage": 5, "range": 1}, "military": 8, "tags": military + ["boss"], "art_index": 10, "trait": "战斗开始时拥有杯、盾、翼、剑 4 枚圣徽：杯使回合结束回复 4 生命；盾提供 2 点伤害减免；翼使最大 AP 和移动距离各 +1；剑使每回合第一次武器打击获得 +3 伤害加值。凯旋圣像生命降至 38、25、13、0 时依次移除杯、盾、翼、剑。灰垒圣骑首次受到致命伤害时保留 1 生命并排队合体；结算时若仍存活，清除原状态、护甲和全部牌区，变为军神圣骸并继承剩余圣徽。其当前生命和生命上限改为 75 加仍存活圣像的当前生命；若圣像对象仍存在，则移动到其所在格并移除圣像，没有圣像时原地变身。"},
		&"triumph_statue": {"name": "凯旋圣像", "rank": EnemyEnums.EnemyRank.BOSS, "base_health": 47, "strength": 1, "agility": 1, "intelligence": 1, "weapon": {"name": "静默圣徽", "damage": 1, "range": 0}, "tags": ["support", "statue", "boss"], "art_index": 11, "trait": "凯旋圣像可以成为攻击目标，但不进入行动顺序。每次受到伤害后，生命降至 38、25、13、0 时分别熄灭灰垒圣骑的杯、盾、翼、剑圣徽；一次伤害跨越多个阈值时，依次熄灭所有被跨越的圣徽。"},
		&"military_god_remains": {"name": "军神圣骸", "rank": EnemyEnums.EnemyRank.BOSS, "base_health": 77, "strength": 7, "agility": 6, "intelligence": 4, "weapon": {"name": "军神巨刃", "damage": 6, "range": 2}, "reserve": {"name": "圣骸辉光", "damage": 4, "range": 4, "damage_type": CardEnums.DamageType.INTELLIGENCE, "range_type": EquipmentData.WeaponRangeType.RANGED}, "military": 8, "tags": military + ["boss"], "art_index": 10, "trait": "每次行动开始时，若仍有圣徽，按杯、盾、翼、剑的剩余顺序消耗 1 枚并发动对应奇迹：杯回复 12 生命；盾获得 12 护甲；翼向最近冒险者移动至多 3 格，然后将所有相邻冒险者推开 1 格；剑使用当前武器依次打击攻击范围内的所有存活冒险者。奇迹没有合法目标时仍消耗圣徽。奇迹结算后，军神圣骸在军神巨刃与圣骸辉光之间切换武器。"},
		&"flesh_spawn": {"name": "血肉衍生物", "base_health": 2, "fixed_max_health": 2, "strength": 3, "agility": 4, "intelligence": 3, "weapon": {"name": "血肉齿爪", "damage": 2, "range": 1}, "tags": ["summon"], "art_index": 8, "trait": "由魔血构造体召唤时，血肉衍生物拥有固定 2 点生命上限，与召唤者共享牌库和弃牌堆，但拥有独立手牌；召唤后从共享牌库抽 2 张牌。"},
	}
	return (specs.get(id, {}) as Dictionary).duplicate(true)
