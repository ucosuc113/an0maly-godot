extends "res://scripts/clickable.gd"

# Cristal del ventanal: clicable (clickable.gd) y con el vidrio transparente.
#
# El vidrio de Blender llega por FBX como material opaco y taparia el exterior;
# aqui se reemplaza esa superficie por un vidrio semitransparente con brillo.
#
# Al pasar el mouse: el cristal crece un poco (desde su centro), el vidrio se
# aclara, el marco brilla y un resaltado (crystal_hover.gdshader) dibuja
# esquinas naranjas como las de los menus, con un destello que lo cruza.
# Al hacer clic: vista del ventanal (camera_views.gd).

const HOVER_SHADER = preload("res://shaders/crystal_hover.gdshader")

## Superficie del modelo que es el vidrio (0 = Material.015).
@export var glass_surface: int = 0
@export var glass_tint: Color = Color(0.72, 0.85, 0.95)
## Opacidad del vidrio: 0.15 = 85% transparente.
@export_range(0.0, 1.0, 0.01) var glass_opacity: float = 0.15
@export_range(0.0, 1.0, 0.01) var glass_roughness: float = 0.05

@export_group("Hover")
@export_range(1.0, 1.2, 0.005) var hover_scale: float = 1.02
## Opacidad del vidrio con el mouse encima (mas claro).
@export_range(0.0, 1.0, 0.01) var hover_glass_opacity: float = 0.24
@export var hover_tint: Color = Color(0.78, 0.92, 1.0)
## Emision del marco con el mouse encima.
@export_range(0.0, 4.0, 0.05) var hover_frame_energy: float = 0.35
@export var hover_accent: Color = Color(1.0, 0.52, 0.14)
## Medidas del marco resaltado, en metros: separacion del borde del panel,
## grosor de linea (~2 px del juego a la distancia de la sala) y largo de los
## brazos de las esquinas.
@export var hover_inset: float = 0.04
## Separacion extra arriba: ahi la moldura de la pared tapa el borde del vidrio.
@export var hover_inset_top: float = 0.07
@export var hover_line: float = 0.03
@export var hover_corner: float = 0.15

@export_group("View")
## Nodo con camera_views.gd y la vista que abre el clic.
@export var views: Node
@export var view_name: StringName = &"Window"

var glass_material: StandardMaterial3D
var _frame_materials: Array[StandardMaterial3D] = []
var _hover_materials: Array[ShaderMaterial] = []
var _rest: Transform3D
var _pivot: Vector3
var _hover: float = 0.0:
	set(value):
		_hover = value
		_apply_hover()
var _hover_tween: Tween

func _ready() -> void:
	glass_material = StandardMaterial3D.new()
	glass_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_material.albedo_color = Color(glass_tint, glass_opacity)
	glass_material.roughness = glass_roughness
	glass_material.metallic_specular = 0.9
	var root: Node3D = model if model else self
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var hover := _make_hover_material(mi)
		for s in mi.mesh.get_surface_count():
			if s == glass_surface:
				mi.set_surface_override_material(s, glass_material)
				continue
			var base := mi.get_active_material(s) as StandardMaterial3D
			if base:
				var m := base.duplicate() as StandardMaterial3D
				m.emission_enabled = true
				m.emission = hover_tint
				m.emission_energy_multiplier = 0.0
				m.next_pass = hover
				mi.set_surface_override_material(s, m)
				_frame_materials.append(m)
		# El resaltado va sobre el vidrio (y el marco, via next_pass arriba).
		glass_material.next_pass = hover
		_hover_materials.append(hover)
	super._ready()

	_rest = root.transform
	var inv := global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = inv * mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	_pivot = box.get_center()
	hover_changed.connect(_on_hover_changed)
	clicked.connect(_on_clicked)
	_apply_hover()

func _make_hover_material(mi: MeshInstance3D) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = HOVER_SHADER
	m.render_priority = 1
	var aabb := mi.get_aabb()
	# Los dos ejes mas largos en metros son el ancho y el alto del panel.
	var meters := Vector3(
		aabb.size.x * mi.global_basis.x.length(),
		aabb.size.y * mi.global_basis.y.length(),
		aabb.size.z * mi.global_basis.z.length())
	var order := [0, 1, 2]
	order.sort_custom(func(a: int, b: int) -> bool: return meters[a] > meters[b])
	var au: int = order[0]
	var av: int = order[1]
	m.set_shader_parameter("box_origin", aabb.position)
	m.set_shader_parameter("box_size", aabb.size)
	m.set_shader_parameter("axis_u", au)
	m.set_shader_parameter("axis_v", av)
	var per_m := Vector2(1.0 / maxf(meters[au], 0.001), 1.0 / maxf(meters[av], 0.001))
	m.set_shader_parameter("inset", per_m * hover_inset)
	m.set_shader_parameter("thickness", per_m * hover_line)
	m.set_shader_parameter("corner", per_m * hover_corner)
	m.set_shader_parameter("inset_top", per_m.y * hover_inset_top)
	m.set_shader_parameter("top_is_high", mi.global_basis[av].y > 0.0)
	m.set_shader_parameter("tint", hover_tint)
	m.set_shader_parameter("accent", hover_accent)
	return m

func _on_hover_changed(hovering: bool) -> void:
	if _hover_tween:
		_hover_tween.kill()
	_hover_tween = create_tween()
	if hovering:
		_hover_tween.tween_property(self, "_hover", 1.0, 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_hover_tween.tween_property(self, "_hover", 0.0, 0.18) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _on_clicked(_hit_position: Vector3) -> void:
	if views == null or views.is_busy():
		return
	enabled = false  # suelta el hover y el cursor de mano
	views.go_to(view_name)

func _apply_hover() -> void:
	if not is_node_ready():
		return
	var root: Node3D = model if model else self
	# TRANS_BACK se pasa de 1: el cristal "rebota" un poco al crecer.
	var s := 1.0 + (hover_scale - 1.0) * _hover
	root.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), _pivot - _pivot * s) * _rest
	var k := clampf(_hover, 0.0, 1.0)
	glass_material.albedo_color = Color(glass_tint.lerp(hover_tint, k),
		lerpf(glass_opacity, hover_glass_opacity, k))
	for m in _frame_materials:
		m.emission_energy_multiplier = hover_frame_energy * k
	for m in _hover_materials:
		m.set_shader_parameter("intensity", k)
