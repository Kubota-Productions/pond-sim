extends Node

## Moves the one thing that runs unconditionally for every boid every
## single frame — flocking's neighbor search, steering-force computation,
## and velocity/position integration — onto the GPU as a single compute
## shader dispatch, instead of N separate GDScript calls (even grid-
## accelerated ones still pay GDScript's per-call interpreter overhead on
## every neighbor check).
##
## WHAT THIS DOES NOT MOVE TO THE GPU, AND WHY:
## Breeding creates new BoidBase nodes and duplicates Resource modules.
## Aging and consumption call queue_free(). Intelligence's break state is a
## whole per-boid state machine. None of that can run inside a compute
## shader — a shader can't create nodes, free them, or call GDScript
## methods. Those systems are untouched: they still run in GDScript,
## through the same spatial grid on BoidBase, exactly as before.
##
## WHAT'S HARDCODED INSTEAD OF GENERIC:
## BoidModifierModule.get_flock_weight() is a dynamic per-pair hook on the
## CPU — a compute shader can't call it. This shader replicates the two
## hooks that actually matter today (BoidSizeModule and BoidSpeedModule's
## clustering) directly in GLSL. If you add a brand new module with its own
## get_flock_weight() later, it will NOT affect GPU flocking unless you add
## its formula here too — it'll still work normally for get_force(),
## modify_speed(), modify_color() and get_scale(), which all stay CPU-side.
##
## REQUIREMENTS:
## Your project must use the Forward+ or Mobile renderer. The Compatibility
## renderer (GLES3) has no RenderingDevice compute support, and this will
## silently fail to initialize (a push_error is printed and the node
## disables itself).
##
## SETUP:
## Add a plain Node anywhere in your scene and attach this script. Nothing
## else to wire up — it finds boids via BoidBase.all_boids automatically
## and sets BoidBase.gpu_flocking_enabled itself.

const _LOCAL_SIZE := 64

## 6 vec4s per boid: pos_vel, flock_params, flock_weights, size_params,
## speed_params, external_force. Kept as whole vec4 groups deliberately —
## std430 alignment rules get subtle fast if you mix bare floats and vec2s
## in a struct, so this sidesteps that by never doing so.
const _FLOATS_PER_BOID_INPUT := 24
const _FLOATS_PER_BOID_OUTPUT := 4  # vec4: new position (xy), new velocity (zw)

