@tool
class_name FighterController
extends CharacterBody3D

## Shared 2.5D fighting controller.
##
## Every pose is drawn from a still photo, so the three things that make a
## sprite fighter feel solid are handled explicitly here:
##   1. Each texture carries its own pivot (the spot on the floor the fighter
##      balances over, and the row where the shoes touch it), so swapping
##      poses never makes the feet jump or the body slide.
##   2. The pivot is mirrored together with the sprite, so turning around
##      leaves the fighter standing exactly where they were.
##   3. Walking is driven by distance travelled rather than by a timer, so
##      the two-frame step cycle stays locked to the ground.
##
## Input arrives as an intent — move, jump, punch, kick — which is filled in
## either from the keyboard or by a CpuBrain. Everything below that point is
## identical for a person and for the computer, so the CPU has no access to
## anything a player does not have.
signal health_changed(player: int, current_health: int)
signal defeated(player: int)

enum Pose { IDLE, STEP, PUNCH, KICK }

const MAX_HEALTH := 100
const PUNCH_DAMAGE := 10
const KICK_DAMAGE := 16
const PUNCH_DURATION := 0.42
const KICK_DURATION := 0.60
## Attacks are split the way a fighting game splits them: a wind-up you can
## read, a short window that actually hits, then a recovery you are stuck in.
const PUNCH_STARTUP := 0.10
const PUNCH_ACTIVE := 0.13
const KICK_STARTUP := 0.16
const KICK_ACTIVE := 0.17
const PUNCH_REACH := 2.35
const KICK_REACH := 2.95
## Height of the arena's paving surface. The body origin rests here, so the
## art pivot sits at local y = 0.
const GROUND_Y := 0.0275
## Distance covered by one full left-right step cycle.
const STRIDE := 1.70
## An attack pressed this long before it is allowed still comes out.
const INPUT_BUFFER := 0.13
## Fighters gently push each other apart below this gap instead of standing
## inside one another. Kept well under punch reach so close play still lands.
const PUSH_DISTANCE := 1.75
## Heights the floor decals sit at, stacked so they never fight each other.
const POOL_HEIGHT := GROUND_Y + 0.012
const FOOT_HEIGHT := GROUND_Y + 0.020
const DUST_HEIGHT := GROUND_Y + 0.030

@export_group("Movement")
## Walking into the opponent is quicker than backing away, as in most fighters.
@export var walk_forward_speed := 5.4
@export var walk_back_speed := 4.1
@export var jump_speed := 11.2
@export var gravity := 33.0
## Jump arcs are committed at take-off, so this is the horizontal speed kept
## when you leap out of a walk.
@export var jump_drift := 4.2
@export var arena_half_width := 6.8
@export_range(1, 2) var player_number := 1

@export_group("Identity")
## Shown on the health bar and in the victory message.
@export var display_name := "FIGHTER"

@export_group("Art")
## True when the artwork is drawn facing screen-right before any mirroring.
@export var art_faces_right := true
@export var step_texture: Texture2D
@export var punch_texture: Texture2D
@export var kick_texture: Texture2D
## Where each pose meets the floor, measured off the artwork in texture
## pixels. Every entry is a list of points:
##   [0] the spot the fighter balances over, which is pinned to the body
##   [1] where the leading shoe stands
##   [2] where the trailing shoe stands, left out when only one foot is down
## Pinning point [0] is what keeps the feet from sliding when the pose
## changes or the fighter turns around; points [1] and [2] get a shadow each.
@export var idle_ground: PackedVector2Array = []
@export var step_ground: PackedVector2Array = []
@export var punch_ground: PackedVector2Array = []
@export var kick_ground: PackedVector2Array = []
## Width of the fighter's stance, used to size the contact shadow.
@export var stance_width := 2.0

@onready var art: Sprite3D = $ArtPivot/FighterArt
@onready var art_pivot: Node3D = $ArtPivot
@onready var idle_texture: Texture2D = art.texture

var opponent: FighterController
var health := MAX_HEALTH
var match_over := false
var facing := 1.0
## Set by the arena when this fighter is the computer's. Leave it null and the
## keyboard drives the fighter instead.
var brain: CpuBrain
var audio: Node
var touch: Node

var shadow: MeshInstance3D
var lead_shadow: MeshInstance3D
var trail_shadow: MeshInstance3D
var dust: MeshInstance3D

