extends Node

# Aspas de los ventiladores del exterior. Giran a la velocidad real de la
# simulacion (reactor_sim.gd, fan_rpm): quietas hasta la fase 1, y mas rapidas
# con la palanca de refrigeracion.
#
# Cada malla gira sobre su propio eje, calculado de sus vertices: el eje es la
# direccion en la que el disco de aspas es mas delgado (componente principal
# menor), asi funciona aunque el ventilador este inclinado (los laterales
# estan a 45 grados). No hace falta que el origen del modelo este en el eje.
#
# Engano de iluminacion: las aspas lejos de las luces se veian negras; sus
# materiales emiten un poco de su propio color (self_light).

## Modelos con las aspas (todas sus mallas giran).
@export var blades: Array[Node3D] = []
@export var sim: Node
## Vueltas por segundo que se ven a 1000 RPM reales (a velocidad real, a 60
## cuadros, las aspas parecerian quietas o girando al reves).
@export var visual_rps_per_1000rpm: float = 2.2
## Brillo propio de las aspas (fraccion de su color).
@export_range(0.0, 2.0, 0.05) var self_light: float = 0.45
## Brillo propio del chasis (0 = sin tocar).
@export var chassis: Array[Node3D] = []
@export_range(0.0, 2.0, 0.05) var chassis_light: float = 0.25

## [{mesh, rest (Transform3D en el padre), pivot, axis, dir}]
var _fans: Array = []
var _angle: float = 0.0
## [StandardMaterial3D, energia base]
var _lit: Array = []

func _ready() -> void:
	var dir := 1.0
	for b in blades:
		if b == null:
			continue
		for mi: MeshInstance3D in b.find_children("*", "MeshInstance3D", true, false):
			_fans.append(_make_fan(mi, dir))
			mi.add_to_group(&"still_shadow")
			dir = -dir
			_add_self_light(mi, self_light)
	for c in chassis:
		if c:
			c.set_meta(&"no_split", true)
		if c == null or chassis_light <= 0.0:
			continue
		for mi: MeshInstance3D in c.find_children("*", "MeshInstance3D", true, false):
			_add_self_light(mi, chassis_light)

func _make_fan(mi: MeshInstance3D, dir: float) -> Dictionary:
	var box := mi.get_aabb()
	var local_axis := _thin_axis(mi.mesh.get_faces())
	var rest := mi.transform
	return {
		"mesh": mi,
		"rest": rest,
		"pivot": rest * box.get_center(),
		"axis": (rest.basis * local_axis).normalized(),
		"dir": dir,
	}

## Direccion de menor varianza de los puntos (normal del disco de aspas).
static func _thin_axis(points: PackedVector3Array) -> Vector3:
	if points.is_empty():
		return Vector3.UP
	var c := Vector3.ZERO
	for p in points:
		c += p
	c /= points.size()
	var xx := 0.0
	var yy := 0.0
	var zz := 0.0
	var xy := 0.0
	var xz := 0.0
	var yz := 0.0
	for p in points:
		var d := p - c
		xx += d.x * d.x
		yy += d.y * d.y
		zz += d.z * d.z
		xy += d.x * d.y
		xz += d.x * d.z
		yz += d.y * d.z
	var cov := Basis(Vector3(xx, xy, xz), Vector3(xy, yy, yz), Vector3(xz, yz, zz))
	# Menor autovalor de una matriz simetrica 3x3 (metodo trigonometrico).
	var q := (xx + yy + zz) / 3.0
	var p1 := xy * xy + xz * xz + yz * yz
	var p2 := (xx - q) * (xx - q) + (yy - q) * (yy - q) + (zz - q) * (zz - q) + 2.0 * p1
	var pp := sqrt(p2 / 6.0)
	if pp < 1e-12:
		return Vector3.UP
	var b := Basis(cov.x - Vector3(q, 0, 0), cov.y - Vector3(0, q, 0), cov.z - Vector3(0, 0, q))
	var r := clampf(b.determinant() / (2.0 * pp * pp * pp), -1.0, 1.0)
	var phi := acos(r) / 3.0
	var smallest := q + 2.0 * pp * cos(phi + TAU / 3.0)
	# El autovector es perpendicular a las filas de (C - lambda I).
	var m := Basis(cov.x - Vector3(smallest, 0, 0), cov.y - Vector3(0, smallest, 0),
		cov.z - Vector3(0, 0, smallest))
	var candidates := [m.x.cross(m.y), m.x.cross(m.z), m.y.cross(m.z)]
	var best: Vector3 = candidates[0]
	for v in candidates:
		if v.length_squared() > best.length_squared():
			best = v
	return best.normalized() if best.length_squared() > 0.0 else Vector3.UP

func _add_self_light(mi: MeshInstance3D, amount: float) -> void:
	for s in mi.mesh.get_surface_count():
		var base := mi.get_active_material(s) as StandardMaterial3D
		if base == null:
			continue
		var m := base.duplicate() as StandardMaterial3D
		m.emission_enabled = true
		m.emission = base.albedo_color
		m.emission_energy_multiplier = amount
		mi.set_surface_override_material(s, m)
		_lit.append([m, amount])

## Escala el brillo propio (0 = sin brillo, p. ej. en el apagon).
## Mallas de aspas (para la onda expansiva y el agujero negro).
func blade_meshes() -> Array:
	return _fans.map(func(f: Dictionary) -> MeshInstance3D: return f.mesh)

## Aspa arrancada (false) o de vuelta (true).
func set_blade_active(mi: Node3D, active: bool) -> void:
	for f in _fans:
		if f.mesh == mi:
			f.off = not active
			mi.visible = active

## Sacudon: el aspa vibra y pierde el paso un momento.
func rattle(mi: Node3D, amount: float) -> void:
	for f in _fans:
		if f.mesh == mi:
			f.rattle = maxf(f.get("rattle", 0.0), amount)

func fade_self_light(scale: float, time: float) -> void:
	var t := create_tween().set_parallel()
	for pair in _lit:
		t.tween_property(pair[0], "emission_energy_multiplier", pair[1] * scale, time)

func _process(delta: float) -> void:
	if sim == null or _fans.is_empty():
		return
	var rps: float = sim.fan_rpm / 1000.0 * visual_rps_per_1000rpm
	_angle = wrapf(_angle + rps * TAU * delta, 0.0, TAU)
	for f in _fans:
		if f.get("off", false):
			continue
		var shake: float = f.get("rattle", 0.0)
		if rps <= 0.0 and shake <= 0.0:
			continue
		var rot := Basis(f.axis, _angle * f.dir + randf_range(-0.4, 0.4) * shake)
		var pivot: Vector3 = f.pivot
		var about := Transform3D(rot, pivot - rot * pivot)
		var xf: Transform3D = about * f.rest
		if shake > 0.0:
			xf.origin += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.02 * shake
			f.rattle = maxf(shake - delta * 1.5, 0.0)
		f.mesh.transform = xf
