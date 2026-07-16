extends Node
class_name AdventureSessionService

signal state_changed
signal status_message(message: String)

const MAP_SCENE_PATH := "res://scenes/adventure_map_scene.tscn"
const BATTLE_SCENE_PATH := "res://scenes/battle_scene.tscn"
const HERO_PATHS := [
	"res://resources/characters/battle_warrior_state.tres",
	"res://resources/characters/battle_ranger_state.tres",
	"res://resources/characters/battle_druid_state.tres",
]
const MELEE_ENEMY_PATH := "res://resources/enemies/battle_melee_enemy_state.tres"
const RANGED_ENEMY_PATH := "res://resources/enemies/battle_ranged_enemy_state.tres"
const ORDINARY_CURSE_PATHS := [
	"res://resources/curses/blood.tres",
	"res://resources/curses/greed.tres",
	"res://resources/curses/cripple.tres",
	"res://resources/curses/disease.tres",
	"res://resources/curses/passing.tres",
	"res://resources/curses/possession.tres",
	"res://resources/curses/unrest.tres",
	"res://resources/curses/counterfeit.tres",
]

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


func request_move(target_room_id: String) -> Dictionary:
	var run := ensure_run()
	if run.run_complete or run.run_failed or run.floor_state == null:
		return _failure("本次冒险已经结束。")
	if has_pending_reward():
		return _failure("请先完成当前战斗奖励。")
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


func consume_pending_battle_scenario() -> BattleScenario:
	return pending_battle_scenario


func complete_pending_battle(result: BattleResult) -> void:
	if current_run == null or current_run.pending_transaction == null:
		return
	var transaction := current_run.pending_transaction
	if transaction.transaction_type != AdventureEnums.TransactionType.BATTLE:
		return
	var payload := transaction.payload
	var room := current_run.floor_state.get_room(str(payload.get("room_id", "")))
	var is_ambush := bool(payload.get("ambush", false))
	var event_battle := bool(payload.get("event_battle", false))
	pending_battle_scenario = null
	if not result.victory:
		current_run.run_failed = true
		current_run.commit_transaction()
		_save_only()
		get_tree().change_scene_to_file(MAP_SCENE_PATH)
		return
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
		_apply_fixed_reward(room, reward)
		current_run.adventure_flags["pending_reward"] = reward
		current_run.begin_transaction(AdventureEnums.TransactionType.REWARD, "reward_%s" % room.room_id, {"room_id": room.room_id})
	_save_only()
	get_tree().change_scene_to_file(MAP_SCENE_PATH)


func has_pending_reward() -> bool:
	if current_run == null:
		return false
	var reward = current_run.adventure_flags.get("pending_reward", {})
	return reward is Dictionary and not (reward as Dictionary).is_empty() and not bool((reward as Dictionary).get("settled", false))


func get_pending_reward() -> Dictionary:
	if not has_pending_reward():
		return {}
	return (current_run.adventure_flags.get("pending_reward", {}) as Dictionary).duplicate(true)


func claim_reward_candidate(candidate_id: String) -> bool:
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
		var stack := reward_service.create_card_stack(str(card_data.get("path", "")), "%s_reward_%s" % [hero.adventure_character_id, candidate_id])
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
		var receiver := _first_inventory_receiver()
		if receiver == null or receiver.get_inventory_item_count() >= CharacterState.INVENTORY_LIMIT:
			return false
		var stack := reward_service.create_item_stack(str(equipment_data.get("path", "")), "%s_reward_%s" % [receiver.adventure_character_id, candidate_id])
		if stack == null:
			return false
		receiver.inventory.append(stack)
		claimed_equipment.append(candidate_id)
		_save_and_emit("获得装备 %s。" % str(equipment_data.get("name", "装备")))
		return true
	return false


