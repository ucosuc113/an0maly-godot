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

func _room_off() -> void:
	var lights: Array = room_lights.find_children("*", "Light3D", true, false) if room_lights else []
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
