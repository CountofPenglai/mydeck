extends Node

var failures := 0


func _ready() -> void:
	var service_path := "res://scripts/adventure/adventure_battle_danger_service.gd"
	_check(ResourceLoader.exists(service_path), "battle danger service is missing")
	if failures > 0:
		get_tree().quit(1)
		return
	var service: Script = load(service_path)
	var fish := ChapterOneEnemyCatalog.create_enemy(&"hungry_fish", 12)
	var enemies: Array[EnemyState] = [fish]
	var snapshot: Dictionary = service.create_snapshot(18, 1, enemies, 91)
	_check(int(snapshot.get("bonus_percent", -1)) == 40, "danger 18 must use a 40 percent bonus")
	_check((snapshot.get("initial_assignments", []) as Array).size() == 1, "danger 18 assigns every initial enemy")
	var base_health := fish.get_max_health()
	service.apply_enemy(fish, snapshot, 0)
	_check(fish.get_max_health() == ceili(float(base_health) * 1.4), "health bonus must round upward from base health")
	var once := fish.get_max_health()
	service.apply_enemy(fish, snapshot, 0)
	_check(fish.get_max_health() == once, "danger application must be idempotent")
	fish.runtime_state["max_health_override"] = 7
	_check(fish.get_max_health() == 10, "fish inverse fixed health must retain danger scaling")
	_test_fixed_health_and_damage(service)
	_test_assignment_and_transfer(service)
	_test_thresholds_and_reinforcement_replay(service)
	_test_battle_controller_damage_paths(service)
	_test_all_enemy_prototypes(service)
	_test_real_form_and_summon_paths(service)
	_test_slider_preview_selection(service)
	print("HEX_BATTLE_DANGER: %s" % ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)


func _test_fixed_health_and_damage(service: Script) -> void:
	var spawn := ChapterTwoEnemyCatalog.create_enemy(&"flesh_spawn", 31)
	var spawn_enemies: Array[EnemyState] = [spawn]
	var spawn_snapshot: Dictionary = service.create_snapshot(18, 2, spawn_enemies, 55)
	service.apply_enemy(spawn, spawn_snapshot, 0)
	_check(spawn.get_max_health() == 3, "fixed base health must receive the 40 percent danger bonus")
	var source := BattleUnitState.new()
	source.enemy_state = spawn
	_check(service.scale_damage(5, source, {}) == 7, "enemy direct damage must round at the danger boundary")
	_check(service.scale_damage(5, source, {"environmental": true}) == 5, "environmental damage must not scale")
	_check(service.scale_damage(5, source, {"target": source}) == 5, "self damage must not scale")


