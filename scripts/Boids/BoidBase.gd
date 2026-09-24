extends Node2D
class_name BoidBase

static var boid_count: int = 0
static var gpu_flocking_enabled: bool = false

static var quadtree_split_count: int = 8
static var quadtree_max_depth: int = 10
static var _quadtree_root: QuadTreeNode = null
static var _quadtree_frame: int = -1


@export_group("Modules")
@export var modules: Array[BoidModifierModule] = []

@export_group("Flocking")
@export var max_force: float = 300.0
@export var perception_radius: float = 60.0
@export var separation_radius: float = 24.0
@export var separation_weight: float = 1.6
@export var alignment_weight: float = 1.0
@export var cohesion_weight: float = 1.0

@export_group("Edge Avoidance")
@export var edge_avoid_margin: float = 80.0
@export var edge_avoid_force: float = 500.0
@export var edge_avoid_curve: float = 2.0

@export_group("Biology")
@export var max_energy: float = 100.0
@export var starting_energy: float = 75.0

var energy: float = 0.0
var velocity: Vector2
var acceleration: Vector2
var external_force: Vector2 = Vector2.ZERO
var break_origin: Vector2
var _module_cache: Dictionary = {}
var _nearby_scratch: Array[BoidBase] = []
var draw_color: Color = Color.WHITE

static var all_boids: Array[BoidBase] = []
static var bounds: Rect2 = Rect2()


class QuadTreeNode:
	var bounds: Rect2
	var depth: int
	var boids: Array[BoidBase] = []
	var children: Array[QuadTreeNode] = []

	func _init(p_bounds: Rect2, p_depth: int):
		bounds = p_bounds
		depth = p_depth

	func is_leaf() -> bool:
		return children.is_empty()


func add_energy(amount: float) -> void:
	energy = clamp(energy + amount, 0.0, max_energy)


func remove_energy(amount: float) -> void:
	energy = max(energy - amount, 0.0)


static func _rebuild_quadtree_if_stale() -> void:
	var frame: int = Engine.get_process_frames()

	if _quadtree_frame == frame:
		return

	_quadtree_frame = frame

	if bounds.size == Vector2.ZERO:
		_quadtree_root = null
		return

	_quadtree_root = QuadTreeNode.new(
		bounds,
		0
	)

	for boid in all_boids:
		if is_instance_valid(boid):
			_quadtree_insert(
				_quadtree_root,
				boid
			)


static func _quadtree_insert(
	node: QuadTreeNode,
	boid: BoidBase
) -> void:
	if node.is_leaf():
		node.boids.append(boid)

		if (
			node.boids.size() > quadtree_split_count
			and node.depth < quadtree_max_depth
		):
			_quadtree_split(node)

		return

	for child in node.children:
		if _quadtree_contains_point(child.bounds, boid.position):
			_quadtree_insert(child, boid)
			return

	node.boids.append(boid)


static func _quadtree_split(node: QuadTreeNode) -> void:
	if not node.is_leaf():
		return

	if node.depth >= quadtree_max_depth:
		return

	var half_size: Vector2 = node.bounds.size * 0.5

	if half_size.x <= 0.001 or half_size.y <= 0.001:
		return

	var origin: Vector2 = node.bounds.position

	node.children = [
		QuadTreeNode.new(
			Rect2(origin, half_size),
			node.depth + 1
		),
		QuadTreeNode.new(
			Rect2(
				Vector2(origin.x + half_size.x, origin.y),
				half_size
			),
			node.depth + 1
		),
		QuadTreeNode.new(
			Rect2(
				Vector2(origin.x, origin.y + half_size.y),
				half_size
			),
			node.depth + 1
		),
		QuadTreeNode.new(
			Rect2(origin + half_size, half_size),
			node.depth + 1
		)
	]

	var old_boids: Array[BoidBase] = node.boids
	node.boids = []

	for boid in old_boids:
		var inserted: bool = false

		for child in node.children:
			if _quadtree_contains_point(child.bounds, boid.position):
				_quadtree_insert(child, boid)
				inserted = true
				break

		if not inserted:
			node.boids.append(boid)


