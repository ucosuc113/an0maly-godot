extends Node

# Reproductor de efectos. Vive como nodo en main.tscn (Sfx). Genera todos los
# sonidos al iniciar (sfx_synth.gd, ~0.4 s) y los reproduce con un grupo
# pequeno de AudioStreamPlayer por el bus SFX, que controla SETTINGS.
#
#   sfx.play("crt_click")
#   sfx.play("crt_type", -3.0, randf_range(0.95, 1.08))

const Synth = preload("res://sfx_synth.gd")

@export var bus: StringName = &"SFX"
## Sonidos simultaneos maximos. Si se llenan, se reusa la voz mas antigua.
@export var voices: int = 8

var _sounds: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next: int = 0

func _ready() -> void:
	_sounds = Synth.build_all()
	for i in voices:
		var p := AudioStreamPlayer.new()
		p.bus = bus
		add_child(p)
		_players.append(p)

func play(sound: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var stream: Variant = _sounds.get(sound)
	if stream == null:
		push_warning("Sonido desconocido: %s" % sound)
		return
	if stream is Array:
		stream = stream.pick_random()
	var p := _free_player()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()

func _free_player() -> AudioStreamPlayer:
	for p in _players:
		if not p.playing:
			return p
	# Todas ocupadas: la siguiente en rotacion (la que lleva mas tiempo).
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	return p
