extends Node
class_name MusicDirector

const MUSIC_DIR := "res://assets/audio/music/"
const FALLBACK_TRACK := "town"
const DEFAULT_VOLUME_DB := -20.0
const FADE_SECONDS := 1.1

var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _current_track := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.name = "Track%d" % i
		player.volume_db = DEFAULT_VOLUME_DB
		player.finished.connect(_on_track_finished.bind(player))
		add_child(player)
		_players.append(player)

func play_ambience(ambience: String) -> void:
	var wanted := ambience.strip_edges()
	if wanted == "":
		wanted = FALLBACK_TRACK
	if wanted == _current_track and _players[_active].playing:
		return
	var stream := _load_track(wanted)
	if stream == null:
		wanted = FALLBACK_TRACK
		stream = _load_track(wanted)
	if stream == null:
		return
	_current_track = wanted
	var next_index := 1 - _active
	var next := _players[next_index]
	var previous := _players[_active]
	next.stream = stream
	next.volume_db = -60.0
	next.play()
	if is_inside_tree():
		var fade := create_tween()
		fade.set_parallel(true)
		fade.tween_property(next, "volume_db", DEFAULT_VOLUME_DB, FADE_SECONDS)
		fade.tween_property(previous, "volume_db", -60.0, FADE_SECONDS)
		fade.chain().tween_callback(previous.stop)
	_active = next_index

func stop_music() -> void:
	_current_track = ""
	for player in _players:
		player.stop()

func current_track() -> String:
	return _current_track

func _load_track(track: String) -> AudioStream:
	var path := MUSIC_DIR + track + ".wav"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream

func _on_track_finished(player: AudioStreamPlayer) -> void:
	if player == _players[_active] and _current_track != "":
		player.play()
