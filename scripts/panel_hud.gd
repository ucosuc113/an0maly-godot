extends Control

# HUD del panel de control, dibujado sobre la franja de split_view.gd. La
# franja tiene ~63 filas: ahi las texturas de las placas (numeros 5x7,
# simbolos 15x9) quedan mas chicas que su tamano nativo y no se leen. El HUD
# pone encima, en la UI pixel del juego y siguiendo a cada modulo en 3D:
#
#   palancas -> etiqueta con su simbolo nitido + nivel actual (o candado), y un
#               medidor 1..5 justo sobre la columna de numeros de la placa.
#   botones  -> etiqueta 01/02/03: candado si esta bloqueado, esquinas
#               naranjas que laten si es el que toca, parpadeo mientras su
#               fase corre, verde si ya se hizo.
#
# Los puntos se sacan de las mallas: las superficies con textura "1".."5" son
# la columna de niveles; la otra textura con nombre de simbolo es el icono.

const PixelFont = preload("res://scripts/pixel_font.gd")
const PanelIcons = preload("res://scripts/panel_icons.gd")
const REVEAL_SHADER = preload("res://shaders/dither_reveal.gdshader")

## Nodo con control_panel.gd.
@export var panel: Node
@export var frame_color: Color = Color(0.3, 0.3, 0.33)
@export var fill_color: Color = Color(0.02, 0.02, 0.025, 0.85)
@export var dim_color: Color = Color(0.42, 0.42, 0.45)
@export var text_color: Color = Color(0.96, 0.95, 0.92)
@export var accent_color: Color = Color(1.0, 0.52, 0.14)
@export var done_color: Color = Color(0.45, 1.0, 0.55)

var _split: Node
var _material: ShaderMaterial
var _time: float = 0.0
## id -> {icon: String, icon_pos: Vector3, first: Vector3, last: Vector3}
var _levers: Dictionary = {}
## [Vector3] centro de cada boton de fase.
var _buttons: Array = []
var _scanned: bool = false

func _ready() -> void:
	_split = get_parent()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = REVEAL_SHADER
	material = _material
	if panel:
		panel.phase_completed.connect(func(_i: int) -> void: queue_redraw())
		panel.levers_unlocked.connect(queue_redraw)
		panel.level_changed.connect(func(_l: StringName, _v: int) -> void: queue_redraw())

func _process(delta: float) -> void:
	if not _split.is_open():
		return
	_time += delta
	# Aparece junto con la pestana de la division.
	_material.set_shader_parameter("progress", clampf((_split.open_progress() - 0.5) / 0.5, 0.0, 1.0))
	queue_redraw()

# --- Puntos de referencia ------------------------------------------------------

func _scan() -> void:
	_scanned = true
	var nodes: Dictionary = panel.lever_nodes()
	for id in nodes:
		var n: Node3D = nodes[id]
		if n == null:
			continue
		var info := {"icon": "", "icon_pos": Vector3.ZERO, "first": Vector3.ZERO, "last": Vector3.ZERO}
		for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
			for s in mi.mesh.get_surface_count():
				var m := mi.get_active_material(s) as BaseMaterial3D
				if m == null or m.albedo_texture == null:
					continue
				var key := m.albedo_texture.resource_path.get_file().get_basename()
				var center := _surface_center(mi, s)
				if key == "1":
					info.first = center
				elif key == "5":
					info.last = center
				elif PanelIcons.has(key):
					info.icon = key
					info.icon_pos = center
		_levers[id] = info
	for b: Node3D in panel.phase_buttons:
		_buttons.append(_node_center(b) if b else Vector3.ZERO)

func _surface_center(mi: MeshInstance3D, surface: int) -> Vector3:
	var verts: PackedVector3Array = mi.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
	var box := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		box = box.expand(v)
	return mi.global_transform * box.get_center()

func _node_center(n: Node3D) -> Vector3:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box.get_center() if not first else n.global_position

## Punto 3D -> pixel de este Control (la franja empieza en pane_top).
func _project(p: Vector3) -> Vector2i:
	var cam: Camera3D = _split.camera
	var v := cam.unproject_position(p)
	return Vector2i(v.round()) + Vector2i(0, _split.pane_top())

# --- Dibujo ------------------------------------------------------------------------

func _draw() -> void:
	if panel == null or not _split.is_open():
		return
	if not _scanned:
		_scan()
	for id in _levers:
		_draw_lever(id, _levers[id])
	for i in _buttons.size():
		_draw_button(i + 1, _buttons[i])

