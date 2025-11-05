extends Control

# Necklace info
var necklace_names = ["Elegant Gold", "Silver Chain", "Pearl Classic", "Ruby Pendant", "Diamond Luxe"]
var current_idx = 0

# UI References
var info_label: Label
var buttons: Array = []
var video_client: Node
var overlay: Node

func _ready():
	print("=== UI Controller Initializing ===")
	
	# PASTIKAN UI DI ATAS SEMUA
	z_index = 100
	mouse_filter = Control.MOUSE_FILTER_PASS
	
	# Cari node
	video_client = get_node("../VideoClient")
	if video_client:
		overlay = video_client.get_node("Overlay")
	
	_create_ui()
	_update_info_label()
	
	print("✓ UI Controller Ready")
	print("🎮 Controls: 1-5=Necklace, H=Hide/Show, S=Screenshot")
	print("💡 Press H to hide/show necklace, S to take screenshot")

func _create_ui():
	_create_necklace_panel()
	_create_info_label()
	_create_status_panel()

func _create_necklace_panel():
	# Panel container - POSISI LEBIH ATAS
	var panel = PanelContainer.new()
	panel.position = Vector2(20, 150)  # ↑ Posisi lebih tinggi
	panel.size = Vector2(200, 280)     # ↓ Sedikit lebih kecil
	panel.z_index = 101                 # ↑ Pastikan di atas
	add_child(panel)
	
	# Style panel
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.4, 0.6, 0.9)
	panel.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)
	
	# Title - LEBIH PENDEK
	var title = Label.new()
	title.text = "NECKLACES"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	vbox.add_child(title)
	
	var sep1 = HSeparator.new()
	vbox.add_child(sep1)
	
	# Buttons - LEBIH KECIL
	for i in range(5):
		var btn = Button.new()
		btn.text = "%d. %s" % [i + 1, necklace_names[i]]
		btn.custom_minimum_size = Vector2(160, 30)
		btn.pressed.connect(_on_necklace_click.bind(i))
		
		# Button style
		var btn_style = StyleBoxFlat.new()
		btn_style.bg_color = Color(0.2, 0.25, 0.3)
		btn_style.corner_radius_top_left = 5
		btn_style.corner_radius_top_right = 5
		btn_style.corner_radius_bottom_left = 5
		btn_style.corner_radius_bottom_right = 5
		btn.add_theme_stylebox_override("normal", btn_style)
		
		var hover_style = btn_style.duplicate()
		hover_style.bg_color = Color(0.3, 0.35, 0.4)
		btn.add_theme_stylebox_override("hover", hover_style)
		
		var pressed_style = btn_style.duplicate()
		pressed_style.bg_color = Color(0.4, 0.5, 0.6)
		btn.add_theme_stylebox_override("pressed", pressed_style)
		
		vbox.add_child(btn)
		buttons.append(btn)
	
	var sep2 = HSeparator.new()
	vbox.add_child(sep2)
	
	# Toggle button
	var hide_btn = Button.new()
	hide_btn.text = "Hide/Show (H)"
	hide_btn.custom_minimum_size = Vector2(160, 30)
	hide_btn.pressed.connect(_on_toggle_visibility)
	
	var toggle_style = StyleBoxFlat.new()
	toggle_style.bg_color = Color(0.3, 0.4, 0.2)
	toggle_style.corner_radius_top_left = 5
	toggle_style.corner_radius_top_right = 5
	toggle_style.corner_radius_bottom_left = 5
	toggle_style.corner_radius_bottom_right = 5
	hide_btn.add_theme_stylebox_override("normal", toggle_style)
	
	vbox.add_child(hide_btn)
	
	# Snapshot button
	var snap_btn = Button.new()
	snap_btn.text = "Snapshot (S)"
	snap_btn.custom_minimum_size = Vector2(160, 30)
	snap_btn.pressed.connect(_on_snapshot)
	
	var snap_style = StyleBoxFlat.new()
	snap_style.bg_color = Color(0.4, 0.3, 0.2)
	snap_style.corner_radius_top_left = 5
	snap_style.corner_radius_top_right = 5
	snap_style.corner_radius_bottom_left = 5
	snap_style.corner_radius_bottom_right = 5
	snap_btn.add_theme_stylebox_override("normal", snap_style)
	
	vbox.add_child(snap_btn)

func _create_info_label():
	info_label = Label.new()
	info_label.position = Vector2(20, 120)  # ↑ Posisi lebih tinggi
	info_label.size = Vector2(180, 40)
	info_label.add_theme_font_size_override("font_size", 12)
	info_label.add_theme_color_override("font_color", Color.WHITE)
	info_label.add_theme_color_override("font_outline_color", Color.BLACK)
	info_label.add_theme_constant_override("outline_size", 1)
	info_label.z_index = 101
	add_child(info_label)

func _create_status_panel():
	var viewport_size = get_viewport().get_visible_rect().size
	
	var status_panel = PanelContainer.new()
	status_panel.position = Vector2(viewport_size.x - 180, 20)  # ← Lebih kecil
	status_panel.size = Vector2(160, 140)                       # ← Lebih kecil
	status_panel.z_index = 101
	add_child(status_panel)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.4, 0.6, 0.9)
	status_panel.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	status_panel.add_child(vbox)
	
	var status_title = Label.new()
	status_title.text = "CONTROLS"
	status_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_title.add_theme_font_size_override("font_size", 12)
	status_title.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	vbox.add_child(status_title)
	
	var sep = HSeparator.new()
	vbox.add_child(sep)
	
	var help = Label.new()
	help.text = "1-5: Necklace\nH: Hide/Show\nS: Snapshot\nArrows: Position"
	help.add_theme_font_size_override("font_size", 10)
	help.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	vbox.add_child(help)

