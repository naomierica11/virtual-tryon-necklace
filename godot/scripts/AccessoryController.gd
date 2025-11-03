extends Node2D

@onready var spr: Sprite2D = $Necklace

var names = ["n1","n2","n3","n4","n5"]
var idx := 0
var textures: Array = []

func _ready():
	for n in names:
		var t = load("res://assets/necklaces/%s.png" % n)
		if t: textures.append(t)
	if textures.size() > 0:
		spr.texture = textures[idx]
	spr.visible = false  # default sembunyi sampai ada face
	set_process_input(true)

func current_name() -> String:
	return names[idx]

func _input(event):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1, KEY_KP_1: set_idx(0)
			KEY_2, KEY_KP_2: set_idx(1)
			KEY_3, KEY_KP_3: set_idx(2)
			KEY_4, KEY_KP_4: set_idx(3)
			KEY_5, KEY_KP_5: set_idx(4)
			KEY_H: visible = !visible
			KEY_S: save_snapshot()

func set_idx(i:int):
	if textures.size() == 0: return
	idx = clamp(i, 0, textures.size()-1)
	spr.texture = textures[idx]
	print("Switched to necklace: ", names[idx])

func update_accessory(face: Array, angle: float, _frame_size: Vector2):
	if textures.size() == 0 or spr.texture == null:
		return

	var fx = float(face[0])
	var fy = float(face[1])
	var fw = float(face[2])
	var fh = float(face[3])

	# Skala kalung - sekitar 45% dari lebar wajah
	var w_target = fw * 0.45
	var h_target = w_target * (float(spr.texture.get_height()) / float(spr.texture.get_width()))

	spr.rotation_degrees = angle
	spr.scale = Vector2(
		w_target / float(spr.texture.get_width()),
		h_target / float(spr.texture.get_height())
	)

	# Posisi kalung di leher (60% dari tinggi wajah)
	var x = fx + fw / 2.0
	var y = fy + fh * 0.60
	
	spr.position = Vector2(x, y)
	spr.visible = true
	
	# Debug print setiap 30 frame
	if Engine.get_frames_drawn() % 30 == 0:
		print("Face: [%d,%d,%d,%d] | Necklace pos: (%.0f, %.0f) | Angle: %.1f" % [face[0], face[1], face[2], face[3], x, y, angle])

func save_snapshot():
	var img: Image = get_viewport().get_texture().get_image()
	var datetime = Time.get_datetime_string_from_system().replace(":","-")
	var path = "user://snapshot_%s.png" % datetime
	if img.save_png(path) == OK:
		print("✓ Snapshot saved: ", path)
		# Print absolute path untuk mudah dicari
		print("  Full path: ", ProjectSettings.globalize_path(path))
	else:
		print("✗ Failed to save snapshot")
