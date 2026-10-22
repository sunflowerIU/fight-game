class_name CpuBrain
extends RefCounted

## Drives a fighter the way a person would: look at the opponent, decide on a
## short plan, commit to it for a moment, then look again.
##
## Difficulty changes three things that matter more than raw speed:
##   * how long it takes to notice a change (reaction)
##   * how often it does nothing useful (dithering)
##   * whether it punishes the recovery frames after your attack misses
##
## Nothing here cheats. It reads the same public state a player can see and
## presses the same four inputs.

enum Plan { WAIT, APPROACH, RETREAT, PUNCH, KICK, HOP }

const SETTINGS := {
	MatchSettings.Difficulty.EASY: {
		"reaction": 0.36,
		"think": 0.44,
		"dither": 0.42,
		"range_slop": 1.5,   # swings from far too far out, and whiffs
		"punish": 0.05,
		"retreat": 0.08,
		"hop": 0.03,
		"pace": 0.62,
		"kick_bias": 0.35,
	},
	MatchSettings.Difficulty.MEDIUM: {
		"reaction": 0.18,
		"think": 0.24,
		"dither": 0.18,
		"range_slop": 1.08,
		"punish": 0.38,
		"retreat": 0.26,
		"hop": 0.07,
		"pace": 0.88,
		"kick_bias": 0.5,
	},
	MatchSettings.Difficulty.HARD: {
		"reaction": 0.07,
		"think": 0.13,
		"dither": 0.04,
		"range_slop": 0.94,  # waits until the blow will actually land
		"punish": 0.82,
		"retreat": 0.42,
		"hop": 0.11,
		"pace": 1.0,
		"kick_bias": 0.62,
	},
}

var tuning: Dictionary
var plan: int = Plan.WAIT
var plan_timer := 0.0
var sense_timer := 0.0
var seen := {}
var rng := RandomNumberGenerator.new()


func _init(difficulty: int = MatchSettings.Difficulty.MEDIUM) -> void:
	tuning = SETTINGS.get(difficulty, SETTINGS[MatchSettings.Difficulty.MEDIUM])
	rng.randomize()


## Returns the buttons the CPU is "pressing" this frame.
func decide(me: FighterController, foe: FighterController, delta: float) -> Dictionary:
	var intent := {"move": 0.0, "jump": false, "punch": false, "kick": false}
	if foe == null or me.match_over or me.health <= 0:
		return intent

	sense_timer -= delta
	if sense_timer <= 0.0 or seen.is_empty():
		_look(me, foe)
		sense_timer = tuning["reaction"]

	plan_timer -= delta
	if plan_timer <= 0.0:
		_choose(me)
		plan_timer = tuning["think"]

	return _act(me, intent)


## The CPU's picture of the fight, refreshed only every `reaction` seconds.
## An easy opponent is therefore working from stale information, which is what
## makes it feel slow rather than simply weak.
func _look(me: FighterController, foe: FighterController) -> void:
	seen = {
		"gap": absf(foe.global_position.x - me.global_position.x),
		"foe_attacking": foe.attack_time > 0.0,
		"foe_airborne": not foe.is_on_floor(),
		"foe_recovering": foe.attack_cooldown > 0.0 and foe.attack_time <= 0.0,
		"stunned": me.hit_stun > 0.0,
		"cornered": absf(me.global_position.x) > me.arena_half_width - 1.2,
	}


func _choose(me: FighterController) -> void:
	if seen["stunned"]:
		plan = Plan.WAIT
		return

	var kick_range: float = me.KICK_REACH * tuning["range_slop"]
	var punch_range: float = me.PUNCH_REACH * tuning["range_slop"]
	var gap: float = seen["gap"]

	# Caught your attack ending? That is the opening, and better opponents
	# take it far more often.
	if seen["foe_recovering"] and gap <= kick_range and rng.randf() < tuning["punish"]:
		plan = Plan.KICK if gap > punch_range else Plan.PUNCH
		return

	# Do not walk into a swing that is already on its way.
	if seen["foe_attacking"] and gap <= kick_range:
		if rng.randf() < tuning["retreat"]:
			plan = Plan.RETREAT
			return
		plan = Plan.PUNCH if gap <= punch_range and rng.randf() < tuning["punish"] else Plan.WAIT
		return

	if seen["foe_airborne"] and gap <= kick_range and rng.randf() < tuning["punish"] * 0.6:
		plan = Plan.WAIT  # let them land, then deal with it
		return

	if rng.randf() < tuning["dither"]:
		plan = Plan.WAIT if rng.randf() < 0.6 else Plan.RETREAT
		return

	if gap <= punch_range:
		plan = Plan.KICK if rng.randf() < tuning["kick_bias"] * 0.5 else Plan.PUNCH
	elif gap <= kick_range:
		plan = Plan.KICK if rng.randf() < tuning["kick_bias"] else Plan.APPROACH
	elif rng.randf() < tuning["hop"]:
		plan = Plan.HOP
	else:
		plan = Plan.APPROACH

	# Backing into the wall is how a CPU gets cornered and stays there.
	if plan == Plan.RETREAT and seen["cornered"]:
		plan = Plan.APPROACH


func _act(me: FighterController, intent: Dictionary) -> Dictionary:
	match plan:
		Plan.APPROACH:
			intent["move"] = me.facing * tuning["pace"]
		Plan.RETREAT:
			intent["move"] = -me.facing * tuning["pace"]
			if seen.get("cornered", false):
				intent["move"] = 0.0
		Plan.HOP:
			intent["move"] = me.facing * tuning["pace"]
			intent["jump"] = _once()
		Plan.PUNCH:
			intent["punch"] = _once()
		Plan.KICK:
			intent["kick"] = _once()
	return intent


## Attacks and jumps are presses, not holds: fire on the first frame of the
## plan and then stop, so the fighter's own cooldown logic stays in charge.
func _once() -> bool:
	if plan_timer >= tuning["think"] - 0.0001:
		return true
	return false
