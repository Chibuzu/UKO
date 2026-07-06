# ReplayBar.gd
# Bottom-of-screen control strip shown during end-of-match replay. Emits
# `replay_action` with "prev" | "play" | "next" | "exit". Pure view + hit-test,
# mirroring EndScreen's button pattern; the controller does the actual stepping.
class_name ReplayBar
extends Node2D

signal replay_action(which: String)

const BTN_W := 120
const BTN_H := 48
const GAP := 12

var _label := "TURN 1 / 1"
var _stats := ""            # per-turn resource readout (HP / MP / EN for both fighters)
var _buttons := [
	{"id": "prev", "label": "< PREV"},
	{"id": "play", "label": "PLAY"},
	{"id": "next", "label": "NEXT >"},
	{"id": "exit", "label": "EXIT"},
]
var _hover := -1
var _enabled := true

func set_label(t: String) -> void:
	_label = t
	queue_redraw()

# Live resource readout for the shown moment of the replay (updated by the controller
# on every step and around each animated turn).
func set_stats(a: Combatant, b: Combatant) -> void:
	_stats = "A   HP %d   MP %d   EN %d        B   HP %d   MP %d   EN %d" % [
		a.hp, a.mp, a.energy, b.hp, b.mp, b.energy]
	queue_redraw()

# Disable while a turn animates so a stray click can't desync the view.
func set_enabled(on: bool) -> void:
	_enabled = on
	queue_redraw()

func _total_w() -> float:
	return _buttons.size() * BTN_W + (_buttons.size() - 1) * GAP

func _btn_rect(i: int, vp: Vector2) -> Rect2:
	var x := vp.x * 0.5 - _total_w() * 0.5 + i * (BTN_W + GAP)
	var y := vp.y - BTN_H - 28
	return Rect2(x, y, BTN_W, BTN_H)

func _draw() -> void:
	var vp := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	if _stats != "":
		draw_string(font, Vector2(0, vp.y - BTN_H - 64), _stats,
			HORIZONTAL_ALIGNMENT_CENTER, vp.x, 15, ViewConfig.COL_TEXT_OFF)
	draw_string(font, Vector2(0, vp.y - BTN_H - 42), _label,
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, 18, ViewConfig.COL_TEXT)
	for i in range(_buttons.size()):
		var r := _btn_rect(i, vp)
		var col := ViewConfig.COL_BTN
		if _enabled and _hover == i:
			col = ViewConfig.COL_BTN_HOVER
		elif not _enabled:
			col = ViewConfig.COL_BTN.darkened(0.35)
		draw_rect(r, col)
		draw_rect(r, ViewConfig.COL_BOARD_EDGE, false, 2.0)
		draw_string(font, Vector2(r.position.x, r.position.y + 31), _buttons[i]["label"],
			HORIZONTAL_ALIGNMENT_CENTER, BTN_W, 16, ViewConfig.COL_TEXT)

func _input(event: InputEvent) -> void:
	if not _enabled:
		return
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
				replay_action.emit(_buttons[i]["id"])
				return
