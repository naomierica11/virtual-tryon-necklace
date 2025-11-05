extends TextureButton

func _on_exit_pressed():
	print("❌ Exit button pressed - Quitting game...")
	get_tree().quit()
