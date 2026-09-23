extends Node2D

## Drop this on a Node2D in your scene. If you leave boid_scene empty it will
## just attach boid.gd to a plain Node2D, so no .tscn is required to get going.
@export var boid_count: int = 150
@export var boid_scene: PackedScene = preload("res://boid.tscn")
@export var spawn_area: Rect2 = Rect2(Vector2.ZERO, Vector2(2000, 2000))

func _ready() -> void:
	BoidBase.bounds = spawn_area
	for i in boid_count:
		_spawn_boid()

func _spawn_boid() -> void:
	var boid: Node2D
	if boid_scene:
		boid = boid_scene.instantiate()
	else:
		boid = Node2D.new()
		boid.set_script(load("res://boid.gd"))

	add_child(boid)
	boid.position = Vector2(
		randf_range(spawn_area.position.x, spawn_area.end.x),
		randf_range(spawn_area.position.y, spawn_area.end.y)
	)

## Call this at runtime to grow or shrink the flock without reloading the scene.
func set_boid_count(new_count: int) -> void:
	var current := get_child_count()
	if new_count > current:
		for i in new_count - current:
			_spawn_boid()
	elif new_count < current:
		for i in current - new_count:
			get_child(get_child_count() - 1).queue_free()
	boid_count = new_count
