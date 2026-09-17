extends TextureRect

# El SubViewport se escala SIEMPRE por un factor entero. Un 3.6x hace que unos
# texeles midan 3 px y otros 4: bordes de grosor irregular y hormigueo al
# moverse. Eso es lo que hace que se lea como "baja resolucion" en vez de pixel
# art, por mucho que la resolucion interna sea baja.

@export var pixel_viewport: SubViewport
## Nodo con camera_views.gd (opcional): en pantalla dividida, el rayo sale de
## la camara que haya bajo el puntero.
@export var views: Node

## Resolucion interna objetivo. En modo fill_window solo manda la altura.
@export var base_size: Vector2i = Vector2i(320, 180)

## Si esta activo, el ANCHO interno crece hasta cubrir la ventana (pixel
## cuadrado, sin barras laterales). Si no, se fija a base_size y se centra.
@export var fill_window: bool = true

# La ALTURA interna es siempre base_size.y, en cualquier modo. La camara
# mantiene el FOV vertical, asi que el tamano en pixeles de todo lo que se ve
# depende solo de esa altura: la pantalla del CRT (180x136 texels) mide 1:1
# en la escena solo si hay exactamente 180 filas. Si la escala entera no cuadra
# con la ventana (p. ej. 1004 px de alto -> 5.58x), se redondea y el sobrante
# se recorta arriba/abajo (o quedan franjas finas), en vez de cambiar de
# resolucion y que la textura pierda filas.

var _scale: int = 1
var _hovered: Object
## Objeto que se esta arrastrando (on_drag_start devolvio true) y la camara
## con la que empezo: el rayo sigue saliendo de ella aunque el puntero cruce a
## la otra mitad de la pantalla dividida.
var _dragging: Object
var _drag_camera: Camera3D
var _drag_offset: Vector2

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

	var vp_size: Vector2i = base_size
	if fill_window:
		vp_size.x = ceili(float(win.x) / float(_scale))

	if pixel_viewport.size != vp_size:
		pixel_viewport.size = vp_size
		texture = pixel_viewport.get_texture()

	var rect: Vector2i = vp_size * _scale
	position = Vector2((win - rect) / 2)
	size = Vector2(rect)

func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouse:
		return
	if _dragging and _handle_drag(event):
		return
	# Primero la UI que vive dentro del viewport pixelado (menu). Si la consume,
	# no se lanza el rayo 3D.
	if _forward_to_viewport(event):
		if event is InputEventMouseMotion:
			_set_hovered(null, Vector3.ZERO)
		return

	if event is InputEventMouseMotion:
		_update_hover(event.position)
		return
	if not (event is InputEventMouseButton and event.pressed):
		return

	match event.button_index:
		MOUSE_BUTTON_LEFT:
			var result := _pick(event.position)
			if not result:
				return
			var collider: Object = result.collider
			if collider.has_method("on_drag_start") and collider.on_drag_start(result.position):
				_dragging = collider
				var view := _camera_for(event.position / float(_scale))
				_drag_camera = view.get("camera")
				_drag_offset = event.position / float(_scale) - view.get("position", Vector2.ZERO)
			elif collider.has_method("on_clicked"):
				collider.on_clicked(result.position)
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			var result := _pick(event.position)
			if result and result.collider.has_method("on_wheel"):
				var direction := 1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1
				result.collider.on_wheel(result.position, direction)

## Mientras hay un arrastre, el movimiento y el soltar van al objeto
## capturado (sin hover ni UI). Devuelve true si consumio el evento.
func _handle_drag(event: InputEventMouse) -> bool:
	if not is_instance_valid(_dragging) or get_tree().paused:
		_end_drag()
		return false
	if event is InputEventMouseMotion:
		var p: Vector2 = event.position / float(_scale) - _drag_offset
		if _drag_camera:
			_dragging.on_drag(_drag_camera.project_ray_origin(p), _drag_camera.project_ray_normal(p))
		return true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and not event.pressed:
		_end_drag()
		return true
	return false

func _end_drag() -> void:
	if is_instance_valid(_dragging) and _dragging.has_method("on_drag_end"):
		_dragging.on_drag_end()
	_dragging = null
	_drag_camera = null

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_set_hovered(null, Vector3.ZERO)
		# Mover el puntero "fuera" del viewport para que los botones suelten el hover.
		var away := InputEventMouseMotion.new()
		away.position = Vector2(-1000, -1000)
		away.global_position = away.position
		pixel_viewport.push_input(away, true)

## Reenvia el evento al SubViewport en sus coordenadas (texels). Devuelve true
## si el puntero esta sobre un Control de ese viewport.
##
## No sirve is_input_handled(): con physics_object_picking activo, Godot marca
## como "handled" todo evento de mouse que entra al viewport (lo encola para el
## picking), haya UI debajo o no, y el rayo al CRT nunca se lanzaria.
func _forward_to_viewport(event: InputEventMouse) -> bool:
	var local := event.duplicate() as InputEventMouse
	local.position = event.position / float(_scale)
	local.global_position = local.position
	if local is InputEventMouseMotion:
		local.relative = event.relative / float(_scale)
		local.screen_relative = event.screen_relative
	pixel_viewport.push_input(local, true)
	return pixel_viewport.gui_get_hovered_control() != null

## Avisa al objeto bajo el puntero (on_pointer_move) y al que se deja atras
## (on_pointer_exit). Ambos metodos son opcionales en el collider.
func _update_hover(screen_position: Vector2) -> void:
	var result := _pick(screen_position)
	if result:
		_set_hovered(result.collider, result.position)
	else:
		_set_hovered(null, Vector3.ZERO)

func _set_hovered(collider: Object, hit_position: Vector3) -> void:
	if collider != _hovered and is_instance_valid(_hovered) \
			and _hovered.has_method("on_pointer_exit"):
		_hovered.on_pointer_exit()
	_hovered = collider
	if collider and collider.has_method("on_pointer_move"):
		collider.on_pointer_move(hit_position)

func _pick(screen_position: Vector2) -> Dictionary:
	# screen_position es local al TextureRect, que mide justo vp_size * _scale.
	# Una sola division: el mapeo no puede desincronizarse del dibujado.
	var mapped_position: Vector2 = screen_position / float(_scale)
	var viewport_size := Vector2(pixel_viewport.size)
	if mapped_position.x < 0.0 or mapped_position.y < 0.0 \
			or mapped_position.x >= viewport_size.x or mapped_position.y >= viewport_size.y:
		return {}

	var view := _camera_for(mapped_position)
	var camera: Camera3D = view.get("camera")
	mapped_position = view.get("position", mapped_position)
	if camera == null:
		return {}

	var ray_origin := camera.project_ray_origin(mapped_position)
	var ray_direction := camera.project_ray_normal(mapped_position)

	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_direction * 1000.0)
	return pixel_viewport.find_world_3d().direct_space_state.intersect_ray(query)

## Camara bajo un punto del PixelViewport y el punto en su propio viewport.
func _camera_for(mapped_position: Vector2) -> Dictionary:
	if views:
		return views.camera_at(mapped_position)
	return {"camera": pixel_viewport.get_camera_3d(), "position": mapped_position}