func _test_assignment_and_transfer(service: Script) -> void:
	var first := ChapterOneEnemyCatalog.create_enemy(&"hungry_fish", 41)
	var second := ChapterOneEnemyCatalog.create_enemy(&"hungry_fish", 42)
	var pair: Array[EnemyState] = [first, second]
	var danger_six: Dictionary = service.create_snapshot(6, 1, pair, 71)
	_check((danger_six.get("initial_assignments", []) as Array).size() == 1, "danger six must assign exactly one tied initial enemy")
	var guard := ChapterTwoEnemyCatalog.create_enemy(&"gray_shield_guard", 43)
	var pool: Script = load("res://scripts/adventure/adventure_battle_danger_mutation_pool.gd")
	_check(not (pool.candidates(2, guard) as Array).has("rock_scale"), "native mutation must be excluded from danger pool")
	var heart_for_mutation := ChapterTwoEnemyCatalog.create_enemy(&"corrupt_heart_veil", 430)
	_check(not (pool.candidates(2, heart_for_mutation) as Array).has("enlightenment"), "corrupt heart without a self-curse-wave source must not receive enlightenment")
	var old_state := ChapterOneEnemyCatalog.create_enemy(&"hungry_fish", 44)
	var one_enemy: Array[EnemyState] = [old_state]
	service.apply_enemy(old_state, service.create_snapshot(18, 1, one_enemy, 72), 0)
	var new_state := ChapterTwoEnemyCatalog.create_enemy(&"military_god_remains", 45)
	service.transfer_form(old_state, new_state)
	_check(new_state.danger_mutation_fields == old_state.danger_mutation_fields and new_state.danger_bonus_percent == 40, "form transfer must retain danger source and bonus")
	new_state.runtime_state["max_health_override"] = 75
	new_state.runtime_state["danger_unscaled_health_bonus"] = 47
	_check(new_state.get_max_health() == 152, "paladin merge must not rescale absorbed statue current health")
	var corrupt_heart := ChapterTwoEnemyCatalog.create_enemy(&"corrupt_heart_veil", 46)
	var heart_enemies: Array[EnemyState] = [corrupt_heart]
	service.apply_enemy(corrupt_heart, service.create_snapshot(18, 2, heart_enemies, 73), 0)
	corrupt_heart.runtime_state["max_health_override"] = 169
	_check(corrupt_heart.get_max_health() == 237, "corrupt heart phase two fixed health must retain danger scaling")
	var distortions := DistortionBattleState.new()
	distortions.danger_fields = PackedStringArray(["night_veil"])
	var manifested := CardData.new()
	manifested.mutation_fields = PackedStringArray(["night_veil"])
	distortions.register_manifestation(manifested)
	distortions.unregister_manifestation(manifested)
	_check(distortions.has_field("night_veil"), "removing a same-name temporary mutation must retain danger source")


func _test_thresholds_and_reinforcement_replay(service: Script) -> void:
	var thresholds := {
		6: {"bonus": 10, "initial": 1},
		12: {"bonus": 20, "initial": 2},
		18: {"bonus": 40, "initial": 2},
		24: {"bonus": 60, "initial": 2},
	}
	for danger in thresholds:
		var first := ChapterOneEnemyCatalog.create_enemy(&"hungry_fish", danger)
		var second := ChapterOneEnemyCatalog.create_enemy(&"harpoon_fish", danger)
		var initial_enemies: Array[EnemyState] = [first, second]
		var snapshot: Dictionary = service.create_snapshot(danger, 1, initial_enemies, 800 + danger)
		var expected: Dictionary = thresholds[danger]
		_check(int(snapshot.get("bonus_percent", -1)) == int(expected["bonus"]), "danger %d must use its configured bonus" % danger)
		_check((snapshot.get("initial_assignments", []) as Array).size() == int(expected["initial"]), "danger %d must assign the configured initial enemy count" % danger)

	var no_initial_enemies: Array[EnemyState] = []
	var danger_six: Dictionary = service.create_snapshot(6, 1, no_initial_enemies, 901)
	var six_reinforcement := ChapterOneEnemyCatalog.create_enemy(&"hungry_fish", 902)
	service.apply_enemy(six_reinforcement, danger_six, -1, true)
	_check(six_reinforcement.danger_mutation_fields.is_empty(), "danger-six reinforcement must not receive a mutation")
	_check(six_reinforcement.danger_bonus_percent == 10, "danger-six reinforcement must retain the numeric bonus")

	var danger_twelve: Dictionary = service.create_snapshot(12, 1, no_initial_enemies, 903)
	var first_reinforcement := ChapterOneEnemyCatalog.create_enemy(&"hungry_fish", 904)
	service.apply_enemy(first_reinforcement, danger_twelve, -1, true)
	var assignments: Array = danger_twelve.get("reinforcement_assignments", []) as Array
	_check(assignments.size() == 1 and first_reinforcement.danger_mutation_fields.size() == 1, "danger-twelve reinforcement must receive exactly one mutation")
	_check(assignments.size() == 1 and int((assignments[0] as Dictionary).get("serial", -1)) == 0, "first reinforcement must record serial zero")
	var replay := danger_twelve.duplicate(true)
	replay["spawn_serial"] = 0
	var replayed_reinforcement := ChapterOneEnemyCatalog.create_enemy(&"harpoon_fish", 905)
	service.apply_enemy(replayed_reinforcement, replay, -1, true)
	var replay_assignments: Array = replay.get("reinforcement_assignments", []) as Array
	_check(replay_assignments.size() == 1, "replaying an existing reinforcement serial must not append another assignment")
	_check(replayed_reinforcement.danger_mutation_fields == first_reinforcement.danger_mutation_fields, "replaying a reinforcement serial must reuse its recorded mutation")


