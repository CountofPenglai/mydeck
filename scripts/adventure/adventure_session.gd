extends Node
class_name AdventureSessionService

const CurseCatalog = preload("res://scripts/curses/curse_catalog.gd")

signal state_changed
signal status_message(message: String)

const MAP_SCENE_PATH := "res://scenes/adventure_map_scene.tscn"
const BATTLE_SCENE_PATH := "res://scenes/battle_scene.tscn"
const HERO_PATHS := [
	"res://resources/characters/battle_warrior_state.tres",
	"res://resources/characters/battle_ranger_state.tres",
	"res://resources/characters/battle_druid_state.tres",
]
const ORDINARY_CURSE_PATHS := CurseCatalog.ORDINARY_PATHS

var current_run: PartyRunState
var definition := AdventureDefinition.new()
var map_generator := AdventureMapGenerator.new()
var save_store := AdventureSaveStore.new()
var reward_service := AdventureRewardService.new()
var pending_battle_scenario: BattleScenario


func _ready() -> void:
	definition.floor_count = 2
	current_run = save_store.load_run()
	if current_run != null and current_run.pending_transaction != null \
		and current_run.pending_transaction.transaction_type == AdventureEnums.TransactionType.BATTLE:
		_rebuild_pending_battle_scenario()


func ensure_run() -> PartyRunState:
	if current_run == null:
		start_new_demo()
	return current_run


func start_new_demo(seed_value: int = 0) -> PartyRunState:
	var resolved_seed := seed_value
	if resolved_seed == 0:
		var seed_rng := RandomNumberGenerator.new()
		seed_rng.randomize()
		resolved_seed = seed_rng.randi()
	var heroes: Array[CharacterState] = []
	for path in HERO_PATHS:
		var template := load(path) as CharacterState
		if template == null:
			continue
		var hero := template.duplicate(true) as CharacterState
		hero.adventure_source_path = path
		hero.ensure_initialized()
		hero.current_health = hero.get_max_health()
		heroes.append(hero)
	current_run = PartyRunState.new()
	current_run.initialize_adventure(resolved_seed, heroes, definition)
	current_run.floor_state = map_generator.generate(resolved_seed, 0, definition)
	pending_battle_scenario = null
	_save_and_emit("新的两层冒险已生成。")
	return current_run


func restart_same_seed() -> void:
	var seed_value := current_run.run_seed if current_run != null else 0
	start_new_demo(seed_value)


func equip_inventory_item(hero_id: String, stack_id: String, slot: String) -> Dictionary:
	if _loadout_change_is_blocked():
		return _failure("战斗或奖励结算期间不能更换装备。")
	var hero := _get_hero(hero_id)
	if hero == null:
		return _failure("没有找到要整理装备的角色。")
	hero.ensure_adventure_instance_ids()
	var result := CharacterEquipmentModel.equip_inventory_stack_to_slot(hero, stack_id, slot)
	if not bool(result.get("success", false)):
		return _failure(str(result.get("message", "换装失败。")))
	_save_and_emit("%s：%s" % [hero.get_character_name(), str(result.get("message", "换装完成。"))])
	return {"ok": true, "message": result.get("message", ""), "result": result}


func unequip_item(hero_id: String, slot: String) -> Dictionary:
	if _loadout_change_is_blocked():
		return _failure("战斗或奖励结算期间不能更换装备。")
	var hero := _get_hero(hero_id)
	if hero == null:
		return _failure("没有找到要整理装备的角色。")
	hero.ensure_adventure_instance_ids()
	var result := CharacterEquipmentModel.unequip_slot_to_inventory(hero, slot)
	if not bool(result.get("success", false)):
		return _failure(str(result.get("message", "卸装失败。")))
	_save_and_emit("%s：%s" % [hero.get_character_name(), str(result.get("message", "卸装完成。"))])
	return {"ok": true, "message": result.get("message", ""), "result": result}


func sort_inventory(hero_id: String) -> Dictionary:
	if _loadout_change_is_blocked():
		return _failure("战斗或奖励结算期间不能整理背包。")
	var hero := _get_hero(hero_id)
	if hero == null:
		return _failure("没有找到要整理背包的角色。")
	hero.ensure_adventure_instance_ids()
	if not CharacterEquipmentModel.sort_inventory(hero):
		return _failure("整理背包失败。")
	_save_and_emit("%s 的背包已按装备位和品质整理。" % hero.get_character_name())
	return {"ok": true, "message": "背包整理完成。"}


func transfer_inventory_item(source_id: String, stack_id: String, target_id: String) -> Dictionary:
	if _loadout_change_is_blocked():
		return _failure("战斗或奖励结算期间不能转交装备。")
	var source := _get_hero(source_id)
	var target := _get_hero(target_id)
	if source == null or target == null:
		return _failure("没有找到装备的持有者或接收者。")
	source.ensure_adventure_instance_ids()
	target.ensure_adventure_instance_ids()
	var result := CharacterEquipmentModel.transfer_inventory_stack(source, target, stack_id)
	if not bool(result.get("success", false)):
		return _failure(str(result.get("message", "转交装备失败。")))
	_save_and_emit(str(result.get("message", "装备已转交。")))
	return {"ok": true, "message": result.get("message", ""), "result": result}


func set_enemy_health_percent(value: int) -> bool:
	var run := ensure_run()
	var resolved_value := clampi(value, 1, 1000)
	if run.enemy_health_percent == resolved_value:
		return true
	run.enemy_health_percent = resolved_value
	_save_and_emit("测试设置：后续战斗的怪物生命为 %d%%。" % resolved_value)
	return true


func request_move(target_room_id: String) -> Dictionary:
	var run := ensure_run()
	if run.run_complete or run.run_failed or run.floor_state == null:
		return _failure("本次冒险已经结束。")
	if has_pending_reward() or has_pending_event_reward():
		return _failure("请先完成当前奖励选择。")
	if run.pending_transaction != null and not run.pending_transaction.committed:
		return _failure("当前仍有未完成的冒险事务。")
	var floor := run.floor_state
	if not floor.are_connected(floor.current_room_id, target_room_id):
		return _failure("只能移动到相邻且有道路连接的房间。")
	var target := floor.get_room(target_room_id)
	if target == null:
		return _failure("目标房间不存在。")
	var move_serial := int(run.adventure_flags.get("move_serial", 0)) + 1
	run.adventure_flags["move_serial"] = move_serial
	var ambush_triggered := false
	var shown_chance := 0
	run.begin_transaction(AdventureEnums.TransactionType.MOVE, "move_%d" % move_serial, {
		"from": floor.current_room_id,
		"to": target_room_id,
		"move_serial": move_serial,
	})
	_save_only()
	if run.provisions > 0:
		run.spend_provision()
	else:
		shown_chance = 20 if floor.ambush_chance <= 0 else floor.ambush_chance
		if floor.watch_protection:
			floor.watch_protection = false
			floor.ambush_chance = 40
		else:
			var rng := RandomNumberGenerator.new()
			rng.seed = AdventureMapGenerator.derive_seed(run.run_seed, "ambush", move_serial + run.floor_index * 10000)
			ambush_triggered = rng.randi_range(1, 100) <= shown_chance
			floor.ambush_chance = 20 if ambush_triggered else mini(80, shown_chance + 20)
	floor.current_room_id = target_room_id
	target.visited = true
	target.content_revealed = true
	_initialize_room_runtime(target)
	if ambush_triggered:
		_prepare_battle_transaction(target, true, AdventureEnums.EncounterTier.AMBUSH)
		_save_and_emit("绝境行军触发了伏击。")
		return {"ok": true, "ambush": true, "chance": shown_chance, "room": target}
	run.commit_transaction()
	_save_and_emit("抵达%s。" % target.get_display_name())
	return {"ok": true, "ambush": false, "chance": shown_chance, "room": target}


func get_current_encounter_tier() -> int:
	var run := ensure_run()
	if run.floor_state == null:
		return AdventureEnums.EncounterTier.WEAK
	var victories := run.floor_state.normal_battle_victories
	if victories < 2:
		return AdventureEnums.EncounterTier.WEAK
	if victories < 4:
		return AdventureEnums.EncounterTier.MIXED
	return AdventureEnums.EncounterTier.STRONG


func start_current_battle() -> bool:
	var run := ensure_run()
	var room := run.floor_state.get_current_room() if run.floor_state != null else null
	if room == null or not room.is_combat_room() or room.completed:
		return false
	var tier := get_current_encounter_tier()
	if room.room_type == AdventureEnums.RoomType.ELITE_BATTLE:
		tier = AdventureEnums.EncounterTier.ELITE
	elif room.room_type == AdventureEnums.RoomType.BOSS_BATTLE:
		tier = AdventureEnums.EncounterTier.BOSS
	_prepare_battle_transaction(room, false, tier)
	return _enter_pending_battle_scene()


func start_event_battle(event_id: String) -> bool:
	var run := ensure_run()
	var room := run.floor_state.get_current_room() if run.floor_state != null else null
	if room == null or room.room_type != AdventureEnums.RoomType.EVENT or room.completed:
		return false
	_prepare_battle_transaction(room, false, AdventureEnums.EncounterTier.ELITE, {
		"event_id": event_id,
		"event_battle": true,
	})
	return _enter_pending_battle_scene()


func resume_pending_battle() -> bool:
	if current_run == null or current_run.pending_transaction == null \
		or current_run.pending_transaction.transaction_type != AdventureEnums.TransactionType.BATTLE:
		return false
	if pending_battle_scenario == null:
		_rebuild_pending_battle_scenario()
	return _enter_pending_battle_scene()


func restart_pending_battle() -> bool:
	if current_run == null or current_run.pending_transaction == null \
			or current_run.pending_transaction.transaction_type != AdventureEnums.TransactionType.BATTLE:
		return false
	_rebuild_pending_battle_scenario()
	return _enter_pending_battle_scene()


func consume_pending_battle_scenario() -> BattleScenario:
	return pending_battle_scenario


func has_pending_battle() -> bool:
	return current_run != null and current_run.pending_transaction != null \
		and current_run.pending_transaction.transaction_type == AdventureEnums.TransactionType.BATTLE \
		and not current_run.pending_transaction.committed


