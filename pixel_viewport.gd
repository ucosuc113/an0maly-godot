@tool
extends SubViewport

# Con own_world_3d activo, los nodos 3D de este SubViewport se registran en un
# World3D propio. El viewport 3D del editor solo dibuja el World3D de la raiz de
# la escena editada, asi que ese mundo aparte le queda invisible: mallas, luces y
# hasta los gizmos del nodo seleccionado desaparecen. En F5 se ve bien porque ahi
# el SubViewport si renderiza su propio mundo a su textura.
#
# Solucion: mundo propio solo al ejecutar. Mientras editas se comparte el mundo
# con la escena y todo vuelve a verse en el editor.

## Desactivalo si alguna vez quieres compartir el mundo tambien en el juego.
@export var use_own_world_in_game: bool = true:
	set(value):
		use_own_world_in_game = value
		_apply_world_mode()

func _enter_tree() -> void:
	_apply_world_mode()

func _apply_world_mode() -> void:
	var wanted: bool = use_own_world_in_game and not Engine.is_editor_hint()
	if own_world_3d != wanted:
		own_world_3d = wanted
