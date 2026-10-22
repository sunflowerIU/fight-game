@tool
extends Node3D

## A self-contained fighting stage. Which fighters appear, whether player two
## is a person or the computer, and how hard the computer plays all come from
## the MatchConfig autoload that the menus fill in.
const PANORAMA = preload("res://assets/nepal_himalaya.png")
const SELECT_SCENE := "res://scenes/character_select.tscn"
## Used when the arena is opened on its own, with no menu to ask.
const DEFAULT_SCENES := {
	"amit": "res://characters/amit_fighter.tscn",
	"janaki": "res://characters/female_fighter.tscn",
}
## How long the bell rings before the fighters are let loose.
const INTRO_LENGTH := 1.35

var stone := _mat(Color("60615f"), 0.91)
var pale_stone := _mat(Color("797b73"), 0.88)
var dark_stone := _mat(Color("343b42"), 0.85)
var grout := _mat(Color("51585b"), 1.0)
var brass := _mat(Color("bc8b48"), 0.42, 0.42)
var roof_red := _mat(Color("542e30"), 0.72)
var timber := _mat(Color("4b302b"), 0.86)
var flame := _mat(Color("ffbb61"), 0.1, 1.9)
var fighter_one: FighterController
var fighter_two: FighterController
var fight_camera: Camera3D
var health_bar_one: ProgressBar
var health_bar_two: ProgressBar
var result_label: Label
var announce_label: Label
var match_over := false
var intro_timer := 0.0


func _ready() -> void:
	_make_world()
	_make_backdrop()
	_make_stage()
	_make_architecture()
	_make_flags()
	_make_lighting()
	_make_camera_and_markers()
	if not Engine.is_editor_hint():
		fighter_one.opponent = fighter_two
		fighter_two.opponent = fighter_one
		fighter_one.health_changed.connect(_on_health_changed)
		fighter_two.health_changed.connect(_on_health_changed)
		fighter_one.defeated.connect(_on_defeated)
		fighter_two.defeated.connect(_on_defeated)
		_make_hud()
		_make_touch_controls()
		_begin_round()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or fighter_one == null or fighter_two == null:
		return
	_tick_intro(delta)
	var separation := absf(fighter_one.global_position.x - fighter_two.global_position.x)
	var center_x := clampf((fighter_one.global_position.x + fighter_two.global_position.x) * 0.5, -3.4, 3.4)
	# Capped so the camera never backs off far enough to reveal that the
	# terrace is a floating slab, or to shrink the fighters.
	var distance := clampf(5.5 + separation * 0.85, 11.5, 15.5)
	var follow := 1.0 - exp(-5.0 * delta)
	fight_camera.position.x = lerpf(fight_camera.position.x, center_x, follow)
	fight_camera.position.z = lerpf(fight_camera.position.z, distance, follow)
	fight_camera.look_at(Vector3(fight_camera.position.x, 3.35, -0.8), Vector3.UP)


