# PauseMenu.gd
# Esc during a duel dims the board and offers RESUME / RESTART / MAIN MENU.
# Emits `choice` with "resume", "restart", or "menu"; the controller does the rest.
# Runs while the tree is paused (PROCESS_MODE_ALWAYS is set by the controller).
class_name PauseMenu
extends Node2D

signal choice(which: String)

const BTN_W := 260
const BTN_H := 54
const GAP := 14

var _buttons := [
	{"id": "resume", "label": "RESUME"},
	{"id": "restart", "label": "RESTART"},
	{"id": "menu", "label": "MAIN MENU"},
]
var _hover := -1

func _btn_rect(i: int, vp: Vector2) -> Rect2:
	var total_h := _buttons.size() * BTN_H + (_buttons.size() - 1) * GAP
	var x := vp.x * 0.5 - BTN_W * 0.5
	var y := vp.y * 0.5 - total_h * 0.5 + i * (BTN_H + GAP)
	return Rect2(x, y, BTN_W, BTN_H)

func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.62))   # dim the board
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(0, vp.y * 0.30), "PAUSED",
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, 56, ViewConfig.COL_TEXT)
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
				get_viewport().set_input_as_handled()
				choice.emit(_buttons[i]["id"])
				return
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		choice.emit("resume")   # Esc again closes the menu
