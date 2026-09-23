@tool
extends Camera2D

## Attach directly to a Camera2D node. No class_name — avoids any global class
## name collisions with other scripts in your project.
## @tool is only here so the bounds debug outline (see show_bounds_debug below)
## renders in the editor viewport, not just at runtime.

@export_group("Zoom")
@export var zoom_step: float = 0.1
@export var min_zoom: float = 0.5
@export var max_zoom: float = 3.0
@export var zoom_smoothing: float = 10.0   # higher = snappier, lower = floatier

@export_group("Edge Pan")
@export var edge_pan_enabled: bool = true
@export var edge_pan_margin: float = 24.0   # pixels from screen edge that trigger panning
@export var edge_pan_speed: float = 900.0   # world units/sec at zoom = 1.0, at max strength
@export var edge_pan_curve: float = 2.0     # >1 = speed ramps up sharply near the very edge; 1.0 = linear

@export_group("Drag Pan")
@export var drag_pan_enabled: bool = true
@export var drag_button: MouseButton = MOUSE_BUTTON_MIDDLE
@export var drag_sensitivity: float = 1.0     # flat multiplier on drag speed
@export var drag_zoom_curve: float = 1.8      # 1.0 = natural 1:1 tracking under the cursor;
											   # >1 makes zoomed-in dragging slower and zoomed-out
											   # dragging faster than strict 1:1; <1 flattens both

@export_group("Smoothing")
@export var position_smoothing: float = 12.0   # higher = snappier, lower = floatier

@export_group("Bounds")
@export var bounds: Rect2 = Rect2():   # zero size = unbounded
	set(value):
		bounds = value
		queue_redraw()
@export var bounds_overscroll: float = 200.0:   # extra world units the camera may pan past the bounds edges; 0 = hard clamp at the edge
	set(value):
		bounds_overscroll = value
		queue_redraw()
@export var min_pan_range: float = 400.0   # guaranteed world units of drag freedom per axis, even if bounds end up tighter than this at the current zoom
## Optional: point this at your BoidsSpawner node and bounds will be copied
## from its spawn_area automatically at _ready(), so you only set it in one place.
@export var sync_bounds_from: NodePath:
	set(value):
		sync_bounds_from = value
		if is_inside_tree():
			_sync_bounds()
			queue_redraw()

@export_group("Debug")
@export var show_bounds_debug: bool = false:
	set(value):
		show_bounds_debug = value
		queue_redraw()
@export var bounds_debug_color: Color = Color(1.0, 0.2, 0.2, 0.8):          # the hard spawn_area rect
	set(value):
		bounds_debug_color = value
		queue_redraw()
@export var overscroll_debug_color: Color = Color(1.0, 1.0, 0.2, 0.5):     # the overscroll-expanded rect
	set(value):
		overscroll_debug_color = value
		queue_redraw()
@export var bounds_debug_line_width: float = 2.0:
	set(value):
		bounds_debug_line_width = value
		queue_redraw()

var _target_zoom: Vector2
var _target_position: Vector2
var _dragging: bool = false

func _ready() -> void:
	set_notify_transform(true)
	if Engine.is_editor_hint():
		_sync_bounds()
		queue_redraw()
		return
	_sync_bounds()
	_target_zoom = zoom
	_target_position = _clamp_to_bounds(global_position, _target_zoom)

func _notification(what: int) -> void:
	# The node's position/rotation/scale changed — either the camera panned at
	# runtime, or someone dragged it in the editor. Either way the debug
	# outline's local-space points are now stale.
	if what == NOTIFICATION_TRANSFORM_CHANGED and show_bounds_debug and bounds.size != Vector2.ZERO:
		queue_redraw()

func _sync_bounds() -> void:
	if sync_bounds_from != NodePath():
		var source := get_node_or_null(sync_bounds_from)
		if source and "spawn_area" in source:
			bounds = source.spawn_area

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(event.position, -zoom_step)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(event.position, zoom_step)
		elif drag_pan_enabled and event.button_index == drag_button:
			_dragging = event.pressed

	elif event is InputEventMouseMotion and _dragging:
		# Screen-space drag converted to world-space. zoom_factor scales how far
		# the world moves per pixel of mouse movement; drag_zoom_curve controls
		# how strongly that scales with how zoomed in/out the camera currently is.
		var zoom_factor: float = pow(_target_zoom.x, drag_zoom_curve)
		var world_delta: Vector2 = event.relative * zoom_factor * drag_sensitivity
		_target_position = _clamp_to_bounds(_target_position - world_delta, _target_zoom)
		global_position = _clamp_to_bounds(global_position - world_delta, zoom)   # applied instantly, bypassing the smoothing lerp

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if edge_pan_enabled and not _dragging:
		_edge_pan(delta)

	# Frame-rate independent smoothing.
	var pos_weight: float = 1.0 - exp(-position_smoothing * delta)
	var zoom_weight: float = 1.0 - exp(-zoom_smoothing * delta)
	global_position = global_position.lerp(_target_position, pos_weight)
	zoom = zoom.lerp(_target_zoom, zoom_weight)
	global_position = _clamp_to_bounds(global_position, zoom)

