extends Control
class_name CardEncyclopedia

signal back_requested

const DEFAULT_CATALOG := preload("res://resources/card_catalog.tres")

var catalog: CardCatalog
var search_edit: LineEdit
var class_filter: OptionButton
var rarity_filter: OptionButton
var card_list: ItemList
var count_label: Label
var detail_title: Label
var detail_meta: Label
var detail_body: RichTextLabel
var detail_rules: RichTextLabel
var artwork: TextureRect
var orientation_button: Button
var filtered: Array[CardData] = []
var selected_card: CardData
var inverted := false


func _ready() -> void:
	theme = MenuTheme.create_theme()
	if catalog == null:
		catalog = DEFAULT_CATALOG
	var root := VBoxContainer.new()
	MenuTheme.margin(self).add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := MenuTheme.label("卡牌图鉴", 32)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var back := MenuTheme.button("返回主菜单")
	back.pressed.connect(func() -> void: back_requested.emit())
	header.add_child(back)
	var filters := HBoxContainer.new()
	root.add_child(filters)
	search_edit = LineEdit.new()
	search_edit.placeholder_text = "搜索卡名 / 逆位名称"
	search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filters.add_child(search_edit)
	class_filter = OptionButton.new()
	class_filter.add_item("全部职业")
	class_filter.set_item_metadata(0, -1)
	for value in CardEnums.CardClass.values():
		class_filter.add_item(CardEnums.class_label(value))
		class_filter.set_item_metadata(class_filter.item_count - 1, value)
	filters.add_child(class_filter)
	rarity_filter = OptionButton.new()
	rarity_filter.add_item("全部品质")
	rarity_filter.set_item_metadata(0, -1)
	for value in CardCatalog.RARITY_ORDER:
		rarity_filter.add_item(CardEnums.rarity_label(value))
		rarity_filter.set_item_metadata(rarity_filter.item_count - 1, value)
	filters.add_child(rarity_filter)
	count_label = MenuTheme.label("")
	root.add_child(count_label)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(columns)
	card_list = ItemList.new()
	card_list.custom_minimum_size.x = 355
	card_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card_list.add_theme_color_override("font_color", MenuTheme.INK)
	card_list.add_theme_stylebox_override("panel", MenuTheme.box(Color("#d7c8a2"), MenuTheme.MUTED))
	card_list.add_theme_color_override("font_selected_color", Color("#fff2cd"))
	card_list.add_theme_stylebox_override("selected", MenuTheme.box(Color("#4b4637"), MenuTheme.INK))
	card_list.add_theme_stylebox_override("selected_focus", MenuTheme.box(Color("#4b4637"), MenuTheme.ACCENT, 2))
	card_list.fixed_icon_size = Vector2i(40, 48)
	columns.add_child(card_list)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(panel)
	var scroll := ScrollContainer.new()
	panel.add_child(scroll)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(details)
	detail_title = MenuTheme.label("", 29)
	detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(detail_title)
	detail_meta = MenuTheme.label("")
	detail_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(detail_meta)
	orientation_button = MenuTheme.button("查看逆位")
	orientation_button.pressed.connect(func() -> void: show_card(selected_card, not inverted))
	details.add_child(orientation_button)
	artwork = TextureRect.new()
	artwork.custom_minimum_size = Vector2(160, 125)
	artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	artwork.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	details.add_child(artwork)
	detail_body = _text_box()
	details.add_child(detail_body)
	details.add_child(HSeparator.new())
	details.add_child(MenuTheme.label("详细裁定", 20))
	detail_rules = _text_box()
	details.add_child(detail_rules)
	search_edit.text_changed.connect(func(_text: String) -> void: refresh_cards())
	class_filter.item_selected.connect(func(_index: int) -> void: refresh_cards())
	rarity_filter.item_selected.connect(func(_index: int) -> void: refresh_cards())
	card_list.item_selected.connect(func(index: int) -> void: show_card(filtered[index]))
	refresh_cards()
	search_edit.grab_focus()


func refresh_cards() -> void:
	filtered = catalog.query(int(class_filter.get_selected_metadata()), int(rarity_filter.get_selected_metadata()), search_edit.text)
	card_list.clear()
	for card in filtered:
		card_list.add_item("%s  ·  %s\n%s / %d AP" % [card.card_name, card.get_rarity_label(), card.get_class_label(), card.ap_cost], card.artwork)
	count_label.text = "%d 张卡牌 · 基础 → 普通 → 稀有 → 史诗 → 传说" % filtered.size()
	if filtered.is_empty():
		show_card(null)
	else:
		card_list.select(0)
		show_card(filtered[0])


func show_card(card: CardData, show_inverted: bool = false) -> void:
	selected_card = card
	inverted = show_inverted and card != null and card.is_druid_dual_card
	orientation_button.visible = card != null and card.is_druid_dual_card
	if card == null:
		detail_title.text = "没有符合条件的卡牌"
		detail_meta.text = ""
		detail_body.text = "试试其他职业、品质或名称。"
		detail_rules.text = ""
		artwork.texture = null
		return
	var context := {"druid_orientation": CardEnums.DruidOrientation.INVERTED if inverted else CardEnums.DruidOrientation.UPRIGHT}
	detail_title.text = card.get_display_name_for_context(context)
	detail_meta.text = "%s · %s · %d AP" % [card.get_class_label(), card.get_rarity_label(), card.get_ap_cost_for_context(context)]
	orientation_button.text = "查看正位" if inverted else "查看逆位"
	artwork.texture = card.artwork if card.artwork != null else MenuTheme.PAPER
	artwork.tooltip_text = "" if card.artwork != null else "暂无插画"
	detail_body.text = RulesTextFormatter.format_card(card, context)
	detail_rules.text = card.get_resolution_rules_for_context(context)
	if detail_rules.text.strip_edges().is_empty():
		detail_rules.text = "暂无额外裁定。"


func _text_box() -> RichTextLabel:
	var result := RichTextLabel.new()
	result.bbcode_enabled = false
	result.fit_content = true
	result.scroll_active = false
	result.selection_enabled = true
	return result


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		back_requested.emit()
