extends Node
var failures := 0

func _ready() -> void:
	var packed := load("res://scenes/adventure_map_scene.tscn") as PackedScene
	for status in [AdventureSaveSchema.LoadStatus.UNSUPPORTED_SCHEMA, AdventureSaveSchema.LoadStatus.LEGACY_SAVE_DETECTED]:
		var session := AdventureSessionService.new()
		session.save_store = AdventureSaveStore.new("hex_diagnostic_startup_ui")
		session.save_store.load_status = status
		var scene := packed.instantiate() as AdventureMapScene
		scene.session = session
		add_child(scene)
		await get_tree().process_frame
		_check(session.current_run == null and scene.modal_layer.visible, "incompatible save waits for an explicit choice")
		_check(scene.map_view.room_nodes.is_empty(), "incompatible save cannot silently generate map")
		scene._copy_seed()
		if status == AdventureSaveSchema.LoadStatus.UNSUPPORTED_SCHEMA:
			scene._confirm_new_run(99)
			_check(session.current_run == null, "future schema cannot be overwritten through normal new-run control")
			scene._begin_new_run_from_gate()
			_check(session.current_run == null, "future schema cannot be overwritten through gate")
		else:
			scene._begin_new_run_from_gate()
			_check(session.current_run != null and scene.run_state != null, "legacy gate can explicitly start isolated hex run")
			_check(scene.map_view.room_nodes.size() == 48, "explicit new run appears immediately")
		scene.free()
		session.save_store.delete_save()
		session.free()
	print("HEX_STARTUP: %s" % ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)

func _check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		printerr("HEX_STARTUP: " + label)
