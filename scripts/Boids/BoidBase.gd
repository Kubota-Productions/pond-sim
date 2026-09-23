extends Node2D
class_name BoidBase

static var boid_count: int:
	get:
		var count: int = 0

		for boid in all_boids:

			if not is_instance_valid(boid):
				continue

			if boid.is_queued_for_deletion():
				continue

			count += 1

		return count


# MODULES
@export_group("Modules")

@export var modules: Array[BoidModifierModule] = []


# FLOCKING
@export_group("Flocking")

@export var max_force: float = 300.0
@export var perception_radius: float = 60.0
@export var separation_radius: float = 24.0

@export var separation_weight: float = 1.6
@export var alignment_weight: float = 1.0
@export var cohesion_weight: float = 1.0


# EDGE AVOIDANCE
@export_group("Edge Avoidance")

@export var edge_avoid_margin: float = 80.0
@export var edge_avoid_force: float = 500.0
@export var edge_avoid_curve: float = 2.0


# BIOLOGY
@export_group("Biology")

@export var max_energy: float = 100.0
@export var starting_energy: float = 75.0

var energy: float = 0.0

func add_energy(amount: float) -> void:
	energy = clamp(
		energy + amount,
		0.0,
		max_energy
	)

func remove_energy(amount: float) -> void:
	energy = max(
		energy - amount,
		0.0
	)


# RUNTIME
var velocity: Vector2
var acceleration: Vector2

var break_origin: Vector2


# GLOBAL FLOCK
static var all_boids: Array[BoidBase] = []

static var bounds: Rect2 = Rect2()


# SPEED
# The base speed every module's modify_speed() chain starts from.
# Exposed as a named constant (instead of a magic number buried in
# _get_max_speed) so modules like BoidSpeedModule can normalize
# against it and apply their own speed as a multiplier rather than an
# outright overwrite — which keeps the speed chain's result
# independent of module ordering in the `modules` array.
const DEFAULT_BASE_SPEED: float = 100.0


# READY
func _ready() -> void:

	# ENERGY
	energy = starting_energy

	# Initialize every installed module.
	for module in modules:

		if module == null:
			continue

		module.initialize(self)

	# Start moving in a random direction.
	velocity = (
		Vector2.RIGHT.rotated(randf() * TAU)
		* _get_max_speed()
	)

	all_boids.append(self)

	queue_redraw()

func copy_base_configuration_from(
	source: BoidBase
) -> void:

	if source == null:
		return


	# =========================================================
	# FLOCKING
	# =========================================================

	max_force = source.max_force
	perception_radius = source.perception_radius
	separation_radius = source.separation_radius

	separation_weight = source.separation_weight
	alignment_weight = source.alignment_weight
	cohesion_weight = source.cohesion_weight


	# =========================================================
	# EDGE AVOIDANCE
	# =========================================================

	edge_avoid_margin = source.edge_avoid_margin
	edge_avoid_force = source.edge_avoid_force
	edge_avoid_curve = source.edge_avoid_curve


	# =========================================================
	# BIOLOGY
	# =========================================================

	max_energy = source.max_energy
	starting_energy = source.starting_energy


# EXIT TREE
func _exit_tree() -> void:

	# Remove this boid from the global flock immediately
	# when it leaves the scene tree.
	all_boids.erase(self)


