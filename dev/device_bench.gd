extends CanvasLayer

# HERRAMIENTA DE DESARROLLO. Solo corre en una exportacion con la etiqueta
# "auto_bench" en Custom Features (dev_shortcuts.gd la carga). Juega sola:
# fase 1, mide cada calidad en SALA / PANEL / VENTANA, fase 2 y otra vez; al
# final deja la tabla en pantalla (y en user://bench.txt).

const FEATURE := "auto_bench"
const TIERS := [[2, "HIGH"], [1, "MED"], [0, "FAST"]]
const VIEWS := [&"Room", &"Panel", &"Window"]
const MEASURE_S := 3.0

var _label: Label
var _bg: ColorRect
var _lines: PackedStringArray = []
var _main: Node

func _ready() -> void:
	layer = 125
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bg = ColorRect.new()
	var bg := _bg
	bg.color = Color(0, 0, 0, 0.78)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.visible = false
	add_child(bg)
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85))
	var px := clampi(int(get_viewport().get_visible_rect().size.y * 0.032), 12, 48)
	_label.add_theme_font_size_override("font_size", px)
	_label.position = Vector2(px, px)
	add_child(_label)
	_say("AN0MALY BENCH  %s  %s" % [RenderingServer.get_video_adapter_name(), Vector2i(get_viewport().get_visible_rect().size)])
	_run.call_deferred()

func _say(line: String) -> void:
	print("[bench] ", line)
	_lines.append(line)
	while _lines.size() > 30:
		_lines.remove_at(0)
	_label.text = "\n".join(_lines)

func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout

func _until(cond: Callable, ms: int) -> void:
	var until := Time.get_ticks_msec() + ms
	while not cond.call() and Time.get_ticks_msec() < until:
		await get_tree().process_frame

func _run() -> void:
	_main = get_tree().current_scene
	var vp: SubViewport = _main.get_node("PixelViewport")
	var dev: Node = _main.get_node("DevShortcuts")
	var panel: Node = vp.get_node("ControlPanel")
	var views: Node = vp.get_node("CameraViews")
	var gs: Node = _main.get_node("GameSettings")
	var keep: int = gs.get_value("graphics")
	vp.get_node("PauseLayer/PauseMenu").pause_on_focus_loss = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
	await _until(func() -> bool: return not views.cinematic, 30000)
	await _wait(1.0)
	var results := []
	for phase in [1, 2]:
		_say("FASE %d..." % phase)
		Engine.time_scale = 12.0
		await _until(func() -> bool: return panel.button_state(phase) == "ready", 30000)
		panel.press_phase(phase)
		await dev._finish_phase(phase)
		await _until(func() -> bool: return panel.button_state(phase) == "done" \
			and not views.is_busy() and not views.cinematic, 40000)
		Engine.time_scale = 1.0
		await _wait(1.5)
		for v in VIEWS:
			await _until(func() -> bool: return not views.is_busy(), 8000)
			views.go_to(v)
			await _until(func() -> bool: return views.current == v and not views.is_busy(), 8000)
			var row := "F%d %-6s" % [phase, v]
			for t in TIERS:
				gs.set_value("graphics", t[0])
				await _wait(1.5)
				var r: Dictionary = await _measure(vp)
				row += "  %s %4.1f (%3.0fms cpu%4.1f)" % [t[1], r.fps, r.worst, r.cpu]
			_say(row)
			results.append(row)
	gs.set_value("graphics", keep)
	var f := FileAccess.open("user://bench.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_lines))
	_bg.visible = true
	_say("LISTO. fps promedio (peor frame, cpu render 3D)")

func _measure(vp: SubViewport) -> Dictionary:
	var rid := vp.get_viewport_rid()
	var frames := 0
	var worst := 0
	var cpu := 0.0
	var start := Time.get_ticks_usec()
	var last := start
	while Time.get_ticks_usec() - start < MEASURE_S * 1000000.0:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxi(worst, now - last)
		last = now
		frames += 1
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
	var secs := (Time.get_ticks_usec() - start) / 1000000.0
	return {"fps": frames / secs, "worst": worst / 1000.0, "cpu": cpu / maxi(frames, 1)}