const _COMPUTE_SHADER_SOURCE := """
#version 450

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

struct BoidData {
	vec4 pos_vel;
	vec4 flock_params;
	vec4 flock_weights;
	vec4 size_params;
	vec4 speed_params;
	vec4 external_force;
};

layout(set = 0, binding = 0, std430) restrict buffer BoidBuffer {
	BoidData boids[];
} boid_buffer;

layout(set = 0, binding = 1, std430) restrict writeonly buffer OutputBuffer {
	vec4 results[];
} output_buffer;

layout(push_constant, std430) uniform Params {
	float delta;
	float boid_count;
	float pad0;
	float pad1;
} params;

// GLSL's normalize() divides by zero (producing NaN) on a zero-length
// vector. GDScript's Vector2.normalized() guards against exactly this and
// returns a zero vector instead — this replicates that safety so a single
// boid landing on an exactly-zero average velocity / center offset /
// separation sum (very plausible right at spawn, since initial velocities
// point in uniformly random directions) can't seed a NaN that then
// contaminates every neighbor's alignment/cohesion sum on the next frame.
vec2 safe_normalize(vec2 v) {
	float len_sq = dot(v, v);
	if (len_sq <= 0.0) {
		return vec2(0.0);
	}
	return v / sqrt(len_sq);
}

void main() {
	uint count = uint(params.boid_count);
	uint i = gl_GlobalInvocationID.x;

	if (i >= count) {
		return;
	}

	BoidData self_data = boid_buffer.boids[i];

	vec2 self_pos = self_data.pos_vel.xy;
	vec2 self_vel = self_data.pos_vel.zw;

	float max_speed = self_data.flock_params.x;
	float max_force = self_data.flock_params.y;
	float perception_radius = self_data.flock_params.z;
	float separation_radius = self_data.flock_params.w;

	float separation_weight = self_data.flock_weights.x;
	float alignment_weight = self_data.flock_weights.y;
	float cohesion_weight = self_data.flock_weights.z;

	float self_size = self_data.size_params.x;
	float size_similarity_range = self_data.size_params.y;
	float size_clustering_weight = self_data.size_params.z;

	float self_speed = self_data.speed_params.x;
	float speed_similarity_range = self_data.speed_params.y;
	float speed_clustering_weight = self_data.speed_params.z;

	vec2 separation = vec2(0.0);
	vec2 alignment = vec2(0.0);
	vec2 cohesion = vec2(0.0);

	int separation_count = 0;
	float flock_weight_total = 0.0;

	float perception_radius_sq = perception_radius * perception_radius;
	float separation_radius_sq = separation_radius * separation_radius;

	// Brute-force over every other boid. At a few hundred to a couple
	// thousand boids this is still extremely fast: count threads each
	// doing O(count) work run in roughly O(count) wall-clock time on the
	// GPU's parallel hardware, unlike the CPU's serial O(count^2). No
	// spatial grid needed at this scale — that's a CPU-specific
	// optimization this shader doesn't need.
	for (uint j = 0u; j < count; j++) {
		if (j == i) {
			continue;
		}

		BoidData other = boid_buffer.boids[j];
		vec2 other_pos = other.pos_vel.xy;
		vec2 other_vel = other.pos_vel.zw;

		vec2 offset = self_pos - other_pos;
		float distance_sq = dot(offset, offset);

		if (distance_sq <= 0.0 || distance_sq >= perception_radius_sq) {
			continue;
		}

		float distance = sqrt(distance_sq);

		if (distance_sq < separation_radius_sq) {
			separation += offset / distance;
			separation_count += 1;
		}

		// FLOCK WEIGHT — mirrors BoidSizeModule.get_flock_weight() and
		// BoidSpeedModule.get_flock_weight() on the CPU. See the header
		// comment in BoidGPUFlock.gd about why this is hardcoded rather
		// than generic.
		float weight = 1.0;

		float other_size = other.size_params.x;
		float size_difference = abs(self_size - other_size);
		if (size_similarity_range > 0.0 && size_difference < size_similarity_range) {
			float size_similarity = 1.0 - (size_difference / size_similarity_range);
			size_similarity = size_similarity * size_similarity;
			weight *= 1.0 + size_similarity * size_clustering_weight;
		}

		float other_speed = other.speed_params.x;
		if (self_speed > 0.0 && speed_similarity_range > 0.0) {
			float speed_difference = abs(self_speed - other_speed);
			float speed_similarity = clamp(
				1.0 - (speed_difference / (self_speed * speed_similarity_range)),
				0.0,
				1.0
			);
			speed_similarity = speed_similarity * speed_similarity;
			weight *= 1.0 + speed_similarity * speed_clustering_weight;
		}

		alignment += other_vel * weight;
		cohesion += other_pos * weight;
		flock_weight_total += weight;
	}

	vec2 acceleration = vec2(0.0);

	if (flock_weight_total > 0.0) {
		vec2 average_velocity = alignment / flock_weight_total;
		vec2 target_velocity = safe_normalize(average_velocity) * max_speed;
		vec2 align_force = target_velocity - self_vel;
		float align_len = length(align_force);
		if (align_len > max_force) {
			align_force = align_force / align_len * max_force;
		}
		acceleration += align_force * alignment_weight;

		vec2 center = cohesion / flock_weight_total;
		vec2 cohesion_target = safe_normalize(center - self_pos) * max_speed;
		vec2 cohesion_force = cohesion_target - self_vel;
		float cohesion_len = length(cohesion_force);
		if (cohesion_len > max_force) {
			cohesion_force = cohesion_force / cohesion_len * max_force;
		}
		acceleration += cohesion_force * cohesion_weight;
	}

	if (separation_count > 0) {
		vec2 sep_dir = safe_normalize(separation / float(separation_count));
		vec2 separation_force = sep_dir * max_speed - self_vel;
		float sep_len = length(separation_force);
		if (sep_len > max_force) {
			separation_force = separation_force / sep_len * max_force;
		}
		acceleration += separation_force * separation_weight;
	}

	// Everything the CPU still computes per-boid this frame — edge
	// avoidance, break-wandering, eating-chase, any future custom module
	// force — arrives pre-summed here instead of being reimplemented in
	// GLSL.
	acceleration += self_data.external_force.xy;

	self_vel += acceleration * params.delta;

	float speed_len = length(self_vel);
	if (speed_len > max_speed) {
		self_vel = self_vel / speed_len * max_speed;
	}

	vec2 new_pos = self_pos + self_vel * params.delta;

	output_buffer.results[i] = vec4(new_pos, self_vel);
}
"""

