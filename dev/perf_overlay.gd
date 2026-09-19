extends CanvasLayer

# HERRAMIENTA DE DESARROLLO. Nada del juego la referencia.
# Muestra FPS, peor frame, CPU/GPU del render 3D, draw calls y pico de scripts.
#
# Conectar: Proyecto > Configuracion > Autoload > res://dev/perf_overlay.gd
# (o agregarla como nodo en main.tscn). Solo corre desde el editor, o en una
# exportacion cuyo preset tenga la etiqueta "perf_overlay" en Custom Features.
# En cualquier otro caso se borra sola.

const PixelFont = preload("res://scripts/pixel_font.gd")
const FEATURE := "perf_overlay"

var _label: _Readout

func _ready() -> void:
	if not (OS.has_feature("editor") or OS.has_feature(FEATURE)):
		queue_free()
		return
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_label = _Readout.new()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_attach.call_deferred()

## Se muda al PixelViewport para dibujar en la misma rejilla que el juego.
func _attach() -> void:
	var vp: SubViewport = null
	while vp == null:
		var scene := get_tree().current_scene
		if scene:
			vp = scene.get_node_or_null(^"PixelViewport") as SubViewport
		if vp == null:
			await get_tree().process_frame
	if get_parent() != vp:
		reparent(vp, false)
	_label.vp_rid = vp.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_label.vp_rid, true)

class _Readout extends Control:
	var vp_rid: RID
	var _t: float = 1.0
	var _worst: float = 0.0
	var _lines: PackedStringArray = []

	func _process(delta: float) -> void:
		_t += delta
		_worst = maxf(_worst, delta)
		if _t < 0.5 or not vp_rid.is_valid():
			return
		_t = 0.0
		_lines = [
			"%d FPS  MAX %dMS" % [Engine.get_frames_per_second(), roundi(_worst * 1000.0)],
			"3D CPU %.1f GPU %.1f" % [RenderingServer.viewport_get_measured_render_time_cpu(vp_rid),
				RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)],
			"DC %d  SCR %.1f" % [
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0],
		]
		_worst = 0.0
		queue_redraw()

	func _draw() -> void:
		var w := 0
		for l in _lines:
			w = maxi(w, PixelFont.text_width(l))
		var x: int = int(size.x) - w - 3
		var h: int = _lines.size() * (PixelFont.GLYPH_H + 2)
		draw_rect(Rect2(x - 2, 1, w + 4, h + 1), Color(0.0, 0.0, 0.0, 0.7))
		for i in _lines.size():
			var c := Color(0.45, 1.0, 0.55) if i == 0 else Color(0.45, 0.8, 1.0)
			PixelFont.draw(self, _lines[i], Vector2(x, 2 + i * (PixelFont.GLYPH_H + 2)), c)