var attack_time := 0.0
var attack_kind := 0
var attack_cooldown := 0.0
var attack_has_hit := false
var attack_buffer := 0.0
var buffered_kind := 0
var hit_stun := 0.0
var hit_flash := 0.0
var knockback_speed := 0.0
var previous_punch := false
var previous_kick := false
var previous_jump := false
var idle_clock := 0.0
var walk_distance := 0.0
var takeoff_time := 0.0
var landing_time := 0.0
var dust_time := 0.0
var current_pose := -1
var current_flip := false
var art_base := Vector3.ZERO
## Each planted shoe relative to the balance point, in world units: x across
## the stage, y how far up the frame the artwork drew it.
var foot_offsets: Array[Vector2] = []


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	facing = 1.0 if player_number == 1 else -1.0
	audio = get_node_or_null("/root/GameAudio")
	touch = get_node_or_null("/root/TouchInput")
	_build_ground_contact()
	_setup_sprite()
	_apply_pose(Pose.IDLE, true)


func _setup_sprite() -> void:
	# An opaque pre-pass keeps the soft photo edges while still writing depth,
	# which is what lets the fighter cast a real silhouette on the floor.
	art.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	art.alpha_scissor_threshold = 0.5
	art.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	art.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	idle_clock += delta
	takeoff_time = maxf(takeoff_time - delta, 0.0)
	landing_time = maxf(landing_time - delta, 0.0)
	dust_time = maxf(dust_time - delta, 0.0)
	attack_time = maxf(attack_time - delta, 0.0)
	attack_cooldown = maxf(attack_cooldown - delta, 0.0)
	attack_buffer = maxf(attack_buffer - delta, 0.0)
	hit_stun = maxf(hit_stun - delta, 0.0)
	hit_flash = maxf(hit_flash - delta, 0.0)

	var was_on_floor := is_on_floor()
	var grounded := was_on_floor
	var busy := match_over or hit_stun > 0.0
	var attacking := attack_time > 0.0

	var intent := _gather_intent(delta)
	var horizontal: float = intent["move"]

	# --- Walking -----------------------------------------------------------
	# Speed depends on whether you are closing in or giving ground, which is
	# what makes the spacing game readable.
	if busy:
		velocity.x = knockback_speed
		knockback_speed = move_toward(knockback_speed, 0.0, 13.0 * delta)
	elif grounded:
		var target := 0.0
		if attacking:
			# Attacks root you in place, apart from a short lunge on the
			# active frames so the blow carries weight.
			target = facing * _attack_lunge()
		elif absf(horizontal) > 0.01:
			var toward := horizontal * facing
			target = horizontal * (walk_forward_speed if toward > 0.0 else walk_back_speed)
		velocity.x = move_toward(velocity.x, target, (90.0 if absf(target) < 0.01 else 70.0) * delta)
	# In the air the arc stays as it was launched: no steering mid-jump.

	velocity.z = 0.0
	velocity.y -= gravity * delta

	# --- Jumping -----------------------------------------------------------
	if not busy and not attacking and intent["jump"] and grounded:
		velocity.y = jump_speed
		velocity.x = horizontal * jump_drift
		takeoff_time = 0.10
		_sound("jump", -4.0, 0.06)

	# --- Attacks -----------------------------------------------------------
	if intent["punch"]:
		buffered_kind = 1
		attack_buffer = INPUT_BUFFER
	elif intent["kick"]:
		buffered_kind = 2
		attack_buffer = INPUT_BUFFER
	if attack_buffer > 0.0 and not busy and attack_cooldown <= 0.0:
		_start_attack(buffered_kind)
		attack_buffer = 0.0

	if attack_time > 0.0 and not attack_has_hit:
		var startup := PUNCH_STARTUP if attack_kind == 1 else KICK_STARTUP
		var duration := PUNCH_DURATION if attack_kind == 1 else KICK_DURATION
		if duration - attack_time >= startup:
			_try_attack_hit()

	move_and_slide()
	_separate_from_opponent(delta)
	position.x = clampf(position.x, -arena_half_width, arena_half_width)
	position.z = 0.2

	if not was_on_floor and is_on_floor():
		landing_time = 0.18
		dust_time = 0.26
		_sound("land", -6.0, 0.07)
	# Turning around is a grounded, neutral action: a fighter never spins
	# mid-swing or mid-jump.
	if is_on_floor() and attack_time <= 0.0 and hit_stun <= 0.0 and not match_over:
		_update_facing()

	if is_on_floor() and not match_over and hit_stun <= 0.0 and attack_time <= 0.0:
		walk_distance += absf(velocity.x) * delta
	_update_visuals(delta)


