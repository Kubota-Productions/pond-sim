extends BoidModifierModule
class_name BoidSizeModule


@export_group("Size")
@export var min_size: float = 0.75
@export var max_size: float = 1.25

@export_group("Size Clustering")
@export var similarity_range: float = 0.08
@export var clustering_weight: float = 2.0


var size: float = 1.0
var size_factor: float = 0.0


func initialize(boid: BoidBase) -> void:
	size = randf_range(min_size, max_size)

	if max_size <= min_size:
		size_factor = 1.0
	else:
		size_factor = (size - min_size) / (max_size - min_size)


func get_scale(boid: BoidBase) -> Vector2:
	return Vector2.ONE * size


func get_flock_weight(boid: BoidBase, other: BoidBase) -> float:
	var other_size_module: BoidSizeModule = other.get_module_by_type(BoidSizeModule)

	if other_size_module == null:
		return 1.0

	var similarity: float = get_similarity(other_size_module)

	if similarity <= 0.0:
		return 1.0

	return 1.0 + similarity * clustering_weight


func get_similarity(other: BoidSizeModule) -> float:
	if other == null:
		return 0.0

	var size_difference: float = abs(size - other.size)

	if size_difference >= similarity_range:
		return 0.0

	var similarity: float = 1.0 - (size_difference / similarity_range)

	return similarity * similarity
