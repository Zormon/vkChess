# TrajectoryPreview.gd — Renders a predicted parabolic arc using ImmediateMesh.
# Uses simple kinematic integration: p = p0 + v*t + 0.5*g*t^2.
# Optionally raycasts between sample points to stop the arc at the first impact.
class_name TrajectoryPreview
extends Node3D

@export_group("Sampling")
@export var sample_count: int = 36
@export_range(0.005, 0.2, 0.005) var time_step: float = 0.04

@export_group("Style")
@export var color_aiming: Color = Color(1.0, 0.9, 0.2, 1.0)   # yellow while aiming
@export var color_frozen: Color = Color(0.25, 1.0, 0.45, 1.0) # green when frozen
@export var ground_offset: float = 0.02  # lift arc slightly to avoid z-fighting

var _mesh_instance: MeshInstance3D
var _immediate_mesh: ImmediateMesh
var _current_color: Color = Color.YELLOW


func _ready() -> void:
	_immediate_mesh = ImmediateMesh.new()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _immediate_mesh
	# Render above the default layer 0 so the arc is always visible.
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_instance)


## Recompute and redraw the arc.
## exclude: array of RIDs to skip (typically the active baton).
## collision_mask: which physics layers to check for impact.
func update_arc(origin: Vector3, velocity: Vector3, exclude: Array[RID] = [], collision_mask: int = 0xFFFFFFFF) -> PackedVector3Array:
	var points: PackedVector3Array = _compute_points(origin, velocity, exclude, collision_mask)
	_redraw(points)
	return points


func hide_arc() -> void:
	_immediate_mesh.clear_surfaces()


func set_aiming_color() -> void:
	_current_color = color_aiming


func set_frozen_color() -> void:
	_current_color = color_frozen


func _compute_points(origin: Vector3, velocity: Vector3, exclude: Array[RID], collision_mask: int) -> PackedVector3Array:
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
	_immediate_mesh.clear_surfaces()
	if points.size() < 2:
		return
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	_immediate_mesh.surface_set_color(_current_color)
	for p in points:
		_immediate_mesh.surface_add_vertex(p)
	_immediate_mesh.surface_end()