func _mat(color: Color, roughness: float, glow: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = glow
	return material


func _make_world() -> void:
	var world := WorldEnvironment.new()
	world.name = "Warm Himalayan atmosphere"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("7394a1")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b4c4d2")
	env.ambient_light_energy = 0.48
	env.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = env
	add_child(world)


func _make_backdrop() -> void:
	var backdrop := MeshInstance3D.new()
	backdrop.name = "Himalayan panorama"
	var quad := QuadMesh.new()
	quad.size = Vector2(118.0, 66.4)
	backdrop.mesh = quad
	backdrop.position = Vector3(0, -7.0, -31.0)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = PANORAMA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	backdrop.material_override = material
	add_child(backdrop)


func _box(label: String, size: Vector3, pos: Vector3, material: Material, parent: Node3D = null) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	item.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	item.mesh = mesh
	item.position = pos
	item.material_override = material
	if parent == null:
		add_child(item)
	else:
		parent.add_child(item)
	return item


func _cylinder(label: String, top: float, bottom: float, height: float, pos: Vector3, material: Material, sides: int = 24, parent: Node3D = null) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	item.name = label
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = sides
	item.mesh = mesh
	item.position = pos
	item.material_override = material
	if parent == null:
		add_child(item)
	else:
		parent.add_child(item)
	return item


func _make_stage() -> void:
	var body := StaticBody3D.new()
	body.name = "Arena floor collision"
	add_child(body)
	_box("Raised stone platform", Vector3(22.4, 0.75, 20.0), Vector3(0, -0.42, -5.95), dark_stone, body)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(22.4, 0.75, 20.0)
	shape.shape = box_shape
	# The collision top is raised to the top face of the paving slabs rather
	# than the platform block, so a fighter's feet rest on the stone they are
	# drawn standing on instead of sinking a few centimetres into it.
	shape.position = Vector3(0, FighterController.GROUND_Y - 0.375, -5.95)
	body.add_child(shape)

	# Individual slabs break up the floor under grazing light.
	for x in range(-11, 11):
		for z in range(-16, 4):
			var offset := 0.004 if (x + z) % 3 == 0 else 0.0
			_box("Stone paving", Vector3(1.075, 0.055, 0.98), Vector3(x + 0.5, 0.0 + offset, z + 0.5), pale_stone if (x + z) % 4 == 0 else stone)

	# Brass inlay gives the arena a readable center without occupying the fighters' space.
	_cylinder("Central medallion", 1.48, 1.48, 0.018, Vector3(0, 0.047, 0), brass, 64)
	_cylinder("Inset stone disc", 1.30, 1.30, 0.022, Vector3(0, 0.061, 0), dark_stone, 64)
	_cylinder("Inner gold ring", 0.63, 0.63, 0.018, Vector3(0, 0.077, 0), brass, 48)
	_cylinder("Inner stone", 0.52, 0.52, 0.020, Vector3(0, 0.090, 0), stone, 48)
	for i in range(12):
		var angle := TAU * float(i) / 12.0
		var ray := _box("Sunburst inlay", Vector3(0.035, 0.014, 0.45), Vector3(sin(angle) * 0.95, 0.083, cos(angle) * 0.95), brass)
		ray.rotation.y = angle

	for x in [-11.25, 11.25]:
		_box("Side edge trim", Vector3(0.12, 0.14, 20.1), Vector3(x, -0.02, -5.95), brass)
	for z in [-15.98, 4.08]:
		_box("Front and back trim", Vector3(22.5, 0.14, 0.13), Vector3(0, -0.02, z), brass)
	for step in range(3):
		_box("Front entrance step", Vector3(5.8 + step * 0.45, 0.19, 0.55), Vector3(0, -0.63 - step * 0.19, 4.41 + step * 0.50), stone)

	# Low rear parapet leaves the mountains visible.
	for x in [-9.0, -5.0, 5.0, 9.0]:
		_box("Carved parapet", Vector3(2.25, 0.68, 0.55), Vector3(x, 0.30, -15.5), pale_stone)
		_box("Parapet cap", Vector3(2.40, 0.13, 0.72), Vector3(x, 0.70, -15.5), brass)


func _make_architecture() -> void:
	for side in [-1, 1]:
		var x := float(side) * 10.6
		_make_pagoda(x, -7.0, 0.90 if side < 0 else 1.15)
		_make_gate_post(float(side) * 8.15, -3.83)
		_make_brazier(float(side) * 7.35, 2.75)

func _make_pagoda(x: float, z: float, scale_factor: float) -> void:
	var root := Node3D.new()
	root.name = "Tiered Nepalese pagoda"
	root.position = Vector3(x, -0.15, z)
	root.scale = Vector3.ONE * scale_factor
	add_child(root)
	_box("Temple plinth", Vector3(4.4, 0.75, 4.4), Vector3(0, 0.25, 0), dark_stone, root)
	_box("Brick chamber", Vector3(3.1, 2.35, 3.1), Vector3(0, 1.70, 0), timber, root)
	for side in [-1, 1]:
		for depth in [-1, 1]:
			_box("Corner timber", Vector3(0.26, 2.45, 0.26), Vector3(float(side) * 1.38, 1.73, float(depth) * 1.38), brass, root)
	for tier in range(3):
		var y := 3.08 + tier * 1.11
		var width := 4.65 - tier * 0.93
		_cylinder("Sweeping pagoda roof", 0.20, width * 0.70, 0.68, Vector3(0, y, 0), roof_red, 4, root).rotation.y = PI / 4.0
		_box("Roof finial base", Vector3(width * 0.22, 0.42, width * 0.22), Vector3(0, y + 0.52, 0), timber, root)
	_cylinder("Gilded spire", 0.0, 0.24, 1.23, Vector3(0, 6.52, 0), brass, 12, root)


func _make_gate_post(x: float, z: float) -> void:
	_box("Stone pier", Vector3(0.76, 2.30, 0.76), Vector3(x, 1.08, z), dark_stone)
	_box("Pier carving", Vector3(0.89, 0.17, 0.89), Vector3(x, 2.24, z), brass)
	_cylinder("Pier crown", 0.18, 0.62, 0.43, Vector3(x, 2.54, z), roof_red, 4).rotation.y = PI / 4.0
	_cylinder("Pier ornament", 0.0, 0.15, 0.42, Vector3(x, 2.95, z), brass, 12)


func _make_brazier(x: float, z: float) -> void:
	_cylinder("Brazier pedestal", 0.22, 0.35, 0.88, Vector3(x, 0.43, z), dark_stone)
	_cylinder("Brazier bowl", 0.55, 0.28, 0.30, Vector3(x, 1.00, z), brass)
	_cylinder("Firelight", 0.0, 0.20, 0.60, Vector3(x, 1.43, z), flame, 12)
	var light := OmniLight3D.new()
	light.name = "Brazier glow"
	light.position = Vector3(x, 1.55, z)
	light.light_color = Color("ff9a4b")
	light.light_energy = 1.6
	light.omni_range = 5.0
	add_child(light)


func _make_flags() -> void:
	var colors := [Color("436f9a"), Color("e4d6ad"), Color("b95142"), Color("698869"), Color("c7a34c")]
	for side in [-1, 1]:
		var start := Vector3(float(side) * 8.2, 5.6, -5.4)
		var end := Vector3(float(side) * 2.4, 4.35, -7.8)
		var rope := _box("Prayer flag cord", Vector3(start.distance_to(end), 0.025, 0.025), (start + end) * 0.5, grout)
		rope.look_at(end, Vector3.UP)
		rope.rotate_y(PI / 2.0)
		for i in range(14):
			var t := (float(i) + 0.5) / 14.0
			var point := start.lerp(end, t)
			var flag := MeshInstance3D.new()
			flag.name = "Prayer flag"
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			st.add_vertex(Vector3(-0.20, 0, 0))
			st.add_vertex(Vector3(0.20, 0, 0))
			st.add_vertex(Vector3(0.04, -0.63, 0))
			flag.mesh = st.commit()
			var cloth := _mat(colors[i % colors.size()], 0.98)
			cloth.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
			flag.material_override = cloth
			flag.position = point
			add_child(flag)


func _make_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sunset key light"
	sun.rotation_degrees = Vector3(-37, -63, 0)
	sun.light_color = Color("ffcf9b")
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.name = "Cool sky fill"
	fill.rotation_degrees = Vector3(-50, 125, 0)
	fill.light_color = Color("a8c6dc")
	fill.light_energy = 0.38
	add_child(fill)


func _make_camera_and_markers() -> void:
	fight_camera = Camera3D.new()
	fight_camera.name = "Fight Camera"
	fight_camera.position = Vector3(0, 5.1, 11.5)
	add_child(fight_camera)
	fight_camera.look_at(Vector3(0, 3.35, -0.8), Vector3.UP)
	fight_camera.fov = 48.0
	fight_camera.current = true
	fight_camera.far = 100.0
	for side in [-1, 1]:
		var spawn := Marker3D.new()
		spawn.name = "Player1Spawn" if side < 0 else "Player2Spawn"
		spawn.position = Vector3(float(side) * 3.2, FighterController.GROUND_Y, 0)
		spawn.rotation.y = -PI / 2.0 if side < 0 else PI / 2.0
		add_child(spawn)
	# Spawning exactly on the paving avoids an opening-frame drop and landing
	# squash, so the round starts with both fighters already settled.
	fighter_one = _spawn_fighter(1, -3.2)
	fighter_two = _spawn_fighter(2, 3.2)


## Builds one fighter from whatever the menus chose, falling back to the
## default pairing when the arena is opened straight from the editor.
func _spawn_fighter(player: int, x: float) -> FighterController:
	var config := get_node_or_null("/root/MatchConfig")
	var id := "amit" if player == 1 else "janaki"
	if config != null:
		id = config.player_one_fighter if player == 1 else config.player_two_fighter
	var scene: PackedScene = config.fighter_scene(id) if config != null else load(DEFAULT_SCENES[id])
	var fighter := scene.instantiate() as FighterController
	fighter.name = "Player %d" % player
	# Set before the fighter enters the tree, because it decides which keys it
	# listens to and which way it starts facing. This is also what lets both
	# players pick the same character for a mirror match.
	fighter.player_number = player
	fighter.position = Vector3(x, FighterController.GROUND_Y, 0.2)
	if player == 2 and config != null and config.opponent_is_cpu():
		fighter.brain = CpuBrain.new(config.difficulty)
	add_child(fighter)
	return fighter


func _make_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Fight HUD"
	add_child(layer)
	var canvas := Control.new()
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(canvas)

	health_bar_one = _make_fighter_plate(canvas, fighter_one, false, Color("c86c4e"))
	health_bar_two = _make_fighter_plate(canvas, fighter_two, true, Color("3caa9e"))
	if not _touch_active():
		# On a handheld the banner's slot belongs to the pad's menu button.
		_make_hud_label(canvas, "HIMALAYAN DUEL", 0.37, 0.63, 0, 24, HORIZONTAL_ALIGNMENT_CENTER, 22)
		_make_hud_label(canvas, _controls_hint(), 0.0, 1.0, 0, -44, HORIZONTAL_ALIGNMENT_CENTER, 15, true)

	announce_label = Label.new()
	announce_label.visible = false
	announce_label.anchor_left = 0.2
	announce_label.anchor_right = 0.8
	announce_label.anchor_top = 0.24
	announce_label.anchor_bottom = 0.42
	announce_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	announce_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	announce_label.add_theme_font_size_override("font_size", 74)
	announce_label.add_theme_color_override("font_color", Color("ffe4ab"))
	announce_label.add_theme_color_override("font_outline_color", Color("24212b"))
	announce_label.add_theme_constant_override("outline_size", 10)
	canvas.add_child(announce_label)

	result_label = Label.new()
	result_label.visible = false
	result_label.anchor_left = 0.2
	result_label.anchor_right = 0.8
	result_label.anchor_top = 0.32
	result_label.anchor_bottom = 0.60
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 46)
	result_label.add_theme_color_override("font_color", Color("fff0cc"))
	result_label.add_theme_color_override("font_outline_color", Color("24212b"))
	result_label.add_theme_constant_override("outline_size", 8)
	canvas.add_child(result_label)


