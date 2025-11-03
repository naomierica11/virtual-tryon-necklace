extends Node

@onready var video_texrect: TextureRect = $Video
@onready var overlay_ctl: Node = $Overlay
var hud: Label = null

var tcp := StreamPeerTCP.new()
var connected := false
var img := Image.new()
var tex := ImageTexture.new()
var frames := 0

func _ready():
	# Create HUD label
	hud = Label.new()
	hud.position = Vector2(10, 10)
	hud.add_theme_color_override("font_color", Color.WHITE)
	hud.add_theme_font_size_override("font_size", 20)
	add_child(hud)
	hud.text = "Starting..."
	
	# Verify nodes
	if video_texrect == null:
		hud.text = "ERROR: Video node not found!"
		return
	
	if overlay_ctl == null:
		hud.text = "ERROR: Overlay node not found!"
		return
	
	print("[Godot] Nodes OK")
	hud.text = "Connecting..."
	connect_to_server()

func connect_to_server():
	var err = tcp.connect_to_host("127.0.0.1", 5006)
	if err != OK:
		hud.text = "Connect failed: %d" % err
		return
	
	set_process(true)
	connected = true
	print("[Godot] Connecting to 127.0.0.1:5006...")

func _process(_dt):
	if not connected:
		return

	var status = tcp.get_status()
	
	if status == StreamPeerTCP.STATUS_CONNECTING:
		return
	
	if status != StreamPeerTCP.STATUS_CONNECTED:
		hud.text = "Disconnected"
		connected = false
		return

	var available = tcp.get_available_bytes()
	if available < 8:
		if frames == 0:
			hud.text = "Connected, waiting data..."
		return

	# Read header
	var meta_len = tcp.get_u32()
	var jpg_len = tcp.get_u32()
	
	# Wait for full packet
	available = tcp.get_available_bytes()
	if available < (meta_len + jpg_len):
		return

	# Read metadata
	var meta_result = tcp.get_data(meta_len)
	if meta_result[0] != OK:
		print("[Godot] Meta read error: ", meta_result[0])
		return
	
	var meta_bytes = meta_result[1]
	var meta_str = meta_bytes.get_string_from_utf8()
	
	# Parse JSON - GODOT 4 WAY
	var json = JSON.new()
	var parse_err = json.parse(meta_str)
	if parse_err != OK:
		print("[Godot] JSON parse error: ", json.get_error_message())
		return
	
	var meta = json.data
	
	# Read JPEG
	var jpg_result = tcp.get_data(jpg_len)
	if jpg_result[0] != OK:
		print("[Godot] JPEG read error: ", jpg_result[0])
		return
	
	var jpg_bytes = jpg_result[1]

	# Decode JPEG
	img = Image.new()
	var load_err = img.load_jpg_from_buffer(jpg_bytes)
	if load_err != OK:
		print("[Godot] JPEG decode error: ", load_err)
		return

	# Update texture
	tex = ImageTexture.create_from_image(img)
	video_texrect.texture = tex
	
	frames += 1
	
	if frames % 30 == 0:
		print("[Godot] Frame #", frames, " | Size: ", img.get_width(), "x", img.get_height())

	# Update necklace
	var has_face := false
	if meta != null and meta.has("face") and meta["face"] != null:
		var f = meta["face"]
		var ang = float(meta.get("angle", 0.0))
		overlay_ctl.call("update_accessory", f, ang, Vector2(meta["w"], meta["h"]))
		has_face = true

	# Update HUD
	hud.text = "Frames: %d | Face: %s | FPS: %.0f" % [frames, "YES" if has_face else "NO", Engine.get_frames_per_second()]
	overlay_ctl.visible = has_face