extends Node


class APCompletionDiagnosticStatus:
	extends StatusEffect

	var records: Array[Dictionary] = []
	var order: Array[String] = []
	var enqueue_completion_effect: bool = false
	var completion_effect_action_id: int = 0
	var completion_effect_scope_depth: int = 0

	func _init() -> void:
		status_id = "diagnostic_ap_completion"
		display_name = "AP completion diagnostic"

	func on_after_card_played(
		_unit: BattleUnitState,
		_card: CardData,
		_context: Dictionary = {}
	) -> void:
		order.append("after_card_hook")

	func on_ap_action_completed(
		_unit: BattleUnitState,
		ap_spent: int,
		context: Dictionary = {}
	) -> void:
		records.append({
			"ap_spent": ap_spent,
			"action_id": int(context.get("action_id", 0)),
			"phase": str(context.get("phase", "")),
		})
		order.append("ap_completed")
		if not enqueue_completion_effect:
			return
		var controller := context.get("controller") as BattleController
		if controller != null:
			controller.enqueue_effect(
				Callable(self, "_record_completion_effect"),
				[controller],
				0,
				"AP completion diagnostic effect"
			)

	func _record_completion_effect(controller: BattleController) -> void:
		order.append("completion_effect")
		completion_effect_action_id = controller.get_current_action_id()
		completion_effect_scope_depth = controller.resolution_runner.queue_scopes.size()


class APGainCardEffect:
	extends CardEffect

	var extra_ap_condition: PayAPCondition
	var ap_gain: int = 0
	var order: Array[String] = []

	func can_pay_play_cost(context: Dictionary = {}) -> bool:
		return extra_ap_condition == null or extra_ap_condition.can_pay(context)

	func pay_play_cost(context: Dictionary = {}) -> bool:
		return extra_ap_condition == null or extra_ap_condition.pay(context)

	func play(context: Dictionary = {}, _targets: Array = []) -> void:
		order.append("card_effect")
		var user := context.get("user") as BattleUnitState
		if user != null:
			user.current_ap += ap_gain


class DefaultCostEquipmentEffect:
	extends EquipmentEffect

	func has_activated_action(
		_owner: BattleUnitState,
		_root: EquipmentData,
		_component: EquipmentData,
		_runtime: EquipmentRuntimeState,
		_context: Dictionary = {}
	) -> bool:
		return true

	func get_action_label(
		_owner: BattleUnitState,
		_root: EquipmentData,
		_component: EquipmentData,
		_runtime: EquipmentRuntimeState,
		_context: Dictionary = {}
	) -> String:
		return "default AP cost"

	func activate(
		_owner: BattleUnitState,
		_root: EquipmentData,
		_component: EquipmentData,
		_runtime: EquipmentRuntimeState,
		_context: Dictionary = {}
	) -> bool:
		return true


class CustomCostEquipmentEffect:
	extends EquipmentEffect

	var advertised_ap_cost: int = 0
	var advertised_momentum_cost: int = 0
	var omit_ap_cost: bool = false
	var activation_succeeds: bool = true
	var set_ap_during_activation: int = -1
	var observed_activation_ap: int = -1

	func get_activated_actions(
		_owner: BattleUnitState,
		_root: EquipmentData,
		_component: EquipmentData,
		_runtime: EquipmentRuntimeState,
		_context: Dictionary = {}
	) -> Array[Dictionary]:
		var action := {
			"action_id": "diagnostic",
			"label": "custom AP cost",
			"enabled": true,
			"momentum_cost": advertised_momentum_cost,
		}
		if not omit_ap_cost:
			action["ap_cost"] = advertised_ap_cost
		return [action]

	func activate(
		owner: BattleUnitState,
		_root: EquipmentData,
		_component: EquipmentData,
		_runtime: EquipmentRuntimeState,
		_context: Dictionary = {}
	) -> bool:
		observed_activation_ap = owner.current_ap
		if set_ap_during_activation >= 0:
			owner.current_ap = set_ap_during_activation
		return activation_succeeds


class OutgoingOrderDiagnosticEquipmentEffect:
	extends EquipmentEffect

	var observed_amount: int = -1

	func modify_outgoing_damage(
		_owner: BattleUnitState,
		_root: EquipmentData,
		_component: EquipmentData,
		_runtime: EquipmentRuntimeState,
		damage_context: DamageContext
	) -> void:
		observed_amount = damage_context.amount if damage_context != null else -1


class TurnEndCleanupDiagnosticController:
	extends BattleController

	var inspected_unit: BattleUnitState
	var status_present_before_advance: bool = true

	func advance_turn() -> void:
		status_present_before_advance = inspected_unit != null \
			and inspected_unit.has_status("stun")


