extends Node

# Task 3 contract diagnostic: real resources, controller, and live BattleScene.
var _exit_code := 0
var _lockdown_plan_at_damage := -1
var _observed_lockdown_plan: EnemyIntentPlan

func _ready() -> void:
	_test_resource_contracts()
	_test_waiting_prey_controller_contracts()
	_test_waiting_prey_rejects_non_ranger_holder()
	_test_lockdown_controller_contracts()
	_test_lockdown_rejects_card_protected_enemy()
	await _test_live_intent_popup_path()
	await _test_live_lockdown_weapon_then_intent_path()
	print("RANGER_REWORK_CARDS_DIAG: completed")
	get_tree().quit(_exit_code)

func _test_resource_contracts() -> void:
	var tether := load("res://resources/cards/ranger_crossbow_tether.tres") as CardData
	var bait := load("res://resources/cards/ranger_exotic_sampling.tres") as CardData
	var prey := load("res://resources/cards/ranger_waiting_prey.tres") as CardData
	var flavor := load("res://resources/cards/ranger_full_flavor.tres") as CardData
	if tether == null or tether.rarity != 0:
		_fail("resource: tether is not common")
	if bait == null or bait.ap_cost != 2 or bait.effect is not RangerExoticSamplingCardEffect:
		_fail("resource: bait is not the 2 AP elemental placement card")
	if prey == null or prey.card_type != CardEnums.CardType.SKILL or prey.ap_cost != 1:
		_fail("resource: waiting prey is not a 1 AP skill")
	if flavor == null or flavor.rarity != 0 or flavor.ap_cost != 1:
		_fail("resource: full flavor is not common / 1 AP")
	if bait != null and not bait.card_text.contains("【爆炸】"):
		_fail("resource: bait card face omits the approved explosion definition")

func _make_active_controller() -> BattleController:
	var template := load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario
	if template == null:
		_fail("fixture: sample scenario is missing")
		return null
	var controller := BattleController.new()
	controller.setup(template.duplicate(true) as BattleScenario)
	for index in range(controller.player_units.size()):
		var unit: BattleUnitState = controller.player_units[index]
		if not controller.deploy_player_unit_at_cell(unit, Vector2i(index % controller.map_data.player_deployment_columns, index + 2)):
			_fail("fixture: could not deploy %s" % unit.get_display_name())
	controller.phase = BattleController.Phase.BATTLE
	controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	var ranger := _find_ranger(controller)
	if ranger == null or controller.enemy_units.is_empty():
		_fail("fixture: ranger or enemy missing")
		return controller
	ranger.current_ap = 9
	controller.current_unit = ranger
	controller.turn_order.clear()
	controller.turn_order.append(ranger)
	controller.turn_order.append_array(controller.enemy_units)
	return controller

func _configure_public_plan(controller: BattleController, category: int = EnemyIntentCategory.Type.ATTACK) -> EnemyIntentPlan:
	var enemy: BattleUnitState = controller.enemy_units[0]
	var plan := enemy.enemy_state.intent_plan
	plan.configure(PackedInt32Array([category]), EnemyIntentCategory.Type.ATTACK, controller.battle_round + 1)
	return plan