func pending_battle_grants_reward() -> bool:
	if not has_pending_battle():
		return false
	var payload := current_run.pending_transaction.payload
	return not bool(payload.get("ambush", false)) and not bool(payload.get("event_battle", false)) \
		and current_run.floor_state != null \
		and current_run.floor_state.get_room(str(payload.get("room_id", ""))) != null


func complete_pending_battle(result: BattleResult) -> void:
	if not resolve_pending_battle_result(result):
		return
	get_tree().change_scene_to_file(MAP_SCENE_PATH)


func resolve_pending_battle_result(result: BattleResult) -> bool:
	if result == null or current_run == null or current_run.pending_transaction == null:
		return false
	var transaction := current_run.pending_transaction
	if transaction.transaction_type != AdventureEnums.TransactionType.BATTLE:
		return transaction.transaction_type == AdventureEnums.TransactionType.REWARD and has_pending_reward()
	var payload := transaction.payload
	var room := current_run.floor_state.get_room(str(payload.get("room_id", ""))) \
		if current_run.floor_state != null else null
	var is_ambush := bool(payload.get("ambush", false))
	var event_battle := bool(payload.get("event_battle", false))
	pending_battle_scenario = null
	if not result.victory:
		current_run.run_failed = true
		current_run.commit_transaction()
		_save_only()
		return true
	for hero in current_run.party:
		if hero != null and result.downed_hero_ids.has(hero.adventure_character_id):
			hero.current_health = 1
	if is_ambush:
		current_run.commit_transaction()
	elif event_battle:
		_complete_event_battle(str(payload.get("event_id", "")), room)
		current_run.commit_transaction()
	elif room != null:
		room.completed = true
		if room.room_type == AdventureEnums.RoomType.NORMAL_BATTLE:
			current_run.floor_state.normal_battle_victories += 1
		var tier := int(payload.get("encounter_tier", AdventureEnums.EncounterTier.WEAK))
		var reward := reward_service.create_battle_reward(current_run, room, tier)
		if str(payload.get("encounter_id", "")) == "corrupt_heart_veil_boss":
			reward["gospel_offer"] = true
			reward["gospel_receiver"] = ""
			reward["gospel_declined"] = false
		_apply_fixed_reward(room, reward)
		current_run.adventure_flags["pending_reward"] = reward
		current_run.begin_transaction(AdventureEnums.TransactionType.REWARD, "reward_%s" % room.room_id, {"room_id": room.room_id})
	else:
		current_run.commit_transaction()
	_save_only()
	return true


func has_pending_reward() -> bool:
	if current_run == null:
		return false
	var reward = current_run.adventure_flags.get("pending_reward", {})
	return reward is Dictionary and not (reward as Dictionary).is_empty() and not bool((reward as Dictionary).get("settled", false))


func get_pending_reward() -> Dictionary:
	if not has_pending_reward():
		return {}
	return (current_run.adventure_flags.get("pending_reward", {}) as Dictionary).duplicate(true)


func has_pending_event_reward() -> bool:
	if current_run == null:
		return false
	var reward = current_run.adventure_flags.get("pending_event_reward", {})
	return reward is Dictionary and not (reward as Dictionary).is_empty()


func get_pending_event_reward() -> Dictionary:
	if not has_pending_event_reward():
		return {}
	return (current_run.adventure_flags.get("pending_event_reward", {}) as Dictionary).duplicate(true)


func claim_pending_event_reward(action_id: String, hero_id: String, candidate_id: String = "") -> Dictionary:
	if not has_pending_event_reward():
		return _failure("当前没有待选择的事件奖励。")
	var reward := current_run.adventure_flags["pending_event_reward"] as Dictionary
	var hero := _get_hero(hero_id)
	if hero == null:
		return _failure("请选择奖励接收者。")
	match action_id:
		"sealed_reliquary":
			var result := _grant_event_item(hero, "res://resources/items/sealed_reliquary.tres", "sealed_reliquary")
			if not bool(result.get("ok", false)):
				return result
			return _finish_pending_event_reward("%s 获得「封印圣匣」：装备后负荷上限 +1，每场首次打出诅咒牌获得 4 护甲。" % hero.get_character_name())
		"arcanist_load":
			hero.curse_load_limit_bonus += 2
			return _finish_pending_event_reward("%s 获得本次冒险负荷上限 +2，当前上限为 %d。" % [hero.get_character_name(), hero.get_curse_load_limit()])
		"arcanist_pendant":
			var result := _grant_event_item(hero, "res://resources/items/arcane_pendant.tres", "arcane_pendant")
			if not bool(result.get("ok", false)):
				return result
			return _finish_pending_event_reward("%s 获得「奥能坠饰」：装备后智力 +2。" % hero.get_character_name())
		"remains_curse":
			if _get_available_curse_capacity(hero) < 1:
				return _failure("%s 无法再承担普通业。" % hero.get_character_name())
			_add_random_curse(hero, int(reward.get("curse_salt", 0)))
			return _finish_pending_event_reward("掷骰结果为 %d；%s 获得 1 个随机普通业，当前负荷 %d/%d。" % [int(reward.get("roll", 6)), hero.get_character_name(), hero.get_curse_load(), hero.get_curse_load_limit()])
		"equipment":
			if not str(reward.get("claimed_equipment", "")).is_empty():
				return _failure("已经选择过装备奖励。")
			var candidate := _find_reward_candidate(reward.get("equipment", []) as Array, candidate_id)
			if candidate.is_empty():
				return _failure("所选装备不在本次候选中。")
			var result := _grant_event_item(hero, str(candidate.get("path", "")), "event_equipment_%s" % candidate_id)
			if not bool(result.get("ok", false)):
				return result
			current_run.mark_equipment_reward_drawn(str(candidate.get("path", "")))
			reward["claimed_equipment"] = candidate_id
			reward["equipment_receiver"] = hero_id
			_save_and_emit("%s 获得装备「%s」。" % [hero.get_character_name(), str(candidate.get("name", "装备"))])
			return {"ok": true, "message": "装备选择已锁定。"}
		"card":
			var claimed_cards := reward.get("claimed_cards", {}) as Dictionary
			if claimed_cards.has(hero_id):
				return _failure("%s 已经选择过职业牌。" % hero.get_character_name())
			var candidate := _find_reward_candidate(reward.get("cards", []) as Array, candidate_id)
			if candidate.is_empty() or str(candidate.get("hero_id", "")) != hero_id:
				return _failure("该卡牌不属于所选角色的候选。")
			var stack := reward_service.create_card_stack(
				str(candidate.get("path", "")),
				"%s_event_reward_%s" % [hero_id, candidate_id],
				hero.character_data.character_class
			)
			if stack == null:
				return _failure("所选卡牌资源无效。")
			hero.deck.append(stack)
			claimed_cards[hero_id] = candidate_id
			reward["claimed_cards"] = claimed_cards
			_save_and_emit("%s 获得卡牌「%s」。" % [hero.get_character_name(), str(candidate.get("name", "卡牌"))])
			return {"ok": true, "message": "卡牌选择已锁定。"}
	return _failure("未知的事件奖励选择。")


func settle_pending_event_reward() -> Dictionary:
	if not has_pending_event_reward():
		return _failure("当前没有待结算的事件奖励。")
	var reward := current_run.adventure_flags["pending_event_reward"] as Dictionary
	if int(reward.get("required_equipment", 0)) > 0 and str(reward.get("claimed_equipment", "")).is_empty():
		return _failure("请先选择 1 件装备。")
	var required_hero_ids := reward.get("required_card_hero_ids", []) as Array
	var claimed_cards := reward.get("claimed_cards", {}) as Dictionary
	for hero_id_value in required_hero_ids:
		if not claimed_cards.has(str(hero_id_value)):
			return _failure("请为每名冒险者各选择 1 张职业牌。")
	var starts_battle := bool(reward.get("starts_battle", false))
	var room := current_run.floor_state.get_room(str(reward.get("room_id", ""))) if current_run.floor_state != null else null
	if bool(reward.get("remains_delivery", false)):
		_remove_adventurer_remains_item()
		current_run.adventure_flags.erase("adventurer_remains")
		current_run.adventure_flags.erase("adventurer_remains_carrier")
	current_run.adventure_flags.erase("pending_event_reward")
	if starts_battle:
		_save_only()
		if start_event_battle(str(reward.get("event_id", ""))):
			return {"ok": true, "battle": true, "message": "混乱之门的奖励已经锁定，强制战斗开始。"}
		current_run.adventure_flags["pending_event_reward"] = reward
		_save_only()
		return _failure("奖励已记录，但无法开始混乱之门战斗。")
	if room != null and bool(reward.get("complete_room", true)):
		room.completed = true
	var message := str(reward.get("completion_message", "事件奖励结算完成。"))
	_save_and_emit(message)
	return {"ok": true, "message": message, "completed": room != null and room.completed}


func claim_reward_candidate(candidate_id: String, receiver_id: String = "") -> bool:
	if not has_pending_reward():
		return false
	var reward := current_run.adventure_flags["pending_reward"] as Dictionary
	for card_data in reward.get("cards", []):
		if not (card_data is Dictionary) or str(card_data.get("id", "")) != candidate_id:
			continue
		var claimed_cards := reward["claimed_cards"] as Array
		if claimed_cards.size() >= int(reward.get("max_cards", 0)) or claimed_cards.has(candidate_id):
			return false
		var hero := _get_hero(str(card_data.get("hero_id", "")))
		if hero == null:
			return false
		var stack := reward_service.create_card_stack(
			str(card_data.get("path", "")),
			"%s_reward_%s" % [hero.adventure_character_id, candidate_id],
			hero.character_data.character_class
		)
		if stack == null:
			return false
		hero.deck.append(stack)
		claimed_cards.append(candidate_id)
		_save_and_emit("%s 获得了 %s。" % [hero.get_character_name(), str(card_data.get("name", "卡牌"))])
		return true
	for equipment_data in reward.get("equipment", []):
		if not (equipment_data is Dictionary) or str(equipment_data.get("id", "")) != candidate_id:
			continue
		var claimed_equipment := reward["claimed_equipment"] as Array
		if claimed_equipment.size() >= int(reward.get("max_equipment", 0)) or claimed_equipment.has(candidate_id):
			return false
		var receiver := _get_hero(receiver_id)
		if receiver == null or receiver.get_inventory_item_count() >= CharacterState.INVENTORY_LIMIT:
			return false
		var stack := reward_service.create_item_stack(str(equipment_data.get("path", "")), "%s_reward_%s" % [receiver.adventure_character_id, candidate_id])
		if stack == null:
			return false
		receiver.inventory.append(stack)
		current_run.mark_equipment_reward_drawn(str(equipment_data.get("path", "")))
		claimed_equipment.append(candidate_id)
		_save_and_emit("获得装备 %s。" % str(equipment_data.get("name", "装备")))
		return true
	return false


