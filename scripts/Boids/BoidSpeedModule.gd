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

# True when this module's genetic value was copied from a parent by
# BoidBreedingModule via prepare_offspring(). Prevents initialize()
# from re-rolling a random value over the inherited one.
var _inherited: bool = false


# =============================================================
# INITIALIZE
# =============================================================

func initialize(boid: BoidBase) -> void:

	if not _inherited:
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

	# NOTE: previously this returned `speed` outright, which silently
	# discarded any multiplier already applied by a module earlier in
	# the array (e.g. BoidIntelligenceModule's break slowdown) — the
	# result depended entirely on module order in the inspector.
	#
	# Instead, treat `current_speed` as an accumulated multiplier chain
	# relative to BoidBase's known default base speed, and apply this
	# module's speed on top of that ratio. This makes the result the
	# same regardless of where BoidSpeedModule sits in the modules array.
	if BoidBase.DEFAULT_BASE_SPEED <= 0.0:
		return speed

	var multiplier: float = (
		current_speed / BoidBase.DEFAULT_BASE_SPEED
	)

	return speed * multiplier


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


# =============================================================
# OFFSPRING
# =============================================================

func prepare_offspring(
	offspring: BoidBase,
	parent_a: BoidBase,
	parent_b: BoidBase
) -> void:

	# Marks this module so initialize() doesn't overwrite the value
	# applied by apply_inherited_state() (below) with a fresh random roll.
	_inherited = true


# =============================================================
# INHERITED STATE
# =============================================================
# duplicate(true) does not copy non-@export vars, so `speed` would
# otherwise come back at its script default (0.0) instead of the
# parent's actual rolled value — leaving offspring unable to move at
# all. BoidBreedingModule captures this on the live parent module and
# re-applies it here on the offspring's copy.

func get_inherited_state() -> Dictionary:
	return {
		"speed": speed,
		"speed_factor": speed_factor,
	}


func apply_inherited_state(state: Dictionary) -> void:
	if state.has("speed"):
		speed = state["speed"]
	if state.has("speed_factor"):
		speed_factor = state["speed_factor"]
