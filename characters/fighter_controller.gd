@tool
class_name FighterController
extends CharacterBody3D

## Shared beginner-friendly combat controller for both 2.5D characters.
signal health_changed(player: int, current_health: int)
signal defeated(player: int)

@export var move_speed := 4.0
@export var jump_speed := 7.2
@export_range(1, 2) var player_number := 1
@export var art_faces_right := true
@export var step_texture: Texture2D
@export var punch_texture: Texture2D
@export var kick_texture: Texture2D

const MAX_HEALTH := 100
const PUNCH_DAMAGE := 10
const KICK_DAMAGE := 16
const PUNCH_DURATION := 0.42
const KICK_DURATION := 0.60

@onready var art: Sprite3D = $FighterArt
@onready var idle_texture: Texture2D = art.texture

var step_art: Sprite3D
var shadow: MeshInstance3D

var opponent: FighterController
var health := MAX_HEALTH
var match_over := false
var facing := 1.0
var attack_time := 0.0
var attack_kind := 0
var attack_cooldown := 0.0
var attack_has_hit := false
var hit_stun := 0.0
var hit_flash := 0.0
var knockback_speed := 0.0
var previous_punch := false
var previous_kick := false
var previous_jump := false
var idle_clock := 0.0
var walk_clock := 0.0
var walk_blend := 0.0
var takeoff_time := 0.0
var landing_time := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	facing = 1.0 if player_number == 1 else -1.0
	_make_shadow()
	step_art = Sprite3D.new()
	step_art.name = "Walking pose"
	step_art.pixel_size = art.pixel_size
	step_art.texture = step_texture
	step_art.modulate.a = 0.0
	add_child(step_art)
	_update_facing()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	idle_clock += delta
	takeoff_time = maxf(takeoff_time - delta, 0.0)
	landing_time = maxf(landing_time - delta, 0.0)
	var was_on_floor := is_on_floor()
	attack_time = maxf(attack_time - delta, 0.0)
	attack_cooldown = maxf(attack_cooldown - delta, 0.0)
	hit_stun = maxf(hit_stun - delta, 0.0)
	hit_flash = maxf(hit_flash - delta, 0.0)

	var right_key := KEY_D if player_number == 1 else KEY_RIGHT
	var left_key := KEY_A if player_number == 1 else KEY_LEFT
	var jump_key := KEY_SPACE if player_number == 1 else KEY_UP
	var punch_key := KEY_J if player_number == 1 else KEY_O
	var kick_key := KEY_K if player_number == 1 else KEY_P
	var horizontal := float(Input.is_physical_key_pressed(right_key)) - float(Input.is_physical_key_pressed(left_key))
	if not match_over and hit_stun <= 0.0:
		velocity.x = move_toward(velocity.x, horizontal * move_speed, 15.0 * delta)
	else:
		velocity.x = knockback_speed
		knockback_speed = move_toward(knockback_speed, 0.0, 13.0 * delta)
	velocity.z = 0.0
	velocity.y -= 16.0 * delta

	var jump_pressed := Input.is_physical_key_pressed(jump_key) or (player_number == 1 and Input.is_physical_key_pressed(KEY_W))
	if not match_over and hit_stun <= 0.0 and jump_pressed and not previous_jump and is_on_floor():
		velocity.y = jump_speed
		takeoff_time = 0.12
	previous_jump = jump_pressed

	var punch_pressed := Input.is_physical_key_pressed(punch_key)
	var kick_pressed := Input.is_physical_key_pressed(kick_key)
	if not match_over and hit_stun <= 0.0 and attack_cooldown <= 0.0:
		if punch_pressed and not previous_punch:
			_start_attack(1)
		elif kick_pressed and not previous_kick:
			_start_attack(2)
	previous_punch = punch_pressed
	previous_kick = kick_pressed

	if attack_time > 0.0 and not attack_has_hit:
		var duration := PUNCH_DURATION if attack_kind == 1 else KICK_DURATION
		if attack_time <= duration * 0.55:
			_update_facing()
			_try_attack_hit()

	move_and_slide()
	position.x = clampf(position.x, -7.0, 7.0)
	position.z = 0.2

	if not was_on_floor and is_on_floor():
		landing_time = 0.16
	_update_facing()
	var walking := is_on_floor() and absf(velocity.x) > 0.3 and hit_stun <= 0.0 and not match_over
	walk_blend = move_toward(walk_blend, 1.0 if walking else 0.0, delta * 8.0)
	if walking:
		walk_clock += delta * (absf(velocity.x) / move_speed) * 2.0 * PI / 0.52
	_update_visuals()


func _start_attack(kind: int) -> void:
	attack_kind = kind
	attack_time = PUNCH_DURATION if kind == 1 else KICK_DURATION
	attack_cooldown = attack_time + 0.08
	attack_has_hit = false