func _test_battle_controller_damage_paths(service: Script) -> void:
	var enemy := ChapterTwoEnemyCatalog.create_enemy(&"flesh_spawn", 1001)
	var one_enemy: Array[EnemyState] = [enemy]
	service.apply_enemy(enemy, service.create_snapshot(18, 2, one_enemy, 1002), 0)
	var source := BattleUnitState.new()
	source.setup_enemy(1, enemy, 24.0)
	var target := BattleUnitState.new()
	target.setup_curse_proxy(2, source, "danger target", 100, false, false, 1)
	var controller := BattleController.new()
	controller.setup(null)
	_check(controller.apply_damage(source, target, 5, "danger direct") == 7, "BattleController direct damage must use danger scaling")
	target.curse_proxy_health = 100
	_check(controller.apply_damage(source, target, 5, "danger fixed", {"fixed_damage": true}) == 7, "BattleController fixed damage must use danger scaling")
	target.curse_proxy_health = 100
	_check(controller.apply_damage(source, target, 5, "danger environment", {"environmental": true}) == 5, "BattleController environmental damage must not use danger scaling")


func _test_all_enemy_prototypes(service: Script) -> void:
	for archetype in ChapterOneEnemyCatalog.ENEMY_ART:
		_assert_prototype_assignment(service, 1, archetype)
	for archetype in ChapterTwoEnemyCatalog.ENEMY_ART:
		_assert_prototype_assignment(service, 2, archetype)


func _test_real_form_and_summon_paths(service: Script) -> void:
	var fish_controller := _danger_controller(1, [&"hungry_fish"], service)
	if fish_controller != null:
		var fish := fish_controller.enemy_units[0]
		fish_controller.apply_damage(null, fish, 999, "danger fish", {"fixed_damage": true})
		_check(bool(fish.enemy_state.runtime_state.get("reversed", false)), "real hungry-fish inverse path must execute")
		_check(fish.get_max_health() == 10, "real hungry-fish inverse must retain danger scaling")
	var paladin_controller := _danger_controller(2, [&"gray_bastion_paladin", &"triumph_statue"], service)
	if paladin_controller != null:
		var paladin := paladin_controller.enemy_units[0]
		ChapterTwoEnemyRules.resolve_paladin_merge(paladin_controller, paladin)
		_check(paladin.enemy_state.enemy_data.archetype_id == &"military_god_remains", "real paladin merge must execute")
		_check(paladin.enemy_state.danger_bonus_percent == 40, "real paladin merge must retain danger bonus")
	var veil_controller := _danger_controller(2, [&"corrupt_heart_veil"], service)
	if veil_controller != null:
		var veil := veil_controller.enemy_units[0]
		ChapterTwoEnemyRules.execute_intent_step(veil_controller, veil, {"type": "chapter_two_special", "action": "gospel"})
		_check(int(veil.enemy_state.runtime_state.get("phase", 0)) == 2, "real corrupt-heart gospel phase must execute")
		_check(veil.enemy_state.danger_bonus_percent == 40 and veil.get_max_health() == 237, "real corrupt-heart phase must retain danger scaling")
	var summon_controller := _danger_controller(2, [&"blood_construct"], service)
	if summon_controller != null:
		var owner := summon_controller.enemy_units[0]
		ChapterTwoEnemyRules.execute_intent_step(summon_controller, owner, {"type": "chapter_two_special", "action": "construct_spawn"})
		var spawned: BattleUnitState = null
		for unit in summon_controller.enemy_units:
			if unit != owner and unit.enemy_state != null and unit.enemy_state.enemy_data.archetype_id == &"flesh_spawn":
				spawned = unit
		_check(spawned != null, "real blood-construct summon path must spawn flesh")
		if spawned != null:
			_check(spawned.enemy_state.danger_bonus_percent == 40, "real flesh spawn must inherit snapshot bonus")
			_check(spawned.get_max_health() == 3 and spawned.get_current_health() == 3, "real flesh spawn must retain its fixed danger-scaled health after setup")
			owner.gain_curse_wave(1, {"controller": summon_controller, "reason": "danger devour fixture"})
			ChapterTwoEnemyRules.execute_intent_step(summon_controller, owner, {"type": "chapter_two_special", "action": "construct_invert"})
			ChapterTwoEnemyRules.execute_intent_step(summon_controller, owner, {"type": "chapter_two_special", "action": "construct_devour"})
			_check(owner.get_max_health() == 43, "devouring danger-scaled flesh must add its current health without rescaling it")
			_check(owner.get_current_health() == 33, "devouring danger-scaled flesh must add its current health exactly once")


