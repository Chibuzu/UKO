# EndScreen.gd
# Shown over the board when a match ends: the result, then REMATCH or MAIN MENU.
# Emits `choice` with "rematch" or "menu"; the controller does the scene swap.
class_name EndScreen
extends Node2D

signal choice(which: String)

const BTN_W := 230
const BTN_H := 54
const GAP := 16

var _result := ""
var _color := Color.WHITE
var _buttons := [
	{"id": "replay", "label": "REPLAY"},
	{"id": "rematch", "label": "REMATCH"},
	{"id": "menu", "label": "MAIN MENU"},
]
var _hover := -1

func setup(result_text: String, result_color: Color) -> void:
	_result = result_text
	_color = result_color
	queue_redraw()

func _btn_rect(i: int, vp: Vector2) -> Rect2:
	var total := _buttons.size() * BTN_W + (_buttons.size() - 1) * GAP
	var x := vp.x * 0.5 - total * 0.5 + i * (BTN_W + GAP)
	var y := vp.y * 0.56
	return Rect2(x, y, BTN_W, BTN_H)

func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.62))   # dim the board
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(0, vp.y * 0.42), _result,
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, 60, _color)
	for i in range(_buttons.size()):
		var r := _btn_rect(i, vp)
		var col := ViewConfig.COL_BTN_HOVER if _hover == i else ViewConfig.COL_BTN
		draw_rect(r, col)
		draw_rect(r, ViewConfig.COL_BOARD_EDGE, false, 2.0)
		draw_string(font, Vector2(r.position.x, r.position.y + 35), _buttons[i]["label"],
			HORIZONTAL_ALIGNMENT_CENTER, BTN_W, 20, ViewConfig.COL_TEXT)

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
				choice.emit(_buttons[i]["id"])
				return
