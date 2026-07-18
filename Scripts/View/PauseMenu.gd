# PauseMenu.gd
# Esc during a duel dims the board and offers RESUME / RESTART / MAIN MENU.
# Emits `choice` with "resume", "restart", or "menu"; the controller does the rest.
# Runs while the tree is paused (PROCESS_MODE_ALWAYS is set by the controller).
# Layout + Esc handling here; the shared overlay machinery lives in ChoiceOverlay.
class_name PauseMenu
extends ChoiceOverlay

const BTN_W := 260
const BTN_H := 54
const GAP := 14

func _init() -> void:
	_buttons = [
		{"id": "resume", "label": "RESUME"},
		{"id": "restart", "label": "RESTART"},
		{"id": "menu", "label": "MAIN MENU"},
	]

func _btn_rect(i: int, vp: Vector2) -> Rect2:
	var total_h := _buttons.size() * BTN_H + (_buttons.size() - 1) * GAP
	var x := vp.x * 0.5 - BTN_W * 0.5
	var y := vp.y * 0.5 - total_h * 0.5 + i * (BTN_H + GAP)
	return Rect2(x, y, BTN_W, BTN_H)

func _draw_content(vp: Vector2, font: Font) -> void:
	draw_string(font, Vector2(0, vp.y * 0.30), "PAUSED",
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, 56, ViewConfig.COL_TEXT)

func _consumes_click() -> bool:
	return true   # while paused, a click must never fall through to the board

func _input(event: InputEvent) -> void:
	super._input(event)
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		choice.emit("resume")   # Esc again closes the menu
