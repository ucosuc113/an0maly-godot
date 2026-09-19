extends SceneTree

# Captura del agujero negro SIN fondo, con canal alfa, para usarlo de recurso.
#
#   "C:/ruta/a/Godot.exe" --path . --rendering-driver opengl3 --script res://scripts/capture_title.gd
#
# Script desechable: borralo cuando no lo necesites.

# --- ajusta esto ---------------------------------------------------------
# Preset pixel art:  OUT_SIZE (320, 180) / UPSCALE 4 / QUANTIZE true / TRIM true
# Preset Full HD:    OUT_SIZE (1920, 1080) / UPSCALE 1 / QUANTIZE false / TRIM false
const OUT_SIZE := Vector2i(1920, 1080) ## Resolucion a la que se renderiza.
const UPSCALE := 1                     ## Multiplicador ENTERO del PNG final.
const QUANTIZE := false                ## Aplicar el post de pixel art.
const TRIM := false                    ## Recortar al alfa util (quita el vacio).
## true  = alfa recta, el PNG se comporta bien en cualquier editor.
## false = color premultiplicado, identico a lo que ves sobre fondo negro.
const STRAIGHT_ALPHA := true
const WARMUP := 60                     ## Frames antes de disparar.
const OUT_PATH := "res://assets/black_hole_title_hd.png"
# -------------------------------------------------------------------------

var _scene: Node
var _vp: SubViewport
var _mat: ShaderMaterial
var _frames := 0

func _initialize() -> void:
	_scene = load("res://main.tscn").instantiate()
	root.add_child(_scene)

func _process(_delta: float) -> bool:
	_frames += 1

	# _ready() no ha corrido todavia dentro de _initialize(), asi que la
	# configuracion va aqui: si no, pixel_display la pisa al inicializarse.
	if _frames == 2:
		_vp = _scene.get_node("PixelViewport")
		var display := _scene.get_node("Display")
		_mat = display.quantize_material if display.quantize_material else display.material
		display.set_quantize_in_viewport(false)
		_vp.transparent_bg = true
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_vp.size = OUT_SIZE
		return false

	if _frames < WARMUP:
		return false

	var img: Image = _vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBAF)

	# Orden importante: el viewport entrega color premultiplicado, que es
	# exactamente lo que ves sobre negro. Cuantizamos ESO para que la captura
	# coincida con la pantalla, y solo despues deshacemos la premultiplicacion.
	# Al reves, los pixeles de alfa bajo se disparan a blanco antes de cuantizar.
	if QUANTIZE and _mat != null:
		_quantize(img)
	if STRAIGHT_ALPHA:
		_unpremultiply(img)
	if TRIM:
		var used: Rect2i = img.get_used_rect()
		if used.size.x > 0 and used.size.y > 0:
			img = img.get_region(used)
	if UPSCALE > 1:
		img.resize(img.get_width() * UPSCALE, img.get_height() * UPSCALE,
				Image.INTERPOLATE_NEAREST)

	img.convert(Image.FORMAT_RGBA8)
	var err: int = img.save_png(OUT_PATH)
	if err != OK:
		err = img.save_png("user://black_hole_title.png")
		print("res:// no escribible, guardado en user://  (err ", err, ")")
	print("guardado: ", img.get_width(), "x", img.get_height(), " -> ", OUT_PATH)
	return true

## Un viewport con transparent_bg entrega el color YA multiplicado por alfa.
## Sin deshacerlo, las zonas semitransparentes salen oscuras al componer.
func _unpremultiply(img: Image) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c: Color = img.get_pixel(x, y)
			if c.a > 0.0001:
				img.set_pixel(x, y, Color(c.r / c.a, c.g / c.a, c.b / c.a, c.a))

func _bayer2(x: float, y: float) -> float:
	return fposmod(floor(x) * 0.5 + floor(y) * floor(y) * 0.75, 1.0)

func _bayer4(x: float, y: float) -> float:
	return _bayer2(x * 0.5, y * 0.5) * 0.25 + _bayer2(x, y)

func _bayer8(x: float, y: float) -> float:
	return _bayer4(x * 0.5, y * 0.5) * 0.25 + _bayer2(x, y)

## Misma matematica que pixel_quantize.gdshader, leyendo SUS parametros para que
## la captura salga identica a lo que ves en pantalla.
func _quantize(img: Image) -> void:
	var steps_n: int = _param("color_steps", 5)
	var dither: float = _param("dither_strength", 0.3)
	var pattern: int = _param("dither_pattern", 4)
	var dscale: int = maxi(_param("dither_scale", 1), 1)
	var sat: float = _param("saturation", 1.3)
	var con: float = _param("contrast", 1.45)
	var black: float = _param("black_level", 0.02)
	var steps: float = float(steps_n - 1)

	for y in img.get_height():
		for x in img.get_width():
			var c: Color = img.get_pixel(x, y)
			if c.a <= 0.0001:
				continue

			var cx: float = floor(float(x) / float(dscale))
			var cy: float = floor(float(y) / float(dscale))
			var d: float
			var levels: float
			if pattern <= 2:
				d = _bayer2(cx, cy)
				levels = 4.0
			elif pattern <= 4:
				d = _bayer4(cx, cy)
				levels = 16.0
			else:
				d = _bayer8(cx, cy)
				levels = 64.0
			var threshold: float = d - (levels - 1.0) / (2.0 * levels)

			var rgb := Vector3(c.r, c.g, c.b)
			var luma: float = rgb.dot(Vector3(0.299, 0.587, 0.114))
			rgb = Vector3(luma, luma, luma).lerp(rgb, sat)
			rgb = (rgb - Vector3(0.5, 0.5, 0.5)) * con + Vector3(0.5, 0.5, 0.5)
			# mix(vec3(black_level), vec3(1.0), col)
			var bl := Vector3(black, black, black)
			rgb = bl + (Vector3.ONE - bl) * rgb
			rgb = Vector3(
				clampf(rgb.x, 0.0, 1.0), clampf(rgb.y, 0.0, 1.0), clampf(rgb.z, 0.0, 1.0))

			rgb = Vector3(
				floor(rgb.x * steps + 0.5 + threshold * dither) / steps,
				floor(rgb.y * steps + 0.5 + threshold * dither) / steps,
				floor(rgb.z * steps + 0.5 + threshold * dither) / steps)

			img.set_pixel(x, y, Color(
				clampf(rgb.x, 0.0, 1.0), clampf(rgb.y, 0.0, 1.0), clampf(rgb.z, 0.0, 1.0), c.a))

func _param(name: String, fallback: Variant) -> Variant:
	var v: Variant = _mat.get_shader_parameter(name)
	return fallback if v == null else v
