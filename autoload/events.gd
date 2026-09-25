extends Node
## Signal bus: gameplay -> presentation (effects, audio, HUD). See core/ev.gd for the types.

signal game_event(type: int, x: float, y: float, a: float, b: float, z: float)


func push(type: int, x: float, y: float, a: float = 0.0, b: float = 0.0, z: float = 0.0) -> void:
	game_event.emit(type, x, y, a, b, z)
