extends BoidModifierModule
class_name BoidAgeModule

@export_group("Age")
@export var minimum_age: float = 40.0
@export var maximum_age: float = 80.0

@export_group("Growth")
@export var starting_size_ratio: float = 1.0
@export var growth_duration: float = 10.0

@export_group("Death")
@export var die_at_maximum_size: bool = false
@export var die_at_maximum_age: bool = true
@export var death_display_duration: float = 1.0

var age: float = 0.0
var growth_progress: float = 0.0
var lifespan: float = 60.0
var spawn_time: float = 0.0

var is_dead: bool = false
var death_timer: float = 0.0

var started_small: bool = false

var _inherited_lifespan: bool = false


func initialize(boid: BoidBase) -> void:

	age = 0.0
	growth_progress = 0.0

	is_dead = false
	death_timer = 0.0

	spawn_time = Time.get_ticks_msec() / 1000.0

	if not _inherited_lifespan:

		if maximum_age <= minimum_age:
			lifespan = minimum_age
		else:
			lifespan = randf_range(
				minimum_age,
				maximum_age
			)

	started_small = starting_size_ratio < 1.0


func update(
	boid: BoidBase,
	delta: float
) -> void:

	# --------------------------------------------------
	# DEAD STATE
	# --------------------------------------------------

	if is_dead:

		death_timer -= delta

		if death_timer <= 0.0:
			boid.queue_free()

		return


	# --------------------------------------------------
	# AGE
	# --------------------------------------------------

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
	# DEATH BY AGE
	# --------------------------------------------------

	if die_at_maximum_age:

		if age >= lifespan:
			_die(boid)
			return


	# --------------------------------------------------
	# DEATH BY SIZE
	# --------------------------------------------------

	if die_at_maximum_size:

		if started_small and growth_progress >= 1.0:
			_die(boid)
			return


func get_scale(
	boid: BoidBase
) -> Vector2:

	var size: float = 1.0

	if starting_size_ratio < 1.0:

		size = lerp(
			starting_size_ratio,
			1.0,
			growth_progress
		)

	return Vector2.ONE * size


func modify_color(
	boid: BoidBase,
	current_color: Color
) -> Color:

	if is_dead:
		return Color.BLACK

	return current_color


func prepare_offspring(
	offspring: BoidBase,
	parent_a: BoidBase,
	parent_b: BoidBase
) -> void:

	age = 0.0
	growth_progress = 0.0

	is_dead = false
	death_timer = 0.0

	spawn_time = 0.0

	started_small = true

	_inherited_lifespan = true


func get_inherited_state() -> Dictionary:

	return {
		"lifespan": lifespan
	}


func apply_inherited_state(
	state: Dictionary
) -> void:

	if state.has("lifespan"):
		lifespan = state["lifespan"]


func _die(
	boid: BoidBase
) -> void:

	if is_dead:
		return

	is_dead = true
	death_timer = death_display_duration

	# Immediately stop the boid.
	boid.velocity = Vector2.ZERO
	boid.acceleration = Vector2.ZERO

	# Make the black corpse visible immediately.
	boid.queue_redraw()
