# VeinDeduction.gd  (gemstones)
# A Mastermind puzzle: a hidden code of coloured facets. Click a slot to cycle its colour, CHECK
# to guess. Feedback pegs = filled (right colour, right slot) + hollow (right colour, wrong slot).
# Crack it within the guess limit. Contract: start(label, difficulty) + finished(success).
class_name VeinDeduction
extends Control

signal finished(success: bool)

const PALETTE := [
	Color(0.90, 0.35, 0.38), Color(0.40, 0.70, 0.95), Color(0.45, 0.85, 0.52),
	Color(0.95, 0.80, 0.35), Color(0.75, 0.50, 0.92), Color(0.95, 0.60, 0.30),
]
var _slots := 4
var _colors := 5
var _max_guesses := 8
var _code: Array[int] = []
var _guess: Array[int] = []
var _history: Array = []      # [{guess:[...], exact:int, partial:int}]
var _done := false
var _ok := false
var _label := ""
var _slot_rects: Array[Rect2] = []
var _check_rect := Rect2()
var _leave_rect := Rect2()

const SW := 40.0             # swatch size
const SGAP := 10.0

func start(label: String, difficulty: float = 0.5) -> void:
	_label = label
	_slots = 4
	_colors = 5 if difficulty < 0.7 else 6
	_max_guesses = 9
	_code = []
	for i in _slots:
		_code.append(randi() % _colors)
	_guess = []
	for i in _slots:
		_guess.append(0)
	_history = []
	_done = false
	_ok = false
	set_anchors_preset(PRESET_FULL_RECT)
	size = get_viewport_rect().size
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = true
	queue_redraw()

func _score(g: Array) -> Array:
	var exact := 0
	var cc := {}
	var gc := {}
	for i in range(_slots):
		if g[i] == _code[i]:
			exact += 1
		cc[_code[i]] = int(cc.get(_code[i], 0)) + 1
		gc[g[i]] = int(gc.get(g[i], 0)) + 1
	var match_total := 0
	for col in cc:
		match_total += mini(int(cc[col]), int(gc.get(col, 0)))
	return [exact, match_total - exact]

func _input(event: InputEvent) -> void:
	if _done:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		var m := get_global_mouse_position()
		if _leave_rect.has_point(m):
			_finish(false)
			return
		if _check_rect.has_point(m):
			_submit()
			return
		for i in range(_slot_rects.size()):
			if _slot_rects[i].has_point(m):
				_guess[i] = (_guess[i] + 1) % _colors   # cycle this facet's colour
				queue_redraw()
				return

func _submit() -> void:
	var s := _score(_guess)
	_history.append({"guess": _guess.duplicate(), "exact": s[0], "partial": s[1]})
	if s[0] == _slots:
		_finish(true)
	elif _history.size() >= _max_guesses:
		_finish(false)
	else:
		queue_redraw()

func _finish(ok: bool) -> void:
	_done = true
	_ok = ok
	queue_redraw()
	await get_tree().create_timer(0.7).timeout
	visible = false
	finished.emit(_ok)

func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.58))
	var font := ThemeDB.fallback_font
	var row_w := _slots * (SW + SGAP)
	var ox := vp.x * 0.5 - row_w * 0.5 - 30.0
	var top := vp.y * 0.5 - 190.0
	draw_string(font, Vector2(0, top - 40), _label, HORIZONTAL_ALIGNMENT_CENTER, vp.x, 20, ViewConfig.COL_TEXT)
	draw_string(font, Vector2(0, top - 18), "Deduce the facet code -- click a slot to change its colour",
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, 14, ViewConfig.COL_TEXT_OFF)
	# history
	var y := top
	for h in _history:
		_draw_row(ox, y, h["guess"], h["exact"], h["partial"])
		y += SW + 8.0
	# current editable guess
	y = top + (_max_guesses) * (SW + 8.0) + 14.0
	_slot_rects = []
	for i in range(_slots):
		var r := Rect2(ox + i * (SW + SGAP), y, SW, SW)
		_slot_rects.append(r)
		draw_rect(r, PALETTE[_guess[i]])
		draw_rect(r, ViewConfig.COL_FRAME, false, 2.0)
	# buttons
	_check_rect = _button(font, ox + row_w + 20, y, "CHECK")
	_leave_rect = _button(font, ox + row_w + 20, y + 44, "LEAVE")
	draw_string(font, Vector2(0, y + SW + 30), "Guesses left: %d" % (_max_guesses - _history.size()),
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, 14, ViewConfig.COL_TEXT_OFF)
	if _done:
		var txt := "Cracked!" if _ok else "Lost the vein"
		draw_string(font, Vector2(0, y + SW + 54), txt, HORIZONTAL_ALIGNMENT_CENTER, vp.x,
			22, ViewConfig.COL_GOLD if _ok else ViewConfig.COL_TEXT_OFF)

func _draw_row(ox: float, y: float, g: Array, exact: int, partial: int) -> void:
	for i in range(g.size()):
		var r := Rect2(ox + i * (SW + SGAP), y, SW, SW)
		draw_rect(r, PALETTE[g[i]])
		draw_rect(r, Color(0.1, 0.1, 0.14), false, 1.0)
	# feedback pegs
	var px := ox + _slots * (SW + SGAP) + 6.0
	for k in range(exact):
		draw_circle(Vector2(px + k * 12, y + SW * 0.35), 4.0, Color(0.35, 0.85, 0.42))
	for k in range(partial):
		draw_arc(Vector2(px + (exact + k) * 12, y + SW * 0.65), 4.0, 0, TAU, 12, Color(0.95, 0.80, 0.35), 1.5)

func _button(font: Font, x: float, y: float, label: String) -> Rect2:
	var r := Rect2(x, y, 116, 34)
	draw_rect(r, Color(0.20, 0.21, 0.27))
	draw_rect(r, ViewConfig.COL_FRAME, false, 2.0)
	draw_string(font, Vector2(r.position.x, r.position.y + 23), label, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 15, ViewConfig.COL_TEXT)
	return r