var _exit_code: int = 0
var _chain_count: int = 0
var _chain_action_ids: Array[int] = []
var _order: Array[String] = []
var _stage_action_ids: Array[int] = []
var _stage_lock_states: Array[bool] = []
var _reentrant_end_attempts: int = 0
var _duplicate_card_results: Array[bool] = []


func _ready() -> void:
	var runner_controller := BattleController.new()
	runner_controller.setup(null)
	_test_non_recursive_action_chain(runner_controller)
	_test_action_chain_limit(runner_controller)
	_test_effect_queue_reentry(runner_controller)
	_test_after_stage(runner_controller)
	_test_action_order(runner_controller)
	_test_ap_frame_isolation(runner_controller)
	_test_card_ap_completion()
	_test_movement_ap_completion()
	_test_basic_attack_ap_completion()
	_test_basic_attack_object_ap_completion()
	_test_zero_ap_action_skips_completion()
	_test_equipment_action_ap_completion()
	_test_stun_rules()
	_test_turn_command_boundary()
	_test_turn_start_death_recovery()

	print("FLOW_DIAG: completed")
	get_tree().quit(_exit_code)


func _test_non_recursive_action_chain(controller: BattleController) -> void:
	controller.resolution_runner.reset()
	_chain_count = 0
	_chain_action_ids.clear()
	controller.push_action_frame(BattleActionFrame.create(
		Callable(self, "_chain_action"),
		[controller, 300]
	))
	if _chain_count != 300:
		_fail("FLOW_DIAG: non-recursive chain expected 300 actions, got %d" % _chain_count)
	var unique_ids := {}
	for action_id in _chain_action_ids:
		unique_ids[action_id] = true
	if unique_ids.size() != 300:
		_fail("FLOW_DIAG: chained actions did not receive unique action ids")
	_assert_runner_idle(controller, "300 action chain")


func _test_action_chain_limit(controller: BattleController) -> void:
	controller.resolution_runner.reset()
	_chain_count = 0
	_chain_action_ids.clear()
	controller.push_action_frame(BattleActionFrame.create(
		Callable(self, "_chain_action"),
		[controller, BattleResolutionRunner.MAX_ACTIONS_PER_PUMP + 20]
	))
	if _chain_count != BattleResolutionRunner.MAX_ACTIONS_PER_PUMP:
		_fail("FLOW_DIAG: action pump limit expected %d, got %d" % [
			BattleResolutionRunner.MAX_ACTIONS_PER_PUMP,
			_chain_count,
		])
	_assert_runner_idle(controller, "action pump limit")


func _chain_action(controller: BattleController, remaining: int) -> void:
	_chain_count += 1
	_chain_action_ids.append(controller.get_current_action_id())
	if remaining > 1:
		controller.push_action_frame(BattleActionFrame.create(
			Callable(self, "_chain_action"),
			[controller, remaining - 1]
		))


func _test_effect_queue_reentry(controller: BattleController) -> void:
	controller.resolution_runner.reset()
	_order.clear()
	controller.push_action_frame(BattleActionFrame.create(
		Callable(self, "_reentrant_effect"),
		[controller]
	))
	if _order != ["effect_enter", "effect_exit", "queued_effect"]:
		_fail("FLOW_DIAG: effect queue reentry changed order: %s" % str(_order))
	_assert_runner_idle(controller, "effect queue reentry")


func _reentrant_effect(controller: BattleController) -> void:
	_order.append("effect_enter")
	controller.enqueue_effect(Callable(self, "_record_order").bind("queued_effect"))
	controller.resolve_effect_queue()
	_order.append("effect_exit")


func _test_after_stage(controller: BattleController) -> void:
	controller.resolution_runner.reset()
	_order.clear()
	_stage_action_ids.clear()
	_stage_lock_states.clear()
	controller.push_action_frame(BattleActionFrame.create(
		Callable(self, "_record_stage"),
		[controller, "main"],
		0,
		"after stage diagnostic",
		null,
		Callable(self, "_queue_after_stage_effect"),
		[controller]
	))
	if _order != ["main", "after_callback", "after_effect"]:
		_fail("FLOW_DIAG: after stage order incorrect: %s" % str(_order))
	if _stage_action_ids.size() != 3 or _stage_action_ids[0] <= 0 \
		or _stage_action_ids[0] != _stage_action_ids[1] \
		or _stage_action_ids[1] != _stage_action_ids[2]:
		_fail("FLOW_DIAG: after stage did not retain one action id")
	for locked in _stage_lock_states:
		if not locked:
			_fail("FLOW_DIAG: after stage escaped the action lock")
			break
	_assert_runner_idle(controller, "after stage")


func _record_stage(controller: BattleController, label: String) -> void:
	_order.append(label)
	_stage_action_ids.append(controller.get_current_action_id())
	_stage_lock_states.append(controller.is_resolving_actions())


