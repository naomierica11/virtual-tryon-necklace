extends Node

@onready var video_texrect: TextureRect = $Video
@onready var overlay_ctl: Node2D = $Overlay

var udp: PacketPeerUDP = null
var connected := false
var frames := 0

# Frame reconstruction
var current_frame_id := -1
var frame_chunks := {}
var frame_metadata := {}

func _ready():
	print("===== VideoClient Starting =====")
	
	# Check if Video node exists
	if not video_texrect:
		print("ERROR: Video TextureRect not found!")
		print("Make sure scene has: VideoClient/Video (TextureRect)")
		return
	
	# Check if Overlay exists
	if not overlay_ctl:
		print("ERROR: Overlay Node2D not found!")
		print("Make sure scene has: VideoClient/Overlay (Node2D)")
		return
	
	print("Video node OK:", video_texrect.get_path())
	print("Overlay node OK:", overlay_ctl.get_path())
	
	# Setup video display
	video_texrect.custom_minimum_size = Vector2(640, 480)
	video_texrect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	video_texrect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	video_texrect.modulate = Color(0.3, 0.3, 0.4)  # Darker while waiting
	
	# Start connection after delay
	await get_tree().create_timer(1.0).timeout
	_connect_udp()

func _connect_udp():
	print("\n[UDP] Initializing connection...")
	
	udp = PacketPeerUDP.new()
	
	# Bind to receive port
	var err = udp.bind(5007)
	if err != OK:
		print("UDP bind failed:", err)
		return
	
	print("Bound to port 5007")
	
	# Set server destination
	udp.set_dest_address("127.0.0.1", 5006)
	print("Server destination: 127.0.0.1:5006")
	
	# Send START message
	var start_msg = "START".to_utf8_buffer()
	var send_err = udp.put_packet(start_msg)
	
	if send_err != OK:
		print("Failed to send START:", send_err)
		return
	
	print("Sent START message to server")
	print("\nWaiting for video stream...")
	print("================================\n")
	
	connected = true
	set_process(true)

func _process(_delta):
	if not connected or not udp:
		return
	
	# Process packets (limit per frame)
	var packets_processed = 0
	var max_packets = 30
	
	while udp.get_available_packet_count() > 0 and packets_processed < max_packets:
		var packet = udp.get_packet()
		if packet.size() > 0:
			_process_packet(packet)
		packets_processed += 1
	
	# Cleanup old frames
	_cleanup_old_frames()

func _process_packet(packet: PackedByteArray):
	# Validate header size
	if packet.size() < 44:
		return
	
	# Parse header
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
		return
	
	# Extract chunk
	var chunk_data = packet.slice(44, 44 + chunk_len)
	
	# Initialize frame storage
	if not frame_chunks.has(frame_id):
		frame_chunks[frame_id] = {}
		frame_metadata[frame_id] = [num_chunks, jpg_size, has_face, fx, fy, fw, fh, angle]
	
	# Store chunk
	if not frame_chunks[frame_id].has(chunk_idx):
		frame_chunks[frame_id][chunk_idx] = chunk_data
	
	# Check if complete
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
	
	# Reconstruct JPEG
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
			# Missing chunk
			frame_chunks.erase(frame_id)
			frame_metadata.erase(frame_id)
			return
	
	# Decode JPEG
	var image = Image.new()
	var err = image.load_jpg_from_buffer(jpeg_bytes)
	
	if err != OK:
		frame_chunks.erase(frame_id)
		frame_metadata.erase(frame_id)
		return
	
	# Update display
	if video_texrect:
		if frames == 0:
			print("\n>>> FIRST FRAME RECEIVED! <<<")
			print("Resolution:", image.get_width(), "x", image.get_height())
			video_texrect.modulate = Color.WHITE  # Full brightness
		
		var tex = ImageTexture.create_from_image(image)
		video_texrect.texture = tex
	
	frames += 1
	
	# Update overlay
	var face_detected = has_face == 1
	if face_detected and overlay_ctl and overlay_ctl.has_method("update_accessory"):
		var scale_x = video_texrect.size.x / 320.0
		var scale_y = video_texrect.size.y / 240.0
		
		var scaled_face = [
			int(fx * scale_x),
			int(fy * scale_y),
			int(fw * scale_x),
			int(fh * scale_y)
		]
		
		overlay_ctl.update_accessory(scaled_face, angle, video_texrect.size)
	
	# Show/hide overlay
	if overlay_ctl:
		overlay_ctl.visible = face_detected
	
	# Debug stats
	if frames % 60 == 0:
		var fps = Engine.get_frames_per_second()
		print("Frame: %d | FPS: %d | Face: %s" % [frames, fps, "YES" if face_detected else "NO"])
	
	# Cleanup
	frame_chunks.erase(frame_id)
	frame_metadata.erase(frame_id)

func _cleanup_old_frames():
	if frame_chunks.size() > 5:
		var keys = frame_chunks.keys()
		keys.sort()
		
		for i in range(keys.size() - 5):
			frame_chunks.erase(keys[i])
			frame_metadata.erase(keys[i])

func _exit_tree():
	if udp:
		udp.close()
	print("\nUDP client closed")
