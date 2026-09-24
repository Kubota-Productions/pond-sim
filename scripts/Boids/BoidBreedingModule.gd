extends BoidModifierModule
class_name BoidBreedingModule


@export_group("Breeding")

@export var enabled: bool = true
@export var breeding_radius: float = 30.0
@export var breeding_cooldown: float = 10.0

## How often a boid re-searches for a mate after failing to find one.
@export var search_retry_interval: float = 0.25


@export_group("Population")

## Maximum number of living boids allowed.
## Breeding stops when this population is reached.
## 0 = unlimited.
@export var population_limit: int = 400


@export_group("Energy Requirements")

@export var minimum_energy: float = 70.0
@export var energy_cost: float = 10.0


@export_group("Size Compatibility")

@export var maximum_size_difference: float = 0.08


var breeding_timer: float = 0.0

var _nearby_scratch: Array[BoidBase] = []

var _search_retry_timer: float = 0.0


# =============================================================
# INITIALIZE
# =============================================================

func initialize(boid: BoidBase) -> void:
	breeding_timer = 1.0
	_search_retry_timer = 0.0


# =============================================================
# UPDATE
# =============================================================

func update(
	boid: BoidBase,
	delta: float
) -> void:

	if not enabled:
		return

	# Population limit.
	if (
		population_limit > 0
		and BoidBase.boid_count >= population_limit
	):
		return

	if breeding_timer > 0.0:
		breeding_timer -= delta
		return

	if boid.energy < minimum_energy:
		return

	# Throttle failed mate searches.
	if _search_retry_timer > 0.0:
		_search_retry_timer -= delta
		return

	var mate: BoidBase = _find_mate(boid)

	if mate == null:
		_search_retry_timer = search_retry_interval
		return

	_breed(boid, mate)


# =============================================================
# FIND MATE
# =============================================================

func _find_mate(
	boid: BoidBase
) -> BoidBase:

	var size_module: BoidSizeModule = (
		boid.get_module_by_type(
			BoidSizeModule
		)
	)

	if size_module == null:
		return null

	var breeding_radius_sq: float = (
		breeding_radius * breeding_radius
	)

	BoidBase.query_radius_into(
		boid.position,
		breeding_radius,
		_nearby_scratch
	)

	for other in _nearby_scratch:

		# queue_free() is deferred, so always validate before
		# accessing the object.
		if not is_instance_valid(other):
			continue

		if other == boid:
			continue

		if other.is_queued_for_deletion():
			continue

		var other_age: BoidAgeModule = (
			other.get_module_by_type(
				BoidAgeModule
			)
		)

		if other_age != null and other_age.is_dead:
			continue

		var other_breeding: BoidBreedingModule = (
			other.get_module_by_type(
				BoidBreedingModule
			)
		)

		if other_breeding == null:
			continue

		if not other_breeding.enabled:
			continue

		if other_breeding.breeding_timer > 0.0:
			continue

		if other.energy < other_breeding.minimum_energy:
			continue

		var distance_sq: float = (
			boid.position.distance_squared_to(
				other.position
			)
		)

		if distance_sq > breeding_radius_sq:
			continue

		var other_size: BoidSizeModule = (
			other.get_module_by_type(
				BoidSizeModule
			)
		)

		if other_size == null:
			continue

		var size_difference: float = abs(
			size_module.size
			- other_size.size
		)

		if size_difference > maximum_size_difference:
			continue

		return other

	return null


# =============================================================
# BREED
# =============================================================

func _breed(
	boid: BoidBase,
	mate: BoidBase
) -> void:

	if not is_instance_valid(mate):
		return

	if mate.is_queued_for_deletion():
		return

	if not boid.is_inside_tree():
		return

	if not mate.is_inside_tree():
		return

	if boid.energy < minimum_energy:
		return

	if mate.energy < minimum_energy:
		return

	# Re-check the population immediately before spawning.
	#
	# This is important because multiple boids can reach _breed()
	# during the same frame.
	if (
		population_limit > 0
		and BoidBase.boid_count >= population_limit
	):
		return

	var parent: Node = boid.get_parent()

	if parent == null:
		return


	# ---------------------------------------------------------
	# CREATE OFFSPRING
	# ---------------------------------------------------------

	var offspring: BoidBase

	if boid.scene_file_path.is_empty():
		offspring = BoidBase.new()
	else:
		offspring = (
			load(boid.scene_file_path) as PackedScene
		).instantiate()

	# Spawn halfway between the parents.
	offspring.position = (
		boid.position
		+ mate.position
	) * 0.5

	parent.add_child(offspring)


	# ---------------------------------------------------------
	# ENERGY COST
	# ---------------------------------------------------------

	boid.remove_energy(energy_cost)
	mate.remove_energy(energy_cost)


	# ---------------------------------------------------------
	# COOLDOWN
	# ---------------------------------------------------------

	breeding_timer = breeding_cooldown

	var mate_breeding: BoidBreedingModule = (
		mate.get_module_by_type(
			BoidBreedingModule
		)
	)

	if mate_breeding != null:
		mate_breeding.breeding_timer = (
			mate_breeding.breeding_cooldown
		)


