extends Node

# Reproductor de efectos. Vive como nodo en main.tscn (Sfx). Genera los sonidos
# con sfx_synth.gd y los reproduce con un grupo pequeno de AudioStreamPlayer por
# el bus SFX, que controla SETTINGS.
#
# Los del CRT y el menu se generan al iniciar (rapido, se usan enseguida). Los
# de la sala (reverb larga) se generan en un hilo para no alargar el arranque;
# si alguien los pide antes de tiempo, play() espera a que esten.
#
#   sfx.play("crt_click")
#   sfx.play("crt_type", -3.0, randf_range(0.95, 1.08))

signal room_sounds_ready

const Synth = preload("res://scripts/sfx_synth.gd")

@export var bus: StringName = &"SFX"
## Sonidos simultaneos maximos. Si se llenan, se reusa la voz mas antigua.
@export var voices: int = 8

var _sounds: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
## Voz -> ms en que se le asigno un sonido por ultima vez.
var _claimed: Dictionary = {}
var _room_ready: bool = false
var _thread: Thread

func _ready() -> void:
	_sounds = Synth.build_ui()
	for i in voices:
		var p := AudioStreamPlayer.new()
		p.bus = bus
		add_child(p)
		_players.append(p)
	_thread = Thread.new()
	_thread.start(_build_room)

func _build_room() -> void:
	var room: Dictionary = Synth.build_room()
	_on_room_built.call_deferred(room)

func _on_room_built(room: Dictionary) -> void:
	_thread.wait_to_finish()
	_sounds.merge(room)
	_room_ready = true
	room_sounds_ready.emit()

func _exit_tree() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()

func play(sound: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var stream := await _wait_stream(sound)
	if stream == null:
		push_warning("Sonido desconocido: %s" % sound)
		return
	var p := _free_player()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()

## El stream crudo (p. ej. para un bucle con su propio reproductor).
func get_stream(sound: String) -> AudioStream:
	return await _wait_stream(sound)

func _wait_stream(sound: String) -> AudioStream:
	if not _sounds.has(sound) and not _room_ready:
		await room_sounds_ready
	var stream: Variant = _sounds.get(sound)
	if stream is Array:
		stream = stream.pick_random()
	return stream

func _free_player() -> AudioStreamPlayer:
	# `playing` no se vuelve true en el mismo frame del play(): sin esta marca,
	# dos sonidos pedidos a la vez caen en la misma voz y uno pisa al otro.
	var now := Time.get_ticks_msec()
	for p in _players:
		if not p.playing and now - int(_claimed.get(p, -1000)) > 100:
			_claimed[p] = now
			return p
	# Todas ocupadas: la siguiente en rotacion (la que lleva mas tiempo).
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	_claimed[p] = now
	return p
