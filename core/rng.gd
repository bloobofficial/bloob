class_name Rng
extends RefCounted
## Seeded random numbers with the prototype's helpers (core/rng.ts). The prototype used
## mulberry32 for exact replays; replays are not ported, so this wraps Godot's generator.

var _r := RandomNumberGenerator.new()


func _init(seed_value: int = 0) -> void:
	_r.seed = seed_value


func next() -> float:
	return _r.randf()


func rangef(a: float, b: float) -> float:
	return a + (b - a) * _r.randf()


func pick(n: int) -> int:
	return mini(n - 1, floori(_r.randf() * n)) if n > 0 else 0


func chance(p: float) -> bool:
	return _r.randf() < p


func sgn() -> int:
	return -1 if _r.randf() < 0.5 else 1


## pick an index from a weights array
func weighted(weights) -> int:
	var total := 0.0
	for w in weights:
		total += w
	var r := _r.randf() * total
	for i in weights.size():
		r -= weights[i]
		if r < 0.0:
			return i
	return weights.size() - 1