## Fills in what the fighter is trying to do this frame. A person's keys and
## the CPU's decisions both come out the other side as the same four values.
func _gather_intent(delta: float) -> Dictionary:
	if brain != null:
		return brain.decide(self, opponent, delta)

	var right_key := KEY_D if player_number == 1 else KEY_RIGHT
	var left_key := KEY_A if player_number == 1 else KEY_LEFT
	var jump_key := KEY_SPACE if player_number == 1 else KEY_UP
	var punch_key := KEY_J if player_number == 1 else KEY_O
	var kick_key := KEY_K if player_number == 1 else KEY_P

	var jump_held := Input.is_physical_key_pressed(jump_key) or (player_number == 1 and Input.is_physical_key_pressed(KEY_W))
	var punch_held := Input.is_physical_key_pressed(punch_key)
	var kick_held := Input.is_physical_key_pressed(kick_key)
	var intent := {
		"move": float(Input.is_physical_key_pressed(right_key)) - float(Input.is_physical_key_pressed(left_key)),
		"jump": jump_held and not previous_jump,
		"punch": punch_held and not previous_punch,
		"kick": kick_held and not previous_kick,
	}
	previous_jump = jump_held
	previous_punch = punch_held
	previous_kick = kick_held

	# The on-screen pad drives player one as a second set of keys. Its taps
	# are read exactly once here, which is also why only player one asks:
	# a second reader would swallow the press.
	if player_number == 1 and touch != null and touch.active():
		if absf(intent["move"]) < 0.01:
			intent["move"] = touch.move
		intent["jump"] = intent["jump"] or touch.take("jump")
		intent["punch"] = intent["punch"] or touch.take("punch")
		intent["kick"] = intent["kick"] or touch.take("kick")
	return intent


func _sound(sound: String, volume := 0.0, spread := 0.0) -> void:
	if audio != null:
		audio.play(sound, volume, spread)


func _attack_lunge() -> float:
	var startup := PUNCH_STARTUP if attack_kind == 1 else KICK_STARTUP
	var active := PUNCH_ACTIVE if attack_kind == 1 else KICK_ACTIVE
	var duration := PUNCH_DURATION if attack_kind == 1 else KICK_DURATION
	var elapsed := duration - attack_time
	if elapsed < startup or elapsed > startup + active:
		return 0.0
	return 1.5 if attack_kind == 1 else 2.1


func _separate_from_opponent(delta: float) -> void:
	if opponent == null or opponent.health <= 0 or health <= 0:
		return
	var gap := opponent.global_position.x - global_position.x
	if absf(gap) >= PUSH_DISTANCE or absf(gap) < 0.001:
		return
	var push := (PUSH_DISTANCE - absf(gap)) * signf(gap) * 3.0 * delta
	position.x -= push


func _start_attack(kind: int) -> void:
	attack_kind = kind
	attack_time = PUNCH_DURATION if kind == 1 else KICK_DURATION
	attack_cooldown = attack_time + 0.06
	attack_has_hit = false
	_update_facing()
	_sound("punch_whoosh" if kind == 1 else "kick_whoosh", -5.0, 0.08)


func _try_attack_hit() -> void:
	attack_has_hit = true
	if opponent == null or opponent.health <= 0:
		return
	var distance_x := opponent.global_position.x - global_position.x
	var reach := PUNCH_REACH if attack_kind == 1 else KICK_REACH
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
	_sound("hit_light" if damage == PUNCH_DAMAGE else "hit_heavy", 0.0, 0.07)
	health_changed.emit(player_number, health)
	if health == 0:
		defeated.emit(player_number)


func _update_facing() -> void:
	if opponent == null:
		return
	var distance_x := opponent.global_position.x - global_position.x
	if absf(distance_x) > 0.001:
		facing = signf(distance_x)


## Snaps a pose onto the sprite and places its pivot on the floor. Mirroring
## negates the horizontal pivot offset, because flipping a sprite mirrors the
## texture inside the quad while the quad itself stays put.
func _apply_pose(pose: int, force: bool = false) -> void:
	var flip := (facing > 0.0) != art_faces_right
	if not force and pose == current_pose and flip == current_flip:
		return
	current_pose = pose
	current_flip = flip
	var texture: Texture2D = idle_texture
	var ground := idle_ground
	match pose:
		Pose.STEP:
			if step_texture != null:
				texture = step_texture
				ground = step_ground
		Pose.PUNCH:
			if punch_texture != null:
				texture = punch_texture
				ground = punch_ground
		Pose.KICK:
			if kick_texture != null:
				texture = kick_texture
				ground = kick_ground
	art.texture = texture
	art.flip_h = flip
	var size := texture.get_size()
	var pixel := art.pixel_size
	var pivot := size * 0.5 if ground.is_empty() else ground[0]
	var dx := (pivot.x - size.x * 0.5) * pixel
	art_base = Vector3(dx if flip else -dx, (pivot.y - size.y * 0.5) * pixel, 0.0)
	foot_offsets.clear()
	for i in range(1, ground.size()):
		var side := (ground[i].x - pivot.x) * pixel
		foot_offsets.append(Vector2(-side if flip else side, (pivot.y - ground[i].y) * pixel))