# =============================================================
# INHERIT MODULES
# =============================================================

func _inherit_modules(
	offspring: BoidBase,
	parent_a: BoidBase,
	parent_b: BoidBase
) -> Array[BoidModifierModule]:

	var inherited: Array[BoidModifierModule] = []


	# ---------------------------------------------------------
	# MODULES FROM FIRST PARENT
	# ---------------------------------------------------------

	for module_a in parent_a.modules:

		if module_a == null:
			continue

		var module_b: BoidModifierModule = (
			_find_module_of_same_type(
				parent_b.modules,
				module_a
			)
		)

		var selected_module: BoidModifierModule

		if module_b != null:

			# Both parents have this module.
			# Randomly inherit one parent's version.
			if randf() < 0.5:
				selected_module = module_a
			else:
				selected_module = module_b

		else:

			# Only parent A has this module.
			selected_module = module_a


		var copy: BoidModifierModule = (
			selected_module.duplicate(true)
			as BoidModifierModule
		)

		if copy != null:

			# Give the module a chance to reset or configure
			# developmental state for the offspring.
			#
			# This is important for modules such as
			# BoidGrowthModule.
			copy.prepare_offspring(
				offspring,
				parent_a,
				parent_b
			)

			inherited.append(copy)


	# ---------------------------------------------------------
	# MODULES ONLY FOUND ON SECOND PARENT
	# ---------------------------------------------------------

	for module_b in parent_b.modules:

		if module_b == null:
			continue

		var already_inherited: bool = (
			_has_module_of_same_type(
				inherited,
				module_b
			)
		)

		if already_inherited:
			continue


		var copy: BoidModifierModule = (
			module_b.duplicate(true)
			as BoidModifierModule
		)

		if copy != null:

			copy.prepare_offspring(
				offspring,
				parent_a,
				parent_b
			)

			inherited.append(copy)


	return inherited


# =============================================================
# INHERIT BASE STATS
# =============================================================

func _inherit_base_stats(
	offspring: BoidBase,
	parent_a: BoidBase,
	parent_b: BoidBase
) -> void:

	# ---------------------------------------------------------
	# FLOCKING
	# ---------------------------------------------------------

	offspring.max_force = _inherit_stat(
		parent_a.max_force,
		parent_b.max_force
	)

	offspring.perception_radius = _inherit_stat(
		parent_a.perception_radius,
		parent_b.perception_radius
	)

	offspring.separation_radius = _inherit_stat(
		parent_a.separation_radius,
		parent_b.separation_radius
	)

	offspring.separation_weight = _inherit_stat(
		parent_a.separation_weight,
		parent_b.separation_weight
	)

	offspring.alignment_weight = _inherit_stat(
		parent_a.alignment_weight,
		parent_b.alignment_weight
	)

	offspring.cohesion_weight = _inherit_stat(
		parent_a.cohesion_weight,
		parent_b.cohesion_weight
	)


	# ---------------------------------------------------------
	# EDGE AVOIDANCE
	# ---------------------------------------------------------

	offspring.edge_avoid_margin = _inherit_stat(
		parent_a.edge_avoid_margin,
		parent_b.edge_avoid_margin
	)

	offspring.edge_avoid_force = _inherit_stat(
		parent_a.edge_avoid_force,
		parent_b.edge_avoid_force
	)

	offspring.edge_avoid_curve = _inherit_stat(
		parent_a.edge_avoid_curve,
		parent_b.edge_avoid_curve
	)


	# ---------------------------------------------------------
	# ENERGY
	# ---------------------------------------------------------

	offspring.max_energy = _inherit_stat(
		parent_a.max_energy,
		parent_b.max_energy
	)

	offspring.starting_energy = _inherit_stat(
		parent_a.starting_energy,
		parent_b.starting_energy
	)


# =============================================================
# INHERIT ONE STAT
# =============================================================

func _inherit_stat(
	value_a: float,
	value_b: float
) -> float:

	if randf() < 0.5:
		return value_a

	return value_b


# =============================================================
# FIND SAME MODULE TYPE
# =============================================================

func _find_module_of_same_type(
	modules_to_search: Array[BoidModifierModule],
	source_module: BoidModifierModule
) -> BoidModifierModule:

	for module in modules_to_search:

		if module == null:
			continue

		if module.get_script() == source_module.get_script():
			return module

	return null


# =============================================================
# CHECK MODULE TYPE
# =============================================================

func _has_module_of_same_type(
	modules_to_search: Array[BoidModifierModule],
	source_module: BoidModifierModule
) -> bool:

	return _find_module_of_same_type(
		modules_to_search,
		source_module
	) != null