func settle_pending_reward() -> void:
	if not has_pending_reward():
		return
	var reward := current_run.adventure_flags["pending_reward"] as Dictionary
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
	if current_run == null or not bool(current_run.adventure_flags.get("interfloor_camp", false)) or has_pending_reward():
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
			if progress >= 3 or not current_run.spend_camp_points(2):
				return false
			if progress < 2:
				var first_element := (current_run.run_seed + progress + current_run.floor_index) % 4
				var second_element := (first_element + 1 + progress) % 4
				hero.ranger_element_inventory[first_element] = mini(5, int(hero.ranger_element_inventory.get(first_element, 0)) + 1)
				hero.ranger_element_inventory[second_element] = mini(5, int(hero.ranger_element_inventory.get(second_element, 0)) + 1)
			current_run.adventure_flags[key] = progress + 1
		_:
			return false
	_save_and_emit("扎营活动已结算。")
	return true


func infuse_card(druid_id: String, target_hero_id: String, stack_id: String, element: int) -> bool:
	var camp_room := _current_room_of_type(AdventureEnums.RoomType.SHELTER)
	if camp_room == null and not bool(current_run.adventure_flags.get("interfloor_camp", false)):
		return false
	var druid := _get_hero(druid_id)
	var target := _get_hero(target_hero_id)
	var flag := "druid_infusion_%s" % druid_id
	if druid == null or target == null or druid.character_data == null \
		or druid.character_data.character_class != CardEnums.CardClass.DRUID \
		or bool(current_run.adventure_flags.get(flag, false)) \
		or not BattleSurfaceState.BASE_ELEMENTS.has(element):
		return false
	var selected_stack: CardStack
	for stack in target.deck:
		if stack != null and stack.stack_id == stack_id and stack.card_data != null and not stack.card_data.is_curse_card():
			selected_stack = stack
			break
	if selected_stack == null or target.card_adventure_modifiers.has(stack_id) or not current_run.spend_camp_points(3):
		return false
	target.card_adventure_modifiers[stack_id] = {"element": element}
	current_run.adventure_flags[flag] = true
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
	return reward_service.get_shop_stock(current_run, room)


func buy_shop_entry(index: int) -> bool:
	var room := current_run.floor_state.get_current_room()
	var stock := reward_service.get_shop_stock(current_run, room)
	if index < 0 or index >= stock.size():
		return false
	var entry := stock[index]
	if bool(entry.get("sold", false)) or not current_run.spend_gold(int(entry.get("price", 0))):
		return false
	var success := false
	if str(entry.get("kind", "")) == "card":
		var hero := _get_hero(str(entry.get("hero_id", "")))
		if hero != null:
			var stack := reward_service.create_card_stack(str(entry.get("path", "")), "%s_shop_%s_%d" % [hero.adventure_character_id, room.room_id, index])
			if stack != null:
				hero.deck.append(stack)
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


