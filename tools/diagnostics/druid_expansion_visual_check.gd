extends Node


const OUTPUT := "res://.superpowers/sdd/2026-09-22-druid-expansion/screenshots"

var failures := 0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("DRUID_EXPANSION_VISUAL: requires a rendered viewport")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	await _capture_wellspring_recovery()
	await _capture_continuous_target_picker()
	await _capture_twin_detail_rulings()
	print("DRUID_EXPANSION_VISUAL: %s" % ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)


func _capture_wellspring_recovery() -> void:
	for dimensions in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		await _set_viewport(dimensions)
		var scene := await _new_battle_scene()
		var owner := _active_druid(scene)
		if owner == null:
			_check(false, "mana-recovery fixture has a druid")
			await _free_scene(scene)
			continue
		var card := _card_copy("druid_wellspring_return")
		var mana_card := _card_copy("druid_wild_wander")
		owner.hand.append(card)
		owner.mana_zone.append(mana_card)
		_check(scene.controller.play_card(owner, card, []), "mana recovery starts")
		scene.call("_refresh")
		await _capture("druid-wellspring-recovery-%dx%d.png" % [dimensions.x, dimensions.y], dimensions)
		var picker := scene.get("_zone_card_picker") as Window
		_check(picker != null and picker.visible and _window_fits(picker) and _window_is_compact(picker), "mana recovery picker fits compactly at %dx%d" % [dimensions.x, dimensions.y])
		if picker != null:
			picker.call("_skip_selection")
		await _frames(2)
		await _free_scene(scene)


func _capture_continuous_target_picker() -> void:
	for dimensions in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		await _set_viewport(dimensions)
		var scene := await _new_battle_scene()
		var owner := _active_druid(scene)
		if owner == null:
			_check(false, "continuous-target fixture has a druid")
			await _free_scene(scene)
			continue
		owner.set_druid_transformed(true)
		owner.gain_mana(2, {"controller": scene.controller})
		owner.draw_pile.append_array([CardData.new(), CardData.new()])
		var card := _card_copy("druid_wellspring_return")
		owner.hand.append(card)
		var target := scene.controller.enemy_units[0] as BattleUnitState
		if target != null:
			target.is_deployed = true
			target.set_hex_cell(Vector2i(5, 4), scene.controller.map_data)
		_check(target != null and scene.controller.play_card(owner, card, []), "continuous strike starts")
		scene.call("_refresh")
		await _capture("druid-continuous-target-picker-%dx%d.png" % [dimensions.x, dimensions.y], dimensions)
		var picker := scene.get("_unit_target_picker") as Window
		_check(picker != null and picker.visible and _window_fits(picker) and _window_is_compact(picker) and _has_button(picker, "结束"), "continuous target picker fits compactly and offers early finish at %dx%d" % [dimensions.x, dimensions.y])
		if picker != null:
			picker.call("_submit", null)
		await _frames(2)
		await _free_scene(scene)


func _capture_twin_detail_rulings() -> void:
	var encyclopedia := CardEncyclopedia.new()
	encyclopedia.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(encyclopedia)
	await _frames(2)
	var whisper := load("res://resources/cards/druid_spirit_whisper.tres") as CardData
	_check(whisper != null, "Whisper resource loads for detailed ruling render")
	if whisper != null:
		encyclopedia.show_card(whisper, false)
		for dimensions in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
			await _set_viewport(dimensions)
			encyclopedia.show_card(whisper, false)
			var scroll := _find_scroll_container(encyclopedia)
			if scroll != null:
				scroll.scroll_vertical = scroll.get_v_scroll_bar().max_value
			await _capture("druid-whisper-upright-detail-%dx%d.png" % [dimensions.x, dimensions.y], dimensions)
			_check(_fits(encyclopedia.detail_rules) and encyclopedia.detail_rules.text.contains("支付2 AP"), "Whisper upright detailed ruling is visible at %dx%d" % [dimensions.x, dimensions.y])
		encyclopedia.show_card(whisper, true)
		for dimensions in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
			await _set_viewport(dimensions)
			encyclopedia.show_card(whisper, true)
			var scroll := _find_scroll_container(encyclopedia)
			if scroll != null:
				scroll.scroll_vertical = scroll.get_v_scroll_bar().max_value
			await _capture("druid-whisper-inverted-detail-%dx%d.png" % [dimensions.x, dimensions.y], dimensions)
			_check(_fits(encyclopedia.detail_rules) and encyclopedia.detail_rules.text.contains("一次性响应"), "Whisper inverted detailed ruling is visible at %dx%d" % [dimensions.x, dimensions.y])
	encyclopedia.queue_free()
	await _frames(1)


func _new_battle_scene() -> BattleScene:
	var scene := (load("res://scenes/battle_scene.tscn") as PackedScene).instantiate() as BattleScene
	add_child(scene)
	await _frames(3)
	scene.controller.phase = BattleController.Phase.BATTLE
	scene.controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	var owner := _active_druid(scene)
	if owner != null:
		owner.is_deployed = true
		owner.set_hex_cell(Vector2i(4, 4), scene.controller.map_data)
		owner.current_ap = 10
		scene.controller.current_unit = owner
	return scene


func _active_druid(scene: BattleScene) -> BattleUnitState:
	for unit_value in scene.controller.player_units:
		var unit := unit_value as BattleUnitState
		if unit != null and unit.is_druid():
			return unit
	return null


func _card_copy(card_id: String) -> CardData:
	var template := load("res://resources/cards/%s.tres" % card_id) as CardData
	return template.duplicate(true) as CardData if template != null else null


func _capture(filename: String, dimensions: Vector2i) -> void:
	await _frames(5)
	await RenderingServer.frame_post_draw
	var screenshot := get_viewport().get_texture().get_image()
	_check(screenshot.save_png(OUTPUT.path_join(filename)) == OK, "screenshot " + filename)


func _set_viewport(dimensions: Vector2i) -> void:
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = dimensions
	get_window().content_scale_size = dimensions
	await _frames(5)


func _fits(control: Control) -> bool:
	if control == null:
		return false
	var rect := control.get_global_rect()
	return rect.position.x >= 0 and rect.position.y >= 0 and rect.end.x <= get_viewport().get_visible_rect().size.x + 1 and rect.end.y <= get_viewport().get_visible_rect().size.y + 1


func _window_fits(window: Window) -> bool:
	if window == null:
		return false
	var viewport_size := get_viewport().get_visible_rect().size
	var rect := Rect2(Vector2(window.position), Vector2(window.size))
	return rect.position.x >= 0 and rect.position.y >= 0 and rect.end.x <= viewport_size.x + 1 and rect.end.y <= viewport_size.y + 1


func _window_is_compact(window: Window) -> bool:
	if window == null:
		return false
	return float(window.size.y) <= get_viewport().get_visible_rect().size.y * 0.8


func _has_button(root: Node, fragment: String) -> bool:
	if root is Button and (root as Button).text.contains(fragment):
		return true
	for child in root.get_children():
		if _has_button(child, fragment):
			return true
	return false


func _find_scroll_container(root: Node) -> ScrollContainer:
	if root is ScrollContainer:
		return root as ScrollContainer
	for child in root.get_children():
		var found := _find_scroll_container(child)
		if found != null:
			return found
	return null


func _frames(count: int) -> void:
	for _frame in range(count):
		await get_tree().process_frame


func _free_scene(scene: BattleScene) -> void:
	scene.queue_free()
	await _frames(2)


func _check(value: bool, label: String) -> void:
	if value:
		return
	failures += 1
	printerr("DRUID_EXPANSION_VISUAL: " + label)
