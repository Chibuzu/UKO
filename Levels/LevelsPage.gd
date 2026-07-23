# LevelsPage.gd
# The LEVELS select screen (round 20) -- a MainMenu page like the shop and the
# lobby: ten slots, locked/next/cleared states, the reward printed on the
# gear levels. Click an open level -> LevelBook.current -> the Levels scene.
class_name LevelsPage
extends Node2D

signal closed()

const LEVELS_SCENE := "res://Levels.tscn"
const COLS := 2
const SLOT_W := 340.0
const SLOT_H := 74.0
const GAP := 14.0

var _hover := -1

func open() -> void:
	_hover = -1
	visible = true
	queue_redraw()

func _slot_rect(i: int, vp: Vector2) -> Rect2:
	var grid_w := COLS * SLOT_W + (COLS - 1) * GAP
	var x := vp.x * 0.5 - grid_w * 0.5 + (i % COLS) * (SLOT_W + GAP)
	var y := vp.y * 0.30 + float(i / COLS) * (SLOT_H + GAP)
	return Rect2(x, y, SLOT_W, SLOT_H)

func _back_rect(vp: Vector2) -> Rect2:
	return Rect2(vp.x * 0.5 - 150, vp.y * 0.30 + 5 * (SLOT_H + GAP) + 10, 300, 50)

func _draw() -> void:
	if not visible:
		return
	var vp := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(0, vp.y * 0.22), "LEVELS",
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, 30, ViewConfig.COL_TEXT)
	draw_string(font, Vector2(0, vp.y * 0.26), "Learn the duel. Earn the set.",
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, 15, ViewConfig.COL_TEXT_OFF)
	for i in LevelBook.count():
		var n := i + 1
		var r := _slot_rect(i, vp)
		var unlocked := LevelProgress.is_unlocked(n)
		var beaten := LevelProgress.is_beaten(n)
		var col := ViewConfig.COL_BTN if unlocked else ViewConfig.COL_BTN_OFF
		if unlocked and _hover == i:
			col = ViewConfig.COL_BTN_HOVER
		draw_rect(r, col)
		draw_rect(r, ViewConfig.COL_BOARD_EDGE, false, 2.0)
		var lname := String(LevelBook.level(n)["name"])
		var title := "%d.  %s" % [n, lname if unlocked else "LOCKED"]
		var tcol := ViewConfig.COL_TEXT if unlocked else ViewConfig.COL_TEXT_OFF
		draw_string(font, Vector2(r.position.x + 16, r.position.y + 30), title,
			HORIZONTAL_ALIGNMENT_LEFT, SLOT_W - 32, 19, tcol)
		var sub := ""
		if beaten:
			sub = "CLEARED"
		elif unlocked:
			sub = LevelBook.objective_label(n)
		if sub != "":
			draw_string(font, Vector2(r.position.x + 16, r.position.y + 54), sub,
				HORIZONTAL_ALIGNMENT_LEFT, SLOT_W - 180, 13,
				ViewConfig.COL_HEAL if beaten else ViewConfig.COL_TEXT_OFF)
		# The prize, printed on the right edge -- the ladder is the promise.
		var rw: Dictionary = LevelBook.level(n).get("reward", {})
		if rw.has("gear") or rw.has("grenade"):
			draw_string(font, Vector2(r.position.x + 16, r.position.y + 54), LevelBook.reward_label(n),
				HORIZONTAL_ALIGNMENT_RIGHT, SLOT_W - 32, 13, ViewConfig.COL_GOLD)
	var br := _back_rect(vp)
	draw_rect(br, ViewConfig.COL_BTN_HOVER if _hover == 100 else ViewConfig.COL_BTN)
	draw_rect(br, ViewConfig.COL_BOARD_EDGE, false, 2.0)
	draw_string(font, Vector2(br.position.x, br.position.y + 32), "BACK",
		HORIZONTAL_ALIGNMENT_CENTER, br.size.x, 22, ViewConfig.COL_TEXT)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	var vp := get_viewport_rect().size
	if event is InputEventMouseMotion:
		var old := _hover
		var m := get_local_mouse_position()
		_hover = -1
		for i in LevelBook.count():
			if LevelProgress.is_unlocked(i + 1) and _slot_rect(i, vp).has_point(m):
				_hover = i
				break
		if _back_rect(vp).has_point(m):
			_hover = 100
		if old != _hover:
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var m := get_local_mouse_position()
		if _back_rect(vp).has_point(m):
			visible = false
			closed.emit()
			return
		for i in LevelBook.count():
			if LevelProgress.is_unlocked(i + 1) and _slot_rect(i, vp).has_point(m):
				LevelBook.current = i + 1
				get_tree().change_scene_to_file(LEVELS_SCENE)
				return
