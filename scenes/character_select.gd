extends Control

## Pick a fighter, pick who you are fighting, pick how hard they fight back.
##
## The opponent starts as a CPU holding the other fighter, so choosing a
## character is the only step needed before pressing FIGHT.

const ARENA_SCENE := "res://scenes/nepal_arena.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"

var player_cards := {1: {}, 2: {}}
var opponent_chips := {}
var difficulty_chips := {}
var player_two_heading: Label
var difficulty_heading: Label
var blurb_labels := {}
var fight_button: Button
var ready_to_listen := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	UiKit.backdrop(self, 0.62)

	var column := VBoxContainer.new()
	column.name = "Select"
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_top = 26
	column.offset_bottom = -22
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)
	add_child(column)

	column.add_child(UiKit.label("CHOOSE YOUR FIGHTER", 44, UiKit.PARCHMENT, 7))
	column.add_child(UiKit.spacer(6))

	var roster := HBoxContainer.new()
	roster.alignment = BoxContainer.ALIGNMENT_CENTER
	roster.add_theme_constant_override("separation", 54)
	column.add_child(roster)
	roster.add_child(_build_side(1, "PLAYER 1"))
	roster.add_child(_build_side(2, "PLAYER 2"))

	column.add_child(UiKit.spacer(14))
	column.add_child(_build_option_row("OPPONENT", ["CPU", "HUMAN"], opponent_chips, _on_opponent_chosen))
	difficulty_heading = UiKit.label("DIFFICULTY", 20, Color("cfc8b8"), 4)
	column.add_child(_build_option_row("DIFFICULTY", ["EASY", "MEDIUM", "HARD"], difficulty_chips, _on_difficulty_chosen, difficulty_heading))

	column.add_child(UiKit.spacer(16))
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 18)
	column.add_child(actions)
	fight_button = UiKit.button("FIGHT!", 32)
	fight_button.custom_minimum_size = Vector2(240, 0)
	fight_button.pressed.connect(_on_fight)
	actions.add_child(fight_button)
	var back := UiKit.button("BACK", 22)
	back.custom_minimum_size = Vector2(160, 0)
	back.pressed.connect(_on_back)
	actions.add_child(back)

	GameAudio.play_music("res://audio/bgm_menu.ogg")
	# One pad cannot drive two fighters, so a handheld plays against the CPU.
	if TouchInput.active():
		MatchConfig.opponent = MatchSettings.Opponent.CPU
		MatchConfig.player_two_fighter = MatchConfig.other_fighter(MatchConfig.player_one_fighter)
		opponent_chips["HUMAN"].disabled = true
		opponent_chips["HUMAN"].tooltip_text = "Two players need two keyboards"
	_refresh()
	ready_to_listen = true
	fight_button.call_deferred("grab_focus")


func _build_side(player: int, heading: String) -> Control:
	var side := VBoxContainer.new()
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_theme_constant_override("separation", 6)

	var title := UiKit.label(heading, 24, UiKit.BRASS, 5)
	side.add_child(title)
	if player == 2:
		player_two_heading = title

	var cards := HBoxContainer.new()
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("separation", 12)
	side.add_child(cards)

	var group := ButtonGroup.new()
	for id in MatchConfig.fighter_ids():
		var card := _build_card(id, group)
		card.pressed.connect(_on_card_pressed.bind(player, id))
		cards.add_child(card)
		player_cards[player][id] = card

	var blurb := UiKit.label("", 16, Color("c7c0b2"), 4)
	blurb.custom_minimum_size = Vector2(430, 44)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(blurb)
	blurb_labels[player] = blurb
	return side


