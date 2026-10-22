class_name MatchSettings
extends Node

## Carries the choices made on the menus into the arena.
##
## Registered as the `MatchConfig` autoload, so the choices survive the scene
## change between the character select screen and the fight. The class name is
## how other scripts reach the enums and the roster table at parse time:
## use `MatchSettings.Difficulty.HARD` for the constants and `MatchConfig` for
## the live values.

enum Opponent { CPU, HUMAN }
enum Difficulty { EASY, MEDIUM, HARD }

const FIGHTERS := {
	"amit": {
		"name": "AMIT",
		"scene": "res://characters/amit_fighter.tscn",
		"avatar": "res://assets/ui/avatar_amit.png",
		"colour": Color("c86c4e"),
		"blurb": "Street boxer out of Thamel. Quick hands, stubborn guard.",
	},
	"janaki": {
		"name": "JANAKI",
		"scene": "res://characters/female_fighter.tscn",
		"avatar": "res://assets/ui/avatar_janaki.png",
		"colour": Color("3caa9e"),
		"blurb": "Trained on the temple steps. Long legs, longer patience.",
	},
}

const DIFFICULTY_NAMES := {
	Difficulty.EASY: "EASY",
	Difficulty.MEDIUM: "MEDIUM",
	Difficulty.HARD: "HARD",
}

var player_one_fighter := "amit"
var player_two_fighter := "janaki"
## The opponent is a CPU unless the player asks for a second human.
var opponent: Opponent = Opponent.CPU
var difficulty: Difficulty = Difficulty.MEDIUM


func fighter_ids() -> Array:
	return FIGHTERS.keys()


func other_fighter(id: String) -> String:
	for candidate in FIGHTERS:
		if candidate != id:
			return candidate
	return id


func info(id: String) -> Dictionary:
	return FIGHTERS.get(id, FIGHTERS["amit"])


func display_name(id: String) -> String:
	return info(id)["name"]


func avatar(id: String) -> Texture2D:
	return load(info(id)["avatar"]) as Texture2D


func fighter_scene(id: String) -> PackedScene:
	return load(info(id)["scene"]) as PackedScene


func difficulty_name() -> String:
	return DIFFICULTY_NAMES[difficulty]


func opponent_is_cpu() -> bool:
	return opponent == Opponent.CPU


## Choosing your fighter hands the other one to the opponent, which is what
## makes "pick a character, then fight the CPU" work with no extra steps.
func choose_player_one(id: String) -> void:
	player_one_fighter = id
	if opponent == Opponent.CPU:
		player_two_fighter = other_fighter(id)


func reset() -> void:
	player_one_fighter = "amit"
	player_two_fighter = "janaki"
	opponent = Opponent.CPU
	difficulty = Difficulty.MEDIUM
