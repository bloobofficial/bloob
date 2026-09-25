extends Node
## The 2.5D projection (prototype: render/camera.ts, a low 3/4 perspective camera).
##
## Godot port: gameplay runs on the ground plane in 2D (x right, y toward the camera), exactly
## like the prototype's sim. The Camera2D zooms the ground plane non-uniformly, squashing it
## vertically by sin(pitch) - the view a camera `pitch` degrees below the horizon gets. Height z
## is drawn as a vertical offset (z * cos(pitch) on screen), and upright sprites are
## counter-scaled so they stand at full size, like the prototype's billboards.
## The prototype's mild perspective (30 degree FOV) is approximated as orthographic.

signal changed

const PITCH_DEFAULT := 36.0
const VIEW_WIDTH_DEFAULT := 820.0

var pitch_deg := PITCH_DEFAULT        ## [ and ] tilt it (22..70)
var view_width := VIEW_WIDTH_DEFAULT  ## world units across the screen; - and = zoom (480..1600)
var ground_k := sin(deg_to_rad(PITCH_DEFAULT))    ## screen y per ground unit of depth
var height_k := cos(deg_to_rad(PITCH_DEFAULT))    ## screen y per unit of height


func set_pitch(deg: float) -> void:
	pitch_deg = clampf(deg, 22.0, 70.0)
	ground_k = sin(deg_to_rad(pitch_deg))
	height_k = cos(deg_to_rad(pitch_deg))
	changed.emit()


func set_view_width(w: float) -> void:
	view_width = clampf(w, 480.0, 1600.0)
	changed.emit()


## world-y offset that draws something `z` units up (world space is pre-squash ground space)
func lift(z: float) -> float:
	return -z * height_k / ground_k


## scale.y that makes an upright sprite show at full height after the ground squash
func upright() -> float:
	return 1.0 / ground_k


## base zoom for a viewport (fit the view width, keep at least ~62% of it vertically)
func zoom_for(viewport_size: Vector2) -> float:
	return minf(viewport_size.x / view_width, viewport_size.y / (view_width * 0.62))


## a world-space (camera space) point back onto the ground plane at height plane_z
func to_ground(world: Vector2, plane_z: float) -> Vector2:
	return Vector2(world.x, world.y - lift(plane_z))


## a ground point at height z to world space
func to_world(ground: Vector2, z: float) -> Vector2:
	return Vector2(ground.x, ground.y + lift(z))
