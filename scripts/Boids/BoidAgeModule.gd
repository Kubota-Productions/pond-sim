extends BoidModifierModule
class_name BoidAgeModule


@export_group("Age")

@export var minimum_age: float = 40.0
@export var maximum_age: float = 80.0


@export_group("Growth")

@export_range(0.01, 1.0)
var starting_size_ratio: float = 0.25

@export var growth_duration: float = 20.0


@export_group("Death")

@export var die_at_maximum_size: bool = false
@export var die_at_maximum_age: bool = true


# RUNTIME
var age: float = 0.0
var growth_progress: float = 0.0

var lifespan: float = 60.0

var spawn_time: float = 0.0

var is_dead: bool = false

# True when this boid was actually spawned as a young boid.
var started_small: bool = true


# INITIALIZE
func initialize(boid: BoidBase) -> void:

	age = 0.0
	growth_progress = 0.0
	is_dead = false

	# Record the moment this boid spawned.
	spawn_time = Time.get_ticks_msec() / 1000.0

	# Give this boid its own random lifespan.
	if maximum_age <= minimum_age:

		lifespan = minimum_age

	else:

		lifespan = randf_range(
			minimum_age,
			maximum_age
		)

	# Determine whether this boid starts young
	# or is already at full size.
	#
	# We use the starting size ratio as the definition
	# of a naturally spawned young boid.
	started_small = starting_size_ratio < 1.0

	print(
		"[AGE] Initialized: ",
		boid.name,
		" | lifespan = ",
		lifespan,
		" | started small = ",
		started_small,
		" | spawn time = ",
		spawn_time
	)


# UPDATE
func update(
	boid: BoidBase,
	delta: float
) -> void:

	if is_dead:
		return


	# --------------------------------------------------
	# AGE
	# --------------------------------------------------

	# Calculate age from the time this boid spawned.
	#
	# This means age is based on actual elapsed time
	# since spawning rather than on growth state.
	var current_time: float = (
		Time.get_ticks_msec() / 1000.0
	)

	age = current_time - spawn_time


	# --------------------------------------------------
	# GROWTH
	# --------------------------------------------------

	if growth_duration > 0.0:

		growth_progress = clamp(
			age / growth_duration,
			0.0,
			1.0
		)

	else:

		growth_progress = 1.0


	# --------------------------------------------------
	# OLD AGE DEATH
	# --------------------------------------------------

	if die_at_maximum_age:

		if age >= lifespan:

			print(
				"[AGE] OLD AGE DEATH: ",
				boid.name,
				" | age = ",
				age,
				" | lifespan = ",
				lifespan
			)

			_die(boid)

			return


	# --------------------------------------------------
	# MAX SIZE DEATH
	# --------------------------------------------------

	# Only use maximum-size death for boids that actually
	# started small and therefore went through a growth phase.
	#
	# A boid spawned at full size will NOT die simply
	# because its size is already at maximum.
	if die_at_maximum_size:

		if started_small and growth_progress >= 1.0:

			print(
				"[AGE] MAX SIZE DEATH: ",
				boid.name,
				" | age = ",
				age
			)

			_die(boid)

			return


# SCALE
func get_scale(boid: BoidBase) -> Vector2:

	var growth_scale: float = lerp(
		starting_size_ratio,
		1.0,
		growth_progress
	)

	return Vector2.ONE * growth_scale


# OFFSPRING
func prepare_offspring(
	offspring: BoidBase,
	parent_a: BoidBase,
	parent_b: BoidBase
) -> void:

	# Runtime state must start fresh.
	age = 0.0
	growth_progress = 0.0
	is_dead = false

	# Offspring gets a new spawn timestamp when
	# initialize() runs.
	spawn_time = 0.0

	# Offspring is considered young.
	started_small = true


# DEATH
func _die(boid: BoidBase) -> void:

	if is_dead:
		return

	is_dead = true

	print(
		"[AGE] queue_free() called on ",
		boid.name
	)

	boid.queue_free()
