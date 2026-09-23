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
	if OS.has_feature("auto_bench"):
		_start_device_bench()
		return
	if "--dump" in OS.get_cmdline_user_args():
		_dump.call_deferred()
		return
	if "--bench2" in OS.get_cmdline_user_args():
		_bench2()
		return
	if "--bench" in OS.get_cmdline_user_args():
		_bench()
		return
	if "--shots" in OS.get_cmdline_user_args():
		_auto_shots()
		return
	print("[dev] F1 init  F2 meltdown  F3 +%ds  F4 velocidad normal"
		% int(skip_seconds))

## Exportacion de prueba para el celular (res://dev/device_bench.gd): arranca
## directo en la partida y se mide sola.
func _start_device_bench() -> void:
	var root := get_tree().root
	if not root.has_meta(&"bench_started"):
		root.set_meta(&"bench_started", true)
		root.set_meta(&"anomaly_direct_start", true)
		get_tree().reload_current_scene.call_deferred()
		return
	var script: Script = load("res://dev/device_bench.gd")
	if script:
		root.add_child.call_deferred(script.new())

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
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		print("[shots] tope de tiempo alcanzado")
		get_tree().quit())

	# Solo la pagina de finales del CRT, sin entrar al juego.
	if "--endings" in OS.get_cmdline_user_args():
		var crt := get_node_or_null(^"../PixelViewport/StaticBody3D")
		# El arranque del CRT (encendido + volcado de texto + menu) tarda.
		await get_tree().create_timer(22.0).timeout
		var settings_page := "--settings" in OS.get_cmdline_user_args()
		var gs := get_node(^"../GameSettings")
		var fps_before: bool = gs.get_value("show_fps")
		if settings_page:
			gs.set_value("show_fps", true)
		if crt and settings_page:
			crt._terminal.start_settings()
		elif crt and crt.has_method("open_endings"):
			crt.open_endings()
		else:
			print("[shots] no encontre open_endings")
		await get_tree().create_timer(4.0).timeout
		if settings_page and crt:
			var term = crt._terminal
			for t in term.SETTING_TABS.size():
				term._tab = t
				term.hover_id = term.SETTING_TABS[t].rows[0].id
				await get_tree().create_timer(0.3).timeout
				await _shot(dir, "settings_%d" % t)
		await _shot(dir, "settings" if settings_page else "endings")
		gs.set_value("show_fps", fps_before)
		print("[shots] listo")
		get_tree().quit()
		return

	await get_tree().create_timer(1.5).timeout
	if intro:
		intro.start()
	await _until(func() -> bool: return panel != null and not views.cinematic, 20000)
	await get_tree().create_timer(1.0).timeout
	await _shot(dir, "01_sala")

	if "--pause" in OS.get_cmdline_user_args():
		await _pause_shots(dir)
		return

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

	# Derretimiento con la pista adelantada: --detonation tira el apagado pasado
	# el limite, --quench purga dentro del rango (debe congelar).
	var args := OS.get_cmdline_user_args()
	if "--detonation" in args or "--quench" in args:
		var det := "--detonation" in args
		crisis._start_meltdown()
		await get_tree().create_timer(2.0).timeout
		print("[shots] arranque del derretimiento: %d K" % int(sim.temp))
		music.seek_track(140.0 if det else 70.0)
		var limit: float = crisis.shutdown_max_temp if det else crisis.purge_safe_temp
		await _until(func() -> bool: return sim.temp > limit - 3000.0, 30000)
		print("[shots] t=%.1f  %d K (limite %d)" % [music.track_time(), int(sim.temp), int(limit)])
		room.open()
		await _until(func() -> bool: return views.current == room.view_name, 25000)
		await _until(func() -> bool: return not views.is_busy(), 8000)
		views.go_to(&"EmergencyEnvelope")
		await _until(func() -> bool: return views.current == &"EmergencyEnvelope", 8000)
		await get_tree().create_timer(1.0).timeout
		await _shot(dir, "det_00_envolvente")
		if det:
			await _until(func() -> bool: return sim.temp > limit + 300.0, 30000)
			print("[shots] t=%.1f  %d K -> apagado tarde" % [music.track_time(), int(sim.temp)])
			await _shot(dir, "det_01_envolvente_fuera")
			room.insert_keys()
			await get_tree().create_timer(0.6).timeout
			room.flip_switch(0)
			await get_tree().create_timer(0.8).timeout
			room.flip_switch(1)
			var n := 0
			while crisis.state != 5 and n < 40:
				await get_tree().create_timer(1.0).timeout
				n += 1
				await _shot(dir, "det_%02d" % (n + 1))
				print("[shots] det t=%.1f estado=%d" % [music.track_time(), crisis.state])
		else:
			print("[shots] purgando a %d K (safe=%d)" % [int(sim.temp), int(limit)])
			room.lift_cover()
			await get_tree().create_timer(1.2).timeout
			room.purge()
			await get_tree().create_timer(1.0).timeout
			print("[shots] tras purga: estado=%d pista=%s" % [crisis.state, music.is_track_playing()])
			await _until(func() -> bool: return crisis.state != 0, 60000)
			print("[shots] fin: %d K estado=%d (1 = freeze)" % [int(sim.temp), crisis.state])
		print("[shots] listo")
		get_tree().quit()
		return

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