func resolve_current_event(option_id: String, hero_id: String = "") -> Dictionary:
	var room := _current_room_of_type(AdventureEnums.RoomType.EVENT)
	if room == null or room.completed:
		return _failure("当前没有可结算事件。")
	if option_id == "leave":
		return {"ok": true, "message": "事件保持未完成，可以稍后回访。"}
	var hero := _get_hero(hero_id)
	if hero == null:
		hero = _first_inventory_receiver()
	var message := "事件已结算。"
	match option_id:
		"take_supply":
			var item := reward_service.get_random_consumable(current_run.run_seed, room.room_id.hash())
			if hero == null or item == null or hero.get_inventory_item_count() >= CharacterState.INVENTORY_LIMIT:
				return _failure("背包没有可用空间。")
			var stack := reward_service.create_item_stack(item.resource_path, "%s_event_%s" % [hero.adventure_character_id, room.room_id])
			hero.inventory.append(stack)
			room.completed = true
			message = "获得了 %s。" % item.item_name
		"offer_1", "offer_2":
			var count := 1 if option_id == "offer_1" else 2
			if hero == null:
				return _failure("没有合法角色。")
			hero.current_health = mini(hero.get_max_health(), hero.current_health + 10 * count)
			for index in range(count):
				_add_random_curse(hero, room.room_id.hash() + index)
			room.completed = true
			message = "%s 恢复生命，并承受了新的业。" % hero.get_character_name()
		"take_remains":
			current_run.adventure_flags["adventurer_remains"] = true
			var roll := _event_roll(room)
			if roll >= 5 and hero != null:
				_add_random_curse(hero, room.room_id.hash() + roll)
			room.completed = true
			message = "拾取遗骨，骰子结果为 %d。" % roll
		"accept_fall":
			if hero == null:
				return _failure("没有合法角色。")
			var card := reward_service.get_random_card(hero.character_data.character_class, CardEnums.Rarity.EPIC, current_run.run_seed, room.room_id.hash())
			if card != null:
				hero.deck.append(reward_service.create_card_stack(card.resource_path, "%s_fall_%s" % [hero.adventure_character_id, room.room_id]))
			_add_random_curse(hero, room.room_id.hash())
			_add_random_curse(hero, room.room_id.hash() + 1)
			room.completed = true
			message = "%s 获得史诗牌并承受两个业。" % hero.get_character_name()
		"share":
			if hero == null:
				return _failure("没有合法角色。")
			_add_random_curse(hero, room.room_id.hash())
			current_run.gain_ritual_points(2)
			room.completed = true
		"aid":
			if not current_run.pay_ritual(1):
				return _failure("仪式点不足。")
			var item := reward_service.get_random_consumable(current_run.run_seed, room.room_id.hash())
			if item != null and hero != null:
				hero.inventory.append(reward_service.create_item_stack(item.resource_path, "%s_wanderer_%s" % [hero.adventure_character_id, room.room_id]))
			room.completed = true
		"gamble":
			var roll := _event_roll(room)
			if roll <= 2 and hero != null:
				_add_random_curse(hero, room.room_id.hash() + roll)
			elif roll <= 5:
				current_run.add_provisions(2)
			elif hero != null:
				var card := reward_service.get_random_card(hero.character_data.character_class, CardEnums.Rarity.RARE, current_run.run_seed, room.room_id.hash())
				if card != null:
					hero.deck.append(reward_service.create_card_stack(card.resource_path, "%s_luck_%s" % [hero.adventure_character_id, room.room_id]))
			room.completed = true
			message = "骰子结果为 %d。" % roll
		"alchemy_roll":
			var price := int(room.runtime_data.get("alchemy_price", 20))
			if not current_run.spend_gold(price):
				return _failure("金币不足。")
			var roll := _event_roll(room)
			if roll <= 3:
				current_run.add_gold(1)
			elif roll <= 5:
				current_run.add_gold(40)
				room.runtime_data["alchemy_price"] = price + 10
			elif bool(room.runtime_data.get("alchemy_epic_claimed", false)):
				current_run.add_gold(60)
				room.runtime_data["alchemy_price"] = price + 10
			elif hero != null:
				var card := reward_service.get_random_card(hero.character_data.character_class, CardEnums.Rarity.EPIC, current_run.run_seed, room.room_id.hash() + roll)
				if card != null:
					hero.deck.append(reward_service.create_card_stack(card.resource_path, "%s_alchemy_%s" % [hero.adventure_character_id, room.room_id]))
				room.runtime_data["alchemy_epic_claimed"] = true
				room.runtime_data["alchemy_price"] = price + 10
			message = "支付 %d 金币，骰子结果为 %d。" % [price, roll]
		"nature_resolve":
			_resolve_nature_blessing()
			room.completed = true
		"remove_card":
			if hero == null or not _remove_first_non_curse_card(hero):
				return _failure("没有可移除的非诅咒牌。")
			_add_random_curse(hero, room.room_id.hash())
			room.completed = true
		"open_shop":
			_initialize_room_runtime(room)
			message = "游商库存已经揭示。"
		"event_battle":
			if start_event_battle(room.content_id):
				return {"ok": true, "message": "正在进入专属战斗。", "battle": true}
			return _failure("无法开始专属战斗。")
		_:
			return _failure("尚未实现该事件选择。")
	_save_and_emit(message)
	return {"ok": true, "message": message}