# PROCESS
func _process(delta: float) -> void:

	# MODULE UPDATE
	for module in modules:

		if module == null:
			continue

		module.update(
			self,
			delta
		)

		# A module may have called queue_free().
		if is_queued_for_deletion():
			return


	# --------------------------------------------------
	# DEAD BOID
	# --------------------------------------------------

	var age_module: BoidAgeModule = (
		get_module_by_type(
			BoidAgeModule
		)
	)

	if age_module != null and age_module.is_dead:

		# Make absolutely sure the corpse cannot move.
		velocity = Vector2.ZERO
		acceleration = Vector2.ZERO

		# Keep the corpse at its current scale.
		scale = _get_scale()

		# Keep it black.
		queue_redraw()

		# IMPORTANT:
		# Do NOT flock.
		# Do NOT apply forces.
		# Do NOT move.
		# Do NOT wrap.
		# Do NOT clamp.
		return


	# --------------------------------------------------
	# FLOCK
	# --------------------------------------------------

	_flock()


	# --------------------------------------------------
	# EDGE AVOIDANCE
	# --------------------------------------------------

	if bounds.size != Vector2.ZERO:
		_avoid_edges()


	# --------------------------------------------------
	# MODULE FORCES
	# --------------------------------------------------

	for module in modules:

		if module == null:
			continue

		acceleration += module.get_force(
			self
		)

		if is_queued_for_deletion():
			return


	# --------------------------------------------------
	# MOVEMENT
	# --------------------------------------------------

	velocity += acceleration * delta

	velocity = velocity.limit_length(
		_get_max_speed()
	)

	position += velocity * delta


	# --------------------------------------------------
	# ROTATION
	# --------------------------------------------------

	if velocity.length_squared() > 0.01:

		rotation = velocity.angle()


	# --------------------------------------------------
	# BOUNDS
	# --------------------------------------------------

	if bounds.size != Vector2.ZERO:

		if position.x < bounds.position.x:

			position.x = bounds.position.x
			velocity.x = max(velocity.x, 0.0)

		elif position.x > bounds.end.x:

			position.x = bounds.end.x
			velocity.x = min(velocity.x, 0.0)


		if position.y < bounds.position.y:

			position.y = bounds.position.y
			velocity.y = max(velocity.y, 0.0)

		elif position.y > bounds.end.y:

			position.y = bounds.end.y
			velocity.y = min(velocity.y, 0.0)

	else:

		_wrap_around()


	# --------------------------------------------------
	# VISUALS
	# --------------------------------------------------

	scale = _get_scale()

	queue_redraw()


	# --------------------------------------------------
	# RESET ACCELERATION
	# --------------------------------------------------

	acceleration = Vector2.ZERO


# FLOCK
func _flock() -> void:

	var separation: Vector2 = Vector2.ZERO
	var alignment: Vector2 = Vector2.ZERO
	var cohesion: Vector2 = Vector2.ZERO

	var separation_count: int = 0
	var flock_weight: float = 0.0

	for other in all_boids:

		if other == self:
			continue

		# IMPORTANT:
		# queue_free() is deferred, so a freed boid can remain
		# in all_boids briefly. Validate it before accessing it.
		if not is_instance_valid(other):
			continue

		if other.is_queued_for_deletion():
			continue

		var distance: float = (
			position.distance_to(
				other.position
			)
		)

		if (
			distance <= 0.0
			or distance >= perception_radius
		):
			continue

		# SEPARATION
		if distance < separation_radius:

			separation += (
				position
				- other.position
			) / distance

			separation_count += 1

		# MODULE FLOCKING WEIGHT
		var weight: float = 1.0

		for module in modules:

			if module == null:
				continue

			weight *= module.get_flock_weight(
				self,
				other
			)

		# ALIGNMENT
		alignment += (
			other.velocity
			* weight
		)

		# COHESION
		cohesion += (
			other.position
			* weight
		)

		flock_weight += weight

	# ALIGNMENT
	if flock_weight > 0.0:

		var average_velocity: Vector2 = (
			alignment / flock_weight
		)

		var target_velocity: Vector2 = (
			average_velocity.normalized()
			* _get_max_speed()
		)

		alignment = (
			target_velocity
			- velocity
		)

		alignment = alignment.limit_length(
			max_force
		)

	# COHESION
	if flock_weight > 0.0:

		var center: Vector2 = (
			cohesion / flock_weight
		)

		var target_velocity: Vector2 = (
			(center - position).normalized()
			* _get_max_speed()
		)

		cohesion = (
			target_velocity
			- velocity
		)

		cohesion = cohesion.limit_length(
			max_force
		)

	# SEPARATION
	if separation_count > 0:

		separation = (
			separation
			/ separation_count
		).normalized()

		separation = (
			separation
			* _get_max_speed()
			- velocity
		)

		separation = separation.limit_length(
			max_force
		)

	# APPLY FLOCKING
	acceleration += (
		separation
		* separation_weight
	)

	acceleration += (
		alignment
		* alignment_weight
	)

	acceleration += (
		cohesion
		* cohesion_weight
	)


