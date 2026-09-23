extends Node


const EXPECTED_IDS := [
	"druid_spirit_pact",
	"druid_element_invocation",
	"druid_curse_prayer",
	"druid_wild_wander",
	"druid_wellspring_return",
	"druid_spirit_whisper",
	"druid_root_oath",
]

const NEW_EPIC_AP := {
	"druid_wild_wander": 1,
	"druid_wellspring_return": 3,
	"druid_spirit_whisper": 2,
	"druid_root_oath": 2,
}

var _exit_code := 0


func _ready() -> void:
	_test_all_dual_resources_are_player_catalogued()
	_test_final_top_level_pool_and_rarity_distribution()
	_test_new_epic_costs_and_explicit_exceptions()
	_test_new_rewards_do_not_modify_the_druid_starter_deck()
	if _exit_code == 0:
		print("DRUID_EXPANSION_CATALOG: PASS")
	get_tree().quit(_exit_code)


# Removing an explicit catalog entry must fail this integration boundary even
# though the .tres remains individually loadable from the filesystem.
func _test_all_dual_resources_are_player_catalogued() -> void:
	var catalog := load("res://resources/card_catalog.tres") as CardCatalog
	var rewards := load("res://resources/adventure_reward_catalog.tres") as AdventureRewardCatalog
	_expect(catalog != null and rewards != null, "both explicit player catalogs load")
	if catalog == null or rewards == null:
		return
	for card_id in EXPECTED_IDS:
		var card := load("res://resources/cards/%s.tres" % card_id) as CardData
		_expect(card != null and card.is_druid_dual_card, "registered druid dual resource: %s" % card_id)
		if card == null:
			continue
		_expect(not card.card_text.strip_edges().is_empty() and not card.inverted_card_text.strip_edges().is_empty(), "both player-facing faces are present: %s" % card_id)
		_expect(not card.resolution_rules.strip_edges().is_empty() and not card.inverted_resolution_rules.strip_edges().is_empty(), "both detailed rulings are present: %s" % card_id)
		_expect(catalog.cards.has(card), "card catalog explicitly contains: %s" % card_id)
		_expect(rewards.cards.has(card), "reward catalog explicitly contains: %s" % card_id)


func _test_final_top_level_pool_and_rarity_distribution() -> void:
	var top_level := 0
	var druid_total := 0
	var basic := 0
	var rare := 0
	var epic := 0
	for filename in DirAccess.get_files_at("res://resources/cards"):
		if not filename.ends_with(".tres"):
			continue
		var card := load("res://resources/cards/%s" % filename) as CardData
		if card == null:
			continue
		top_level += 1
		if card.card_class != CardEnums.CardClass.DRUID:
			continue
		druid_total += 1
		if card.rarity == CardEnums.Rarity.BASIC:
			basic += 1
		elif card.rarity == CardEnums.Rarity.RARE:
			rare += 1
		elif card.rarity == CardEnums.Rarity.EPIC:
			epic += 1
	_expect(top_level == 78, "top-level CardData pool is 78")
	_expect(druid_total == 17 and basic == 3 and rare == 8 and epic == 6, "druid pool is 17 (3 basic, 8 rare, 6 epic)")


func _test_new_epic_costs_and_explicit_exceptions() -> void:
	for card_id in NEW_EPIC_AP:
		var card := load("res://resources/cards/%s.tres" % card_id) as CardData
		_expect(card != null and card.rarity == CardEnums.Rarity.EPIC, "new card is epic: %s" % card_id)
		if card == null:
			continue
		var expected_ap := int(NEW_EPIC_AP[card_id])
		_expect(card.ap_cost == expected_ap and card.inverted_ap_cost == expected_ap, "both faces retain their printed AP: %s" % card_id)
	var wander := load("res://resources/cards/druid_wild_wander.tres") as CardData
	var whisper := load("res://resources/cards/druid_spirit_whisper.tres") as CardData
	_expect(wander != null and wander.upright_play_ignores_form and not wander.allow_twin_face_play, "only Wander has the upright form exception")
	_expect(whisper != null and whisper.allow_twin_face_play and not whisper.upright_play_ignores_form, "Whisper has only the explicit twin-face play exception")


func _test_new_rewards_do_not_modify_the_druid_starter_deck() -> void:
	var starter := load("res://resources/characters/battle_druid_state.tres") as CharacterState
	_expect(starter != null, "druid starter deck resource loads")
	if starter == null:
		return
	for stack in starter.deck:
		if stack == null or stack.card_data == null:
			continue
		_expect(not EXPECTED_IDS.has(stack.card_data.resource_path.get_file().get_basename()), "new reward is absent from druid starter deck: %s" % stack.card_data.resource_path)


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_exit_code = 1
	push_error("DRUID_EXPANSION_CATALOG: " + label)
