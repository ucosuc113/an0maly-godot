extends Node3D

# Pantalla LED sobre una superficie de un modelo, SIN ser clicable.
#
# info_monitor.gd hace esto mismo, pero ademas es el cuerpo clicable y
# registra su propia vista de camara. Los monitores de la sala de emergencia
# ya tienen su cuerpo de enfoque aparte (focus_target.gd, que rutea segun
# desde donde se los mire), asi que aca hace falta solo la parte de dibujar:
# buscar la superficie por nombre de material, colgarle un SubViewport con el
# contenido y mostrarlo con el shader de LCD.
#
# Va como hijo del modelo del monitor. La superficie se busca en `model` (o en
# el padre si esta vacio).
#
# Ademas registra su PROPIA vista de camara, colocada a la distancia exacta
# para que un pixel de la pantalla sea un pixel del juego. Sin eso el texto no
# se lee: encuadrar los tres monitores juntos deja cada pantalla en un puñado
# de pixeles. Es la misma cuenta que hace info_monitor.gd para los monitores
# de la sala principal.

const LCD_SHADER = preload("res://shaders/lcd_screen.gdshader")

## Modelo que contiene la pantalla. Vacio = el padre.
@export var model: Node3D
## Material de la superficie de la pantalla.
@export var screen_material: String = "Material.028"
## Contenido (extiende monitor_screen.gd).
@export var screen_script: Script
## Ancho del contenido en pixeles. El ALTO se deduce de la forma real de la
## superficie: ponerlo a mano es como se deforma el contenido (la pantalla de
## arriba es ancha y baja, y con un viewport casi cuadrado el texto quedaba
## aplastado hasta no leerse).
@export var screen_width_px: int = 200
var screen_size: Vector2i = Vector2i(200, 107)
@export var boot_title: String = "TELEMETRY"
## Variante del contenido, si el script lo soporta (emergency_screen.gd usa
## esto para elegir cual de las tres pantallas dibuja).
@export var screen_mode: int = 0
## Se enciende sola al arrancar (estos monitores no tienen secuencia propia).
@export var auto_power: bool = true
@export_group("Vista propia")
@export var views: Node
## Vista a la que se llega para leerla (vacio = no registra ninguna).
@export var view_name: StringName = &""
## De que vista cuelga: BACK vuelve ahi, no a la sala.
@export var parent_view: StringName = &""
## Cuanto sube la pantalla en el encuadre (px), para no quedar debajo del
## boton BACK.
@export var focus_raise_px: int = 10
@export_group("Datos")
@export var sim: Node
@export var crisis: Node
@export var room: Node

var screen: Control
var _viewport: SubViewport
var _lcd: ShaderMaterial
var powered: bool = false
## Geometria de la pantalla en el mundo, para el encuadre 1:1.
var _center: Vector3
var _normal: Vector3
var _up: Vector3
var _width_m: float = 1.0
var _height_m: float = 1.0

func _ready() -> void:
	_build()
	_register_view.call_deferred()
	if auto_power:
		power_on.call_deferred()

func _meshes() -> Array[Node]:
	var root: Node3D = model if model else get_parent_node_3d()
	if root == null:
		return []
	return root.find_children("*", "MeshInstance3D", true, false)

func _build() -> void:
	if screen_script == null:
		push_warning("ScreenPanel %s: sin contenido" % name)
		return
	# Primero hay que encontrar y MEDIR la superficie: de su forma sale el
	# tamano del viewport, asi que no se puede armar nada antes.
	var found: MeshInstance3D = null
	var surface := -1
	for mi: MeshInstance3D in _meshes():
		for k in mi.mesh.get_surface_count():
			var base := mi.mesh.surface_get_material(k)
			if base != null and base.resource_name == screen_material:
				found = mi
				surface = k
				break
		if found:
			break
	if found == null:
		push_warning("ScreenPanel %s: no encontre la superficie %s"
			% [name, screen_material])
		return
	var uv := _measure(found, surface)
	screen_size = Vector2i(screen_width_px,
		maxi(int(round(screen_width_px * _height_m / maxf(_width_m, 0.0001))), 8))

	_viewport = SubViewport.new()
	_viewport.name = "ScreenViewport"
	_viewport.size = screen_size
	_viewport.disable_3d = true
	_viewport.transparent_bg = false
	_viewport.gui_disable_input = true
	_viewport.canvas_item_default_texture_filter = 		Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)

	screen = Control.new()
	screen.set_script(screen_script)
	screen.size = screen_size
	screen.sim = sim
	screen.boot_title = boot_title
	if "crisis" in screen:
		screen.crisis = crisis
	if "room" in screen:
		screen.room = room
	if "mode" in screen:
		screen.mode = screen_mode
	_viewport.add_child(screen)

	_lcd = ShaderMaterial.new()
	_lcd.shader = LCD_SHADER
	_lcd.set_shader_parameter("screen_tex", _viewport.get_texture())
	_lcd.set_shader_parameter("power", 0.0)
	_lcd.set_shader_parameter("uv_matrix", uv[0])
	_lcd.set_shader_parameter("uv_offset", uv[1])
	found.set_surface_override_material(surface, _lcd)

