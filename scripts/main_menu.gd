extends Control

# Menu principal flotando en la oscuridad. Vive en main.tscn, en un CanvasLayer
# dentro del PixelViewport, asi que usa la misma rejilla de 180 filas,
# cuantizacion y dithering que la escena. El fondo es el negro de la escena:
# aqui no se dibuja ninguno.
#
# appear() lo dispara la senal view_cleared del monitor (la primera vez y cada
# vez que se vuelve de SETTINGS). Al elegir una opcion con algo conectado, el
# menu se desvanece y DESPUES emite la senal.

signal enter_pressed
signal settings_pressed
signal endings_pressed

const REVEAL_SHADER = preload("res://shaders/dither_reveal.gdshader")

@export var title_texture: Texture2D
## El PNG es pixel art escalado x4 (nativo 456x93). Se reduce este factor en
## total: 8 => 228x46, cabe comodo en 320x180 y deja aire para los botones.
@export var title_source_scale: int = 4
@export var title_extra_downscale: int = 2
@export var appear_delay: float = 1.0
## Nodo con sfx.gd (opcional): sonidos del menu.
@export var sfx: Node

@export_group("Layout")
## Centro vertical del titulo y del bloque de botones (0..1 del alto).
@export_range(0.0, 1.0) var title_center: float = 0.3
@export_range(0.0, 1.0) var buttons_center: float = 0.7
@export var button_spacing: int = 15
## Amplitud del flotado del titulo en pixeles (entero: nada de subpixel).
@export var title_float_px: int = 1
@export var title_float_period: float = 4.5

@onready var _title: TextureRect = $Title
@onready var _buttons: Array[Control] = [$EnterButton, $SettingsButton, $EndingsButton]

var _title_material: ShaderMaterial
var _time: float = 0.0
var _busy: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_title.texture = _build_title_texture()
	_title.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_material = ShaderMaterial.new()
	_title_material.shader = REVEAL_SHADER
	_title.material = _title_material

	$EnterButton.pressed.connect(_on_choice.bind(enter_pressed))
	$SettingsButton.pressed.connect(_on_choice.bind(settings_pressed))
	$EndingsButton.pressed.connect(_on_choice.bind(endings_pressed))
	for b in _buttons:
		b.hovered.connect(_play.bind("menu_hover"))
		b.pressed.connect(_play.bind("menu_click"))

	resized.connect(_layout)
	_set_hidden()
	_layout()

func _set_hidden() -> void:
	visible = false
	_set_title_reveal(0.0)
	for b in _buttons:
		b.reveal = 0.0
		b.interactive = false

func appear() -> void:
	if _busy or visible:
		return
	_busy = true
	await get_tree().create_timer(appear_delay).timeout
	visible = true
	_time = 0.0
	_play("menu_appear")

	var t := create_tween().set_parallel()
	# Titulo: se materializa lento.
	t.tween_method(_set_title_reveal, 0.0, 1.0, 1.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Botones: en cascada, cuando el titulo ya va por la mitad.
	for i in _buttons.size():
		t.tween_property(_buttons[i], "reveal", 1.0, 0.6) \
			.set_delay(0.8 + i * 0.22).set_trans(Tween.TRANS_SINE)
	await t.finished
	set_interactive(true)
	_busy = false

## Se desvanece (la misma disolucion, al reves y mas rapida) y se oculta.
func disappear() -> void:
	_busy = true
	set_interactive(false)
	var t := create_tween().set_parallel()
	for i in _buttons.size():
		t.tween_property(_buttons[i], "reveal", 0.0, 0.35) \
			.set_delay((_buttons.size() - 1 - i) * 0.08).set_trans(Tween.TRANS_SINE)
	t.tween_method(_set_title_reveal, 1.0, 0.0, 0.6) \
		.set_delay(0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await t.finished
	visible = false
	_busy = false

func _play(sound: String) -> void:
	if sfx:
		sfx.play(sound)

func _set_title_reveal(v: float) -> void:
	_title_material.set_shader_parameter("progress", v)

func _on_choice(sig: Signal) -> void:
	# Sin nada conectado (p. ej. ENDINGS por ahora) no se esconde el menu:
	# el boton solo destella y todo sigue igual.
	if sig.get_connections().is_empty():
		return
	await disappear()
	sig.emit()

## Desbloquea los botones otra vez (p. ej. al volver de Settings).
func set_interactive(value: bool) -> void:
	for b in _buttons:
		b.interactive = value

func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	_layout()

func _layout() -> void:
	if _title == null or _title.texture == null:
		return
	var w: int = int(size.x)
	var h: int = int(size.y)

	# Titulo centrado, con flotado de 1 px en pasos enteros.
	var ts: Vector2i = _title.texture.get_size()
	var bob: int = int(round(sin(_time * TAU / title_float_period) * title_float_px))
	_title.size = Vector2(ts)
	_title.position = Vector2(
		(w - ts.x) / 2,
		int(h * title_center) - ts.y / 2 + bob)

	# Botones apilados y centrados alrededor de buttons_center.
	var bh: int = int(_buttons[0].get_combined_minimum_size().y)
	var block: int = button_spacing * (_buttons.size() - 1) + bh
	var y: int = int(h * buttons_center) - block / 2
	for b in _buttons:
		var bs: Vector2i = Vector2i(b.get_combined_minimum_size())
		b.size = Vector2(bs)
		b.position = Vector2((w - bs.x) / 2, y)
		y += button_spacing

## Reduce el PNG a su resolucion nativa (nearest, exacto) y luego promedia
## bloques para bajar mas sin perder los bordes. El negro de fondo se vuelve
## transparencia con alfa = brillo: sobre negro se ve identico, pero el titulo
## flota sin caja y el disolvente funciona pixel a pixel.
func _build_title_texture() -> Texture2D:
	if title_texture == null:
		return null
	var img: Image = title_texture.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var native := img.get_size() / maxi(title_source_scale, 1)
	img.resize(native.x, native.y, Image.INTERPOLATE_NEAREST)
	var step := maxi(title_extra_downscale, 1)
	while step > 1:
		# Mitad exacta con bilineal = promedio 2x2 (filtro de caja).
		img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_BILINEAR)
		step /= 2

	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var a := maxf(c.r, maxf(c.g, c.b))
			if a <= 0.02:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				img.set_pixel(x, y, Color(c.r / a, c.g / a, c.b / a, a))
	return ImageTexture.create_from_image(img)
