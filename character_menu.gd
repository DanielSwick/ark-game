extends Control

@onready var color_picker: ColorPickerButton = $CenterContainer/VBoxContainer/ColorPickerButton
@onready var preview: ColorRect = $CenterContainer/VBoxContainer/Preview

func _ready() -> void:
	color_picker.color = Global.player_color
	preview.color = Global.player_color

func _on_color_picker_button_color_changed(color: Color) -> void:
	Global.player_color = color
	preview.color = color

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://title_screen.tscn")
