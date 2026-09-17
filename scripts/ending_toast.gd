extends Control

# Aviso de final desbloqueado, en la esquina superior derecha (como un logro,
# pero de finales). Entra deslizandose, se escribe el nombre y sale.
#
#   ENDING UNLOCKED            2/4
#   CRYOGENIC COLLAPSE

const PixelFont = preload("res://scripts/pixel_font.gd")

@export var endings: Node
@export var sfx: Node
@export var hold_time: float = 4.5
@export var margin: Vector2i = Vector2i(6, 20)
@export var fill_color: Color = Color(0.012, 0.012, 0.016, 0.88)
@export var frame_color: Color = Color(0.3, 0.3, 0.33)
@export var accent_color: Color = Color(1.0, 0.52, 0.14)
@export var title_color: Color = Color(0.96, 0.95, 0.92)
@export var dim_color: Color = Color(0.5, 0.5, 0.55)

var _queue: Array[StringName] = []
var _showing: bool = false
var _slide: float = 0.0
var _title: String = ""
var _chars: int = 0
var _counter: String = ""
var _time: float = 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	if endings:
		endings.unlocked.connect(_on_unlocked)

func _on_unlocked(id: StringName) -> void:
	_queue.append(id)
	if not _showing:
		_next()

func _next() -> void:
	if _queue.is_empty():
		_showing = false
		return
	_showing = true
	var id: StringName = _queue.pop_front()
	_title = endings.info(id).get("title", String(id))
	_counter = "%d/%d" % [endings.count(), endings.total()]
	_chars = 0
	if sfx:
		sfx.play("ending_unlock")
	var t := create_tween()
	t.tween_property(self, "_slide", 1.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for i in _title.length():
		t.tween_callback(func() -> void: _chars = i + 1)
		t.tween_interval(0.03)
	t.tween_interval(hold_time)
	t.tween_property(self, "_slide", 0.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	await t.finished
	_next()

func _process(delta: float) -> void:
	_time += delta
	# Siempre: si solo se redibujara con _slide > 0, el ultimo cuadro de la
	# salida quedaria pegado en pantalla.
	queue_redraw()

func _draw() -> void:
	if _slide <= 0.0:
		return
	var w := maxi(PixelFont.text_width(_title) + 16, 110)
	var h := 26
	var x := int(size.x) - margin.x - int(round(w * _slide))
	var r := Rect2i(x, margin.y, w, h)
	draw_rect(r, fill_color)
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 1), frame_color)
	draw_rect(Rect2(r.position.x, r.end.y - 1, r.size.x, 1), frame_color)
	draw_rect(Rect2(r.position.x, r.position.y, 1, r.size.y), frame_color)
	draw_rect(Rect2(r.end.x - 1, r.position.y, 1, r.size.y), frame_color)
	# Franja naranja a la izquierda que late.
	var pulse := 0.7 + 0.3 * sin(_time * 6.0)
	draw_rect(Rect2(r.position.x, r.position.y, 3, r.size.y), Color(accent_color, pulse))
	PixelFont.draw(self, "ENDING UNLOCKED", Vector2(r.position.x + 7, r.position.y + 4), accent_color)
	PixelFont.draw(self, _counter,
		Vector2(r.end.x - 6 - PixelFont.text_width(_counter), r.position.y + 4), dim_color)
	PixelFont.draw(self, _title.substr(0, _chars), Vector2(r.position.x + 7, r.position.y + 15), title_color)
