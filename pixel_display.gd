extends TextureRect

# El SubViewport se escala SIEMPRE por un factor entero. Un 3.6x hace que unos
# texeles midan 3 px y otros 4: bordes de grosor irregular y hormigueo al
# moverse. Eso es lo que hace que se lea como "baja resolucion" en vez de pixel
# art, por mucho que la resolucion interna sea baja.

@export var pixel_viewport: SubViewport

## Resolucion interna objetivo. En modo fill_window solo manda la altura.
@export var base_size: Vector2i = Vector2i(320, 180)

## Si esta activo, la resolucion interna crece hasta cubrir la ventana entera
## manteniendo el pixel cuadrado (sin barras negras, se ve un pelin mas de
## escena). Si no, se fija a base_size y se centra con barras.
@export var fill_window: bool = true

var _scale: int = 1
var _hovered: Object

func _ready() -> void:
	texture = pixel_viewport.get_texture()
	mouse_filter = Control.MOUSE_FILTER_STOP
	pixel_viewport.physics_object_picking = true

	# Sin filtrado y sin estirado no entero: el TextureRect mide exactamente
	# tamano_viewport * _scale, asi que STRETCH_SCALE es 1 texel -> k x k px.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	stretch_mode = TextureRect.STRETCH_SCALE
	set_anchors_preset(Control.PRESET_TOP_LEFT)

	get_viewport().size_changed.connect(_update_layout)
	_update_layout()

func _update_layout() -> void:
	var win: Vector2i = Vector2i(get_viewport_rect().size)
	if win.x <= 0 or win.y <= 0 or base_size.y <= 0:
		return

	_scale = maxi(1, int(round(float(win.y) / float(base_size.y))))

	var vp_size: Vector2i
	if fill_window:
		vp_size = Vector2i(
			ceili(float(win.x) / float(_scale)),
			ceili(float(win.y) / float(_scale)))
	else:
		vp_size = base_size

	if pixel_viewport.size != vp_size:
		pixel_viewport.size = vp_size
		texture = pixel_viewport.get_texture()

	var rect: Vector2i = vp_size * _scale
	position = Vector2((win - rect) / 2)
	size = Vector2(rect)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_update_hover(event.position)
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return

	var result := _pick(event.position)
	if result and result.collider.has_method("on_clicked"):
		result.collider.on_clicked(result.position)

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_set_hovered(null, Vector3.ZERO)

## Avisa al objeto bajo el puntero (on_pointer_move) y al que se deja atras
## (on_pointer_exit). Ambos metodos son opcionales en el collider.
func _update_hover(screen_position: Vector2) -> void:
	var result := _pick(screen_position)
	if result:
		_set_hovered(result.collider, result.position)
	else:
		_set_hovered(null, Vector3.ZERO)

func _set_hovered(collider: Object, hit_position: Vector3) -> void:
	if collider != _hovered and is_instance_valid(_hovered) 			and _hovered.has_method("on_pointer_exit"):
		_hovered.on_pointer_exit()
	_hovered = collider
	if collider and collider.has_method("on_pointer_move"):
		collider.on_pointer_move(hit_position)

func _pick(screen_position: Vector2) -> Dictionary:
	# screen_position es local al TextureRect, que mide justo vp_size * _scale.
	# Una sola division: el mapeo no puede desincronizarse del dibujado.
	var mapped_position: Vector2 = screen_position / float(_scale)
	var viewport_size := Vector2(pixel_viewport.size)
	if mapped_position.x < 0.0 or mapped_position.y < 0.0 			or mapped_position.x >= viewport_size.x or mapped_position.y >= viewport_size.y:
		return {}

	var camera := pixel_viewport.get_camera_3d()
	if camera == null:
		return {}

	var ray_origin := camera.project_ray_origin(mapped_position)
	var ray_direction := camera.project_ray_normal(mapped_position)

	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_direction * 1000.0)
	return pixel_viewport.find_world_3d().direct_space_state.intersect_ray(query)