var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _input_buffer: RID
var _output_buffer: RID
var _uniform_set: RID

var _capacity: int = 0
var _live_boids: Array[BoidBase] = []


func _ready() -> void:

	# Run after every boid's own _process() this frame (they're at the
	# default priority, 0; lower process_priority values run first in
	# Godot). This matters: boids compute external_force during their own
	# _process(), and this node needs that to already be set before it
	# uploads the buffer and dispatches.
	process_priority = 100

	_rd = RenderingServer.create_local_rendering_device()

	if _rd == null:
		push_error(
			"BoidGPUFlock: couldn't create a local RenderingDevice. " +
			"Your project's renderer is probably set to Compatibility " +
			"(GLES3), which doesn't support compute shaders — switch to " +
			"Forward+ or Mobile in Project Settings > Rendering > Renderer."
		)
		set_process(false)
		return

	var shader_source := RDShaderSource.new()
	shader_source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	shader_source.source_compute = _COMPUTE_SHADER_SOURCE

	var shader_spirv: RDShaderSPIRV = _rd.shader_compile_spirv_from_source(shader_source)

	var compile_error: String = shader_spirv.compile_error_compute

	if compile_error != "":
		push_error("BoidGPUFlock: shader failed to compile:\n" + compile_error)
		set_process(false)
		return

	_shader = _rd.shader_create_from_spirv(shader_spirv)
	_pipeline = _rd.compute_pipeline_create(_shader)

	BoidBase.gpu_flocking_enabled = true


func _exit_tree() -> void:

	BoidBase.gpu_flocking_enabled = false

	if _rd == null:
		return

	# Free GPU resources in dependency order (uniform set depends on the
	# buffers and the shader; the pipeline depends on the shader).
	if _uniform_set.is_valid():
		_rd.free_rid(_uniform_set)
	if _input_buffer.is_valid():
		_rd.free_rid(_input_buffer)
	if _output_buffer.is_valid():
		_rd.free_rid(_output_buffer)
	if _pipeline.is_valid():
		_rd.free_rid(_pipeline)
	if _shader.is_valid():
		_rd.free_rid(_shader)

	_rd.free()