## Avatar, name and health bar for one fighter, mirrored for player two so
## both plates read outward from the middle of the screen.
func _make_fighter_plate(canvas: Control, fighter: FighterController, right_side: bool, colour: Color) -> ProgressBar:
	var plate := HBoxContainer.new()
	plate.name = "%s plate" % fighter.name
	plate.anchor_left = 0.52 if right_side else 0.0
	plate.anchor_right = 1.0 if right_side else 0.48
	plate.offset_left = 14 if right_side else 24
	plate.offset_right = -24 if right_side else -14
	plate.offset_top = 26
	plate.offset_bottom = 118
	plate.add_theme_constant_override("separation", 12)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(plate)

	var portrait := TextureRect.new()
	portrait.texture = _avatar_for(fighter)
	portrait.custom_minimum_size = Vector2(78, 78)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)

	var caption := HBoxContainer.new()
	caption.add_theme_constant_override("separation", 8)
	caption.alignment = BoxContainer.ALIGNMENT_END if right_side else BoxContainer.ALIGNMENT_BEGIN

	var name_label := Label.new()
	name_label.text = fighter.display_name
	name_label.add_theme_font_size_override("font_size", 27)
	name_label.add_theme_color_override("font_color", Color("fff3db"))
	name_label.add_theme_color_override("font_outline_color", Color("23202b"))
	name_label.add_theme_constant_override("outline_size", 6)

	var badge := Label.new()
	badge.text = _badge_for(fighter)
	badge.add_theme_font_size_override("font_size", 15)
	badge.add_theme_color_override("font_color", colour.lightened(0.35))
	badge.add_theme_color_override("font_outline_color", Color("23202b"))
	badge.add_theme_constant_override("outline_size", 5)
	badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM

	if right_side:
		caption.add_child(badge)
		caption.add_child(name_label)
	else:
		caption.add_child(name_label)
		caption.add_child(badge)
	column.add_child(caption)

	var bar := _make_health_bar(colour)
	column.add_child(bar)

	if right_side:
		plate.add_child(column)
		plate.add_child(portrait)
	else:
		plate.add_child(portrait)
		plate.add_child(column)
	return bar


