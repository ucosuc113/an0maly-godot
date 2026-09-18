extends Node

# La sala de apagado de emergencia: el cuartito detras de la puerta corrediza,
# al otro lado de la sala del panel principal.
#
# Las dos vistas existen DESDE EL PRIMER SEGUNDO, este o no abierta la sala:
#
#   EmergencyButton  el boton de apertura, junto al panel principal
#                    (x = -1.45). Se lo puede enfocar siempre; apretarlo, solo
#                    cuando el desastre lo pide.
#   Emergency        la sala entera. Con la puerta cerrada se la ve igual,
#                    porque el cristal de la puerta es transparente: se
#                    adivina la consola apagada del otro lado.
#
# Y ya adentro hay DOS sub-enfoques mas, porque de lejos no se lee nada:
#
#   EmergencyMonitors  los tres monitores del fondo
#   EmergencyPanel     la consola: llaves, palancas y boton criogenico
#
# Se entra clicando la pieza correspondiente (focus_target.gd) y se sale con
# BACK, como en el resto del juego.
#
# Al apretar el boton la puerta sube, las luces prenden en el naranja rojizo
# de la emergencia y la camara se mueve ENTERA a la consola (no hay pantalla
# dividida: adentro hay demasiados elementos para una franja).
#
#   Adentro, de izquierda a derecha:
#     tres ranuras de llave    la primera traba. Se insertan las tres juntas.
#     dos switches             giran sobre si mismos como la rueda de un
#                              mouse. El IZQUIERDO es el de seguridad: no hace
#                              nada salvo habilitar al DERECHO, que es el
#                              apagado forzado de verdad.
#     boton criogenico         bajo una escotilla de cristal que se LEVANTA al
#                              clicarla (no se desliza como las del panel).
#
# Las cinco luces del panel dicen en que punto de la secuencia esta cada cosa:
# tres para las llaves (van juntas, son una sola malla) y una por switch.
#
#     rojo   no disponible todavia
#     azul   se puede accionar, nada lo impide
#     verde  accionado
#
# El boton criogenico se desbloquea cuando el nucleo pasa `purge_unlock_temp`.
# Al apretarlo vacia TODAS las reservas de refrigerante sobre el agujero negro
# y no se puede deshacer: los ventiladores ya no vuelven a encender nunca.
# Lo maneja crisis_director.purge(); aca solo se dispara.
#
# A proposito: apretarlo NO muestra ningun cartel. Pasa en silencio.

signal opened
## El jugador vacio las reservas.
signal purged
signal keys_inserted
## Un switch quedo en posicion (0 = el primero, 1 = el segundo).
signal switch_flipped(index: int)
## Los dos switches puestos: arranca el apagado forzado
## (crisis_director.forced_shutdown()).
signal shutdown_armed

@export var views: Node
@export var sfx: Node
@export var sim: Node
## crisis_director.gd: decide si el boton de apertura esta disponible y que
## pasa al purgar.
@export var crisis: Node

@export_group("Puerta")
@export var door: Node3D
## Material del vidrio de la puerta: se ve la sala del otro lado aunque este
## cerrada.
@export var door_glass_material: String = "Material.011"
@export_range(0.0, 1.0, 0.01) var door_glass_opacity: float = 0.2
## Cuanto sube, en metros. 0 = su propia altura (se mide de la malla).
@export var door_lift: float = 0.0
@export var door_time: float = 2.4

@export_group("Sala")
## Luces del cuartito (arrancan apagadas).
@export var lights: Array[Light3D] = []
@export var light_color: Color = Color(1.0, 0.34, 0.16)
@export var light_energy: float = 1.2
@export var light_fade: float = 1.6
## Piezas que enmarca la vista general (mesa, monitores, botones).
@export var console_parts: Array[Node3D] = []
@export var view_name: StringName = &"Emergency"

@export_subgroup("Sub-enfoques")
## Los tres monitores del fondo.
@export var monitor_parts: Array[Node3D] = []
@export var monitors_view: StringName = &"EmergencyMonitors"
@export var monitors_margin: float = 1.15
## La consola de abajo: llaves, palancas, boton criogenico.
@export var panel_parts: Array[Node3D] = []
@export var panel_view: StringName = &"EmergencyPanel"
@export var panel_margin: float = 1.55
## Desde donde se mira la consola. Por defecto, de frente y un poco desde
## arriba: los controles sobresalen de la mesa y de canto no se leen.
@export var panel_forward: Vector3 = Vector3(1.0, -0.7, 0.0)
## Pose a mano. Vacio: se deduce de las mallas de `console_parts`.
@export var camera_marker: Node3D
## Margen alrededor de la consola al encuadrarla (1 = justo).
@export var frame_margin: float = 1.25

