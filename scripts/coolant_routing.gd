extends Node

# Rearmado de circuitos de refrigerante (lo dibuja y lo opera el monitor
# derecho, monitor_right.gd). Vive como nodo en main.tscn para que
# reactor_sim.gd pueda leer el estado sin depender de la pantalla.
#
# El circuito son COLS bancos de rele en fila; cada banco tiene ROWS canales y
# solo UNO puede estar cerrado. El refrigerante entra por la izquierda, pasa
# de banco en banco y sale a la derecha, PERO solo salta entre bancos vecinos
# si los canales elegidos estan pegados (misma fila o una de diferencia).
#
#   IN =[1]===[1]   [ ]   [ ]   [ ]= OUT      <- cortado entre el 2do y el 3ro
#         [ ]   [ ]=[2]===[2]===[2]
#
# Durante el derretimiento los canales se van quemando de a uno (burn_one()).
# Un canal quemado no se puede elegir, asi que el jugador tiene que rehacer el
# camino. Mientras no haya camino, el escudo se queda sin caudal.
#
#   select(col, row)   elige un canal (false si esta quemado)
#   burn_one()         quema un canal; por defecto solo quema si DESPUES sigue
#                      existiendo algun camino valido
#   flow               hay camino ahora mismo

signal flow_changed(ok: bool)

const COLS := 5
const ROWS := 3

@export var sfx: Node

## Canal cerrado en cada banco.
var selected: Array[int] = []
## burned[col][row]
var burned: Array = []
## El circuito esta en juego (lo enciende el derretimiento).
var active: bool = false
## Hay camino de la entrada a la salida.
var flow: bool = true

func _ready() -> void:
	reset()

func reset() -> void:
	selected.clear()
	burned.clear()
	for c in COLS:
		selected.append(1)
		var col: Array[bool] = []
		for r in ROWS:
			col.append(false)
		burned.append(col)
	active = false
	_update_flow()

## Lo pone en juego (arranque del derretimiento).
func start() -> void:
	reset()
	active = true
	_update_flow()

func stop() -> void:
	active = false
	_update_flow()

func is_burned(col: int, row: int) -> bool:
	return bool(burned[col][row])

## Elige el canal `row` del banco `col`. false si esta quemado o fuera de rango.
func select(col: int, row: int) -> bool:
	if col < 0 or col >= COLS or row < 0 or row >= ROWS:
		return false
	if is_burned(col, row) or selected[col] == row:
		return false
	selected[col] = row
	_play("lever_tick", -6.0, randf_range(0.95, 1.1))
	_update_flow()
	return true

## Quema un canal. Con `force` quema aunque deje el circuito sin solucion.
## Devuelve [col, row] o un array vacio si no quemo nada.
func burn_one(force: bool = false) -> Array:
	var free: Array = []
	for c in COLS:
		for r in ROWS:
			if not is_burned(c, r):
				free.append([c, r])
	if free.is_empty():
		return []
	free.shuffle()
	for cell in free:
		burned[cell[0]][cell[1]] = true
		if force or _solvable():
			# El canal quemado no puede quedar elegido: salta al primero sano
			# del banco (si no hay, se queda y el flujo se corta).
			if selected[cell[0]] == cell[1]:
				for r in ROWS:
					if not is_burned(cell[0], r):
						selected[cell[0]] = r
						break
			_play("breaker_off", -10.0, randf_range(0.9, 1.1))
			_update_flow()
			return cell
		burned[cell[0]][cell[1]] = false
	return []

## Canales quemados (para los monitores y la dificultad).
func burned_count() -> int:
	var n := 0
	for c in COLS:
		for r in ROWS:
			if is_burned(c, r):
				n += 1
	return n

# --- Camino ---------------------------------------------------------------------

func _update_flow() -> void:
	var ok := _path_ok()
	if ok == flow:
		return
	flow = ok
	flow_changed.emit(ok)

## El camino elegido ahora mismo sirve.
func _path_ok() -> bool:
	for c in COLS:
		if is_burned(c, selected[c]):
			return false
		if c > 0 and absi(selected[c] - selected[c - 1]) > 1:
			return false
	return true

## Todavia existe ALGUN camino valido (programacion dinamica banco a banco).
func _solvable() -> bool:
	var reach: Array[bool] = []
	for r in ROWS:
		reach.append(not is_burned(0, r))
	for c in range(1, COLS):
		var next: Array[bool] = []
		for r in ROWS:
			var ok := false
			if not is_burned(c, r):
				for p in range(maxi(r - 1, 0), mini(r + 2, ROWS)):
					if reach[p]:
						ok = true
						break
			next.append(ok)
		reach = next
	return reach.has(true)

func _play(sound: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if sfx:
		sfx.play(sound, volume_db, pitch)
