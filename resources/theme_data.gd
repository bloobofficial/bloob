class_name ThemeData
extends Resource
## A room's palette + fog (prototype: content/rooms.ts THEMES).

@export var id := ""
@export var floor := Color(0.22, 0.26, 0.24)
@export var plateau := Color(0.33, 0.34, 0.3)
@export var high := Color(0.4, 0.38, 0.33)
@export var stairs := Color(0.37, 0.33, 0.29)
@export var path := Color(0.34, 0.29, 0.2)
@export var wall := Color(0.27, 0.24, 0.31)
@export var wall_side := Color(0.2, 0.18, 0.25)
@export var cliff := Color(0.27, 0.22, 0.21)
@export var foliage := Color(0.1, 0.15, 0.11)   ## ground under trees and bushes
@export var water := Color(0.13, 0.24, 0.27)
@export var tree := Color(0.8, 0.95, 0.82)      ## sprite tint for trees / bushes
@export var fog := Color(0.05, 0.045, 0.07)     ## background + distance fog
