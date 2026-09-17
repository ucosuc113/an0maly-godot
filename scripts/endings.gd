extends Node

# Finales desbloqueados. Vive como nodo en main.tscn (Endings) y se guarda en
# user://endings.cfg: sobrevive a reiniciar la partida y el juego.
#
#   endings.unlock(&"freeze")    -> unlocked(id) (solo la primera vez)
#   endings.is_unlocked(id)
#   endings.reset()              -> borra todo (boton RESET del CRT)

signal unlocked(id: StringName)
signal changed

const PATH := "user://endings.cfg"
const SECTION := "endings"

## Orden en la lista del CRT. `hint` se muestra mientras esta bloqueado.
const ENDINGS := [
	{"id": &"freeze", "title": "CRYOGENIC COLLAPSE", "hint": "COLD IS ALSO A WEAPON"},
	{"id": &"meltdown", "title": "EVENT HORIZON BREACH", "hint": "LET IT BURN"},
	{"id": &"shutdown", "title": "EMERGENCY SHUTDOWN", "hint": "PULL THE PLUG IN TIME"},
	{"id": &"averted", "title": "CATASTROPHE AVERTED", "hint": "COOL IT BEFORE IT ENDS"},
]

var _unlocked: Dictionary = {}

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		for e in ENDINGS:
			if cfg.get_value(SECTION, String(e.id), false):
				_unlocked[e.id] = true

func is_unlocked(id: StringName) -> bool:
	return _unlocked.has(id)

func count() -> int:
	return _unlocked.size()

func total() -> int:
	return ENDINGS.size()

func info(id: StringName) -> Dictionary:
	for e in ENDINGS:
		if e.id == id:
			return e
	return {}

## Devuelve true si es nuevo.
func unlock(id: StringName) -> bool:
	if _unlocked.has(id) or info(id).is_empty():
		return false
	_unlocked[id] = true
	_save()
	unlocked.emit(id)
	changed.emit()
	return true

func reset() -> void:
	_unlocked.clear()
	_save()
	changed.emit()

func _save() -> void:
	var cfg := ConfigFile.new()
	for e in ENDINGS:
		cfg.set_value(SECTION, String(e.id), _unlocked.has(e.id))
	cfg.save(PATH)
