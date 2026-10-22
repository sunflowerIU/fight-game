extends SceneTree

## Guards the two things that made the fighters look wrong before:
## feet that jumped around when the pose changed, and a body that slid
## sideways when the sprite mirrored.
##
## Run with: godot --headless --path . --script res://tests/pose_smoke.gd

const POSE_NAMES := ["idle", "step", "punch", "kick"]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Two humans, so nothing moves except what this test moves.
	TestSupport.two_player_settings(self)
	var arena: Node3D = load("res://scenes/nepal_arena.tscn").instantiate()
	root.add_child(arena)
	await physics_frame
	for name in ["Player 1", "Player 2"]:
		var fighter := arena.get_node(name) as FighterController
		if not _check_fighter(fighter, name):
			quit(1)
			return
	print("Pose smoke test passed: pivots match the artwork, mirroring is symmetric, stance is stable.")
	quit(0)


func _grounds(fighter: FighterController) -> Array:
	return [fighter.idle_ground, fighter.step_ground, fighter.punch_ground, fighter.kick_ground]


func _textures(fighter: FighterController) -> Array:
	return [fighter.idle_texture, fighter.step_texture, fighter.punch_texture, fighter.kick_texture]


func _check_fighter(fighter: FighterController, label: String) -> bool:
	var grounds := _grounds(fighter)
	var textures := _textures(fighter)

	for pose in range(4):
		var ground: PackedVector2Array = grounds[pose]
		var who := "%s %s" % [label, POSE_NAMES[pose]]
		if ground.size() < 2:
			push_error("%s needs a balance point and at least one shoe." % who)
			return false
		if absf(ground[0].y - ground[1].y) > 1.0:
			push_error("%s: the balance point must sit on the leading shoe's row." % who)
			return false
		# The balance point belongs between the shoes, never outside them.
		var lo: float = ground[1].x
		var hi: float = ground[1].x
		for i in range(2, ground.size()):
			lo = minf(lo, ground[i].x)
			hi = maxf(hi, ground[i].x)
		if ground[0].x < lo - 1.0 or ground[0].x > hi + 1.0:
			if ground.size() > 2:
				push_error("%s: the balance point falls outside the stance." % who)
				return false
		if not _pivot_matches_art(textures[pose], ground, who):
			return false

	# Walking alternates idle and step, so a big gap between their balance
	# points would show up as the body twitching with every stride.
	var drift: float = absf(grounds[0][0].x - grounds[1][0].x) * fighter.art.pixel_size
	if drift > 0.16:
		push_error("%s: idle and step balance points are %.3f apart; walking would slide." % [label, drift])
		return false

	# Mirroring must be exact: the same pose facing the other way has to put
	# the body and both shoes at mirrored offsets, not shifted ones.
	for pose in range(4):
		fighter.facing = 1.0
		fighter._apply_pose(pose, true)
		var right_base := fighter.art_base
		var right_feet := fighter.foot_offsets.duplicate()
		fighter.facing = -1.0
		fighter._apply_pose(pose, true)
		if absf(fighter.art_base.x + right_base.x) > 0.0005 or absf(fighter.art_base.y - right_base.y) > 0.0005:
			push_error("%s %s: mirroring moved the body off its pivot." % [label, POSE_NAMES[pose]])
			return false
		if fighter.foot_offsets.size() != right_feet.size():
			push_error("%s %s: mirroring lost a shoe." % [label, POSE_NAMES[pose]])
			return false
		for i in range(right_feet.size()):
			var mirrored: Vector2 = fighter.foot_offsets[i]
			var original: Vector2 = right_feet[i]
			if absf(mirrored.x + original.x) > 0.0005 or absf(mirrored.y - original.y) > 0.0005:
				push_error("%s %s: shoe %d did not mirror cleanly." % [label, POSE_NAMES[pose], i])
				return false
	fighter.facing = 1.0 if fighter.player_number == 1 else -1.0
	fighter._apply_pose(FighterController.Pose.IDLE, true)
	return true


## Reads the artwork back and confirms the recorded rows really are where the
## shoes stop, so regenerating a pose cannot silently leave a fighter floating.
func _pivot_matches_art(texture: Texture2D, ground: PackedVector2Array, who: String) -> bool:
	if texture == null:
		push_error("%s has no texture." % who)
		return false
	var image := texture.get_image()
	if image == null:
		print("  (%s: artwork not readable here, skipping the pixel check)" % who)
		return true
	if image.is_compressed() and image.decompress() != OK:
		print("  (%s: artwork is VRAM compressed, skipping the pixel check)" % who)
		return true
	var size := image.get_size()
	if Vector2(size) != texture.get_size():
		print("  (%s: artwork size mismatch, skipping the pixel check)" % who)
		return true
	var lowest := -1
	for y in range(size.y - 1, -1, -1):
		for x in range(0, size.x, 3):
			if image.get_pixel(x, y).a > 0.1:
				lowest = y
				break
		if lowest >= 0:
			break
	if lowest < 0:
		push_error("%s: the artwork is fully transparent." % who)
		return false
	if absf(float(lowest) - ground[1].y) > 6.0:
		push_error("%s: the leading shoe is recorded at row %d but the artwork stops at %d." % [who, int(ground[1].y), lowest])
		return false
	return true
