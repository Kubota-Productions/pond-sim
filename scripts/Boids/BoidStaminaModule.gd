extends BoidModifierModule
class_name BoidStaminaModule


@export_group("Stamina")

@export_range(0.0, 1.0) var min_stamina: float = 0.2
@export_range(0.0, 1.0) var max_stamina: float = 1.0


@export_group("Breaks")

@export var break_interval_min: float = 3.0
@export var break_interval_max: float = 8.0

@export var break_duration_min: float = 1.0
@export var break_duration_max: float = 3.0

@export_range(0.0, 1.0) var break_speed_multiplier: float = 0.25

@export var break_wander_radius: float = 30.0
@export var break_wander_force: float = 80.0


@export_group("Break Group")

## Number of nearby boids that must want a break.
@export_range(1, 20) var break_group_size: int = 3

## Distance within which boids count as part of the group.
@export var break_group_radius: float = 100.0

## How quickly break desire increases.
@export var break_urge_growth: float = 1.5

## How often a boid re-checks the group once it's past its preferred break
## interval but hasn't found enough nearby boids ready for a break yet.
## Without this, that check (a grid query) runs on EVERY SINGLE FRAME from
## the moment the interval passes until a group break actually triggers —
## which, at high population counts, is most of the flock most of the time.
@export var group_check_retry_interval: float = 0.25


# =============================================================
# STATE
# =============================================================

var stamina: float = 1.0

var time_since_break: float = 0.0
var break_urge: float = 0.0

var is_taking_break: bool = false
var break_timer: float = 0.0

var break_origin: Vector2

## Reused across calls instead of letting _count_ready_boids() allocate a
## fresh array every time it runs.
var _nearby_scratch: Array[BoidBase] = []

var _group_check_retry_timer: float = 0.0


# =============================================================
# INITIALIZE
# =============================================================

func initialize(boid: BoidBase) -> void:

	stamina = randf_range(
		min_stamina,
		max_stamina
	)

	time_since_break = 0.0
	break_urge = 0.0
	is_taking_break = false
	break_timer = 0.0

	break_origin = boid.position


# =============================================================
# UPDATE
# =============================================================

func update(
	boid: BoidBase,
	delta: float
) -> void:

	if is_taking_break:

		_update_break(delta)

		return


	# ---------------------------------------------------------
	# BUILD BREAK DESIRE
	# ---------------------------------------------------------

	time_since_break += delta

	var stamina_factor: float = (
		1.0 - stamina
	)

	var preferred_interval: float = lerp(
		break_interval_max,
		break_interval_min,
		stamina_factor
	)

	if time_since_break < preferred_interval:
		return


	# ---------------------------------------------------------
	# INCREASE BREAK URGE
	# ---------------------------------------------------------

	var excess_time: float = (
		time_since_break
		- preferred_interval
	)

	break_urge = clamp(
		excess_time * break_urge_growth,
		0.0,
		1.0
	)


	# ---------------------------------------------------------
	# CHECK GROUP
	# ---------------------------------------------------------

	# Throttle the grid query instead of re-checking the group on every
	# single frame once past preferred_interval. break_urge above still
	# updates every frame from delta-accumulated time, so the ramp-up feel
	# is unaffected — only how often we ask "is the group ready yet?" changes.
	if _group_check_retry_timer > 0.0:
		_group_check_retry_timer -= delta
		return

	_group_check_retry_timer = group_check_retry_interval

	var ready_count: int = _count_ready_boids(boid)

	if ready_count >= break_group_size:
		_start_break(boid)


# =============================================================
# UPDATE CURRENT BREAK
# =============================================================

func _update_break(delta: float) -> void:

	break_timer -= delta

	if break_timer <= 0.0:

		is_taking_break = false

		time_since_break = 0.0
		break_urge = 0.0


# =============================================================
# COUNT READY BOIDS
# =============================================================

func _count_ready_boids(
	boid: BoidBase
) -> int:

	var count: int = 1

	var break_group_radius_sq: float = (
		break_group_radius * break_group_radius
	)

	# Was: loop every boid in BoidBase.all_boids (O(n) per call, and this
	# is called from update() for potentially every boid). Now: only the
	# boids the spatial grid says are actually within break_group_radius,
	# filled into a reused array instead of allocating a new one each call.
	BoidBase.query_radius_into(
		boid.position,
		break_group_radius,
		_nearby_scratch
	)

	for other in _nearby_scratch:

		if other == boid:
			continue


		var other_stamina: BoidStaminaModule = (
			other.get_module_by_type(
				BoidStaminaModule
			)
		)

		if other_stamina == null:
			continue


		if other_stamina.is_taking_break:
			continue


		var distance_sq: float = (
			boid.position.distance_squared_to(
				other.position
			)
		)

		if distance_sq > break_group_radius_sq:
			continue


		if other_stamina.break_urge > 0.0:
			count += 1


	return count


# =============================================================
# START BREAK
# =============================================================

func _start_break(
	boid: BoidBase
) -> void:

	is_taking_break = true

	break_timer = randf_range(
		break_duration_min,
		break_duration_max
	)

	break_origin = boid.position

	time_since_break = 0.0
	break_urge = 0.0


# =============================================================
# BREAK FORCE
# =============================================================

func get_force(
	boid: BoidBase
) -> Vector2:

	if not is_taking_break:
		return Vector2.ZERO


	var offset: Vector2 = (
		boid.position
		- break_origin
	)


	# ---------------------------------------------------------
	# STAY INSIDE BREAK AREA
	# ---------------------------------------------------------

	if offset.length() > break_wander_radius:

		var return_direction: Vector2 = (
			break_origin
			- boid.position
		).normalized()

		return (
			return_direction
			* break_wander_force
		)


	# ---------------------------------------------------------
	# RANDOM WANDERING
	# ---------------------------------------------------------

	var wander: Vector2 = Vector2.from_angle(
		randf() * TAU
	)

	return (
		wander
		* break_wander_force
		* 0.05
	)


# =============================================================
# SPEED
# =============================================================

func modify_speed(
	boid: BoidBase,
	current_speed: float
) -> float:

	if is_taking_break:

		return (
			current_speed
			* break_speed_multiplier
		)

	return current_speed


# =============================================================
# DEBUG / COLOR
# =============================================================

func modify_color(
	boid: BoidBase,
	current_color: Color
) -> Color:

	if is_taking_break:

		return current_color.darkened(
			0.25
		)

	return current_color
