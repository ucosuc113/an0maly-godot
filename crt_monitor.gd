extends StaticBody3D

# Monitor CRT: enciende, corre la terminal de arranque, espera el clic en
# "INITIALIZE SYSTEMS", se apaga y el personaje "levanta la mirada". La camara
# no se mueve: el monitor hace el movimiento inverso (look_illusion.gd).
#
# Despues sirve de pantalla para SETTINGS: open_settings() lo trae de vuelta
# ("baja la mirada"), enciende la pagina de ajustes, y BACK repite el apagado.
#
# pixel_display.gd llama on_pointer_move / on_pointer_exit / on_clicked /
# on_wheel con el punto de impacto del rayo; aqui se convierte a pixeles de la
# pantalla y se le pasa a la terminal.

## Se emite cuando la pantalla termina de apagarse (antes de mirar arriba).
signal screen_off
## Se emite cada vez que el personaje termina de levantar la mirada (tras
## INITIALIZE y tras BACK). El menu principal escucha esta senal.
signal view_cleared

## Nodo con look_illusion.gd que saca/trae el monitor de cuadro.
@export var look_illusion: Node
## Nodo con game_settings.gd: lo que muestra y edita la pagina SETTINGS.
@export var settings: Node
@export var look_delay: float = 0.35
## Resolucion interna de la pantalla. 180x136 = el tamano que ocupa el panel
## en la escena a 180 px de alto: 1 texel ~ 1 pixel, el texto queda nitido.
@export var screen_size: Vector2i = Vector2i(180, 136)
@export var phosphor: Color = Color(1.0, 0.66, 0.12)
@export var power_on_delay: float = 0.3
## Luz que la pantalla proyecta sobre la carcasa y el entorno (opcional).
@export var screen_light: OmniLight3D

enum State { OFF, BOOTING, INTERACTIVE, SHUTTING_DOWN, GONE, RETURNING }

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
	if settings:
		settings.changed.connect(_on_setting_changed)
		_on_setting_changed("reduce_flashing", settings.get_value("reduce_flashing"))
	_set_collapse(1.0)
	_power_on(_terminal.start_boot)

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
	_terminal.settings = settings
	_terminal.size = screen_size
	vp.add_child(_terminal)
	_terminal.page_ready.connect(_on_page_ready)

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

# --- Secuencias ------------------------------------------------------------

## Enciende la pantalla y arranca la secuencia de la terminal (start_boot,
## start_settings...). La pagina avisa con page_ready cuando es interactiva.
func _power_on(sequence: Callable) -> void:
	_state = State.BOOTING
	await get_tree().create_timer(power_on_delay).timeout
	sequence.call()
	var t := create_tween()
	t.tween_method(_set_collapse, 1.0, 0.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _on_page_ready() -> void:
	_state = State.INTERACTIVE
	# Si el puntero ya estaba encima de algo, resaltarlo sin esperar a que se mueva.
	if _last_hit != null:
		on_pointer_move(_last_hit)

## Trae el monitor de vuelta a cuadro y abre la pagina de ajustes.
func open_settings() -> void:
	if _state != State.GONE:
		return
	_state = State.RETURNING
	if look_illusion:
		look_illusion.play_back()
		await look_illusion.finished
	_power_on(_terminal.start_settings)

func _shut_down() -> void:
	_state = State.SHUTTING_DOWN
	_set_cursor(false)
	await get_tree().create_timer(0.14).timeout
	_terminal.pressed_id = ""

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

func _on_setting_changed(id: String, value: Variant) -> void:
	if id == "reduce_flashing":
		# La linea del apagado deja de ser un destello casi blanco.
		_material.set_shader_parameter("collapse_color",
			phosphor.darkened(0.3) if value else Color(1.0, 0.92, 0.75))

# --- Puntero ---------------------------------------------------------------

func on_pointer_move(hit_position: Vector3) -> void:
	_last_hit = hit_position
	if _state != State.INTERACTIVE:
		return
	_set_cursor(_terminal.hover(_to_screen_px(hit_position)) != "")

func on_pointer_exit() -> void:
	_last_hit = null
	if _state == State.INTERACTIVE:
		_terminal.hover_id = ""
	_set_cursor(false)

func on_clicked(hit_position: Vector3) -> void:
	if _state != State.INTERACTIVE:
		return
	match _terminal.click(_to_screen_px(hit_position)):
		"initialize", "back":
			_shut_down()

func on_wheel(hit_position: Vector3, direction: int) -> void:
	if _state == State.INTERACTIVE:
		_terminal.wheel(_to_screen_px(hit_position), direction)

func _set_cursor(pointing: bool) -> void:
	Input.set_default_cursor_shape(
		Input.CURSOR_POINTING_HAND if pointing else Input.CURSOR_ARROW)

func _to_screen_px(hit_position: Vector3) -> Vector2i:
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
	return Vector2i((uv * Vector2(screen_size)).floor())
