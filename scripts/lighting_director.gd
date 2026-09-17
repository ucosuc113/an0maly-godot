extends Node

# Luces de la partida por fase.
#
#   dim_for_shield(t)   fase 2: baja lo que brilla (exterior, lasers,
#                       ventiladores) para que el escudo resalte.
#   blackout()          fase 3: se apaga TODO (sala, exterior, portal,
#                       ventiladores) en cascada; solo quedan los lasers,
#                       atenuados. Queda asi despues, para ver el agujero negro.

@export var room_lights: Node3D
@export var environment: WorldEnvironment
## GameIntro (su zumbido de fluorescentes se apaga con la sala).
@export var intro: Node
@export var outside: Node
@export var fans: Node
@export var lasers: Array[Node] = []
@export var sfx: Node
@export_range(0.0, 1.0, 0.05) var shield_outside_level: float = 0.45
@export_range(0.0, 1.0, 0.05) var shield_laser_light: float = 0.55
@export_range(0.0, 1.0, 0.05) var blackout_laser_light: float = 0.15

## Energias originales de la sala (antes del apagon).
var _room_energy: Dictionary = {}
var _ambient: float = 0.0

func dim_for_shield(time: float = 4.0) -> void:
	if outside:
		outside.fade_level(shield_outside_level, time)
	for l in lasers:
		l.set_light_scale(shield_laser_light, time)
	if fans:
		fans.fade_self_light(0.5, time)

## Apagon en cascada (~4 s): tubos de la sala uno por uno, el ambiente, y el
## exterior por filas.
func blackout() -> void:
	for l in lasers:
		l.set_light_scale(blackout_laser_light, 3.0)
		l.charge_up(0.85, 3.0)
	if fans:
		fans.fade_self_light(0.0, 3.0)
	await _room_off()
	if outside:
		await outside.shut_down(2.4)

## Enciende solo la sala (el exterior queda apagado), a `factor` de su
## energia original, con un par de tirones.
func room_on(factor: float = 0.75) -> void:
	var lights: Array = room_lights.find_children("*", "Light3D", true, false) if room_lights else []
	_play("lights_on", -6.0)
	for l: Light3D in lights:
		var target: float = _room_energy.get(l, l.light_energy) * factor
		var t := create_tween()
		for f in [0.8, 0.2, 1.0, 0.5, 1.0]:
			t.tween_property(l, "light_energy", target * f, 0.05)
	if environment and environment.environment:
		create_tween().tween_property(environment.environment, "ambient_light_energy",
			_ambient * factor, 0.8)
	if intro and intro.get("_hum"):
		intro._start_hum()

## Alarma: las luces de la sala se tinen de rojo y laten con `period`.
var _alarm_tween: Tween
var _room_color: Dictionary = {}
## Multiplicador de parpadeo (golpes de la onda expansiva).
var _flicker: float = 1.0

## Tiron de las luces de la sala: se caen y vuelven.
func flicker(strength: float = 1.0) -> void:
	var t := create_tween()
	t.tween_property(self, "_flicker", 1.0 + 0.8 * strength, 0.03)
	t.tween_property(self, "_flicker", 0.05, 0.06)
	t.tween_property(self, "_flicker", 0.7, 0.05)
	t.tween_property(self, "_flicker", 0.15, 0.05)
	t.tween_property(self, "_flicker", 1.0, 0.25)
	if _alarm_tween == null or not _alarm_tween.is_valid():
		var lights: Array = room_lights.find_children("*", "Light3D", true, false) if room_lights else []
		for l: Light3D in lights:
			var e := l.light_energy
			var lt := create_tween()
			for f in [0.05, 0.7, 0.15, 1.0]:
				lt.tween_property(l, "light_energy", e * f, 0.05)

func alarm(on: bool, period: float = 0.667) -> void:
	var lights: Array = room_lights.find_children("*", "Light3D", true, false) if room_lights else []
	if _alarm_tween:
		_alarm_tween.kill()
	if on:
		for l: Light3D in lights:
			if not _room_color.has(l):
				_room_color[l] = l.light_color
			if not _room_energy.has(l):
				_room_energy[l] = l.light_energy
		_alarm_tween = create_tween().set_loops()
		_alarm_tween.tween_method(func(k: float) -> void:
			for l: Light3D in lights:
				l.light_color = Color(1.0, 0.08, 0.05)
				l.light_energy = _room_energy[l] * lerpf(0.08, 0.9, k) * _flicker, 1.0, 0.0, period) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	else:
		for l: Light3D in lights:
			l.light_color = _room_color.get(l, l.light_color)
			l.light_energy = _room_energy.get(l, l.light_energy) * 0.75

func _room_off() -> void:
	var lights: Array = room_lights.find_children("*", "Light3D", true, false) if room_lights else []
	for l: Light3D in lights:
		if not _room_energy.has(l):
			_room_energy[l] = l.light_energy
	if environment and environment.environment:
		_ambient = environment.environment.ambient_light_energy
	for l: Light3D in lights:
		_play("breaker_off", -4.0, randf_range(0.95, 1.1))
		var start := l.light_energy
		var t := create_tween()
		for f in [0.3, 0.8, 0.0]:
			t.tween_property(l, "light_energy", start * f, 0.05)
		await get_tree().create_timer(0.28, false).timeout
	if environment and environment.environment:
		var env := environment.environment
		create_tween().tween_property(env, "ambient_light_energy", 0.0, 1.2)
	if intro and intro.get("_hum"):
		var hum: AudioStreamPlayer = intro._hum
		var h := create_tween()
		h.tween_property(hum, "volume_db", -60.0, 1.5)
		h.tween_callback(hum.stop)

func _play(sound: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if sfx:
		sfx.play(sound, volume_db, pitch)
