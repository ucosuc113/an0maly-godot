extends "res://scripts/mesh_interactable.gd"

# Pieza clicable de la sala de apagado de emergencia (emergency_room.gd).
# Todas se comportan igual —se hunden o se mueven y avisan a la sala— asi que
# van con el mismo script y cambia `action`:
#
# Mientras el boton de apertura este disponible y nadie lo haya tocado, late
# solo: el jugador no tiene forma de adivinar en que momento se desbloquea, y
# sin eso queda esperando delante de un boton que ya se podia usar.
#
#   OPEN_DOOR   el boton junto al panel principal. Va en dos tiempos: desde
#               la sala, el clic lo ENFOCA (siempre, este bloqueado o no);
#               ya enfocado, el clic lo aprieta, y eso solo cuando el desastre
#               lo pide. Abre la puerta y lleva la camara adentro.
#   LIFT_COVER  la escotilla de cristal del boton criogenico: se levanta.
#   PURGE       el boton azul. Solo con la escotilla abierta y el nucleo
#               pasado del umbral. Vacia todas las reservas, en silencio.
#   KEYS        las tres ranuras de llave: se insertan juntas.
#   SWITCH      uno de los dos switches, segun `switch_index`. Giran sobre si
#               mismos y hay que accionarlos en orden.

enum Action { OPEN_DOOR, LIFT_COVER, PURGE, KEYS, SWITCH }

## Nodo con emergency_room.gd.
@export var room: Node
@export var action: Action = Action.OPEN_DOOR
## Cual de los dos switches, con Action.SWITCH (0 = el primero de la secuencia).
@export var switch_index: int = 0
## Vista desde la que se puede usar. Vacio = desde cualquiera.
@export var usable_in_view: StringName = &""
## Vista propia de la pieza. Si esta puesta, el clic desde `usable_in_view`
## primero enfoca, y recien ahi el siguiente clic actua.
@export var focus_view: StringName = &""
## Cuanto se hunde al apretarlo (0 = no se hunde, p. ej. la escotilla).
@export var press_depth: float = 0.004

var _in_view: bool = true
## La camara ya esta en la vista propia de la pieza.
var _focused: bool = false
## Ya avisamos que se desbloqueo (para el sonido, una sola vez).
var _announced: bool = false

func _ready() -> void:
	super._ready()
	if views and not usable_in_view.is_empty():
		views.view_changed.connect(_on_view_changed)
		_on_view_changed(views.current)
	if room:
		room.opened.connect(_refresh)
		room.purged.connect(_refresh)
	_refresh()

func _on_view_changed(view: StringName) -> void:
	_in_view = view == usable_in_view or (not focus_view.is_empty() and view == focus_view)
	_focused = not focus_view.is_empty() and view == focus_view
	_refresh()

func _refresh() -> void:
	enabled = _in_view and _available()

func _available() -> bool:
	if room == null:
		return false
	match action:
		Action.OPEN_DOOR:
			# Enfocarlo se puede siempre; apretarlo, solo con el desastre encima.
			if not focus_view.is_empty() and not _focused:
				return true
			return room.can_open()
		Action.LIFT_COVER:
			return room.is_open and not room.cover_lifted
		Action.PURGE:
			return room.can_purge()
		Action.KEYS:
			return room.can_insert_keys()
		Action.SWITCH:
			return room.can_flip(switch_index)
	return false

# El estado cambia solo (la temperatura sube, la escotilla se abre), asi que
# hay que revisarlo seguido en vez de esperar una senal para cada cosa.
func _process(_delta: float) -> void:
	var want := _in_view and _available()
	if want != enabled:
		enabled = want
	_attention()

## El de apertura late mientras este disponible y sin apretar. No se pisa con
## el resaltado del mouse: si el puntero esta encima, manda el hover.
func _attention() -> bool:
	if action != Action.OPEN_DOOR or room == null or room.is_open 			or not room.can_open():
		_announced = false
		return false
	if not _announced:
		_announced = true
		if views and views.sfx:
			views.sfx.play("crt_ok", -4.0, 0.8)
	if _hovering:
		return true
	_hover = 0.45 + 0.4 * sin(Time.get_ticks_msec() * 0.0055)
	return true

func _on_clicked(_hit_position: Vector3) -> void:
	if not enabled:
		return
	enabled = false
	if press_depth > 0.0:
		_press_animation()
	match action:
		Action.OPEN_DOOR:
			if not focus_view.is_empty() and not _focused:
				# Primer clic: la camara se acerca.
				views.go_to(focus_view)
				return
			if views and views.sfx:
				views.sfx.play("panel_button")
			room.open()
		Action.LIFT_COVER:
			room.lift_cover()
		Action.PURGE:
			if views and views.sfx:
				views.sfx.play("panel_button", 2.0, 0.8)
			room.purge()
		Action.KEYS:
			room.insert_keys()
		Action.SWITCH:
			room.flip_switch(switch_index)

func _press_animation() -> void:
	var root: Node3D = model if model else self
	var rest := root.position
	var down := rest - root.transform.basis.y.normalized() * press_depth
	var t := create_tween()
	t.tween_property(root, "position", down, 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.08)
	t.tween_property(root, "position", rest, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
