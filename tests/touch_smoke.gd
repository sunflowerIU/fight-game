extends Node

## Drives the on-screen pad with synthetic touches and checks the fighter
## actually responds: hold a direction, tap an attack, and do both at once
## with two fingers, which is the case emulated mouse input cannot handle.
##
## Run with: godot --headless --path . res://tests/touch_smoke.tscn

var failed := false


func _ready() -> void:
	_run.call_deferred()


func _fail(message: String) -> void:
	push_error(message)
	failed = true


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _settle(frames := 3) -> void:
	for i in range(frames):
		await get_tree().physics_frame


## Events go straight to the pad rather than through Input.parse_input_event:
## headless runs with the dummy display server, which has no viewport to route
## touches through. This still exercises everything the pad itself does —
## region matching, per-finger tracking and latching.
func _touch(pad: TouchControls, index: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	pad._input(event)
	await get_tree().process_frame


func _drag(pad: TouchControls, index: int, position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	pad._input(event)
	await get_tree().process_frame


func _run() -> void:
	TouchInput.force(true)
	_expect(TouchInput.active(), "Forcing touch on should make the pad active.")

	# Same shape as the arena: the pad lives in a CanvasLayer, which is what
	# gives a Control the full viewport to lay itself out in.
	var layer := CanvasLayer.new()
	add_child(layer)
	var pad := TouchControls.new()
	layer.add_child(pad)
	await _settle(2)

	for name in ["left", "right", "jump", "punch", "kick"]:
		_expect(pad.regions.has(name), "The pad is missing its %s button." % name)
	var screen := Rect2(Vector2.ZERO, pad.layout_size)
	_expect(pad.layout_size.x > 1.0, "The pad never laid itself out.")
	for name in pad.regions:
		_expect(screen.has_point(pad.regions[name]), "The %s button sits off screen." % name)

	# Holding right walks right, and letting go stops.
	await _touch(pad, 0, pad.regions["right"], true)
	_expect(TouchInput.move > 0.5, "Holding right should push the stick right.")
	await _touch(pad, 0, pad.regions["right"], false)
	_expect(absf(TouchInput.move) < 0.01, "Letting go should centre the stick.")

	# A tap is read exactly once, however many frames it spans.
	await _touch(pad, 0, pad.regions["punch"], true)
	await _touch(pad, 0, pad.regions["punch"], false)
	_expect(TouchInput.take("punch"), "A tap on punch should register.")
	_expect(not TouchInput.take("punch"), "One tap must not produce two punches.")

	# Two fingers: hold a direction and attack at the same time.
	await _touch(pad, 0, pad.regions["left"], true)
	await _touch(pad, 1, pad.regions["kick"], true)
	_expect(TouchInput.move < -0.5, "The direction should hold while attacking.")
	_expect(TouchInput.take("kick"), "The second finger should land a kick.")
	await _touch(pad, 1, pad.regions["kick"], false)
	_expect(TouchInput.move < -0.5, "Releasing the attack must not drop the direction.")
	# Sliding the thumb from left to right swaps direction, like a stick.
	await _drag(pad, 0, pad.regions["right"])
	_expect(TouchInput.move > 0.5, "Sliding across should swap direction.")
	await _touch(pad, 0, pad.regions["right"], false)
	_expect(absf(TouchInput.move) < 0.01, "Every finger up should centre the stick.")

	# A press that starts away from any button does nothing.
	await _touch(pad, 0, Vector2(800, 450), true)
	_expect(absf(TouchInput.move) < 0.01 and not TouchInput.take("punch"), "The middle of the screen is not a button.")
	await _touch(pad, 0, Vector2(800, 450), false)

	pad.queue_free()
	await _settle(2)

	await _check_fighter_responds()

	TouchInput.force(false)
	if failed:
		get_tree().quit(1)
		return
	print("Touch smoke test passed: layout, hold, tap, two fingers, slide, and the fighter responds.")
	get_tree().quit(0)


## The pad is only useful if the fighter moves, so drive one end to end.
func _check_fighter_responds() -> void:
	MatchConfig.reset()
	var arena: Node3D = load("res://scenes/nepal_arena.tscn").instantiate()
	add_child(arena)
	await _settle(2)
	for frame in range(300):
		if arena.intro_timer <= 0.0:
			break
		await get_tree().physics_frame

	var one := arena.get_node("Player 1") as FighterController
	_expect(arena.get_node_or_null("Touch controls/Pad") != null, "The arena should show the pad on a touchscreen.")

	var start: float = one.position.x
	TouchInput.move = 1.0
	await _settle(30)
	TouchInput.move = 0.0
	_expect(one.position.x > start + 0.3, "Holding right on the pad should walk the fighter right.")

	TouchInput.press("punch")
	await _settle(4)
	_expect(one.attack_time > 0.0, "Tapping punch on the pad should throw a punch.")

	arena.queue_free()
	await _settle(2)
