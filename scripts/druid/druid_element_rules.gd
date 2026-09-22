extends RefCounted
class_name DruidElementRules

var _controller: BattleController

func setup(controller: BattleController) -> void:
	_controller = controller


func resolve_after_strike(attacker: BattleUnitState, target: BattleUnitState, context: Dictionary) -> void:
	if attacker == null:
		return
	match int(context.get("druid_element", BattleSurfaceState.Element.NONE)):
		BattleSurfaceState.Element.FIRE:
			_apply_burn(target)
		BattleSurfaceState.Element.WATER:
			_apply_freeze(target)
		BattleSurfaceState.Element.EARTH:
			attacker.gain_armor(3, context)
		BattleSurfaceState.Element.AIR:
			if target != null and target.is_alive() and _controller != null:
				_controller.force_move_away(target, attacker.cell, 1, attacker)
	if bool(context.get("druid_extra_earth", false)):
		attacker.gain_armor(3, context)


func is_surface_protected(unit: BattleUnitState) -> bool:
	if unit == null:
		return false
	for card in unit.mana_zone:
		if card != null and card.effect != null and card.effect.grants_elemental_surface_protection(unit):
			return true
	return false


func _apply_burn(target: BattleUnitState) -> void:
	if target == null:
		return
	var burn := RangerBurnStatus.new()
	burn.damage_per_turn = 2
	burn.remaining_turns = 2
	target.remove_status(burn.status_id)
	target.add_status(burn)


func _apply_freeze(target: BattleUnitState) -> void:
	if target == null:
		return
	var surcharge := RangerMoveSurchargeStatus.new()
	surcharge.stacks = 1
	surcharge.surcharge = 1
	target.remove_status(surcharge.status_id)
	target.add_status(surcharge)