func claim_gospel_reward(hero_id: String) -> bool:
	if not has_pending_reward():
		return false
	var reward := current_run.adventure_flags["pending_reward"] as Dictionary
	if not bool(reward.get("gospel_offer", false)) or not str(reward.get("gospel_receiver", "")).is_empty() \
			or bool(reward.get("gospel_declined", false)):
		return false
	var hero := _get_hero(hero_id)
	var definition_resource := load("res://resources/curses/gospel.tres") as CurseDefinition
	if hero == null or definition_resource == null or hero.acquire_curse(definition_resource) == null:
		return false
	reward["gospel_receiver"] = hero_id
	_save_and_emit("%s 接受了「福音」之业。" % hero.get_character_name())
	return true


func decline_gospel_reward() -> bool:
	if not has_pending_reward():
		return false
	var reward := current_run.adventure_flags["pending_reward"] as Dictionary
	if not bool(reward.get("gospel_offer", false)) or not str(reward.get("gospel_receiver", "")).is_empty():
		return false
	reward["gospel_declined"] = true
	_save_and_emit("队伍放弃了「福音」之业。")
	return true


func settle_pending_reward() -> void:
	if not has_pending_reward():
		return
	var reward := current_run.adventure_flags["pending_reward"] as Dictionary
	if bool(reward.get("gospel_offer", false)) and str(reward.get("gospel_receiver", "")).is_empty():
		reward["gospel_declined"] = true
	reward["settled"] = true
	var room := current_run.floor_state.get_room(str(reward.get("room_id", "")))
	current_run.commit_transaction()
	if room != null and room.room_type == AdventureEnums.RoomType.BOSS_BATTLE:
		if current_run.floor_index >= current_run.floor_count - 1:
			current_run.run_complete = true
		else:
			current_run.adventure_flags["interfloor_camp"] = true
	_save_and_emit("奖励结算完成。")


func enter_next_floor() -> bool:
	if current_run == null or not bool(current_run.adventure_flags.get("interfloor_camp", false)) or has_pending_reward() or has_pending_event_reward():
		return false
	_heal_party_percent(0.25)
	current_run.add_camp_points(definition.get_economy().shelter_camp_points, definition.get_economy().camp_point_cap)
	current_run.floor_index += 1
	current_run.add_provisions(definition.get_economy().later_floor_provisions)
	current_run.floor_state = map_generator.generate(current_run.run_seed, current_run.floor_index, definition)
	current_run.adventure_flags.erase("interfloor_camp")
	_save_and_emit("进入第 %d 层。" % (current_run.floor_index + 1))
	return true


func rest_at_current_shelter() -> bool:
	var room := _current_room_of_type(AdventureEnums.RoomType.SHELTER)
	if room == null or room.rest_used:
		return false
	_ensure_camp_opened(room)
	_heal_party_percent(0.25)
	current_run.add_camp_points(definition.get_economy().shelter_camp_points, definition.get_economy().camp_point_cap)
	room.rest_used = true
	_save_and_emit("队伍完成休息，并获得 4 点扎营点。")
	return true


func can_deliver_adventurer_remains() -> bool:
	var room := _current_room_of_type(AdventureEnums.RoomType.SHELTER)
	return room != null and room.shelter_type == AdventureEnums.ShelterType.OUTPOST \
		and bool(current_run.adventure_flags.get("adventurer_remains", false)) \
		and not has_pending_event_reward()


func begin_adventurer_remains_delivery() -> Dictionary:
	if not can_deliver_adventurer_remains():
		return _failure("只有携带遗骨抵达据点时才能交付。")
	var room := _current_room_of_type(AdventureEnums.RoomType.SHELTER)
	var candidates := reward_service.get_equipment_candidates(current_run, room.room_id.hash() + 5700, 3, current_run.floor_index)
	if candidates.is_empty():
		return _failure("当前楼层没有可用的装备候选。")
	current_run.adventure_flags["pending_event_reward"] = {
		"event_id": "adventurer_remains_delivery",
		"room_id": room.room_id,
		"title": "交付冒险者遗骨",
		"kind": "equipment",
		"instructions": "据点确认了死者身份。从 3 件本层装备中选择 1 件并指定接收者；确认后遗骨任务物品消失。",
		"starts_battle": false,
		"complete_room": false,
		"remains_delivery": true,
		"completion_message": "遗骨已交还据点，任务物品移除。",
		"required_equipment": 1,
		"equipment": candidates,
		"claimed_equipment": "",
		"equipment_receiver": "",
		"cards": [],
		"required_card_hero_ids": [],
		"claimed_cards": {},
	}
	_save_and_emit("据点已确认遗骨身份，请选择 1 件本层装备作为报酬。")
	return {"ok": true, "message": "请选择 1 件本层装备。", "pending_event_reward": true}


func use_camp_activity(activity_id: String, hero_id: String = "") -> bool:
	var camp_room := _current_room_of_type(AdventureEnums.RoomType.SHELTER)
	if camp_room == null and not bool(current_run.adventure_flags.get("interfloor_camp", false)):
		return false
	_ensure_camp_opened(camp_room)
	var hero := _get_hero(hero_id)
	match activity_id:
		"bandage":
			var bandage_key := "interfloor_bandaged" if camp_room == null else "bandaged_hero_ids"
			var bandaged: Array = current_run.adventure_flags.get(bandage_key, []) as Array if camp_room == null \
				else camp_room.runtime_data.get(bandage_key, []) as Array
			if hero == null or bandaged.has(hero.adventure_character_id) or not current_run.spend_camp_points(2):
				return false
			hero.current_health = mini(hero.get_max_health(), hero.current_health + ceili(hero.get_max_health() * 0.2))
			bandaged.append(hero.adventure_character_id)
			if camp_room == null:
				current_run.adventure_flags[bandage_key] = bandaged
			else:
				camp_room.runtime_data[bandage_key] = bandaged
		"tactics":
			if bool(current_run.adventure_flags.get("tactical_rehearsal", false)) or not current_run.spend_camp_points(2):
				return false
			current_run.adventure_flags["tactical_rehearsal"] = true
		"scout":
			var target := _find_scout_target()
			if target == null or not current_run.spend_camp_points(1):
				return false
			target.content_revealed = true
		"watch":
			if not current_run.spend_camp_points(2):
				return false
			if current_run.floor_state.ambush_chance >= 40:
				current_run.floor_state.ambush_chance = maxi(20, current_run.floor_state.ambush_chance - 40)
			else:
				current_run.floor_state.watch_protection = true
		"sharpen":
			if hero == null or hero.character_data == null or hero.character_data.character_class != CardEnums.CardClass.WARRIOR \
				or bool(current_run.adventure_flags.get("sharpen_%s" % hero.adventure_character_id, false)) \
				or not current_run.spend_camp_points(3):
				return false
			var weapon_instance_id := hero.get_equipment_instance_id(hero.weapon_equipment)
			if weapon_instance_id.is_empty():
				current_run.add_camp_points(3, definition.get_economy().camp_point_cap)
				return false
			var modifiers := hero.equipment_adventure_modifiers.get(weapon_instance_id, {}) as Dictionary
			modifiers["damage_bonus"] = int(modifiers.get("damage_bonus", 0)) + 1
			hero.equipment_adventure_modifiers[weapon_instance_id] = modifiers
			current_run.adventure_flags["sharpen_%s" % hero.adventure_character_id] = true
		"ranger_dig":
			if hero == null or hero.character_data == null or hero.character_data.character_class != CardEnums.CardClass.RANGER:
				return false
			var key := "ranger_dig_%s" % hero.adventure_character_id
			var progress := int(current_run.adventure_flags.get(key, 0))
			if progress >= 3:
				return false
			if progress < 2:
				if not current_run.spend_camp_points(2):
					return false
				var elements := _grant_ranger_dig_elements(hero, progress)
				current_run.adventure_flags[key] = progress + 1
				_save_and_emit("%s 第 %d 次挖掘：获得 %s。元素库存 %d/%d；还可挖掘 %d 次。" % [
					hero.get_character_name(),
					progress + 1,
					"、".join(elements) if not elements.is_empty() else "元素库存已满，未能收入元素",
					_get_ranger_element_total(hero),
					RangerCombatState.ELEMENT_LIMIT,
					2 - progress,
				])
				return true
			var equipment_candidates := reward_service.get_equipment_candidates(
				current_run,
				hero.adventure_character_id.hash() + current_run.floor_index * 7919,
				3,
				current_run.floor_index
			)
			if equipment_candidates.is_empty() or not current_run.spend_camp_points(2):
				return false
			current_run.adventure_flags[key] = 3
			current_run.adventure_flags["pending_event_reward"] = {
				"event_id": "ranger_dig",
				"room_id": camp_room.room_id if camp_room != null else "",
				"title": "挖掘宝藏",
				"kind": "equipment",
				"instructions": "第三次挖掘发现了装备。请选择 1 件当前楼层装备，并指定背包接收者。",
				"starts_battle": false,
				"complete_room": false,
				"completion_message": "%s 完成了三次挖掘。" % hero.get_character_name(),
				"required_equipment": 1,
				"equipment": equipment_candidates,
				"claimed_equipment": "",
				"equipment_receiver": "",
				"cards": [],
				"required_card_hero_ids": [],
				"claimed_cards": {},
			}
			_save_and_emit("%s 第 3 次挖掘：发现 3 件当前楼层装备，请选择其中 1 件并指定接收者。" % hero.get_character_name())
			return true
		_:
			return false
	_save_and_emit("扎营活动已结算。")
	return true