func _choose_pose() -> int:
	if health == 0:
		return Pose.IDLE
	if attack_time > 0.0:
		var startup := PUNCH_STARTUP if attack_kind == 1 else KICK_STARTUP
		var duration := PUNCH_DURATION if attack_kind == 1 else KICK_DURATION
		# The wind-up keeps the guard pose, so the strike itself reads as a
		# distinct, sudden frame rather than a slow fade.
		if duration - attack_time < startup * 0.55:
			return Pose.STEP
		return Pose.PUNCH if attack_kind == 1 else Pose.KICK
	if not is_on_floor():
		return Pose.STEP
	if hit_stun > 0.0:
		return Pose.IDLE
	if absf(velocity.x) > 0.35:
		# Locked to distance travelled, so the step never slides on the floor.
		return Pose.STEP if int(walk_distance / (STRIDE * 0.5)) % 2 == 1 else Pose.IDLE
	return Pose.IDLE


func _update_visuals(_delta: float) -> void:
	_apply_pose(_choose_pose())

	var offset := Vector3.ZERO
	var lean := 0.0
	var squash := Vector3.ONE
	var walking := is_on_floor() and absf(velocity.x) > 0.35 and hit_stun <= 0.0 and attack_time <= 0.0 and not match_over

	if attack_time > 0.0:
		var duration := PUNCH_DURATION if attack_kind == 1 else KICK_DURATION
		var progress := 1.0 - attack_time / duration
		var pulse := sin(progress * PI)
		offset.x = facing * pulse * (0.10 if attack_kind == 1 else 0.16)
		lean = -facing * pulse * (0.022 if attack_kind == 1 else 0.040)
		squash = Vector3(1.0 + pulse * 0.02, 1.0 - pulse * 0.012, 1.0)
	elif not is_on_floor():
		var ascent := clampf(velocity.y / jump_speed, 0.0, 1.0)
		var descent := clampf(-velocity.y / jump_speed, 0.0, 1.0)
		lean = facing * (0.030 * descent - 0.045 * ascent)
		squash = Vector3(1.0 - 0.05 * ascent + 0.03 * descent, 1.0 + 0.06 * ascent - 0.035 * descent, 1.0)
		if takeoff_time > 0.0:
			var launch := takeoff_time / 0.10
			squash.x += 0.05 * launch
			squash.y -= 0.06 * launch
	elif hit_stun > 0.0:
		lean = facing * 0.13
		offset.x = -facing * 0.10 * (hit_stun / 0.34)
	elif landing_time > 0.0:
		var landing := landing_time / 0.18
		squash = Vector3(1.0 + 0.10 * landing, 1.0 - 0.11 * landing, 1.0)
	elif walking:
		var cycle := walk_distance / STRIDE * TAU
		offset.y = absf(sin(cycle)) * 0.055
		lean = -facing * 0.020 * sin(cycle)
	else:
		offset.y = sin(idle_clock * 3.4) * 0.020

	if health == 0:
		lean = -facing * 0.34
		offset.y = -0.06

	art_pivot.position = Vector3(offset.x, offset.y, 0.0)
	art_pivot.rotation.z = lean
	art_pivot.scale = squash
	art.position = art_base
	art.modulate = Color(1.0, 0.45, 0.45) if hit_flash > 0.0 else Color(1.0, 0.975, 0.945)
	if health == 0:
		art.modulate = Color(0.68, 0.66, 0.68)

	_update_ground_contact()


# --- Ground contact ---------------------------------------------------------
# A wide soft pool of ambient occlusion under the body, plus a tighter, darker
# disc under each shoe. Together with the silhouette the sprite now casts into
# the sunlight, they read as weight on the stone rather than a cut-out hanging
# in front of it.
func _build_ground_contact() -> void:
	shadow = _make_decal("Body shadow", Vector2(stance_width * 1.55, stance_width * 0.78), Color(0.06, 0.07, 0.11, 0.34), POOL_HEIGHT, 0.52)
	lead_shadow = _make_decal("Leading shoe shadow", Vector2(stance_width * 0.52, stance_width * 0.26), Color(0.03, 0.03, 0.06, 0.50), FOOT_HEIGHT, 0.34)
	trail_shadow = _make_decal("Trailing shoe shadow", Vector2(stance_width * 0.48, stance_width * 0.24), Color(0.03, 0.03, 0.06, 0.44), FOOT_HEIGHT, 0.36)
	dust = _make_decal("Landing dust", Vector2(1.0, 1.0), Color(0.86, 0.80, 0.68, 0.0), DUST_HEIGHT, 0.70)
	dust.visible = false


