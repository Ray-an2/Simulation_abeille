extends Node3D

func _ready() -> void:
	var total := AABB()
	var first := true
	for m in find_children("*", "MeshInstance3D", true, false):
		var box: AABB = m.global_transform * m.get_aabb()
		total = box if first else total.merge(box)
		first = false
	var s := total.size * 100.0
	print("Taille de %s (cm) : %.1f x %.1f x %.1f" % [name, s.x, s.y, s.z])
