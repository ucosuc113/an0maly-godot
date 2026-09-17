extends Control

# Pantalla de "restableciendo instalaciones" despues de un final. Negro, texto
# de terminal en ambar (el mismo lenguaje del CRT) y una barra de progreso;
# al terminar recarga la escena y la partida empieza directo, como recien
# presionado ENTER THE ANOMALY (crt_monitor.gd DIRECT_START_META).

const PixelFont = preload("res://scripts/pixel_font.gd")
const CrtMonitor = preload("res://scripts/crt_monitor.gd")

@export var phosphor: Color = Color(1.0, 0.66, 0.12)
@export var sfx: Node

var _lines: Array = []
var _fade: float = 0.0
var _progress: float = -1.0
var _time: float = 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

## `headline`: primera linea (p. ej. el motivo). Recarga la escena al final.
func play(headline: String) -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	var t := create_tween()
	t.tween_property(self, "_fade", 1.0, 1.2)
	await t.finished
	await _wait(0.8)
	var steps := [
		[headline, 2, 0.6],
		["", 1, 0.3],
		["> FACILITY INTEGRITY ..... LOST", 1, 0.5],
		["> RESTORING FACILITY", 1, 0.2],
	]
	for s in steps:
		await _type(s[0], s[1])
		await _wait(s[2])
	_progress = 0.0
	var bar := create_tween()
	bar.tween_property(self, "_progress", 1.0, 3.0).set_trans(Tween.TRANS_SINE)
	await bar.finished
	_progress = -1.0
	for s in [
		["> REBUILDING CONTAINMENT .. OK", 1, 0.35],
		["> RESEEDING LASER ARRAY ... OK", 1, 0.35],
		["> RESETTING CORE .......... OK", 1, 0.5],
		["", 1, 0.2],
		["FACILITY READY.", 2, 1.4],
	]:
		await _type(s[0], s[1])
		await _wait(s[2])
	get_tree().root.set_meta(CrtMonitor.DIRECT_START_META, true)
	get_tree().paused = false
	get_tree().reload_current_scene()

func _type(text: String, tone: int) -> void:
	_lines.append([text, tone])
	if sfx and not text.is_empty():
		sfx.play("crt_type", -6.0, randf_range(0.95, 1.08))
	if text.ends_with("OK"):
		if sfx:
			sfx.play("crt_ok", -4.0)

func _wait(s: float) -> void:
	await get_tree().create_timer(s, true).timeout

func _process(delta: float) -> void:
	if visible:
		_time += delta
		queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, _fade))
	if _fade < 1.0:
		return
	var x := int(size.x) / 2 - 90
	var y := int(size.y) / 2 - 36
	for l in _lines:
		var col := phosphor.lerp(Color.WHITE, 0.45) if l[1] == 2 else phosphor
		PixelFont.draw(self, l[0], Vector2(x, y), col)
		y += 10
	if _progress >= 0.0:
		var w := 150
		draw_rect(Rect2(x, y + 2, w, 1), phosphor.darkened(0.5))
		draw_rect(Rect2(x, y + 8, w, 1), phosphor.darkened(0.5))
		draw_rect(Rect2(x, y + 3, int(w * _progress), 5), phosphor)
		var pct := "%3d%%" % int(_progress * 100.0)
		PixelFont.draw(self, pct, Vector2(x + w + 6, y + 1), phosphor)
	elif fmod(_time, 0.5) < 0.25:
		draw_rect(Rect2(x, y, 5, 7), phosphor)
