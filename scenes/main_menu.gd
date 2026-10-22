extends Control

## Title screen. Start Game leads to the character select.

const SELECT_SCENE := "res://scenes/character_select.tscn"

var start_button: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	UiKit.backdrop(self, 0.52)

	var column := VBoxContainer.new()
	column.name = "Menu"
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 14)
	add_child(column)

	column.add_child(UiKit.label("HIMALAYAN", 64, UiKit.PARCHMENT, 9))
	column.add_child(UiKit.label("DUEL", 92, UiKit.BRASS, 9))
	column.add_child(UiKit.label("A rooftop fight above the mountains", 22, Color("d8d2c4"), 5))
	column.add_child(UiKit.spacer(38))

	var buttons := VBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)

	start_button = _menu_button(buttons, "START GAME", 34)
	start_button.pressed.connect(_on_start)
	var quit_button := _menu_button(buttons, "QUIT", 24)
	quit_button.pressed.connect(_on_quit)

	column.add_child(UiKit.spacer(26))
	var hint := "Tap to choose" if TouchInput.active() else "Arrow keys or mouse to choose   ·   Enter to confirm"
	column.add_child(UiKit.label(hint, 17, Color("b9b3a6"), 4))

	GameAudio.play_music("res://audio/bgm_menu.ogg")
	start_button.call_deferred("grab_focus")


func _menu_button(parent: Control, text: String, size: int) -> Button:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(row)
	var button := UiKit.button(text, size)
	button.custom_minimum_size = Vector2(340, 0)
	button.focus_entered.connect(func(): GameAudio.play("ui_move", -6.0))
	row.add_child(button)
	return button


func _on_start() -> void:
	GameAudio.play("ui_select")
	get_tree().change_scene_to_file(SELECT_SCENE)


func _on_quit() -> void:
	GameAudio.play("ui_back")
	get_tree().quit()


## Android's back button on the title screen leaves the game.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		get_tree().quit()
