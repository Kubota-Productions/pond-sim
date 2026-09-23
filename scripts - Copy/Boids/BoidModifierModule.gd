extends Resource
class_name BoidModifierModule


func initialize(boid: BoidBase) -> void:
	pass


func update(
	boid: BoidBase,
	delta: float
) -> void:
	pass


func get_force(
	boid: BoidBase
) -> Vector2:
	return Vector2.ZERO


func modify_speed(
	boid: BoidBase,
	current_speed: float
) -> float:
	return current_speed


func get_flock_weight(
	boid: BoidBase,
	other: BoidBase
) -> float:
	return 1.0


func modify_color(
	boid: BoidBase,
	current_color: Color
) -> Color:
	return current_color


func get_scale(
	boid: BoidBase
) -> Vector2:
	return Vector2.ONE


## Called when this module is inherited by an offspring.
## Override this when a module needs to reset runtime state.
func prepare_offspring(
	offspring: BoidBase,
	parent_a: BoidBase,
	parent_b: BoidBase
) -> void:
	pass
