extends Node3D

func _ready() -> void:
	var bounds := AABB()
	var found := false
	for node in $Model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		bounds = bounds.merge(box) if found else box
		found = true
	var center := bounds.get_center() if found else Vector3.ZERO
	var radius := maxf(bounds.size.length() * 0.5, 0.5)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = center + Vector3(radius * 1.8, radius, radius * 2.4)
	camera.look_at(center, Vector3.UP)
	camera.current = true
	var light := DirectionalLight3D.new()
	add_child(light)
	light.rotation = Vector3(-0.8, -0.4, 0.0)
	light.light_energy = 2.0
