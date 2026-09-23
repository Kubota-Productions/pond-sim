extends Node2D
class_name BoidBase

## Maintained incrementally in _ready() / _exit_tree() instead of being
## recomputed by scanning all_boids every time it's read. Counter.gd reads
## this every frame, so the old computed-property version was an O(n) scan
## just to display a number.
static var boid_count: int = 0


# MODULES
@export_group("Modules")

@export var modules: Array[BoidModifierModule] = []


# FLOCKING
@export_group("Flocking")

@export var max_force: float = 300.0
@export var perception_radius: float = 60.0
@export var separation_radius: float = 24.0

@export var separation_weight: float = 1.6
@export var alignment_weight: float = 1.0
@export var cohesion_weight: float = 1.0


# EDGE AVOIDANCE
@export_group("Edge Avoidance")

@export var edge_avoid_margin: float = 80.0
@export var edge_avoid_force: float = 500.0
@export var edge_avoid_curve: float = 2.0


# BIOLOGY
@export_group("Biology")

@export var max_energy: float = 100.0
@export var starting_energy: float = 75.0

var energy: float = 0.0

func add_energy(amount: float) -> void:
	energy = clamp(
		energy + amount,
		0.0,
		max_energy
	)

func remove_energy(amount: float) -> void:
	energy = max(
		energy - amount,
		0.0
	)


# RUNTIME
var velocity: Vector2
var acceleration: Vector2

var break_origin: Vector2

## script -> module instance. Built once in _ready() so get_module_by_type()
## is a dictionary lookup instead of a linear scan + is_instance_of check.
## This matters a lot because get_module_by_type() is called from inside the
## per-neighbor loops below (flocking, breeding, consumption, intelligence),
## so an O(module_count) scan there used to get multiplied by every single
## boid-pair check in the simulation.
var _module_cache: Dictionary = {}

## Reused every frame by _flock() so it doesn't allocate a fresh Array on
## every single call (that's 700+ allocations/frame at 700 boids, since
## flocking runs unconditionally for every boid every frame).
var _nearby_scratch: Array[BoidBase] = []

## Color this boid should be drawn with this frame, computed once here and
## read by BoidRenderer's single batched draw call instead of each boid
## doing its own draw_colored_polygon() call.
var draw_color: Color = Color.WHITE


# GLOBAL FLOCK
static var all_boids: Array[BoidBase] = []

static var bounds: Rect2 = Rect2()


# =============================================================
# SPATIAL GRID
# =============================================================
#
# _flock(), breeding, consumption and the intelligence break-group check
# all need to answer "which boids are near this position?". Looping over
# ALL boids to answer that (as before) is O(n^2) per frame, across FOUR
# separate systems, which is why things fell over well before 100 boids.
#
# This grid is rebuilt at most once per engine frame — whichever boid asks
# for it first that frame triggers the rebuild, everyone else that same
# frame reuses it — and turns "who's nearby" into checking a handful of
# buckets instead of scanning the whole flock.

## World units per grid cell. Keep this roughly in line with your largest
## interaction radius (perception / detection / break-group radius). The
## default spawn_area is 2000x2000 with radii around 60-100, so 100 is a
## reasonable starting point; tune per-project.
static var grid_cell_size: float = 100.0

static var _grid: Dictionary = {}
static var _grid_frame: int = -1


static func _cell_coords(pos: Vector2) -> Vector2i:
	return Vector2i(
		int(floor(pos.x / grid_cell_size)),
		int(floor(pos.y / grid_cell_size))
	)


static func _rebuild_grid_if_stale() -> void:

	var current_frame: int = Engine.get_process_frames()

	if current_frame == _grid_frame:
		return

	_grid_frame = current_frame

	# Reuse each cell's existing bucket array instead of replacing it with a
	# brand new Array every frame. Boids tend to stay in roughly the same
	# handful of cells from one frame to the next, so this keeps the same
	# backing arrays alive and just empties them, instead of allocating a
	# fresh array per used cell (up to ~boid_count of them) every frame.
	for cell in _grid.keys():
		(_grid[cell] as Array).clear()

	for boid in all_boids:

		if not is_instance_valid(boid):
			continue

		if boid.is_queued_for_deletion():
			continue

		var cell: Vector2i = _cell_coords(boid.position)

		if not _grid.has(cell):
			_grid[cell] = []

		(_grid[cell] as Array).append(boid)


