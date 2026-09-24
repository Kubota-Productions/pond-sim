extends Node2D

## Drop this on a Node2D in your scene. If you leave boid_scene empty it will
## just attach boid.gd to a plain Node2D, so no .tscn is required to get going.
@export var boid_count: int = 150
@export var boid_scene: PackedScene = preload("res://boid.tscn")
@export var spawn_area: Rect2 = Rect2(Vector2.ZERO, Vector2(2000, 2000))

@export_group("Quadtree Debug")
@export var debug_quadtree: bool = false:
	set(value):
		debug_quadtree = value
		set_process(debug_quadtree)
		queue_redraw()
@export var debug_max_depth: int = -1   # -1 = draw every depth
@export var debug_line_width: float = 2.0
@export var debug_color: Color = Color(1.0, 0.0, 0.0, 0.5)

func _ready() -> void:
	z_index = 100   # draw on top of our own boid children, not behind them
	set_process(debug_quadtree)
	BoidBase.bounds = spawn_area
	for i in boid_count:
		_spawn_boid()

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if not debug_quadtree:
		return

	var root: BoidBase.QuadTreeNode = BoidBase.get_debug_quadtree_root()

	if root == null:
		return

	_draw_quad_node(root)

func _draw_quad_node(node: BoidBase.QuadTreeNode) -> void:
	if debug_max_depth >= 0 and node.depth > debug_max_depth:
		return

	if node.is_leaf():
		if node.boids.is_empty():
			return

		var alpha: float = clamp(
			0.25 + (float(node.boids.size()) / float(BoidBase.quadtree_split_count)) * 0.5,
			0.2, 0.8
		)

		var c := debug_color
		c.a = alpha

		draw_rect(node.bounds, c, false, debug_line_width)
		return

	for child in node.children:
		_draw_quad_node(child)

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
