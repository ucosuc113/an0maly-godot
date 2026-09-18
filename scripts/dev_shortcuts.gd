extends Node

# Atajos de desarrollo. SOLO en compilaciones de depuracion: en una
# exportacion release OS.is_debug_build() es false y este nodo se apaga solo,
# asi que no hay riesgo de que lleguen al juego publicado.
#
#   F1  inicializacion completa: aprieta las tres fases y se saltea sus
#       cinematicas (deja las palancas destapadas y el agujero negro puesto)
#   F2  derretimiento ya (sin tener que recalentar el nucleo a mano)
#   F3  adelanta `skip_seconds` de la pista del derretimiento
#   F4  velocidad normal (por si algo dejo Engine.time_scale acelerado)
#
# MODO AUTOMATICO, para mirar el resultado sin jugar cuatro minutos:
#
#     godot --path . --audio-driver Dummy -- --shots
#
# arranca la partida, se saltea la inicializacion, fuerza el derretimiento,
# guarda una foto de cada paso en user://devshots/ y cierra el juego.
#
# Como se saltean las cinematicas: las fases 2 y 3 esperan cada paso en
#
#     while music.is_track_playing() and music.track_time() < t: ...
#
# o sea que si la pista se termina, TODOS los pasos que quedan dejan de
# esperar y la secuencia corre hasta el final sola, incluido complete_phase().
# Eso ya estaba pensado asi para cuando una pista es mas corta que su
# secuencia; aca se fuerza a proposito con stop_track(). La fase 1 no tiene
# pista (va por temporizadores), asi que para esa se acelera Engine.time_scale,
# que arrastra timers y tweens por igual.
#
# Los visuales quedan atropellados (los tweens arrancan todos juntos), pero el
# ESTADO final es el correcto, que es lo que se quiere para probar.

const KEYS := {
	KEY_F1: &"dev_init",
	KEY_F2: &"dev_meltdown",
	KEY_F3: &"dev_skip",
	KEY_F4: &"dev_normal",
}

@export var panel: Node
@export var music: Node
@export var crisis: Node
@export var overlay: Node
## Solo para el modo automatico.
@export var intro: Node
@export var views: Node
@export var pause_menu: Node
@export var room: Node
@export var sim: Node
## Cuanto acelera el reloj mientras se saltea la fase 1.
@export var time_scale: float = 12.0
## Cuanto adelanta F3 en la pista del derretimiento.
@export var skip_seconds: float = 30.0
## Subarbol que imprime el modo --dump.
@export var dump_path: NodePath = ^"../PixelViewport/MapAnomalyPlayerRoom/EmergencyRoom"

var _busy: bool = false

func _ready() -> void:
	if not OS.is_debug_build():
		set_process(false)
		return
	_register_actions()
	if "--dump" in OS.get_cmdline_user_args():
		_dump.call_deferred()
		return
	if "--shots" in OS.get_cmdline_user_args():
		_auto_shots()
		return
	print("[dev] F1 init  F2 meltdown  F3 +%ds  F4 velocidad normal"
		% int(skip_seconds))

func _register_actions() -> void:
	for key in KEYS:
		var action: StringName = KEYS[key]
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var e := InputEventKey.new()
		e.physical_keycode = key
		InputMap.action_add_event(action, e)

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(&"dev_normal"):
		Engine.time_scale = 1.0
		_say("TIME SCALE 1x")
	if Input.is_action_just_pressed(&"dev_init"):
		_skip_init()
	if Input.is_action_just_pressed(&"dev_meltdown"):
		_force_meltdown()
	if Input.is_action_just_pressed(&"dev_skip"):
		_skip_ahead()

# --- F1: inicializacion -------------------------------------------------------------