func _queue_after_stage_effect(controller: BattleController) -> void:
	_record_stage(controller, "after_callback")
	controller.enqueue_effect(
		Callable(self, "_record_stage"),
		[controller, "after_effect"]
	)


func _test_action_order(controller: BattleController) -> void:
	controller.resolution_runner.reset()
	_order.clear()
	controller.push_action_frame(BattleActionFrame.create(
		Callable(self, "_queue_outer_and_inner"),
		[controller]
	))
	if _order != ["outer_1", "outer_2", "inner_action"]:
		_fail("FLOW_DIAG: action/effect order incorrect: %s" % str(_order))
	_assert_runner_idle(controller, "action order")


func _test_ap_frame_isolation(controller: BattleController) -> void:
	controller.resolution_runner.reset()
	var unit := _create_proxy_unit("AP frame isolation")
	var status := APCompletionDiagnosticStatus.new()
	unit.add_status(status)
	controller._record_action_ap_spent(unit, 99)
	controller.push_action_frame(BattleActionFrame.create(
		Callable(self, "_resolve_outer_ap_diagnostic"),
		[controller, unit, status.order],
		0,
		"outer AP diagnostic",
		null,
		Callable(self, "_resolve_outer_ap_after_diagnostic"),
		[controller, status.order]
	))
	var recorded_amounts: Array[int] = []
	var recorded_ids: Array[int] = []
	for record in status.records:
		recorded_amounts.append(int(record.get("ap_spent", 0)))
		recorded_ids.append(int(record.get("action_id", 0)))
	if recorded_amounts != [2, 3] \
			or recorded_ids.size() != 2 \
			or recorded_ids[0] <= 0 \
			or recorded_ids[1] <= 0 \
			or recorded_ids[0] == recorded_ids[1]:
		_fail("FLOW_DIAG: queued AP frames did not retain isolated totals/action ids")
	var expected_order := [
		"outer_main",
		"main_effect",
		"main_trigger",
		"outer_after",
		"after_effect",
		"after_trigger",
		"ap_completed",
		"inner_main",
		"ap_completed",
	]
	if status.order != expected_order:
		_fail("FLOW_DIAG: AP frame drain/finalization order incorrect: %s" % str(status.order))
	_assert_runner_idle(controller, "queued AP frame isolation")


func _resolve_outer_ap_diagnostic(
	controller: BattleController,
	unit: BattleUnitState,
	order: Array[String]
) -> void:
	order.append("outer_main")
	controller._record_action_ap_spent(unit, 2)
	controller.enqueue_effect(Callable(self, "_append_ap_order"), [order, "main_effect"])
	controller.enqueue_trigger(Callable(self, "_append_ap_order"), [order, "main_trigger"])
	controller.push_action_frame(BattleActionFrame.create(
		Callable(self, "_resolve_inner_ap_diagnostic"),
		[controller, unit, order]
	))


func _resolve_outer_ap_after_diagnostic(
	controller: BattleController,
	order: Array[String]
) -> void:
	order.append("outer_after")
	controller.enqueue_effect(Callable(self, "_append_ap_order"), [order, "after_effect"])
	controller.enqueue_trigger(Callable(self, "_append_ap_order"), [order, "after_trigger"])


func _resolve_inner_ap_diagnostic(
	controller: BattleController,
	unit: BattleUnitState,
	order: Array[String]
) -> void:
	order.append("inner_main")
	controller._record_action_ap_spent(unit, 3)


func _append_ap_order(order: Array[String], label: String) -> void:
	order.append(label)


func _queue_outer_and_inner(controller: BattleController) -> void:
	controller.enqueue_effect(Callable(self, "_record_order").bind("outer_1"))
	controller.push_action_frame(BattleActionFrame.create(
		Callable(self, "_record_order"),
		["inner_action"]
	))
	controller.enqueue_effect(Callable(self, "_record_order").bind("outer_2"))


func _record_order(label: String) -> void:
	_order.append(label)


func _test_card_ap_completion() -> void:
	var controller := _create_started_controller()
	if controller == null:
		return
	var unit := _prepare_player_turn(controller)
	var status := APCompletionDiagnosticStatus.new()
	status.enqueue_completion_effect = true
	unit.statuses.clear()
	unit.add_status(status)

	var extra_cost := PayAPCondition.new()
	extra_cost.amount = 3
	var effect := APGainCardEffect.new()
	effect.extra_ap_condition = extra_cost
	effect.ap_gain = 4
	effect.order = status.order
	var card := CardData.new()
	card.card_name = "AP ledger diagnostic"
	card.ap_cost = 2
	card.effect = effect
	unit.hand.assign([card])
	unit.current_ap = 10

	if not controller.play_card(unit, card, []):
		_fail("FLOW_DIAG: AP ledger card was rejected")
		return
	if unit.current_ap != 9:
		_fail("FLOW_DIAG: AP gain card expected 9 AP after payment and effect, got %d" % unit.current_ap)
	_assert_ap_records(status, [5], "base plus PayAPCondition")
	if status.order != ["card_effect", "after_card_hook", "ap_completed", "completion_effect"]:
		_fail("FLOW_DIAG: AP finalization order incorrect: %s" % str(status.order))
	var action_id := int(status.records[0].get("action_id", 0)) if not status.records.is_empty() else 0
	if action_id <= 0 or status.completion_effect_action_id != action_id:
		_fail("FLOW_DIAG: finalization effect escaped its action id")
	if status.completion_effect_scope_depth <= 1:
		_fail("FLOW_DIAG: finalization effect ran after the action queue scope was popped")
	_assert_runner_idle(controller, "card AP finalization")