# GET MAX SPEED
func _get_max_speed() -> float:

	var speed: float = DEFAULT_BASE_SPEED

	for module in modules:

		if module == null:
			continue

		speed = module.modify_speed(
			self,
			speed
		)

	return max(speed, 0.0)


# GET MODULE
func get_module_by_type(
	module_type: Variant
) -> BoidModifierModule:

	for module in modules:

		if module == null:
			continue

		if is_instance_of(
			module,
			module_type
		):

			return module

	return null


# EDGE AVOIDANCE
func _avoid_edges() -> void:

	var steer: Vector2 = Vector2.ZERO

	var dist_left: float = (
		position.x
		- bounds.position.x
	)

	var dist_right: float = (
		bounds.end.x
		- position.x
	)

	var dist_top: float = (
		position.y
		- bounds.position.y
	)

	var dist_bottom: float = (
		bounds.end.y
		- position.y
	)

	var direction: Vector2 = (
		velocity.normalized()
	)

	# LEFT
	if dist_left < edge_avoid_margin:

		var strength: float = _edge_push(
			dist_left
		)

		var moving_toward: float = max(
			-direction.x,
			0.0
		)

		steer.x += strength * (
			0.5
			+ moving_toward * 2.0
		)

	# RIGHT
	if dist_right < edge_avoid_margin:

		var strength: float = _edge_push(
			dist_right
		)

		var moving_toward: float = max(
			direction.x,
			0.0
		)

		steer.x -= strength * (
			0.5
			+ moving_toward * 2.0
		)

	# TOP
	if dist_top < edge_avoid_margin:

		var strength: float = _edge_push(
			dist_top
		)

		var moving_toward: float = max(
			-direction.y,
			0.0
		)

		steer.y += strength * (
			0.5
			+ moving_toward * 2.0
		)

	# BOTTOM
	if dist_bottom < edge_avoid_margin:

		var strength: float = _edge_push(
			dist_bottom
		)

		var moving_toward: float = max(
			direction.y,
			0.0
		)

		steer.y -= strength * (
			0.5
			+ moving_toward * 2.0
		)

	if steer != Vector2.ZERO:

		steer = steer.normalized()

		var desired_velocity: Vector2 = (
			steer * _get_max_speed()
		)

		var steering: Vector2 = (
			desired_velocity
			- velocity
		)

		acceleration += (
			steering.limit_length(
				edge_avoid_force
			)
		)


# EDGE PUSH
func _edge_push(
	distance_from_edge: float
) -> float:

	var t: float = clamp(
		1.0
		- (
			distance_from_edge
			/ edge_avoid_margin
		),
		0.0,
		1.0
	)

	return pow(
		t,
		edge_avoid_curve
	)


# WRAP
func _wrap_around() -> void:

	var view: Vector2 = (
		get_viewport_rect().size
	)

	if position.x < 0.0:
		position.x = view.x

	elif position.x > view.x:
		position.x = 0.0

	if position.y < 0.0:
		position.y = view.y

	elif position.y > view.y:
		position.y = 0.0


# DRAW
func _draw() -> void:

	var points: PackedVector2Array = PackedVector2Array([
		Vector2(10, 0),
		Vector2(-6, 5),
		Vector2(-6, -5)
	])

	var color: Color = Color.WHITE

	# Give every module a chance to modify appearance.
	for module in modules:

		if module == null:
			continue

		color = module.modify_color(
			self,
			color
		)

	draw_colored_polygon(
		points,
		color
	)


# GET SCALE
func _get_scale() -> Vector2:

	var boid_scale: Vector2 = Vector2.ONE

	for module in modules:

		if module == null:
			continue

		boid_scale *= module.get_scale(
			self
		)

	return boid_scale