@export_group("Vista del boton de apertura")
@export var open_button: Node3D
@export var button_view: StringName = &"EmergencyButton"
## Cuanto se abre el encuadre alrededor del boton (es chiquito: si se lo
## encuadra justo, la camara queda pegada a la pared).
@export var button_margin: float = 3.2

@export_group("Llaves y switches")
## Donde se clica para meter las llaves (el modelo de referencia).
@export var key_slot: Node3D
## Las tres luces de las llaves. Son una sola malla, asi que prenden juntas.
@export var key_lights: Node3D
## Los dos switches EN ORDEN DE USO: el [0] solo habilita al [1]. Si el orden
## quedo al reves, se da vuelta este arreglo y listo.
@export var switches: Array[Node3D] = []
## La luz de cada switch, en el mismo orden.
@export var switch_lights: Array[Node3D] = []
## Cuanto gira un switch sobre su propio eje al accionarlo.
## Giran como la rueda de un mouse: el eje es horizontal y cruzado a la vista,
## no vertical. Con (0,1,0) giraban de plano, como una perilla.
@export var switch_axis: Vector3 = Vector3(0.0, 0.0, 1.0)
@export var switch_angle_degrees: float = 70.0
@export var switch_time: float = 0.35

@export_subgroup("Luces de estado")
## Material de la lente de las cinco luces.
@export var lamp_material: String = "Material.032"
## Colores saturados y emision alta a proposito: la sala esta bañada en luz
## roja de emergencia, y con emision baja el azul y el verde se lavan hasta
## volverse el mismo cian palido. Aca el color de la lente tiene que ganarle
## al ambiente, no mezclarse con el.
## Medido sobre la captura: con emision alta los canales verde y azul clipean
## los dos a 255 y las tres luces terminan del mismo cian. La emision tiene
## que quedar en el rango medio, donde el tonemap AgX todavia respeta el tono.
@export var lamp_blocked: Color = Color(1.0, 0.03, 0.0)
@export var lamp_ready: Color = Color(0.0, 0.25, 1.0)
@export var lamp_active: Color = Color(0.0, 1.0, 0.1)
@export_range(0.0, 20.0, 0.1) var lamp_energy: float = 2.0

@export_group("Escotilla del boton criogenico")
@export var cover: Node3D
## Material del cristal (se vuelve transparente al arrancar).
@export var glass_material: String = "Material.011"
@export_range(0.0, 1.0, 0.01) var glass_opacity: float = 0.16
## Eje de la bisagra, en el espacio de la tapa.
@export var cover_axis: Vector3 = Vector3(0.0, 0.0, 1.0)
## Cuanto se levanta.
@export var cover_angle_degrees: float = -100.0
## Hacia que borde de su caja esta la bisagra (-1/0/1 por eje).
@export var cover_hinge_edge: Vector3 = Vector3(-1.0, 0.0, 0.0)
@export var cover_time: float = 0.7

var _door_rest: Vector3
var is_open: bool = false
## Las tres llaves ya estan puestas.
var keys_in: bool = false
## Cuantos switches se accionaron (0, 1 o 2).
var switches_on: int = 0
## Ultimo color puesto en cada luz, para no rehacer el material cada cuadro.
var _lamp_state: Dictionary = {}
var cover_lifted: bool = false
## Ya se vacio el refrigerante (no tiene vuelta).
var is_purged: bool = false

func _ready() -> void:
	for l in lights:
		if l:
			l.light_energy = 0.0
			l.light_color = light_color
	if door:
		_door_rest = door.position
	# Diferido: los clicables de la puerta y de la escotilla arman sus
	# materiales en su propio _ready(), y aca hay que tocar esos, no los de
	# antes (si no, el contorno naranja se pierde).
	_setup_materials.call_deferred()
	# Las dos vistas se registran ya: se puede mirar la sala (a traves del
	# cristal) y el boton desde el primer segundo, este o no abierta.
	_register_views.call_deferred()

func _setup_materials() -> void:
	if door:
		_setup_door()
	_make_glass()
	_refresh_lamps()

# --- Apertura ----------------------------------------------------------------------

## El desastre justifica abrirla. Lo decide crisis_director.gd.
func can_open() -> bool:
	if is_open:
		return false
	return crisis != null and crisis.emergency_available()