func _update_info_label():
	if overlay:
		var visibility = "ON" if overlay.visible else "OFF"
		# TEXT LEBIH PENDEK
		info_label.text = "%s\nVis: %s" % [necklace_names[current_idx], visibility]
	else:
		info_label.text = "Select necklace\n1-5"

func _on_necklace_click(idx: int):
	print("🎯 Button clicked:", idx)
	current_idx = idx
	
	if overlay and overlay.has_method("set_idx"):
		overlay.set_idx(idx)
		print("✓ Changed to:", necklace_names[idx])
		_update_button_styles()
	
	_update_info_label()

func _update_button_styles():
	for i in range(buttons.size()):
		var btn = buttons[i]
		var btn_style = StyleBoxFlat.new()
		
		if i == current_idx:
			btn_style.bg_color = Color(0.3, 0.5, 0.7)
		else:
			btn_style.bg_color = Color(0.2, 0.25, 0.3)
			
		btn_style.corner_radius_top_left = 5
		btn_style.corner_radius_top_right = 5
		btn_style.corner_radius_bottom_left = 5
		btn_style.corner_radius_bottom_right = 5
		
		btn.add_theme_stylebox_override("normal", btn_style)

func _on_toggle_visibility():
	print("👁️ Toggle UI KONTROL visibility pressed")
	
	# Toggle visibility semua child node UI (panel, button, label)
	for child in get_children():
		child.visible = !child.visible
	
	# Update info label untuk menampilkan status
	_update_info_label()
	
	# Debug info
	var visible_count = 0
	for child in get_children():
		if child.visible:
			visible_count += 1
	print("✓ UI kontrol visibility:", visible_count, "/", get_child_count(), " visible")

func _on_snapshot():
	print("📸 Snapshot pressed")
	if overlay and overlay.has_method("save_snapshot"):
		# Panggil method save_snapshot dan dapatkan path-nya
		var screenshot_path = overlay.save_snapshot()
		if screenshot_path != "":
			info_label.text = "Saved to:\n%s" % screenshot_path
			print("✓ Snapshot saved to:", screenshot_path)
			
			# Tampilkan path lengkap di console
			var full_path = ProjectSettings.globalize_path(screenshot_path)
			print("📁 Full path: ", full_path)
		else:
			info_label.text = "❌ Save failed!"
			print("✗ Failed to save snapshot")
		
		await get_tree().create_timer(3.0).timeout  # Tampilkan info lebih lama
		_update_info_label()

# FIX INPUT HANDLING - PASTIKAN TIDAK ADA KONFLIK
func _input(event):
	# Hanya proses jika ini key event dan pressed
	if event is InputEventKey and event.pressed and not event.is_echo():
		print("⌨️ Key pressed:", OS.get_keycode_string(event.keycode))
		
		match event.keycode:
			KEY_1, KEY_KP_1: 
				_on_necklace_click(0)
				get_viewport().set_input_as_handled()
			KEY_2, KEY_KP_2: 
				_on_necklace_click(1)
				get_viewport().set_input_as_handled()
			KEY_3, KEY_KP_3: 
				_on_necklace_click(2)
				get_viewport().set_input_as_handled()
			KEY_4, KEY_KP_4: 
				_on_necklace_click(3)
				get_viewport().set_input_as_handled()
			KEY_5, KEY_KP_5: 
				_on_necklace_click(4)
				get_viewport().set_input_as_handled()
			KEY_H: 
				_on_toggle_visibility()
				get_viewport().set_input_as_handled()
			KEY_S: 
				_on_snapshot()
				get_viewport().set_input_as_handled()
			KEY_UP:
				_adjust_necklace_position(0, -1)
				get_viewport().set_input_as_handled()
			KEY_DOWN:
				_adjust_necklace_position(0, 1)
				get_viewport().set_input_as_handled()
			KEY_LEFT:
				_adjust_necklace_position(-1, 0)
				get_viewport().set_input_as_handled()
			KEY_RIGHT:
				_adjust_necklace_position(1, 0)
				get_viewport().set_input_as_handled()

func _adjust_necklace_position(x_dir: int, y_dir: int):
	if not overlay:
		return
	
	if y_dir != 0:
		overlay.neck_offset_y += y_dir * 0.05
		overlay.neck_offset_y = clamp(overlay.neck_offset_y, 0.5, 1.2)
		print("📏 Neck Y offset: %.2f" % overlay.neck_offset_y)
	
	if x_dir != 0:
		overlay.neck_offset_below += x_dir * 0.02
		overlay.neck_offset_below = clamp(overlay.neck_offset_below, -0.1, 0.3)
		print("📐 Below face offset: %.2f" % overlay.neck_offset_below)
	
	_update_info_label()

# PASTIKAN MOUSE EVENT BISA DITERIMA
func _gui_input(event):
	if event is InputEventMouseButton:
		print("🖱️ Mouse event in UI")
