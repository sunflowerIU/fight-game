extends SceneTree

## Run with: godot --headless --path . --script res://tests/combat_smoke.gd
func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arena: Node3D = load("res://scenes/nepal_arena.tscn").instantiate()
	root.add_child(arena)
	await physics_frame
	var player_one := arena.get_node("Player 1") as FighterController
	var player_two := arena.get_node("Player 2") as FighterController
	if player_one == null or player_two == null:
		push_error("Both fighters must be in the arena.")
		quit(1)
		return

	player_one._start_attack(1)
	var punch_pose_seen := false
	for frame in range(30):
		await physics_frame
		punch_pose_seen = punch_pose_seen or player_one.art.texture == player_one.punch_texture
	if not punch_pose_seen:
		push_error("The punch action must show a distinct punch pose.")
		quit(1)
		return
	if player_two.health != 100:
		push_error("A punch should miss when the fighters are far apart.")
		quit(1)
		return

	player_one.position.x = -0.95
	player_two.position.x = 0.95
	await physics_frame
	player_one._start_attack(1)
	for frame in range(30):
		await physics_frame
	if player_two.health != 90:
		push_error("A punch in range should deal exactly 10 damage.")
		quit(1)
		return

	player_one.position.x = -1.1
	player_two.position.x = 1.1
	await physics_frame
	player_one._start_attack(2)
	var kick_pose_seen := false
	for frame in range(35):
		await physics_frame
		kick_pose_seen = kick_pose_seen or player_one.art.texture == player_one.kick_texture
	if not kick_pose_seen:
		push_error("The kick action must show a distinct kick pose.")
		quit(1)
		return
	if player_two.health != 74:
		push_error("A kick in range should deal exactly 16 damage.")
		quit(1)
		return

	player_two.receive_hit(74, 1.0)
	await process_frame
	if not arena.match_over or not arena.result_label.visible or arena.health_bar_two.value != 0:
		push_error("A knockout should end the match and update the HUD.")
		quit(1)
		return
	print("Combat smoke test passed: miss, punch, kick, health, knockout, HUD.")
	quit(0)
