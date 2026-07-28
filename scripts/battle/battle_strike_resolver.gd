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
	if not attacker.can_use_attack_mode(equipment_slot, {"controller": controller, "target": target, "source": source}):
		return 0

	var profile_context := options.duplicate()
	profile_context["controller"] = controller
	profile_context["source"] = source
	profile_context["target"] = target
	profile_context["label"] = label
	profile_context["equipment_slot"] = equipment_slot
	var profile := attacker.build_strike_profile_object(equipment_slot, profile_context)
	profile_context = attacker.notify_before_strike(profile_context)
	var resolved_multiplier := damage_multiplier
	if options.has("ranger_attack_multiplier"):
		if bool(options.get("skip_ranger_ambush", false)):
			resolved_multiplier *= float(options.get("ranger_attack_multiplier", 1.0))
		elif not attacker.is_stealthed():
			resolved_multiplier *= float(options.get("ranger_attack_multiplier", 1.0))
		else:
			resolved_multiplier *= controller.consume_ranger_stealth_for_attack(
				attacker,
				float(options.get("ranger_attack_multiplier", 1.0)),
				profile_context
			)
	elif bool(options.get("equipment_automatic", false)) and attacker.is_stealthed():
		attacker.leave_stealth()
	elif not bool(options.get("skip_ranger_ambush", false)):
		resolved_multiplier *= controller.consume_ranger_stealth_for_attack(
			attacker,
			float(options.get("ranger_ambush_override", 0.0)),
			profile_context
		)
	var primary_weapon_damage := int(options.get("primary_base_damage_override", profile.primary_base_damage))
	var primary_base_damage := maxi(0, primary_weapon_damage + profile.primary_damage_bonus + damage_modifier)
	var primary_damage := _apply_damage_multiplier(primary_base_damage, resolved_multiplier)
	var damage_metadata := {
		"strike": true,
		"range_type": profile.primary_range_type,
		"equipment_slot": equipment_slot,
		"source_card": source,
		"ignore_ranged_surface_reduction": bool(options.get("ignore_ranged_surface_reduction", false)),
		"ignore_armor": bool(profile_context.get("ignore_armor", false)),
		"surface_element": int(profile_context.get("surface_element", BattleSurfaceState.Element.NONE)),
	}
	var actual_damage := controller.apply_damage(attacker, target, primary_damage, label, damage_metadata)
	var hit_results: Array[StrikeHitResult] = [
		StrikeHitResult.create(profile.primary_slot, profile.primary_equipment, primary_damage, actual_damage)
	]

	if profile.add_offhand and target.is_alive():
		var offhand_base_damage := maxi(0, profile.offhand_base_damage + profile.offhand_damage_bonus + damage_modifier)
		var offhand_damage := _apply_damage_multiplier(offhand_base_damage, resolved_multiplier)
		var offhand_actual := controller.apply_damage(attacker, target, offhand_damage, "%s（副手）" % label, {
			"strike": true,
			"range_type": profile.primary_range_type,
			"equipment_slot": "off",
			"source_card": source,
			"ignore_ranged_surface_reduction": bool(options.get("ignore_ranged_surface_reduction", false)),
		})
		actual_damage += offhand_actual
		hit_results.append(StrikeHitResult.create("off", profile.offhand_equipment, offhand_damage, offhand_actual))

	var attack_results := []
	for result in hit_results:
		attack_results.append(result.to_dict())

	var trigger_context := {
		"controller": controller,
		"action_id": controller.get_current_action_id(),
		"attacker": attacker,
		"target": target,
		"source": source,
		"damage_amount": primary_damage,
		"base_damage_amount": primary_base_damage,
		"damage_modifier": damage_modifier,
		"damage_multiplier": resolved_multiplier,
		"actual_damage": actual_damage,
		"label": label,
		"strike_profile": profile.to_dict(),
		"strike_profile_object": profile,
		"attack_results": attack_results,
		"attack_result_objects": hit_results,
		"equipment_slot": profile.primary_slot,
		"strike_options": options,
	}
	trigger_context.merge(profile_context)
	attacker.notify_after_strike(trigger_context)
	controller.resolve_ranger_after_strike(trigger_context)
	controller.enqueue_trigger(Callable(controller, "_emit_basic_attack_trigger"), [trigger_context], 0, "普通攻击触发", trigger_context)
	return actual_damage


