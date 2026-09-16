extends StaticBody3D

@export var slide_distance: float = 0.5
@export var slide_duration: float = 0.8

var _rest_position: Vector3
var _is_down: bool = false

func _ready() -> void:
	_rest_position = position

func on_clicked(_hit_position: Vector3 = Vector3.ZERO) -> void:
	_slide_down()

func _slide_down() -> void:
	if _is_down:
		return
	_is_down = true
	var target_y := _rest_position.y - slide_distance

	var tween := create_tween()
	tween.tween_property(self, "position:y", target_y, slide_duration)\
		.set_trans(Tween.TRANS_CUBIC)\
		.set_ease(Tween.EASE_OUT)
