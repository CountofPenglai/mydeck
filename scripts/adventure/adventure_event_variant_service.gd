extends RefCounted
class_name AdventureEventVariantService

const CARD_ONLY_EVENTS: PackedStringArray = [
	"hermit_house", "adventurer_remains", "nature_blessing",
]
const DANGER_TEXT := "危险 18+：改为进入一场普通战斗。胜利后仅获得卡牌奖励，不获得本事件的原有效果或其他战斗奖励。"

## Pure presentation and resolution policy; never rolls encounters or grants rewards.
static func resolve(content_id: String, danger: int) -> Dictionary:
	var definition := AdventureContentCatalog.get_event_definition(content_id)
	var has_variant := CARD_ONLY_EVENTS.has(content_id)
	var active := has_variant and danger >= 18
	return {
		"variant_id": content_id + "_danger18_cards" if active else "",
		"auto_battle": active,
		"reward_mode": "cards_only" if active else "event",
		"normal_text": str(definition.get("rules", definition.get("summary", ""))),
		"danger_text": DANGER_TEXT if has_variant else "",
		"has_danger_variant": has_variant,
	}

static func describe(content_id: String, danger: int) -> Dictionary:
	var definition := AdventureContentCatalog.get_event_definition(content_id)
	var policy := resolve(content_id, danger)
	definition.merge(policy)
	if policy.has_danger_variant:
		definition["rules"] = "%s\n\n%s" % [policy.normal_text, policy.danger_text]
		if policy.auto_battle:
			definition["risk"] = "危险事件战斗"
			definition["reward"] = "仅卡牌奖励"
			definition["options"] = []
	return definition
