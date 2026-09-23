extends CardEffect
class_name DruidRootOathCardEffect


const ROOT_STATUS := preload("res://scripts/status/druid_root_status.gd")
const OATH_STATUS := preload("res://scripts/status/druid_root_oath_status.gd")


func play(context: Dictionary = {}, _targets: Array = []) -> void:
	var controller := context.get("controller") as BattleController
	var user := context.get("user") as BattleUnitState
	var card := context.get("card") as CardData
	if controller == null or user == null or card == null:
		return
	if _is_inverted(context):
		user.move_hand_card_to_enchant(card, context)
		return
	user.add_status(ROOT_STATUS.new())
	controller.request_druid_form_change(user, true, context)
	for recipient in controller.druid_battle_rules.get_rooted_units(user):
		if recipient.faction != user.faction:
			continue
		recipient.gain_armor(4, {
			"controller": controller,
			"source": user,
			"source_card": card,
		})
		_grant_oath(recipient, user)


func get_incarnation_bonus(owner: BattleUnitState, context: Dictionary = {}) -> int:
	if owner == null or not bool(context.get("strike", false)):
		return 0
	var result := 4
	if owner.has_status("druid_root") and owner.battle_controller != null:
		result += 2 * owner.battle_controller.druid_battle_rules.get_rooted_units(owner).size()
	return result


func get_zone_owner_damage_bonus(owner: BattleUnitState, _zone_card: CardData, context: Dictionary = {}) -> int:
	if not _is_enchant_card(owner, _zone_card, context) or context.get("equipment") == null:
		return 0
	return get_incarnation_bonus(owner, context)


func get_zone_owner_damage_reduction(owner: BattleUnitState, _zone_card: CardData, context: Dictionary = {}) -> int:
	if not _is_enchant_card(owner, _zone_card, context) or not owner.has_status("druid_root"):
		return 0
	var damage_context := context.get("damage_context") as DamageContext
	if damage_context != null and bool(damage_context.metadata.get("fixed_damage", false)):
		return 0
	return 3


func get_zone_effect_deduplication_key(zone_card: CardData, context: Dictionary = {}) -> String:
	var owner := context.get("zone_owner") as BattleUnitState
	return "druid_root_oath_incarnation" if _is_enchant_card(owner, zone_card, context) else ""


func _grant_oath(recipient: BattleUnitState, source: BattleUnitState) -> void:
	if recipient == null or source == null:
		return
	var status := OATH_STATUS.new()
	status.source_unit_id = source.unit_id
	status.expires_on_source_turn = source.turn_serial + 1
	recipient.remove_status(status.status_id)
	recipient.add_status(status)


func _is_inverted(context: Dictionary) -> bool:
	return int(context.get("druid_orientation", CardEnums.DruidOrientation.UPRIGHT)) == CardEnums.DruidOrientation.INVERTED


func _is_enchant_card(owner: BattleUnitState, zone_card: CardData, context: Dictionary) -> bool:
	return owner != null and zone_card != null and str(context.get("zone_name", "")) == "enchant" and owner.enchant_zone.has(zone_card)