## Abre la puerta, prende las luces y lleva la camara adentro.
func open() -> void:
	if is_open:
		return
	is_open = true
	_play("breaker_off", -2.0, 0.7)
	var lift := door_lift
	if lift <= 0.0 and door:
		lift = _box(door).size.y * 1.02
	if door:
		_play("cover_slide", 0.0, 0.6)
		var t := create_tween()
		t.tween_property(door, "position", _door_rest + Vector3(0.0, lift, 0.0), door_time) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	# Las luces de emergencia entran a tirones, como los tubos de la sala.
	var flick := create_tween()
	for e in [0.3, 0.05, 0.8, 0.1, 1.0]:
		for l in lights:
			if l:
				flick.parallel().tween_property(l, "light_energy", light_energy * float(e), 0.06)
		flick.tween_interval(0.05)
	if sfx:
		sfx.play("lights_on", -8.0)
	await get_tree().create_timer(door_time * 0.55, false).timeout
	_refresh_lamps()
	opened.emit()
	if views:
		while views.is_busy():
			await get_tree().process_frame
		views.go_to(view_name)

## Registra las dos vistas. La camara entra ENTERA a la consola: adentro hay
## demasiados elementos para una franja dividida.
func _register_views() -> void:
	if views == null:
		return
	if camera_marker and not view_name.is_empty():
		views.register_view(view_name, camera_marker.global_transform)
	elif not view_name.is_empty():
		# La sala se mira desde la puerta hacia adentro (de -X a +X).
		_frame_view(view_name, _parts_box(), Vector3.RIGHT, frame_margin)
	if open_button and not button_view.is_empty():
		# El boton esta sobre la pared del fondo: se lo mira de frente (-Z).
		_frame_view(button_view, _box(open_button), Vector3.FORWARD, button_margin)
	# El sub-enfoque del panel. Los monitores registran cada uno el suyo, a
	# escala 1:1 (screen_panel.gd): encuadrarlos juntos los dejaba ilegibles.
	if not panel_parts.is_empty() and not panel_view.is_empty():
		_frame_view(panel_view, _box_of(panel_parts), panel_forward, panel_margin,
			view_name)

## Encuadra `box` desde `forward` (direccion camara -> objeto) y registra la
## vista. El tamano que entra se mide sobre los ejes de la propia camara, asi
## que sirve para cualquier orientacion.
func _frame_view(view: StringName, box: AABB, forward: Vector3, margin: float,
		parent: StringName = &"") -> void:
	if box.size == Vector3.ZERO or views.camera == null:
		push_warning("EmergencyRoom: no pude encuadrar %s" % view)
		return
	var basis := _look_basis(forward)
	var cam: Camera3D = views.camera
	var aspect := maxf(cam.get_viewport().size.aspect(), 0.01)
	# Medio alto y medio ancho del objeto vistos desde esa orientacion.
	var half_y := absf(box.size.dot(basis.y.abs())) * 0.5
	var half_x := absf(box.size.dot(basis.x.abs())) * 0.5
	var need := maxf(half_y, half_x / aspect)
	var depth := absf(box.size.dot(basis.z.abs())) * 0.5
	var dist := need * margin / tan(deg_to_rad(cam.fov * 0.5)) + depth
	views.register_view(view, Transform3D(basis,
		box.get_center() - forward.normalized() * dist), parent)

