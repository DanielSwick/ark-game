extends Node

# Holds choices made in the menus (which mode, character color, sensitivity)
# so they survive when we swap between title_screen.tscn, the sub-menus, and
# main.tscn. Registered as an autoload named "Global" in Project Settings,
# so every other script can just call Global.mode, Global.player_color, etc.

enum Mode { SURVIVAL, CREATIVE }

var mode: Mode = Mode.SURVIVAL
var player_color: Color = Color(0.2, 0.6, 0.9)
var mouse_sensitivity: float = 0.003
