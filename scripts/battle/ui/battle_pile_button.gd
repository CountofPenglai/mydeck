extends TextureButton
class_name BattlePileButton

@onready var pile_label: Label = $PileLabel


func set_pile(label: String, count: int, accent: Color) -> void:
	pile_label.text = "%s\n%d" % [label, maxi(0, count)]
	pile_label.add_theme_color_override("font_color", accent)
	tooltip_text = "%s：%d 张" % [label, maxi(0, count)]
