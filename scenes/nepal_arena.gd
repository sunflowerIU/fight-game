@tool
extends Node3D

## A self-contained fighting stage. Player spawn markers are at x = -3 and +3.
const PANORAMA = preload("res://assets/nepal_himalaya.png")
const FIGHTER_SCENE = preload("res://characters/amit_fighter.tscn")
const FEMALE_FIGHTER_SCENE = preload("res://characters/female_fighter.tscn")

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
var match_over := false


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


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or fighter_one == null or fighter_two == null:
		return
	var separation := absf(fighter_one.global_position.x - fighter_two.global_position.x)
	var center_x := clampf((fighter_one.global_position.x + fighter_two.global_position.x) * 0.5, -2.5, 2.5)
	var distance := maxf(11.5, 5.5 + separation * 0.9)
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
	shape.position = Vector3(0, -0.42, -5.95)
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
		spawn.position = Vector3(float(side) * 3.0, 0.15, 0)
		spawn.rotation.y = -PI / 2.0 if side < 0 else PI / 2.0
		add_child(spawn)
	fighter_one = FIGHTER_SCENE.instantiate() as FighterController
	fighter_one.name = "Player 1"
	fighter_one.position = Vector3(-3.0, 0.15, 0.2)
	add_child(fighter_one)
	fighter_two = FEMALE_FIGHTER_SCENE.instantiate() as FighterController
	fighter_two.name = "Player 2"
	fighter_two.position = Vector3(3.0, 0.15, 0.2)
	add_child(fighter_two)


func _make_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Fight HUD"
	add_child(layer)
	var canvas := Control.new()
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(canvas)

	health_bar_one = _make_health_bar(canvas, Color("c86c4e"), false)
	health_bar_two = _make_health_bar(canvas, Color("3caa9e"), true)
	_make_hud_label(canvas, "PLAYER 1", 0.0, 0.48, 35, 20, HORIZONTAL_ALIGNMENT_LEFT, 20)
	_make_hud_label(canvas, "PLAYER 2", 0.52, 1.0, 20, 20, HORIZONTAL_ALIGNMENT_RIGHT, 20)
	_make_hud_label(canvas, "HIMALAYAN DUEL", 0.37, 0.63, 0, 21, HORIZONTAL_ALIGNMENT_CENTER, 23)
	_make_hud_label(canvas, "P1  A/D move   Space jump   J punch   K kick        P2  ←/→ move   ↑ jump   O punch   P kick", 0.0, 1.0, 0, -48, HORIZONTAL_ALIGNMENT_CENTER, 16, true)

	result_label = Label.new()
	result_label.visible = false
	result_label.anchor_left = 0.25
	result_label.anchor_right = 0.75
	result_label.anchor_top = 0.32
	result_label.anchor_bottom = 0.58
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 48)
	result_label.add_theme_color_override("font_color", Color("fff0cc"))
	result_label.add_theme_color_override("font_outline_color", Color("24212b"))
	result_label.add_theme_constant_override("outline_size", 8)
	canvas.add_child(result_label)


func _make_health_bar(canvas: Control, color: Color, right_side: bool) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = FighterController.MAX_HEALTH
	bar.value = FighterController.MAX_HEALTH
	bar.show_percentage = false
	bar.anchor_left = 0.54 if right_side else 0.0
	bar.anchor_right = 1.0 if right_side else 0.46
	bar.offset_left = 12 if right_side else 35
	bar.offset_right = -35 if right_side else -12
	bar.offset_top = 52
	bar.offset_bottom = 81
	var background := StyleBoxFlat.new()
	background.bg_color = Color("282a34")
	background.border_width_left = 2
	background.border_width_top = 2
	background.border_width_right = 2
	background.border_width_bottom = 2
	background.border_color = Color("e0c796")
	bar.add_theme_stylebox_override("background", background)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
	canvas.add_child(bar)
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
	var winner := 2 if player == 1 else 1
	result_label.text = "PLAYER %d WINS!\nPress R to fight again" % winner
	result_label.visible = true


func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not match_over:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		get_tree().reload_current_scene()
