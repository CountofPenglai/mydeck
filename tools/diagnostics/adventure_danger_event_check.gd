extends Node

var failures: int = 0

func _ready() -> void:
	var service := AdventureRewardService.new()
	_check(service.has_method("create_cards_only_reward"), "cards-only reward entry point missing")
	var resolver_path := "res://scripts/adventure/adventure_event_variant_service.gd"
	_check(ResourceLoader.exists(resolver_path), "danger event resolver missing")
	if failures > 0:
		get_tree().quit(1)
		return
	var resolver: Script = load(resolver_path)
	for event_id in ["hermit_house", "adventurer_remains", "nature_blessing"]:
		var normal: Dictionary = resolver.resolve(event_id, 17)
		var dangerous: Dictionary = resolver.resolve(event_id, 18)
		_check(not normal.auto_battle and dangerous.auto_battle, "event threshold must replace only at 18")
		_check(dangerous.reward_mode == "cards_only", "danger reward policy")
		_check(not dangerous.normal_text.is_empty() and not dangerous.danger_text.is_empty(), "both rulings visible")
		var copy: Dictionary = resolver.resolve(event_id, 18)
		copy["normal_text"] = "changed"
		_check(resolver.resolve(event_id, 18).normal_text != "changed", "no shared mutable event definition")
	var untouched: Array = AdventureContentCatalog.EVENT_DEFINITIONS.keys().filter(func(id): return id not in ["hermit_house", "adventurer_remains", "nature_blessing"])
	untouched.append("unknown")
	for event_id in untouched:
		_check(not resolver.resolve(event_id, 24).auto_battle, "unlisted event must not be converted")
	var run := PartyRunState.new()
	var hero := (load("res://resources/characters/battle_warrior_state.tres") as CharacterState).duplicate(true) as CharacterState
	hero.ensure_initialized()
	run.initialize_adventure(71239, [hero], AdventureDefinition.new())
	var room := AdventureRoomState.new()
	room.room_id = "danger_event"
	room.room_type = AdventureEnums.RoomType.EVENT
	room.content_id = "hermit_house"
	for tier in [AdventureEnums.EncounterTier.WEAK, AdventureEnums.EncounterTier.MIXED, AdventureEnums.EncounterTier.STRONG]:
		var flags_before := run.adventure_flags.duplicate(true)
		var gold_before := run.gold
		var reward: Dictionary = service.call("create_cards_only_reward", run, room, tier)
		_check(not (reward.cards as Array).is_empty(), "ordinary card candidates required")
		_check(reward.max_cards == 2 and reward.max_equipment == 0, "normal selection limits")
		for key in ["gold", "provisions", "camp_supplies", "ritual_points"]:
			_check(int(reward.get(key, 0)) == 0, "unexpected reward "+key)
		_check((reward.equipment as Array).is_empty(), "no equipment")
		_check(run.gold == gold_before and run.adventure_flags == flags_before, "reward construction cannot grant event effects")
		var ordinary := room.duplicate(true) as AdventureRoomState
		ordinary.room_type = AdventureEnums.RoomType.NORMAL_BATTLE
		var expected := service.create_battle_reward(run, ordinary, tier)
		_check(reward.cards == expected.cards, "same normal encounter card distribution")
		_check(not room.completed, "constructing reward cannot complete event")
	_test_session_cards_only()
	print("HEX_DANGER_EVENT: %s" % ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("HEX_DANGER_EVENT: " + message)

func _test_session_cards_only() -> void:
	for event_id in ["hermit_house", "adventurer_remains", "nature_blessing"]:
		var session := AdventureSessionService.new()
		session.save_store = AdventureSaveStore.new("hex_diagnostic_event_reward_v7")
		var run := PartyRunState.new()
		var hero := (load("res://resources/characters/battle_warrior_state.tres") as CharacterState).duplicate(true) as CharacterState
		hero.ensure_initialized()
		hero.adventure_source_path = "res://resources/characters/battle_warrior_state.tres"
		hero.current_health = 7
		run.initialize_adventure(734, [hero], AdventureDefinition.new())
		run.floor_state = AdventureFloorState.new()
		var room := AdventureRoomState.new()
		room.room_id = "event_target"
		room.room_type = AdventureEnums.RoomType.EVENT
		room.content_id = event_id
		room.visited = true
		run.floor_state.rooms.append(room)
		run.floor_state.current_room_id = room.room_id
		run.begin_transaction(AdventureEnums.TransactionType.BATTLE, "event_battle", {
			"room_id": room.room_id, "event_id": event_id, "event_battle": true,
			"reward_mode": "cards_only", "encounter_tier": AdventureEnums.EncounterTier.WEAK,
		})
		session.current_run = run
		_check(session.pending_battle_grants_reward(), "danger event card-choice preview enabled")
		var gold_before := run.gold
		var result := BattleResult.new()
		result.victory = true
		_check(session.resolve_pending_battle_result(result), "danger event victory accepted")
		_check(session.has_pending_reward(), "victory creates card choice")
		_check(run.pending_transaction.transaction_type == AdventureEnums.TransactionType.REWARD, "reward transaction retained")
		_check(not room.completed, "card choice precedes event completion")
		_check(run.gold == gold_before and hero.current_health == 7, "no fixed loot or original healing")
		_check(not run.adventure_flags.has("adventurer_remains") and not session.has_pending_event_reward(), "no original callback/delivery")
		var reloaded := session.save_store.load_run()
		_check(reloaded != null, "pending reward restorable")
		if reloaded != null:
			session.current_run = reloaded
			_check(session.has_pending_reward(), "restored card choice")
			var candidate: Dictionary = session.get_pending_reward().cards[0]
			var deck_size := reloaded.party[0].deck.size()
			_check(session.claim_reward_candidate(str(candidate.id)), "cards-only card can be claimed")
			_check(not session.claim_reward_candidate(str(candidate.id)), "cannot claim same card twice")
			_check(reloaded.party[0].deck.size() == deck_size + 1, "one card granted")
			session.settle_pending_reward()
			_check(reloaded.floor_state.get_room(room.room_id).completed, "skip completes event")
			_check(not session.has_pending_reward(), "skip settles once")
			session.settle_pending_reward()
			_check(reloaded.gold == gold_before, "repeat settlement no loot")
		# A defeated dangerous event has neither original effects nor rewards.
		session.current_run = run
		run.adventure_flags.erase("pending_reward")
		run.begin_transaction(AdventureEnums.TransactionType.BATTLE, "defeat", {"room_id": room.room_id, "event_battle": true, "reward_mode": "cards_only"})
		var defeat := BattleResult.new()
		defeat.victory = false
		_check(session.resolve_pending_battle_result(defeat) and run.run_failed, "defeat ends run")
		_check(not session.has_pending_reward() and run.gold == gold_before, "defeat grants nothing")
		session.save_store.delete_save()
		session.free()
