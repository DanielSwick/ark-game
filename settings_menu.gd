extends Control

@onready var sensitivity_slider: HSlider = $CenterContainer/VBoxContainer/SensitivitySlider
@onready var sensitivity_label: Label = $CenterContainer/VBoxContainer/SensitivityLabel

func _ready() -> void:
	sensitivity_slider.value = Global.mouse_sensitivity
	_update_label()

func _on_sensitivity_slider_value_changed(value: float) -> void:
	Global.mouse_sensitivity = value
	_update_label()

func _update_label() -> void:
	sensitivity_label.text = "Mouse Sensitivity: %.4f" % Global.mouse_sensitivity

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://title_screen.tscn")
