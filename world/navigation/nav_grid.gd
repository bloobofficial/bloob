class_name NavGrid
extends RefCounted
## Height-aware pathfinding over a room's cells.
##
## The prototype rebuilt BFS flow fields every tick (sim/flowfield.ts): 5 fields, toward Bloob
## and four anchor points around him. That's too much per-tick work for GDScript, so the port
## uses Godot's native AStar2D with the same connectivity: one-way edges (you can drop down any
## height but climb at most STEP_UP), 8 directions, no corner cutting past blocked cells.
## Callers keep a small cache dictionary so paths are only recomputed when needed.

const DIAG := 0.70710678
const REPATH_TICKS := 20

var astar := AStar2D.new()
var map: RoomMap


func build(m: RoomMap) -> void:
	map = m
	astar.clear()
	var w := m.w
	for cy in m.h:
		for cx in w:
			var c := cy * w + cx
			if _open(c):
				astar.add_point(c, Vector2((cx + 0.5) * Tuning.CELL, (cy + 0.5) * Tuning.CELL))
	for cy in m.h:
		for cx in w:
			var c := cy * w + cx
			if not _open(c):
				continue
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					if ox == 0 and oy == 0:
						continue
					var nx := cx + ox
					var ny := cy + oy
					if nx < 0 or ny < 0 or nx >= w or ny >= m.h:
						continue
					var n := ny * w + nx
					if not _can_step(c, n):
						continue
					if ox != 0 and oy != 0:
						if not _can_step(c, cy * w + nx) or not _can_step(c, ny * w + cx):
							continue
					astar.connect_points(c, n, false)


func _open(c: int) -> bool:
	return map.height[c] != Tuning.VOID_H and not map.wall[c]


func _can_step(from: int, to: int) -> bool:
	return _open(to) and map.height[to] - map.height[from] <= Tuning.STEP_UP


## the open cell nearest a point (goal cells must be walkable)
func goal_cell(p: Vector2) -> int:
	var c := map.cell_of(p.x, p.y)
	if c >= 0 and _open(c):
		return c
	var oc := map.nearest_open(p.x, p.y)
	return oc.y * map.w + oc.x


## Which way to walk from `from` toward goal cell `goal` (a unit vector, diagonals normalized),
## or ZERO when already there or unreachable (the prototype's flow field `sample` returning false).
func flow_dir(from: Vector2, goal: int, cache: Dictionary, tick: int) -> Vector2:
	var cur := map.cell_of(from.x, from.y)
	if cur < 0 or not astar.has_point(cur) or cur == goal or not astar.has_point(goal):
		return Vector2.ZERO
	var path: PackedInt64Array = cache.get("path", PackedInt64Array())
	var idx := path.find(cur)
	if cache.get("goal", -1) != goal or idx < 0 or idx >= path.size() - 1 or tick - int(cache.get("t", -9999)) > REPATH_TICKS:
		path = astar.get_id_path(cur, goal)
		cache["path"] = path
		cache["goal"] = goal
		cache["t"] = tick
		idx = 0
	if path.size() < 2:
		return Vector2.ZERO
	var nxt := int(path[idx + 1])
	var dx := signi(nxt % map.w - cur % map.w)
	var dy := signi(nxt / map.w - cur / map.w)
	if dx != 0 and dy != 0:
		return Vector2(dx * DIAG, dy * DIAG)
	return Vector2(dx, dy)


func reachable(from: Vector2, goal: int) -> bool:
	var cur := map.cell_of(from.x, from.y)
	if cur < 0 or not astar.has_point(cur) or not astar.has_point(goal):
		return false
	return cur == goal or astar.get_id_path(cur, goal).size() > 0
