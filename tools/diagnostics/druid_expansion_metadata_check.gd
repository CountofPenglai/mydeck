extends Node


const Fixture := preload("res://tools/diagnostics/druid_expansion_fixture.gd")

var _exit_code := 0


func _ready() -> void:
	_test_twin_face_play_boundary()
	_test_serialized_legacy_twin_resource()
	_test_upright_form_exception()
	_test_face_metadata_persists_and_classifies_without_text()
	_test_new_cards_are_cataloged_with_top_level_counts()
	if _exit_code == 0:
		print("DRUID_EXPANSION_METADATA: PASS")
	get_tree().quit(_exit_code)


# Catches treating every twin spell as unplayable while transformed, even when its keyword face is explicitly allowed.
func _test_twin_face_play_boundary() -> void:
	var f := Fixture.make("druid_binding_enchantment", false)
	if f.is_empty():
		_fail("fixture could not create human druid")
		return
	f.card.twin_spell_face = CardEnums.DruidOrientation.UPRIGHT
	var ap_before: int = f.u.current_ap
	_expect(not f.c.play_card(f.u, f.card, [f.u]), "upright twin keyword face is not actively playable by default")
	_expect(f.u.current_ap == ap_before and f.u.hand.has(f.card), "rejected upright twin keyword face costs nothing")
	f = Fixture.make("druid_binding_enchantment", true)
	if f.is_empty():
		_fail("fixture could not create transformed druid")
		return
	f.card.twin_spell_face = CardEnums.DruidOrientation.INVERTED
	ap_before = f.u.current_ap
	_expect(not f.c.play_card(f.u, f.card, [f.u]), "twin keyword face is not actively playable by default")
	_expect(f.u.current_ap == ap_before and f.u.hand.has(f.card), "rejected twin keyword face costs nothing")
	f = Fixture.make("druid_binding_enchantment", true)
	f.card.twin_spell_face = CardEnums.DruidOrientation.INVERTED
	f.card.allow_twin_face_play = true
	_expect(f.c.play_card(f.u, f.card, [f.u]), "explicit twin-face exception permits the keyword face")


func _test_serialized_legacy_twin_resource() -> void:
	var legacy := load("res://tools/diagnostics/fixtures/druid_legacy_twin_spell.tres") as CardData
	_expect(legacy != null and legacy.get_twin_spell_face() == CardEnums.DruidOrientation.INVERTED, "serialized pre-field twin resource keeps the inverse keyword face")
	if legacy == null:
		return
	var f := Fixture.make("druid_binding_enchantment", true)
	if f.is_empty():
		_fail("fixture could not create serialized legacy twin case")
		return
	f.u.hand.clear()
	f.u.hand.append(legacy)
	var ap_before: int = f.u.current_ap
	_expect(not f.c.play_card(f.u, legacy, [f.u]), "serialized legacy twin keyword face remains blocked")
	_expect(f.u.current_ap == ap_before and f.u.hand.has(legacy), "serialized legacy twin rejection costs nothing")
	legacy.allow_twin_face_play = true
	_expect(f.c.play_card(f.u, legacy, [f.u]), "serialized legacy twin honors the explicit play exception")


# Catches resolving an explicit upright exception as the transformed face.
func _test_upright_form_exception() -> void:
	var f := Fixture.make("druid_binding_enchantment", true)
	if f.is_empty():
		_fail("fixture could not create upright exception case")
		return
	f.card.set("upright_play_ignores_form", true)
	_expect(f.c.play_card(f.u, f.card, [f.u]), "upright form exception is playable while transformed")
	_expect(f.u.discard_pile.has(f.card) and not f.u.mana_zone.has(f.card), "upright form exception resolves the upright destination")


