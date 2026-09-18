extends Node

# Entrada al juego (ENTER THE ANOMALY). Vive como nodo en main.tscn (GameIntro).
#
#   menu se desvanece -> negro -> BANG (golpe de interruptor + destello que
#   satura la pantalla) -> los fluorescentes pelean por prender -> luces fijas
#   con su zumbido -> la sala queda a la vista.
#
# La sala y sus luces estan ocultas hasta ese momento: durante el CRT y el menu
# todo es oscuridad. Con REDUCE FLASHING no hay destello ni parpadeo.

## Se emite al entrar al juego (antes del golpe de luces). Desde aqui ya se
## puede pausar: la entrada tambien es partida, no un menu.
signal started

## Se emite cuando las luces quedaron fijas y la sala es jugable.
signal room_revealed

## Raiz de la sala (MapAnomalyPlayerRoom).
@export var room: Node3D
## Otras partes del escenario que aparecen junto con la sala (el exterior).
@export var reveal_nodes: Array[Node3D] = []
## Nodo con las luces de la sala (sus hijos Light3D).
@export var room_lights: Node3D
## ColorRect a pantalla completa para el destello (en un CanvasLayer arriba).
@export var flash: ColorRect
## WorldEnvironment de la sala (opcional). Su luz ambiente queda en 0 hasta el
## destello y luego sube/parpadea junto con los tubos: sin esto, el ambiente
## iluminaria el CRT y el menu, que deben estar a oscuras.
@export var environment: WorldEnvironment
@export var sfx: Node
@export var settings: Node
## Exposicion del tone mapping mientras estan el CRT y el menu. La de la sala
## es la que tenga el Environment en el editor; se aplica al entrar al juego.
@export var menu_exposure: float = 1.0
## Silencio en negro entre que se va el menu y el golpe.
@export var dark_hold: float = 0.8
## Volumen del zumbido de fondo de los fluorescentes.
@export_range(-40.0, 0.0, 0.5) var hum_volume_db: float = -16.0

var _lights: Array[Light3D] = []
var _energy: Dictionary = {}
var _ambient_energy: float = 0.0
var _tonemap: Environment.ToneMapper = Environment.TONE_MAPPER_LINEAR
var _room_exposure: float = 1.0
var _hum: AudioStreamPlayer
var _started: bool = false

func _ready() -> void:
	if room:
		room.visible = false
	for n in reveal_nodes:
		if n:
			n.visible = false
	if room_lights:
		room_lights.visible = false
		for l in room_lights.find_children("*", "Light3D", true, false):
			_lights.append(l)
			_energy[l] = l.light_energy
	if environment and environment.environment:
		var env := environment.environment
		_ambient_energy = env.ambient_light_energy
		env.ambient_light_energy = 0.0
		# El tone mapping de la sala (AgX) apaga el ambar del CRT: se aplica
		# recien en el destello, cuando la pantalla esta en blanco.
		_tonemap = env.tonemap_mode
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		_room_exposure = env.tonemap_exposure
		env.tonemap_exposure = menu_exposure
	if flash:
		flash.visible = false
		flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hum = AudioStreamPlayer.new()
	_hum.bus = &"SFX"
	add_child(_hum)

func start() -> void:
	if _started:
		return
	_started = true
	started.emit()
	# Al hacer clic: la pantalla ya esta a oscuras (el menu se fue), el cambio
	# de exposicion y de tone mapping no se ve.
	if environment and environment.environment:
		environment.environment.tonemap_exposure = _room_exposure
		environment.environment.tonemap_mode = _tonemap
	await get_tree().create_timer(dark_hold, false).timeout

	var gentle: bool = settings != null and bool(settings.get_value("reduce_flashing"))
	room.visible = true
	for n in reveal_nodes:
		if n:
			n.visible = true
	room_lights.visible = true
	if sfx:
		# El PUUMMM de la nave + clic, tinks y zumbido de los tubos.
		sfx.play("lights_boom")
		sfx.play("lights_on", -6.0)

	if gentle:
		# Sin destello: las luces suben en un momento, sin parpadeo.
		_set_lights(0.0)
		var t := create_tween()
		t.tween_method(_set_lights, 0.0, 1.0, 0.6).set_trans(Tween.TRANS_SINE)
		await get_tree().create_timer(0.35, false).timeout
		_start_hum()
		await t.finished
	else:
		await _bang()

	room_revealed.emit()

## Tiempos alineados con el sonido lights_on (tinks en 0.40 y 0.47 s,
## zumbido desde 0.45 s).
func _bang() -> void:
	# Golpe: blanco parejo en TODA la pantalla, que se desvanece y deja ver la
	# sala ya encendida (las luces no se sobreexponen: eso dejaba manchas).
	_set_lights(1.0)
	flash.visible = true
	flash.color = Color.WHITE
	var t := create_tween()
	t.tween_interval(0.05)
	t.tween_property(flash, "color:a", 0.0, 0.3).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	await t.finished
	flash.visible = false

	# Dos tirones de los tubos antes de quedar fijos.
	var steps := [
		[0.05, 1.0],   # 0.35 -> 0.40
		[0.04, 0.15],  # 0.40 tink: caida fuerte
		[0.03, 1.0],
		[0.03, 0.45],  # 0.47 tink: caida corta
	]
	for s in steps:
		_set_lights(s[1])
		await get_tree().create_timer(s[0], false).timeout
	_set_lights(1.0)
	_start_hum()

## factor: 1 = energia configurada en cada luz del editor.
func _set_lights(factor: float) -> void:
	for l in _lights:
		l.light_energy = _energy[l] * factor
	if environment and environment.environment:
		# El rebote no se sobreexpone con el golpe: se limita a 1.5x.
		environment.environment.ambient_light_energy = _ambient_energy * minf(factor, 1.5)

func _start_hum() -> void:
	if sfx == null or _hum.playing:
		return
	_hum.stream = await sfx.get_stream("fluoro_hum")
	_hum.volume_db = -40.0
	_hum.play()
	create_tween().tween_property(_hum, "volume_db", hum_volume_db, 0.4)
