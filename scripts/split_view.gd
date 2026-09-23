extends Control

# Pantalla dividida: arriba sigue la camara principal y abajo (ratio del alto)
# una segunda camara del mismo mundo 3D. Vive en un CanvasLayer dentro del
# PixelViewport, asi que la franja de abajo pasa por el mismo pixelado,
# cuantizacion y dithering que el resto.
#
# La separacion es una linea gris con puntas naranjas y una pestana con la
# etiqueta, que se abre desde el centro; la franja de abajo lleva esquinas
# naranjas como un visor. camera_views.gd la abre/cierra con la pantalla
# tapada; pixel_display.gd le pregunta que camara hay bajo el puntero.

const PixelFont = preload("res://scripts/pixel_font.gd")
const REVEAL_SHADER = preload("res://shaders/dither_reveal.gdshader")

## Fraccion del alto para la franja de abajo.
@export_range(0.1, 0.9, 0.01) var ratio: float = 0.35:
	set(value):
		ratio = value
		_layout()
@export var fov: float = 20.5
## Exposicion de la franja respecto a la de la sala: vista desde arriba, la
## cubierta del panel recibe las luces de frente y se quemaba en blanco.
@export_range(0.1, 2.0, 0.05) var exposure_scale: float = 0.7
@export var label: String = "CONTROL PANEL"

@export_group("Look")
@export var line_color: Color = Color(0.3, 0.3, 0.33)
@export var label_color: Color = Color(0.5, 0.5, 0.53)
@export var accent_color: Color = Color(1.0, 0.52, 0.14)

var camera: Camera3D

## Capa del tapon: solo lo ve la camara principal.
const BLOCKER_LAYER := 1 << 19
## Filas de margen bajo la linea (la sacudida de camara no llega a destaparlo).
const BLOCKER_MARGIN := 3
## Tapon negro pegado a la camara principal sobre lo que tapa la franja: la GPU
## descarta por profundidad los pixeles que igual no se iban a ver.
var _blocker: MeshInstance3D
## Calidad baja: la franja se redibuja un frame si y otro no.
var half_rate: bool = false

var _viewport: SubViewport
var _pane: TextureRect
var _overlay: Control
var _overlay_material: ShaderMaterial
var _open_t: float = 0.0
var _is_open: bool = false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Sin mundo propio: hereda el World3D del PixelViewport.
	_viewport = SubViewport.new()
	_viewport.name = "PaneViewport"
	_viewport.disable_3d = false
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	for q in 4:
		_viewport.set_positional_shadow_atlas_quadrant_subdiv(q, Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_16)
	add_child(_viewport)
	camera = Camera3D.new()
	camera.name = "PaneCamera"
	camera.fov = fov
	camera.cull_mask &= ~BLOCKER_LAYER
	camera.current = true
	_viewport.add_child(camera)

	_pane = TextureRect.new()
	_pane.name = "Pane"
	_pane.texture = _viewport.get_texture()
	_pane.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_pane.stretch_mode = TextureRect.STRETCH_SCALE
	_pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pane)
	move_child(_pane, 0)

	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay_material = ShaderMaterial.new()
	_overlay_material.shader = REVEAL_SHADER
	_overlay.material = _overlay_material
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	# Debajo de los hijos de la escena (el HUD va encima de todo).
	move_child(_overlay, 1)

	visible = false
	resized.connect(_layout)
	_layout()

func is_open() -> bool:
	return _is_open

## 0..1: cuanto va la animacion de apertura de la division.
func open_progress() -> float:
	return _open_t

## Fila donde empieza la franja de abajo (debajo de la linea).
func pane_top() -> int:
	return int(size.y) - _pane_height()

func _pane_height() -> int:
	return int(round(size.y * ratio))

## Muestra la franja con la camara en xf, al instante (con la pantalla tapada).
func open(xf: Transform3D) -> void:
	camera.global_transform = xf
	camera.fov = fov
	_apply_exposure()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_is_open = true
	visible = true
	_set_open(0.0)

## Abre la linea desde el centro y materializa la etiqueta.
func animate_in() -> void:
	var t := create_tween()
	t.tween_method(_set_open, 0.0, 1.0, 0.45) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	await t.finished

## La camara de la franja usa una copia del Environment de la sala con menos
## exposicion (se crea la primera vez).
func _apply_exposure() -> void:
	if camera.environment != null or is_equal_approx(exposure_scale, 1.0):
		return
	var world_env := camera.get_world_3d().environment
	if world_env == null:
		return
	var env := world_env.duplicate() as Environment
	env.tonemap_exposure *= exposure_scale
	camera.environment = env

func close() -> void:
	_is_open = false
	visible = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if _blocker:
		_blocker.visible = false

func _process(_delta: float) -> void:
	if _is_open:
		_update_blocker()
		if half_rate:
			_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE \
				if Engine.get_process_frames() % 2 == 0 else SubViewport.UPDATE_DISABLED
		elif _viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS:
			_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

