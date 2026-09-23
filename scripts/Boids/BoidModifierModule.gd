extends Resource
class_name BoidModifierModule


func initialize(boid: BoidBase) -> void:
	pass


func update(
	boid: BoidBase,
	delta: float
) -> void:
	pass


func get_force(
	boid: BoidBase
) -> Vector2:
	return Vector2.ZERO


func modify_speed(
	boid: BoidBase,
	current_speed: float
) -> float:
	return current_speed


func get_flock_weight(
	boid: BoidBase,
	other: BoidBase
) -> float:
	return 1.0


func modify_color(
	boid: BoidBase,
	current_color: Color
) -> Color:
	return current_color


func get_scale(
	boid: BoidBase
) -> Vector2:
	return Vector2.ONE


## Called when this module is inherited by an offspring.
## Override this when a module needs to reset runtime state.
func prepare_offspring(
	offspring: BoidBase,
	parent_a: BoidBase,
	parent_b: BoidBase
) -> void:
	pass


## Override to return this module's genetically-inheritable runtime
## state (values normally rolled randomly in initialize(), like a
## rolled speed/size/intelligence) as a Dictionary.
##
## IMPORTANT: Resource.duplicate(true) does NOT copy plain (non-@export)
## script variables — only exported properties survive it. Runtime
## state like a rolled `speed` or `size` is deliberately not exported
## (it shouldn't be hand-edited in the inspector), so it is silently
## reset to its script default by duplicate(). This pair of methods is
## the explicit workaround: BoidBreedingModule calls
## get_inherited_state() on the LIVE parent module (before duplicating
## it) and apply_inherited_state() on the offspring's duplicated copy
## (after), carrying the value across by hand instead of relying on
## duplicate() to do it.
func get_inherited_state() -> Dictionary:
	return {}


## Override to apply state previously captured by get_inherited_state().
## Called on the offspring's module instance, after duplicate() and
## before initialize().
func apply_inherited_state(state: Dictionary) -> void:
	pass