func _test_slider_preview_selection(service: Script) -> void:
	var first := ChapterOneEnemyCatalog.create_enemy(&"hungry_fish", 6101)
	var second := ChapterOneEnemyCatalog.create_enemy(&"harpoon_fish", 6102)
	first.runtime_state["max_health_override"] = 101
	second.runtime_state["max_health_override"] = 102
	first.max_health_percent = 50
	second.max_health_percent = 50
	var enemies: Array[EnemyState] = [first, second]
	for seed in range(1, 25):
		var snapshot: Dictionary = service.create_snapshot(6, 1, enemies, seed)
		var assignments: Array = snapshot.get("initial_assignments", []) as Array
		_check(assignments.size() == 1 and int((assignments[0] as Dictionary).get("slot", -1)) == 1, "danger-six preview must select the actual highest slider-scaled enemy")


func _danger_controller(chapter: int, archetypes: Array, service: Script) -> BattleController:
	var template := load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario
	if template == null:
		_check(false, "missing sample battle scenario")
		return null
	var scenario := template.duplicate(true) as BattleScenario
	scenario.scene_prototype = null
	scenario.enemies.clear()
	var states: Array[EnemyState] = []
	for index in range(archetypes.size()):
		var state := EnemyCatalogRouter.create_enemy(chapter, StringName(archetypes[index]), 5000 + index)
		states.append(state)
		scenario.enemies.append(state)
	scenario.danger_snapshot = service.create_snapshot(18, chapter, states, 5100)
	var controller := BattleController.new()
	controller.setup(scenario)
	return controller


func _assert_prototype_assignment(service: Script, chapter: int, archetype: StringName) -> void:
	var state := EnemyCatalogRouter.create_enemy(chapter, archetype, archetype.hash())
	_check(state != null, "chapter %d prototype %s must be constructible" % [chapter, archetype])
	if state == null:
		return
	var initial_enemy: Array[EnemyState] = [state]
	var snapshot: Dictionary = service.create_snapshot(24, chapter, initial_enemy, 1200 + archetype.hash())
	var assignments: Array = snapshot.get("initial_assignments", []) as Array
	_check(assignments.size() == 1, "chapter %d prototype %s must have one compatible danger mutation" % [chapter, archetype])
	if assignments.is_empty():
		return
	var field_id := str((assignments[0] as Dictionary).get("field_id", ""))
	_check(not state.enemy_data.permanent_distortion_fields.has(field_id), "chapter %d prototype %s must not duplicate its native mutation" % [chapter, archetype])


func _check(value: bool, message: String) -> void:
	if value:
		return
	failures += 1
	printerr("HEX_BATTLE_DANGER: " + message)
