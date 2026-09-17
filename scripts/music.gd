extends Node

# Musica del menu. Vive como nodo en main.tscn (Music) y suena por el bus
# Music, que controla SETTINGS.
#
#   start()  entra con fundido la primera vez que el monitor sale de cuadro.
#            Si ya esta sonando no hace nada: sigue igual en SETTINGS/ENDINGS.
#   stop()   se desvanece (al entrar al juego).

@export var stream: AudioStream
@export var bus: StringName = &"Music"
## Volumen base. El archivo esta masterizado muy fuerte (RMS ~-12 dBFS, picos
## a 0 dB); -14 dB lo deja en ~-26 dBFS, debajo de los efectos.
@export_range(-40.0, 0.0, 0.5) var base_volume_db: float = -14.0
@export var fade_in_time: float = 2.5
@export var fade_out_time: float = 1.5

var _player: AudioStreamPlayer
var _tween: Tween
var _playing: bool = false

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = bus
	add_child(_player)
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_player.stream = stream

func start() -> void:
	if _playing or stream == null:
		return
	_playing = true
	_player.volume_db = -60.0
	_player.play()
	_fade_to(base_volume_db, fade_in_time, Tween.EASE_OUT)

func stop() -> void:
	if not _playing:
		return
	_playing = false
	_fade_to(-60.0, fade_out_time, Tween.EASE_IN)
	await _tween.finished
	if not _playing:
		_player.stop()

func _fade_to(db: float, time: float, easing: Tween.EaseType) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	# El fundido se hace en lineal (no en dB) para que suene parejo al oido.
	_tween.tween_method(_set_linear, db_to_linear(_player.volume_db), db_to_linear(db), time) \
		.set_trans(Tween.TRANS_SINE).set_ease(easing)

func _set_linear(v: float) -> void:
	_player.volume_db = linear_to_db(maxf(v, 0.00001))
