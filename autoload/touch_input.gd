class_name TouchState
extends Node

## Holds what the on-screen controls are currently doing.
##
## Registered as the `TouchInput` autoload. The overlay writes into it and the
## fighter reads it, which keeps the pad itself free of any knowledge about
## fighters and lets the same pad drive the menus later if needed.
##
## Presses are latched rather than sampled: a tap that starts and ends between
## two physics frames would otherwise be missed entirely, which on a phone is
## most of them.

## -1 for left, +1 for right, 0 for neither.
var move := 0.0

var _latched := {"jump": false, "punch": false, "kick": false}
var _forced := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## True when the on-screen pad should be shown at all.
func active() -> bool:
	return _forced or DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")


## Turns the pad on for a desktop run, so the layout can be checked without a
## phone. Also used by the tests.
func force(enabled: bool) -> void:
	_forced = enabled
	if not enabled:
		release_all()


func press(action: String) -> void:
	if _latched.has(action):
		_latched[action] = true


## Reads a press and clears it, so one tap produces exactly one attack.
func take(action: String) -> bool:
	if not _latched.get(action, false):
		return false
	_latched[action] = false
	return true


func release_all() -> void:
	move = 0.0
	for action in _latched:
		_latched[action] = false
