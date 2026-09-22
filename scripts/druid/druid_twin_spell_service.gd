extends RefCounted
class_name DruidTwinSpellService


const SELECTION_SERVICE := preload("res://scripts/battle/battle_selection_service.gd")

var controller: BattleController
var selection_service := SELECTION_SERVICE.new()


func setup(new_controller: BattleController) -> void:
	controller = new_controller


func can_begin(owner: BattleUnitState, card: CardData) -> bool:
	if controller == null or owner == null or card == null:
		return false
	if controller.phase != BattleController.Phase.BATTLE or controller.turn_flow_state != BattleController.TurnFlowState.ACTIVE:
		return false
	return controller.current_unit == owner and owner.faction == BattleUnitState.Faction.PLAYER and owner.is_alive() and owner.is_druid() \
		and not controller.is_resolving_actions() and not controller.resolution_state_notification_active \
		and owner.has_card_in_hand(card) and card.get_twin_spell_face() >= 0


func get_candidates(owner: BattleUnitState, card: CardData) -> Array[CardData]:
	var result: Array[CardData] = []
	if owner == null or card == null:
		return result
	var face: int = card.get_twin_spell_face()
	if face < 0:
		return result
	var opposite: int = CardEnums.DruidOrientation.INVERTED if face == CardEnums.DruidOrientation.UPRIGHT else CardEnums.DruidOrientation.UPRIGHT
	for candidate in selection_service.get_cards(owner, PackedStringArray(["draw", "discard"])):
		if candidate != null and candidate != card and candidate.get_twin_spell_face() == opposite:
			result.append(candidate)
	return result


func is_candidate_for(source: CardData, candidate: CardData) -> bool:
	if source == null or candidate == null or source == candidate:
		return false
	var face: int = source.get_twin_spell_face()
	if face < 0:
		return false
	var opposite: int = CardEnums.DruidOrientation.INVERTED if face == CardEnums.DruidOrientation.UPRIGHT else CardEnums.DruidOrientation.UPRIGHT
	return candidate.get_twin_spell_face() == opposite


func execute(owner: BattleUnitState, card: CardData, selected: CardData = null, searched_deck: bool = false) -> bool:
	if owner == null or card == null or card.get_twin_spell_face() < 0 or not owner.has_card_in_hand(card):
		return false
	if selected != null and not get_candidates(owner, card).has(selected):
		return false
	if not owner.move_hand_card_to_mana(card, {"controller": controller, "reason": "druid_twin_spell_free_entry", "source": owner, "source_card": card}):
		return false
	if controller != null and controller.get_current_action_id() > 0:
		controller.resolution_runner.enqueue_after_current_effect_queue(Callable(self, "_finish_retrieval").bind(owner, selected, searched_deck), [], "双生法术检索")
	else:
		_finish_retrieval(owner, selected, searched_deck)
	return true


func _finish_retrieval(owner: BattleUnitState, selected: CardData, searched_deck: bool) -> void:
	if owner == null:
		return
	if selected != null:
		var selected_from_draw: bool = owner.draw_pile.has(selected)
		var selected_from_discard: bool = owner.discard_pile.has(selected)
		if selected_from_draw:
			owner.move_draw_card_to_hand(selected)
		elif selected_from_discard:
			owner.move_discard_card_to_hand(selected)
		searched_deck = searched_deck or selected_from_draw
	if searched_deck and controller != null:
		owner.shuffle_draw_pile(controller.rng)
