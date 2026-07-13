extends StatusEffect
class_name RangerDualPhaseHuntStatus

var zone_card: CardData
var offensive_remaining: int = 1
var defensive_remaining: int = 1
var expires_turn_serial: int = -1
var _controller: BattleController
var _owner: BattleUnitState
var _was_stealthed: bool = false
var _defensive_scheduled: bool = false


func _init() -> void:
	status_id = "ranger_dual_phase_hunt"
	display_name = "双相猎影"
	effect_priority = -20
	stacks = 1


func configure(controller: BattleController, owner: BattleUnitState, card: CardData) -> void:
	_controller = controller
	_owner = owner
	zone_card = card
	_was_stealthed = owner != null and owner.is_stealthed()


func on_after_strike(unit: BattleUnitState, context: Dictionary = {}) -> void:
	if unit == null or offensive_remaining <= 0 or unit.is_stealthed():
		return
	var attacker: BattleUnitState = context.get("attacker") as BattleUnitState
	if attacker != unit:
		return
	offensive_remaining = 0
	_enter_followup_stealth(unit, context, "进攻续接")


## 供战斗控制器在“敌方行动被潜行抵消并完全结束”后派发。
## 当前共享控制器尚未派发该事件；保留独立钩子以便 UI/控制器接入时无需改卡牌文件。
func on_ranger_stealth_cancelled(unit: BattleUnitState, context: Dictionary = {}) -> void:
	if unit == null or defensive_remaining <= 0 or unit.is_stealthed():
		return
	defensive_remaining = 0
	_enter_followup_stealth(unit, context, "防御续接")


func on_turn_end(unit: BattleUnitState, context: Dictionary = {}) -> void:
	if unit != null and expires_turn_serial >= 0 and unit.turn_serial >= expires_turn_serial:
		force_cleanup(unit, context)


func force_cleanup(unit: BattleUnitState, context: Dictionary = {}) -> void:
	_disconnect()
	if unit == null:
		stacks = 0
		return
	if zone_card != null and unit.has_card_in_enchant(zone_card):
		unit.move_enchant_card_to_discard(zone_card, context)
		var controller: BattleController = context.get("controller") as BattleController
		if controller != null:
			controller._emit_log("%s 的双相猎影结束。" % unit.get_display_name())
	stacks = 0


func _enter_followup_stealth(unit: BattleUnitState, context: Dictionary, label: String) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	if controller != null:
		controller.enter_ranger_stealth(unit, label)
	else:
		unit.enter_stealth()
	if offensive_remaining <= 0 and defensive_remaining <= 0:
		force_cleanup(unit, context)


func _on_controller_state_changed() -> void:
	if _controller == null or _owner == null or stacks <= 0:
		_disconnect()
		return
	var is_stealthed := _owner.is_stealthed()
	var enemy_action := _controller.current_unit != null \
		and _controller.current_unit.faction != _owner.faction \
		and _controller.get_current_action_id() > 0
	if _was_stealthed and not is_stealthed and enemy_action and defensive_remaining > 0 and not _defensive_scheduled:
		_defensive_scheduled = true
		_controller.push_action_frame(BattleActionFrame.create(
			Callable(self, "_resolve_defensive_followup"),
			[],
			-20,
			"双相猎影：防御续接",
			{"controller": _controller, "owner": _owner, "source_card": zone_card}
		))
	_was_stealthed = is_stealthed


func _resolve_defensive_followup() -> void:
	_defensive_scheduled = false
	if _owner == null or zone_card == null or not _owner.has_card_in_enchant(zone_card):
		return
	if _owner.is_stealthed():
		_was_stealthed = true
		return
	on_ranger_stealth_cancelled(_owner, {"controller": _controller})
	_was_stealthed = _owner.is_stealthed()


func _disconnect() -> void:
	var callback := Callable(self, "_on_controller_state_changed")
	if _controller != null and _controller.state_changed.is_connected(callback):
		_controller.state_changed.disconnect(callback)
