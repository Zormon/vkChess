# TrajectoryPreview.gd - Renders a predicted parabolic arc using a MultiMesh of small spheres.
# Spheres are much more visible than 1-pixel PRIMITIVE_LINE_STRIP lines and
# also make the arc feel like a "dotted line" that's easy to read at a glance.
class_name TrajectoryPreview
extends Node3D

@export_group("Sampling")
@export var sample_count: int = 30
@export_range(0.005, 0.2, 0.005) var time_step: float = 0.04

@export_group("Style")
@export var color_aiming: Color = Color(1.0, 0.85, 0.15, 1.0)
@export var color_frozen: Color = Color(0.25, 1.0, 0.5, 1.0)
@export var ground_offset: float = 0.02
@export var dot_radius: float = 0.06

var _multi_mesh_instance: MultiMeshInstance3D
var _multi_mesh: MultiMesh
var _sphere_mesh: SphereMesh
var _sphere_material: StandardMaterial3D
var _current_color: Color = Color.YELLOW


func _ready() -> void:
	_sphere_material = StandardMaterial3D.new()
	_sphere_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sphere_material.albedo_color = _current_color
	_sphere_material.no_depth_test = false

	_sphere_mesh = SphereMesh.new()
	_sphere_mesh.radius = dot_radius
	_sphere_mesh.height = dot_radius * 2.0
	_sphere_mesh.radial_segments = 8
	_sphere_mesh.rings = 4
	_sphere_mesh.material = _sphere_material

	_multi_mesh = MultiMesh.new()
	_multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	_multi_mesh.mesh = _sphere_mesh
	_multi_mesh.instance_count = 0

	_multi_mesh_instance = MultiMeshInstance3D.new()
	_multi_mesh_instance.multimesh = _multi_mesh
	_multi_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_multi_mesh_instance)


## Recompute and redraw the arc.
## exclude: array of RIDs to skip (typically the active baton). Typed as
## untyped Array so callers can pass a generic Array without conversion errors.
## collision_mask: which physics layers to check for impact.
func update_arc(origin: Vector3, velocity: Vector3, exclude: Array = [], collision_mask: int = 0xFFFFFFFF) -> PackedVector3Array:
	var points: PackedVector3Array = _compute_points(origin, velocity, exclude, collision_mask)
	_redraw(points)
	return points


func hide_arc() -> void:
	_multi_mesh.instance_count = 0


func set_aiming_color() -> void:
	_current_color = color_aiming
	_sphere_material.albedo_color = _current_color


func set_frozen_color() -> void:
	_current_color = color_frozen
	_sphere_material.albedo_color = _current_color


func _compute_points(origin: Vector3, velocity: Vector3, exclude: Array, collision_mask: int) -> PackedVector3Array:
	var pts: PackedVector3Array = PackedVector3Array()
	pts.append(origin)
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var gravity_vec: Vector3 = Vector3.DOWN * float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	for i in range(1, sample_count + 1):
		var t: float = time_step * float(i)
		var pos: Vector3 = origin + velocity * t + 0.5 * gravity_vec * t * t
		# Clamp to ground plane to avoid sub-terrain rays.
		if pos.y < ground_offset:
			pos.y = ground_offset
		# Raycast from previous point to this point so we cut the arc at impact.
		var prev: Vector3 = pts[pts.size() - 1]
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(prev, pos, collision_mask, exclude)
		var hit: Dictionary = space_state.intersect_ray(query)
		if not hit.is_empty():
			pts.append(hit.position)
			return pts
		pts.append(pos)
	return pts


func _redraw(points: PackedVector3Array) -> void:
	if points.size() < 2:
		_multi_mesh.instance_count = 0
		return
	_multi_mesh.instance_count = points.size()
	for i in range(points.size()):
		_multi_mesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, points[i]))