## Mide la superficie (centro, normal, tamano en metros) y devuelve el mapeo
## UV -> pantalla, para que el contenido caiga derecho sea cual sea el
## desempaquetado del modelo. Es la misma cuenta que hace info_monitor.gd.
func _measure(mi: MeshInstance3D, surface: int) -> Array:
	var arrays := mi.mesh.surface_get_arrays(surface)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	if verts.size() < 3 or uvs.size() < 3:
		push_warning("ScreenPanel %s: la superficie no tiene UV" % name)
		return [Vector4(1, 0, 0, 1), Vector2.ZERO]
	var world := PackedVector3Array()
	var center := Vector3.ZERO
	for v in verts:
		var w: Vector3 = mi.global_transform * v
		world.append(w)
		center += w
	center /= verts.size()
	var normal := (world[1] - world[0]).cross(world[2] - world[0]).normalized()
	var cam := get_viewport().get_camera_3d()
	if cam and normal.dot(cam.global_position - center) < 0.0:
		normal = -normal
	var up := (Vector3.UP - normal * Vector3.UP.dot(normal)).normalized()
	var right := up.cross(normal)
	_center = center
	_normal = normal
	_up = up

	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for w in world:
		var p := w - center
		min_x = minf(min_x, p.dot(right))
		max_x = maxf(max_x, p.dot(right))
		min_y = minf(min_y, p.dot(up))
		max_y = maxf(max_y, p.dot(up))
	_width_m = maxf(max_x - min_x, 0.0001)
	_height_m = maxf(max_y - min_y, 0.0001)
	var st := PackedVector2Array()
	for w in world:
		var p := w - center
		st.append(Vector2((p.dot(right) - min_x) / _width_m,
			(max_y - p.dot(up)) / maxf(max_y - min_y, 0.0001)))
	var d := Transform2D(uvs[1] - uvs[0], uvs[2] - uvs[0], Vector2.ZERO)
	var sm := Transform2D(st[1] - st[0], st[2] - st[0], Vector2.ZERO)
	var a := sm * d.affine_inverse()
	return [Vector4(a.x.x, a.y.x, a.x.y, a.y.y), st[0] - a.basis_xform(uvs[0])]

## La camara queda de frente y a la distancia justa para que la pantalla mida
## screen_size.x pixeles de ancho: a esa escala el texto se lee.
func _register_view() -> void:
	if views == null or view_name.is_empty() or _lcd == null:
		return
	var cam: Camera3D = views.camera
	if cam == null:
		return
	var tan_half := tan(deg_to_rad(cam.fov * 0.5))
	# 180 filas es la resolucion interna del juego (pixel_display.gd).
	var dist := 180.0 * _width_m / (screen_size.x * 2.0 * tan_half)
	var px_per_m := screen_size.x / _width_m
	var pos := _center + _normal * dist - _up * (focus_raise_px / px_per_m)
	views.register_view(view_name, Transform3D(Basis.looking_at(-_normal, _up), pos),
		parent_view)

func power_on() -> void:
	if powered or _lcd == null:
		return
	powered = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_lcd.set_shader_parameter("sweep", 0.0)
	var t := create_tween()
	for p in [0.6, 0.1, 0.9, 0.3, 1.0]:
		t.tween_callback(_lcd.set_shader_parameter.bind("power", p))
		t.tween_interval(0.05)
	await t.finished
	screen.power_on()
	var s := create_tween()
	s.tween_method(func(v: float) -> void:
		_lcd.set_shader_parameter("sweep", v), 0.0, 1.0, 0.35)