## Base de camara que mira hacia `forward` con +Y arriba.
func _look_basis(forward: Vector3) -> Basis:
	var f := forward.normalized()
	var up := Vector3.UP if absf(f.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	var z := -f
	var x := up.cross(z).normalized()
	return Basis(x, z.cross(x), z)

func _parts_box() -> AABB:
	return _box_of(console_parts)

## Caja que envuelve las mallas de varias piezas.
func _box_of(parts: Array[Node3D]) -> AABB:
	var box := AABB()
	var first := true
	for n in parts:
		if n == null:
			continue
		var b := _box(n)
		if b.size == Vector3.ZERO:
			continue
		box = b if first else box.merge(b)
		first = false
	return box

func _box(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box

# --- Llaves y switches --------------------------------------------------------------

## Se pueden meter las llaves: la sala abierta y todavia sin ponerlas.
func can_insert_keys() -> bool:
	return is_open and not keys_in

func insert_keys() -> void:
	if not can_insert_keys():
		return
	keys_in = true
	_play("laser_lock", -6.0, 1.2)
	_refresh_lamps()
	keys_inserted.emit()

## El switch `index` se puede accionar: llaves puestas y le toca a el.
func can_flip(index: int) -> bool:
	return is_open and keys_in and switches_on == index and index < switches.size()

## Lo gira sobre su propio eje y avanza la secuencia.
func flip_switch(index: int) -> void:
	if not can_flip(index):
		return
	switches_on = index + 1
	_play("lever_clack", -2.0, 0.9)
	_turn(switches[index])
	_refresh_lamps()
	switch_flipped.emit(index)
	if switches_on >= switches.size():
		shutdown_armed.emit()
		if crisis:
			crisis.forced_shutdown()

## Giro sobre si mismo, alrededor del centro de sus mallas.
func _turn(node: Node3D) -> void:
	if node == null:
		return
	var pivot := _box(node).get_center()
	var axis := (node.global_basis * switch_axis).normalized()
	var start := node.global_transform
	var t := create_tween()
	t.tween_method(func(a: float) -> void:
		var rot := Basis(axis, deg_to_rad(switch_angle_degrees) * a)
		node.global_transform = Transform3D(rot, pivot - rot * pivot) * start,
		0.0, 1.0, switch_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# --- Luces de estado ----------------------------------------------------------------

## Rojo = no disponible, azul = se puede, verde = hecho.
func _refresh_lamps() -> void:
	_set_lamp(key_lights, lamp_active if keys_in else (
		lamp_ready if can_insert_keys() else lamp_blocked))
	for i in switch_lights.size():
		var col := lamp_blocked
		if i < switches_on:
			col = lamp_active
		elif can_flip(i):
			col = lamp_ready
		_set_lamp(switch_lights[i], col)

func _set_lamp(node: Node3D, color: Color) -> void:
	if node == null or _lamp_state.get(node) == color:
		return
	_lamp_state[node] = color
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var base := mi.get_active_material(i) as BaseMaterial3D
			if base == null or base.resource_name != lamp_material:
				continue
			var m := _own_material(mi, i)
			if m == null:
				continue
			m.albedo_color = color
			m.emission_enabled = true
			m.emission = color
			m.emission_energy_multiplier = lamp_energy

# --- Escotilla ---------------------------------------------------------------------

## La puerta: sin descarte de caras y con su ventana transparente.
##
## Sin culling porque es una plancha gruesa que se ve de los dos lados: con
## backface culling, mirada desde adentro desaparece y la sombra que proyecta
## queda partida. El vidrio va aparte, al `door_glass_opacity` pedido; en
## Godot un material con transparencia ALPHA no proyecta sombra, asi que la
## ventana deja pasar la luz y el resto de la puerta no.
func _setup_door() -> void:
	for mi: MeshInstance3D in door.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var m := _own_material(mi, i)
			if m == null:
				continue
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			if m.resource_name == door_glass_material:
				_make_transparent(m, door_glass_opacity)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED

## El cristal de la escotilla, transparente de verdad.
func _make_glass() -> void:
	if cover == null:
		return
	for mi: MeshInstance3D in cover.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var m := _own_material(mi, i)
			if m != null:
				_make_transparent(m, glass_opacity)

## Material propio de esa superficie, para tocarlo sin pisar a nadie.
##
## OJO: si la pieza tiene un clicable encima, mesh_interactable.gd ya le puso
## un material propio con el contorno naranja enganchado como `next_pass` y se
## guardo la referencia para animarlo. Si aca se reemplazara con un duplicado,
## el borde se perderia. Por eso: si ya hay un override, se modifica ESE en el
## lugar; recien si no hay ninguno se duplica.
func _own_material(mi: MeshInstance3D, surface: int) -> BaseMaterial3D:
	var own := mi.get_surface_override_material(surface) as BaseMaterial3D
	if own != null:
		return own
	var base := mi.get_active_material(surface) as BaseMaterial3D
	if base == null:
		return null
	var m := base.duplicate() as BaseMaterial3D
	mi.set_surface_override_material(surface, m)
	return m

func _make_transparent(m: BaseMaterial3D, opacity: float) -> void:
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color.a = opacity
	m.roughness = 0.05
	m.metallic_specular = 0.9

## Levanta la escotilla sobre su bisagra (no se desliza: se abre como tapa).
func lift_cover() -> void:
	if cover_lifted or cover == null:
		return
	cover_lifted = true
	_play("cover_slide", -3.0, 1.2)
	var box := _box(cover)
	# La bisagra va sobre el borde indicado de la caja, en el mundo.
	var hinge := box.get_center() + box.size * 0.5 * cover_hinge_edge
	var axis := (cover.global_basis * cover_axis).normalized()
	var start := cover.global_transform
	var t := create_tween()
	t.tween_method(func(a: float) -> void:
		var rot := Basis(axis, deg_to_rad(cover_angle_degrees) * a)
		var xf := Transform3D(rot, hinge - rot * hinge) * start
		cover.global_transform = xf, 0.0, 1.0, cover_time) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# --- Boton criogenico ---------------------------------------------------------------

## El boton azul esta disponible: la escotilla abierta y el nucleo pasado del
## umbral. Lo consulta el clicable del boton.
func can_purge() -> bool:
	return cover_lifted and not is_purged and crisis != null and crisis.purge_ready()

## Vacia las reservas. Sin cartel, sin aviso: pasa y ya.
func purge() -> void:
	if not can_purge():
		return
	is_purged = true
	_play("cryo_freeze", -2.0, 0.9)
	crisis.purge()
	purged.emit()

func _play(sound: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if sfx:
		sfx.play(sound, volume_db, pitch)