func _grant_ranger_dig_elements(hero: CharacterState, progress: int) -> PackedStringArray:
	var labels := PackedStringArray()
	if hero == null:
		return labels
	var first_index := posmod(
		current_run.run_seed + current_run.floor_index + progress * 2,
		BattleSurfaceState.BASE_ELEMENTS.size()
	)
	for offset in [0, 1]:
		if _get_ranger_element_total(hero) >= RangerCombatState.ELEMENT_LIMIT:
			break
		var index := posmod(first_index + offset + progress, BattleSurfaceState.BASE_ELEMENTS.size())
		var element := BattleSurfaceState.BASE_ELEMENTS[index]
		hero.ranger_element_inventory[element] = int(hero.ranger_element_inventory.get(element, 0)) + 1
		labels.append("%s×1" % BattleSurfaceState.label(element))
	return labels


func _get_ranger_element_total(hero: CharacterState) -> int:
	if hero == null:
		return 0
	var total := 0
	for element in BattleSurfaceState.BASE_ELEMENTS:
		total += maxi(0, int(hero.ranger_element_inventory.get(element, 0)))
	return total


func infuse_card(druid_id: String, target_hero_id: String, stack_id: String, element: int) -> bool:
	var camp_room := _current_room_of_type(AdventureEnums.RoomType.SHELTER)
	if camp_room == null and not bool(current_run.adventure_flags.get("interfloor_camp", false)):
		return false
	var druid := _get_hero(druid_id)
	var target := _get_hero(target_hero_id)
	if druid == null or target == null or druid.character_data == null \
		or druid.character_data.character_class != CardEnums.CardClass.DRUID \
		or not BattleSurfaceState.BASE_ELEMENTS.has(element):
		return false
	var selected_stack: CardStack
	for stack in target.deck:
		if stack != null and stack.stack_id == stack_id and stack.card_data != null and not stack.card_data.is_curse_card():
			selected_stack = stack
			break
	var existing_modifier := target.card_adventure_modifiers.get(stack_id, {}) as Dictionary
	if selected_stack == null or existing_modifier.has("element") or not current_run.spend_camp_points(3):
		return false
	var updated_modifier := existing_modifier.duplicate(true)
	updated_modifier["element"] = element
	target.card_adventure_modifiers[stack_id] = updated_modifier
	_save_and_emit("%s 为 %s 注入了%s元素。" % [druid.get_character_name(), selected_stack.card_data.card_name, BattleSurfaceState.label(element)])
	return true


func seal_curse_at_camp(hero_id: String, curse_id: String) -> bool:
	if not _camp_is_available():
		return false
	var hero := _get_hero(hero_id)
	var curse := hero.get_curse(curse_id) if hero != null else null
	if hero == null or curse == null or curse.state == CurseInstance.State.INDUSTRY or not hero.sealed_curse_id.is_empty():
		return false
	var resolves_overload := hero.get_curse_load() > hero.get_curse_load_limit() \
		and hero.get_curse_load() - curse.get_load_cost() <= hero.get_curse_load_limit()
	if current_run.camp_points < 2 or not current_run.can_pay_ritual(2, resolves_overload):
		return false
	current_run.spend_camp_points(2)
	if not hero.seal_curse(curse, current_run, resolves_overload):
		current_run.add_camp_points(2, definition.get_economy().camp_point_cap)
		return false
	_save_and_emit("%s 已被封印。" % curse.get_display_name())
	return true


func unseal_curse_at_camp(hero_id: String) -> bool:
	if not _camp_is_available():
		return false
	var hero := _get_hero(hero_id)
	if hero == null or hero.sealed_curse_id.is_empty() or current_run.camp_points < 1:
		return false
	current_run.spend_camp_points(1)
	if not hero.unseal_curse():
		current_run.add_camp_points(1, definition.get_economy().camp_point_cap)
		return false
	_save_and_emit("已解除封印。")
	return true


func transfer_curse_at_camp(source_id: String, curse_id: String, target_id: String) -> bool:
	if not _camp_is_available():
		return false
	var source := _get_hero(source_id)
	var target := _get_hero(target_id)
	var curse := source.get_curse(curse_id) if source != null else null
	if source == null or target == null or curse == null or source == target or curse.state == CurseInstance.State.INDUSTRY:
		return false
	var resolves_overload := source.get_curse_load() > source.get_curse_load_limit() \
		and source.get_curse_load() - curse.get_load_cost() <= source.get_curse_load_limit()
	if current_run.camp_points < 1 or not current_run.can_pay_ritual(1, resolves_overload):
		return false
	current_run.spend_camp_points(1)
	if not source.transfer_curse_to(curse, target, current_run, false, resolves_overload):
		current_run.add_camp_points(1, definition.get_economy().camp_point_cap)
		return false
	_save_and_emit("%s 已转移给 %s。" % [curse.get_display_name(), target.get_character_name()])
	return true


func has_pending_distortion_reward(hero_id: String = "") -> bool:
	if current_run == null:
		return false
	if not hero_id.is_empty():
		var selected_hero := _get_hero(hero_id)
		return selected_hero != null and selected_hero.has_pending_distortion_reward()
	for hero in current_run.party:
		if hero != null and hero.has_pending_distortion_reward():
			return true
	return false