func _avatar_for(fighter: FighterController) -> Texture2D:
	var config := get_node_or_null("/root/MatchConfig")
	if config != null:
		for id in config.fighter_ids():
			if config.display_name(id) == fighter.display_name:
				return config.avatar(id)
	return null


func _badge_for(fighter: FighterController) -> String:
	if fighter.brain != null:
		var config := get_node_or_null("/root/MatchConfig")
		return "CPU · %s" % (config.difficulty_name() if config != null else "MEDIUM")
	return "P1" if fighter.player_number == 1 else "P2"


func _touch_active() -> bool:
	var touch := get_node_or_null("/root/TouchInput")
	return touch != null and touch.active()


## The on-screen pad goes in its own layer above the HUD, and only when there
## is a touchscreen to use it. Any press still latched from the menus is
## dropped, so the round cannot open with a phantom punch.
func _make_touch_controls() -> void:
	if not _touch_active():
		return
	var touch := get_node_or_null("/root/TouchInput")
	touch.release_all()
	var layer := CanvasLayer.new()
	layer.name = "Touch controls"
	layer.layer = 2
	add_child(layer)
	var pad := TouchControls.new()
	pad.name = "Pad"
	layer.add_child(pad)
	pad.menu_requested.connect(_leave_to_select)


func _leave_to_select() -> void:
	_audio_play("ui_back")
	var touch := get_node_or_null("/root/TouchInput")
	if touch != null:
		touch.release_all()
	get_tree().change_scene_to_file(SELECT_SCENE)


