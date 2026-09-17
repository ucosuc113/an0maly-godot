extends "res://scripts/mesh_interactable.gd"

# Mango de una palanca deslizante (5 niveles). Va como StaticBody hijo del
# modelo del mango (model = ".."), que en el editor esta en el nivel 1.
#
# El riel sale de la placa: la linea que va del centro del numero "1" al del
# "5" (sus texturas). El mango se mueve en esa direccion, 1/4 del recorrido
# por nivel. Solo responde en la vista del panel y con las palancas
# desbloqueadas (control_panel.gd).
#
#   arrastre -> el mango sigue al puntero sobre el riel; en cada muesca suena
#               un tic y el nivel cambia en vivo; en los extremos se resiste
#               como una goma.
#   soltar   -> encaja en el nivel mas cercano con un rebote y un "clac".
#   rueda    -> sube / baja un nivel.

## Nodo con control_panel.gd.
@export var panel: Node
## Id de la palanca en control_panel.gd (lateral, diagonal, fans, shield).
@export var lever_id: StringName = &"lateral"
## Modelo de la placa (la que tiene las texturas 1..5).
@export var plate: Node3D
@export var usable_in_view: StringName = &"Panel"
## Cuanto se puede pasar de los extremos al arrastrar, en niveles.
@export var overdrag: float = 0.2
## Rapidez con la que el mango alcanza al puntero (mas = mas pegado).
@export var follow_speed: float = 30.0

## Direccion del riel (unitaria, mundo) y distancia entre niveles.
var _axis: Vector3 = Vector3.RIGHT
var _step: float = 0.0167
var _rest_pos: Vector3
## Punto del riel: el centro del mango en el nivel 1 (el origen del nodo del
## FBX puede estar lejos de la malla).
var _rail_origin: Vector3
## Nivel "continuo" que se muestra (1.0 .. 5.0) y al que se dirige.
var _shown: float = 1.0
var _goal: float = 1.0
var _dragging: bool = false
var _grab: float = 0.0
var _last_detent: int = 1
var _snap_tween: Tween
var _in_view: bool = false

func _ready() -> void:
	super._ready()
	var root: Node3D = model if model else self
	_rest_pos = root.global_position
	_rail_origin = _handle_center(root)
	_find_rail()
	if views:
		views.view_changed.connect(_on_view_changed)
	if panel:
		panel.levers_unlocked.connect(_refresh)
		panel.level_changed.connect(_on_level_changed)
		_shown = panel.get_level(lever_id)
		_goal = _shown
		_last_detent = int(_shown)
	_apply_position()
	_refresh()

func _handle_center(root: Node3D) -> Vector3:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box.get_center() if not first else root.global_position

func _find_rail() -> void:
	if plate == null:
		push_warning("Palanca %s: sin placa, riel por defecto." % lever_id)
		return
	var first := Vector3.ZERO
	var last := Vector3.ZERO
	for mi: MeshInstance3D in plate.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s) as BaseMaterial3D
			if m == null or m.albedo_texture == null:
				continue
			var key := m.albedo_texture.resource_path.get_file().get_basename()
			if key != "1" and key != "5":
				continue
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			var box := AABB(verts[0], Vector3.ZERO)
			for v in verts:
				box = box.expand(v)
			var center := mi.global_transform * box.get_center()
			if key == "1":
				first = center
			else:
				last = center
	var rail := last - first
	# Solo el recorrido horizontal: la altura del mango no cambia.
	rail.y = 0.0
	if rail.length() > 0.001:
		_axis = rail.normalized()
		_step = rail.length() / 4.0

## Si el nivel cambia desde otro lado (no por este mango), el mango lo sigue.
func _on_level_changed(id: StringName, level: int) -> void:
	if id != lever_id or _dragging or level == _last_detent:
		return
	_snap_to(level)

func _on_view_changed(view: StringName) -> void:
	_in_view = view == usable_in_view
	_refresh()

func _refresh() -> void:
	enabled = _in_view and panel != null and not panel.levers_locked()

# --- Arrastre (pixel_display.gd) -------------------------------------------------

func on_drag_start(hit_position: Vector3) -> bool:
	if not is_interactive():
		return false
	_dragging = true
	if _snap_tween:
		_snap_tween.kill()
	# Donde se agarro, en niveles, respecto a la posicion del mango.
	_grab = _level_at(hit_position) - _shown
	Input.set_default_cursor_shape(Input.CURSOR_VSIZE)
	_play("lever_tick", -8.0, 0.8)
	return true

func on_drag(ray_origin: Vector3, ray_dir: Vector3) -> void:
	if not _dragging:
		return
	var p := _closest_on_rail(ray_origin, ray_dir)
	var target := _level_at(p) - _grab
	# Goma: pasado el extremo, avanza cada vez menos.
	if target < 1.0:
		target = 1.0 - overdrag * (1.0 - exp(-(1.0 - target) / overdrag))
	elif target > 5.0:
		target = 5.0 + overdrag * (1.0 - exp(-(target - 5.0) / overdrag))
	_goal = target

func on_drag_end() -> void:
	if not _dragging:
		return
	_dragging = false
	Input.set_default_cursor_shape(
		Input.CURSOR_POINTING_HAND if _hovering else Input.CURSOR_ARROW)
	_snap_to(clampi(int(round(_goal)), 1, 5))

func on_wheel(_hit_position: Vector3, direction: int) -> void:
	if not is_interactive() or _dragging:
		return
	var from := int(round(_goal))
	var to := clampi(from + direction, 1, 5)
	if to != from:
		_snap_to(to)

## Nivel continuo de un punto del mundo, proyectado sobre el riel.
func _level_at(p: Vector3) -> float:
	return 1.0 + (p - _rail_origin).dot(_axis) / _step

## Punto del riel mas cercano al rayo del puntero.
func _closest_on_rail(ro: Vector3, rd: Vector3) -> Vector3:
	var w := _rail_origin - ro
	var b := _axis.dot(rd)
	var d := _axis.dot(w)
	var e := rd.dot(w)
	var denom := 1.0 - b * b
	if absf(denom) < 1e-6:
		return _rail_origin
	var s := (b * e - d) / denom
	return _rail_origin + _axis * s

func _snap_to(level: int) -> void:
	if _snap_tween:
		_snap_tween.kill()
	_snap_tween = create_tween()
	_snap_tween.tween_property(self, "_goal", float(level), 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_play("lever_clack")
	_set_level(level)

func _set_level(level: int) -> void:
	_last_detent = level
	if panel:
		panel.set_level(lever_id, level)

# --- Movimiento ------------------------------------------------------------------

func _process(delta: float) -> void:
	if is_equal_approx(_shown, _goal):
		return
	if _dragging:
		_shown = lerpf(_shown, _goal, 1.0 - exp(-follow_speed * delta))
		# Muescas: cada nivel que se cruza suena y cambia en vivo.
		var detent := clampi(int(round(_shown)), 1, 5)
		if detent != _last_detent:
			_play("lever_tick", 0.0, randf_range(0.95, 1.08))
			_set_level(detent)
	else:
		_shown = _goal
	_apply_position()

func _apply_position() -> void:
	var root: Node3D = model if model else self
	root.global_position = _rest_pos + _axis * (_shown - 1.0) * _step

func _play(sound: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if views and views.sfx:
		views.sfx.play(sound, volume_db, pitch)
