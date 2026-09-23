extends Node

# Ajustes del jugador: se guardan en user://settings.cfg y se aplican al
# momento. Vive como nodo en main.tscn (GameSettings). La pantalla del CRT
# los muestra y edita a traves de get_value / set_value.

signal changed(id: String, value: Variant)

const PATH := "user://settings.cfg"
const SECTION := "settings"
const LEVEL_MAX := 10
const GRAPHICS_FAST := 0
const GRAPHICS_MEDIUM := 1
const GRAPHICS_HIGH := 2

## Valores por defecto. Niveles de volumen: 0..LEVEL_MAX.
const DEFAULTS := {
	"fullscreen": false,
	"vsync": true,
	"master_volume": 8,
	"music_volume": 7,
	"sfx_volume": 8,
	"mute_unfocused": true,
	"reduce_flashing": false,
	"bloom": true,
	"extra_lights": true,
	"graphics": 2,
	"show_fps": false,
}

## Bus de audio que controla cada ajuste de volumen. Music y SFX se crean si el
## proyecto aun no los tiene (enviando a Master).
const VOLUME_BUSES := {
	"master_volume": "Master",
	"music_volume": "Music",
	"sfx_volume": "SFX",
}

## WorldEnvironment cuyo glow controla "bloom".
@export var bloom_environment: WorldEnvironment
## Nodos con luces decorativas que controla "extra_lights" (se ocultan: una
## luz oculta no cuesta nada). Pensado para equipos lentos.
@export var extra_lights: Array[Node3D] = []

const PIXEL_VIEWPORT := ^"../PixelViewport"

var _values: Dictionary = DEFAULTS.duplicate()
var _proxies: Node3D
var _fps: CanvasLayer
## Master silenciado porque la ventana perdio el foco (y mute_unfocused esta ON).
var _unfocused_muted: bool = false

func _ready() -> void:
	_ensure_buses()
	var vp := get_node_or_null(PIXEL_VIEWPORT)
	if vp:
		_proxies = preload("res://scripts/render_tuning.gd").new()
		_proxies.name = "RenderTuning"
		vp.add_child.call_deferred(_proxies)
	_load()
	for id in _values:
		_apply(id)

func get_value(id: String) -> Variant:
	return _values.get(id, DEFAULTS.get(id))

func set_value(id: String, value: Variant) -> void:
	if not DEFAULTS.has(id):
		push_warning("Ajuste desconocido: %s" % id)
		return
	if id == "graphics":
		value = clampi(int(value), GRAPHICS_FAST, GRAPHICS_HIGH)
	elif typeof(DEFAULTS[id]) == TYPE_INT:
		value = clampi(int(value), 0, LEVEL_MAX)
	if _values[id] == value:
		return
	_values[id] = value
	_apply(id)
	_save()
	changed.emit(id, value)

func toggle(id: String) -> void:
	set_value(id, not bool(get_value(id)))

func _apply(id: String) -> void:
	var value: Variant = _values[id]
	match id:
		"fullscreen":
			var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if value \
				else DisplayServer.WINDOW_MODE_WINDOWED
			if DisplayServer.window_get_mode() != mode:
				DisplayServer.window_set_mode(mode)
		"vsync":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if value
				else DisplayServer.VSYNC_DISABLED)
		"master_volume", "music_volume", "sfx_volume":
			var bus := AudioServer.get_bus_index(VOLUME_BUSES[id])
			if bus < 0:
				return
			var level: int = value
			AudioServer.set_bus_mute(bus, level == 0 or (bus == 0 and _unfocused_muted))
			AudioServer.set_bus_volume_db(bus, linear_to_db(float(level) / LEVEL_MAX))
		"bloom":
			if bloom_environment and bloom_environment.environment:
				bloom_environment.environment.glow_enabled = value
		"extra_lights":
			for n in extra_lights:
				if n:
					n.visible = value
		"graphics":
			_apply_graphics.call_deferred(value)
		"show_fps":
			if value and _fps == null:
				_fps = preload("res://scripts/fps_counter.gd").new()
				add_child(_fps)
			if _fps:
				_fps.visible = value
				_fps.set_process(value)
		# mute_unfocused se aplica en _notification; reduce_flashing lo leen los
		# efectos que destellan (por ahora, el apagado del CRT).

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			_unfocused_muted = bool(get_value("mute_unfocused"))
			_apply("master_volume")
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_unfocused_muted = false
			_apply("master_volume")

func _ensure_buses() -> void:
	for bus_name in VOLUME_BUSES.values():
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")

func _load() -> void:
	if OS.has_feature("mobile"):
		_values["graphics"] = GRAPHICS_MEDIUM
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	# Archivos de antes de los tres niveles: HIGH / FAST pasan a ALTO / MEDIO.
	if not cfg.has_section_key(SECTION, "graphics") and cfg.has_section_key(SECTION, "high_graphics"):
		_values["graphics"] = GRAPHICS_HIGH if bool(cfg.get_value(SECTION, "high_graphics")) else GRAPHICS_MEDIUM
	for id in DEFAULTS:
		var v: Variant = cfg.get_value(SECTION, id, _values[id])
		# Ignora valores de tipo equivocado (archivo editado a mano o viejo).
		if typeof(v) == typeof(DEFAULTS[id]):
			_values[id] = v

func _save() -> void:
	var cfg := ConfigFile.new()
	for id in _values:
		cfg.set_value(SECTION, id, _values[id])
	cfg.save(PATH)

## ALTO: sombras y agujero negro completo. MEDIO: sin sombras, raymarch
## corto. RAPIDO: MEDIO + luz Lambert sin especular (-30% de GPU, ~6% mas
## oscuro) y pantallas 2D a 30 Hz.
func _apply_graphics(level: int) -> void:
	var vp := get_node_or_null(PIXEL_VIEWPORT) as SubViewport
	if vp == null:
		return
	var high := level >= GRAPHICS_HIGH
	if _proxies:
		_proxies.fast = not high
		_proxies.cheap_lighting = level <= GRAPHICS_FAST
		_proxies.half_rate_screens = level <= GRAPHICS_FAST
	vp.positional_shadow_atlas_size = 2048 if high else 1024
	var split := vp.get_node_or_null(^"SplitLayer/SplitView")
	if split:
		split.half_rate = level <= GRAPHICS_FAST
	var bh := vp.get_node_or_null(^"BlackHole")
	if bh:
		bh.march_steps = 140 if high else 48
		bh.max_octaves = 5 if high else 2
