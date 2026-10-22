class_name TestSupport
extends RefCounted

## Shared helpers for the headless smoke tests.
##
## Running a test with `--script` replaces the main loop. In that mode Godot
## still adds the autoload nodes under /root, but it does not register their
## global names, so `MatchConfig` will not compile and the node has to be
## reached by path. `settings()` below does that, and creates the node if it
## is missing, so a test works either way.
##
## Sound is deliberately left alone: the fighters look up the audio node and
## stay quiet when it is absent, so tests run silently and fast.

const INTRO_PATIENCE := 300


## The live MatchSettings, reset to its defaults.
static func settings(tree: SceneTree) -> MatchSettings:
	var existing := tree.root.get_node_or_null("MatchConfig") as MatchSettings
	if existing != null:
		existing.reset()
		return existing
	var config := MatchSettings.new()
	config.name = "MatchConfig"
	tree.root.add_child(config)
	return config


## Settings for a fight with no AI in it. Tests that drive the fighters
## themselves need this: left on the default, player two is a CPU and will
## walk around on its own, which makes anything measured about positions or
## damage flap from run to run.
static func two_player_settings(tree: SceneTree) -> MatchSettings:
	var config := settings(tree)
	config.opponent = MatchSettings.Opponent.HUMAN
	return config


## The round opens with the bell and a short hold, so wait for the fighters to
## actually be let loose before testing anything about the fight.
static func await_round_start(tree: SceneTree, arena: Node) -> bool:
	for frame in range(INTRO_PATIENCE):
		if arena.intro_timer <= 0.0:
			return true
		await tree.physics_frame
	push_error("The round never started.")
	return false
