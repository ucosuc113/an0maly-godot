extends Node

# Encendido de las luces del exterior (fase 1). Vive en main.tscn dentro de
# Outside. Al iniciar el juego todo queda apagado: las tiras (strip_power
# .gdshader), sus luces reales y el portal. power_on() las enciende de arriba
# hacia abajo: un frente de luz baja por las tiras y cada fila de luces prende
# con un golpe de interruptor y los tirones de un tubo al pasar el frente. Al
# final se enciende el portal.
#
# Va despues de GlowLights / GlowPortal en el arbol: toma los valores que ellos
# ya prepararon.
#
#   fade_level(v, t)     nivel general de tiras y luces (1 = normal, 0 = apagado)
#   shut_down(t)         apagado por filas de abajo arriba, con golpes

const STRIP_SHADER = preload("res://shaders/strip_power.gdshader")

## Modelo de las tiras (MapAnomalyAfueraluz).
@export var strips: Node3D
## Nodo con las luces reales (OutsideLights).
@export var lights: Node3D
## Nodo con glow_control.gd del portal (GlowPortal).
@export var portal_glow: Node
@export var sfx: Node
## Duracion del recorrido del frente, de arriba a abajo.
@export var sweep_time: float = 2.6
## Intensidad de las tiras respecto al modelo importado (encandilaban y no
## dejaban ver el escudo).
@export_range(0.0, 2.0, 0.05) var strip_intensity: float = 0.35
## Intensidad de las luces reales respecto a la del editor.
@export_range(0.0, 2.0, 0.05) var light_intensity: float = 0.45
@export var portal_time: float = 1.2

var _strip_mats: Array[ShaderMaterial] = []
var _top: float = 2.0
var _bottom: float = -2.0
## [{y, lights: [Light3D], energy: {Light3D: float}, on: bool}] de arriba abajo.
var _rows: Array = []
var _portal_intensity: float = 1.0
## Nivel general (lo animan fade_level / shut_down).
var level: float = 1.0:
	set(value):
		level = value
		_apply_level()
## Factor actual de cada fila (tirones del encendido).
var _row_factor: Dictionary = {}
var _strip_energy: float = 0.0

func _ready() -> void:
	_setup_strips()
	_setup_rows()
	if portal_glow:
		_portal_intensity = portal_glow.intensity
		portal_glow.intensity = 0.0
	_set_front(_top + 1.0)

func _setup_strips() -> void:
	if strips == null:
		return
	var first := true
	for mi: MeshInstance3D in strips.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = mi.global_transform * mi.get_aabb()
		_top = box.end.y if first else maxf(_top, box.end.y)
		_bottom = box.position.y if first else minf(_bottom, box.position.y)
		first = false
		for s in mi.mesh.get_surface_count():
			var base := mi.get_active_material(s) as StandardMaterial3D
			if base == null or not base.emission_enabled:
				continue
			var m := ShaderMaterial.new()
			m.shader = STRIP_SHADER
			m.set_shader_parameter("albedo", base.albedo_color)
			m.set_shader_parameter("roughness", base.roughness)
			m.set_shader_parameter("emission_color", base.emission)
			_strip_energy = maxf(base.emission_energy_multiplier, 1.0) * strip_intensity
			m.set_shader_parameter("emission_energy", _strip_energy)
			mi.set_surface_override_material(s, m)
			_strip_mats.append(m)

func _setup_rows() -> void:
	if lights == null:
		return
	var by_y := {}
	for l: Light3D in lights.find_children("*", "Light3D", true, false):
		var key := snappedf(l.global_position.y, 0.1)
		if not by_y.has(key):
			by_y[key] = {"y": l.global_position.y, "lights": [], "energy": {}, "on": false}
		by_y[key].lights.append(l)
		by_y[key].energy[l] = l.light_energy * light_intensity
		l.light_energy = 0.0
	_rows = by_y.values()
	_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.y > b.y)