# --- Benchmark: fps + captura por escena (-- --bench --tag=nombre) -------------------

func _bench() -> void:
	var tag := "base"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			tag = a.substr(6)
	var dir := "user://devshots/bench_" + tag
	DirAccess.make_dir_recursive_absolute(dir)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if pause_menu:
		pause_menu.pause_on_focus_loss = false
	get_tree().create_timer(300.0).timeout.connect(get_tree().quit)
	await get_tree().create_timer(1.5).timeout
	if intro:
		intro.start()
	await _until(func() -> bool: return panel != null and not views.cinematic, 20000)
	await _measure(dir, "01_room")
	Engine.time_scale = time_scale
	for i in [1, 2]:
		await _until(func() -> bool: return panel.button_state(i) == "ready", 20000)
		panel.press_phase(i)
		await _finish_phase(i)
	Engine.time_scale = 1.0
	await _until(func() -> bool: return panel.button_state(3) == "ready", 20000)
	panel.press_phase(3)
	await get_tree().create_timer(3.0).timeout
	await _measure(dir, "02_p3_a")
	await get_tree().create_timer(5.0).timeout
	await _measure(dir, "03_p3_b")
	await _finish_phase(3)
	await _until(func() -> bool: return panel.unlocked, 20000)
	for v: StringName in [&"Window", &"Panel", &"Room"]:
		await _until(func() -> bool: return not views.is_busy(), 8000)
		views.go_to(v)
		await _until(func() -> bool: return views.current == v and not views.is_busy(), 8000)
		await _measure(dir, "04_view_" + v)
	crisis._start_meltdown()
	await get_tree().create_timer(15.0).timeout
	await _measure(dir, "05_melt_a")
	await get_tree().create_timer(15.0).timeout
	await _measure(dir, "06_melt_b")
	_set_exp(_arg("--exp="), false)
	print("[bench] listo")
	get_tree().quit()

var _shadow_backup: Dictionary = {}

class _Stamp extends Node:
	var on_tick: Callable
	func _process(_d: float) -> void:
		on_tick.call()

var _t_early := 0
var _t_prev := 0
var _nodes_prev := 0

func _hitch_early() -> void:
	_t_prev = _t_early
	_t_early = Time.get_ticks_usec()

func _hitch_late() -> void:
	var now := Time.get_ticks_usec()
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var frame := (_t_early - _t_prev) / 1000.0
	if _t_prev > 0 and frame > 25.0:
		var comp := 0
		for k in [RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH,
				RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW,
				RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION]:
			comp += RenderingServer.get_rendering_info(k)
		print("[hitch] t=%6.1f  frame %6.1f ms  scripts(este) %5.1f ms  nodos %+d  estado %d  compil %d" % [
			music.track_time(), frame, (now - _t_early) / 1000.0, nodes - _nodes_prev, crisis.state, comp])
	var sc := (now - _t_early) / 1000.0
	if sc > 3.0 and "--spikes" in OS.get_cmdline_user_args():
		print("[spike] t=%6.1f  scripts %5.1f ms  frame %d" % [music.track_time(), sc, Engine.get_process_frames()])
	_nodes_prev = nodes