func _skip_init() -> void:
	if _busy or panel == null:
		return
	if panel.unlocked:
		_say("DEV: YA ESTA INICIALIZADO")
		return
	_busy = true
	_say("DEV: SALTEANDO INICIALIZACION")
	Engine.time_scale = time_scale
	var guard := Time.get_ticks_msec() + 60000
	while panel.phase < panel.PHASES and Time.get_ticks_msec() < guard:
		var next: int = panel.phase + 1
		if panel.button_state(next) != "ready":
			# Todavia se esta corriendo la tapa del boton anterior.
			await get_tree().process_frame
			continue
		panel.press_phase(next)
		await _finish_phase(next)
	# complete_phase() marca la fase antes de correr la tapa de las palancas.
	await _until(func() -> bool: return panel.unlocked, 8000)
	Engine.time_scale = 1.0
	_busy = false
	_say("DEV: PALANCAS LISTAS" if panel.unlocked else "DEV: SE TRABO, REVISAR")

## Espera a que la fase `index` termine, cortandole la pista para que su
## secuencia deje de esperar en cada `_at()`.
func _finish_phase(index: int) -> void:
	# Un momento para que la fase arranque y ponga su pista. Se mide en tiempo
	# real: con Engine.time_scale acelerado, get_process_delta_time() miente.
	var until := Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < until and not music.is_track_playing() \
			and panel.phase < index:
		await get_tree().process_frame
	if music.is_track_playing():
		music.stop_track(0.15)
	await _until(func() -> bool: return panel.phase >= index, 20000)

# --- F2 / F3 / F4 -------------------------------------------------------------------

func _force_meltdown() -> void:
	if crisis == null or panel == null:
		return
	if not panel.unlocked:
		_say("DEV: FALTA INICIALIZAR (F1)")
		return
	if not crisis.is_idle():
		_say("DEV: YA HAY UNA CRISIS EN CURSO")
		return
	_say("DEV: DERRETIMIENTO FORZADO")
	crisis._start_meltdown()

func _skip_ahead() -> void:
	if music == null or not music.is_track_playing():
		_say("DEV: NO HAY PISTA SONANDO")
		return
	var t: float = music.track_time()
	if t < 0.0:
		return
	music.seek_track(t + skip_seconds)
	_say("DEV: +%ds" % int(skip_seconds))

## Espera a que `cond` sea true, con tope en milisegundos de tiempo real.
func _until(cond: Callable, timeout_ms: int) -> void:
	var until := Time.get_ticks_msec() + timeout_ms
	while not cond.call() and Time.get_ticks_msec() < until:
		await get_tree().process_frame

# --- Modo automatico ----------------------------------------------------------------