func _draw_lever(id: StringName, info: Dictionary) -> void:
	var locked: bool = panel.levers_locked()
	var level: int = panel.get_level(id)
	var icon: String = info.icon
	var group: Color = PanelIcons.COLORS.get(icon, accent_color)

	# Medidor sobre la columna de numeros: 5 segmentos entre el "1" y el "5".
	var p1 := _project(info.first)
	var p5 := _project(info.last)
	var top := mini(p1.y, p5.y) - 3
	var bottom := maxi(p1.y, p5.y) + 3
	var mx := (p1.x + p5.x) / 2
	draw_rect(Rect2(mx - 4, top, 9, bottom - top), fill_color)
	_frame(Rect2i(mx - 4, top, 9, bottom - top), frame_color)
	for i in range(1, 6):
		var p := Vector2(p1).lerp(Vector2(p5), (i - 1) / 4.0).round()
		var seg := Rect2(p.x - 2, p.y - 1, 5, 3)
		if locked:
			draw_rect(seg, dim_color.darkened(0.4))
		elif i <= level:
			var lc: Color = PanelIcons.LEVEL_COLORS[i - 1]
			draw_rect(seg, lc if i == level else lc.darkened(0.45))
		else:
			draw_rect(seg, dim_color.darkened(0.55))
	# Marca del nivel actual, afuera de la columna.
	if not locked:
		var cur := Vector2(p1).lerp(Vector2(p5), (level - 1) / 4.0).round()
		draw_rect(Rect2(mx + 6, cur.y - 1, 2, 3), PanelIcons.LEVEL_COLORS[level - 1])

	# Etiqueta: simbolo + nivel (o candado), centrada sobre el simbolo 3D.
	var c := _project(info.icon_pos)
	var box := Rect2i(c.x - 14, c.y - 6, 29, 13)
	# Nunca encima del medidor: si se cruzan, la etiqueta sube.
	box.position.y = mini(box.position.y, top - box.size.y - 1)
	draw_rect(box, fill_color)
	_frame(box, dim_color if locked else group)
	PanelIcons.draw(self, icon, box.position + Vector2i(2, 2),
		dim_color if locked else group)
	var glyph := "🔒" if locked else str(level)
	var gc: Color = dim_color if locked else PanelIcons.LEVEL_COLORS[level - 1]
	PixelFont.draw(self, glyph, Vector2(box.position.x + 20, box.position.y + 3), gc)

func _draw_button(index: int, center: Vector3) -> void:
	var state: String = panel.button_state(index)
	var c := _project(center)
	var label := "%02d" % index
	var col := text_color
	var border := frame_color
	match state:
		"locked":
			col = dim_color
			label = "🔒" + str(index)
		"done":
			col = done_color
			border = done_color
		"running":
			# En curso: marco naranja fijo y texto que parpadea rapido.
			border = accent_color
			col = accent_color if fmod(_time, 0.3) < 0.15 else text_color
		"ready":
			var on := fmod(_time, 0.9) < 0.6
			border = accent_color if on else frame_color
			# Esquinas que laten alrededor del boton: "este es el que toca".
			if on:
				_brackets(Rect2i(c.x - 9, c.y - 9, 19, 19), accent_color)

	var tw := PixelFont.text_width(label)
	var box := Rect2i(c.x - (tw + 6) / 2, c.y - 23, tw + 6, 11)
	box.position.y = maxi(box.position.y, _split.pane_top() + 7)
	draw_rect(box, fill_color)
	_frame(box, border)
	PixelFont.draw(self, label, Vector2(box.position.x + 3, box.position.y + 2), col)

func _frame(r: Rect2i, color: Color) -> void:
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 1), color)
	draw_rect(Rect2(r.position.x, r.end.y - 1, r.size.x, 1), color)
	draw_rect(Rect2(r.position.x, r.position.y, 1, r.size.y), color)
	draw_rect(Rect2(r.end.x - 1, r.position.y, 1, r.size.y), color)

func _brackets(r: Rect2i, color: Color) -> void:
	var L := 4
	for corner in [r.position, Vector2i(r.end.x - 1, r.position.y),
			Vector2i(r.position.x, r.end.y - 1), r.end - Vector2i.ONE]:
		var sx := 1 if corner.x == r.position.x else -1
		var sy := 1 if corner.y == r.position.y else -1
		draw_rect(Rect2(mini(corner.x, corner.x + sx * (L - 1)), corner.y, L, 1), color)
		draw_rect(Rect2(corner.x, mini(corner.y, corner.y + sy * (L - 1)), 1, L), color)