func _test_movement_ap_completion() -> void:
	var controller := _create_started_controller()
	if controller == null:
		return
	var unit := _prepare_player_turn(controller)
	var status := APCompletionDiagnosticStatus.new()
	unit.statuses.clear()
	unit.add_status(status)
	unit.current_ap = 10
	var destination := _find_reachable_destination(controller, unit)
	if destination == BattleHexGrid.INVALID_CELL:
		_fail("FLOW_DIAG: movement AP diagnostic found no reachable destination")
		return
	var ap_before := unit.current_ap
	if not controller.move_unit_to_cell(unit, destination):
		_fail("FLOW_DIAG: movement AP diagnostic action was rejected")
		return
	var spent := ap_before - unit.current_ap
	if spent <= 0:
		_fail("FLOW_DIAG: movement AP diagnostic did not spend AP")
	_assert_ap_records(status, [spent], "movement")
	_assert_runner_idle(controller, "movement AP finalization")


func _test_basic_attack_ap_completion() -> void:
	var controller := _create_started_controller()
	if controller == null:
		return
	var attacker := _prepare_player_turn(controller)
	var target := controller.enemy_units[0] if not controller.enemy_units.is_empty() else null
	if target == null or not _place_adjacent(controller, attacker, target):
		_fail("FLOW_DIAG: unit attack AP diagnostic could not place targets")
		return
	var status := APCompletionDiagnosticStatus.new()
	attacker.statuses.clear()
	attacker.add_status(status)
	attacker.current_ap = 10
	if not controller.basic_attack(attacker, target):
		_fail("FLOW_DIAG: unit attack AP diagnostic action was rejected")
		return
	_assert_ap_records(status, [controller.config.basic_attack_ap_cost], "unit basic attack")
	_assert_runner_idle(controller, "unit attack AP finalization")


func _test_basic_attack_object_ap_completion() -> void:
	var controller := _create_started_controller()
	if controller == null:
		return
	var attacker := _prepare_player_turn(controller)
	var target_cell := _find_empty_neighbor(controller, attacker.cell, [attacker])
	if target_cell == BattleHexGrid.INVALID_CELL:
		_fail("FLOW_DIAG: object attack AP diagnostic found no adjacent cell")
		return
	var target := controller.spawn_battle_object(
		BattleObjectDefinition.Kind.EXPLOSIVE_BARREL,
		target_cell
	)
	if target == null:
		_fail("FLOW_DIAG: object attack AP diagnostic could not spawn target")
		return
	var status := APCompletionDiagnosticStatus.new()
	attacker.statuses.clear()
	attacker.add_status(status)
	attacker.current_ap = 10
	if not controller.basic_attack_object(attacker, target):
		_fail("FLOW_DIAG: object attack AP diagnostic action was rejected")
		return
	_assert_ap_records(status, [controller.config.basic_attack_ap_cost], "object basic attack")
	_assert_runner_idle(controller, "object attack AP finalization")


func _test_zero_ap_action_skips_completion() -> void:
	var controller := _create_started_controller()
	if controller == null:
		return
	var unit := _prepare_player_turn(controller)
	var status := APCompletionDiagnosticStatus.new()
	unit.statuses.clear()
	unit.add_status(status)
	var card := CardData.new()
	card.card_name = "zero AP diagnostic"
	card.ap_cost = 0
	unit.hand.assign([card])
	unit.current_ap = 4
	if not controller.play_card(unit, card, []):
		_fail("FLOW_DIAG: zero AP diagnostic action was rejected")
		return
	_assert_ap_records(status, [], "zero AP action")
	_assert_runner_idle(controller, "zero AP finalization")


