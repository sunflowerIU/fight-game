extends SceneTree

## Checks that the CPU actually fights, that it fights harder as the
## difficulty goes up, and that it never wanders out of the arena.
##
## Each difficulty is put in front of a dummy that does nothing, and we count
## the damage it manages to deal in a fixed stretch of simulated time. The
## dummy is healed every time it is hit so the round never ends early.
##
## Run with: godot --headless --path . --script res://tests/cpu_smoke.gd

const SECONDS := 22.0
const TRIALS := 3


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var config := TestSupport.settings(self)
	var scores := {}
	for level in [MatchSettings.Difficulty.EASY, MatchSettings.Difficulty.MEDIUM, MatchSettings.Difficulty.HARD]:
		var total := 0.0
		var attacks := 0
		for trial in range(TRIALS):
			var result := await _measure(config, level)
			if result.is_empty():
				quit(1)
				return
			total += result["damage"]
			attacks += result["attacks"]
		scores[level] = total / TRIALS
		print("  %-6s  average damage %5.1f   attacks thrown %d" % [
			MatchSettings.DIFFICULTY_NAMES[level], scores[level], attacks])
		if attacks == 0:
			push_error("%s CPU never attacked." % MatchSettings.DIFFICULTY_NAMES[level])
			quit(1)
			return

	var easy: float = scores[MatchSettings.Difficulty.EASY]
	var medium: float = scores[MatchSettings.Difficulty.MEDIUM]
	var hard: float = scores[MatchSettings.Difficulty.HARD]
	if not (hard > medium and medium > easy):
		push_error("Difficulty must raise the pressure: easy %.1f, medium %.1f, hard %.1f" % [easy, medium, hard])
		quit(1)
		return
	if hard < easy * 1.5:
		push_error("Hard (%.1f) is barely tougher than easy (%.1f)." % [hard, easy])
		quit(1)
		return
	print("CPU smoke test passed: every level fights, harder levels hit harder, nobody left the arena.")
	quit(0)


func _measure(config: MatchSettings, level: int) -> Dictionary:
	config.opponent = MatchSettings.Opponent.CPU
	config.difficulty = level
	config.choose_player_one("amit")

	var arena: Node3D = load("res://scenes/nepal_arena.tscn").instantiate()
	root.add_child(arena)
	await physics_frame
	var dummy := arena.get_node("Player 1") as FighterController
	var cpu := arena.get_node("Player 2") as FighterController
	if cpu.brain == null:
		push_error("Player two should be driven by a CpuBrain.")
		arena.queue_free()
		return {}

	await TestSupport.await_round_start(self, arena)

	var damage := 0.0
	var attacks := 0
	var was_attacking := false
	var frames := int(SECONDS * Engine.physics_ticks_per_second)
	for frame in range(frames):
		await physics_frame
		if dummy.health < FighterController.MAX_HEALTH:
			damage += FighterController.MAX_HEALTH - dummy.health
			dummy.health = FighterController.MAX_HEALTH
		var attacking := cpu.attack_time > 0.0
		if attacking and not was_attacking:
			attacks += 1
		was_attacking = attacking
		if absf(cpu.position.x) > cpu.arena_half_width + 0.05:
			push_error("The CPU walked out of the arena at x = %.2f." % cpu.position.x)
			arena.queue_free()
			return {}

	arena.queue_free()
	await physics_frame
	return {"damage": damage, "attacks": attacks}