func _process(delta: float) -> void:

	_live_boids.clear()

	for boid in BoidBase.all_boids:

		if not is_instance_valid(boid):
			continue

		if boid.is_queued_for_deletion():
			continue

		_live_boids.append(boid)

	var count: int = _live_boids.size()

	if count == 0:
		return

	_ensure_capacity(count)

	# ---------------------------------------------------------
	# PACK INPUT BUFFER
	# ---------------------------------------------------------

	var input_data := PackedFloat32Array()
	input_data.resize(count * _FLOATS_PER_BOID_INPUT)

	for i in count:

		var boid: BoidBase = _live_boids[i]

		var size_module: BoidSizeModule = boid.get_module_by_type(BoidSizeModule)
		var speed_module: BoidSpeedModule = boid.get_module_by_type(BoidSpeedModule)

		var size: float = 0.0
		var size_similarity_range: float = 0.0
		var size_clustering_weight: float = 0.0

		if size_module != null:
			size = size_module.size
			size_similarity_range = size_module.similarity_range
			size_clustering_weight = size_module.clustering_weight

		var speed_stat: float = 0.0
		var speed_similarity_range: float = 0.0
		var speed_clustering_weight: float = 0.0

		if speed_module != null:
			speed_stat = speed_module.speed
			speed_similarity_range = speed_module.similarity_range
			speed_clustering_weight = speed_module.clustering_weight

		var base: int = i * _FLOATS_PER_BOID_INPUT

		input_data[base + 0] = boid.position.x
		input_data[base + 1] = boid.position.y
		input_data[base + 2] = boid.velocity.x
		input_data[base + 3] = boid.velocity.y

		input_data[base + 4] = boid._get_max_speed()
		input_data[base + 5] = boid.max_force
		input_data[base + 6] = boid.perception_radius
		input_data[base + 7] = boid.separation_radius

		input_data[base + 8] = boid.separation_weight
		input_data[base + 9] = boid.alignment_weight
		input_data[base + 10] = boid.cohesion_weight
		input_data[base + 11] = 0.0

		input_data[base + 12] = size
		input_data[base + 13] = size_similarity_range
		input_data[base + 14] = size_clustering_weight
		input_data[base + 15] = 0.0

		input_data[base + 16] = speed_stat
		input_data[base + 17] = speed_similarity_range
		input_data[base + 18] = speed_clustering_weight
		input_data[base + 19] = 0.0

		input_data[base + 20] = boid.external_force.x
		input_data[base + 21] = boid.external_force.y
		input_data[base + 22] = 0.0
		input_data[base + 23] = 0.0

	_rd.buffer_update(
		_input_buffer,
		0,
		input_data.size() * 4,
		input_data.to_byte_array()
	)

	# ---------------------------------------------------------
	# DISPATCH
	# ---------------------------------------------------------

	var push_constant: PackedByteArray = PackedFloat32Array([
		delta,
		float(count),
		0.0,
		0.0
	]).to_byte_array()

	var compute_list: int = _rd.compute_list_begin()

	_rd.compute_list_bind_compute_pipeline(compute_list, _pipeline)
	_rd.compute_list_bind_uniform_set(compute_list, _uniform_set, 0)
	_rd.compute_list_set_push_constant(
		compute_list,
		push_constant,
		push_constant.size()
	)

	var group_count: int = int(ceil(float(count) / float(_LOCAL_SIZE)))
	_rd.compute_list_dispatch(compute_list, group_count, 1, 1)
	_rd.compute_list_end()

	# Synchronous submit+sync: simplest correct version, at the cost of the
	# CPU stalling until the GPU finishes this dispatch. If this dispatch
	# itself ever becomes the bottleneck (unlikely at hundreds-to-low-
	# thousands of boids), the next step would be double-buffering this
	# across two frames to overlap CPU and GPU work — more complexity, one
	# frame of latency, so it's worth measuring before reaching for it.
	_rd.submit()
	_rd.sync()

	# ---------------------------------------------------------
	# READ BACK AND APPLY
	# ---------------------------------------------------------

	var output_bytes: PackedByteArray = _rd.buffer_get_data(
		_output_buffer,
		0,
		count * _FLOATS_PER_BOID_OUTPUT * 4
	)

	var output_data: PackedFloat32Array = output_bytes.to_float32_array()

	for i in count:

		var boid: BoidBase = _live_boids[i]
		var base: int = i * _FLOATS_PER_BOID_OUTPUT

		var new_position := Vector2(
			output_data[base + 0],
			output_data[base + 1]
		)

		var new_velocity := Vector2(
			output_data[base + 2],
			output_data[base + 3]
		)

		boid.apply_gpu_motion(new_position, new_velocity)


func _ensure_capacity(needed: int) -> void:

	if needed <= _capacity:
		return

	_capacity = max(needed, max(_capacity * 2, 64))

	if _uniform_set.is_valid():
		_rd.free_rid(_uniform_set)
	if _input_buffer.is_valid():
		_rd.free_rid(_input_buffer)
	if _output_buffer.is_valid():
		_rd.free_rid(_output_buffer)

	_input_buffer = _rd.storage_buffer_create(
		_capacity * _FLOATS_PER_BOID_INPUT * 4
	)

	_output_buffer = _rd.storage_buffer_create(
		_capacity * _FLOATS_PER_BOID_OUTPUT * 4
	)

	var input_uniform := RDUniform.new()
	input_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	input_uniform.binding = 0
	input_uniform.add_id(_input_buffer)

	var output_uniform := RDUniform.new()
	output_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	output_uniform.binding = 1
	output_uniform.add_id(_output_buffer)

	_uniform_set = _rd.uniform_set_create(
		[input_uniform, output_uniform],
		_shader,
		0
	)
