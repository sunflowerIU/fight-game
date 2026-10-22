extends Node

## Walks the menus the way a player does and checks the choices really reach
## the arena: fighter, opponent type, difficulty, names and avatars.
##
## This one runs as a scene rather than with --script, because the menus talk
## to the MatchConfig and GameAudio autoloads and Godot only sets those up
## when a scene is actually running.
##
## Run with: godot --headless --path . res://tests/menu_smoke.tscn

const SOUNDS := [
	"punch_whoosh", "kick_whoosh", "hit_light", "hit_heavy", "jump", "land",
	"ui_move", "ui_select", "ui_back", "round_start", "ko",
]
const TRACKS := ["res://audio/bgm_menu.ogg", "res://audio/bgm_arena.ogg"]

var failed := false


func _ready() -> void:
	_run.call_deferred()


func _fail(message: String) -> void:
	push_error(message)
	failed = true


func _settle(frames := 3) -> void:
	for i in range(frames):
		await get_tree().process_frame


func _run() -> void:
	await _settle()
	await _check_audio_assets()
	await _check_title_screen()
	await _check_select_screen()
	await _check_arena_receives_choices()
	if failed:
		get_tree().quit(1)
		return
	print("Menu smoke test passed: title, fighter choice, CPU/human, difficulty, names, avatars, audio.")
	get_tree().quit(0)


func _check_audio_assets() -> void:
	for sound in SOUNDS:
		var path := "res://audio/sfx/%s.wav" % sound
		if not ResourceLoader.exists(path):
			_fail("Missing sound effect: %s" % path)
		elif load(path) == null:
			_fail("Sound effect will not load: %s" % path)
	for track in TRACKS:
		if not ResourceLoader.exists(track):
			_fail("Missing music track: %s" % track)
			continue
		var stream := load(track)
		if not (stream is AudioStreamOggVorbis):
			_fail("%s should be an Ogg Vorbis stream." % track)
	GameAudio.play("ui_select", -60.0)
	GameAudio.play_music(TRACKS[0], 0.01)
	await _settle(4)
	if not GameAudio.get_node("Music").playing:
		_fail("Music did not start.")


func _check_title_screen() -> void:
	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	add_child(menu)
	await _settle(4)
	var start := _find_button(menu, "START GAME")
	if start == null:
		_fail("The title screen needs a START GAME button.")
	elif start.disabled:
		_fail("START GAME must be clickable.")
	if _find_button(menu, "QUIT") == null:
		_fail("The title screen needs a QUIT button.")
	menu.queue_free()
	await _settle()


func _check_select_screen() -> void:
	MatchConfig.reset()
	var select: Control = load("res://scenes/character_select.tscn").instantiate()
	add_child(select)
	await _settle(4)

	# Defaults: you are Amit, the CPU takes Janaki, difficulty is medium.
	_expect(MatchConfig.player_one_fighter == "amit", "Player one should default to Amit.")
	_expect(MatchConfig.player_two_fighter == "janaki", "The CPU should default to Janaki.")
	_expect(MatchConfig.opponent_is_cpu(), "The opponent should default to the CPU.")
	_expect(MatchConfig.difficulty == MatchSettings.Difficulty.MEDIUM, "Difficulty should default to medium.")
	_expect(select.opponent_chips["CPU"].button_pressed, "The CPU chip should start selected.")
	_expect(select.difficulty_chips["MEDIUM"].button_pressed, "The medium chip should start selected.")
	_expect(not select.difficulty_chips["HARD"].disabled, "Difficulty should be available against the CPU.")
	_expect(select.player_cards[2]["amit"].disabled, "Player two's cards are decided for them against the CPU.")

	# Picking Janaki hands Amit to the CPU.
	select.player_cards[1]["janaki"].pressed.emit()
	await _settle()
	_expect(MatchConfig.player_one_fighter == "janaki", "Choosing Janaki should set player one.")
	_expect(MatchConfig.player_two_fighter == "amit", "The CPU should take the other fighter.")

	# Switching to a second human opens up their side and closes difficulty.
	select.opponent_chips["HUMAN"].pressed.emit()
	await _settle()
	_expect(not MatchConfig.opponent_is_cpu(), "The opponent should now be human.")
	_expect(select.difficulty_chips["HARD"].disabled, "Difficulty means nothing without a CPU.")
	_expect(not select.player_cards[2]["janaki"].disabled, "A human player two picks their own fighter.")

	# Both players may take the same fighter.
	select.player_cards[2]["janaki"].pressed.emit()
	await _settle()
	_expect(MatchConfig.player_two_fighter == "janaki", "A mirror match should be allowed.")

	# Going back to the CPU hands it the other fighter again.
	select.opponent_chips["CPU"].pressed.emit()
	await _settle()
	_expect(MatchConfig.player_two_fighter == "amit", "The CPU should retake the other fighter.")

	select.difficulty_chips["HARD"].pressed.emit()
	await _settle()
	_expect(MatchConfig.difficulty == MatchSettings.Difficulty.HARD, "Choosing hard should stick.")

	select.queue_free()
	await _settle()


func _check_arena_receives_choices() -> void:
	MatchConfig.reset()
	MatchConfig.choose_player_one("janaki")
	MatchConfig.difficulty = MatchSettings.Difficulty.HARD
	var arena: Node3D = load("res://scenes/nepal_arena.tscn").instantiate()
	add_child(arena)
	await _settle(6)

	var one := arena.get_node("Player 1") as FighterController
	var two := arena.get_node("Player 2") as FighterController
	_expect(one.display_name == "JANAKI", "Player one should be the fighter that was chosen.")
	_expect(two.display_name == "AMIT", "The CPU should hold the other fighter.")
	_expect(one.player_number == 1 and two.player_number == 2, "Player numbers decide which keys each fighter listens to.")
	_expect(one.brain == null, "Player one is the person at the keyboard.")
	_expect(two.brain != null, "Player two should be driven by the CPU.")
	_expect(two.brain.tuning == CpuBrain.SETTINGS[MatchSettings.Difficulty.HARD], "The CPU should use the chosen difficulty.")

	# The plates on the HUD carry the fighter's name and face.
	for fighter in [one, two]:
		var plate := _find_node_named(arena, "%s plate" % fighter.name)
		if plate == null:
			_fail("No HUD plate for %s." % fighter.name)
			continue
		_expect(_find_label(plate, fighter.display_name) != null, "%s's name is missing from the HUD." % fighter.display_name)
		var portrait := _find_texture_rect(plate)
		_expect(portrait != null and portrait.texture != null, "%s's avatar is missing from the HUD." % fighter.display_name)

	arena.queue_free()
	await _settle()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text:
		return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _find_label(node: Node, text: String) -> Label:
	if node is Label and node.text == text:
		return node
	for child in node.get_children():
		var found := _find_label(child, text)
		if found != null:
			return found
	return null


func _find_texture_rect(node: Node) -> TextureRect:
	if node is TextureRect:
		return node
	for child in node.get_children():
		var found := _find_texture_rect(child)
		if found != null:
			return found
	return null


func _find_node_named(node: Node, wanted: String) -> Node:
	if node.name == wanted:
		return node
	for child in node.get_children():
		var found := _find_node_named(child, wanted)
		if found != null:
			return found
	return null
