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


@export_group("Speed Repulsion")

## Boids whose speed doesn't match this one get actively pushed away
## when within this range. Independent of perception_radius/separation_radius
## on BoidBase — this can be shorter- or longer-ranged than general separation.
@export var repulsion_radius: float = 40.0

## Force applied at point-blank range against a fully dissimilar boid
## (one at or beyond similarity_range difference). Scales down to zero
## as distance grows toward repulsion_radius, and as the two boids'
## speeds get closer together — a boid just barely outside "similar"
## barely pushes; use similarity_range to control that cutoff.
@export var repulsion_strength: float = 80.0


## Actual speed assigned to this boid.
var speed: float = 0.0

## 0 = slowest.
## 1 = fastest.
var speed_factor: float = 0.0

## Reused across calls instead of letting get_force() allocate a fresh
## array every time it runs.
var _nearby_scratch: Array[BoidBase] = []


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
# SPEED REPULSION
# =============================================================

func get_force(
	boid: BoidBase
) -> Vector2:

	if repulsion_strength <= 0.0 or repulsion_radius <= 0.0:
		return Vector2.ZERO

	var repulsion: Vector2 = Vector2.ZERO

	BoidBase.query_radius_into(
		boid.position,
		repulsion_radius,
		_nearby_scratch
	)

	for other in _nearby_scratch:

		if other == boid:
			continue

		if not is_instance_valid(other):
			continue

		if other.is_queued_for_deletion():
			continue

		var other_speed_module: BoidSpeedModule = (
			other.get_module_by_type(
				BoidSpeedModule
			)
		)

		if other_speed_module == null:
			continue

		# Similar-speed boids don't repel — only push away from ones
		# whose speed doesn't match (the inverse of the clustering
		# similarity used above).
		var dissimilarity: float = 1.0 - get_similarity(
			other_speed_module
		)

		if dissimilarity <= 0.0:
			continue

		var offset: Vector2 = (
			boid.position - other.position
		)

		var distance_squared: float = (
			offset.length_squared()
		)

		if distance_squared <= 0.0001:
			continue

		var distance: float = sqrt(
			distance_squared
		)

		if distance >= repulsion_radius:
			continue

		var direction: Vector2 = (
			offset / distance
		)

		# 1.0 when touching, 0.0 at the edge of repulsion_radius.
		var proximity: float = (
			1.0
			- distance / repulsion_radius
		)

		repulsion += (
			direction
			* proximity
			* dissimilarity
			* repulsion_strength
		)

	return repulsion


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
