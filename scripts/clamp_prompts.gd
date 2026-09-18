extends Control

# Anclajes de emergencia: durante el derretimiento el agujero negro tira de
# una pieza (un cabezal, un anillo, un aspa) antes de arrancarla. Mientras la
# sacude, aparece un cerco sobre ella EN LA VISTA, no en un menu: el jugador
# tiene unos segundos para clicarlo y volver a trabar los clamps.
#
#   var p = prompts.open(pieza, 2.6, color)
#   var salvada: bool = await p.resolved
#
# El cerco se va cerrando mientras queda tiempo (los clamps bajando) y late
# mas rapido cuanto menos queda. Si la pieza no se ve (la camara esta en un
# monitor, o quedo detras), el cerco no se dibuja ni se puede clicar, pero el
# aviso sigue vivo: offscreen_count() lo usa crisis_director.gd para decirle
# al jugador que mire por el ventanal.
#
# Vive en un CanvasLayer del PixelViewport (HudLayer), asi que sus
# coordenadas son las mismas que devuelve Camera3D.unproject_position().

const PixelFont = preload("res://scripts/pixel_font.gd")

## Nodo con camera_views.gd (de ahi sale la camara y si hay cinematica).
@export var views: Node
@export var sfx: Node
@export var settings: Node
@export_group("Look")
## Lado del cerco al aparecer y al cerrarse del todo (px).
@export var box_open: int = 21
@export var box_shut: int = 9
## Area clicable alrededor del cerco (px de lado).
@export var hit_size: int = 29
@export var frame_color: Color = Color(1.0, 0.52, 0.14)
@export var urgent_color: Color = Color(1.0, 0.25, 0.2)
@export var hover_color: Color = Color(0.96, 0.95, 0.92)
@export var saved_color: Color = Color(0.45, 1.0, 0.75)
## Los primeros avisos de la partida muestran el cartel sin pasar el mouse.
@export var teach_count: int = 3

var _live: Array = []
var _shown: int = 0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## Abre un aviso sobre `target`. Devuelve el Prompt: `await p.resolved` da
## true si el jugador lo salvo.
func open(target: Node3D, window: float, tint: Color = Color.TRANSPARENT) -> Prompt:
	var p := Prompt.new()
	p.setup(self, target, window, tint if tint.a > 0.0 else frame_color)
	p.teach = _shown < teach_count
	_shown += 1
	_live.append(p)
	add_child(p)
	p.tree_exited.connect(func() -> void: _live.erase(p))
	_play("crt_hover", -8.0, 1.2)
	return p

## Cuantos avisos abiertos no se estan viendo (la camara mira a otro lado).
func offscreen_count() -> int:
	var n := 0
	for p in _live:
		if is_instance_valid(p) and not p.on_screen:
			n += 1
	return n

func live_count() -> int:
	return _live.size()

## Cierra todo sin salvar nada (al estabilizar o al entrar al climax).
func clear() -> void:
	for p in _live.duplicate():
		if is_instance_valid(p):
			p.cancel()

## El jugador puede clicar: en juego, no en medio de un corte de camara.
func interactive() -> bool:
	if views == null:
		return true
	return not views.cinematic and not views.is_busy()

func calm() -> bool:
	return settings != null and bool(settings.get_value("reduce_flashing"))

