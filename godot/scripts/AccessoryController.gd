extends Node2D

@onready var spr: Sprite2D = $Necklace

var names = ["n1","n2","n3","n4","n5"]
var idx := 0
var textures: Array = []

# Adjustable positioning
var neck_offset_y := 0.85  # Posisi vertikal (0.0 = atas wajah, 1.0 = bawah wajah)
var neck_offset_below := 0.05  # Offset tambahan di bawah wajah (dalam proporsi tinggi wajah)

func _ready():
	# Load textures
	for n in names:
		var t = load("res://assets/necklaces/%s.png" % n)
		if t: 
			textures.append(t)
		else:
			print("WARNING: Failed to load texture: ", n)
	
	if textures.size() > 0:
		spr.texture = textures[idx]
		print("✓ Loaded ", textures.size(), " necklace textures")
		print("  Controls: UP/DOWN = adjust position, 1-5 = change necklace, H = hide, S = snapshot")
	else:
		print("✗ No necklace textures loaded")
	
	spr.visible = false
	set_process_input(true)

func current_name() -> String:
	if idx >= 0 and idx < names.size():
		return names[idx]
	return "unknown"

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
			# Fine-tune position dengan arrow keys
			KEY_UP:
				neck_offset_y -= 0.05
				neck_offset_y = clamp(neck_offset_y, 0.5, 1.2)
				print("Neck Y offset: %.2f (UP = higher)" % neck_offset_y)
			KEY_DOWN:
				neck_offset_y += 0.05
				neck_offset_y = clamp(neck_offset_y, 0.5, 1.2)
				print("Neck Y offset: %.2f (DOWN = lower)" % neck_offset_y)
			KEY_LEFT:
				neck_offset_below -= 0.02
				neck_offset_below = clamp(neck_offset_below, -0.1, 0.3)
				print("Below face offset: %.2f" % neck_offset_below)
			KEY_RIGHT:
				neck_offset_below += 0.02
				neck_offset_below = clamp(neck_offset_below, -0.1, 0.3)
				print("Below face offset: %.2f" % neck_offset_below)

func set_idx(i:int):
	if textures.size() == 0: 
		return
	
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

	# Skala kalung - 55% dari lebar wajah
	var w_target = fw * 0.55
	var texture_width = float(spr.texture.get_width())
	var texture_height = float(spr.texture.get_height())
	
	if texture_width == 0:
		return
		
	var h_target = w_target * (texture_height / texture_width)

	spr.rotation_degrees = angle
	spr.scale = Vector2(
		w_target / texture_width,
		h_target / texture_height
	)

	# POSISI KALUNG - Area Leher
	# X: Tengah wajah
	var x = fx + fw / 2.0
	
	# Y: Menggunakan posisi dalam bounding box wajah + offset
	# neck_offset_y = 0.85 berarti 85% dari tinggi wajah (sekitar area dagu bawah)
	# Lalu tambah sedikit offset untuk turun ke area leher
	var y = fy + (fh * neck_offset_y) + (fh * neck_offset_below)
	
	spr.position = Vector2(x, y)
	spr.visible = true
	
	# Debug setiap 2 detik
	if Engine.get_frames_drawn() % 120 == 0:
		print("Necklace - Face[%d,%d,%d,%d] Pos:(%.0f,%.0f) Y%%:%.0f%%" % [
			face[0], face[1], face[2], face[3], 
			x, y,
			neck_offset_y * 100
		])

func save_snapshot():
	var viewport = get_viewport()
	if viewport == null:
		return
		
	var img: Image = viewport.get_texture().get_image()
	var datetime = Time.get_datetime_string_from_system().replace(":","-").replace("T", "_")
	var path = "user://snapshot_%s.png" % datetime
	
	if img.save_png(path) == OK:
		print("✓ Snapshot saved: ", path)
		print("  Full path: ", ProjectSettings.globalize_path(path))
	else:
		print("✗ Failed to save snapshot")