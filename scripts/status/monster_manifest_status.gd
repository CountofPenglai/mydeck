extends StatusEffect
class_name MonsterManifestStatus

enum Kind {
	TENTACLE,
	BLOOD_MOUTH,
	EXTRA_LIMB,
	FIRE_SAC,
}

@export var kind: int = Kind.TENTACLE
var source_card_id: int = 0
var triggered_turn_serial: int = -1
var resolving_extra_strike: bool = false


func configure(value: int, card: CardData) -> void:
	kind = value
	source_card_id = card.get_instance_id() if card != null else 0
	status_id = "monster_manifest_%d" % kind
	display_name = ["显化触腕", "显化口器", "显化附肢", "显化灼囊"][kind]
	stacks = 1


func modify_attack_range(_unit: BattleUnitState, current_range: int, _context: Dictionary = {}) -> int:
	return current_range + 1 if kind == Kind.TENTACLE else current_range


func on_after_damage_dealt(unit: BattleUnitState, context: Dictionary = {}) -> void:
	if kind != Kind.BLOOD_MOUTH or unit == null or unit.turn_serial == triggered_turn_serial:
		return
	if int(context.get("amount", 0)) <= 0:
		return
	var controller := context.get("controller") as BattleController
	if controller == null:
		return
	triggered_turn_serial = unit.turn_serial
	controller.heal_unit(unit, unit, 2, "觅血口器")


func on_after_strike(unit: BattleUnitState, context: Dictionary = {}) -> void:
	if unit == null or unit.turn_serial == triggered_turn_serial:
		return
	var controller := context.get("controller") as BattleController
	var target := context.get("target") as BattleUnitState
	if controller == null or target == null or not target.is_alive():
		return
	if kind == Kind.FIRE_SAC:
		triggered_turn_serial = unit.turn_serial
		controller.apply_base_surface_element(target.cell, BattleSurfaceState.Element.FIRE)
	elif kind == Kind.EXTRA_LIMB and not resolving_extra_strike:
		triggered_turn_serial = unit.turn_serial
		resolving_extra_strike = true
		var profile := unit.build_strike_profile_object()
		var damage := 1 + unit.get_damage_bonus({
			"controller": controller,
			"target": target,
			"resolved_damage_type": profile.primary_damage_type,
		})
		controller.apply_damage(unit, target, damage, "增生附肢追加段", {"monster_manifest": true})
		resolving_extra_strike = false