func _bench2() -> void:
	var early := _Stamp.new()
	early.process_priority = -100000
	early.on_tick = _hitch_early
	var late := _Stamp.new()
	late.process_priority = 100000
	late.on_tick = _hitch_late
	get_tree().root.add_child.call_deferred(early)
	get_tree().root.add_child.call_deferred(late)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if pause_menu:
		pause_menu.pause_on_focus_loss = false
	get_tree().create_timer(400.0).timeout.connect(get_tree().quit)
	var gs := get_node_or_null(^"../GameSettings")
	if gs and "--fast" in OS.get_cmdline_user_args():
		gs.set_value("graphics", 1)
	var vp: SubViewport = get_node(^"../PixelViewport")
	RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
	var k := _arg("--scale=").to_int()
	if k > 1:
		var display := get_node(^"../Display")
		display.base_size = Vector2i(320, 180) * k
		display._update_layout()
		print("[prof] viewport ", vp.size)
	await get_tree().create_timer(1.5).timeout
	if intro:
		intro.start()
	await _until(func() -> bool: return panel != null and not views.cinematic, 20000)
	_set_exp(_arg("--exp="), true)
	await _profile("room", 2.0)
	await _skip_init()
	await _profile("init_done", 2.0)
	if "--count" in OS.get_cmdline_user_args():
		_count_geometry()
		for sv: SubViewport in get_tree().root.find_children("*", "SubViewport", true, false):
			print("[vp] %-60s %s upd=%d 3d=%s own=%s" % [str(sv.get_path()).replace("/root/Node3D/", ""), sv.size, sv.render_target_update_mode, not sv.disable_3d, sv.own_world_3d])
	crisis._start_meltdown()
	await get_tree().create_timer(3.0).timeout
	await _profile("melt_act1", 2.0)
	music.seek_track(130.0)
	await get_tree().create_timer(3.0).timeout
	await _profile("melt_act3", 2.0)
	music.seek_track(168.0)
	await get_tree().create_timer(4.0).timeout
	for i in 8:
		_set_exp(_arg("--exp="), true)
		await _profile("climax_%d" % i, 2.0)
		if "--climaxshots" in OS.get_cmdline_user_args():
			await _shot("user://devshots", "climax_%d" % i)
	if gs and "--fast" in OS.get_cmdline_user_args():
		gs.set_value("graphics", 2)
	_set_exp(_arg("--exp="), false)
	print("[prof] listo")
	get_tree().quit()

func _count_geometry() -> void:
	var vp := get_node(^"../PixelViewport")
	var per := {}
	for gi: GeometryInstance3D in vp.find_children("*", "GeometryInstance3D", true, false):
		if not gi.is_visible_in_tree():
			continue
		var path := str(vp.get_path_to(gi)).split("/")
		var key := "/".join(path.slice(0, mini(2, path.size() - 1)))
		var surf := 1
		var mi := gi as MeshInstance3D
		if mi and mi.mesh:
			surf = mi.mesh.get_surface_count()
		var tris := 0
		if mi and mi.mesh:
			for si in mi.mesh.get_surface_count():
				var arr := mi.mesh.surface_get_arrays(si)
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				tris += (idx.size() if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		if not per.has(key):
			per[key] = [0, 0, 0, 0]
		per[key][0] += 1
		per[key][1] += surf
		per[key][2] += tris
		if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			per[key][3] += 1
	var surf_total := 0
	var mat_total := 0
	var by_group := {}
	for mi: MeshInstance3D in vp.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var mats := {}
		for si in mi.mesh.get_surface_count():
			mats[mi.get_active_material(si)] = true
		surf_total += mi.mesh.get_surface_count()
		mat_total += mats.size()
		var g := str(vp.get_path_to(mi)).get_slice("/", 0) + "/" + str(vp.get_path_to(mi)).get_slice("/", 1)
		if not by_group.has(g):
			by_group[g] = [0, 0]
		by_group[g][0] += mi.mesh.get_surface_count()
		by_group[g][1] += mats.size()
	print("[merge] superficies %d -> materiales unicos por malla %d" % [surf_total, mat_total])
	for g in by_group:
		if by_group[g][0] > by_group[g][1]:
			print("[merge]   %-45s %d -> %d" % [g, by_group[g][0], by_group[g][1]])
	var keys := per.keys()
	keys.sort_custom(func(a, b) -> bool: return per[a][1] > per[b][1])
	for k in keys.slice(0, 30):
		print("[geo] %-55s inst %4d surf %4d tris %7d sombra %4d" % [k, per[k][0], per[k][1], per[k][2], per[k][3]])

func _profile(label: String, secs: float) -> void:
	var vp: SubViewport = get_node(^"../PixelViewport")
	var rid := vp.get_viewport_rid()
	var frames := 0
	var worst := 0
	var proc := 0.0
	var phys := 0.0
	var cpu := 0.0
	var gpu := 0.0
	var start := Time.get_ticks_usec()
	var last := start
	while Time.get_ticks_usec() - start < secs * 1000000.0:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxi(worst, now - last)
		last = now
		frames += 1
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	var n := float(maxi(frames, 1))
	var lit := 0
	var shadowed := 0
	for l: Light3D in vp.find_children("*", "Light3D", true, false):
		if l.is_visible_in_tree() and l.light_energy > 0.001:
			lit += 1
			if l.shadow_enabled:
				shadowed += 1
	print("[prof] %-10s %6.1f fps peor %5.1fms | proc %5.2f fis %5.2f | vp cpu %5.2f gpu %5.2f | draws %5d objs %5d prims %5dk | luces %d (sombra %d) nodos %d" % [
		label, frames / ((Time.get_ticks_usec() - start) / 1000000.0), worst / 1000.0,
		proc / n, phys / n, cpu / n, gpu / n,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME) / 1000,
		lit, shadowed, Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])

