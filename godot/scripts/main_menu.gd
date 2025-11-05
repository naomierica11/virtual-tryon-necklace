extends Control

func _ready():
	print("🎮 Main Menu Ready")

# These will be called when buttons are pressed (connected in editor)
func _on_start_pressed():
	print("🚀 Start button pressed - Loading main game...")
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _on_exit_pressed():
	print("❌ Exit button pressed - Quitting game...")
	get_tree().quit()
