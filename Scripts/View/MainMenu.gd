# MainMenu.gd
# Title screen + difficulty selector, and the project's MAIN SCENE. PLAY opens
# the difficulty page; choosing a difficulty stores it (AI.selected_difficulty)
# and swaps to the game scene. MULTIPLAYER and GEAR stay placeholders.
# Pure view, drawn by hand like the rest of the UI.
class_name MainMenu
extends Node2D

const GAME_SCENE := "res://Game.tscn"   # adjust if your game scene lives elsewhere

const BTN_W := 300

var _mode := "main"        # "main" | "difficulty"
var _hover := -1

var _buttons := [
	{"id": "play", "label": "PLAY", "on": true},
	{"id": "multiplayer", "label": "MULTIPLAYER", "on": false},
	{"id": "gear", "label": "GEAR", "on": false},
]

# Difficulty page. EASY + CHALLENGING are real; HARD/EXTREME currently fall back
# to CHALLENGING, so they're shown but disabled until they're actually built.
var _diff_buttons := [
	{"diff": AI.Difficulty.EASY,        "label": "EASY",        "on": true},
	{"diff": AI.Difficulty.CHALLENGING, "label": "CHALLENGING", "on": true},
	{"diff": AI.Difficulty.HARD,        "label": "HARD",        "on": false},
	{"diff": AI.Difficulty.EXTREME,     "label": "EXTREME",     "on": false},
	{"diff": -1,                        "label": "BACK",        "on": true},
]

func _active() -> Array:
	return _buttons if _mode == "main" else _diff_buttons

func _btn_h() -> float:
	return 58.0 if _mode == "main" else 50.0

func _gap() -> float:
	return 18.0 if _mode == "main" else 14.0

func _top(vp: Vector2) -> float:
	return vp.y * (0.40 if _mode == "main" else 0.32)

func _btn_rect(i: int, vp: Vector2) -> Rect2:
	var x := vp.x * 0.5 - BTN_W * 0.5
	return Rect2(x, _top(vp) + i * (_btn_h() + _gap()), BTN_W, _btn_h())

func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), ViewConfig.COL_LOG_BG)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(0, vp.y * 0.20), "UKO DUEL",
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, 64, ViewConfig.COL_TEXT)
	if _mode == "difficulty":
		draw_string(font, Vector2(0, vp.y * 0.27), "SELECT DIFFICULTY",
			HORIZONTAL_ALIGNMENT_CENTER, vp.x, 22, ViewConfig.COL_TEXT_OFF)

	var items := _active()
	var bh := _btn_h()
	for i in range(items.size()):
		var b: Dictionary = items[i]
		var on: bool = b["on"]
		var r := _btn_rect(i, vp)
		var col := ViewConfig.COL_BTN
		if not on:
			col = ViewConfig.COL_BTN_OFF
		elif _hover == i:
			col = ViewConfig.COL_BTN_HOVER
		draw_rect(r, col)
		draw_rect(r, ViewConfig.COL_BOARD_EDGE, false, 2.0)
		var label: String = b["label"]
		if not on:
			label += "   (soon)"
		var tcol := ViewConfig.COL_TEXT if on else ViewConfig.COL_TEXT_OFF
		draw_string(font, Vector2(r.position.x, r.position.y + bh * 0.64), label,
			HORIZONTAL_ALIGNMENT_CENTER, BTN_W, 22, tcol)

func _input(event: InputEvent) -> void:
	var vp := get_viewport_rect().size
	if event is InputEventMouseMotion:
		var m := get_local_mouse_position()
		var old := _hover
		_hover = -1
		var items := _active()
		for i in range(items.size()):
			if items[i]["on"] and _btn_rect(i, vp).has_point(m):
				_hover = i
				break
		if old != _hover:
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var m := get_local_mouse_position()
		var items := _active()
		for i in range(items.size()):
			if not items[i]["on"] or not _btn_rect(i, vp).has_point(m):
				continue
			if _mode == "main":
				if items[i]["id"] == "play":
					_mode = "difficulty"          # PLAY opens the difficulty page
					_hover = -1
					queue_redraw()
			else:
				var diff: int = items[i]["diff"]
				if diff == -1:
					_mode = "main"                 # BACK
					_hover = -1
					queue_redraw()
				else:
					AI.selected_difficulty = diff  # carry the choice into the game
					get_tree().change_scene_to_file(GAME_SCENE)
			return
