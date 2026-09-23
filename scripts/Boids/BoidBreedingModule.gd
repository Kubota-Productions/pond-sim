extends BoidModifierModule
class_name BoidBreedingModule


@export_group("Breeding")

@export var enabled: bool = true
@export var breeding_radius: float = 30.0
@export var breeding_cooldown: float = 10.0


@export_group("Energy Requirements")

@export var minimum_energy: float = 70.0
@export var energy_cost: float = 10.0


@export_group("Size Compatibility")

@export var maximum_size_difference: float = 0.08


var breeding_timer: float = 0.0


# =============================================================
# INITIALIZE
# =============================================================

func initialize(boid: BoidBase) -> void:
	breeding_timer = 1


# =============================================================
# UPDATE
# =============================================================

func update(
	boid: BoidBase,
	delta: float
) -> void:

	if not enabled:
		return

	if breeding_timer > 0.0:
		breeding_timer -= delta
		return

	if boid.energy < minimum_energy:
		return

	var mate: BoidBase = _find_mate(boid)

	if mate == null:
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

	for other in BoidBase.all_boids:

		if not is_instance_valid(other):
			continue

		if other == boid:
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

		var distance: float = (
			boid.position.distance_to(
				other.position
			)
		)

		if distance > breeding_radius:
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

	if not boid.is_inside_tree():
		return

	if not mate.is_inside_tree():
		return

	if boid.energy < minimum_energy:
		return

	if mate.energy < minimum_energy:
		return


	var parent: Node = boid.get_parent()

	if parent == null:
		return


	# ---------------------------------------------------------
	# CREATE OFFSPRING
	# ---------------------------------------------------------

	var offspring: BoidBase = BoidBase.new()

	# Give the offspring inherited modules BEFORE adding it
	# to the scene tree.
	offspring.modules = _inherit_modules(
		boid,
		mate
	)

	# Spawn halfway between parents.
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
	parent_a: BoidBase,
	parent_b: BoidBase
) -> Array[BoidModifierModule]:

	var inherited: Array[BoidModifierModule] = []

	# ---------------------------------------------------------
	# FIRST PARENT
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
			inherited.append(copy)


	return inherited


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