func _make_decal(label: String, size: Vector2, color: Color, height: float, softness: float) -> MeshInstance3D:
	var decal := MeshInstance3D.new()
	decal.name = label
	var plane := PlaneMesh.new()
	plane.size = size
	decal.mesh = plane
	decal.position = Vector3(0.0, height, 0.0)
	decal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, clampf(1.0 - softness, 0.05, 0.95), 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
	var ramp := GradientTexture2D.new()
	ramp.gradient = gradient
	ramp.fill = GradientTexture2D.FILL_RADIAL
	ramp.fill_from = Vector2(0.5, 0.5)
	ramp.fill_to = Vector2(1.0, 0.5)
	ramp.width = 128
	ramp.height = 128

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.albedo_texture = ramp
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	decal.material_override = material
	add_child(decal)
	return decal


func _update_ground_contact() -> void:
	if shadow == null:
		return
	# Shadows live in world space on the floor, directly under the fighter's
	# balance point, and shrink and fade as the fighter climbs away from it.
	var foot_x := global_position.x + art_pivot.position.x
	var height := maxf(global_position.y - GROUND_Y, 0.0)
	# The pool stays readable in the air: it is what tells a player where a
	# jump is going to come down.
	var lift := minf(height * 0.09, 0.34)
	shadow.global_position = Vector3(foot_x, POOL_HEIGHT, global_position.z)
	shadow.scale = Vector3(1.0 - lift * 0.55, 1.0, 1.0 - lift * 0.55)
	var fade := 1.0 - minf(height * 0.11, 0.45)
	if health == 0:
		fade *= 0.65
	_set_decal_alpha(shadow, 0.34 * fade)
	var grounded := is_on_floor() and health > 0
	_place_foot_shadow(lead_shadow, 0 if grounded else -1, foot_x, lift, 0.50 * fade)
	_place_foot_shadow(trail_shadow, 1 if grounded else -1, foot_x, lift, 0.44 * fade)

	if dust_time > 0.0:
		var t := 1.0 - dust_time / 0.26
		dust.visible = true
		dust.global_position = Vector3(foot_x, DUST_HEIGHT, global_position.z)
		dust.scale = Vector3(0.9 + t * 2.4, 1.0, 0.45 + t * 1.1)
		_set_decal_alpha(dust, (1.0 - t) * 0.40)
	elif dust.visible:
		dust.visible = false


## Drops a shadow under one planted shoe. The artwork draws the trailing shoe
## higher up the frame because it stands further into the stage, so a disc
## laid flat beside the fighter would miss it entirely. Casting the eye ray
## through the drawn shoe and landing the disc where that ray meets the floor
## puts it under the shoe on screen, whatever the fight camera is doing.
func _place_foot_shadow(decal: MeshInstance3D, index: int, foot_x: float, lift: float, alpha: float) -> void:
	if decal == null:
		return
	var camera := get_viewport().get_camera_3d()
	if index < 0 or index >= foot_offsets.size() or camera == null:
		decal.visible = false
		return
	var offset: Vector2 = foot_offsets[index]
	var eye := camera.global_position
	var drop := eye.y - GROUND_Y - offset.y
	if drop <= 0.5:
		decal.visible = false
		return
	var reach := (eye.y - GROUND_Y) / drop
	var depth := (eye.z - global_position.z) * (reach - 1.0)
	if depth < 0.0 or depth > 9.0:
		decal.visible = false
		return
	decal.visible = true
	decal.global_position = Vector3(
		eye.x + (foot_x + offset.x - eye.x) * reach,
		FOOT_HEIGHT + 0.002 * float(index),
		global_position.z - depth)
	# Grow the disc by the same factor, so the extra distance does not make
	# the trailing shoe's shadow read as smaller than the leading one's.
	decal.scale = Vector3(reach * (1.0 - lift), 1.0, reach * (1.0 - lift))
	_set_decal_alpha(decal, alpha * (1.0 - lift * 0.8))


func _set_decal_alpha(decal: MeshInstance3D, alpha: float) -> void:
	var material := decal.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color.a = alpha
