extends RefCounted
class_name EnemyIntentCategory

enum Type {
	APPROACH,
	DEFEND,
	ATTACK,
	UTILITY,
	CURSE,
	RETREAT,
	HARVEST,
}

const COUNT := 7


static func get_label(category: int) -> String:
	match category:
		Type.APPROACH: return "接近"
		Type.DEFEND: return "防御"
		Type.ATTACK: return "攻击"
		Type.UTILITY: return "功能"
		Type.CURSE: return "施咒"
		Type.RETREAT: return "逃离"
		Type.HARVEST: return "收割"
		_: return "观望"


static func get_description(category: int) -> String:
	match category:
		Type.APPROACH: return "移动到能够发动攻击的位置。"
		Type.DEFEND: return "使用护甲、治疗或保护类行动。"
		Type.ATTACK: return "使用攻击牌或武器打击。"
		Type.UTILITY: return "使用强化、附魔、畸变或其它功能行动。"
		Type.CURSE: return "使用诅咒或咒害牌。"
		Type.RETREAT: return "远离近战威胁并维持有效射程。"
		Type.HARVEST: return "接近并追杀生命较低的目标。"
		_: return "本阶段没有明确行动。"


static func is_valid(category: int) -> bool:
	return category >= 0 and category < COUNT