static func _quadtree_contains_point(
	rect: Rect2,
	point: Vector2
) -> bool:
	return (
		point.x >= rect.position.x
		and point.x <= rect.end.x
		and point.y >= rect.position.y
		and point.y <= rect.end.y
	)


static func _quadtree_rect_intersects(
	a: Rect2,
	b: Rect2
) -> bool:
	return not (
		a.end.x < b.position.x
		or a.position.x > b.end.x
		or a.end.y < b.position.y
		or a.position.y > b.end.y
	)


static func _quadtree_query(
	node: QuadTreeNode,
	query_rect: Rect2,
	result: Array[BoidBase]
) -> void:
	if not _quadtree_rect_intersects(node.bounds, query_rect):
		return

	for boid in node.boids:
		if is_instance_valid(boid):
			result.append(boid)

	for child in node.children:
		_quadtree_query(child, query_rect, result)


static func query_radius_into(
	center: Vector2,
	radius: float,
	result: Array[BoidBase]
) -> void:
	result.clear()

	if radius <= 0.0:
		return

	_rebuild_quadtree_if_stale()

	if _quadtree_root == null:
		return

	var query_rect: Rect2 = Rect2(
		center - Vector2.ONE * radius,
		Vector2.ONE * radius * 2.0
	)

	_quadtree_query(
		_quadtree_root,
		query_rect,
		result
	)


static func query_radius(
	center: Vector2,
	radius: float
) -> Array[BoidBase]:
	var result: Array[BoidBase] = []
	query_radius_into(center, radius, result)
	return result

func _exit_tree() -> void:
	all_boids.erase(self)
	boid_count = max(boid_count - 1, 0)

	_quadtree_frame = -1


func _ready() -> void:
	energy = starting_energy

	for module in modules:
		if module == null:
			continue

		_module_cache[module.get_script()] = module

	for module in modules:
		if module == null:
			continue

		module.initialize(self)

	velocity = (
		Vector2.RIGHT.rotated(randf() * TAU)
		* _get_max_speed()
	)

	all_boids.append(self)
	boid_count += 1

	draw_color = _compute_draw_color()


func _process(delta: float) -> void:
	for module in modules:
		if module == null:
			continue

		module.update(self, delta)

		if is_queued_for_deletion():
			return

	if gpu_flocking_enabled:
		external_force = _compute_external_force()
	else:
		_flock()

		if bounds.size != Vector2.ZERO:
			_avoid_edges()

		for module in modules:
			if module == null:
				continue

			acceleration += module.get_force(self)

			if is_queued_for_deletion():
				return

		velocity += acceleration * delta
		velocity = velocity.limit_length(_get_max_speed())
		position += velocity * delta

		if velocity.length_squared() > 0.01:
			rotation = velocity.angle()

		if bounds.size != Vector2.ZERO:
			position.x = clamp(
				position.x,
				bounds.position.x,
				bounds.end.x
			)

			position.y = clamp(
				position.y,
				bounds.position.y,
				bounds.end.y
			)
		else:
			_wrap_around()

		acceleration = Vector2.ZERO

	scale = _get_scale()
	draw_color = _compute_draw_color()

func _compute_external_force() -> Vector2:
	var force: Vector2 = Vector2.ZERO

	if bounds.size != Vector2.ZERO:
		force += _compute_edge_avoidance_force()

	for module in modules:
		if module == null:
			continue

		force += module.get_force(self)

	return force


func apply_gpu_motion(
	new_position: Vector2,
	new_velocity: Vector2
) -> void:
	velocity = new_velocity

	if velocity.length_squared() > 0.01:
		rotation = velocity.angle()

	position = new_position

	if bounds.size != Vector2.ZERO:
		position.x = clamp(
			position.x,
			bounds.position.x,
			bounds.end.x
		)

		position.y = clamp(
			position.y,
			bounds.position.y,
			bounds.end.y
		)
	else:
		_wrap_around()

## Lets external overlays (BoidQuadtreeDebugDraw) read the current
## quadtree without duplicating the rebuild-if-stale logic.
static func get_debug_quadtree_root() -> QuadTreeNode:
	_rebuild_quadtree_if_stale()
	return _quadtree_root
	
