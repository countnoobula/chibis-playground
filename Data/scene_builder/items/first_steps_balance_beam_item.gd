@tool
extends Node3D
class_name FirstStepsBalanceBeamItem

## Editor-visible preview for the runtime-built balance beam.
## The existing balance-beam scene creates its mesh and collision at runtime,
## so Scene Builder needs a visible editor proxy while designers place it.
const BALANCE_BEAM_SCENE := preload("res://features/stations/parkour_balance_beam.tscn")

@export_range(1.0, 32.0, 0.25) var beam_length: float = 8.0:
	set(value):
		beam_length = clampf(value, 1.0, 32.0)
		_update_editor_preview()

@export_range(0.05, 1.0, 0.01) var beam_radius: float = 0.14:
	set(value):
		beam_radius = clampf(value, 0.05, 1.0)
		_update_editor_preview()


func _ready() -> void:
	_update_editor_preview()
	if Engine.is_editor_hint():
		return

	var editor_preview := get_node_or_null("EditorPreview")
	if editor_preview:
		editor_preview.free()

	var gameplay_beam := BALANCE_BEAM_SCENE.instantiate() as ParkourBalanceBeam
	gameplay_beam.name = "ParkourBalanceBeam"
	gameplay_beam.beam_length = beam_length
	gameplay_beam.beam_radius = beam_radius
	add_child(gameplay_beam)


func _update_editor_preview() -> void:
	var preview_mesh := get_node_or_null("EditorPreview/BeamMesh") as MeshInstance3D
	if preview_mesh == null:
		return

	var cylinder := CylinderMesh.new()
	cylinder.top_radius = beam_radius
	cylinder.bottom_radius = beam_radius
	cylinder.height = beam_length
	preview_mesh.mesh = cylinder
	preview_mesh.position = Vector3(0.0, 0.0, -beam_length * 0.5)
	preview_mesh.rotation = Vector3(PI * 0.5, 0.0, 0.0)
