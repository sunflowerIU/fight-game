extends Node

## One place to ask for a sound.
##
## Effects come from a small pool of players so several hits can overlap, and
## music cross-fades between screens instead of cutting out.

const SFX_FOLDER := "res://audio/sfx/"
const VOICES := 10

var music_volume_db := -9.0
var sfx_volume_db := -3.0

var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _cache: Dictionary = {}
var _music: AudioStreamPlayer
var _music_path := ""
var _fade: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in range(VOICES):
		var voice := AudioStreamPlayer.new()
		voice.name = "Voice %d" % (i + 1)
		voice.bus = "Master"
		add_child(voice)
		_voices.append(voice)
	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	add_child(_music)


## Plays a file from audio/sfx by name, without the extension.
## `pitch_spread` detunes each shot a little so repeated hits do not machine-gun.
func play(sound: String, volume_db := 0.0, pitch_spread := 0.0) -> void:
	var stream := _load(sound)
	if stream == null:
		return
	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	voice.stream = stream
	voice.volume_db = sfx_volume_db + volume_db
	voice.pitch_scale = 1.0 + randf_range(-pitch_spread, pitch_spread)
	voice.play()


func play_music(path: String, fade_in := 1.2) -> void:
	if path == _music_path and _music.playing:
		return
	_music_path = path
	var stream := load(path)
	if stream == null:
		return
	# The tracks are written as loops, so tell the stream to behave like one.
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_music.stream = stream
	_music.volume_db = -40.0
	_music.play()
	_tween_music(music_volume_db, fade_in)


func stop_music(fade_out := 0.5) -> void:
	_music_path = ""
	if not _music.playing:
		return
	_tween_music(-40.0, fade_out)
	await get_tree().create_timer(fade_out).timeout
	_music.stop()


func _tween_music(target_db: float, duration: float) -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade.tween_property(_music, "volume_db", target_db, maxf(duration, 0.01))


func _load(sound: String) -> AudioStream:
	if _cache.has(sound):
		return _cache[sound]
	var path := SFX_FOLDER + sound + ".wav"
	if not ResourceLoader.exists(path):
		push_warning("Missing sound effect: %s" % path)
		_cache[sound] = null
		return null
	var stream: AudioStream = load(path)
	_cache[sound] = stream
	return stream
