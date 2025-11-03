extends Node

@onready var video_texrect: TextureRect = $Video
@onready var overlay_ctl: Node2D = $Overlay

var hud: Label = null
var udp: PacketPeerUDP = null
var connected := false
var frames := 0

# Frame reconstruction
var current_frame_id := -1
var frame_chunks := {}  # Dictionary to store chunks: {frame_id: {chunk_idx: data}}
var frame_metadata := {}  # Store metadata: {frame_id: [num_chunks, jpg_size, has_face, fx, fy, fw, fh, angle]}

func _ready():
	print("VideoClient - UDP Version")
	
	# HUD
	hud = Label.new()
	hud.position = Vector2(10, 10)
	hud.add_theme_color_override("font_color", Color.WHITE)
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_theme_constant_override("outline_size", 2)
	hud.add_theme_font_size_override("font_size", 18)
	add_child(hud)
	hud.z_index = 100
	
	if not video_texrect:
		hud.text = "ERROR: No Video node!"
		return
	
	video_texrect.custom_minimum_size = Vector2(320, 240)
	call_deferred("_setup_video")
	
	hud.text = "Connecting..."
	await get_tree().create_timer(1.0).timeout
	_connect_udp()

func _setup_video():
	if video_texrect:
		video_texrect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		video_texrect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		video_texrect.modulate = Color(0.3, 0.3, 0.4)

func _connect_udp():
	udp = PacketPeerUDP.new()
	
	# Bind to local port for receiving
	var err = udp.bind(5007)  # Client listens on different port
	if err != OK:
		hud.text = "Bind failed: " + str(err)
		print("UDP bind error: ", err)
		return
	
	# Set destination (server)
	udp.set_dest_address("127.0.0.1", 5006)
	
	# Send START message to initiate connection
	var start_msg = "START".to_utf8_buffer()
	var send_err = udp.put_packet(start_msg)
	if send_err != OK:
		hud.text = "Send failed: " + str(send_err)
		print("Failed to send START: ", send_err)
		return
	
	print("✓ Sent START message to server (127.0.0.1:5006)")
	
	connected = true
	set_process(true)
	hud.text = "Waiting for video..."

func _process(_delta):
	if not connected or not udp:
		return
	
	# Process all available packets (limit to prevent freezing)
	var packets_processed = 0
	var max_packets_per_frame = 20  # Process up to 20 packets per frame
	
	while udp.get_available_packet_count() > 0 and packets_processed < max_packets_per_frame:
		var packet = udp.get_packet()
		if packet.size() > 0:
			_process_packet(packet)
		packets_processed += 1
	
	# Cleanup old incomplete frames
	_cleanup_old_frames()

func _process_packet(packet: PackedByteArray):
	# Minimum header size check
	if packet.size() < 44:
		if frames % 100 == 0:
			print("⚠ Invalid packet size: ", packet.size())
		return
	
	# Parse header (40 bytes + 4 for angle)
	var frame_id = packet.decode_u32(0)
	var chunk_idx = packet.decode_u32(4)
	var num_chunks = packet.decode_u32(8)
	var chunk_len = packet.decode_u32(12)
	var jpg_size = packet.decode_u32(16)
	var has_face = packet.decode_u32(20)
	var fx = packet.decode_s32(24)
	var fy = packet.decode_s32(28)
	var fw = packet.decode_s32(32)
	var fh = packet.decode_s32(36)
	var angle = packet.decode_float(40)
	
	# Validate chunk data
	if packet.size() < 44 + chunk_len:
		print("⚠ Incomplete chunk data")
		return
	
	# Extract chunk data (skip 44-byte header)
	var chunk_data = packet.slice(44, 44 + chunk_len)
	
	# Initialize frame storage if new frame
	if not frame_chunks.has(frame_id):
		frame_chunks[frame_id] = {}
		frame_metadata[frame_id] = [num_chunks, jpg_size, has_face, fx, fy, fw, fh, angle]
	
	# Store chunk (avoid duplicates)
	if not frame_chunks[frame_id].has(chunk_idx):
		frame_chunks[frame_id][chunk_idx] = chunk_data
	
	# Check if frame is complete
	if frame_chunks[frame_id].size() == num_chunks:
		_reconstruct_frame(frame_id)