func _test_waiting_prey_controller_contracts() -> void:
	var controller := _make_active_controller()
	if controller == null:
		return
	var ranger := _find_ranger(controller)
	var prey_template := load("res://resources/cards/ranger_waiting_prey.tres") as CardData
	var plan := _configure_public_plan(controller)
	var prey := prey_template.duplicate(true) as CardData
	ranger.hand.append(prey)
	var effect := prey.effect as RangerWaitingPreyCardEffect
	var options := effect.get_enemy_intent_choice_options({"controller": controller, "user": ranger, "card": prey})
	if options.size() < 2:
		_fail("prey: configured public primary and fallback plans were not both selectable")
		return
	var ap_before := ranger.current_ap
	if controller.play_card(ranger, prey, [], {"enemy_intent_choice": options[0]}):
		if plan.primary_ap_reductions.size() != 1 or plan.primary_ap_reductions[0] != 1:
			_fail("prey: primary choice did not steal exactly 1 AP")
		# The card costs 1 AP and steals 1 AP, so the net pool remains unchanged.
		if ranger.current_ap != ap_before or ranger.hand.has(prey) or not ranger.discard_pile.has(prey):
			_fail("prey: valid primary choice did not preserve net AP while moving exactly once to discard")
	else:
		_fail("prey: valid primary choice was rejected by controller.play_card")
	var fallback := prey_template.duplicate(true) as CardData
	ranger.hand.append(fallback)
	var fallback_choice: Dictionary = {}
	for choice in effect.get_enemy_intent_choice_options({"controller": controller, "user": ranger, "card": fallback}):
		if bool(choice.get("is_fallback", false)):
			fallback_choice = choice
	if fallback_choice.is_empty() or not controller.play_card(ranger, fallback, [], {"enemy_intent_choice": fallback_choice}):
		_fail("prey: valid fallback choice was rejected")
	elif plan.fallback_ap_reduction != 1:
		_fail("prey: fallback did not steal exactly 1 AP")
	plan.prepare_execution(controller.enemy_units[0].get_max_ap(controller.config))
	if plan.execution_groups.is_empty() or plan.execution_groups[0].allocated_ap != 1:
		_fail("prey: next-turn primary allocation did not reflect stolen AP")
	for rejection in ["missing", "prepared", "zero", "stale"]:
		var rejected := prey_template.duplicate(true) as CardData
		ranger.hand.append(rejected)
		var before_ap := ranger.current_ap
		var before_hand := ranger.hand.size()
		var before_stolen := plan.stolen_ap_total
		var context := {}
		if rejection == "prepared": context["enemy_intent_choice"] = fallback_choice
		elif rejection == "stale":
			# Replace the live plan with a real fresh public plan; a stale choice must
			# not be masked merely because the old plan was execution-prepared.
			var replacement := EnemyIntentPlan.new()
			replacement.configure(PackedInt32Array([EnemyIntentCategory.Type.ATTACK]), EnemyIntentCategory.Type.ATTACK, controller.battle_round + 1)
			controller.enemy_units[0].enemy_state.intent_plan = replacement
			context["enemy_intent_choice"] = fallback_choice
		elif rejection == "zero":
			plan.execution_prepared = false; plan.stolen_ap_total = controller.enemy_units[0].get_max_ap(controller.config); before_stolen = plan.stolen_ap_total; context["enemy_intent_choice"] = fallback_choice
		if controller.play_card(ranger, rejected, [], context): _fail("prey: %s selection unexpectedly paid and played" % rejection)
		if ranger.current_ap != before_ap or ranger.hand.size() != before_hand or plan.stolen_ap_total != before_stolen:
			_fail("prey: %s rejection mutated AP, hand, or intent budget" % rejection)
		ranger.hand.erase(rejected)
		if rejection != "stale": plan.execution_prepared = true; plan.stolen_ap_total = before_stolen


func _test_waiting_prey_rejects_non_ranger_holder() -> void:
	var controller := _make_active_controller()
	if controller == null:
		return
	var holder: BattleUnitState = null
	for unit in controller.player_units:
		if unit != null and not unit.is_ranger():
			holder = unit
			break
	if holder == null:
		_fail("prey non-ranger: fixture has no other live player")
		return
	controller.current_unit = holder
	holder.current_ap = 9
	var plan := _configure_public_plan(controller)
	var card := (load("res://resources/cards/ranger_waiting_prey.tres") as CardData).duplicate(true) as CardData
	holder.hand.append(card)
	var choice := {"enemy": controller.enemy_units[0], "enemy_id": controller.enemy_units[0].get_instance_id(), "plan_id": plan.get_instance_id(), "slot_index": 0, "is_fallback": false}
	var ap_before := holder.current_ap
	if controller.play_card(holder, card, [], {"enemy_intent_choice": choice}) \
			or holder.current_ap != ap_before or not holder.hand.has(card) or plan.stolen_ap_total != 0:
		_fail("prey non-ranger: held card paid, discarded, or interfered with the plan")

