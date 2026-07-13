extends RefCounted
class_name BattleStrikeResolver

var controller: BattleController


func setup(new_controller: BattleController) -> void:
	controller = new_controller


func perform_strike(attacker: BattleUnitState, target: BattleUnitState, source = null, label: String = "打击", equipment_slot: String = "") -> int:
	return perform_strike_with_modifier(attacker, target, source, 0, label, equipment_slot)


func perform_strike_with_modifier(attacker: BattleUnitState, target: BattleUnitState, source = null, damage_modifier: int = 0, label: String = "打击", equipment_slot: String = "") -> int:
	return perform_strike_with_modifier_and_multiplier(attacker, target, source, damage_modifier, 1.0, label, equipment_slot)


func perform_strike_with_multiplier(attacker: BattleUnitState, target: BattleUnitState, source = null, damage_multiplier: float = 1.0, label: String = "打击", equipment_slot: String = "") -> int:
	return perform_strike_with_modifier_and_multiplier(attacker, target, source, 0, damage_multiplier, label, equipment_slot)


func perform_strike_with_modifier_and_multiplier(attacker: BattleUnitState, target: BattleUnitState, source = null, damage_modifier: int = 0, damage_multiplier: float = 1.0, label: String = "打击", equipment_slot: String = "", options: Dictionary = {}) -> int:
	if controller == null or attacker == null or target == null or not attacker.is_alive() or not target.is_alive():
		return 0

	var profile_context := options.duplicate()
	profile_context["controller"] = controller
	profile_context["source"] = source
	profile_context["target"] = target
	profile_context["label"] = label
	var profile := attacker.build_strike_profile_object(equipment_slot, profile_context)
	var primary_base_damage := maxi(0, profile.primary_base_damage + profile.primary_damage_bonus + damage_modifier)
	var primary_damage := _apply_damage_multiplier(primary_base_damage, damage_multiplier)
	var actual_damage := controller.apply_damage(attacker, target, primary_damage, label)
	var hit_results: Array[StrikeHitResult] = [
		StrikeHitResult.create(profile.primary_slot, profile.primary_equipment, primary_damage, actual_damage)
	]

	if profile.add_offhand and target.is_alive():
		var offhand_base_damage := maxi(0, profile.offhand_base_damage + profile.offhand_damage_bonus + damage_modifier)
		var offhand_damage := _apply_damage_multiplier(offhand_base_damage, damage_multiplier)
		var offhand_actual := controller.apply_damage(attacker, target, offhand_damage, "%s（副手）" % label)
		actual_damage += offhand_actual
		hit_results.append(StrikeHitResult.create("off", profile.offhand_equipment, offhand_damage, offhand_actual))

	var attack_results := []
	for result in hit_results:
		attack_results.append(result.to_dict())

	var trigger_context := {
		"controller": controller,
		"attacker": attacker,
		"target": target,
		"source": source,
		"damage_amount": primary_damage,
		"base_damage_amount": primary_base_damage,
		"damage_modifier": damage_modifier,
		"damage_multiplier": damage_multiplier,
		"actual_damage": actual_damage,
		"label": label,
		"strike_profile": profile.to_dict(),
		"strike_profile_object": profile,
		"attack_results": attack_results,
		"attack_result_objects": hit_results,
	}
	attacker.notify_after_strike(trigger_context)
	controller.enqueue_trigger(Callable(controller, "_emit_basic_attack_trigger"), [trigger_context], 0, "普通攻击触发", trigger_context)
	return actual_damage


func _apply_damage_multiplier(amount: int, multiplier: float) -> int:
	if amount <= 0:
		return 0

	return maxi(0, ceili(float(amount) * multiplier))