## Juega solo hasta la consola auxiliar y va guardando fotos. Cada espera tiene
## tope propio: si algo se traba, igual sale y cierra.
func _auto_shots() -> void:
	var dir := "user://devshots"
	DirAccess.make_dir_recursive_absolute(dir)
	print("[shots] carpeta: ", ProjectSettings.globalize_path(dir))
	# Sin esto, en cuanto la ventana pierde el foco se abre la pausa y la
	# corrida se queda congelada para siempre.
	if pause_menu:
		pause_menu.pause_on_focus_loss = false
	# Cortafuegos absoluto por si alguna espera no alcanza.
	get_tree().create_timer(180.0).timeout.connect(func() -> void:
		print("[shots] tope de tiempo alcanzado")
		get_tree().quit())

	# Solo la pagina de finales del CRT, sin entrar al juego.
	if "--endings" in OS.get_cmdline_user_args():
		var crt := get_node_or_null(^"../PixelViewport/StaticBody3D")
		# El arranque del CRT (encendido + volcado de texto + menu) tarda.
		await get_tree().create_timer(22.0).timeout
		if crt and crt.has_method("open_endings"):
			crt.open_endings()
		else:
			print("[shots] no encontre open_endings")
		await get_tree().create_timer(4.0).timeout
		await _shot(dir, "endings")
		print("[shots] listo")
		get_tree().quit()
		return

	await get_tree().create_timer(1.5).timeout
	if intro:
		intro.start()
	await _until(func() -> bool: return panel != null and not views.cinematic, 20000)
	await get_tree().create_timer(1.0).timeout
	await _shot(dir, "01_sala")

	await _skip_init()
	await get_tree().create_timer(1.5).timeout
	await _shot(dir, "02_inicializado")

	# Las dos vistas tienen que existir ya, con la sala todavia cerrada.
	for v in ["EmergencyButton", "Emergency"]:
		await _until(func() -> bool: return not views.is_busy(), 8000)
		views.go_to(StringName(v))
		await _until(func() -> bool: return views.current == StringName(v), 8000)
		await get_tree().create_timer(0.8).timeout
		await _shot(dir, "02b_cerrada_" + v)
	await _until(func() -> bool: return not views.is_busy(), 8000)
	views.go_to(views.home_view)
	await get_tree().create_timer(1.0).timeout

	# Calienta el nucleo hasta la ventana en la que la purga TODAVIA alcanza
	# (entre purge_unlock_temp y purge_safe_temp).
	panel.set_level(&"lateral", 4)
	panel.set_level(&"diagonal", 4)
	panel.set_level(&"fans", 3)
	panel.set_level(&"shield", 3)
	await _until(func() -> bool: return crisis.purge_ready(), 60000)
	print("[shots] nucleo a %d K, purge_ready=%s" % [int(sim.temp), crisis.purge_ready()])
	await _shot(dir, "03_nucleo_caliente")

	room.open()
	await _until(func() -> bool: return views.current == room.view_name, 25000)
	await get_tree().create_timer(1.0).timeout
	await _shot(dir, "04_sala_emergencia")

	# Los sub-enfoques de adentro.
	for v in ["EmergencyPanel"]:
		await _until(func() -> bool: return not views.is_busy(), 8000)
		views.go_to(StringName(v))
		await _until(func() -> bool: return views.current == StringName(v), 8000)
		await get_tree().create_timer(0.8).timeout
		await _shot(dir, "04b_" + v)
	await _until(func() -> bool: return not views.is_busy(), 8000)

	# Hover sobre la mesa, para ver el contorno naranja.
	var focus := get_node_or_null(
		^"../PixelViewport/MapAnomalyPlayerRoom/EmergencyRoom/TableEmergency/ConsoleFocus")
	if focus:
		await _until(func() -> bool: return not views.is_busy(), 8000)
		views.go_to(&"Emergency")
		await _until(func() -> bool: return views.current == &"Emergency", 8000)
		focus.on_pointer_move(Vector3.ZERO)
		await get_tree().create_timer(0.6).timeout
		await _shot(dir, "04c_hover_mesa")
		focus.on_pointer_exit()
		await _until(func() -> bool: return not views.is_busy(), 8000)
		views.go_to(&"EmergencyPanel")
		await _until(func() -> bool: return views.current == &"EmergencyPanel", 8000)
		await get_tree().create_timer(0.6).timeout

	# Corrida corta: cada monitor en su vista propia, y se prueba que BACK
	# suba un solo nivel.
	if "--monitors" in OS.get_cmdline_user_args():
		for v in ["EmergencyCore", "EmergencyCooling", "EmergencyEnvelope"]:
			await _until(func() -> bool: return not views.is_busy(), 8000)
			views.go_to(StringName(v))
			await _until(func() -> bool: return views.current == StringName(v), 8000)
			if views.current != StringName(v):
				print("[shots] FALLO: la vista %s no existe" % v)
				continue
			await get_tree().create_timer(1.2).timeout
			await _shot(dir, "mon_" + v)
		await _until(func() -> bool: return not views.is_busy(), 8000)
		views.back()
		await _until(func() -> bool: return not views.is_busy(), 8000)
		print("[shots] BACK desde un monitor -> %s (deberia ser Emergency)" % views.current)
		views.back()
		await _until(func() -> bool: return not views.is_busy(), 8000)
		print("[shots] BACK otra vez -> %s" % views.current)
		print("[shots] listo")
		get_tree().quit()
		return

	# Secuencia de llaves y switches, mirando las luces en cada paso.
	await _until(func() -> bool: return not views.is_busy(), 8000)
	views.go_to(&"EmergencyPanel")
	await _until(func() -> bool: return views.current == &"EmergencyPanel", 8000)
	await get_tree().create_timer(0.5).timeout
	await _shot(dir, "04d_luces_0_sin_llaves")
	print("[shots] llaves: %s  switch0: %s" % [room.can_insert_keys(), room.can_flip(0)])
	room.insert_keys()
	await get_tree().create_timer(0.6).timeout
	await _shot(dir, "04d_luces_1_llaves")
	room.flip_switch(0)
	await get_tree().create_timer(0.8).timeout
	await _shot(dir, "04d_luces_2_switch1")
	room.flip_switch(1)
	await get_tree().create_timer(0.8).timeout
	print("[shots] switches_on=%d -> apagado forzado" % room.switches_on)
	await _shot(dir, "04d_luces_3_switch2")
	# La cinematica del apagado, paso a paso.
	for i in range(1, 9):
		await get_tree().create_timer(5.0).timeout
		await _shot(dir, "05_apagado_%d" % i)
		print("[shots] apagado t=%ds estado=%d" % [i * 5, crisis.state])
	print("[shots] listo")
	get_tree().quit()
	return

	room.lift_cover()
	await get_tree().create_timer(1.2).timeout
	await _shot(dir, "05_escotilla")

	print("[shots] purgando a %d K (safe=%d)" % [int(sim.temp), int(crisis.purge_safe_temp)])
	room.purge()
	await get_tree().create_timer(12.0).timeout
	print("[shots] a los 12 s: %d K" % int(sim.temp))
	await _shot(dir, "06_purga")
	await _until(func() -> bool: return crisis.state != 0, 60000)
	print("[shots] fin: %d K  estado=%d  (0 idle 1 freeze 2 meltdown)" % [
		int(sim.temp), crisis.state])
	await get_tree().create_timer(3.0).timeout
	await _shot(dir, "07_resultado")
	print("[shots] listo")
	get_tree().quit()