func _test_live_intent_popup_path() -> void:
	var packed := load("res://scenes/battle_scene.tscn") as PackedScene
	if packed == null: _fail("ui: battle scene is missing"); return
	var scene := packed.instantiate() as BattleScene
	add_child(scene)
	await get_tree().process_frame
	var controller := scene.controller
	var ranger := _find_ranger(controller)
	if controller == null or ranger == null or controller.enemy_units.is_empty():
		_fail("ui: scene did not create ranger fixture"); scene.queue_free(); return
	controller.phase = BattleController.Phase.BATTLE
	controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	controller.current_unit = ranger
	ranger.current_ap = 9
	_configure_public_plan(controller)
	var prey := (load("res://resources/cards/ranger_waiting_prey.tres") as CardData).duplicate(true) as CardData
	ranger.hand.append(prey)
	var ap_before := ranger.current_ap
	# Normal initial selection continuation, deliberately not _show_intent_choice.
	scene._select_card(prey)
	await get_tree().process_frame
	if scene._intent_choice_popup == null or not scene._intent_choice_popup.visible:
		_fail("ui: initial card selection did not open the enemy-intent PopupPanel")
	else:
		var cancel := _find_button(scene._intent_choice_list, "取消")
		if cancel == null: _fail("ui: intent PopupPanel has no actual cancel button")
		else:
			cancel.emit_signal("pressed")
			await get_tree().process_frame
			if ranger.current_ap != ap_before or not ranger.hand.has(prey) or scene.input_mode != BattleScene.InputMode.NONE:
				_fail("ui: cancelling intent selection mutated card/AP or left input active")
			# Re-enter via initial selection and press the live option button; this
			# intentionally proves both routes without ever calling _show_intent_choice.
			scene._select_card(prey)
			await get_tree().process_frame
			var choice_button := _first_choice_button(scene._intent_choice_list)
			if choice_button == null:
				_fail("ui: intent PopupPanel has no selectable intent button")
			else:
				choice_button.emit_signal("pressed")
				await get_tree().process_frame
				if ranger.hand.has(prey) or ranger.current_ap != ap_before:
					_fail("ui: confirmed intent button did not execute the real card path")
	scene.queue_free()

func _test_lockdown_controller_contracts() -> void:
	var controller := _make_active_controller()
	if controller == null: return
	var ranger := _find_ranger(controller)
	var enemy: BattleUnitState = controller.enemy_units[0]
	ranger.set_hex_cell(Vector2i(2, 3), controller.map_data)
	enemy.set_hex_cell(Vector2i(3, 3), controller.map_data)
	var card := (load("res://resources/cards/ranger_hunting_ground_lockdown.tres") as CardData).duplicate(true) as CardData
	var plan := _configure_public_plan(controller, EnemyIntentCategory.Type.ATTACK)
	ranger.hand.append(card)
	var options := card.get_enemy_intent_choice_options({"controller": controller, "user": ranger, "card": card, "equipment_slot": "paired"})
	if options.is_empty():
		_fail("lockdown: ranged weapon did not offer in-range ATTACK intent")
		return
	var health_before := enemy.get_current_health()
	_observed_lockdown_plan = plan
	_lockdown_plan_at_damage = -1
	controller.log_message.connect(_observe_lockdown_damage)
	if not controller.play_card(ranger, card, [], {"equipment_slot": "paired", "enemy_intent_choice": options[0]}):
		_fail("lockdown: valid weapon/attack-intent choice was rejected")
	elif plan.stolen_ap_total != 1 or enemy.get_current_health() >= health_before or _lockdown_plan_at_damage != 1:
		_fail("lockdown: did not steal before striking the selected enemy")
	controller.log_message.disconnect(_observe_lockdown_damage)
	var nonattack := _configure_public_plan(controller, EnemyIntentCategory.Type.DEFEND)
	var reject := (load("res://resources/cards/ranger_hunting_ground_lockdown.tres") as CardData).duplicate(true) as CardData
	ranger.hand.append(reject)
	var public_options := RangerWaitingPreyCardEffect.new().get_enemy_intent_choice_options({"controller": controller, "user": ranger, "card": reject})
	var defend_choice: Dictionary = {}
	for choice in public_options:
		if not bool(choice.get("is_fallback", false)): defend_choice = choice
	var ap_before := ranger.current_ap
	if defend_choice.is_empty(): _fail("lockdown: fixture did not expose a real public DEFEND primary option")
	if controller.play_card(ranger, reject, [], {"equipment_slot": "paired", "enemy_intent_choice": defend_choice}): _fail("lockdown: real DEFEND intent unexpectedly played")
	if ranger.current_ap != ap_before or nonattack.stolen_ap_total != 0 or not ranger.hand.has(reject): _fail("lockdown: nonattack rejection consumed AP/card/budget")


func _test_lockdown_rejects_card_protected_enemy() -> void:
	var controller := _make_active_controller()
	if controller == null:
		return
	var ranger := _find_ranger(controller)
	var enemy: BattleUnitState = controller.enemy_units[0]
	ranger.set_hex_cell(Vector2i(2, 3), controller.map_data)
	enemy.set_hex_cell(Vector2i(3, 3), controller.map_data)
	enemy.distortion_state.permanent_fields.append("night_veil")
	var plan := _configure_public_plan(controller, EnemyIntentCategory.Type.ATTACK)
	var card := (load("res://resources/cards/ranger_hunting_ground_lockdown.tres") as CardData).duplicate(true) as CardData
	ranger.hand.append(card)
	var options := card.get_enemy_intent_choice_options({"controller": controller, "user": ranger, "card": card, "equipment_slot": "paired"})
	var ap_before := ranger.current_ap
	if not options.is_empty() or controller.play_card(ranger, card, [], {"equipment_slot": "paired", "enemy_intent_choice": {"enemy": enemy, "enemy_id": enemy.get_instance_id(), "plan_id": plan.get_instance_id(), "slot_index": 0, "is_fallback": false}}) \
			or ranger.current_ap != ap_before or not ranger.hand.has(card) or plan.stolen_ap_total != 0:
		_fail("lockdown protection: protected enemy was offered or paid/struck")

