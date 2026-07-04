extends RefCounted
class_name CardPlayContext

var controller: BattleController
var user: BattleUnitState
var card: CardData
var equipment_slot: String = ""
var play_mode: int = CardEnums.CardPlayMode.NORMAL
var extra: Dictionary = {}


static func create(new_controller: BattleController, new_user: BattleUnitState, new_card: CardData, new_equipment_slot: String = "", new_extra: Dictionary = {}, new_play_mode: int = CardEnums.CardPlayMode.NORMAL) -> CardPlayContext:
	var context := CardPlayContext.new()
	context.controller = new_controller
	context.user = new_user
	context.card = new_card
	context.equipment_slot = new_equipment_slot
	context.play_mode = new_play_mode
	context.extra = new_extra.duplicate()
	return context


func to_dict() -> Dictionary:
	var result := extra.duplicate()
	result["controller"] = controller
	result["user"] = user
	result["card"] = card
	result["equipment_slot"] = equipment_slot
	result["play_mode"] = play_mode
	result["play_mode_label"] = CardEnums.play_mode_label(play_mode)
	result["card_context"] = self
	return result
