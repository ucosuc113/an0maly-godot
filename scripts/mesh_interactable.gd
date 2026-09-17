extends "res://scripts/clickable.gd"

# Objeto 3D con volumen que se puede usar (el panel base, y despues botones y
# palancas). Al pasar el mouse: resaltado naranja que late, la superficie se
# aclara y, si hover_scale > 1, crece un poco desde su centro.
#
# Resaltado (outline_style):
#   Edges -> aristas y esquinas de la caja dibujadas sobre el objeto
#            (hover_edges). Para objetos apoyados en paredes/pisos.
#   Hull  -> contorno por detras con la malla inflada (hover_outline). Para
#            piezas sueltas y simples, donde la silueta se ve contra el fondo.
# Al hacer clic abre view_name en camera_views.gd (si hay una); si no, solo
# emite `clicked`.
#
# La colision sale de la forma real de la malla (collision_from_mesh), no de
# una caja.

const EDGES_SHADER = preload("res://shaders/hover_edges.gdshader")
const HULL_SHADER = preload("res://shaders/hover_outline.gdshader")

@export_group("Hover")
@export var hover_accent: Color = Color(1.0, 0.52, 0.14)
@export_enum("Edges", "Hull") var outline_style: int = 0
## Grosor de las lineas en metros (~1 px del juego a 1.3 m de distancia).
@export var outline_width: float = 0.025
## Largo de los brazos de las esquinas (Edges), en metros.
@export var corner_length: float = 0.12
## Cuanto se empuja el contorno detras del objeto (Hull), en metros. En
## piezas chicas tiene que ser menor que el objeto.
@export var outline_depth_push: float = 0.03
## Aclarado de la superficie con el mouse encima.
@export var hover_tint: Color = Color(0.78, 0.92, 1.0)
@export_range(0.0, 2.0, 0.05) var hover_energy: float = 0.18
@export_range(1.0, 1.2, 0.005) var hover_scale: float = 1.0

@export_group("View")
## Nodo con camera_views.gd y la vista que abre el clic (vacio = ninguna).
@export var views: Node
@export var view_name: StringName = &""

var _lit_materials: Array[StandardMaterial3D] = []
var _outlines: Array[ShaderMaterial] = []
var _rest: Transform3D
var _pivot: Vector3
var _hover: float = 0.0:
	set(value):
		_hover = value
		_apply_hover()
var _hover_tween: Tween

func _init() -> void:
	collision_from_mesh = true

func _ready() -> void:
	for mi: MeshInstance3D in _meshes():
		var outline := _make_edges(mi) if outline_style == 0 else _make_hull(mi)
		_outlines.append(outline)
		for s in mi.mesh.get_surface_count():
			var base := mi.get_active_material(s) as StandardMaterial3D
			if base == null:
				continue
			var m := base.duplicate() as StandardMaterial3D
			m.emission_enabled = true
			m.emission = hover_tint
			m.emission_energy_multiplier = 0.0
			# En todas las superficies: cada una dibuja su parte (con Hull,
			# todas se inflan desde el mismo centro).
			m.next_pass = outline
			mi.set_surface_override_material(s, m)
			_lit_materials.append(m)
	super._ready()

	var root: Node3D = model if model else self
	_rest = root.transform
	var box := AABB()
	var first := true
	var inv := root.get_parent_node_3d().global_transform.affine_inverse() \
		if root.get_parent_node_3d() else Transform3D.IDENTITY
	for mi: MeshInstance3D in _meshes():
		var b: AABB = inv * mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	_pivot = box.get_center()
	hover_changed.connect(_on_hover_changed)
	clicked.connect(_on_clicked)
	_apply_hover()

## Tamano de la caja de la malla en metros.
func _size_m(mi: MeshInstance3D) -> Vector3:
	var size := mi.get_aabb().size
	return Vector3(size.x * mi.global_basis.x.length(),
		size.y * mi.global_basis.y.length(),
		size.z * mi.global_basis.z.length())

func _make_edges(mi: MeshInstance3D) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = EDGES_SHADER
	m.render_priority = 1
	var aabb := mi.get_aabb()
	var size_m := _size_m(mi)
	m.set_shader_parameter("box_origin", aabb.position)
	m.set_shader_parameter("box_size", aabb.size)
	m.set_shader_parameter("size_m", size_m)
	m.set_shader_parameter("long_axis", size_m.max_axis_index())
	m.set_shader_parameter("line_width", outline_width)
	m.set_shader_parameter("corner_length", corner_length)
	m.set_shader_parameter("accent", hover_accent)
	m.set_shader_parameter("tint", hover_tint)
	return m

func _make_hull(mi: MeshInstance3D) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = HULL_SHADER
	var aabb := mi.get_aabb()
	var half_m := _size_m(mi) * 0.5
	m.set_shader_parameter("center", aabb.get_center())
	m.set_shader_parameter("grow", Vector3(
		outline_width / maxf(half_m.x, 0.001),
		outline_width / maxf(half_m.y, 0.001),
		outline_width / maxf(half_m.z, 0.001)))
	m.set_shader_parameter("color", hover_accent)
	m.set_shader_parameter("depth_push", outline_depth_push)
	return m

func _on_hover_changed(hovering: bool) -> void:
	if _hover_tween:
		_hover_tween.kill()
	_hover_tween = create_tween()
	if hovering:
		_hover_tween.tween_property(self, "_hover", 1.0, 0.2) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_hover_tween.tween_property(self, "_hover", 0.0, 0.16) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _on_clicked(_hit_position: Vector3) -> void:
	if views == null or view_name.is_empty() or views.is_busy():
		return
	enabled = false  # suelta el hover y el cursor de mano
	views.go_to(view_name)

func _apply_hover() -> void:
	if not is_node_ready():
		return
	if hover_scale > 1.0:
		var root: Node3D = model if model else self
		var s := 1.0 + (hover_scale - 1.0) * _hover
		root.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), _pivot - _pivot * s) * _rest
	var k := clampf(_hover, 0.0, 1.0)
	for m in _lit_materials:
		m.emission_energy_multiplier = hover_energy * k
	for m in _outlines:
		m.set_shader_parameter("intensity", k)
