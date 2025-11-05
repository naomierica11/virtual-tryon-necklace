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
	else:
		print("✗ No necklace textures loaded")
	
	spr.visible = false
	# HAPUS BARIS INI: set_process_input(true) - biar UIController yang handle input

func current_name() -> String:
	if idx >= 0 and idx < names.size():
		return names[idx]
	return "unknown"

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

func save_snapshot() -> String:
	var viewport = get_viewport()
	if viewport == null:
		return ""
	
	var img: Image = viewport.get_texture().get_image()
	if img == null:
		return ""
	
	# SIMPAN DI FOLDER PROJECT (lebih mudah dicari)
	var datetime = Time.get_datetime_string_from_system()
	datetime = datetime.replace(":", "-").replace("T", "_").replace("-", "")
	var path = "res://screenshots/snapshot_%s.png" % datetime
	
	# Buat folder screenshots jika belum ada
	var dir = DirAccess.open("res://")
	if not dir.dir_exists("screenshots"):
		dir.make_dir("screenshots")
	
	if img.save_png(path) == OK:
		var full_path = ProjectSettings.globalize_path(path)
		print("✅ SNAPSHOT SAVED TO PROJECT FOLDER!")
		print("📁 Location: ", full_path)
		return path
	else:
		print("❌ FAILED TO SAVE SNAPSHOT")
		return ""
