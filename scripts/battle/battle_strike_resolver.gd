extends RefCounted
class_name BattleStrikeResolver

var controller: BattleController


func setup(new_controller: BattleController) -> void:
	controller = new_controller


func perform_strike(attacker: BattleUnitState, target: BattleUnitState, source = null, label: String = "打击", weapon_slot: String = "") -> int:
	return perform_strike_with_modifier(attacker, target, source, 0, label, weapon_slot)


func perform_strike_with_modifier(attacker: BattleUnitState, target: BattleUnitState, source = null, damage_modifier: int = 0, label: String = "打击", weapon_slot: String = "") -> int:
	if controller == null or attacker == null or target == null or not attacker.is_alive() or not target.is_alive():
		return 0

	var profile := attacker.build_strike_profile_object(weapon_slot)
	var primary_damage := maxi(0, profile.primary_power + profile.damage_bonus + damage_modifier)
	var actual_damage := controller.apply_damage(attacker, target, primary_damage, label)
	var hit_results: Array[StrikeHitResult] = [
		StrikeHitResult.create(profile.primary_slot, profile.primary_weapon, primary_damage, actual_damage)
	]

	if profile.add_offhand and target.is_alive():
		var offhand_damage := maxi(0, profile.offhand_power)
		var offhand_actual := controller.apply_damage(attacker, target, offhand_damage, "%s（副手）" % label)
		actual_damage += offhand_actual
		hit_results.append(StrikeHitResult.create("off", profile.offhand_weapon, offhand_damage, offhand_actual))

	var attack_results := []
	for result in hit_results:
		attack_results.append(result.to_dict())

	var trigger_context := {
		"controller": controller,
		"attacker": attacker,
		"target": target,
		"source": source,
		"damage_amount": primary_damage,
		"actual_damage": actual_damage,
		"label": label,
		"strike_profile": profile.to_dict(),
		"strike_profile_object": profile,
		"attack_results": attack_results,
		"attack_result_objects": hit_results,
	}
	controller.enqueue_trigger(Callable(controller, "_emit_basic_attack_trigger"), [trigger_context], 0, "普通攻击触发", trigger_context)
	return actual_damage