func _edge_pan(delta: float) -> void:
	if not get_window().has_focus():
		return

	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var viewport_size: Vector2 = get_viewport_rect().size

	# Skip edge panning if the cursor isn't even inside the window.
	if mouse_pos.x < 0 or mouse_pos.y < 0 or mouse_pos.x > viewport_size.x or mouse_pos.y > viewport_size.y:
		return

	var strength := Vector2.ZERO

	if mouse_pos.x <= edge_pan_margin:
		strength.x = -_edge_strength(mouse_pos.x)
	elif mouse_pos.x >= viewport_size.x - edge_pan_margin:
		strength.x = _edge_strength(viewport_size.x - mouse_pos.x)

	if mouse_pos.y <= edge_pan_margin:
		strength.y = -_edge_strength(mouse_pos.y)
	elif mouse_pos.y >= viewport_size.y - edge_pan_margin:
		strength.y = _edge_strength(viewport_size.y - mouse_pos.y)

	if strength != Vector2.ZERO:
		# Scale by zoom so pan speed feels consistent whether zoomed in or out.
		_target_position = _clamp_to_bounds(_target_position + strength * edge_pan_speed * delta * _target_zoom.x, _target_zoom)

## Converts a distance-from-edge (0 = touching the edge, edge_pan_margin = just
## inside the trigger band) into a 0..1 speed factor, curved so it ramps up
## sharply right at the edge when edge_pan_curve > 1.
func _edge_strength(distance_from_edge: float) -> float:
	var t: float = clamp(1.0 - (distance_from_edge / edge_pan_margin), 0.0, 1.0)
	return pow(t, edge_pan_curve) if edge_pan_curve != 1.0 else t

## Keeps the camera's visible rectangle inside bounds (expanded by
## bounds_overscroll) at the given zoom. If bounds is zero-size (unset), or if
## the visible area at this zoom is larger than the bounds on a given axis,
## that axis is left unclamped rather than being locked to the center — a
## hard center-lock made dragging feel dead whenever you were zoomed out
## enough that the view exceeded the play area.
func _clamp_to_bounds(pos: Vector2, at_zoom: Vector2) -> Vector2:
	if bounds.size == Vector2.ZERO:
		return pos

	var effective_bounds: Rect2 = bounds.grow(bounds_overscroll)
	var half: Vector2 = get_viewport_rect().size * at_zoom / 2.0
	var min_x: float = effective_bounds.position.x + half.x
	var max_x: float = effective_bounds.end.x - half.x
	var min_y: float = effective_bounds.position.y + half.y
	var max_y: float = effective_bounds.end.y - half.y

	# Never let the usable range get so tight it feels locked — widen
	# symmetrically around the center if it falls under min_pan_range.
	if min_x <= max_x and (max_x - min_x) < min_pan_range:
		var extra_x: float = (min_pan_range - (max_x - min_x)) / 2.0
		min_x -= extra_x
		max_x += extra_x
	if min_y <= max_y and (max_y - min_y) < min_pan_range:
		var extra_y: float = (min_pan_range - (max_y - min_y)) / 2.0
		min_y -= extra_y
		max_y += extra_y

	var x: float = clamp(pos.x, min_x, max_x) if min_x <= max_x else pos.x
	var y: float = clamp(pos.y, min_y, max_y) if min_y <= max_y else pos.y
	return Vector2(x, y)

func _draw() -> void:
	if not show_bounds_debug or bounds.size == Vector2.ZERO:
		return
	if bounds_overscroll > 0.0:
		_draw_world_rect(bounds.grow(bounds_overscroll), overscroll_debug_color)
	_draw_world_rect(bounds, bounds_debug_color)

## Draws a world-space rect as an outline, converting its corners into this
## node's local space so it stays pinned to the world regardless of where the
## camera itself has panned to.
func _draw_world_rect(rect: Rect2, color: Color) -> void:
	var corners: Array[Vector2] = [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	]
	var points := PackedVector2Array()
	for c in corners:
		points.append(to_local(c))
	points.append(points[0])
	draw_polyline(points, color, bounds_debug_line_width)

func _zoom_at(screen_pos: Vector2, delta_zoom: float) -> void:
	var old_zoom := _target_zoom
	var new_zoom_scalar: float = clamp(_target_zoom.x + delta_zoom, min_zoom, max_zoom)
	_target_zoom = Vector2(new_zoom_scalar, new_zoom_scalar)

	# Keep the world point under the cursor fixed while zooming.
	var viewport_size: Vector2 = get_viewport_rect().size
	var offset_from_center: Vector2 = screen_pos - viewport_size / 2.0
	var world_before: Vector2 = _target_position + offset_from_center * old_zoom
	var world_after: Vector2 = _target_position + offset_from_center * _target_zoom
	_target_position = _clamp_to_bounds(_target_position + world_before - world_after, _target_zoom)
