extends BoidModifierModule
class_name BoidSizeModule


@export_group("Size")
@export var min_size: float = 1.0
@export var max_size: float = 1.5


@export_group("Size Clustering")
@export var similarity_range: float = 0.08
@export var clustering_weight: float = 2.0


@export_group("Personal Space")
@export var personal_space_radius: float = 30.0
@export var personal_space_strength: float = 100.0
@export var size_space_multiplier: float = 1.0


var size: float = 1.0
var size_factor: float = 0.0


# True when this module's genetic value was copied from a parent by
# BoidBreedingModule via prepare_offspring(). Prevents initialize()
# from re-rolling a random value over the inherited one.
var _inherited: bool = false


func initialize(boid: BoidBase) -> void:

	if not _inherited:
		size = randf_range(
			min_size,
			max_size
		)

	if max_size <= min_size:
		size_factor = 1.0
	else:
		size_factor = (
			size - min_size
		) / (
			max_size - min_size
		)


func get_scale(boid: BoidBase) -> Vector2:

	return Vector2.ONE * size


# =============================================================
# PERSONAL SPACE
# =============================================================

func get_force(boid: BoidBase) -> Vector2:

	var separation: Vector2 = Vector2.ZERO

	var effective_radius: float = (
		personal_space_radius
		* lerp(
			1.0,
			size,
			size_space_multiplier
		)
	)

	for other in BoidBase.all_boids:

		if other == boid:
			continue

		if not is_instance_valid(other):
			continue

		if other.is_queued_for_deletion():
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

		if distance >= effective_radius:
			continue

		var direction: Vector2 = (
			offset / distance
		)

		# 1.0 when touching, 0.0 at the edge
		# of the personal-space radius.
		var proximity: float = (
			1.0
			- distance / effective_radius
		)

		# Larger boids produce stronger separation.
		var size_strength: float = (
			1.0
			+ size_factor * size_space_multiplier
		)

		separation += (
			direction
			* proximity
			* personal_space_strength
			* size_strength
		)

	return separation


# =============================================================
# FLOCK SIZE CLUSTERING
# =============================================================

func get_flock_weight(
	boid: BoidBase,
	other: BoidBase
) -> float:

	var other_size_module: BoidSizeModule = (
		other.get_module_by_type(
			BoidSizeModule
		)
	)

	if other_size_module == null:
		return 1.0

	var similarity: float = get_similarity(
		other_size_module
	)

	if similarity <= 0.0:
		return 1.0

	return (
		1.0
		+ similarity * clustering_weight
	)


func get_similarity(
	other: BoidSizeModule
) -> float:

	if other == null:
		return 0.0

	var size_difference: float = abs(
		size - other.size
	)

	if size_difference >= similarity_range:
		return 0.0

	var similarity: float = (
		1.0
		- (
			size_difference
			/ similarity_range
		)
	)

	return similarity * similarity


# =============================================================
# OFFSPRING
# =============================================================

func prepare_offspring(
	offspring: BoidBase,
	parent_a: BoidBase,
	parent_b: BoidBase
) -> void:

	# Marks this module so initialize() doesn't overwrite the value
	# applied by apply_inherited_state() with a fresh random roll.
	_inherited = true


# =============================================================
# INHERITED STATE
# =============================================================
# duplicate(true) does not copy non-@export vars, so `size` would
# otherwise come back at its script default (1.0) instead of the
# parent's actual rolled value.

func get_inherited_state() -> Dictionary:

	return {
		"size": size,
		"size_factor": size_factor,
	}


func apply_inherited_state(
	state: Dictionary
) -> void:

	if state.has("size"):
		size = state["size"]

	if state.has("size_factor"):
		size_factor = state["size_factor"]