## Fills `result` with every valid, non-freed boid within `radius` of
## `center` (clearing it first), instead of returning a freshly allocated
## array. Use this in hot paths — anything that runs every frame for every
## boid, like _flock() — paired with a persistent scratch array on the
## caller, to avoid allocating a new array on every single call.
static func query_radius_into(
	center: Vector2,
	radius: float,
	result: Array[BoidBase]
) -> void:

	_rebuild_grid_if_stale()

	result.clear()

	var cell_radius: int = int(ceil(radius / grid_cell_size))
	var center_cell: Vector2i = _cell_coords(center)

	for dx in range(-cell_radius, cell_radius + 1):

		for dy in range(-cell_radius, cell_radius + 1):

			var cell: Vector2i = center_cell + Vector2i(dx, dy)

			if not _grid.has(cell):
				continue

			for boid in _grid[cell]:

				if not is_instance_valid(boid):
					continue

				if boid.is_queued_for_deletion():
					continue

				result.append(boid)


## Convenience wrapper for call sites that aren't hot paths (e.g. gated
## behind a cooldown, so they don't run every frame for every boid) where
## allocating a fresh array each call is fine.
static func query_radius(
	center: Vector2,
	radius: float
) -> Array[BoidBase]:

	var result: Array[BoidBase] = []
	query_radius_into(center, radius, result)
	return result


# READY
func _ready() -> void:

	# ENERGY
	energy = starting_energy

	# Build the module lookup cache before anything calls
	# get_module_by_type() (including modules' own initialize()).
	for module in modules:

		if module == null:
			continue

		_module_cache[module.get_script()] = module

	# Initialize every installed module.
	for module in modules:

		if module == null:
			continue

		module.initialize(self)

	# Start moving in a random direction.
	velocity = (
		Vector2.RIGHT.rotated(randf() * TAU)
		* _get_max_speed()
	)

	all_boids.append(self)
	boid_count += 1

	draw_color = _compute_draw_color()


# EXIT TREE
func _exit_tree() -> void:

	# Remove this boid from the global flock immediately
	# when it leaves the scene tree.
	all_boids.erase(self)
	boid_count -= 1


# PROCESS
func _process(delta: float) -> void:

	# MODULE UPDATE
	for module in modules:

		if module == null:
			continue

		module.update(
			self,
			delta
		)

		# A module may have called queue_free().
		# Stop processing this boid immediately.
		if is_queued_for_deletion():
			return

	# FLOCK
	_flock()

	# EDGE AVOIDANCE
	if bounds.size != Vector2.ZERO:
		_avoid_edges()

	# MODULE FORCES
	for module in modules:

		if module == null:
			continue

		acceleration += module.get_force(
			self
		)

		# A future module could queue this boid for deletion.
		if is_queued_for_deletion():
			return

	# MOVEMENT
	velocity += acceleration * delta

	velocity = velocity.limit_length(
		_get_max_speed()
	)

	position += velocity * delta

	# ROTATION
	if velocity.length_squared() > 0.01:

		rotation = velocity.angle()

	# BOUNDS
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

	scale = _get_scale()

	draw_color = _compute_draw_color()

	acceleration = Vector2.ZERO


