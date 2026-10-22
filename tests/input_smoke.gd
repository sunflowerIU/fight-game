extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arena: Node3D = load("res://scenes/nepal_arena.tscn").instantiate()
	root.add_child(arena)
	await physics_frame
	var fighter := arena.get_node("Player 1") as FighterController
	var starting_x := fighter.position.x
	var down := InputEventKey.new()
	down.physical_keycode = KEY_D
	down.pressed = true
	Input.parse_input_event(down)
	print("D key state: ", Input.is_physical_key_pressed(KEY_D))
	var step_pose_seen := false
	for frame in range(30):
		await physics_frame
		step_pose_seen = step_pose_seen or fighter.step_art.modulate.a > 0.5
	var up := InputEventKey.new()
	up.physical_keycode = KEY_D
	up.pressed = false
	Input.parse_input_event(up)
	print("Player 1 x: ", starting_x, " -> ", fighter.position.x)
	if fighter.position.x <= starting_x + 0.2:
		push_error("Player 1 did not move when D was pressed.")
		quit(1)
		return
	if not step_pose_seen:
		push_error("Walking must show a stepping pose.")
		quit(1)
		return

	var opponent := arena.get_node("Player 2") as FighterController
	fighter.position.x = 4.0
	opponent.position.x = -3.0
	await physics_frame
	if fighter.facing != -1.0 or opponent.facing != 1.0 or not fighter.art.flip_h:
		push_error("Both fighters must face each other after crossing sides.")
		quit(1)
		return

	var jump_down := InputEventKey.new()
	jump_down.physical_keycode = KEY_SPACE
	jump_down.pressed = true
	Input.parse_input_event(jump_down)
	for frame in range(3):
		await physics_frame
	if fighter.is_on_floor() or fighter.step_art.modulate.a > 0.0:
		push_error("Jumping must leave the floor without showing the walk pose.")
		quit(1)
		return
	var jump_up := InputEventKey.new()
	jump_up.physical_keycode = KEY_SPACE
	jump_up.pressed = false
	Input.parse_input_event(jump_up)
	var landed := false
	for frame in range(70):
		await physics_frame
		if fighter.is_on_floor():
			landed = fighter.landing_time > 0.0
			break
	if not landed:
		push_error("Jumping must return to the floor with a landing pose.")
		quit(1)
		return
	var camera := arena.get_node("Fight Camera") as Camera3D
	fighter.position.x = -7.0
	opponent.position.x = 7.0
	for frame in range(25):
		await process_frame
	if camera.position.z <= 13.0:
		push_error("The fight camera must widen when fighters separate.")
		quit(1)
		return
	print("Input smoke test passed: walk, facing, jump, landing, camera.")
	quit(0)
