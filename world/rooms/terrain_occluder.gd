class_name TerrainOccluder
extends Node2D
## One run of raised cells in a row (stairs, plateau, wall), drawn by TerrainView.
## Lives in the y-sorted Actors layer at the run's north edge, so it covers anything behind it.

var view: TerrainView
var cells: Array = []
var cy := 0


func _draw() -> void:
	for cx in cells:
		view.draw_cell(self, cx, cy, position)