func _test_live_lockdown_weapon_then_intent_path() -> void:
	var packed := load("res://scenes/battle_scene.tscn") as PackedScene
	if packed == null: _fail("ui lockdown: battle scene is missing"); return
	var scene := packed.instantiate() as BattleScene
	add_child(scene)
	await get_tree().process_frame
	var controller := scene.controller
	var ranger := _find_ranger(controller)
	if controller == null or ranger == null or controller.enemy_units.is_empty():
		_fail("ui lockdown: scene fixture missing ranger/enemy"); scene.queue_free(); return
	var enemy: BattleUnitState = controller.enemy_units[0]
	controller.phase = BattleController.Phase.BATTLE
	controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	controller.current_unit = ranger
	ranger.current_ap = 9
	ranger.set_hex_cell(Vector2i(2, 3), controller.map_data)
	enemy.set_hex_cell(Vector2i(5, 3), controller.map_data) # melee-out, paired-ranged-in
	var plan := _configure_public_plan(controller, EnemyIntentCategory.Type.ATTACK)
	var card := (load("res://resources/cards/ranger_hunting_ground_lockdown.tres") as CardData).duplicate(true) as CardData
	ranger.hand.append(card)
	scene._select_card(card)
	await get_tree().process_frame
	if scene._weapon_choice_popup == null or not scene._weapon_choice_popup.visible:
		_fail("ui lockdown: initial selection did not open weapon PopupPanel")
		scene.queue_free(); return
	var paired_button := _last_button(scene._weapon_choice_list)
	if paired_button == null:
		_fail("ui lockdown: no real paired-weapon button")
		scene.queue_free(); return
	paired_button.emit_signal("pressed")
	await get_tree().process_frame
	if scene._weapon_choice_popup.visible:
		_fail("ui lockdown: weapon choice did not resolve exactly once")
	if scene._intent_choice_popup == null or not scene._intent_choice_popup.visible:
		_fail("ui lockdown: paired weapon choice did not open intent PopupPanel before direct card play")
		scene.queue_free(); return
	var intent_button := _first_choice_button(scene._intent_choice_list)
	if intent_button == null:
		_fail("ui lockdown: no real ATTACK-intent button")
		scene.queue_free(); return
	var ap_before := ranger.current_ap
	var health_before := enemy.get_current_health()
	intent_button.emit_signal("pressed")
	await get_tree().process_frame
	if ranger.hand.has(card) or ranger.current_ap != ap_before - 1 or plan.stolen_ap_total != 1 or enemy.get_current_health() >= health_before:
		_fail("ui lockdown: confirm did not pay 2 AP, steal 1 AP, discard and strike through one weapon/intent route")
	scene.queue_free()

func _find_ranger(controller: BattleController) -> BattleUnitState:
	for unit in controller.player_units:
		if unit != null and unit.is_ranger(): return unit
	return null

func _find_button(root: Node, label: String) -> Button:
	if root == null: return null
	for child in root.get_children():
		if child is Button and (child as Button).text == label: return child as Button
		var nested := _find_button(child, label)
		if nested != null: return nested
	return null

func _first_choice_button(root: Node) -> Button:
	if root == null: return null
	for child in root.get_children():
		if child is Button and (child as Button).text != "取消": return child as Button
		var nested := _first_choice_button(child)
		if nested != null: return nested
	return null

func _last_button(root: Node) -> Button:
	if root == null: return null
	var result: Button = null
	for child in root.get_children():
		if child is Button: result = child as Button
	return result

func _observe_lockdown_damage(message: String) -> void:
	if message.contains("猎场封锁") and _observed_lockdown_plan != null:
		_lockdown_plan_at_damage = _observed_lockdown_plan.stolen_ap_total

func _fail(message: String) -> void:
	_exit_code = 1
	push_error("RANGER_REWORK_CARDS_DIAG: " + message)
	print("ERROR: RANGER_REWORK_CARDS_DIAG: " + message)
