class_name LayoutTemplate
extends Resource
## A hand-designed map shape for explorable rooms (data/layouts). Each character of `rows` is
## a BLOCK x BLOCK patch of cells, so a 20 x 14 template makes an 80 x 56 cell room; change
## `block` to make every map bigger or smaller. LayoutBuilder expands it into a RoomData layout.
##
## Legend (one block each):
##   '#' forest (the walls of the map: trees, bushes along the edges)
##   '.' open ground          '*' open ground where enemies gather (spawn points)
##   'o' open ground with standing stones      '~' a pond
##   '=' the main path        'n' a narrow path through the trees (2 cells wide)
##   '$' a dead end with a loot spot           'h' a hidden pocket: loot behind brush
##   '1' a raised plateau     'g' plateau with a loot spot     '^' stairs up to the plateau north of it
##   'A' 'B' 'C' 'D' passages (A north, B east, C south, D west), on the template's edge

@export var id := ""
@export var shape := ""               ## LONG, WIDE, L-SHAPE, BRANCH, OPEN, CROSS
@export var names := PackedStringArray()   ## what a room built from it may be called
@export var block := 4
@export var rows := PackedStringArray()


func doors() -> String:
	var out := ""
	for id_ch in "ABCD":
		for r in rows:
			if r.contains(id_ch):
				out += id_ch
				break
	return out