func _reconstruct_frame(frame_id: int):
	if not frame_metadata.has(frame_id):
		return
	
	var metadata = frame_metadata[frame_id]
	var num_chunks = metadata[0]
	var jpg_size = metadata[1]
	var has_face = metadata[2]
	var fx = metadata[3]
	var fy = metadata[4]
	var fw = metadata[5]
	var fh = metadata[6]
	var angle = metadata[7]
	
	# Reconstruct JPEG from chunks in order
	var jpeg_bytes = PackedByteArray()
	jpeg_bytes.resize(jpg_size)
	
	var offset = 0
	for i in range(num_chunks):
		if frame_chunks[frame_id].has(i):
			var chunk = frame_chunks[frame_id][i]
			for byte_idx in range(chunk.size()):
				if offset < jpg_size:
					jpeg_bytes[offset] = chunk[byte_idx]
					offset += 1
		else:
			print("⚠ Missing chunk ", i, " for frame ", frame_id)
			# Clean up incomplete frame
			frame_chunks.erase(frame_id)
			frame_metadata.erase(frame_id)
			return
	
	# Decode image
	var image = Image.new()
	var err = image.load_jpg_from_buffer(jpeg_bytes)
	
	if err != OK:
		if frames % 30 == 0:
			print("✗ JPEG decode error: ", err, " (size: ", jpeg_bytes.size(), ")")
		# Clean up failed frame
		frame_chunks.erase(frame_id)
		frame_metadata.erase(frame_id)
		return
	
	# Update texture
	if video_texrect:
		if frames == 0:
			print("✓ First frame received and decoded!")
			print("  Image size: ", image.get_width(), "x", image.get_height())
		
		var tex = ImageTexture.create_from_image(image)
		video_texrect.texture = tex
		video_texrect.modulate = Color.WHITE
	
	frames += 1
	
	# Face overlay
	var face_detected = has_face == 1
	if face_detected and overlay_ctl:
		if overlay_ctl.has_method("update_accessory"):
			# Scale face coordinates to match display size
			var scale_x = video_texrect.size.x / 320.0
			var scale_y = video_texrect.size.y / 240.0
			
			var scaled_face = [
				int(fx * scale_x),
				int(fy * scale_y),
				int(fw * scale_x),
				int(fh * scale_y)
			]
			
			overlay_ctl.update_accessory(scaled_face, angle, video_texrect.size)
	
	# Update HUD
	var fps = Engine.get_frames_per_second()
	var face_status = "YES" if face_detected else "NO"
	hud.text = "Frame: %d | Face: %s | FPS: %d" % [frames, face_status, fps]
	
	# Debug output
	if frames % 60 == 0:
		print("Stats - Frames: %d | FPS: %d | Face: %s" % [frames, fps, face_status])
	
	# Show/hide overlay based on face detection
	if overlay_ctl:
		overlay_ctl.visible = face_detected
	
	# Clean up this frame
	frame_chunks.erase(frame_id)
	frame_metadata.erase(frame_id)

func _cleanup_old_frames():
	# Keep only the last 5 frame IDs to prevent memory leak
	if frame_chunks.size() > 5:
		var keys_to_remove = []
		var keys = frame_chunks.keys()
		keys.sort()
		
		# Remove oldest frames
		for i in range(keys.size() - 5):
			keys_to_remove.append(keys[i])
		
		for key in keys_to_remove:
			frame_chunks.erase(key)
			frame_metadata.erase(key)

func _exit_tree():
	if udp:
		udp.close()
	print("UDP client closed")