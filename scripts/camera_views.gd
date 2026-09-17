extends Node3D

# Vistas de camara. Cada hijo Marker3D es una vista: su transform es donde
# queda la camara (se pueden mover en el editor). La camara nunca se desliza:
# la pantalla se tapa (view_transition.gd), la camara salta y se destapa.
#
#   $CameraViews.go_to(&"Window")
#   $CameraViews.back()               # vuelve a home_view
#
# Pantalla dividida: si el Marker3D de una vista tiene un Marker3D hijo, esa
# vista usa split_view.gd: la camara principal arriba y la del hijo en la
# franja de abajo. Ahi el boton BACK va arriba para no tapar la franja.
#
# Fuera de home_view aparece el boton BACK (view_back_button.gd) y funcionan
# las teclas de view_back (SPACE / S / flecha abajo / BACKSPACE / clic
# derecho). Los nodos de home_interactables (con `enabled`) solo responden en
# home_view.

signal view_changed(view: StringName)

const BACK_ACTION := &"view_back"

@export var camera: Camera3D
@export var transition: Node
## Nodo con view_back_button.gd.
@export var back_button: Node
## Nodo con split_view.gd (para las vistas con camara secundaria).
@export var split_view: Node
@export var sfx: Node
@export var home_view: StringName = &"Room"
@export var home_interactables: Array[Node] = []
## Pausa con la pantalla tapada, ya con la camara en su lugar.
@export var hold_time: float = 0.12

var current: StringName
## En una secuencia (fases del panel): sin boton BACK ni teclas para salir.
var cinematic: bool = false:
	set(value):
		cinematic = value
		if value and back_button:
			back_button.hide_bar()
var _busy: bool = false
var _shake_tween: Tween

func _ready() -> void:
	current = home_view
	_register_action()
	if back_button:
		back_button.pressed.connect(back)

func _register_action() -> void:
	if InputMap.has_action(BACK_ACTION):
		return
	InputMap.add_action(BACK_ACTION)
	for key in [KEY_SPACE, KEY_S, KEY_DOWN, KEY_BACKSPACE]:
		var e := InputEventKey.new()
		e.physical_keycode = key
		InputMap.action_add_event(BACK_ACTION, e)
	var m := InputEventMouseButton.new()
	m.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event(BACK_ACTION, m)
	var j := InputEventJoypadButton.new()
	j.button_index = JOY_BUTTON_B
	InputMap.action_add_event(BACK_ACTION, j)

func _process(_delta: float) -> void:
	# Pausable: con el juego en pausa no se procesa.
	if current != home_view and not _busy and not cinematic \
			and Input.is_action_just_pressed(BACK_ACTION):
		if back_button:
			back_button.flash()
		back()

func is_busy() -> bool:
	return _busy

func back() -> void:
	go_to(home_view)

func go_to(view: StringName) -> void:
	if _busy or view == current or camera == null or transition == null:
		return
	var marker := get_node_or_null(NodePath(view)) as Node3D
	if marker == null:
		push_warning("CameraViews: no existe la vista %s" % view)
		return
	_busy = true
	_set_home_interactive(false)
	if back_button:
		back_button.hide_bar()
	_play("view_close")
	await transition.cover()

	camera.global_transform = marker.global_transform
	var pane := _pane_marker(marker)
	if split_view:
		if pane:
			split_view.open(pane.global_transform)
		else:
			split_view.close()
	if back_button:
		back_button.at_top = pane != null
	current = view
	view_changed.emit(view)
	await get_tree().create_timer(hold_time, false).timeout

	_play("view_open")
	if pane and split_view:
		split_view.animate_in()
	await transition.uncover()
	if view == home_view:
		_set_home_interactive(true)
	elif back_button and not cinematic:
		back_button.show_bar()
	_busy = false

## Sacudida de camara (golpes). strength en metros; en pixel art 0.004 ~ 1 px
## a la distancia del ventanal.
func shake(strength: float = 0.004, time: float = 0.18) -> void:
	if _shake_tween:
		_shake_tween.kill()
	_shake_tween = create_tween()
	var steps := int(time / 0.03)
	for i in steps:
		var k := 1.0 - float(i) / steps
		var off := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * strength * k
		_shake_tween.tween_callback(func() -> void:
			camera.h_offset = off.x
			camera.v_offset = off.y)
		_shake_tween.tween_interval(0.03)
	_shake_tween.tween_callback(func() -> void:
		camera.h_offset = 0.0
		camera.v_offset = 0.0)

## Empuje lento de la camara desde su vista actual (en su espacio local).
func dolly(offset: Vector3, time: float) -> Tween:
	var t := create_tween()
	var target := camera.global_transform.translated_local(offset)
	t.tween_property(camera, "global_transform", target, time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return t

## Camara secundaria de una vista: su primer Marker3D hijo.
func _pane_marker(marker: Node3D) -> Node3D:
	for c in marker.get_children():
		if c is Marker3D:
			return c
	return null

## Camara y posicion (en su viewport) bajo un punto del PixelViewport.
func camera_at(pos: Vector2) -> Dictionary:
	if split_view:
		var hit: Dictionary = split_view.camera_at(pos)
		if not hit.is_empty():
			return hit
	return {"camera": camera, "position": pos}

func _set_home_interactive(value: bool) -> void:
	for n in home_interactables:
		if n:
			n.enabled = value

func _play(sound: String) -> void:
	if sfx:
		sfx.play(sound)
