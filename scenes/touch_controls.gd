class_name TouchControls
extends Control

## The on-screen pad: two direction buttons on the left, jump, punch and kick
## on the right.
##
## Raw touch events are handled here rather than using Button nodes, because
## Godot's buttons run off emulated mouse input and only one finger can be
## down at a time. A fighting game needs to hold a direction and tap an attack
## together, so each finger is tracked by its own index and regions are
## matched by hand. Dragging a finger from one button to another counts as
## releasing the first and pressing the second, the way an arcade stick feels.

signal menu_requested

const LABELS := {
	"left": "◀", "right": "▶", "jump": "JUMP", "punch": "PUNCH", "kick": "KICK",
}
const DIRECTIONS := ["left", "right"]

var regions := {}
var menu_rect := Rect2()
## Which region each finger is currently inside, keyed by touch index.
## The mouse is tracked as index -1 so the layout can be tried on a desktop.
var fingers := {}
var radius := 60.0
## The rect the buttons were last laid out against.
var layout_size := Vector2.ZERO


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# The pad draws itself and reads input straight from the event stream, so
	# it must never swallow clicks meant for anything underneath.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	# A Control only inherits a rect from a Control parent. Inside a
	# CanvasLayer it gets one from the viewport, but fall back to the
	# viewport anyway so the pad is never laid out into nothing.
	var view := size
	if view.x < 2.0 or view.y < 2.0:
		view = get_viewport_rect().size
	if view.x < 2.0 or view.y < 2.0:
		return
	layout_size = view
	# Sized off the screen height so the buttons stay thumb-sized on any
	# phone, and clamped so they never swallow a small window.
	radius = clampf(view.y * 0.082, 34.0, 96.0)
	var margin := maxf(view.y * 0.045, 18.0)
	var r := radius
	var bottom := view.y - margin - r

	regions = {
		"left": Vector2(margin + r, bottom),
		"right": Vector2(margin + r + 2.35 * r, bottom),
		"kick": Vector2(view.x - margin - r, bottom),
		"punch": Vector2(view.x - margin - 3.35 * r, bottom),
		"jump": Vector2(view.x - margin - 2.175 * r, bottom - 2.1 * r),
	}
	# Centred at the top, in the gap the two health bars leave between them.
	# The arena drops its title banner while the pad is up so this can sit
	# there without landing on a fighter's name.
	var menu_size := Vector2(minf(r * 1.6, view.x * 0.085), r * 0.55)
	menu_rect = Rect2(Vector2((view.x - menu_size.x) * 0.5, margin * 0.35), menu_size)
	queue_redraw()


func _region_at(point: Vector2) -> String:
	for name in regions:
		# A touch target slightly wider than the drawn circle: fingers are
		# imprecise and a missed attack reads as the game ignoring you.
		if point.distance_to(regions[name]) <= radius * 1.18:
			return name
	return ""


func _enter(index: int, point: Vector2) -> bool:
	var region := _region_at(point)
	if region == "":
		return false
	fingers[index] = region
	if region in DIRECTIONS:
		_apply_direction()
	else:
		TouchInput.press(region)
	queue_redraw()
	return true


func _move(index: int, point: Vector2) -> void:
	if not fingers.has(index):
		# Sliding onto the pad mid-drag still counts, but a drag that starts
		# off the pad must not fire an attack.
		var region := _region_at(point)
		if region in DIRECTIONS:
			fingers[index] = region
			_apply_direction()
			queue_redraw()
		return
	var region := _region_at(point)
	if region == fingers[index]:
		return
	var was_direction: bool = fingers[index] in DIRECTIONS
	if region == "":
		fingers.erase(index)
	else:
		fingers[index] = region
		if not (region in DIRECTIONS):
			TouchInput.press(region)
	if was_direction or region in DIRECTIONS:
		_apply_direction()
	queue_redraw()


func _exit(index: int) -> void:
	if not fingers.has(index):
		return
	var was_direction: bool = fingers[index] in DIRECTIONS
	fingers.erase(index)
	if was_direction:
		_apply_direction()
	queue_redraw()


## Holding both arrows cancels out, which is what a stick would do.
func _apply_direction() -> void:
	var axis := 0.0
	for index in fingers:
		if fingers[index] == "left":
			axis -= 1.0
		elif fingers[index] == "right":
			axis += 1.0
	TouchInput.move = signf(axis)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if _enter(event.index, event.position):
				get_viewport().set_input_as_handled()
			elif menu_rect.has_point(event.position):
				menu_requested.emit()
				get_viewport().set_input_as_handled()
		else:
			_exit(event.index)
	elif event is InputEventScreenDrag:
		_move(event.index, event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _enter(-1, event.position):
				get_viewport().set_input_as_handled()
			elif menu_rect.has_point(event.position):
				menu_requested.emit()
				get_viewport().set_input_as_handled()
		else:
			_exit(-1)
	elif event is InputEventMouseMotion and fingers.has(-1):
		_move(-1, event.position)


func _notification(what: int) -> void:
	# Losing the window with a finger down would otherwise leave the fighter
	# walking into the wall forever.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		fingers.clear()
		TouchInput.release_all()
		queue_redraw()


func _draw() -> void:
	if regions.is_empty():
		return
	var font := ThemeDB.fallback_font
	var held := {}
	for index in fingers:
		held[fingers[index]] = true

	for name in regions:
		var centre: Vector2 = regions[name]
		var down: bool = held.has(name)
		var accent := Color("d6a75c") if name in DIRECTIONS else Color("e07a52")
		if name == "kick":
			accent = Color("4fb8aa")
		elif name == "jump":
			accent = Color("8ea9c4")
		draw_circle(centre, radius, Color(0.08, 0.08, 0.11, 0.34 if down else 0.22))
		draw_arc(centre, radius, 0.0, TAU, 48, Color(accent, 0.95 if down else 0.6), 3.0, true)
		if down:
			draw_circle(centre, radius * 0.82, Color(accent, 0.26))

		var label: String = LABELS[name]
		var font_size := maxi(int(radius * (0.72 if name in DIRECTIONS else 0.34)), 8)
		var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string_outline(font, centre + Vector2(-width * 0.5, font_size * 0.36), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 5, Color(0.08, 0.07, 0.1, 0.9))
		draw_string(font, centre + Vector2(-width * 0.5, font_size * 0.36), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 0.97, 0.92, 0.95 if down else 0.8))

	draw_rect(menu_rect, Color(0.08, 0.08, 0.11, 0.3), true)
	draw_rect(menu_rect, Color(0.84, 0.78, 0.66, 0.55), false, 2.0)
	var menu_size := maxi(int(menu_rect.size.y * 0.46), 8)
	var menu_width := font.get_string_size("MENU", HORIZONTAL_ALIGNMENT_LEFT, -1, menu_size).x
	draw_string(font, menu_rect.get_center() + Vector2(-menu_width * 0.5, menu_size * 0.36), "MENU",
		HORIZONTAL_ALIGNMENT_LEFT, -1, menu_size, Color(1, 0.97, 0.92, 0.85))
