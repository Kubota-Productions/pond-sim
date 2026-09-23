extends BoidModifierModule
class_name BoidSpeedModule


@export_group("Speed")

@export var min_speed: float = 120.0
@export var max_speed: float = 200.0


@export_group("Speed Clustering")

## How strongly this boid prefers boids with similar speeds.
@export var clustering_weight: float = 2.0

## How much speed difference is considered similar.
@export_range(0.01, 1.0) var similarity_range: float = 0.25


## Actual speed assigned to this boid.
var speed: float = 0.0

## 0 = slowest.
## 1 = fastest.
var speed_factor: float = 0.0


# =============================================================
# INITIALIZE
# =============================================================

func initialize(boid: BoidBase) -> void:

	speed = randf_range(
		min_speed,
		max_speed
	)

	if max_speed <= min_speed:
		speed_factor = 1.0
	else:
		speed_factor = (
			(speed - min_speed)
			/ (max_speed - min_speed)
		)


# =============================================================
# FLOCK WEIGHT
# =============================================================

func get_flock_weight(
	boid: BoidBase,
	other: BoidBase
) -> float:

	var other_speed_module: BoidSpeedModule = (
		other.get_module_by_type(
			BoidSpeedModule
		)
	)

	if other_speed_module == null:
		return 1.0

	var similarity: float = get_similarity(
		other_speed_module
	)

	return (
		1.0
		+ similarity
		* clustering_weight
	)


# =============================================================
# SPEED SIMILARITY
# =============================================================

func get_similarity(
	other: BoidSpeedModule
) -> float:

	if other == null:
		return 0.0

	if speed <= 0.0:
		return 0.0

	var speed_difference: float = abs(
		speed - other.speed
	)

	var similarity: float = 1.0 - (
		speed_difference
		/ (
			speed
			* similarity_range
		)
	)

	similarity = clamp(
		similarity,
		0.0,
		1.0
	)

	# Smooth transition.
	return similarity * similarity


# =============================================================
# SPEED
# =============================================================

func modify_speed(
	boid: BoidBase,
	current_speed: float
) -> float:

	return speed


# =============================================================
# COLOR
# =============================================================

func modify_color(
	boid: BoidBase,
	current_color: Color
) -> Color:

	# Slow = white
	# Fast = red

	return current_color.lerp(
		Color.RED,
		speed_factor
	)
