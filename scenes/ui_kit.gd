class_name UiKit
extends RefCounted

## Shared styling for the menus, so the title screen and the select screen
## read as one game rather than two different prototypes.

const INK := Color("23202b")
const PARCHMENT := Color("fff3db")
const BRASS := Color("d6a75c")
const SLATE := Color("2b2a35")


static func box(fill: Color, border: Color, width := 2, radius := 6) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style


static func label(text: String, size: int, colour := PARCHMENT, outline := 5) -> Label:
	var item := Label.new()
	item.text = text
	item.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item.add_theme_font_size_override("font_size", size)
	item.add_theme_color_override("font_color", colour)
	if outline > 0:
		item.add_theme_color_override("font_outline_color", INK)
		item.add_theme_constant_override("outline_size", outline)
	return item


static func button(text: String, size := 26, accent := BRASS) -> Button:
	var item := Button.new()
	item.text = text
	item.focus_mode = Control.FOCUS_ALL
	item.add_theme_font_size_override("font_size", size)
	item.add_theme_color_override("font_color", PARCHMENT)
	item.add_theme_color_override("font_hover_color", Color.WHITE)
	item.add_theme_color_override("font_focus_color", Color.WHITE)
	item.add_theme_color_override("font_pressed_color", INK)
	item.add_theme_color_override("font_disabled_color", Color(0.62, 0.60, 0.58))
	item.add_theme_color_override("font_outline_color", INK)
	item.add_theme_constant_override("outline_size", 4)
	item.add_theme_stylebox_override("normal", box(Color(0.16, 0.15, 0.19, 0.86), accent.darkened(0.3)))
	item.add_theme_stylebox_override("hover", box(Color(0.26, 0.22, 0.20, 0.94), accent))
	item.add_theme_stylebox_override("focus", box(Color(0.26, 0.22, 0.20, 0.0), accent.lightened(0.2), 3))
	item.add_theme_stylebox_override("pressed", box(accent, accent.lightened(0.3)))
	item.add_theme_stylebox_override("disabled", box(Color(0.14, 0.14, 0.16, 0.7), Color(0.32, 0.31, 0.33)))
	return item


## A pill used for the toggles: opponent type and difficulty.
static func chip(text: String, accent: Color) -> Button:
	var item := button(text, 20, accent)
	item.toggle_mode = true
	item.custom_minimum_size = Vector2(132, 44)
	item.add_theme_stylebox_override("pressed", box(accent, PARCHMENT, 2))
	item.add_theme_stylebox_override("hover_pressed", box(accent.lightened(0.12), PARCHMENT, 2))
	return item


## The Himalayan plate behind every menu, dimmed so text stays readable.
static func backdrop(parent: Control, dim := 0.55) -> void:
	var image := TextureRect.new()
	image.name = "Backdrop"
	image.texture = load("res://assets/nepal_himalaya.png")
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.set_anchors_preset(Control.PRESET_FULL_RECT)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(image)

	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = Color(0.07, 0.06, 0.10, dim)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(scrim)


static func spacer(height: int) -> Control:
	var item := Control.new()
	item.custom_minimum_size = Vector2(0, height)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return item
