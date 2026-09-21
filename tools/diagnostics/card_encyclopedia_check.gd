extends Node

var failures := 0

func _ready() -> void:
	if not ResourceLoader.exists("res://resources/card_catalog.tres"):
		_check(false, "export-safe card catalog missing")
	else:
		await _exercise_catalog()
	print("CARD_ENCYCLOPEDIA: %s" % ("PASS" if failures == 0 else "FAIL"))
	get_tree().quit(0 if failures == 0 else 1)

func _exercise_catalog() -> void:
	var script: Script = load("res://scripts/menu/card_catalog.gd")
	var catalog: Resource = script.new()
	var dual := CardData.new()
	dual.card_name = "测试正位"
	dual.is_druid_dual_card = true
	dual.inverted_name = "测试逆位"
	dual.inverted_ap_cost = 3
	dual.inverted_card_text = "逆位规则正文"
	dual.inverted_resolution_rules = "逆位详细裁定"
	dual.allowed_classes = PackedInt32Array([CardEnums.CardClass.WARRIOR, CardEnums.CardClass.DRUID])
	var basic := CardData.new()
	basic.card_name = "基础样本"
	basic.rarity = CardEnums.Rarity.BASIC
	var cards: Array[CardData] = [dual, basic, dual]
	catalog.cards = cards
	_check(catalog.query().size() == 2, "duplicate resources deduplicated")
	_check(catalog.query()[0] == basic, "basic sorted before common")
	_check(catalog.query(CardEnums.CardClass.DRUID, -1, "  逆位 ").size() == 1, "multiclass and reverse-name search")
	_check(catalog.query(CardEnums.CardClass.NEUTRAL).size() == 1, "explicit multiclass not misclassified neutral")
	_check(catalog.query(-1, CardEnums.Rarity.BASIC).size() == 1, "rarity filter")
	_check(catalog.query(-1, -1, "不存在").is_empty(), "empty search result")
	var real: Resource = load("res://resources/card_catalog.tres")
	var paths: Array[String] = []
	for card in real.query():
		_check(card != null, "all references load")
		paths.append(card.resource_path)
	var rewards := load("res://resources/adventure_reward_catalog.tres") as AdventureRewardCatalog
	var reward_before := rewards.cards.duplicate()
	for card in rewards.cards:
		_check(paths.has(card.resource_path), "reward card included: " + card.card_name)
	for hero_path in AdventureSessionService.HERO_PATHS:
		var hero := load(hero_path) as CharacterState
		for stack in hero.deck:
			_check(paths.has(stack.card_data.resource_path), "starter included")
	for path in ["res://resources/cards/curse_disease.tres", "res://resources/cards/monster_cards/temporary_jinx.tres", "res://resources/cards/curse_industry_gospel.tres"]:
		_check(paths.has(path), "player-generated curse included")
	_check(not paths.has("res://resources/cards/monster_cards/approach_bite.tres"), "enemy-only card excluded")
	var page: Control = load("res://scenes/ui/card_encyclopedia.tscn").instantiate()
	page.catalog = catalog
	add_child(page)
	await get_tree().process_frame
	page.show_card(dual, true)
	var selected_style := page.card_list.get_theme_stylebox("selected") as StyleBoxFlat
	var panel_style := page.card_list.get_theme_stylebox("panel") as StyleBoxFlat
	var selected_background := panel_style.bg_color.blend(selected_style.bg_color)
	var selected_foreground: Color = page.card_list.get_theme_color("font_selected_color")
	_check(absf(selected_foreground.get_luminance() - selected_background.get_luminance()) > 0.35, "selected card text retains readable contrast")
	_check(page.detail_title.text.contains("测试逆位") and page.detail_meta.text.contains("3 AP"), "reverse name and cost")
	_check(page.detail_body.text.contains("逆位规则正文") and page.detail_rules.text.contains("逆位详细裁定"), "existing rules shown")
	_check(page.find_child("PlayButton", true, false) == null, "encyclopedia is read-only")
	_check(dual.card_name == "测试正位" and rewards.cards == reward_before, "browsing cannot mutate cards or rewards")
	page.show_card(basic)
	_check(not page.detail_rules.text.is_empty(), "missing rulings gets placeholder")
	page.free()

func _check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		printerr("CARD_ENCYCLOPEDIA: " + label)