func power_on() -> void:
	var t := create_tween()
	t.tween_method(_set_front, _top + 0.05, _bottom - 0.3, sweep_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await t.finished
	# Filas que el frente no alcanzo a prender (por redondeo).
	for row in _rows:
		if not row.on:
			_row_on(row)
	if portal_glow:
		_play("portal_on")
		await portal_glow.fade_to(_portal_intensity, portal_time).finished

func _set_front(y: float) -> void:
	for m in _strip_mats:
		m.set_shader_parameter("front_y", y)
	for row in _rows:
		if not row.on and y <= row.y:
			_row_on(row)

func _row_on(row: Dictionary) -> void:
	row.on = true
	_play("flood_on", -2.0, randf_range(0.92, 1.05))
	# Tirones de tubo: prende, cae, vuelve y queda fija.
	var steps := [[1.2, 0.05], [0.1, 0.06], [0.8, 0.04], [0.3, 0.05], [1.0, 0.0]]
	var t := create_tween()
	for st in steps:
		t.tween_callback(_set_row.bind(row, st[0]))
		if st[1] > 0.0:
			t.tween_interval(st[1])

func _set_row(row: Dictionary, factor: float) -> void:
	_row_factor[row] = factor
	for l: Light3D in row.lights:
		l.light_energy = row.energy[l] * factor * level

func _apply_level() -> void:
	for m in _strip_mats:
		m.set_shader_parameter("emission_energy", _strip_energy * level)
	for row in _rows:
		if row.on:
			_set_row(row, _row_factor.get(row, 1.0))

func fade_level(value: float, time: float) -> Tween:
	var t := create_tween()
	t.tween_property(self, "level", value, time).set_trans(Tween.TRANS_SINE)
	return t

## Apagado por filas, de abajo hacia arriba, cada una con su golpe y un
## ultimo parpadeo. Al final se apagan las tiras y el portal.
func shut_down(time: float = 3.0) -> void:
	var rows := _rows.duplicate()
	rows.reverse()
	var step := time / maxf(rows.size() + 1, 1)
	for row in rows:
		if not row.on:
			continue
		_play("breaker_off", -3.0, randf_range(0.9, 1.05))
		var t := create_tween()
		for st in [[0.4, 0.04], [0.9, 0.05], [0.0, 0.0]]:
			t.tween_callback(_set_row.bind(row, st[0]))
			if st[1] > 0.0:
				t.tween_interval(st[1])
		await get_tree().create_timer(step, false).timeout
	var s := create_tween().set_parallel()
	for m in _strip_mats:
		s.tween_method(func(v: float) -> void: m.set_shader_parameter("emission_energy", v),
			_strip_energy * level, 0.0, step)
	if portal_glow:
		s.tween_property(portal_glow, "intensity", 0.0, step)
	_play("breaker_off", 0.0, 0.8)
	await s.finished

## Luces de emergencia (derretimiento): las filas vuelven en rojo, con
## tirones. on = false las apaga y les devuelve su color.
var _base_color: Dictionary = {}

func emergency(on: bool, color: Color = Color(1.0, 0.16, 0.08), factor: float = 1.1) -> void:
	for row in _rows:
		for l: Light3D in row.lights:
			if not _base_color.has(l):
				_base_color[l] = l.light_color
			l.light_color = color if on else _base_color[l]
			if not on:
				l.visible = true
		var steps := [[0.6, 0.05], [0.1, 0.07], [factor, 0.0]] if on else [[factor * 0.4, 0.05], [0.0, 0.0]]
		var t := create_tween()
		t.tween_interval(randf_range(0.0, 0.5))
		for st in steps:
			t.tween_callback(_set_row.bind(row, st[0]))
			if st[1] > 0.0:
				t.tween_interval(st[1])
	_play("breaker_off", -4.0, 1.3 if on else 0.8)

func _play(sound: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if sfx:
		sfx.play(sound, volume_db, pitch)
