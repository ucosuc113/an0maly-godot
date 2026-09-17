extends "res://scripts/mesh_interactable.gd"

# Boton de fase del panel (la "bolita"). Solo responde en la vista del panel
# y cuando control_panel.gd dice que es el que toca. Al clicarlo se hunde y
# vuelve, y arranca su fase.

## Nodo con control_panel.gd.
@export var panel: Node
## Fase que inicia (1..3).
@export var phase_index: int = 1
## Vista de camera_views.gd desde donde se usa.
@export var usable_in_view: StringName = &"Panel"
@export var press_depth: float = 0.005

var _in_view: bool = false

func _ready() -> void:
	super._ready()
	if views:
		views.view_changed.connect(_on_view_changed)
	if panel:
		panel.phase_started.connect(_refresh.unbind(1))
		panel.phase_completed.connect(_refresh.unbind(1))
		panel.phase_ready.connect(_refresh.unbind(1))
	_refresh()

func _on_view_changed(view: StringName) -> void:
	_in_view = view == usable_in_view
	_refresh()

func _refresh() -> void:
	enabled = _in_view and panel != null and panel.button_state(phase_index) == "ready"

func _on_clicked(_hit_position: Vector3) -> void:
	if not enabled:
		return
	enabled = false
	_press_animation()
	if sfx_node():
		sfx_node().play("panel_button")
	panel.press_phase(phase_index)

func sfx_node() -> Node:
	return views.sfx if views else null

func _press_animation() -> void:
	var root: Node3D = model if model else self
	var rest := root.position
	var down := rest - root.transform.basis.y.normalized() * press_depth
	var t := create_tween()
	t.tween_property(root, "position", down, 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.08)
	t.tween_property(root, "position", rest, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