func get_distortion_reward_options(hero_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var hero := _get_hero(hero_id)
	if hero == null:
		return result
	var milestone_index := hero.get_pending_distortion_milestone()
	if milestone_index < 0:
		return result
	var excluded := hero.selected_distortion_fields.duplicate()
	var option_seed := AdventureMapGenerator.derive_seed(
		current_run.run_seed,
		"distortion_reward_%s" % hero.adventure_character_id,
		milestone_index,
	)
	var option_ids := DistortionCatalog.get_options_for_tier(milestone_index, excluded, option_seed)
	for option_id_value in option_ids:
		var option_id := str(option_id_value)
		result.append({
			"id": option_id,
			"name": DistortionCatalog.get_display_name(option_id),
			"description": DistortionCatalog.get_description(option_id),
		})
	return result


func get_distortion_reward_state(hero_id: String) -> Dictionary:
	var hero := _get_hero(hero_id)
	if hero == null:
		return {}
	var milestone_index := hero.get_pending_distortion_milestone()
	return {
		"hero_id": hero.adventure_character_id,
		"progress": hero.distortion_progress,
		"milestone_index": milestone_index,
		"threshold": hero.get_effective_distortion_threshold(milestone_index) if milestone_index >= 0 else hero.get_next_distortion_threshold(),
		"options": get_distortion_reward_options(hero_id),
		"grace": {
			"id": DistortionCatalog.GRACE_ID,
			"name": DistortionCatalog.get_display_name(DistortionCatalog.GRACE_ID),
			"description": DistortionCatalog.get_description(DistortionCatalog.GRACE_ID),
		},
	}


func choose_distortion_reward(hero_id: String, reward_id: String) -> bool:
	var hero := _get_hero(hero_id)
	if hero == null or not hero.has_pending_distortion_reward():
		return false
	if reward_id != DistortionCatalog.GRACE_ID:
		var offered := false
		for option in get_distortion_reward_options(hero_id):
			if str(option.get("id", "")) == reward_id:
				offered = true
				break
		if not offered:
			return false
	var reward_name := DistortionCatalog.get_display_name(reward_id)
	if not hero.apply_distortion_reward(reward_id):
		return false
	_save_and_emit("%s 选择了畸变奖励「%s」。" % [hero.get_character_name(), reward_name])
	return true


func exchange_camp_supply() -> bool:
	if current_run == null or current_run.camp_supplies <= 0:
		return false
	current_run.camp_supplies -= 1
	current_run.add_camp_points(2, definition.get_economy().camp_point_cap)
	_save_and_emit("消耗 1 份扎营物资，获得 2 点扎营点。")
	return true


func get_shop_stock() -> Array[Dictionary]:
	var room := current_run.floor_state.get_current_room() if current_run != null and current_run.floor_state != null else null
	if room == null or room.room_type not in [AdventureEnums.RoomType.SHOP, AdventureEnums.RoomType.EVENT]:
		return []
	return _get_room_shop_stock(room)


func buy_shop_entry(index: int) -> bool:
	var room := current_run.floor_state.get_current_room()
	var stock := _get_room_shop_stock(room)
	if index < 0 or index >= stock.size():
		return false
	var entry := stock[index]
	if bool(entry.get("sold", false)) or not current_run.spend_gold(int(entry.get("price", 0))):
		return false
	var success := false
	var entry_kind := str(entry.get("kind", ""))
	if entry_kind == "card":
		var hero := _get_hero(str(entry.get("hero_id", "")))
		if hero != null:
			var stack := reward_service.create_card_stack(
				str(entry.get("path", "")),
				"%s_shop_%s_%d" % [hero.adventure_character_id, room.room_id, index],
				hero.character_data.character_class
			)
			if stack != null:
				hero.deck.append(stack)
				success = true
	elif entry_kind == "camp_supply":
		current_run.camp_supplies += 1
		success = true
	else:
		var receiver := _first_inventory_receiver()
		if receiver != null and receiver.get_inventory_item_count() < CharacterState.INVENTORY_LIMIT:
			var stack := reward_service.create_item_stack(str(entry.get("path", "")), "%s_shop_%s_%d" % [receiver.adventure_character_id, room.room_id, index])
			if stack != null:
				receiver.inventory.append(stack)
				success = true
	if not success:
		current_run.add_gold(int(entry.get("price", 0)))
		return false
	entry["sold"] = true
	stock[index] = entry
	room.runtime_data["shop_stock"] = stock
	_save_and_emit("购买了 %s。" % str(entry.get("name", "物品")))
	return true


func buy_provision() -> bool:
	var price := definition.get_economy().provision_price
	if current_run == null or not current_run.spend_gold(price):
		return false
	current_run.add_provisions(1)
	_save_and_emit("购买 1 点补给。")
	return true


func buy_camp_supply() -> bool:
	var price := definition.get_economy().camp_supply_price
	if current_run == null or not current_run.spend_gold(price):
		return false
	current_run.camp_supplies += 1
	_save_and_emit("购买 1 份扎营物资。")
	return true


func remove_shop_card(hero_id: String, stack_id: String) -> bool:
	var room := _current_room_of_type(AdventureEnums.RoomType.SHOP)
	if room == null or bool(room.runtime_data.get("card_removal_used", false)):
		return false
	var hero := _get_hero(hero_id)
	if hero == null or hero.deck.size() <= 1:
		return false
	var selected_stack: CardStack
	for stack in hero.deck:
		if stack != null and stack.stack_id == stack_id and stack.card_data != null and not stack.card_data.is_curse_card():
			selected_stack = stack
			break
	var price := definition.get_economy().get_card_removal_price(current_run.card_removals_used)
	if selected_stack == null or not current_run.spend_gold(price):
		return false
	hero.deck.erase(selected_stack)
	room.runtime_data["card_removal_used"] = true
	current_run.card_removals_used += 1
	_save_and_emit("从 %s 的牌组中移除了 %s。" % [hero.get_character_name(), selected_stack.card_data.card_name])
	return true


func get_current_event_options(room: AdventureRoomState = null) -> Array[Dictionary]:
	var event_room := room if room != null else _current_room_of_type(AdventureEnums.RoomType.EVENT)
	if event_room == null:
		return []
	var event_definition := get_event_definition(event_room)
	var result: Array[Dictionary] = []
	for raw_option in event_definition.get("options", []):
		if not (raw_option is Dictionary):
			continue
		var option := (raw_option as Dictionary).duplicate(true)
		var option_id := str(option.get("id", "leave"))
		var availability := _get_event_option_availability(event_room, option_id)
		option.merge(availability, true)
		if option_id == "alchemy_roll":
			var price := int(event_room.runtime_data.get("alchemy_price", 20))
			option["label"] = "支付 %d 金并投掷" % price
			option["preview"] = "%s 当前金币：%d。" % [str(option.get("preview", "")), current_run.gold]
		result.append(option)
	return result


func get_event_selection(option_id: String) -> Dictionary:
	var room := _current_room_of_type(AdventureEnums.RoomType.EVENT)
	if room == null or room.completed:
		return {"kind": "none", "title": "事件已经结束", "choices": []}
	match option_id:
		"take_supply", "aid":
			return {
				"kind": "hero_item",
				"title": "选择消耗品与获得者",
				"heroes": _event_hero_entries(true),
				"items": _get_locked_event_consumables(room, option_id),
			}
		"altar_resolve":
			return {"kind": "altar", "title": "为每名冒险者选择献祭数量", "heroes": _event_hero_entries(false)}
		"take_remains":
			return {"kind": "hero", "title": "选择遗骨携带者", "heroes": _event_hero_entries(true)}
		"accept_fall":
			return {"kind": "hero", "title": "选择负荷最高的承受者", "heroes": _highest_load_hero_entries()}
		"share":
			return {"kind": "hero", "title": "选择承担普通业的角色", "heroes": _event_hero_entries(false)}
		"gamble", "alchemy_roll":
			return {"kind": "hero", "title": "选择可能获得卡牌或诅咒的角色", "heroes": _event_hero_entries(false)}
		"remove_card":
			return {"kind": "cards", "title": "选择同一角色的 1 至 2 张牌", "heroes": _event_card_entries()}
		"nature_resolve":
			return {"kind": "nature", "title": "选择超负荷角色的诅咒处理", "heroes": _nature_choice_entries()}
	return {"kind": "none", "title": "确认事件选择", "choices": []}


func resolve_current_event(option_id: String, selection_value: Variant = {}) -> Dictionary:
	var room := _current_room_of_type(AdventureEnums.RoomType.EVENT)
	if room == null or room.completed:
		return _failure("当前没有可结算事件。")
	if option_id == "leave":
		return {"ok": true, "message": "你暂时离开了%s。事件保持未完成，回到这里时仍可继续选择。" % str(get_event_definition(room).get("title", "事件")), "completed": false}
	var availability := _get_event_option_availability(room, option_id)
	if not bool(availability.get("available", false)):
		return _failure(str(availability.get("reason", "当前不能选择该项。")))
	var selection: Dictionary = selection_value.duplicate(true) if selection_value is Dictionary else {"hero_id": str(selection_value)}
	var hero := _get_hero(str(selection.get("hero_id", "")))
	var message := ""
	match option_id:
		"take_supply":
			var item_path := str(selection.get("item_path", ""))
			if hero == null or not _event_candidate_path_is_valid(_get_locked_event_consumables(room, option_id), item_path):
				return _failure("请选择一件候选消耗品及其获得者。")
			if hero.get_inventory_item_count() >= CharacterState.INVENTORY_LIMIT:
				return _failure("%s 的背包已满。" % hero.get_character_name())
			var stack := reward_service.create_item_stack(item_path, "%s_event_%s" % [hero.adventure_character_id, room.room_id])
			if stack == null:
				return _failure("所选消耗品资源无效。")
			hero.inventory.append(stack)
			room.completed = true
			message = "%s 将「%s」收入背包。背包现在为 %d/%d。" % [hero.get_character_name(), stack.item_data.item_name, hero.get_inventory_item_count(), CharacterState.INVENTORY_LIMIT]
		"altar_resolve":
			var curse_counts := selection.get("curse_counts", {}) as Dictionary
			var result_lines := PackedStringArray()
			for party_hero in current_run.party:
				if party_hero == null:
					continue
				var count := clampi(int(curse_counts.get(party_hero.adventure_character_id, 0)), 0, 3)
				if count > _get_available_curse_capacity(party_hero):
					return _failure("%s 无法再承担 %d 个普通业。" % [party_hero.get_character_name(), count])
				var before_health := party_hero.current_health
				party_hero.current_health = mini(party_hero.get_max_health(), party_hero.current_health + 10 * count)
				for index in range(count):
					_add_random_curse(party_hero, room.room_id.hash() + party_hero.adventure_character_id.hash() + index)
				result_lines.append("%s：恢复 %d 生命，获得 %d 个普通业，负荷 %d/%d。" % [party_hero.get_character_name(), party_hero.current_health - before_health, count, party_hero.get_curse_load(), party_hero.get_curse_load_limit()])
			room.completed = true
			message = "堕落圣坛完成结算：\n%s" % "\n".join(result_lines)
		"take_remains":
			var carrier := hero
			if carrier == null:
				return _failure("请选择遗骨携带者。")
			if carrier.get_inventory_item_count() >= CharacterState.INVENTORY_LIMIT:
				return _failure("%s 的背包已满。" % carrier.get_character_name())
			var remains_stack := reward_service.create_item_stack("res://resources/items/adventurer_remains.tres", "%s_remains_%s" % [carrier.adventure_character_id, room.room_id])
			if remains_stack == null:
				return _failure("冒险者遗骨资源缺失。")
			carrier.inventory.append(remains_stack)
			current_run.adventure_flags["adventurer_remains"] = true
			current_run.adventure_flags["adventurer_remains_carrier"] = carrier.adventure_character_id
			var roll := _event_roll(room)
			if roll >= 5:
				_create_pending_remains_curse(room, roll)
				message = "%s 携带冒险者遗骨，占用 1 个背包格。掷骰结果：%d；请继续选择 1 名角色承受随机普通业。" % [carrier.get_character_name(), roll]
				_save_and_emit(message)
				return {"ok": true, "message": message, "pending_event_reward": true, "completed": false}
			room.completed = true
			message = "%s 携带冒险者遗骨，占用 1 个背包格。掷骰结果：%d，没有额外惩罚。抵达下一座据点后可交付遗骨。" % [carrier.get_character_name(), roll]
		"accept_fall":
			if hero == null or not _highest_load_hero_entries().any(func(entry: Dictionary) -> bool: return str(entry.get("id", "")) == hero.adventure_character_id):
				return _failure("请选择当前未封印负荷最高的角色。")
			if _get_available_curse_capacity(hero) < 2:
				return _failure("%s 无法承担两个普通业。" % hero.get_character_name())
			var card := reward_service.get_random_card(hero.character_data.character_class, CardEnums.Rarity.EPIC, current_run.run_seed, room.room_id.hash())
			if card != null:
				var stack := reward_service.create_card_stack(
					card.resource_path,
					"%s_fall_%s" % [hero.adventure_character_id, room.room_id],
					hero.character_data.character_class
				)
				if stack != null:
					hero.deck.append(stack)
			_add_random_curse(hero, room.room_id.hash())
			_add_random_curse(hero, room.room_id.hash() + 1)
			room.completed = true
			message = "%s 获得史诗牌「%s」并承受 2 个普通业。最终负荷：%d/%d。" % [hero.get_character_name(), card.card_name if card != null else "未生成", hero.get_curse_load(), hero.get_curse_load_limit()]
		"share":
			if hero == null:
				return _failure("请选择承担普通业的角色。")
			if _get_available_curse_capacity(hero) < 1:
				return _failure("%s 无法再承担普通业。" % hero.get_character_name())
			_add_random_curse(hero, room.room_id.hash())
			current_run.gain_ritual_points(2)
			room.completed = true
			message = "%s 分担了 1 个随机普通业；团队仪式点 +2，现有 %d 点。" % [hero.get_character_name(), current_run.ritual_points]
		"aid":
			if not current_run.pay_ritual(1):
				return _failure("仪式点不足。")
			var aid_item_path := str(selection.get("item_path", ""))
			if hero == null or hero.get_inventory_item_count() >= CharacterState.INVENTORY_LIMIT or not _event_candidate_path_is_valid(_get_locked_event_consumables(room, option_id), aid_item_path):
				current_run.gain_ritual_points(1)
				return _failure("请选择有背包空间的获得者和候选消耗品。")
			var aid_stack := reward_service.create_item_stack(aid_item_path, "%s_wanderer_%s" % [hero.adventure_character_id, room.room_id])
			if aid_stack == null:
				current_run.gain_ritual_points(1)
				return _failure("所选消耗品资源无效。")
			hero.inventory.append(aid_stack)
			room.completed = true
			message = "支付 1 仪式点援助游荡者；%s 获得「%s」。剩余仪式点：%d。" % [hero.get_character_name(), aid_stack.item_data.item_name, current_run.ritual_points]
		"gamble":
			if hero == null:
				return _failure("请选择随机结果的承受者。")
			var roll := _event_roll(room)
			if roll <= 2:
				_add_random_curse(hero, room.room_id.hash() + roll)
				message = "掷骰结果：%d。%s 获得 1 个随机普通业。" % [roll, hero.get_character_name()]
			elif roll <= 5:
				current_run.add_provisions(2)
				message = "掷骰结果：%d。团队补给 +2，现有 %d。" % [roll, current_run.provisions]
			else:
				_create_pending_card_event_reward(room, hero, CardEnums.Rarity.RARE, "受咒游荡者 · 稀有牌三选一", "掷骰结果为 6。为 %s 从 3 张本职业稀有牌中选择 1 张。" % hero.get_character_name(), true)
				message = "掷骰结果：6。已锁定 %s 的 3 张稀有牌候选，请继续选择 1 张。" % hero.get_character_name()
				_save_and_emit(message)
				return {"ok": true, "message": message, "pending_event_reward": true, "completed": false}
			room.completed = true
		"alchemy_roll":
			if hero == null:
				return _failure("请选择首次史诗奖励的获得者。")
			var price := int(room.runtime_data.get("alchemy_price", 20))
			if not current_run.spend_gold(price):
				return _failure("金币不足。")
			var roll := _event_roll(room)
			if roll <= 3:
				current_run.add_gold(1)
				message = "支付 %d 金，掷骰结果：%d。仅回收 1 金，当前金币 %d。" % [price, roll, current_run.gold]
			elif roll <= 5:
				current_run.add_gold(40)
				room.runtime_data["alchemy_price"] = price + 10
				message = "支付 %d 金，掷骰结果：%d。获得 40 金；下次费用提高到 %d。" % [price, roll, price + 10]
			elif bool(room.runtime_data.get("alchemy_epic_claimed", false)):
				current_run.add_gold(60)
				room.runtime_data["alchemy_price"] = price + 10
				message = "支付 %d 金，掷骰结果：6。史诗奖励已领取，本次获得 60 金；下次费用为 %d。" % [price, price + 10]
			else:
				room.runtime_data["alchemy_epic_claimed"] = true
				room.runtime_data["alchemy_price"] = price + 10
				_create_pending_card_event_reward(room, hero, CardEnums.Rarity.EPIC, "炼金术 · 史诗牌三选一", "首次掷出 6。为 %s 从 3 张本职业史诗牌中选择 1 张；下次费用为 %d 金。" % [hero.get_character_name(), price + 10], false)
				message = "支付 %d 金，掷骰结果：6。已锁定 %s 的 3 张史诗牌候选；选牌后仍可再次参与，费用为 %d 金。" % [price, hero.get_character_name(), price + 10]
				_save_and_emit(message)
				return {"ok": true, "message": message, "pending_event_reward": true, "completed": false}
		"nature_resolve":
			var nature_result := _resolve_nature_blessing(selection.get("curse_actions", {}) as Dictionary)
			if not bool(nature_result.get("ok", false)):
				return _failure(str(nature_result.get("message", "恩惠选择无效。")))
			room.completed = true
			message = str(nature_result.get("message", "大自然的恩惠完成结算。"))
		"remove_card":
			var stack_ids := selection.get("stack_ids", []) as Array
			if hero == null or stack_ids.size() < 1 or stack_ids.size() > 2:
				return _failure("请选择同一角色的 1 至 2 张非诅咒牌。")
			if hero.deck.size() - stack_ids.size() < 1 or _get_available_curse_capacity(hero) < stack_ids.size():
				return _failure("该选择会使牌组低于最低张数，或无法承担对应数量的业。")
			var removed_names := PackedStringArray()
			for stack_id_value in stack_ids:
				var removed := _remove_card_stack(hero, str(stack_id_value))
				if removed.is_empty():
					return _failure("所选牌已不在该角色的持久牌组中。")
				removed_names.append(removed)
			for index in range(stack_ids.size()):
				_add_random_curse(hero, room.room_id.hash() + index)
			room.completed = true
			message = "%s 永久移除 %s，并获得 %d 个随机普通业。" % [hero.get_character_name(), "、".join(removed_names), stack_ids.size()]
		"open_shop":
			_initialize_room_runtime(room)
			message = "游商的固定库存已经揭示。库存不会刷新，可以离开后回访。"
		"event_battle":
			if room.content_id == "chaos_gate":
				_create_pending_event_reward(room, room.content_id, true)
				_save_and_emit("混乱之门已经锁定奖励候选；完成全部选择后将立即进入战斗。")
				return {"ok": true, "message": "请先选择下一档装备，并为每名冒险者各选择 1 张职业牌。完成后将立即强制开战。", "pending_event_reward": true, "completed": false}
			if start_event_battle(room.content_id):
				return {"ok": true, "message": "事件选择已经锁定，正在进入专属战斗。胜利后会继续处理事件奖励。", "battle": true}
			return _failure("无法开始专属战斗。")
		_:
			return _failure("尚未实现该事件选择。")
	_save_and_emit(message)
	return {"ok": true, "message": message, "completed": room.completed}


func get_event_definition(room: AdventureRoomState) -> Dictionary:
	return AdventureContentCatalog.get_event_definition(room.content_id if room != null else "")


func _prepare_battle_transaction(room: AdventureRoomState, ambush: bool, tier: int, extra_payload: Dictionary = {}) -> void:
	var payload := extra_payload.duplicate(true)
	payload["room_id"] = room.room_id
	payload["ambush"] = ambush
	payload["encounter_tier"] = tier
	payload["battle_seed"] = AdventureMapGenerator.derive_seed(current_run.run_seed, "encounter", room.room_id.hash() + current_run.floor_index * 1000 + (70000 if ambush else 0))
	payload["starting_hand_bonus"] = 1 if bool(current_run.adventure_flags.get("tactical_rehearsal", false)) else 0
	payload["enemy_health_percent"] = current_run.enemy_health_percent
	var enemy_chapter := EnemyCatalogRouter.chapter_for_floor(current_run.floor_index)
	payload["enemy_chapter"] = enemy_chapter
	payload["battlefield_seed"] = AdventureMapGenerator.derive_seed(
		int(payload["battle_seed"]),
		"battlefield_layout",
		0
	)
	payload["battlefield_generation_version"] = 1
	payload["generate_battlefield_features"] = tier != AdventureEnums.EncounterTier.BOSS
	payload["force_abyss_features"] = _roll_chapter_one_abyss(
		enemy_chapter,
		tier,
		int(payload["battlefield_seed"])
	)
	current_run.adventure_flags.erase("tactical_rehearsal")
	var last_key := "last_chapter_%d_encounter_%d" % [enemy_chapter, tier]
	var bag_key := "chapter_%d_encounter_bag_%d" % [enemy_chapter, tier]
	var bag_ids: Array = current_run.adventure_flags.get(bag_key, []) as Array
	var draw := EnemyCatalogRouter.draw_encounter(enemy_chapter, tier, int(payload.battle_seed), bag_ids, str(current_run.adventure_flags.get(last_key, "")))
	var encounter := draw.get("encounter", {}) as Dictionary
	payload["encounter_id"] = str(encounter.get("id", ""))
	payload["enemy_archetypes"] = encounter.get("enemies", []).duplicate()
	current_run.adventure_flags[last_key] = payload.encounter_id
	current_run.adventure_flags[bag_key] = draw.get("remaining_ids", [])
	current_run.begin_transaction(AdventureEnums.TransactionType.BATTLE, "battle_%s" % room.room_id, payload)
	pending_battle_scenario = _build_battle_scenario(payload)
	_save_only()


func _rebuild_pending_battle_scenario() -> void:
	if current_run == null or current_run.pending_transaction == null:
		return
	pending_battle_scenario = _build_battle_scenario(current_run.pending_transaction.payload)


func _build_battle_scenario(payload: Dictionary) -> BattleScenario:
	var template := load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario
	if template == null:
		return null
	var scenario := template.duplicate(true) as BattleScenario
	scenario.scene_prototype = null
	scenario.players.clear()
	for hero in current_run.get_active_party():
		scenario.players.append(hero)
	scenario.enemies.clear()
	var tier := int(payload.get("encounter_tier", AdventureEnums.EncounterTier.WEAK))
	var archetypes: Array = payload.get("enemy_archetypes", []) as Array
	var fallback_chapter := 1 if not archetypes.is_empty() else EnemyCatalogRouter.chapter_for_floor(current_run.floor_index)
	var enemy_chapter := int(payload.get("enemy_chapter", fallback_chapter))
	if archetypes.is_empty():
		var encounter := EnemyCatalogRouter.pick_encounter(enemy_chapter, tier, int(payload.get("battle_seed", current_run.run_seed)))
		archetypes = encounter.get("enemies", []) as Array
	var birth_index := 0
	var enemy_health_percent := clampi(
		int(payload.get("enemy_health_percent", current_run.enemy_health_percent)), 1, 1000
	)
	for archetype in archetypes:
		var enemy_seed := AdventureMapGenerator.derive_seed(int(payload.get("battle_seed", current_run.run_seed)), "enemy_deck", birth_index)
		var enemy := EnemyCatalogRouter.create_enemy(enemy_chapter, StringName(archetype), enemy_seed)
		if enemy != null:
			enemy.max_health_percent = enemy_health_percent
			enemy.current_health = enemy.get_max_health()
			scenario.enemies.append(enemy)
		birth_index += 1
	scenario.seed = int(payload.get("battle_seed", current_run.run_seed))
	scenario.generate_battlefield_features = bool(payload.get("generate_battlefield_features", true))
	scenario.feature_chapter = enemy_chapter
	scenario.feature_encounter_tier = tier
	scenario.feature_seed = int(payload.get("battlefield_seed", scenario.seed))
	scenario.force_abyss_features = bool(payload.get("force_abyss_features", false))
	if scenario.battle_config != null:
		scenario.battle_config = scenario.battle_config.duplicate(true) as BattleConfig
		scenario.battle_config.starting_hand_size += int(payload.get("starting_hand_bonus", 0))
	return scenario


func _roll_chapter_one_abyss(chapter: int, tier: int, battlefield_seed: int) -> bool:
	if current_run == null or chapter != 1 \
			or (tier != AdventureEnums.EncounterTier.STRONG \
			and tier != AdventureEnums.EncounterTier.ELITE):
		return false
	const MISS_KEY := "chapter_1_battlefield_abyss_misses"
	var misses := int(current_run.adventure_flags.get(MISS_KEY, 0))
	var generated := misses >= 2
	if not generated:
		var rng := RandomNumberGenerator.new()
		rng.seed = AdventureMapGenerator.derive_seed(battlefield_seed, "abyss_roll", misses)
		var chance := 75 if tier == AdventureEnums.EncounterTier.ELITE else 50
		generated = rng.randi_range(1, 100) <= chance
	current_run.adventure_flags[MISS_KEY] = 0 if generated else misses + 1
	return generated


func _enter_pending_battle_scene() -> bool:
	if pending_battle_scenario == null or pending_battle_scenario.players.is_empty():
		status_message.emit("没有可以参加战斗的冒险者。")
		return false
	_save_only()
	return get_tree().change_scene_to_file(BATTLE_SCENE_PATH) == OK


func _apply_fixed_reward(room: AdventureRoomState, reward: Dictionary) -> void:
	var gold := definition.get_economy().get_battle_gold(room.room_type, current_run.floor_index)
	reward["gold"] = gold
	current_run.add_gold(gold)
	current_run.add_provisions(int(reward.get("provisions", 0)))
	current_run.gain_ritual_points(int(reward.get("ritual_points", 0)))
	current_run.camp_supplies += int(reward.get("camp_supplies", 0))


func _complete_event_battle(event_id: String, room: AdventureRoomState) -> void:
	if room == null:
		return
	if event_id == "chaos_gate":
		room.completed = true
		return
	_create_pending_event_reward(room, event_id, false)


func _create_pending_event_reward(room: AdventureRoomState, event_id: String, starts_battle: bool) -> void:
	if room == null:
		return
	var event_definition := AdventureContentCatalog.get_event_definition(event_id)
	var reward := {
		"event_id": event_id,
		"room_id": room.room_id,
		"title": str(event_definition.get("title", "事件")),
		"starts_battle": starts_battle,
		"complete_room": true,
		"required_equipment": 0,
		"equipment": [],
		"claimed_equipment": "",
		"equipment_receiver": "",
		"cards": [],
		"required_card_hero_ids": [],
		"claimed_cards": {},
	}
	match event_id:
		"sealed_chapel":
			reward["kind"] = "sealed_reliquary"
			reward["instructions"] = "选择 1 名背包有空位的冒险者获得封印圣匣。它是饰品：负荷上限 +1，每场首次打出诅咒牌后获得 4 护甲。"
		"trapped_arcanist":
			reward["kind"] = "arcanist"
			reward["instructions"] = "二选一：指定 1 名冒险者在本次冒险中负荷上限 +2；或选择 1 名冒险者获得智力 +2 的奥能坠饰。"
		"master_forging", "chaos_gate":
			reward["kind"] = "chaos" if event_id == "chaos_gate" else "equipment"
			reward["instructions"] = "从 3 件下一档装备中选择 1 件并指定接收者。"
			reward["required_equipment"] = 1
			reward["equipment"] = reward_service.get_equipment_candidates(current_run, room.room_id.hash() + 4100, 3, current_run.floor_index + 1)
			if event_id == "chaos_gate":
				reward["instructions"] += " 再为每名冒险者各选择 1 张职业牌；全部锁定后立即强制开战。"
				var cards: Array[Dictionary] = []
				var required_ids: Array[String] = []
				for hero in current_run.party:
					if hero == null or hero.character_data == null:
						continue
					required_ids.append(hero.adventure_character_id)
					var candidates := reward_service.get_card_candidates(hero.character_data.character_class, CardEnums.Rarity.RARE, current_run.run_seed, room.room_id.hash() + hero.adventure_character_id.hash(), 3)
					for candidate_data in candidates:
						var candidate := candidate_data.duplicate(true)
						candidate["id"] = "%s_%s" % [hero.adventure_character_id, str(candidate.get("id", "card"))]
						candidate["hero_id"] = hero.adventure_character_id
						cards.append(candidate)
				reward["cards"] = cards
				reward["required_card_hero_ids"] = required_ids
		_:
			room.completed = true
			return
	current_run.adventure_flags["pending_event_reward"] = reward


func _create_pending_card_event_reward(room: AdventureRoomState, hero: CharacterState, rarity: int, title: String, instructions: String, complete_room: bool) -> void:
	if room == null or hero == null or hero.character_data == null:
		return
	var candidates := reward_service.get_card_candidates(hero.character_data.character_class, rarity, current_run.run_seed, room.room_id.hash() + int(room.runtime_data.get("roll_count", 0)) * 313, 3)
	var cards: Array[Dictionary] = []
	for candidate_data in candidates:
		var candidate := candidate_data.duplicate(true)
		candidate["id"] = "%s_%s_%d" % [hero.adventure_character_id, str(candidate.get("id", "card")), int(room.runtime_data.get("roll_count", 0))]
		candidate["hero_id"] = hero.adventure_character_id
		cards.append(candidate)
	current_run.adventure_flags["pending_event_reward"] = {
		"event_id": room.content_id,
		"room_id": room.room_id,
		"title": title,
		"kind": "single_card",
		"instructions": instructions,
		"starts_battle": false,
		"complete_room": complete_room,
		"completion_message": "%s 获得了所选卡牌。" % hero.get_character_name(),
		"required_equipment": 0,
		"equipment": [],
		"claimed_equipment": "",
		"cards": cards,
		"required_card_hero_ids": [hero.adventure_character_id],
		"claimed_cards": {},
	}


func _create_pending_remains_curse(room: AdventureRoomState, roll: int) -> void:
	current_run.adventure_flags["pending_event_reward"] = {
		"event_id": room.content_id,
		"room_id": room.room_id,
		"title": "冒险者遗骨 · 诅咒承受者",
		"kind": "remains_curse",
		"instructions": "掷骰结果为 %d。选择 1 名仍可承担普通业的冒险者；确认后遗骨事件完成。" % roll,
		"starts_battle": false,
		"complete_room": true,
		"required_equipment": 0,
		"equipment": [],
		"claimed_equipment": "",
		"cards": [],
		"required_card_hero_ids": [],
		"claimed_cards": {},
		"roll": roll,
		"curse_salt": room.room_id.hash() + roll,
	}


func _find_reward_candidate(candidates: Array, candidate_id: String) -> Dictionary:
	for candidate_data in candidates:
		if candidate_data is Dictionary and str(candidate_data.get("id", "")) == candidate_id:
			return (candidate_data as Dictionary).duplicate(true)
	return {}


func _grant_event_item(hero: CharacterState, item_path: String, stack_suffix: String) -> Dictionary:
	if hero == null or hero.get_inventory_item_count() >= CharacterState.INVENTORY_LIMIT:
		return _failure("所选角色的背包已满。")
	var stack := reward_service.create_item_stack(item_path, "%s_%s" % [hero.adventure_character_id, stack_suffix])
	if stack == null:
		return _failure("事件奖励物品资源无效。")
	hero.inventory.append(stack)
	return {"ok": true, "message": "%s 获得「%s」。" % [hero.get_character_name(), stack.item_data.item_name]}


func _remove_adventurer_remains_item() -> void:
	for hero in current_run.party:
		if hero == null:
			continue
		for stack in hero.inventory.duplicate():
			if stack != null and stack.item_data != null and stack.item_data.resource_path == "res://resources/items/adventurer_remains.tres":
				hero.inventory.erase(stack)
				return


func _finish_pending_event_reward(message: String) -> Dictionary:
	if not has_pending_event_reward():
		return _failure("当前没有待结算的事件奖励。")
	var reward := current_run.adventure_flags["pending_event_reward"] as Dictionary
	var room := current_run.floor_state.get_room(str(reward.get("room_id", ""))) if current_run.floor_state != null else null
	if room != null and bool(reward.get("complete_room", true)):
		room.completed = true
	current_run.adventure_flags.erase("pending_event_reward")
	_save_and_emit(message)
	return {"ok": true, "message": message, "completed": true}


func _initialize_room_runtime(room: AdventureRoomState) -> void:
	if room.room_type == AdventureEnums.RoomType.SHOP or room.content_id == "wilderness_merchant":
		_get_room_shop_stock(room)


func _get_room_shop_stock(room: AdventureRoomState) -> Array[Dictionary]:
	if room == null:
		return []
	if room.content_id == "wilderness_merchant":
		return reward_service.get_wilderness_merchant_stock(current_run, room)
	return reward_service.get_shop_stock(current_run, room)


func _event_roll(room: AdventureRoomState) -> int:
	var roll_index := int(room.runtime_data.get("roll_count", 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = AdventureMapGenerator.derive_seed(current_run.run_seed, "event_dice", room.room_id.hash() + roll_index * 101)
	room.runtime_data["roll_count"] = roll_index + 1
	return rng.randi_range(1, 6)


func _add_random_curse(hero: CharacterState, salt: int) -> void:
	if hero == null:
		return
	var candidates: Array[CurseDefinition] = []
	for path in ORDINARY_CURSE_PATHS:
		var definition_resource := load(path) as CurseDefinition
		if definition_resource == null:
			continue
		var existing := hero.get_curse(definition_resource.curse_id)
		if existing == null or existing.depth < 3:
			candidates.append(definition_resource)
	if candidates.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = AdventureMapGenerator.derive_seed(current_run.run_seed, "event_curse", salt)
	var definition_resource := candidates[rng.randi_range(0, candidates.size() - 1)]
	var existing := hero.get_curse(definition_resource.curse_id)
	if existing != null:
		existing.deepen()
	else:
		var curse := CurseInstance.new()
		curse.definition = definition_resource
		curse.state = CurseInstance.State.INDUSTRY
		hero.curse_instances.append(curse)


func _get_event_option_availability(room: AdventureRoomState, option_id: String) -> Dictionary:
	if option_id == "leave":
		return {"available": true, "reason": ""}
	var available := true
	var reason := ""
	match option_id:
		"take_supply", "aid":
			if option_id == "aid" and not current_run.can_pay_ritual(1):
				available = false
				reason = "需要 1 点仪式点。"
			elif _first_inventory_receiver() == null:
				available = false
				reason = "所有角色的背包都已满。"
			elif _get_locked_event_consumables(room, option_id).is_empty():
				available = false
				reason = "当前资源中没有可用消耗品。"
		"altar_resolve":
			available = current_run != null and not current_run.party.is_empty()
			reason = "队伍中没有可结算角色。" if not available else ""
		"take_remains":
			available = _first_inventory_receiver() != null
			reason = "所有角色的背包都已满，无法携带遗骨。" if not available else ""
		"accept_fall":
			available = _highest_load_hero_entries().any(func(entry: Dictionary) -> bool: return int(entry.get("curse_capacity", 0)) >= 2)
			reason = "负荷最高的角色都无法再承担两个普通业。" if not available else ""
		"share":
			available = current_run.party.any(func(hero: CharacterState) -> bool: return hero != null and _get_available_curse_capacity(hero) >= 1)
			reason = "没有角色能够再承担一个普通业。" if not available else ""
		"gamble", "alchemy_roll":
			available = current_run != null and not current_run.party.is_empty()
			if option_id == "alchemy_roll" and available:
				var price := int(room.runtime_data.get("alchemy_price", 20))
				available = current_run.gold >= price
				reason = "需要 %d 金，当前只有 %d 金。" % [price, current_run.gold] if not available else ""
		"remove_card":
			available = not _event_card_entries().is_empty()
			reason = "没有能承担业且可以继续精简牌组的角色。" if not available else ""
		"nature_resolve", "open_shop":
			available = true
		"event_battle":
			available = current_run != null and not current_run.get_active_party().is_empty()
			reason = "没有生命大于 0 且未超负荷的角色可以参战。" if not available else ""
	return {"available": available, "reason": reason}


func _event_hero_entries(require_inventory_space: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if current_run == null:
		return result
	for hero in current_run.party:
		if hero == null:
			continue
		var inventory_space := CharacterState.INVENTORY_LIMIT - hero.get_inventory_item_count()
		result.append({
			"id": hero.adventure_character_id,
			"name": hero.get_character_name(),
			"health": hero.current_health,
			"max_health": hero.get_max_health(),
			"load": hero.get_curse_load(),
			"load_limit": hero.get_curse_load_limit(),
			"curse_capacity": _get_available_curse_capacity(hero),
			"inventory_space": inventory_space,
			"available": inventory_space > 0 if require_inventory_space else true,
		})
	return result


func _highest_load_hero_entries() -> Array[Dictionary]:
	var entries := _event_hero_entries(false)
	var highest := 0
	for entry in entries:
		highest = maxi(highest, int(entry.get("load", 0)))
	var result: Array[Dictionary] = []
	for entry in entries:
		if int(entry.get("load", 0)) == highest:
			result.append(entry)
	return result


func _event_card_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if current_run == null:
		return result
	for hero in current_run.party:
		if hero == null or hero.deck.size() <= 1 or _get_available_curse_capacity(hero) <= 0:
			continue
		var cards: Array[Dictionary] = []
		for stack in hero.deck:
			if stack == null or stack.card_data == null or stack.card_data.is_curse_card():
				continue
			cards.append({"id": stack.stack_id, "name": stack.card_data.card_name, "description": RulesTextFormatter.format_card(stack.card_data)})
		if not cards.is_empty():
			result.append({"id": hero.adventure_character_id, "name": hero.get_character_name(), "cards": cards, "max_count": mini(2, mini(cards.size(), hero.deck.size() - 1)), "curse_capacity": _get_available_curse_capacity(hero)})
	return result


func _nature_choice_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if current_run == null:
		return result
	for hero in current_run.party:
		if hero == null or hero.get_curse_load() < hero.get_curse_load_limit():
			continue
		var choices: Array[Dictionary] = []
		for curse in hero.curse_instances:
			if curse == null or curse.sealed:
				continue
			if curse.state == CurseInstance.State.INDUSTRY:
				choices.append({"id": "remove:%s" % curse.get_curse_id(), "label": "移除业：%s" % curse.get_display_name()})
			elif curse.state == CurseInstance.State.REPORT:
				choices.append({"id": "mature:%s" % curse.get_curse_id(), "label": "报成熟 +1：%s" % curse.get_display_name()})
		result.append({"id": hero.adventure_character_id, "name": hero.get_character_name(), "choices": choices})
	return result


func _get_locked_event_consumables(room: AdventureRoomState, option_id: String) -> Array[Dictionary]:
	var key := "event_consumables_%s" % option_id
	var existing := room.runtime_data.get(key, []) as Array
	if not existing.is_empty():
		var result: Array[Dictionary] = []
		for entry in existing:
			if entry is Dictionary:
				result.append((entry as Dictionary).duplicate(true))
		return result
	var candidates := reward_service.get_consumable_candidates(current_run.run_seed, room.room_id.hash() + option_id.hash(), 3)
	room.runtime_data[key] = candidates.duplicate(true)
	return candidates


func _event_candidate_path_is_valid(candidates: Array[Dictionary], item_path: String) -> bool:
	return candidates.any(func(candidate: Dictionary) -> bool: return str(candidate.get("path", "")) == item_path)


func _get_available_curse_capacity(hero: CharacterState) -> int:
	if hero == null:
		return 0
	var capacity := 0
	for path in ORDINARY_CURSE_PATHS:
		var curse_definition := load(path) as CurseDefinition
		if curse_definition == null:
			continue
		var existing := hero.get_curse(curse_definition.curse_id)
		capacity += 3 if existing == null else maxi(0, 3 - existing.depth)
	return capacity


func _resolve_nature_blessing(curse_actions: Dictionary) -> Dictionary:
	var result_lines := PackedStringArray()
	for hero in current_run.party:
		if hero == null:
			continue
		if hero.get_curse_load() >= hero.get_curse_load_limit():
			var choices := _nature_choice_entries().filter(func(entry: Dictionary) -> bool: return str(entry.get("id", "")) == hero.adventure_character_id)
			var action_id := str(curse_actions.get(hero.adventure_character_id, ""))
			if not choices.is_empty() and not (choices[0].get("choices", []) as Array).is_empty() \
					and not (choices[0].get("choices", []) as Array).any(func(choice: Dictionary) -> bool: return str(choice.get("id", "")) == action_id):
				return {"ok": false, "message": "请选择 %s 的诅咒处理方式。" % hero.get_character_name()}
			var loss := ceili(hero.get_max_health() * 0.1)
			hero.current_health = maxi(1, hero.current_health - loss)
			var action_text := "没有可处理的业或报"
			if action_id.begins_with("remove:"):
				var remove_curse_id := action_id.trim_prefix("remove:")
				var industry_curse := hero.get_curse(remove_curse_id)
				if industry_curse != null and industry_curse.state == CurseInstance.State.INDUSTRY:
					hero.curse_instances.erase(industry_curse)
					action_text = "移除业「%s」" % industry_curse.get_display_name()
			elif action_id.begins_with("mature:"):
				var mature_curse_id := action_id.trim_prefix("mature:")
				var report_curse := hero.get_curse(mature_curse_id)
				if report_curse != null and report_curse.state == CurseInstance.State.REPORT:
					report_curse.add_maturity(1)
					action_text = "令报「%s」成熟度 +1" % report_curse.get_display_name()
			result_lines.append("%s：失去 %d 生命，并%s。" % [hero.get_character_name(), loss, action_text])
		else:
			var before := hero.current_health
			hero.current_health = mini(hero.get_max_health(), hero.current_health + ceili(hero.get_max_health() * 0.1))
			result_lines.append("%s：恢复 %d 生命。" % [hero.get_character_name(), hero.current_health - before])
	return {"ok": true, "message": "大自然的恩惠完成结算：\n%s" % "\n".join(result_lines)}


func _remove_card_stack(hero: CharacterState, stack_id: String) -> String:
	if hero == null:
		return ""
	for stack in hero.deck:
		if stack != null and stack.stack_id == stack_id and stack.card_data != null and not stack.card_data.is_curse_card():
			var card_name := stack.card_data.card_name
			hero.deck.erase(stack)
			return card_name
	return ""


func _remove_first_non_curse_card(hero: CharacterState) -> bool:
	if hero == null or hero.deck.size() <= 1:
		return false
	for stack in hero.deck:
		if stack != null and stack.card_data != null and not stack.card_data.is_curse_card():
			hero.deck.erase(stack)
			return true
	return false


func _heal_party_percent(ratio: float) -> void:
	for hero in current_run.party:
		if hero != null and hero.current_health > 0:
			hero.current_health = mini(hero.get_max_health(), hero.current_health + ceili(hero.get_max_health() * ratio))


func _ensure_camp_opened(room: AdventureRoomState) -> void:
	var flag_key := "interfloor_camp_opened" if room == null else "camp_opened"
	var opened := bool(current_run.adventure_flags.get(flag_key, false)) if room == null \
		else bool(room.runtime_data.get(flag_key, false))
	if opened:
		return
	for hero in current_run.party:
		if hero != null and hero.character_data != null and hero.character_data.character_class == CardEnums.CardClass.RANGER:
			hero.ranger_element_inventory.clear()
	if room == null:
		current_run.adventure_flags[flag_key] = true
	else:
		room.runtime_data[flag_key] = true


func _camp_is_available() -> bool:
	return _current_room_of_type(AdventureEnums.RoomType.SHELTER) != null \
		or (current_run != null and bool(current_run.adventure_flags.get("interfloor_camp", false)))


func _find_scout_target() -> AdventureRoomState:
	if current_run == null or current_run.floor_state == null:
		return null
	var floor := current_run.floor_state
	for room in floor.rooms:
		if room != null and room.room_type == AdventureEnums.RoomType.EVENT and not room.visited \
			and not room.content_revealed and floor.graph_distance(floor.current_room_id, room.room_id) <= 3:
			return room
	return null


func _current_room_of_type(room_type: int) -> AdventureRoomState:
	if current_run == null or current_run.floor_state == null:
		return null
	var room := current_run.floor_state.get_current_room()
	return room if room != null and room.room_type == room_type else null


func _loadout_change_is_blocked() -> bool:
	if current_run == null or current_run.run_complete or current_run.run_failed:
		return true
	if has_pending_reward() or has_pending_event_reward():
		return true
	return current_run.pending_transaction != null and not current_run.pending_transaction.committed


func _get_hero(hero_id: String) -> CharacterState:
	if current_run == null:
		return null
	for hero in current_run.party:
		if hero != null and hero.adventure_character_id == hero_id:
			return hero
	return null


func _first_inventory_receiver() -> CharacterState:
	if current_run == null:
		return null
	for hero in current_run.party:
		if hero != null and hero.get_inventory_item_count() < CharacterState.INVENTORY_LIMIT:
			return hero
	return null


func _save_only() -> void:
	var error := save_store.save_run(current_run)
	if error != OK:
		status_message.emit("自动存档失败：%s" % error_string(error))


func _save_and_emit(message: String) -> void:
	_save_only()
	status_message.emit(message)
	state_changed.emit()


func _failure(message: String) -> Dictionary:
	status_message.emit(message)
	return {"ok": false, "message": message}
