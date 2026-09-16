extends Node

# Ajustes del jugador: se guardan en user://settings.cfg y se aplican al
# momento. Vive como nodo en main.tscn (GameSettings). La pantalla del CRT
# los muestra y edita a traves de get_value / set_value.

signal changed(id: String, value: Variant)

const PATH := "user://settings.cfg"
const SECTION := "settings"
const LEVEL_MAX := 10

## Valores por defecto. Niveles de volumen: 0..LEVEL_MAX.
const DEFAULTS := {
	"fullscreen": false,
	"master_volume": 8,
	"music_volume": 7,
	"sfx_volume": 8,
	"mute_unfocused": true,
	"reduce_flashing": false,
}

## Bus de audio que controla cada ajuste de volumen. Music y SFX se crean si el
## proyecto aun no los tiene (enviando a Master).
const VOLUME_BUSES := {
	"master_volume": "Master",
	"music_volume": "Music",
	"sfx_volume": "SFX",
}

var _values: Dictionary = DEFAULTS.duplicate()
## Master silenciado porque la ventana perdio el foco (y mute_unfocused esta ON).
var _unfocused_muted: bool = false

func _ready() -> void:
	_ensure_buses()
	_load()
	for id in _values:
		_apply(id)

func get_value(id: String) -> Variant:
	return _values.get(id, DEFAULTS.get(id))

func set_value(id: String, value: Variant) -> void:
	if not DEFAULTS.has(id):
		push_warning("Ajuste desconocido: %s" % id)
		return
	if typeof(DEFAULTS[id]) == TYPE_INT:
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
		"master_volume", "music_volume", "sfx_volume":
			var bus := AudioServer.get_bus_index(VOLUME_BUSES[id])
			if bus < 0:
				return
			var level: int = value
			AudioServer.set_bus_mute(bus, level == 0 or (bus == 0 and _unfocused_muted))
			AudioServer.set_bus_volume_db(bus, linear_to_db(float(level) / LEVEL_MAX))
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
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for id in DEFAULTS:
		var v: Variant = cfg.get_value(SECTION, id, DEFAULTS[id])
		# Ignora valores de tipo equivocado (archivo editado a mano o viejo).
		if typeof(v) == typeof(DEFAULTS[id]):
			_values[id] = v

func _save() -> void:
	var cfg := ConfigFile.new()
	for id in _values:
		cfg.set_value(SECTION, id, _values[id])
	cfg.save(PATH)