func _controls_hint() -> String:
	var config := get_node_or_null("/root/MatchConfig")
	var left := "P1  A/D move   Space jump   J punch   K kick"
	if config != null and config.opponent_is_cpu():
		return "%s        R rematch   Esc change fighter" % left
	return "%s        P2  ←/→ move   ↑ jump   O punch   P kick        R rematch   Esc menu" % left


func _make_health_bar(colour: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = FighterController.MAX_HEALTH
	bar.value = FighterController.MAX_HEALTH
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 26)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var background := StyleBoxFlat.new()
	background.bg_color = Color("282a34")
	background.set_border_width_all(2)
	background.border_color = Color("e0c796")
	background.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", background)
	var fill := StyleBoxFlat.new()
	fill.bg_color = colour
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


func _make_hud_label(canvas: Control, caption: String, left: float, right: float, margin_x: int, y: int, alignment: HorizontalAlignment, font_size: int, from_bottom: bool = false) -> void:
	var label := Label.new()
	label.text = caption
	label.anchor_left = left
	label.anchor_right = right
	label.anchor_top = 1.0 if from_bottom else 0.0
	label.anchor_bottom = label.anchor_top
	label.offset_left = margin_x
	label.offset_right = -margin_x
	label.offset_top = y
	label.offset_bottom = y + 26
	label.horizontal_alignment = alignment
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("fff3db"))
	label.add_theme_color_override("font_outline_color", Color("28212c"))
	label.add_theme_constant_override("outline_size", 5)
	canvas.add_child(label)


## Holds both fighters still for a beat while the bell rings, so a round does
## not begin with someone already mid-punch.
func _begin_round() -> void:
	intro_timer = INTRO_LENGTH
	fighter_one.match_over = true
	fighter_two.match_over = true
	if announce_label != null:
		announce_label.text = "READY"
		announce_label.visible = true
	_audio_play("round_start", -2.0)
	_music("res://audio/bgm_arena.ogg")


func _tick_intro(delta: float) -> void:
	if intro_timer <= 0.0:
		return
	intro_timer -= delta
	if announce_label != null and intro_timer <= INTRO_LENGTH * 0.45:
		announce_label.text = "FIGHT!"
	if intro_timer > 0.0:
		return
	fighter_one.match_over = false
	fighter_two.match_over = false
	if announce_label != null:
		var fade := create_tween()
		fade.tween_property(announce_label, "modulate:a", 0.0, 0.45)
		fade.tween_callback(func(): announce_label.visible = false)


func _audio_play(sound: String, volume := 0.0) -> void:
	var audio := get_node_or_null("/root/GameAudio")
	if audio != null:
		audio.play(sound, volume)


func _music(path: String) -> void:
	var audio := get_node_or_null("/root/GameAudio")
	if audio != null:
		audio.play_music(path)


func _on_health_changed(player: int, current_health: int) -> void:
	if player == 1:
		health_bar_one.value = current_health
	else:
		health_bar_two.value = current_health


func _on_defeated(player: int) -> void:
	if match_over:
		return
	match_over = true
	fighter_one.match_over = true
	fighter_two.match_over = true
	var winner := fighter_two if player == 1 else fighter_one
	_audio_play("ko")
	result_label.text = "%s WINS!\nR to fight again   ·   Esc to change fighter" % winner.display_name
	result_label.visible = true


## Android's back button arrives as this notification rather than a key.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and not Engine.is_editor_hint():
		_leave_to_select()


func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_ESCAPE:
		_leave_to_select()
	elif event.physical_keycode == KEY_R and match_over:
		_audio_play("ui_select")
		get_tree().reload_current_scene()