# Catches future card classification by prose and confirms new face metadata survives Resource serialization.
func _test_face_metadata_persists_and_classifies_without_text() -> void:
	var card := CardData.new()
	card.set("twin_spell_face", CardEnums.DruidOrientation.INVERTED)
	card.set("upright_is_transformation", true)
	card.set("inverted_is_transformation", false)
	card.is_druid_dual_card = true
	card.card_text = "ordinary wording"
	card.inverted_card_text = "ordinary wording"
	_expect(card.has_method("get_twin_spell_face") and int(card.call("get_twin_spell_face")) == CardEnums.DruidOrientation.INVERTED, "explicit twin face is available to consumers")
	_expect(card.has_method("is_transformation_for_context") and bool(card.call("is_transformation_for_context", {"druid_orientation": CardEnums.DruidOrientation.UPRIGHT})), "upright transformation classification ignores wording")
	_expect(card.has_method("is_transformation_for_context") and not bool(card.call("is_transformation_for_context", {"druid_orientation": CardEnums.DruidOrientation.INVERTED})), "inverted transformation classification uses its own face")
	_expect(RulesTextFormatter.format_card(card).contains("双生法术（逆位）"), "formatter exposes the twin keyword face")
	var canopy := load("res://resources/cards/druid_canopy_cycle.tres") as CardData
	var verdant := load("res://resources/cards/druid_verdant_strike.tres") as CardData
	var wild_shape := load("res://resources/cards/druid_wild_shape.tres") as CardData
	_expect(canopy != null and canopy.is_transformation_for_context({"druid_orientation": CardEnums.DruidOrientation.UPRIGHT}), "canopy upright is explicitly a transformation")
	_expect(verdant != null and verdant.is_transformation_for_context({"druid_orientation": CardEnums.DruidOrientation.UPRIGHT}), "verdant upright is explicitly a transformation")
	_expect(wild_shape != null and wild_shape.is_transformation_for_context({"druid_orientation": CardEnums.DruidOrientation.UPRIGHT}) and wild_shape.is_transformation_for_context({"druid_orientation": CardEnums.DruidOrientation.INVERTED}), "wild shape records both form-changing faces")
	var save_path := "user://druid_expansion_metadata_check.tres"
	_expect(ResourceSaver.save(card, save_path) == OK, "metadata resource saves")
	var loaded := load(save_path) as CardData
	if loaded == null:
		_fail("serialized metadata reloads for consumers")
	else:
		_expect(int(loaded.get("twin_spell_face")) == CardEnums.DruidOrientation.INVERTED and bool(loaded.get("upright_is_transformation")), "serialized metadata reloads for consumers")
	DirAccess.remove_absolute(save_path)


func _test_new_cards_are_cataloged_with_top_level_counts() -> void:
	var catalog := load("res://resources/card_catalog.tres") as CardCatalog
	var rewards := load("res://resources/adventure_reward_catalog.tres") as AdventureRewardCatalog
	_expect(catalog != null and rewards != null, "card and reward catalogs load")
	if catalog == null or rewards == null: return
	for id in ["druid_spirit_pact", "druid_element_invocation", "druid_curse_prayer"]:
		var card := load("res://resources/cards/%s.tres" % id) as CardData
		_expect(catalog.cards.has(card) and rewards.cards.has(card), "%s appears in both player catalogs" % id)
	var top_level := 0
	var druid_total := 0
	var basic := 0
	var rare := 0
	var epic := 0
	for filename in DirAccess.get_files_at("res://resources/cards"):
		if not filename.ends_with(".tres"): continue
		var card := load("res://resources/cards/%s" % filename) as CardData
		if card == null: continue
		top_level += 1
		if card.card_class == CardEnums.CardClass.DRUID:
			druid_total += 1
			if card.rarity == CardEnums.Rarity.BASIC: basic += 1
			elif card.rarity == CardEnums.Rarity.RARE: rare += 1
			elif card.rarity == CardEnums.Rarity.EPIC: epic += 1
	_expect(top_level == 74 and druid_total == 13 and basic == 3 and rare == 8 and epic == 2, "top-level pool is 74 cards; druid is 13 (3 basic, 8 rare, 2 epic)")


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_fail(label)


func _fail(label: String) -> void:
	_exit_code = 1
	push_error("DRUID_EXPANSION_METADATA: %s" % label)
