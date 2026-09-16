extends StaticBody3D

# Monitor CRT: enciende, corre la terminal de arranque, espera el clic en
# "INITIALIZE SYSTEMS", se apaga y el personaje "levanta la mirada". La camara
# no se mueve: el monitor hace el movimiento inverso (look_illusion.gd).
#
# pixel_display.gd llama on_pointer_move / on_pointer_exit / on_clicked con el
# punto de impacto del rayo; aqui se convierte a pixeles de la pantalla.

## Se emite cuando la pantalla termina de apagarse (antes de mirar arriba).
signal screen_off
## Se emite cuando el personaje ya levanto la mirada. Punto de enganche para
## los eventos siguientes (laseres, agujero negro...).
signal view_cleared

## Nodo con look_illusion.gd que saca el monitor de cuadro tras el apagado.
@export var look_illusion: Node
@export var look_delay: float = 0.35
## Resolucion interna de la pantalla. 180x136 = el tamano que ocupa el panel
## en la escena a 180 px de alto: 1 texel ~ 1 pixel, el texto queda nitido.
@export var screen_size: Vector2i = Vector2i(180, 136)
@export var phosphor: Color = Color(1.0, 0.66, 0.12)
@export var power_on_delay: float = 0.3
## Luz que la pantalla proyecta sobre la carcasa y el entorno (opcional).
@export var screen_light: OmniLight3D

enum State { OFF, BOOTING, MENU, SHUTTING_DOWN, GONE }

var _state: State = State.OFF
var _panel: MeshInstance3D
var _material: ShaderMaterial
var _terminal: Control
var _half_extents: Vector2
var _plane_z: float
var _light_energy: float = 0.0
var _last_hit: Variant = null

func _ready() -> void:
	_panel = $"monitor crt panel".find_children("*", "MeshInstance3D")[0]
	if screen_light:
		_light_energy = screen_light.light_energy
		screen_light.light_color = phosphor
	_build_screen()
	_set_collapse(1.0)
	_power_on()

func _build_screen() -> void:
	var vp := SubViewport.new()
	vp.name = "ScreenViewport"
	vp.size = screen_size
	vp.disable_3d = true
	vp.gui_disable_input = true
	vp.transparent_bg = false
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)

	_terminal = Control.new()
	_terminal.set_script(load("res://crt_terminal.gd"))
	_terminal.phosphor = phosphor
	_terminal.size = screen_size
	vp.add_child(_terminal)
	_terminal.boot_finished.connect(_on_boot_finished)

	var aabb := _panel.mesh.get_aabb()
	_half_extents = Vector2(
		maxf(absf(aabb.position.x), absf(aabb.end.x)),
		maxf(absf(aabb.position.y), absf(aabb.end.y)))
	# El borde del vidrio es la parte mas hundida: la cara trasera del AABB.
	_plane_z = aabb.position.z

	_material = ShaderMaterial.new()
	_material.shader = load("res://crt_screen.gdshader")
	_material.set_shader_parameter("screen_tex", vp.get_texture())
	_material.set_shader_parameter("half_extents", _half_extents)
	_material.set_shader_parameter("screen_size", Vector2(screen_size))
	_material.set_shader_parameter("plane_z", _plane_z)
	_panel.material_override = _material

# --- Secuencia -------------------------------------------------------------

func _power_on() -> void:
	_state = State.BOOTING
	await get_tree().create_timer(power_on_delay).timeout
	_terminal.start_boot()
	var t := create_tween()
	t.tween_method(_set_collapse, 1.0, 0.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _on_boot_finished() -> void:
	_state = State.MENU
	# Si el puntero ya estaba sobre el boton, resaltarlo sin esperar a que se mueva.
	if _last_hit != null:
		on_pointer_move(_last_hit)

func _shut_down() -> void:
	_state = State.SHUTTING_DOWN
	_set_hover(false)
	_terminal.pressed = true
	await get_tree().create_timer(0.14).timeout
	_terminal.pressed = false

	var t := create_tween()
	t.tween_method(_set_collapse, 0.0, 1.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await t.finished
	_terminal.blank()
	screen_off.emit()

	await get_tree().create_timer(look_delay).timeout
	_state = State.GONE
	if look_illusion:
		look_illusion.play()
		await look_illusion.finished
	view_cleared.emit()

func _set_collapse(value: float) -> void:
	_material.set_shader_parameter("collapse", value)
	if screen_light:
		screen_light.light_energy = _light_energy * (1.0 - value)

# --- Puntero ---------------------------------------------------------------

func on_pointer_move(hit_position: Vector3) -> void:
	_last_hit = hit_position
	_set_hover(_is_on_button(hit_position))

func on_pointer_exit() -> void:
	_last_hit = null
	_set_hover(false)

func on_clicked(hit_position: Vector3) -> void:
	if _state == State.MENU and _is_on_button(hit_position):
		_shut_down()

func _set_hover(value: bool) -> void:
	var active := value and _state == State.MENU
	if _terminal.hovered == active:
		return
	_terminal.hovered = active
	Input.set_default_cursor_shape(
		Input.CURSOR_POINTING_HAND if active else Input.CURSOR_ARROW)

func _is_on_button(hit_position: Vector3) -> bool:
	if _state != State.MENU:
		return false
	# Misma proyeccion que el shader: el punto se lleva, por el rayo de la
	# camara, al plano de referencia; luego local XY -> UV -> texel.
	var to_local := _panel.global_transform.affine_inverse()
	var local := to_local * hit_position
	var camera := get_viewport().get_camera_3d()
	if camera:
		var cam := to_local * camera.global_position
		var denom := cam.z - local.z
		if absf(denom) > 0.0001:
			local = cam + (local - cam) * ((cam.z - _plane_z) / denom)
	var uv := Vector2(local.x / _half_extents.x, -local.y / _half_extents.y) * 0.5 \
		+ Vector2(0.5, 0.5)
	var px := Vector2i((uv * Vector2(screen_size)).floor())
	# Un par de texels de tolerancia: el boton es chico en pantalla.
	return _terminal.button_rect.grow(2).has_point(px)