func _arg(prefix: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return ""

func _set_exp(exp: String, on: bool) -> void:
	if exp == "":
		return
	var root := get_node(^"../PixelViewport")
	for l: Light3D in root.find_children("*", "Light3D", true, false):
		var p := str(l.get_path())
		var strip := "strip" in exp and l.name.begins_with("Strip")
		if "allshadow" in exp or ("laser" in exp and "Lasers" in p) or strip:
			if not _shadow_backup.has(l):
				_shadow_backup[l] = l.shadow_enabled
			l.shadow_enabled = false if on else _shadow_backup[l]
	if "nobh" in exp:
		for mi: MeshInstance3D in root.get_node(^"BlackHole").find_children("*", "MeshInstance3D", true, false):
			mi.visible = not on
	var pv := root as SubViewport
	if "atlas" in exp:
		if not _shadow_backup.has("atlas"):
			_shadow_backup["atlas"] = pv.positional_shadow_atlas_size
		pv.positional_shadow_atlas_size = int(exp.get_slice("atlas", 1).to_int()) if on else _shadow_backup["atlas"]
	if "steps" in exp:
		var bh := root.get_node(^"BlackHole")
		if not _shadow_backup.has("steps"):
			_shadow_backup["steps"] = bh.march_steps
		bh.march_steps = int(exp.get_slice("steps", 1).to_int()) if on else _shadow_backup["steps"]
	if "noshield" in exp:
		root.get_node(^"Outside/GravityShield").visible = not on
	if "noglow" in exp:
		root.get_node(^"RoomEnvironment").environment.glow_enabled = not on
	if "nolit" in exp:
		for l: Light3D in root.find_children("*", "Light3D", true, false):
			l.visible = not on
	if "nolasers" in exp:
		root.get_node(^"Outside/Lasers").visible = not on
	if "noscreens" in exp:
		for sv: SubViewport in root.find_children("*", "SubViewport", true, false):
			if sv.disable_3d:
				sv.render_target_update_mode = SubViewport.UPDATE_DISABLED if on else SubViewport.UPDATE_ALWAYS
				for c in sv.get_children():
					if c is CanvasItem:
						c.visible = not on
	if "nohud" in exp:
		for n in ["HudLayer", "CinematicLayer", "MenuLayer"]:
			root.get_node(NodePath(n)).visible = not on
	if "nooutside" in exp:
		root.get_node(^"Outside").visible = not on
	if "oldquant" in exp:
		get_node(^"../Display").set_quantize_in_viewport(not on)
	if "fast" in exp:
		var gs := get_node_or_null(^"../GameSettings")
		if gs:
			gs.set_value("graphics", 1 if on else 2)

func _measure(dir: String, label: String) -> void:
	_set_exp(_arg("--exp="), true)
	await get_tree().create_timer(1.0).timeout
	var ab := _arg("--ab=")
	if ab != "":
		process_mode = Node.PROCESS_MODE_ALWAYS
		get_tree().paused = true
		for i in 3:
			await get_tree().process_frame
		await _shot(dir, label + "_A")
		_set_exp(ab, true)
		for i in 3:
			await get_tree().process_frame
		await _shot(dir, label + "_B")
		_set_exp(ab, false)
		get_tree().paused = false
	var frames := 0
	var worst := 0
	var start := Time.get_ticks_usec()
	var last := start
	while Time.get_ticks_usec() - start < 2000000:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxi(worst, now - last)
		last = now
		frames += 1
	var secs := (Time.get_ticks_usec() - start) / 1000000.0
	print("[bench] %-14s %6.1f fps  peor %5.1f ms  draws %d  objs %d  prims %dk" % [label, frames / secs, worst / 1000.0,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME) / 1000])
	if ab == "":
		await _shot(dir, label)

func _pause_shots(dir: String) -> void:
	var pm := pause_menu
	pm.open()
	await get_tree().create_timer(1.0).timeout
	await _shot(dir, "p0_main")
	pm._set_page(pm.Page.SETTINGS)
	await get_tree().create_timer(0.3).timeout
	await _shot(dir, "p1_grow")
	await get_tree().create_timer(1.0).timeout
	for t in 3:
		pm._tab = t
		pm._set_hover(pm.CrtTerminal.SETTING_TABS[t].rows[0].id, false)
		await get_tree().create_timer(0.4).timeout
		await _shot(dir, "p2_tab%d" % t)
	pm._set_hover("", false)
	pm._set_page(pm.Page.MAIN)
	await get_tree().create_timer(1.2).timeout
	await _shot(dir, "p3_back")
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