func get_event_definition(room: AdventureRoomState) -> Dictionary:
	return AdventureContentCatalog.get_event_definition(room.content_id if room != null else "")


func _prepare_battle_transaction(room: AdventureRoomState, ambush: bool, tier: int, extra_payload: Dictionary = {}) -> void:
	var payload := extra_payload.duplicate(true)
	payload["room_id"] = room.room_id
	payload["ambush"] = ambush
	payload["encounter_tier"] = tier
	payload["battle_seed"] = AdventureMapGenerator.derive_seed(current_run.run_seed, "encounter", room.room_id.hash() + current_run.floor_index * 1000 + (70000 if ambush else 0))
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
	scenario.players.clear()
	for hero in current_run.get_active_party():
		scenario.players.append(hero)
	scenario.enemies.clear()
	var tier := int(payload.get("encounter_tier", AdventureEnums.EncounterTier.WEAK))
	var enemy_paths := [MELEE_ENEMY_PATH]
	if tier in [AdventureEnums.EncounterTier.MIXED, AdventureEnums.EncounterTier.AMBUSH]:
		enemy_paths = [MELEE_ENEMY_PATH, RANGED_ENEMY_PATH]
	elif tier in [AdventureEnums.EncounterTier.STRONG, AdventureEnums.EncounterTier.ELITE, AdventureEnums.EncounterTier.BOSS]:
		enemy_paths = [MELEE_ENEMY_PATH, RANGED_ENEMY_PATH, MELEE_ENEMY_PATH]
	for path in enemy_paths:
		var enemy := load(path) as EnemyState
		if enemy != null:
			scenario.enemies.append(enemy)
	scenario.seed = int(payload.get("battle_seed", current_run.run_seed))
	if scenario.battle_config != null:
		scenario.battle_config = scenario.battle_config.duplicate(true) as BattleConfig
		if bool(current_run.adventure_flags.get("tactical_rehearsal", false)):
			scenario.battle_config.starting_hand_size += 1
			current_run.adventure_flags.erase("tactical_rehearsal")
	return scenario


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
	room.completed = true
	var receiver := _first_inventory_receiver()
	match event_id:
		"sealed_chapel":
			if receiver != null:
				receiver.curse_load_limit_bonus += 1
				current_run.adventure_flags["sealed_reliquary"] = true
		"trapped_arcanist":
			if receiver != null:
				receiver.curse_load_limit_bonus += 2
		"master_forging", "chaos_gate":
			current_run.add_gold(30)


func _initialize_room_runtime(room: AdventureRoomState) -> void:
	if room.room_type == AdventureEnums.RoomType.SHOP or room.content_id == "wilderness_merchant":
		reward_service.get_shop_stock(current_run, room)


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


func _resolve_nature_blessing() -> void:
	for hero in current_run.party:
		if hero == null:
			continue
		if hero.get_curse_load() >= hero.get_curse_load_limit():
			hero.current_health = maxi(1, hero.current_health - ceili(hero.get_max_health() * 0.1))
			var resolved := false
			for curse in hero.curse_instances.duplicate():
				if curse != null and curse.state == CurseInstance.State.INDUSTRY:
					hero.curse_instances.erase(curse)
					resolved = true
					break
			if not resolved:
				for curse in hero.curse_instances:
					if curse != null and curse.state == CurseInstance.State.REPORT:
						curse.add_maturity(1)
						break
		else:
			hero.current_health = mini(hero.get_max_health(), hero.current_health + ceili(hero.get_max_health() * 0.1))


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