func _test_equipment_action_ap_completion() -> void:
	var controller := _create_started_controller()
	if controller == null:
		return
	var unit := _prepare_player_turn(controller)
	var status := APCompletionDiagnosticStatus.new()
	unit.statuses.clear()
	unit.add_status(status)

	var default_effect := DefaultCostEquipmentEffect.new()
	_equip_diagnostic_effect(unit, default_effect)
	unit.current_ap = 4
	if not controller.activate_equipment_action(unit, default_effect):
		_fail("FLOW_DIAG: default-cost equipment action was rejected")
	_assert_ap_records(status, [], "default equipment AP cost")
	if unit.current_ap != 4:
		_fail("FLOW_DIAG: default equipment AP cost changed AP")

	var custom_effect := CustomCostEquipmentEffect.new()
	custom_effect.omit_ap_cost = true
	_equip_diagnostic_effect(unit, custom_effect)
	if not controller.activate_equipment_action(unit, custom_effect, "diagnostic"):
		_fail("FLOW_DIAG: missing-key equipment action was rejected")
	_assert_ap_records(status, [], "missing equipment AP key")
	if unit.current_ap != 4:
		_fail("FLOW_DIAG: missing equipment AP key did not default to zero")

	custom_effect.omit_ap_cost = false
	custom_effect.advertised_ap_cost = 3
	unit.current_ap = 2
	if controller.can_activate_equipment_action(unit, custom_effect, "diagnostic"):
		_fail("FLOW_DIAG: equipment action ignored insufficient AP")
	custom_effect.activation_succeeds = false
	custom_effect.advertised_momentum_cost = 2
	custom_effect.set_ap_during_activation = 0
	var momentum := unit.get_class_resource(BattleController.WARRIOR_MOMENTUM_RESOURCE)
	if momentum == null:
		_fail("FLOW_DIAG: equipment transaction diagnostic found no momentum pool")
		return
	momentum.current_value = 5
	unit.current_ap = 5
	if not controller.activate_equipment_action(unit, custom_effect, "diagnostic"):
		_fail("FLOW_DIAG: failing equipment effect was not queued")
	if unit.current_ap != 5:
		_fail("FLOW_DIAG: failed equipment effect spent AP")
	if unit.get_class_resource_value(BattleController.WARRIOR_MOMENTUM_RESOURCE) != 5:
		_fail("FLOW_DIAG: failed equipment effect did not roll back momentum")
	_assert_ap_records(status, [], "failed equipment activation")

	custom_effect.activation_succeeds = true
	custom_effect.set_ap_during_activation = 0
	if not controller.activate_equipment_action(unit, custom_effect, "diagnostic"):
		_fail("FLOW_DIAG: successful equipment action was rejected")
	if custom_effect.observed_activation_ap != 2:
		_fail("FLOW_DIAG: equipment effect did not observe atomically reserved AP")
	if unit.current_ap != 0:
		_fail("FLOW_DIAG: successful AP-mutating equipment effect produced invalid AP")
	if unit.get_class_resource_value(BattleController.WARRIOR_MOMENTUM_RESOURCE) != 3:
		_fail("FLOW_DIAG: successful equipment action did not commit momentum cost")
	_assert_ap_records(status, [3], "successful equipment activation")
	_assert_runner_idle(controller, "equipment AP finalization")


