extends RangerWeaponCardEffect
class_name RangerWaitingPreyCardEffect

const WATCHER_STATUS := preload("res://scripts/status/ranger_enchant_watcher_status.gd")


func play(context: Dictionary = {}, _targets: Array = []) -> void:
	var controller: BattleController = context.get("controller") as BattleController
	var user: BattleUnitState = context.get("user") as BattleUnitState
	var card: CardData = context.get("card") as CardData
	var equipment_slot := str(context.get("equipment_slot", ""))
	if controller == null or user == null or card == null:
		return
	if not user.move_hand_card_to_enchant(card, context):
		return
	var watcher := WATCHER_STATUS.new() as RangerEnchantWatcherStatus
	watcher.configure(
		controller,
		user,
		card,
		RangerEnchantWatcherStatus.TriggerKind.WAIT_FOR_MOVEMENT,
		equipment_slot
	)
	user.add_status(watcher)
	controller.enqueue_effect(
		Callable(controller, "enter_ranger_stealth"),
		[user, "守候猎物潜行"],
		effect_priority,
		"守候猎物：进入潜行",
		context
	)
	controller._emit_log("%s 以%s模式守候猎物。" % [user.get_display_name(), "近战" if equipment_slot != "paired" else "远程"])