func _update_blocker() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam == camera or cam.projection != Camera3D.PROJECTION_PERSPECTIVE:
		return
	if _blocker == null or _blocker.get_parent() != cam:
		if _blocker:
			_blocker.queue_free()
		_blocker = MeshInstance3D.new()
		_blocker.mesh = QuadMesh.new()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color.BLACK
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.render_priority = Material.RENDER_PRIORITY_MAX
		_blocker.material_override = m
		_blocker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_blocker.layers = BLOCKER_LAYER
		cam.add_child(_blocker)
	var h := size.y
	var d := cam.near * 1.5
	var half := d * tan(deg_to_rad(cam.fov) * 0.5)
	var top := (1.0 - 2.0 * (pane_top() + BLOCKER_MARGIN) / h) * half
	var bottom := -half * 1.2
	var width := half * size.x / h * 2.4
	var quad := _blocker.mesh as QuadMesh
	var want := Vector2(width, top - bottom)
	if not quad.size.is_equal_approx(want):
		quad.size = want
	_blocker.position = Vector3(cam.h_offset, cam.v_offset + (top + bottom) * 0.5, -d)
	_blocker.visible = true

## Camara y posicion (en su viewport) para un punto del PixelViewport.
func camera_at(pos: Vector2) -> Dictionary:
	if not _is_open or pos.y < pane_top():
		return {}
	return {"camera": camera, "position": pos - Vector2(0, pane_top())}

func _set_open(v: float) -> void:
	_open_t = v
	# La linea (la dibuja este nodo) va primero; el resto se materializa
	# cuando ya va por la mitad.
	_overlay_material.set_shader_parameter("progress", clampf((v - 0.4) / 0.6, 0.0, 1.0))
	queue_redraw()
	_overlay.queue_redraw()

func _layout() -> void:
	if _pane == null:
		return
	var w := int(size.x)
	var h := _pane_height()
	var vs := Vector2i(maxi(w, 1), maxi(h, 1))
	if _viewport.size != vs:
		_viewport.size = vs
	_pane.position = Vector2(0, pane_top())
	_pane.size = Vector2(vs)
	queue_redraw()
	_overlay.queue_redraw()

## Banda negra y linea que se abre desde el centro (sin disolvente).
func _draw() -> void:
	var w := int(size.x)
	var y := pane_top()
	draw_rect(Rect2(0, y - 2, w, 3), Color.BLACK)
	var lw: int = int(round(w * _open_t / 2.0)) * 2
	if lw > 0:
		draw_rect(Rect2((w - lw) / 2, y - 1, lw, 1), line_color)

## Puntas, pestana y esquinas de visor (con disolvente).
func _draw_overlay() -> void:
	var w := int(size.x)
	var y := pane_top()

	# Puntas naranjas.
	_overlay.draw_rect(Rect2(0, y - 1, 8, 1), accent_color)
	_overlay.draw_rect(Rect2(w - 8, y - 1, 8, 1), accent_color)

	# Pestana con la etiqueta, montada sobre la linea.
	if not label.is_empty():
		var tw := PixelFont.text_width(label)
		var tab := Rect2i((w - tw) / 2 - 7, y - 6, tw + 14, 11)
		_overlay.draw_rect(tab, Color.BLACK)
		_overlay.draw_rect(Rect2(tab.position.x, tab.position.y, tab.size.x, 1), line_color)
		_overlay.draw_rect(Rect2(tab.position.x, tab.end.y - 1, tab.size.x, 1), line_color)
		_overlay.draw_rect(Rect2(tab.position.x, tab.position.y, 1, tab.size.y), line_color)
		_overlay.draw_rect(Rect2(tab.end.x - 1, tab.position.y, 1, tab.size.y), line_color)
		# Marcas naranjas a los lados de la pestana.
		_overlay.draw_rect(Rect2(tab.position.x - 5, y - 1, 3, 1), accent_color)
		_overlay.draw_rect(Rect2(tab.end.x + 2, y - 1, 3, 1), accent_color)
		PixelFont.draw(_overlay, label, Vector2((w - tw) / 2, tab.position.y + 2), label_color)

	# Esquinas de visor en la franja de abajo.
	var r := Rect2i(3, y + 4, w - 6, int(size.y) - y - 7)
	var L := 5
	for corner in [r.position, Vector2i(r.end.x - 1, r.position.y),
			Vector2i(r.position.x, r.end.y - 1), r.end - Vector2i.ONE]:
		var sx := 1 if corner.x == r.position.x else -1
		var sy := 1 if corner.y == r.position.y else -1
		_overlay.draw_rect(Rect2(mini(corner.x, corner.x + sx * (L - 1)), corner.y, L, 1), accent_color)
		_overlay.draw_rect(Rect2(corner.x, mini(corner.y, corner.y + sy * (L - 1)), 1, L), accent_color)
