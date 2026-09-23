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


# =============================================================
# STATE
# =============================================================

var stamina: float = 1.0

var time_since_break: float = 0.0
var break_urge: float = 0.0

var is_taking_break: bool = false
var break_timer: float = 0.0

var break_origin: Vector2

# True when this module's genetic value was copied from a parent by
# BoidBreedingModule via prepare_offspring(). Prevents initialize()
# from re-rolling a random value over the inherited one. Runtime break
# state (below) is intentionally NOT covered by this flag — every
# boid, inherited or not, should start with a clean break cycle.
var _inherited: bool = false


# =============================================================
# INITIALIZE
# =============================================================

func initialize(boid: BoidBase) -> void:

	if not _inherited:
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

	for other in BoidBase.all_boids:

		# IMPORTANT:
		# queue_free() is deferred, so a freed boid can remain
		# in all_boids briefly.
		if not is_instance_valid(other):
			continue

		if other == boid:
			continue

		if other.is_queued_for_deletion():
			continue


		var other_stamina: BoidstaminaModule = (
			other.get_module_by_type(
				BoidstaminaModule
			)
		)

		if other_stamina == null:
			continue


		if other_stamina.is_taking_break:
			continue


		var distance: float = (
			boid.position.distance_to(
				other.position
			)
		)

		if distance > break_group_radius:
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
	# Runtime break state is reset unconditionally in initialize()
	# regardless of this flag, which is correct — a newborn shouldn't
	# start mid-break or with an inherited break_urge.
	_inherited = true


# =============================================================
# INHERITED STATE
# =============================================================
# duplicate(true) does not copy non-@export vars, so `stamina`
# would otherwise come back at its script default (1.0) instead of the
# parent's actual rolled value. BoidBreedingModule captures this on
# the live parent module and re-applies it here on the offspring's copy.

func get_inherited_state() -> Dictionary:
	return {
		"stamina": stamina,
	}


func apply_inherited_state(state: Dictionary) -> void:
	if state.has("stamina"):
		stamina = state["stamina"]