## Guarda lo que se ve en pantalla. Hay que esperar a que el cuadro este
## dibujado, si no sale el anterior (o negro).
func _shot(dir: String, shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [dir, shot_name]
	var err := img.save_png(path)
	print("[shots] %s -> %s" % [shot_name, "ok" if err == OK else "ERROR %d" % err])

## Vuelca la estructura real de un subarbol: mallas, materiales y medidas.
## Los FBX traen los nombres de material de Blender y la geometria lejos del
## origen del nodo, asi que esto es la unica forma de saber que hay adentro.
func _dump() -> void:
	var root := get_node_or_null(dump_path)
	if root == null:
		print("[dump] no encontre ", dump_path)
		get_tree().quit()
		return
	for child in root.get_children():
		var n3 := child as Node3D
		if n3 == null:
			continue
		print("")
		print("== %s ==" % child.name)
		var box := AABB()
		var first := true
		for mi: MeshInstance3D in n3.find_children("*", "MeshInstance3D", true, false):
			var mats: Array[String] = []
			for i in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(i)
				mats.append(mat.resource_name if mat else "(sin material)")
			var b: AABB = mi.global_transform * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
			print("   malla %-28s superficies=%s" % [mi.name, mats])
		if not first:
			print("   caja  centro=%s  tam=%s" % [
				_v(box.get_center()), _v(box.size)])
		else:
			print("   (sin mallas) pos=%s" % _v(n3.global_position))
	get_tree().quit()

func _v(v: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]

# --- Aviso --------------------------------------------------------------------------

## Se ve en pantalla y en la consola de Godot, para no adivinar si el atajo
## agarro o no.
func _say(text: String) -> void:
	print("[dev] ", text)
	if overlay:
		overlay.flash_banner(text, 1.8)
