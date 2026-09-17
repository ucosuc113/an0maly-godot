extends "res://scripts/mesh_interactable.gd"

# Monitor de telemetria colgado en la sala. Va como StaticBody hijo del modelo
# (model = ".."). Busca la superficie de la pantalla (screen_material), le
# pone un SubViewport con el contenido (screen_script, monitor_screen.gd) y la
# muestra con lcd_screen.gdshader.
#
# Clic en la sala -> vista enfocada a este monitor. La vista se calcula aqui:
# la camara queda de frente a la pantalla, a la distancia justa para que cada
# pixel de la pantalla sea un pixel del juego, y se registra en
# camera_views.gd con el nombre view_name.
#
#   await monitor.power_on()     titila, barre la pantalla y arranca

const LCD_SHADER = preload("res://shaders/lcd_screen.gdshader")

## Material de la superficie de la pantalla LED.
@export var screen_material: String = "Material.022"
## Contenido (extiende monitor_screen.gd).
@export var screen_script: Script
@export var screen_size: Vector2i = Vector2i(200, 100)
@export var boot_title: String = "TELEMETRY"
## Nodo con reactor_sim.gd.
@export var sim: Node
## Nodo con control_panel.gd (para el monitor central).
@export var panel: Node
## Lasers que dibuja el esquema (monitor central).
@export var lateral_lasers: Array[Node] = []
@export var diagonal_lasers: Array[Node] = []
## Cuanto sube la pantalla en la vista enfocada (px), para no quedar debajo
## del boton BACK.
@export var focus_raise_px: int = 8

var screen: Control
var _viewport: SubViewport
var _lcd: ShaderMaterial
var _center: Vector3
var _normal: Vector3
var _up: Vector3
var _width_m: float = 1.0
var powered: bool = false

func _ready() -> void:
	super._ready()
	_build_screen()
	_register_view.call_deferred()

func _build_screen() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "ScreenViewport"
	_viewport.size = screen_size
	_viewport.disable_3d = true
	_viewport.transparent_bg = false
	_viewport.gui_disable_input = true
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	screen = Control.new()
	screen.set_script(screen_script)
	screen.size = screen_size
	screen.sim = sim
	screen.boot_title = boot_title
	if "panel" in screen:
		screen.panel = panel
	if "lateral_lasers" in screen:
		screen.lateral_lasers = lateral_lasers
		screen.diagonal_lasers = diagonal_lasers
	_viewport.add_child(screen)

	_lcd = ShaderMaterial.new()
	_lcd.shader = LCD_SHADER
	_lcd.set_shader_parameter("screen_tex", _viewport.get_texture())
	_lcd.set_shader_parameter("power", 0.0)
	for mi: MeshInstance3D in _meshes():
		for s in mi.mesh.get_surface_count():
			var base := mi.mesh.surface_get_material(s)
			if base == null or base.resource_name != screen_material:
				continue
			_measure(mi, s)
			mi.set_surface_override_material(s, _lcd)
			return
	push_warning("Monitor %s: no encontre la superficie %s" % [name, screen_material])

## Centro, normal, orientacion y tamano de la pantalla, y el mapeo del UV.
func _measure(mi: MeshInstance3D, s: int) -> void:
	var arrays := mi.mesh.surface_get_arrays(s)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var world := PackedVector3Array()
	_center = Vector3.ZERO
	for v in verts:
		var w := mi.global_transform * v
		world.append(w)
		_center += w
	_center /= verts.size()
	# Normal hacia la sala (hacia la camara principal).
	_normal = (world[1] - world[0]).cross(world[2] - world[0]).normalized()
	var cam := get_viewport().get_camera_3d()
	if cam and _normal.dot(cam.global_position - _center) < 0.0:
		_normal = -_normal
	_up = (Vector3.UP - _normal * Vector3.UP.dot(_normal)).normalized()
	var right := _up.cross(_normal)

	# Coordenadas de pantalla de cada vertice: x hacia la derecha, y hacia
	# abajo, 0..1.
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for w in world:
		var p := w - _center
		min_x = minf(min_x, p.dot(right))
		max_x = maxf(max_x, p.dot(right))
		min_y = minf(min_y, p.dot(_up))
		max_y = maxf(max_y, p.dot(_up))
	_width_m = max_x - min_x
	var st := PackedVector2Array()
	for w in world:
		var p := w - _center
		st.append(Vector2((p.dot(right) - min_x) / (max_x - min_x),
			(max_y - p.dot(_up)) / (max_y - min_y)))
	# Afin UV -> pantalla con tres vertices no alineados.
	var d := Transform2D(uvs[1] - uvs[0], uvs[2] - uvs[0], Vector2.ZERO)
	var sm := Transform2D(st[1] - st[0], st[2] - st[0], Vector2.ZERO)
	var a := sm * d.affine_inverse()
	var offset := st[0] - a.basis_xform(uvs[0])
	# basis_xform(uv) = x * uv.x + y * uv.y: filas (x.x, y.x) y (x.y, y.y).
	_lcd.set_shader_parameter("uv_matrix", Vector4(a.x.x, a.y.x, a.x.y, a.y.y))
	_lcd.set_shader_parameter("uv_offset", offset)

func _register_view() -> void:
	if views == null or view_name.is_empty():
		return
	var cam: Camera3D = views.camera
	var tan_half := tan(deg_to_rad(cam.fov * 0.5))
	var rows := 180.0
	# Distancia a la que la pantalla mide screen_size.x pixeles de ancho.
	var dist := rows * _width_m / (screen_size.x * 2.0 * tan_half)
	var px_per_m := screen_size.x / _width_m
	var pos := _center + _normal * dist - _up * (focus_raise_px / px_per_m)
	var xf := Transform3D(Basis.looking_at(-_normal, _up), pos)
	views.register_view(view_name, xf)

# --- Encendido --------------------------------------------------------------------

func power_on() -> void:
	if powered:
		return
	powered = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if views and views.sfx:
		views.sfx.play("monitor_on", 0.0, randf_range(0.95, 1.05))
	# Tirones de la retroiluminacion y barrido de arriba a abajo.
	_lcd.set_shader_parameter("sweep", 0.0)
	var t := create_tween()
	for p in [0.6, 0.1, 0.9, 0.3, 1.0]:
		t.tween_callback(_lcd.set_shader_parameter.bind("power", p))
		t.tween_interval(0.05)
	await t.finished
	screen.power_on()
	var s := create_tween()
	s.tween_method(func(v: float) -> void: _lcd.set_shader_parameter("sweep", v), 0.0, 1.0, 0.35)
	await s.finished
