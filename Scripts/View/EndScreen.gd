# EndScreen.gd
# Shown over the board when a match ends: the result, then REPLAY / REMATCH /
# MAIN MENU. Emits `choice`; the controller does the scene swap. Layout + the
# result text here; the shared overlay machinery lives in ChoiceOverlay.
class_name EndScreen
extends ChoiceOverlay

const BTN_W := 230
const BTN_H := 54
const GAP := 16

var _result := ""
var _color := Color.WHITE
var _reward := 0
var _balance := 0

func _init() -> void:
	_buttons = [
		{"id": "replay", "label": "REPLAY"},
		{"id": "rematch", "label": "REMATCH"},
		{"id": "menu", "label": "MAIN MENU"},
	]

func setup(result_text: String, result_color: Color, reward: int = 0, balance: int = 0) -> void:
	_result = result_text
	_color = result_color
	_reward = reward
	_balance = balance
	queue_redraw()

func _btn_rect(i: int, vp: Vector2) -> Rect2:
	var total := _buttons.size() * BTN_W + (_buttons.size() - 1) * GAP
	var x := vp.x * 0.5 - total * 0.5 + i * (BTN_W + GAP)
	var y := vp.y * 0.56
	return Rect2(x, y, BTN_W, BTN_H)

func _draw_content(vp: Vector2, font: Font) -> void:
	draw_string(font, Vector2(0, vp.y * 0.42), _result,
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, 60, _color)
	# Gold reward line (only when something was won; balance shown for context).
	if _reward > 0:
		draw_string(font, Vector2(0, vp.y * 0.42 + 38),
			"+%d GOLD     (total %d)" % [_reward, _balance],
			HORIZONTAL_ALIGNMENT_CENTER, vp.x, 26, ViewConfig.COL_GOLD)