func _try_attack_hit() -> void:
	attack_has_hit = true
	if opponent == null or opponent.health <= 0:
		return
	var distance_x := opponent.global_position.x - global_position.x
	var reach := 2.35 if attack_kind == 1 else 2.95
	if distance_x * facing <= 0.0 or absf(distance_x) > reach:
		return
	if absf(opponent.global_position.y - global_position.y) > 1.35:
		return
	var damage := PUNCH_DAMAGE if attack_kind == 1 else KICK_DAMAGE
	opponent.receive_hit(damage, facing)


func receive_hit(damage: int, direction: float) -> void:
	if health <= 0 or match_over:
		return
	health = maxi(health - damage, 0)
	attack_time = 0.0
	attack_cooldown = maxf(attack_cooldown, 0.25)
	hit_stun = 0.22 if damage == PUNCH_DAMAGE else 0.34
	hit_flash = 0.16
	knockback_speed = direction * (2.4 if damage == PUNCH_DAMAGE else 4.0)
	health_changed.emit(player_number, health)
	if health == 0:
		defeated.emit(player_number)


func _update_facing() -> void:
	if opponent == null:
		return
	var distance_x := opponent.global_position.x - global_position.x
	if absf(distance_x) > 0.001:
		facing = signf(distance_x)


func _update_visuals() -> void:
	art.flip_h = (facing > 0.0) != art_faces_right
	step_art.flip_h = art.flip_h
	art.position = Vector3(0.0, 2.46, 0.0)
	art.rotation.z = 0.0
	art.scale = Vector3.ONE
	art.modulate = Color(1.0, 0.48, 0.48) if hit_flash > 0.0 else Color.WHITE
	art.texture = idle_texture
	var step_alpha := 0.0
	if shadow != null:
		var height := maxf(global_position.y - 0.15, 0.0)
		shadow.global_position = Vector3(global_position.x, 0.025, global_position.z)
		shadow.scale = Vector3.ONE * (1.0 - minf(height * 0.12, 0.35))
		shadow.transparency = minf(height * 0.13, 0.55)
	if attack_time > 0.0:
		var duration := PUNCH_DURATION if attack_kind == 1 else KICK_DURATION
		var progress := 1.0 - attack_time / duration
		var pulse := sin(progress * PI)
		if progress >= 0.12 and progress <= 0.86:
			art.texture = punch_texture if attack_kind == 1 else kick_texture
		art.position.x += facing * pulse * (0.12 if attack_kind == 1 else 0.18)
		art.rotation.z = -facing * pulse * (0.025 if attack_kind == 1 else 0.045)
		art.scale = Vector3(1.0 + pulse * 0.025, 1.0 - pulse * 0.015, 1.0)
	elif not is_on_floor():
		var ascent := clampf(velocity.y / jump_speed, 0.0, 1.0)
		var descent := clampf(-velocity.y / jump_speed, 0.0, 1.0)
		art.position.y += 0.05 + 0.06 * ascent
		art.rotation.z = facing * (0.025 * descent - 0.035 * ascent)
		art.scale = Vector3(1.0 - 0.035 * ascent + 0.02 * descent, 1.0 + 0.035 * ascent - 0.025 * descent, 1.0)
		if takeoff_time > 0.0:
			var launch := takeoff_time / 0.12
			art.scale.x += 0.035 * launch
			art.scale.y -= 0.04 * launch
	elif hit_stun > 0.0:
		art.rotation.z = facing * 0.10
	elif landing_time > 0.0:
		var landing := landing_time / 0.16
		art.scale = Vector3(1.0 + 0.06 * landing, 1.0 - 0.07 * landing, 1.0)
		art.position.y -= 0.10 * landing
	else:
		var stride := sin(walk_clock)
		var step_phase := smoothstep(0.42, 0.58, stride * 0.5 + 0.5)
		step_alpha = walk_blend * step_phase
		art.position.y += sin(idle_clock * 3.4) * 0.018 * (1.0 - walk_blend)
		art.position.y += walk_blend * 0.035 * (1.0 - cos(walk_clock * 2.0)) * 0.5
		art.rotation.z = -facing * walk_blend * 0.018 * stride
	if health == 0:
		step_alpha = 0.0
		art.rotation.z = -facing * 0.32
		art.modulate = Color(0.65, 0.65, 0.65)
	step_art.position = art.position + Vector3(0.0, 0.0, 0.01)
	step_art.rotation = art.rotation
	step_art.scale = art.scale
	step_art.modulate = art.modulate
	step_art.modulate.a = step_alpha
	art.modulate.a = 1.0 - step_alpha


func _make_shadow() -> void:
	shadow = MeshInstance3D.new()
	shadow.name = "Contact shadow"
	var disc := CylinderMesh.new()
	disc.top_radius = 0.58
	disc.bottom_radius = 0.58
	disc.height = 0.012
	disc.radial_segments = 32
	shadow.mesh = disc
	shadow.position = Vector3(0, 0.025, 0)
	var ink := StandardMaterial3D.new()
	ink.albedo_color = Color(0.08, 0.08, 0.10, 0.37)
	ink.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow.material_override = ink
	add_child(shadow)