func _build_card(id: String, group: ButtonGroup) -> Button:
	var info := MatchConfig.info(id)
	var card := UiKit.button(info["name"], 22, info["colour"])
	card.toggle_mode = true
	card.button_group = group
	card.icon = MatchConfig.avatar(id)
	card.expand_icon = true
	card.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	card.custom_minimum_size = Vector2(205, 232)
	# The chosen card keeps the light lettering, so the name stays readable
	# once the card fills with the fighter's colour.
	card.add_theme_color_override("font_pressed_color", UiKit.PARCHMENT)
	card.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	card.add_theme_stylebox_override("pressed", UiKit.box(Color(info["colour"], 0.62), UiKit.PARCHMENT, 3))
	card.add_theme_stylebox_override("hover_pressed", UiKit.box(Color(info["colour"], 0.74), UiKit.PARCHMENT, 3))
	card.focus_entered.connect(func(): GameAudio.play("ui_move", -8.0))
	return card


func _build_option_row(heading: String, options: Array, store: Dictionary, handler: Callable, title: Label = null) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	var caption := title if title != null else UiKit.label(heading, 20, Color("cfc8b8"), 4)
	caption.custom_minimum_size = Vector2(160, 0)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(caption)

	var group := ButtonGroup.new()
	for option in options:
		var chip := UiKit.chip(option, UiKit.BRASS)
		chip.button_group = group
		chip.pressed.connect(handler.bind(option))
		chip.focus_entered.connect(func(): GameAudio.play("ui_move", -8.0))
		row.add_child(chip)
		store[option] = chip
	return row


func _on_card_pressed(player: int, id: String) -> void:
	if not ready_to_listen:
		return
	GameAudio.play("ui_select", -4.0)
	if player == 1:
		MatchConfig.choose_player_one(id)
	else:
		MatchConfig.player_two_fighter = id
	_refresh()


func _on_opponent_chosen(option: String) -> void:
	if not ready_to_listen:
		return
	GameAudio.play("ui_select", -4.0)
	MatchConfig.opponent = MatchSettings.Opponent.HUMAN if option == "HUMAN" else MatchSettings.Opponent.CPU
	if MatchConfig.opponent == MatchSettings.Opponent.CPU:
		MatchConfig.player_two_fighter = MatchConfig.other_fighter(MatchConfig.player_one_fighter)
	_refresh()


func _on_difficulty_chosen(option: String) -> void:
	if not ready_to_listen:
		return
	GameAudio.play("ui_select", -4.0)
	for level in MatchSettings.DIFFICULTY_NAMES:
		if MatchSettings.DIFFICULTY_NAMES[level] == option:
			MatchConfig.difficulty = level
	_refresh()


## Pushes the stored choices back onto every control, so the screen always
## shows exactly what the fight is about to use.
func _refresh() -> void:
	var cpu := MatchConfig.opponent_is_cpu()
	for player in [1, 2]:
		var chosen: String = MatchConfig.player_one_fighter if player == 1 else MatchConfig.player_two_fighter
		for id in player_cards[player]:
			var card: Button = player_cards[player][id]
			card.set_pressed_no_signal(id == chosen)
			# In CPU mode player two's fighter is decided for them, so the
			# cards show the choice without inviting a click.
			card.disabled = player == 2 and cpu
			card.modulate = Color(1, 1, 1, 0.55) if (card.disabled and id != chosen) else Color.WHITE
		blurb_labels[player].text = MatchConfig.info(chosen)["blurb"]

	player_two_heading.text = "PLAYER 2  ·  CPU" if cpu else "PLAYER 2  ·  HUMAN"
	opponent_chips["CPU"].set_pressed_no_signal(cpu)
	opponent_chips["HUMAN"].set_pressed_no_signal(not cpu)

	for option in difficulty_chips:
		var chip: Button = difficulty_chips[option]
		chip.set_pressed_no_signal(option == MatchConfig.difficulty_name())
		chip.disabled = not cpu
	difficulty_heading.modulate = Color.WHITE if cpu else Color(1, 1, 1, 0.45)


func _on_fight() -> void:
	GameAudio.play("ui_select")
	get_tree().change_scene_to_file(ARENA_SCENE)


func _on_back() -> void:
	GameAudio.play("ui_back")
	get_tree().change_scene_to_file(MENU_SCENE)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		_on_back()
