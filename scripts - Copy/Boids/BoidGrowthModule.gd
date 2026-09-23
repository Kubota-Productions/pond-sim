extends BoidModifierModule
class_name BoidGrowthModule


@export_group("Growth")

@export var enabled: bool = true

## Size at which growth begins.
@export var starting_size: float = 0.1

## Maximum size the boid can reach.
@export var maximum_size: float = 1.25

## How much size is gained per second.
@export var growth_rate: float = 0.05


@export_group("Energy")

## If enabled, the boid must have enough energy to grow.
@export var require_energy: bool = false

## Energy required to grow by one size unit.
@export var energy_per_size: float = 10.0


var current_size: float = 0.5


# =============================================================
# INITIALIZE
# =============================================================

func initialize(boid: BoidBase) -> void:

	current_size = starting_size

	var size_module: BoidSizeModule = (
		boid.get_module_by_type(
			BoidSizeModule
		)
	)

	if size_module != null:
		size_module.size = current_size


# =============================================================
# UPDATE
# =============================================================

func update(
	boid: BoidBase,
	delta: float
) -> void:

	if not enabled:
		return


	if current_size >= maximum_size:
		current_size = maximum_size
		_apply_size(boid)
		return


	# ---------------------------------------------------------
	# DETERMINE GROWTH
	# ---------------------------------------------------------

	var growth_amount: float = (
		growth_rate * delta
	)


	# ---------------------------------------------------------
	# ENERGY REQUIREMENT
	# ---------------------------------------------------------

	if require_energy:

		var energy_cost: float = (
			growth_amount * energy_per_size
		)

		if boid.energy < energy_cost:
			return

		boid.remove_energy(energy_cost)


	# ---------------------------------------------------------
	# GROW
	# ---------------------------------------------------------

	current_size += growth_amount

	current_size = min(
		current_size,
		maximum_size
	)


	_apply_size(boid)


# =============================================================
# APPLY SIZE
# =============================================================

func _apply_size(
	boid: BoidBase
) -> void:

	var size_module: BoidSizeModule = (
		boid.get_module_by_type(
			BoidSizeModule
		)
	)

	if size_module == null:
		return


	size_module.size = current_size


	# Keep the size factor updated so other modules can use it.
	if size_module.max_size <= size_module.min_size:

		size_module.size_factor = 1.0

	else:

		size_module.size_factor = clamp(
			(
				current_size
				- size_module.min_size
			)
			/
			(
				size_module.max_size
				- size_module.min_size
			),
			0.0,
			1.0
		)