func _flock() -> void:
	var separation: Vector2 = Vector2.ZERO
	var alignment: Vector2 = Vector2.ZERO
	var cohesion: Vector2 = Vector2.ZERO

	var separation_count: int = 0
	var flock_weight: float = 0.0

	var perception_radius_sq: float = (
		perception_radius * perception_radius
	)

	var separation_radius_sq: float = (
		separation_radius * separation_radius
	)

	BoidBase.query_radius_into(
		position,
		perception_radius,
		_nearby_scratch
	)

	for other in _nearby_scratch:
		if other == self:
			continue

		var distance_sq: float = (
			position.distance_squared_to(
				other.position
			)
		)

		if (
			distance_sq <= 0.0
			or distance_sq >= perception_radius_sq
		):
			continue

		var distance: float = sqrt(distance_sq)

		if distance_sq < separation_radius_sq:
			separation += (
				position
				- other.position
			) / distance

			separation_count += 1

		var weight: float = 1.0

		for module in modules:
			if module == null:
				continue

			weight *= module.get_flock_weight(
				self,
				other
			)

		alignment += other.velocity * weight
		cohesion += other.position * weight
		flock_weight += weight

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
		).limit_length(max_force)

		var center: Vector2 = (
			cohesion / flock_weight
		)

		target_velocity = (
			(center - position).normalized()
			* _get_max_speed()
		)

		cohesion = (
			target_velocity
			- velocity
		).limit_length(max_force)

	if separation_count > 0:
		separation = (
			separation / separation_count
		).normalized()

		separation = (
			separation
			* _get_max_speed()
			- velocity
		).limit_length(max_force)

	acceleration += separation * separation_weight
	acceleration += alignment * alignment_weight
	acceleration += cohesion * cohesion_weight


func _get_max_speed() -> float:
	var speed: float = 100.0

	for module in modules:
		if module == null:
			continue

		speed = module.modify_speed(
			self,
			speed
		)

	return max(speed, 0.0)


func get_module_by_type(
	module_type: Variant
) -> BoidModifierModule:
	if _module_cache.has(module_type):
		return _module_cache[module_type]

	for module in modules:
		if module == null:
			continue

		if is_instance_of(module, module_type):
			_module_cache[module_type] = module
			return module

	return null


func _avoid_edges() -> void:
	acceleration += _compute_edge_avoidance_force()


func _compute_edge_avoidance_force() -> Vector2:
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

	var direction: Vector2 = Vector2.ZERO

	if velocity.length_squared() > 0:
		direction = velocity.normalized()

	if dist_left < edge_avoid_margin:
		var strength: float = _edge_push(dist_left)
		var moving_toward: float = max(-direction.x, 0.0)

		steer.x += strength * (
			0.5
			+ moving_toward * 2.0
		)

	if dist_right < edge_avoid_margin:
		var strength: float = _edge_push(dist_right)
		var moving_toward: float = max(direction.x, 0.0)

		steer.x -= strength * (
			0.5
			+ moving_toward * 2.0
		)

	if dist_top < edge_avoid_margin:
		var strength: float = _edge_push(dist_top)
		var moving_toward: float = max(-direction.y, 0.0)

		steer.y += strength * (
			0.5
			+ moving_toward * 2.0
		)

	if dist_bottom < edge_avoid_margin:
		var strength: float = _edge_push(dist_bottom)
		var moving_toward: float = max(direction.y, 0.0)

		steer.y -= strength * (
			0.5
			+ moving_toward * 2.0
		)

	if steer == Vector2.ZERO:
		return Vector2.ZERO

	steer = steer.normalized()

	var desired_velocity: Vector2 = (
		steer * _get_max_speed()
	)

	var steering: Vector2 = (
		desired_velocity
		- velocity
	)

	return steering.limit_length(
		edge_avoid_force
	)


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


func _compute_draw_color() -> Color:
	var color: Color = Color.WHITE

	for module in modules:
		if module == null:
			continue

		color = module.modify_color(
			self,
			color
		)

	return color


func _get_scale() -> Vector2:
	var boid_scale: Vector2 = Vector2.ONE

	for module in modules:
		if module == null:
			continue

		boid_scale *= module.get_scale(self)

	return boid_scale
