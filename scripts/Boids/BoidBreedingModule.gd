extends BoidModifierModule
class_name BoidBreedingModule


@export_group("Breeding")

@export var enabled: bool = true
@export var breeding_radius: float = 30.0
@export var breeding_cooldown: float = 10.0


@export_group("Population Control")

## Hard ceiling on the global boid count. Breeding is skipped entirely
## once BoidBase.boid_count reaches this. 0 = unlimited (not recommended —
## with starting_energy above minimum_energy, growth is exponential and
## will run away from your spawn_area with nothing else to check it).
@export var max_population: int = 400


@export_group("Maturity Requirements")

## Minimum age (seconds, from BoidAgeModule.age) required before a boid
## may breed. Skipped if the boid has no BoidAgeModule.
@export var minimum_breeding_age: float = 0.0

## If true, a boid must be fully grown (BoidAgeModule.growth_progress
## >= 1.0) before it may breed. Skipped if the boid has no BoidAgeModule.
@export var require_full_growth: bool = true

## Minimum BoidSizeModule.size required before a boid may breed. This is
## the boid's rolled genetic size trait (see BoidSizeModule), separate
## from growth progress — use it if you want only your larger-rolled
## individuals breeding, on top of / instead of maturity. 0 = no
## requirement. Skipped if the boid has no BoidSizeModule.
@export var minimum_breeding_size: float = 0.0


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

	# Jittered instead of a flat "1" so every boid spawned in the same
	# burst doesn't become breeding-eligible at the exact same instant.
	# A flat grace period synchronizes offspring into bursts, which is
	# part of what drives runaway exponential growth.
	breeding_timer = randf_range(0.5, 1.5)


# =============================================================
# UPDATE
# =============================================================

func update(
	boid: BoidBase,
	delta: float
) -> void:

	if not enabled:
		return

	# POPULATION CAP
	# Checked before anything else — cheapest possible early-out, and
	# the one thing standing between this system and unbounded growth
	# if predation isn't culling boids fast enough.
	if (
		max_population > 0
		and BoidBase.boid_count >= max_population
	):
		return

	if breeding_timer > 0.0:
		breeding_timer -= delta
		return

	if boid.energy < minimum_energy:
		return

	if not _is_mature(boid):
		return

	var mate: BoidBase = _find_mate(boid)

	if mate == null:
		return

	_breed(boid, mate)


# =============================================================
# MATURITY
# =============================================================

func _is_mature(
	boid: BoidBase
) -> bool:

	var age_module: BoidAgeModule = (
		boid.get_module_by_type(
			BoidAgeModule
		)
	)

	if age_module != null:

		if age_module.age < minimum_breeding_age:
			return false

		if (
			require_full_growth
			and age_module.growth_progress < 1.0
		):
			return false

	if minimum_breeding_size > 0.0:

		var size_module: BoidSizeModule = (
			boid.get_module_by_type(
				BoidSizeModule
			)
		)

		if (
			size_module != null
			and size_module.size < minimum_breeding_size
		):
			return false

	return true


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

		# IMPORTANT:
		# queue_free() is deferred, so a freed boid (e.g. one that was
		# just eaten this same frame) can remain in all_boids briefly.
		# Without this check a boid could be picked as a mate the exact
		# frame it's being removed from the scene.
		if other.is_queued_for_deletion():
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

		if not other_breeding._is_mature(other):
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

	if not _is_mature(boid):
		return

	if not _is_mature(mate):
		return


	var parent: Node = boid.get_parent()

	if parent == null:
		return


	# ---------------------------------------------------------
	# CREATE OFFSPRING
	# ---------------------------------------------------------

	var offspring: BoidBase = BoidBase.new()
	offspring.copy_base_configuration_from(boid)

	# Give the offspring inherited modules BEFORE adding it
	# to the scene tree.
	offspring.modules = _inherit_modules(
		boid,
		mate
	)

	# Let every inherited module know it's being carried over from a
	# parent, so it can preserve genetic state (e.g. size/speed/
	# intelligence) instead of having initialize() re-roll it below
	# when the offspring enters the tree.
	for module in offspring.modules:

		if module == null:
			continue

		module.prepare_offspring(
			offspring,
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

		# Capture runtime state (rolled speed/size/intelligence/etc.)
		# from the LIVE selected module before duplicating it — see
		# BoidModifierModule.get_inherited_state() for why this can't
		# just be left to duplicate() itself.
		var state_a: Dictionary = (
			selected_module.get_inherited_state()
		)

		var copy: BoidModifierModule = (
			selected_module.duplicate(true)
			as BoidModifierModule
		)

		if copy != null:
			copy.apply_inherited_state(state_a)
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

		var state_b: Dictionary = (
			module_b.get_inherited_state()
		)

		var copy: BoidModifierModule = (
			module_b.duplicate(true)
			as BoidModifierModule
		)

		if copy != null:
			copy.apply_inherited_state(state_b)
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