func perform_object_strike_with_modifier(
	attacker: BattleUnitState,
	target: BattleObjectState,
	source = null,
	damage_modifier: int = 0,
	label: String = "打击",
	equipment_slot: String = ""
) -> int:
	if controller == null or attacker == null or target == null \
			or not attacker.is_alive() or not target.can_be_damaged():
		return 0
	var profile_context := {
		"controller": controller,
		"source": source,
		"target_object": target,
		"label": label,
		"equipment_slot": equipment_slot,
	}
	if not attacker.can_use_attack_mode(equipment_slot, profile_context):
		return 0
	var profile := attacker.build_strike_profile_object(equipment_slot, profile_context)
	profile_context = attacker.notify_before_strike(profile_context)
	var damage_multiplier := controller.consume_ranger_stealth_for_attack(
		attacker,
		0.0,
		profile_context
	)
	var primary_damage := maxi(
		0,
		profile.primary_base_damage + profile.primary_damage_bonus + damage_modifier
	)
	primary_damage = _apply_damage_multiplier(primary_damage, damage_multiplier)
	var actual_damage := controller.apply_object_damage(
		attacker,
		target,
		primary_damage,
		label,
		{
			"strike": true,
			"range_type": profile.primary_range_type,
			"equipment_slot": equipment_slot,
			"source_cell": attacker.cell,
			"source_card": source,
		}
	)
	var hit_results: Array[StrikeHitResult] = [
		StrikeHitResult.create(
			profile.primary_slot,
			profile.primary_equipment,
			primary_damage,
			actual_damage
		)
	]
	if profile.add_offhand and target.can_be_damaged():
		var offhand_damage := maxi(
			0,
			profile.offhand_base_damage + profile.offhand_damage_bonus + damage_modifier
		)
		offhand_damage = _apply_damage_multiplier(offhand_damage, damage_multiplier)
		var offhand_actual := controller.apply_object_damage(
			attacker,
			target,
			offhand_damage,
			"%s（副手）" % label,
			{
				"strike": true,
				"range_type": profile.primary_range_type,
				"equipment_slot": "off",
				"source_cell": attacker.cell,
				"source_card": source,
			}
		)
		actual_damage += offhand_actual
		hit_results.append(StrikeHitResult.create(
			"off",
			profile.offhand_equipment,
			offhand_damage,
			offhand_actual
		))
	var attack_results: Array = []
	for result in hit_results:
		attack_results.append(result.to_dict())
	var trigger_context := {
		"controller": controller,
		"action_id": controller.get_current_action_id(),
		"attacker": attacker,
		"target_object": target,
		"source": source,
		"damage_amount": primary_damage,
		"base_damage_amount": primary_damage,
		"damage_modifier": damage_modifier,
		"damage_multiplier": damage_multiplier,
		"actual_damage": actual_damage,
		"label": label,
		"strike_profile": profile.to_dict(),
		"strike_profile_object": profile,
		"attack_results": attack_results,
		"attack_result_objects": hit_results,
		"equipment_slot": profile.primary_slot,
		"strike_options": {"object_target": true},
	}
	trigger_context.merge(profile_context)
	attacker.notify_after_strike(trigger_context)
	controller.resolve_ranger_after_strike(trigger_context)
	controller.enqueue_trigger(
		Callable(controller, "_emit_basic_attack_trigger"),
		[trigger_context],
		0,
		"普通攻击触发",
		trigger_context
	)
	return actual_damage


func _apply_damage_multiplier(amount: int, multiplier: float) -> int:
	if amount <= 0:
		return 0

	return maxi(0, ceili(float(amount) * multiplier))
