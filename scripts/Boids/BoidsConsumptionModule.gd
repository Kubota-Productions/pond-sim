extends BoidModifierModule
class_name BoidConsumptionModule


@export_group("Consumption")

@export var enabled: bool = true
@export var detection_radius: float = 100.0
@export var eating_distance: float = 12.0
@export var consumption_cooldown: float = 2.0

## How often a boid re-searches for food once it's hungry but has no
## current target. Without this, any predator-sized boid with no target
## calls _find_food() (a grid query) on EVERY SINGLE FRAME until it finds
## something — the cooldown only applies after a successful meal, so this
## is the actual steady-state hot path, not the occasional check it looks
## like at a glance.
@export var search_retry_interval: float = 0.25


@export_group("Size Requirement")

# The predator must be at least this size to eat.
@export var minimum_predator_size: float = 1.0

# The predator must be this much larger than its prey.
@export var minimum_size_ratio: float = 1.25


@export_group("Energy")

@export var energy_per_meal: float = 30.0
@export var energy_loss_per_second: float = 2.0


@export_group("Eating Force")

@export var eating_force: float = 100.0


# RUNTIME

var target: BoidBase = null
var consumption_timer: float = 0.0

## Reused across calls instead of letting _find_food() allocate a fresh
## array every time it runs.
var _nearby_scratch: Array[BoidBase] = []

var _search_retry_timer: float = 0.0


# INITIALIZE

func initialize(boid: BoidBase) -> void:

	target = null
	consumption_timer = 0.0


# UPDATE

func update(
	boid: BoidBase,
	delta: float
) -> void:

	if not enabled:
		return


	# --------------------------------------------------
	# ENERGY LOSS
	# --------------------------------------------------

	if energy_loss_per_second > 0.0:

		boid.remove_energy(
			energy_loss_per_second * delta
		)


	# --------------------------------------------------
	# COOLDOWN
	# --------------------------------------------------

	if consumption_timer > 0.0:

		consumption_timer -= delta

		target = null

		return


	# --------------------------------------------------
	# MINIMUM PREDATOR SIZE
	# --------------------------------------------------

	var predator_size: float = _get_boid_size(boid)

	if predator_size < minimum_predator_size:

		# Too small to consume anything.
		target = null

		return


	# --------------------------------------------------
	# TARGET
	# --------------------------------------------------

	if not is_instance_valid(target):

		# Throttle retries instead of searching again on every single
		# frame while no target is in range.
		if _search_retry_timer > 0.0:

			_search_retry_timer -= delta

		else:

			target = _find_food(boid)
			_search_retry_timer = search_retry_interval


	# --------------------------------------------------
	# EAT
	# --------------------------------------------------

	if target != null:

		var distance_sq: float = (
			boid.position.distance_squared_to(
				target.position
			)
		)

		if distance_sq <= eating_distance * eating_distance:

			_eat(
				boid,
				target
			)


# FIND FOOD

func _find_food(
	boid: BoidBase
) -> BoidBase:

	var predator_size: float = _get_boid_size(boid)

	# Safety check in case this function is called
	# directly by another module.
	if predator_size < minimum_predator_size:
		return null


	var closest_food: BoidBase = null
	var closest_distance_sq: float = (
		detection_radius * detection_radius
	)

	# Was: loop every boid in BoidBase.all_boids. Now: only boids the
	# spatial grid says are actually within detection_radius, filled into
	# a reused array instead of allocating a new one each call.
	BoidBase.query_radius_into(
		boid.position,
		detection_radius,
		_nearby_scratch
	)

	for other in _nearby_scratch:

		if other == boid:
			continue


		# --------------------------------------------------
		# PREY SIZE
		# --------------------------------------------------

		var prey_size: float = _get_boid_size(other)

		if prey_size <= 0.0:
			continue


		# Predator must be sufficiently larger than prey.
		var size_ratio: float = (
			predator_size / prey_size
		)

		if size_ratio < minimum_size_ratio:
			continue


		# --------------------------------------------------
		# DISTANCE
		# --------------------------------------------------

		var distance_sq: float = (
			boid.position.distance_squared_to(
				other.position
			)
		)

		if distance_sq >= closest_distance_sq:
			continue


		closest_distance_sq = distance_sq
		closest_food = other


	return closest_food


# EAT

func _eat(
	boid: BoidBase,
	prey: BoidBase
) -> void:

	if not is_instance_valid(prey):
		target = null
		return

	if prey.is_queued_for_deletion():
		target = null
		return


	# Give the predator energy.
	boid.add_energy(
		energy_per_meal
	)


	# Start cooldown.
	consumption_timer = consumption_cooldown

	target = null


	# Remove prey.
	prey.queue_free()


# GET BOID SIZE

func _get_boid_size(
	boid: BoidBase
) -> float:

	if not is_instance_valid(boid):
		return 0.0

	var size_module: BoidSizeModule = (
		boid.get_module_by_type(
			BoidSizeModule
		)
	)

	if size_module == null:
		return 1.0

	return size_module.size


# EATING FORCE

func get_force(
	boid: BoidBase
) -> Vector2:

	if not enabled:
		return Vector2.ZERO


	if consumption_timer > 0.0:
		return Vector2.ZERO


	# Don't move toward prey if we're too small to eat.
	var predator_size: float = _get_boid_size(boid)

	if predator_size < minimum_predator_size:
		return Vector2.ZERO


	if not is_instance_valid(target):
		return Vector2.ZERO

	if target.is_queued_for_deletion():
		target = null
		return Vector2.ZERO


	var direction: Vector2 = (
		target.position - boid.position
	)

	if direction.length_squared() <= 0.001:
		return Vector2.ZERO


	var desired_velocity: Vector2 = (
		direction.normalized()
		* boid._get_max_speed()
	)

	var steering: Vector2 = (
		desired_velocity
		- boid.velocity
	)

	return steering.limit_length(
		eating_force
	)