func _test_stun_rules() -> void:
	var controller := BattleController.new()
	controller.setup(null)
	var source := _create_proxy_unit("stun source")
	var target := _create_proxy_unit("stun target")

	var incoming_stun := StunStatus.new()
	incoming_stun.stacks = 1
	target.add_status(incoming_stun)
	var incoming_context := DamageContext.create(controller, source, target, 4, "stun incoming")
	target.modify_incoming_damage(incoming_context)
	if incoming_context.amount != 6:
		_fail("FLOW_DIAG: 1 stun stack should add exactly 2 incoming damage, got %d" % incoming_context.amount)
	incoming_stun.stacks = 5
	incoming_context = DamageContext.create(controller, source, target, 4, "stun incoming")
	target.modify_incoming_damage(incoming_context)
	if incoming_context.amount != 6:
		_fail("FLOW_DIAG: 5 stun stacks should still add exactly 2 incoming damage, got %d" % incoming_context.amount)

	target.statuses.clear()
	var outgoing_stun := StunStatus.new()
	outgoing_stun.stacks = 5
	source.add_status(outgoing_stun)
	target.curse_proxy_health = 100
	var dealt := controller.apply_damage(source, target, 5, "stun outgoing")
	if dealt != 3:
		_fail("FLOW_DIAG: stun should reduce non-fixed outgoing damage by 2, got %d" % dealt)
	target.curse_proxy_health = 100
	dealt = controller.apply_damage(source, target, 1, "stun outgoing clamp")
	if dealt != 0:
		_fail("FLOW_DIAG: stun outgoing penalty should clamp damage to 0, got %d" % dealt)
	target.curse_proxy_health = 100
	dealt = controller.apply_damage(source, target, 5, "stun fixed outgoing", {"fixed_damage": true})
	if dealt != 5:
		_fail("FLOW_DIAG: fixed damage should ignore stun outgoing penalty, got %d" % dealt)
	target.curse_proxy_health = 100
	dealt = controller.apply_damage(source, target, 5, "stun environmental outgoing", {"environmental": true})
	if dealt != 5:
		_fail("FLOW_DIAG: environmental damage should ignore stun outgoing penalty, got %d" % dealt)

	var config := BattleConfig.new()
	config.base_move_cells_per_ap = 5
	if source.get_move_distance_per_ap(config) != 3:
		_fail("FLOW_DIAG: stun should halve move distance per AP with ceiling")

	source.current_ap = 7
	outgoing_stun.on_turn_start(source, {"controller": controller})
	if source.current_ap != 7 or outgoing_stun.stacks != 5:
		_fail("FLOW_DIAG: stun should not consume AP or stacks at turn start")
	outgoing_stun.on_turn_end(source, {"controller": controller})
	if outgoing_stun.stacks != 4:
		_fail("FLOW_DIAG: turn end should remove exactly 1 stun stack")

	var action_controller := _create_started_controller()
	if action_controller == null:
		return
	var action_unit := _prepare_player_turn(action_controller)
	var action_stun := StunStatus.new()
	action_stun.stacks = 6
	action_unit.statuses.clear()
	action_unit.add_status(action_stun)
	var extra_cost := PayAPCondition.new()
	extra_cost.amount = 1
	var ap_gain_effect := APGainCardEffect.new()
	ap_gain_effect.extra_ap_condition = extra_cost
	ap_gain_effect.ap_gain = 4
	var ap_card := CardData.new()
	ap_card.card_name = "stun real AP action"
	ap_card.ap_cost = 2
	ap_card.effect = ap_gain_effect
	action_unit.hand.assign([ap_card])
	action_unit.current_ap = 10
	if not action_controller.play_card(action_unit, ap_card, []):
		_fail("FLOW_DIAG: stunned AP gain card was rejected")
	elif action_unit.current_ap != 11 or action_stun.stacks != 3:
		_fail("FLOW_DIAG: real 3 AP action should keep gained AP and remove exactly 3 stun")
	var zero_card := CardData.new()
	zero_card.card_name = "stun zero AP action"
	zero_card.ap_cost = 0
	action_unit.hand.assign([zero_card])
	if not action_controller.play_card(action_unit, zero_card, []):
		_fail("FLOW_DIAG: stunned zero AP card was rejected")
	elif action_stun.stacks != 3:
		_fail("FLOW_DIAG: real 0 AP action should not remove stun stacks")
	_assert_runner_idle(action_controller, "stun real action finalization")

	var order_controller := _create_started_controller()
	if order_controller == null:
		return
	var order_unit := _prepare_player_turn(order_controller)
	var order_stun := StunStatus.new()
	order_stun.stacks = 1
	order_unit.statuses.clear()
	order_unit.add_status(order_stun)
	var order_effect := OutgoingOrderDiagnosticEquipmentEffect.new()
	_equip_diagnostic_effect(order_unit, order_effect)
	var order_context := DamageContext.create(order_controller, order_unit, target, 5, "stun order")
	order_unit.modify_outgoing_damage(order_context)
	if order_effect.observed_amount != 3:
		_fail("FLOW_DIAG: equipment should observe outgoing damage after stun, got %d" % order_effect.observed_amount)

	var lifecycle_controller := TurnEndCleanupDiagnosticController.new()
	lifecycle_controller.setup(null)
	var lifecycle_unit := _create_proxy_unit("stun lifecycle")
	lifecycle_unit.battle_controller = lifecycle_controller
	var lifecycle_stun := StunStatus.new()
	lifecycle_stun.stacks = 1
	lifecycle_unit.add_status(lifecycle_stun)
	lifecycle_controller.inspected_unit = lifecycle_unit
	lifecycle_controller.units.assign([lifecycle_unit])
	lifecycle_controller.turn_order.assign([lifecycle_unit])
	lifecycle_controller.phase = BattleController.Phase.BATTLE
	lifecycle_controller.current_unit = lifecycle_unit
	lifecycle_controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	lifecycle_controller.end_current_turn()
	if lifecycle_controller.status_present_before_advance or lifecycle_unit.has_status("stun"):
		_fail("FLOW_DIAG: expired stun should be removed before advancing from turn end")
	_assert_runner_idle(lifecycle_controller, "stun turn-end cleanup")


func _create_proxy_unit(display_name: String) -> BattleUnitState:
	var unit := BattleUnitState.new()
	unit.is_curse_proxy = true
	unit.curse_proxy_name = display_name
	unit.curse_proxy_max_health = 100
	unit.curse_proxy_health = 100
	return unit


func _create_started_controller() -> BattleController:
	var scenario := load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario
	if scenario == null:
		_fail("FLOW_DIAG: sample battle scenario missing for AP diagnostic")
		return null
	var controller := BattleController.new()
	controller.setup(scenario)
	_deploy_players(controller)
	if not controller.start_battle():
		_fail("FLOW_DIAG: AP diagnostic failed to start battle")
		return null
	return controller


