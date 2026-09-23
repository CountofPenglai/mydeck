extends CardEffect
class_name DruidWellspringReturnCardEffect

var direct_draw_count := 0
var strikes_remaining := 0


func requires_weapon_choice(context: Dictionary = {}) -> bool:
	return _is_inverted(context)


func play(context: Dictionary = {}, _targets: Array = []) -> void:
	var controller := context.get("controller") as BattleController
	var owner := context.get("user") as BattleUnitState
	var card := context.get("card") as CardData
	if controller == null or owner == null or card == null:
		return
	if _is_inverted(context):
		_begin_inverse(context, controller, owner, card)
		return
	controller.resolution_runner.request_zone_card_choice(owner, card, PackedStringArray(["mana"]), 0, 5, "灵泉归流：选择至多5张法力区卡牌移回手牌", Callable(self, "_resolve_upright_choice").bind(context, owner), Callable(), true)

func _resolve_upright_choice(selected: Array[CardData], context: Dictionary, owner: BattleUnitState) -> void:
	if owner == null:
		return
	for selected_card in selected:
		owner.move_mana_card_to_hand(selected_card, context)
	owner.gain_mana(3, context)

func _begin_inverse(context: Dictionary, controller: BattleController, owner: BattleUnitState, card: CardData) -> void:
	# The resolving card remains in hand until frame finalization, but it is not
	# one of the cards the inverse compares against available mana.
	var resolving_source_count := 1 if owner.hand.has(card) else 0
	var needed := maxi(0, owner.get_available_mana() - (owner.hand.size() - resolving_source_count))
	var direct_cards := draw_directly_for_this_effect(owner, needed, context)
	direct_draw_count = direct_cards.size()
	strikes_remaining = direct_draw_count
	controller.resolution_runner.enqueue_after_current_effect_queue(Callable(self, "_request_next_strike").bind(context, controller, owner, card), [], "怒潮奔涌：抽牌后打击")

func draw_directly_for_this_effect(owner: BattleUnitState, amount: int, context: Dictionary) -> Array[CardData]:
	var controller := context.get("controller") as BattleController
	if owner == null or controller == null:
		return []
	var direct_context := context.duplicate()
	direct_context["reason"] = "druid_wellspring_return_direct_draw"
	direct_context["direct_draw_source"] = "druid_wellspring_return"
	return owner.draw_cards_detailed(amount, controller.rng, direct_context)

func _request_next_strike(context: Dictionary, controller: BattleController, owner: BattleUnitState, card: CardData) -> void:
	if strikes_remaining <= 0 or controller == null or owner == null or card == null or not owner.is_alive() or not owner.is_deployed:
		return
	var equipment_slot := str(context.get("equipment_slot", ""))
	var candidates: Array[BattleUnitState] = []
	candidates.assign(controller.enemy_units)
	controller.resolution_runner.request_unit_target_choice(owner, card, "怒潮奔涌：选择1名敌人进行打击，或结束", Callable(self, "_resolve_inverse_strike").bind(context, controller, owner, card), candidates, Callable(self, "_is_legal_strike_target").bind(controller, owner, equipment_slot))

func _resolve_inverse_strike(target: BattleUnitState, context: Dictionary, controller: BattleController, owner: BattleUnitState, card: CardData) -> void:
	if target == null or strikes_remaining <= 0 or not _is_legal_strike_target(target, controller, owner, str(context.get("equipment_slot", ""))):
		return
	strikes_remaining -= 1
	controller.perform_unit_strike_with_after_effects(owner, target, card, "怒潮奔涌", str(context.get("equipment_slot", "")), Callable(self, "_request_next_strike").bind(context, controller, owner, card))

func _is_legal_strike_target(target: BattleUnitState, controller: BattleController, owner: BattleUnitState, equipment_slot: String) -> bool:
	if target == null or controller == null or owner == null or not owner.is_alive() or not owner.is_deployed \
			or not target.is_alive() or not target.is_deployed or target.faction == owner.faction \
			or controller.is_unit_concealed(target):
		return false
	var strike_context := {"controller": controller, "target": target, "equipment_slot": equipment_slot}
	if not owner.can_use_attack_mode(equipment_slot, strike_context):
		return false
	if owner.get_range_distance_to(target, strike_context) > controller.get_effective_attack_range_against(owner, target, equipment_slot):
		return false
	var profile := owner.build_strike_profile_object(equipment_slot, strike_context)
	return profile.primary_range_type != EquipmentData.WeaponRangeType.RANGED \
		or controller.targeting.has_line_of_sight_between_units(owner, target)

func _is_inverted(context: Dictionary) -> bool:
	return int(context.get("druid_orientation", CardEnums.DruidOrientation.UPRIGHT)) == CardEnums.DruidOrientation.INVERTED
