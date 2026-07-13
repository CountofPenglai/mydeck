extends Node

var _exit_code := 0


func _ready() -> void:
	print("DIAG: loading all project resources")
	_load_resources("res://resources")
	print("DIAG: instantiating battle scene")
	var packed := load("res://scenes/battle_scene.tscn") as PackedScene
	if packed == null:
		_fail("DIAG: failed to load battle_scene.tscn")
		get_tree().quit(_exit_code)
		return

	var scene := packed.instantiate()
	if scene == null:
		_fail("DIAG: failed to instantiate battle_scene.tscn")
		get_tree().quit(_exit_code)
		return

	get_tree().root.add_child.call_deferred(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	var controller_value = scene.get("controller")
	if controller_value is BattleController:
		var controller := controller_value as BattleController
		_deploy_players(controller)
		_start_battle(controller)
	else:
		_fail("DIAG: battle scene has no BattleController controller property")

	await get_tree().process_frame
	await get_tree().process_frame
	print("DIAG: completed")
	get_tree().quit(_exit_code)


func _deploy_players(controller: BattleController) -> void:
	print("DIAG: deploying players")
	for index in range(controller.player_units.size()):
		var unit: BattleUnitState = controller.player_units[index]
		var cell := Vector2i(index % controller.map_data.player_deployment_columns, index + 2)
		if not controller.deploy_player_unit_at_cell(unit, cell):
			_fail("DIAG: failed to deploy %s at %s" % [unit.get_display_name(), cell])


func _start_battle(controller: BattleController) -> void:
	print("DIAG: starting battle through controller")
	if not controller.start_battle():
		_fail("DIAG: controller.start_battle returned false")
		return

	if controller.current_unit == null:
		_fail("DIAG: battle started without current_unit")
		return

	print("DIAG: current unit %s AP %d/%d HP %d/%d hand %d" % [
		controller.current_unit.get_display_name(),
		controller.current_unit.current_ap,
		controller.current_unit.get_max_ap(controller.config),
		controller.current_unit.get_current_health(),
		controller.current_unit.get_max_health(),
		controller.current_unit.hand.size(),
	])


func _load_resources(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		_fail("DIAG: cannot open %s" % path)
		return

	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue

		var full_path := path.path_join(entry)
		if dir.current_is_dir():
			_load_resources(full_path)
		elif entry.ends_with(".tres") or entry.ends_with(".tscn"):
			var resource := load(full_path)
			if resource == null:
				_fail("DIAG: failed to load %s" % full_path)

		entry = dir.get_next()
	dir.list_dir_end()


func _fail(message: String) -> void:
	_exit_code = 1
	push_error(message)
	print("ERROR: " + message)