func _prepare_player_turn(controller: BattleController) -> BattleUnitState:
	var unit := controller.player_units[0] as BattleUnitState
	controller.current_unit = unit
	controller.turn_flow_state = BattleController.TurnFlowState.ACTIVE
	return unit


func _find_reachable_destination(controller: BattleController, unit: BattleUnitState) -> Vector2i:
	for cell in controller.get_reachable_cells(unit, 1):
		if cell != unit.cell:
			return cell
	return BattleHexGrid.INVALID_CELL


func _place_adjacent(
	controller: BattleController,
	first: BattleUnitState,
	second: BattleUnitState
) -> bool:
	for cell in controller.map_data.get_all_cells():
		if controller.get_battle_object_at_cell(cell) != null:
			continue
		var occupant := controller.get_unit_at_cell(cell)
		if occupant != null and occupant != first and occupant != second:
			continue
		var neighbor := _find_empty_neighbor(controller, cell, [first, second])
		if neighbor == BattleHexGrid.INVALID_CELL:
			continue
		first.set_hex_cell(cell, controller.map_data)
		second.set_hex_cell(neighbor, controller.map_data)
		return true
	return false


func _find_empty_neighbor(
	controller: BattleController,
	origin: Vector2i,
	ignored_units: Array
) -> Vector2i:
	for cell in BattleHexGrid.neighbors(origin):
		if not controller.map_data.is_valid_cell(cell) \
				or controller.get_battle_object_at_cell(cell) != null:
			continue
		var occupant := controller.get_unit_at_cell(cell)
		if occupant == null or ignored_units.has(occupant):
			return cell
	return BattleHexGrid.INVALID_CELL


func _equip_diagnostic_effect(unit: BattleUnitState, effect: EquipmentEffect) -> void:
	var equipment := EquipmentData.new()
	equipment.item_name = "AP diagnostic equipment"
	equipment.activated_effects.assign([effect])
	unit.character_state.weapon_equipment = equipment
	unit.character_state.weapon_face = 0
	unit.equipment_runtime_states.clear()


func _assert_ap_records(
	status: APCompletionDiagnosticStatus,
	expected: Array[int],
	label: String
) -> void:
	var actual: Array[int] = []
	for record in status.records:
		actual.append(int(record.get("ap_spent", -1)))
		if str(record.get("phase", "")) != "action_finalize":
			_fail("FLOW_DIAG: %s used wrong AP completion phase" % label)
	if actual != expected:
		_fail("FLOW_DIAG: %s expected AP completions %s, got %s" % [label, str(expected), str(actual)])


func _test_turn_command_boundary() -> void:
	var scenario := load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario
	if scenario == null:
		_fail("FLOW_DIAG: sample battle scenario missing")
		return
	var controller := BattleController.new()
	controller.setup(scenario)
	_deploy_players(controller)
	if not controller.start_battle() or controller.current_unit == null:
		_fail("FLOW_DIAG: failed to start sample battle")
		return

	var active_unit := controller.current_unit
	var inactive_unit := _find_other_alive_unit(controller, active_unit)
	var opponent := controller.get_nearest_opponent(inactive_unit) if inactive_unit != null else null
	if inactive_unit == null or opponent == null:
		_fail("FLOW_DIAG: command boundary units missing")
		return
	var inactive_ap := inactive_unit.current_ap
	var inactive_cell := inactive_unit.cell
	if controller.move_unit_to_cell(inactive_unit, inactive_cell):
		_fail("FLOW_DIAG: out-of-turn movement was accepted")
	if controller.basic_attack(inactive_unit, opponent):
		_fail("FLOW_DIAG: out-of-turn basic attack was accepted")
	if not inactive_unit.hand.is_empty():
		var card := inactive_unit.hand[0] as CardData
		if controller.can_play_card_with_mode(inactive_unit, card, CardEnums.CardPlayMode.NORMAL):
			_fail("FLOW_DIAG: out-of-turn card preview was accepted")
		if controller.play_card(inactive_unit, card, [opponent]):
			_fail("FLOW_DIAG: out-of-turn card play was accepted")
	if inactive_unit.current_ap != inactive_ap or inactive_unit.cell != inactive_cell:
		_fail("FLOW_DIAG: rejected out-of-turn command changed unit state")

	_test_duplicate_card_submission(controller, active_unit)

	var expected_player := _find_next_player_in_turn_order(controller, active_unit)
	controller.state_changed.connect(_attempt_reentrant_end_turn.bind(controller))
	controller.end_current_turn()
	if _reentrant_end_attempts <= 0:
		_fail("FLOW_DIAG: reentrant end-turn path was not exercised")
	if expected_player != null and controller.phase == BattleController.Phase.BATTLE and controller.current_unit != expected_player:
		_fail("FLOW_DIAG: reentrant end-turn skipped the expected player turn")
	_assert_runner_idle(controller, "turn command boundary")


