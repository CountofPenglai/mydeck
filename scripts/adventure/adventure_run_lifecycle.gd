extends RefCounted
class_name AdventureRunLifecycle

const MAIN_MENU_PATH := "res://scenes/main_menu_scene.tscn"


static func get_menu_state(session: AdventureSessionService) -> Dictionary:
	var store := session.save_store
	var run := session.current_run
	var blocked := store.has_unsupported_schema() or store.load_status == AdventureSaveSchema.LoadStatus.UNSUPPORTED_SCHEMA
	var active := run != null and not run.run_failed and not run.run_complete
	var reason := ""
	if blocked:
		reason = "该存档版本不受支持，不会覆盖。请使用匹配的游戏版本。"
	elif run != null and run.run_failed:
		reason = "本次冒险已失败。可以开始新的冒险。"
	elif run != null and run.run_complete:
		reason = "本次冒险已完成。可以开始新的冒险。"
	elif run == null:
		match store.load_status:
			AdventureSaveSchema.LoadStatus.CORRUPT_SAVE:
				reason = "存档及备份无法读取。开始游戏将重建当前存档。"
			AdventureSaveSchema.LoadStatus.LEGACY_SAVE_DETECTED:
				reason = "检测到旧版存档。新冒险使用独立存档，不会删除旧文件。"
			_:
				reason = "尚无冒险进度。开始一段新的旅程。"
	elif store.load_status == AdventureSaveSchema.LoadStatus.RESTORED_BACKUP:
		reason = "已从有效备份恢复冒险进度。"
	var summary := ""
	if run != null and run.floor_state != null:
		summary = "第 %d / %d 章 · 危险 %d\n%s" % [
			run.floor_index + 1, run.floor_count, run.floor_state.danger,
			"战斗待恢复 · 从本场开始" if session.has_pending_battle() else "继续你的冒险",
		]
	return {
		"can_continue": active and not blocked,
		"can_start": not blocked,
		"requires_confirmation": run != null or store.has_save() or store.has_legacy_save(),
		"reason": reason, "summary": summary,
	}


static func build_run(seed_value: int, definition: AdventureDefinition) -> PartyRunState:
	if seed_value == 0:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		seed_value = rng.randi()
	var heroes: Array[CharacterState] = []
	for path in AdventureSessionService.HERO_PATHS:
		var template := load(path) as CharacterState
		if template == null:
			return null
		var hero := template.duplicate(true) as CharacterState
		hero.adventure_source_path = path
		hero.ensure_initialized()
		hero.current_health = hero.get_max_health()
		heroes.append(hero)
	var run := PartyRunState.new()
	run.initialize_adventure(seed_value, heroes, definition)
	run.floor_state = AdventureMapGenerator.new().generate(seed_value, 0, definition)
	AdventureShopService.initialize_map(run)
	return run


static func start_new_game(session: AdventureSessionService, seed_value: int = 0, confirmed: bool = false) -> Dictionary:
	var state := get_menu_state(session)
	if not state.can_start:
		return _failure(state.reason)
	if state.requires_confirmation and not confirmed:
		return _failure("请先确认开始新冒险；当前进度将被替换。")
	var candidate := build_run(seed_value, session.definition)
	if candidate == null:
		return _failure("无法加载初始队伍。")
	var error := session.save_store.save_run(candidate)
	if error != OK:
		return _failure("保存新冒险失败：%s" % error_string(error))
	session.current_run = candidate
	session.pending_battle_scenario = null
	session.state_changed.emit()
	return _success(AdventureSessionService.MAP_SCENE_PATH)


static func prepare_continue(session: AdventureSessionService) -> Dictionary:
	var state := get_menu_state(session)
	if not state.can_continue:
		return _failure(state.reason if not state.reason.is_empty() else "没有可继续的冒险。")
	var restored := _restore_saved_run(session)
	if not restored.ok:
		return restored
	if session.current_run.run_complete or session.current_run.run_failed:
		return _failure("本次冒险已经结束。")
	return _success(AdventureSessionService.BATTLE_SCENE_PATH if session.has_pending_battle() else AdventureSessionService.MAP_SCENE_PATH)


static func prepare_return_to_menu(session: AdventureSessionService, from_battle: bool) -> Dictionary:
	if from_battle:
		var restored := _restore_saved_run(session)
		if not restored.ok:
			return restored
	elif session.current_run != null:
		var error := session.save_store.save_run(session.current_run)
		if error != OK:
			return _failure("保存失败，仍停留在当前页面：%s" % error_string(error))
	return _success(MAIN_MENU_PATH)


static func _restore_saved_run(session: AdventureSessionService) -> Dictionary:
	var loaded := session.save_store.load_run()
	if loaded == null:
		return _failure("无法恢复有效存档；当前场景仍然保留。")
	var scenario: BattleScenario
	var transaction := loaded.pending_transaction
	if transaction != null and not transaction.committed and transaction.transaction_type == AdventureEnums.TransactionType.BATTLE:
		scenario = AdventureBattleScenarioBuilder.build(loaded, transaction.payload)
		if scenario == null or scenario.players.is_empty():
			return _failure("无法重建本场战斗。")
	var previous := session.current_run
	var previous_scenario := session.pending_battle_scenario
	session.current_run = loaded
	session.pending_battle_scenario = scenario
	var recovered := true
	if transaction != null and not transaction.committed:
		match transaction.transaction_type:
			AdventureEnums.TransactionType.MOVE:
				recovered = bool(session._finish_pending_move().get("ok", false)) and session._save_only()
			AdventureEnums.TransactionType.SHOP:
				recovered = bool(AdventureShopService.apply_pending_restock(loaded).get("ok", false)) and session._save_only()
	if not recovered:
		session.current_run = previous
		session.pending_battle_scenario = previous_scenario
		return _failure("恢复待处理事务失败，请重试。")
	session.state_changed.emit()
	return _success(MAIN_MENU_PATH)


static func _success(path: String) -> Dictionary:
	return {"ok": true, "message": "", "scene_path": path}


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message, "scene_path": ""}
