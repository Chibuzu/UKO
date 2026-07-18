# ChoiceOverlay.gd
# Base for the simple full-screen choice overlays (PauseMenu, EndScreen): a dim
# backdrop, a list of drawn buttons with hover, one `choice` signal. Subclasses
# fill `_buttons`, place them via _btn_rect(), and draw their title/content in
# _draw_content(). (StoryPauseMenu stays separate on purpose — it's a tabbed
# panel with its own bag grid, not a button list.)
class_name ChoiceOverlay
extends Node2D

signal choice(which: String)

const DIM := Color(0, 0, 0, 0.62)   # the shared board-dimming backdrop

var _buttons: Array = []            # [{id, label}] — subclass fills in _init
var _hover := -1

# Where button i sits — the one thing every subclass lays out differently.
func _btn_rect(_i: int, _vp: Vector2) -> Rect2:
	push_error("ChoiceOverlay._btn_rect is abstract")
	return Rect2()

# Title / result text above the buttons — subclass draws its own.
func _draw_content(_vp: Vector2, _font: Font) -> void:
	pass

# Whether a button click also consumes the input event (the pause menu does, so
# the click can't fall through to the board while the tree is paused).
func _consumes_click() -> bool:
	return false

func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), DIM)
	var font := ThemeDB.fallback_font
	_draw_content(vp, font)
	for i in range(_buttons.size()):
		var r := _btn_rect(i, vp)
		draw_rect(r, ViewConfig.COL_BTN_HOVER if _hover == i else ViewConfig.COL_BTN)
		draw_rect(r, ViewConfig.COL_BOARD_EDGE, false, 2.0)
		draw_string(font, Vector2(r.position.x, r.position.y + 35), _buttons[i]["label"],
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 20, ViewConfig.COL_TEXT)

func _input(event: InputEvent) -> void:
	var vp := get_viewport_rect().size
	if event is InputEventMouseMotion:
		var m := get_local_mouse_position()
		var old := _hover
		_hover = -1
		for i in range(_buttons.size()):
			if _btn_rect(i, vp).has_point(m):
				_hover = i
				break
		if old != _hover:
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var m := get_local_mouse_position()
		for i in range(_buttons.size()):
			if _btn_rect(i, vp).has_point(m):
				if _consumes_click():
					get_viewport().set_input_as_handled()
				choice.emit(_buttons[i]["id"])
				return
