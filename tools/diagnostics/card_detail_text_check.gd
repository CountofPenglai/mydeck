extends Node

var _exit_code := 0


func _ready() -> void:
	_test_card_text_precedence_and_legacy_fallback()
	_test_druid_face_text_and_rules()
	await _test_detail_rules_toggle_and_preview_state()
	if _exit_code == 0:
		print("CARD_DETAIL_TEXT_CHECK: PASS")
	get_tree().quit(_exit_code)


func _test_card_text_precedence_and_legacy_fallback() -> void:
	var card := CardData.new()
	if not _has_export(card, "card_text"):
		_fail("CardData is missing the card_text display field")
		return
	card.description = "旧版卡面效果。"
	card.card_text = "新版卡面效果。"
	_expect(RulesTextFormatter.format_card(card).contains("新版卡面效果。"), "card text does not override legacy description")
	_expect(not RulesTextFormatter.format_card(card).contains("旧版卡面效果。"), "formatter still renders legacy text when card text exists")
	card.card_text = ""
	_expect(RulesTextFormatter.format_card(card).contains("旧版卡面效果。"), "empty card text does not fall back to legacy description")
	card.card_text = " \n\t "
	_expect(RulesTextFormatter.format_card(card).contains("旧版卡面效果。"), "whitespace-only card text does not fall back to legacy description")


func _test_druid_face_text_and_rules() -> void:
	var card := CardData.new()
	if not _has_export(card, "inverted_card_text") or not _has_export(card, "inverted_resolution_rules"):
		_fail("Druid inverse face cannot carry its own display text and rulings")
		return
	card.is_druid_dual_card = true
	card.card_text = "正位正文"
	card.resolution_rules = "正位裁定"
	card.inverted_description = "旧逆位正文"
	card.set("inverted_card_text", "逆位新正文")
	card.set("inverted_resolution_rules", "逆位裁定")
	var upright := {"druid_orientation": CardEnums.DruidOrientation.UPRIGHT}
	var inverted := {"druid_orientation": CardEnums.DruidOrientation.INVERTED}
	_expect(card.get_description_for_context(upright) == "正位正文", "upright face leaked inverse text")
	_expect(card.get_description_for_context(inverted) == "逆位新正文", "inverse display ignored new face text")
	_expect(card.get_resolution_rules_for_context(inverted) == "逆位裁定", "inverse detail leaked upright ruling")
	_expect(card.get_resolution_rules_for_context(upright) == "正位裁定", "upright detail leaked inverse ruling")
	card.set("inverted_card_text", " \n ")
	card.set("inverted_resolution_rules", "")
	_expect(card.get_description_for_context(inverted) == "旧逆位正文", "legacy inverse display fallback lost")
	_expect(card.get_resolution_rules_for_context(inverted) == "正位裁定", "legacy shared rule fallback lost")


func _test_detail_rules_toggle_and_preview_state() -> void:
	var field_probe := CardData.new()
	if not _has_export(field_probe, "resolution_rules"):
		_fail("CardData is missing the resolution_rules detail field")
		return
	var panel_scene := load("res://scenes/ui/battle/battle_detail_panel.tscn") as PackedScene
	var panel := panel_scene.instantiate() as BattleDetailPanel
	add_child(panel)
	await get_tree().process_frame
	var first_card := CardData.new()
	first_card.card_name = "首张"
	first_card.card_text = "首张卡面效果。"
	first_card.resolution_rules = "首张详细裁定。"
	panel.preview_card(first_card)
	_expect(panel.get_display_body().contains("首张卡面效果。"), "detail card body does not render card text")
	_expect(not panel.get_display_body().contains("首张详细裁定。"), "rules appear before detail expansion")
	_expect(panel.has_resolution_rules_toggle(), "rules toggle is missing for card with rules")
	var rules_button := panel.get_node_or_null("%ResolutionRulesButton") as Button
	_expect(rules_button != null, "rules button is absent from the detail scene")
	if rules_button != null:
		rules_button.pressed.emit()
	_expect(panel.get_display_body().contains("首张详细裁定。"), "rules do not appear after detail expansion")
	panel.lock_current()

	var second_card := CardData.new()
	second_card.card_name = "次张"
	second_card.card_text = "次张卡面效果。"
	second_card.resolution_rules = "次张详细裁定。"
	panel.preview_card(second_card)
	_expect(not panel.get_display_body().contains("首张详细裁定。"), "switching cards leaks prior rules")
	_expect(not panel.get_display_body().contains("次张详细裁定。"), "switching cards leaves rules expanded")
	panel.clear_preview()
	_expect(not panel.get_display_body().contains("次张详细裁定。"), "locked preview restores another card's rules")
	panel.clear_lock()

	var legacy_card := CardData.new()
	legacy_card.description = "旧版详情效果。"
	panel.preview_card(legacy_card)
	_expect(not panel.has_resolution_rules_toggle(), "rules toggle remains visible for card without rules")
	_expect(not panel.get_display_body().contains("首张详细裁定。"), "cleared lock retains prior rules")
	panel.queue_free()
	await get_tree().process_frame


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_fail(label)


func _has_export(resource: Resource, field_name: String) -> bool:
	for property in resource.get_property_list():
		if str(property.get("name", "")) == field_name:
			return true
	return false


func _fail(label: String) -> void:
	_exit_code = 1
	push_error("CARD_DETAIL_TEXT_CHECK: %s" % label)