# FLOCK
func _flock() -> void:

	var separation: Vector2 = Vector2.ZERO
	var alignment: Vector2 = Vector2.ZERO
	var cohesion: Vector2 = Vector2.ZERO

	var separation_count: int = 0
	var flock_weight: float = 0.0

	var perception_radius_sq: float = perception_radius * perception_radius
	var separation_radius_sq: float = separation_radius * separation_radius

	# Was: loop every boid in the flock (O(n) per boid, O(n^2) total).
	# Now: only boids the spatial grid says could plausibly be nearby,
	# filled into a reused scratch array so this doesn't allocate every
	# single frame for every boid.
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

		# Only pay for the sqrt once we know this boid is an actual
		# neighbor, instead of on every candidate like distance_to() did.
		var distance: float = sqrt(distance_sq)

		# SEPARATION
		if distance_sq < separation_radius_sq:

			separation += (
				position
				- other.position
			) / distance

			separation_count += 1

		# MODULE FLOCKING WEIGHT
		var weight: float = 1.0

		for module in modules:

			if module == null:
				continue

			weight *= module.get_flock_weight(
				self,
				other
			)

		# ALIGNMENT
		alignment += (
			other.velocity
			* weight
		)

		# COHESION
		cohesion += (
			other.position
			* weight
		)

		flock_weight += weight

	# ALIGNMENT
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
		)

		alignment = alignment.limit_length(
			max_force
		)

	# COHESION
	if flock_weight > 0.0:

		var center: Vector2 = (
			cohesion / flock_weight
		)

		var target_velocity: Vector2 = (
			(center - position).normalized()
			* _get_max_speed()
		)

		cohesion = (
			target_velocity
			- velocity
		)

		cohesion = cohesion.limit_length(
			max_force
		)

	# SEPARATION
	if separation_count > 0:

		separation = (
			separation
			/ separation_count
		).normalized()

		separation = (
			separation
			* _get_max_speed()
			- velocity
		)

		separation = separation.limit_length(
			max_force
		)

	# APPLY FLOCKING
	acceleration += (
		separation
		* separation_weight
	)

	acceleration += (
		alignment
		* alignment_weight
	)

	acceleration += (
		cohesion
		* cohesion_weight
	)


# GET MAX SPEED
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


# GET MODULE
func get_module_by_type(
	module_type: Variant
) -> BoidModifierModule:

	if _module_cache.has(module_type):
		return _module_cache[module_type]

	for module in modules:

		if module == null:
			continue

		if is_instance_of(
			module,
			module_type
		):

			_module_cache[module_type] = module

			return module

	return null


# EDGE AVOIDANCE
func _avoid_edges() -> void:

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

	var direction: Vector2 = (
		velocity.normalized()
	)

	# LEFT
	if dist_left < edge_avoid_margin:

		var strength: float = _edge_push(
			dist_left
		)

		var moving_toward: float = max(
			-direction.x,
			0.0
		)

		steer.x += strength * (
			0.5
			+ moving_toward * 2.0
		)

	# RIGHT
	if dist_right < edge_avoid_margin:

		var strength: float = _edge_push(
			dist_right
		)

		var moving_toward: float = max(
			direction.x,
			0.0
		)

		steer.x -= strength * (
			0.5
			+ moving_toward * 2.0
		)

	# TOP
	if dist_top < edge_avoid_margin:

		var strength: float = _edge_push(
			dist_top
		)

		var moving_toward: float = max(
			-direction.y,
			0.0
		)

		steer.y += strength * (
			0.5
			+ moving_toward * 2.0
		)

	# BOTTOM
	if dist_bottom < edge_avoid_margin:

		var strength: float = _edge_push(
			dist_bottom
		)

		var moving_toward: float = max(
			direction.y,
			0.0
		)

		steer.y -= strength * (
			0.5
			+ moving_toward * 2.0
		)

	if steer != Vector2.ZERO:

		steer = steer.normalized()

		var desired_velocity: Vector2 = (
			steer * _get_max_speed()
		)

		var steering: Vector2 = (
			desired_velocity
			- velocity
		)

		acceleration += (
			steering.limit_length(
				edge_avoid_force
			)
		)


# EDGE PUSH
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


# WRAP
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


# DRAW COLOR
#
# Boids no longer draw themselves individually — at hundreds of boids, one
# CanvasItem._draw() call per boid (times one per frame, since the old code
# called queue_redraw() unconditionally every frame) became the bottleneck
# in its own right. BoidRenderer.gd now draws every boid in a single batched
# MultiMesh draw call instead, reading position/rotation/scale directly and
# this cached color, which still runs every module's modify_color() hook
# exactly as before.
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


# GET SCALE
func _get_scale() -> Vector2:

	var boid_scale: Vector2 = Vector2.ONE

	for module in modules:

		if module == null:
			continue

		boid_scale *= module.get_scale(
			self
		)

	return boid_scale
