extends Node3D

## Wind-bent leaves give the +X tailwind direction a readable cue before takeoff.

var _stems: Array[MeshInstance3D] = []
var _leaf_pivots: Array[Node3D] = []
var _time := 0.0


func _ready() -> void:
	_build_cue()


func _process(delta: float) -> void:
	_time += delta
	for index in _stems.size():
		var phase := _time * 2.4 + float(index) * 0.8
		var angle := -0.42 + sin(phase) * 0.04
		_stems[index].rotation.z = angle
		_leaf_pivots[index].rotation.z = angle * 0.72 + sin(phase + 0.55) * 0.025


func _build_cue() -> void:
	var stalk_material := _material(Color(0.32, 0.47, 0.27, 1.0))
	var leaf_materials: Array[StandardMaterial3D] = [
		_material(Color(0.38, 0.59, 0.34, 1.0)),
		_material(Color(0.54, 0.67, 0.35, 1.0)),
		_material(Color(0.29, 0.51, 0.35, 1.0)),
	]
	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.035
	stem_mesh.bottom_radius = 0.055
	stem_mesh.height = 1.12
	stem_mesh.radial_segments = 8
	var leaf_mesh := CapsuleMesh.new()
	leaf_mesh.radius = 0.11
	leaf_mesh.height = 0.62
	leaf_mesh.radial_segments = 8
	leaf_mesh.rings = 4

	for index in 5:
		var z := (float(index) - 2.0) * 0.36
		var stem := MeshInstance3D.new()
		stem.name = "DownwindStem_%02d" % index
		stem.mesh = stem_mesh
		stem.position = Vector3(0.0, 0.58, 0.0)
		stem.rotation.z = -0.52
		stem.material_override = stalk_material
		add_child(stem)
		_stems.append(stem)

		var leaf_pivot := Node3D.new()
		leaf_pivot.name = "DownwindLeafPivot_%02d" % index
		leaf_pivot.position = Vector3(0.0, 0.0, z)
		leaf_pivot.rotation.z = -0.30
		add_child(leaf_pivot)
		_leaf_pivots.append(leaf_pivot)

		for leaf_index in 3:
			var leaf := MeshInstance3D.new()
			leaf.name = "DownwindLeaf_%02d_%02d" % [index, leaf_index]
			leaf.mesh = leaf_mesh
			leaf.position = Vector3(0.28 + leaf_index * 0.12, 0.93 - leaf_index * 0.17, (leaf_index - 1) * 0.035)
			leaf.rotation.z = -1.02 + float(leaf_index) * 0.10
			leaf.scale = Vector3(0.72, 0.82, 0.58)
			leaf.material_override = leaf_materials[(index + leaf_index) % leaf_materials.size()]
			leaf_pivot.add_child(leaf)

	# A loose pair of leaves points into the open takeoff lane and sways with the stems.
	for index in 2:
		var leaf := MeshInstance3D.new()
		leaf.name = "FlowingLeaf_%02d" % index
		leaf.mesh = leaf_mesh
		leaf.position = Vector3(1.02 + index * 0.30, 0.58 + index * 0.24, -0.32 + index * 0.64)
		leaf.rotation.z = -0.72
		leaf.scale = Vector3(0.62, 0.80, 0.50)
		leaf.material_override = leaf_materials[index]
		add_child(leaf)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
