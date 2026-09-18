extends Node

# Musica de la partida. Vive como nodo en main.tscn (GameMusic), por el bus
# Music (lo controla SETTINGS).
#
#   start_background()   al quedar la sala a la vista: entra con fundido, bajo
#                        y en bucle.
#   play_track(stream)   musica de una fase: el fondo se desvanece y se
#                        detiene; al terminar la pista, el fondo vuelve.
#   duck_track(db, t)    baja la pista (p. ej. al terminar la cinematica).
#   track_time()         posicion exacta de la pista (para sincronizar).
#
# El fondo sigue sonando en la pausa; las pistas de fase se pausan con el
# juego (asi las cinematicas no se desincronizan).
#
# OJO con la pausa: las cinematicas esperan con
#
#     while music.is_track_playing() and music.track_time() < t: ...
#
# y un AudioStreamPlayer pausado deja de estar `playing` y no tiene posicion
# util. Si esos dos metodos se contestaran con el estado crudo del
# reproductor, al pausar saldrian todos los `_at()` de golpe: la secuencia se
# correria entera en dos cuadros mientras los tweens siguen congelados. Por
# eso is_track_playing() responde "hay una pista en curso" (no "esta sonando
# ahora") y track_time() devuelve la posicion congelada en vez de -1.

signal track_finished

## Ruta de la musica de fondo (se carga al iniciar; si todavia no esta
## importada, no suena y no rompe nada).
@export_file("*.mp3", "*.ogg", "*.wav") var background_path: String = ""
var background: AudioStream
@export var bus: StringName = &"Music"
## El archivo esta masterizado bajo (~-17 dBFS RMS): -8 lo deja de fondo,
## parejo con la musica del menu.
@export_range(-40.0, 0.0, 0.5) var background_volume_db: float = -8.0
@export var background_fade_in: float = 3.0
@export var background_fade_out: float = 1.8

var _bg: AudioStreamPlayer
var _track: AudioStreamPlayer
var _bg_tween: Tween
var _track_tween: Tween
var _bg_wanted: bool = false
## Hay una pista de fase en curso: desde play_track() hasta que termina o la
## paran. Sigue siendo true con el juego en pausa.
var _track_live: bool = false

func _ready() -> void:
	_bg = AudioStreamPlayer.new()
	_bg.bus = bus
	_bg.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_bg)
	_track = AudioStreamPlayer.new()
	_track.bus = bus
	_track.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_track)
	_track.finished.connect(_on_track_finished)
	background = load_stream(background_path)
	_set_loop(background)
	_bg.stream = background

func start_background() -> void:
	_bg_wanted = true
	if _track_live or background == null:
		return
	_bg.volume_db = -60.0
	if not _bg.playing:
		_bg.play()
	_bg_tween = _fade(_bg, _bg_tween, background_volume_db, background_fade_in, Tween.EASE_OUT)

## Desvanece el fondo (p. ej. en un final); vuelve con start_background().
func stop_background(time: float = 2.0) -> void:
	_bg_wanted = false
	if _bg.playing:
		_bg_tween = _fade(_bg, _bg_tween, -60.0, time, Tween.EASE_IN)
		_bg_tween.finished.connect(_bg.stop)

func play_track(stream: AudioStream, volume_db: float = -6.0) -> void:
	if stream == null:
		return
	if _bg.playing:
		_bg_tween = _fade(_bg, _bg_tween, -60.0, background_fade_out, Tween.EASE_IN)
		_bg_tween.finished.connect(_bg.stop)
	if _track_tween:
		_track_tween.kill()
	_track.stream = stream
	_track.volume_db = volume_db
	_track_live = true
	_track.play()

## Salta a un punto de la pista (el jugador adelanto el final a mano).
func seek_track(seconds: float) -> void:
	if _track_live:
		_track.seek(maxf(seconds, 0.0))

func duck_track(volume_db: float, time: float) -> void:
	if _track_live:
		_track_tween = _fade(_track, _track_tween, volume_db, time, Tween.EASE_IN_OUT)

func stop_track(time: float = 1.5) -> void:
	if not _track_live:
		return
	_track_tween = _fade(_track, _track_tween, -60.0, time, Tween.EASE_IN)
	_track_tween.finished.connect(func() -> void:
		_track.stop()
		_on_track_finished())

## Hay una pista de fase en curso (aunque el juego este en pausa).
func is_track_playing() -> bool:
	return _track_live

## Segundos de la pista que se estan escuchando ahora (compensa el buffer de
## audio y la latencia de salida). -1 si no hay pista.
func track_time() -> float:
	if not _track_live:
		return -1.0
	if not _track.playing:
		# En pausa: la posicion queda quieta y las cinematicas esperan ahi.
		return _track.get_playback_position()
	return _track.get_playback_position() + AudioServer.get_time_since_last_mix() \
		- AudioServer.get_output_latency()

## Carga una pista por ruta; null si no existe (p. ej. sin importar).
static func load_stream(path: String) -> AudioStream:
	if path.is_empty() or not ResourceLoader.exists(path):
		if not path.is_empty():
			push_warning("Musica: no encontre %s (¿importada?)" % path)
		return null
	return load(path) as AudioStream

func _on_track_finished() -> void:
	_track_live = false
	track_finished.emit()
	if _bg_wanted:
		start_background()

func _fade(player: AudioStreamPlayer, previous: Tween, db: float, time: float,
		easing: Tween.EaseType) -> Tween:
	if previous:
		previous.kill()
	var t := create_tween()
	# En lineal (no en dB) para que suene parejo.
	t.tween_method(func(v: float) -> void: player.volume_db = linear_to_db(maxf(v, 0.00001)),
		db_to_linear(player.volume_db), db_to_linear(db), time) \
		.set_trans(Tween.TRANS_SINE).set_ease(easing)
	return t

func _set_loop(stream: AudioStream) -> void:
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