func _test_duplicate_card_submission(controller: BattleController, unit: BattleUnitState) -> void:
	var card := (load("res://resources/cards/battle_slam.tres") as CardData).duplicate() as CardData
	var target := controller.get_nearest_opponent(unit)
	if card == null or target == null:
		_fail("FLOW_DIAG: duplicate card diagnostic resources missing")
		return
	unit.hand.append(card)
	unit.current_ap = 10
	target.set_hex_cell(Vector2i(unit.cell.x + 1, unit.cell.y), controller.map_data)
	_duplicate_card_results.clear()
	controller.push_action_frame(BattleActionFrame.create(
		Callable(self, "_submit_same_card_twice"),
		[controller, unit, card, target]
	))
	if _duplicate_card_results != [true, false]:
		_fail("FLOW_DIAG: duplicate in-flight card submissions were not rejected: %s" % str(_duplicate_card_results))


func _submit_same_card_twice(controller: BattleController, unit: BattleUnitState, card: CardData, target: BattleUnitState) -> void:
	controller.internal_action_submission_depth += 1
	_duplicate_card_results.append(controller.play_card(unit, card, [target]))
	_duplicate_card_results.append(controller.play_card(unit, card, [target]))
	controller.internal_action_submission_depth = maxi(0, controller.internal_action_submission_depth - 1)


func _test_turn_start_death_recovery() -> void:
	var scenario := load("res://resources/battle/sample_battle_scenario.tres") as BattleScenario
	if scenario == null:
		return
	var controller := BattleController.new()
	controller.setup(scenario)
	_deploy_players(controller)
	if not controller.start_battle() or controller.current_unit == null:
		_fail("FLOW_DIAG: failed to start turn-start death diagnostic")
		return
	var doomed := controller.current_unit
	controller.turn_flow_state = BattleController.TurnFlowState.START_PENDING
	controller.push_action_frame(BattleActionFrame.create(
		Callable(doomed, "set_current_health"),
		[0],
		0,
		"turn-start lethal diagnostic",
		null,
		Callable(controller, "_finish_turn_start_action"),
		[doomed]
	))
	if controller.phase == BattleController.Phase.BATTLE \
		and (controller.current_unit == doomed or controller.turn_flow_state != BattleController.TurnFlowState.ACTIVE):
		_fail("FLOW_DIAG: lethal turn-start effect left combat stuck")
	_assert_runner_idle(controller, "turn-start death recovery")


func _attempt_reentrant_end_turn(controller: BattleController) -> void:
	if not controller.is_resolving_actions() and not controller.resolution_state_notification_active:
		return
	_reentrant_end_attempts += 1
	controller.end_current_turn()


func _deploy_players(controller: BattleController) -> void:
	for index in range(controller.player_units.size()):
		var unit: BattleUnitState = controller.player_units[index]
		var cell := Vector2i(index % controller.map_data.player_deployment_columns, index + 2)
		if not controller.deploy_player_unit_at_cell(unit, cell):
			_fail("FLOW_DIAG: failed to deploy %s" % unit.get_display_name())


func _find_other_alive_unit(controller: BattleController, excluded: BattleUnitState) -> BattleUnitState:
	for unit in controller.units:
		if unit != null and unit != excluded and unit.is_alive():
			return unit
	return null


func _find_next_player_in_turn_order(controller: BattleController, current: BattleUnitState) -> BattleUnitState:
	var start := controller.turn_order.find(current)
	if start < 0:
		return null
	for offset in range(1, controller.turn_order.size() + 1):
		var unit: BattleUnitState = controller.turn_order[(start + offset) % controller.turn_order.size()]
		if unit != null and unit.is_alive() and unit.faction == BattleUnitState.Faction.PLAYER:
			return unit
	return null


func _assert_runner_idle(controller: BattleController, label: String) -> void:
	if controller.is_resolving_actions():
		_fail("FLOW_DIAG: controller remained locked after %s" % label)
	if controller.get_current_action_id() != 0:
		_fail("FLOW_DIAG: action id leaked after %s" % label)
	if controller.resolution_runner.current_action_frame != null:
		_fail("FLOW_DIAG: current action frame leaked after %s" % label)
	if not controller.resolution_runner.action_queue.is_empty():
		_fail("FLOW_DIAG: action queue not empty after %s" % label)
	if controller.resolution_runner.queue_scopes.size() != 1 \
		or not (controller.resolution_runner.queue_scopes[0] as Array).is_empty():
		_fail("FLOW_DIAG: effect queue scope leaked after %s" % label)


func _fail(message: String) -> void:
	_exit_code = 1
	push_error(message)
	print("ERROR: " + message)
