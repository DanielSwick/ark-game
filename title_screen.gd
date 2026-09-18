extends Control

# The first thing players see. Survival/Creative jump straight into the
# world; Character/Settings open a sub-menu first.

func _on_survival_pressed() -> void:
	Global.mode = Global.Mode.SURVIVAL
	get_tree().change_scene_to_file("res://main.tscn")

func _on_creative_pressed() -> void:
	Global.mode = Global.Mode.CREATIVE
	get_tree().change_scene_to_file("res://main.tscn")

func _on_character_pressed() -> void:
	get_tree().change_scene_to_file("res://character_menu.tscn")

func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://settings_menu.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()
