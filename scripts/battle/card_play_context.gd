extends RefCounted
class_name CardPlayContext

var controller: BattleController
var user: BattleUnitState
var card: CardData
var weapon_slot: String = ""
var extra: Dictionary = {}


static func create(new_controller: BattleController, new_user: BattleUnitState, new_card: CardData, new_weapon_slot: String = "", new_extra: Dictionary = {}) -> CardPlayContext:
	var context := CardPlayContext.new()
	context.controller = new_controller
	context.user = new_user
	context.card = new_card
	context.weapon_slot = new_weapon_slot
	context.extra = new_extra.duplicate()
	return context


func to_dict() -> Dictionary:
	var result := extra.duplicate()
	result["controller"] = controller
	result["user"] = user
	result["card"] = card
	result["weapon_slot"] = weapon_slot
	result["card_context"] = self
	return result

