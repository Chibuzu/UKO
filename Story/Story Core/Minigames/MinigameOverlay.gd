# MinigameOverlay.gd
# Base class for the full-screen gathering mini-games. Owns the shared
# scaffolding every game was copy-pasting: the open/close lifecycle, the result
# hold-then-emit, the dim backdrop, and the drawn button. Subclasses implement
# their own start(...) (calling _open() once ready), _input and _draw, and end
# by calling _finish(quality).
#
# THE result contract: finished(quality: float) — 0.0 = failed/ruined/left,
# anything above is the success grade the caller converts into yield.
class_name MinigameOverlay
extends Control

signal finished(quality: float)

const DIM := Color(0, 0, 0, 0.58)   # the shared backdrop shade

var _done := false
var _quality := 0.0

# Fill the viewport, swallow the mouse, reset the result state, show.
func _open() -> void:
	_done = false
	_quality = 0.0
	set_anchors_preset(PRESET_FULL_RECT)
	size = get_viewport_rect().size
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = true
	queue_redraw()

# End the game: hold the result on screen briefly, then hide and report.
func _finish(q: float, hold := 0.7) -> void:
	_done = true
	_quality = q
	queue_redraw()
	await get_tree().create_timer(hold).timeout
	visible = false
	finished.emit(_quality)

# The shared dim backdrop — call first in _draw().
func _dim_backdrop() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), DIM)

# The shared drawn button; returns its rect for hit-testing.
func _button(font: Font, x: float, y: float, label: String) -> Rect2:
	var r := Rect2(x, y, 118, 34)
	draw_rect(r, Color(0.20, 0.21, 0.27))
	draw_rect(r, ViewConfig.COL_FRAME, false, 2.0)
	draw_string(font, Vector2(r.position.x, r.position.y + 23), label, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 15, ViewConfig.COL_TEXT)
	return r