func _play(sound: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if sfx:
		sfx.play(sound, volume_db, pitch)

# --- Un aviso ------------------------------------------------------------------

class Prompt extends Control:
	## saved = el jugador lo clico a tiempo.
	signal resolved(saved: bool)

	var mgr: Control
	var target: Node3D
	## Centro de las mallas en el espacio de `target` (el origen del FBX puede
	## estar lejos de la pieza).
	var center: Vector3
	var window: float = 2.5
	var left: float = 2.5
	var tint: Color = Color.WHITE
	var teach: bool = false
	## La pieza se esta viendo (si no, no se puede clicar).
	var on_screen: bool = false

	var _done: bool = false
	var _saved: bool = false
	var _hover: bool = false
	var _fade: float = 1.0
	var _time: float = 0.0

	func setup(manager: Control, node: Node3D, seconds: float, color: Color) -> void:
		mgr = manager
		target = node
		window = maxf(seconds, 0.3)
		left = window
		tint = color.lerp(Color.WHITE, 0.25)
		center = _mesh_center(node)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = Vector2(mgr.hit_size, mgr.hit_size)
		visible = false
		mouse_entered.connect(_set_hover.bind(true))
		mouse_exited.connect(_set_hover.bind(false))
		gui_input.connect(_on_input)

	## Centro de las mallas visibles, en el espacio local de `node`.
	static func _mesh_center(node: Node3D) -> Vector3:
		var list: Array = []
		if node is MeshInstance3D:
			list.append(node)
		list.append_array(node.find_children("*", "MeshInstance3D", true, false))
		var box := AABB()
		var first := true
		var inv := node.global_transform.affine_inverse()
		for mi: MeshInstance3D in list:
			var b: AABB = inv * mi.global_transform * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
		return box.get_center() if not first else Vector3.ZERO

	func _process(delta: float) -> void:
		_time += delta
		if _done:
			# Destello de cierre y adios.
			_fade = maxf(_fade - delta * 4.0, 0.0)
			_place()
			queue_redraw()
			if _fade <= 0.0:
				queue_free()
			return
		left -= delta
		_place()
		queue_redraw()
		if left <= 0.0:
			_finish(false)

	## Sigue a la pieza en pantalla; se apaga si no se ve.
	func _place() -> void:
		var cam: Camera3D = mgr.views.camera if mgr.views else null
		if cam == null or not is_instance_valid(target) or not target.is_visible_in_tree() \
				or not mgr.interactive():
			_off()
			return
		var world: Vector3 = target.global_transform * center
		if cam.is_position_behind(world):
			_off()
			return
		var p := cam.unproject_position(world)
		var vp := get_viewport_rect().size
		var half := size * 0.5
		if p.x < half.x or p.y < half.y or p.x > vp.x - half.x or p.y > vp.y - half.y:
			_off()
			return
		position = (p - half).round()
		on_screen = true
		visible = true
		if mouse_filter != Control.MOUSE_FILTER_STOP and not _done:
			mouse_filter = Control.MOUSE_FILTER_STOP

	func _off() -> void:
		on_screen = false
		visible = false
		if _hover:
			_set_hover(false)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _set_hover(value: bool) -> void:
		value = value and not _done
		if _hover == value:
			return
		_hover = value
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if value else Input.CURSOR_ARROW)
		if value:
			mgr._play("menu_hover", -4.0)

	func _on_input(event: InputEvent) -> void:
		if _done or not on_screen:
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
				and event.pressed:
			accept_event()
			_finish(true)

	## Cierra el aviso sin salvar (estabilizacion, climax).
	func cancel() -> void:
		_finish(false)

	func _finish(saved: bool) -> void:
		if _done:
			return
		_done = true
		_saved = saved
		_set_hover(false)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resolved.emit(saved)

	# El cerco: cuatro escuadras que se cierran sobre la pieza mientras queda
	# tiempo, y una barra fina debajo con lo que falta.
	func _draw() -> void:
		var k := 1.0 - clampf(left / window, 0.0, 1.0)
		var side := int(round(lerpf(mgr.box_open, mgr.box_shut, k)))
		if _done:
			# Al salvarla se cierra de golpe; si se la llevan, se abre y se va.
			side = mgr.box_shut if _saved else int(round(lerpf(mgr.box_open, mgr.box_open + 8, 1.0 - _fade)))
		var c := Vector2i(size * 0.5)
		var r := Rect2i(c.x - side / 2, c.y - side / 2, side, side)

		var urgency := ease(k, 2.0)
		# Tipos explicitos: `mgr` es un Control generico, asi que sus colores
		# llegan sin tipo y el inferidor no puede resolverlos.
		var base: Color = mgr.frame_color
		var col: Color = base.lerp(tint, 0.25).lerp(mgr.urgent_color, urgency)
		if _hover:
			col = mgr.hover_color
		if _done:
			col = mgr.saved_color if _saved else mgr.urgent_color
		# Late mas rapido cuanto menos queda (con REDUCE FLASHING, apenas).
		var period := lerpf(0.5, 0.16, urgency)
		var dim: float = 0.75 if mgr.calm() else 0.35
		var on := _done or fmod(_time, period) < period * 0.62
		col = col if on else col.darkened(dim)
		col.a *= _fade

		# Escuadras (brazos de 5 px).
		var arm := 5
		for corner in [r.position, Vector2i(r.end.x - 1, r.position.y),
				Vector2i(r.position.x, r.end.y - 1), r.end - Vector2i.ONE]:
			var sx := 1 if corner.x == r.position.x else -1
			var sy := 1 if corner.y == r.position.y else -1
			draw_rect(Rect2(mini(corner.x, corner.x + sx * arm), corner.y, arm, 1), col)
			draw_rect(Rect2(corner.x, mini(corner.y, corner.y + sy * arm), 1, arm), col)
		# Punto en el centro: el punto de agarre.
		if not _done or _saved:
			draw_rect(Rect2(c.x, c.y, 1, 1), col)

		if _done:
			return
		# Barra de tiempo, pegada abajo del cerco.
		var bw := side
		var bx := c.x - bw / 2
		var by := r.end.y + 2
		draw_rect(Rect2(bx, by, bw, 1), Color(col, 0.25))
		draw_rect(Rect2(bx, by, int(round(bw * clampf(left / window, 0.0, 1.0))), 1), col)
		if _hover or teach:
			var label := "CLAMP"
			var tw := PixelFont.text_width(label)
			PixelFont.draw(self, label, Vector2(c.x - tw / 2, r.position.y - PixelFont.GLYPH_H - 2), col)
