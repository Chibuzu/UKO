# CleanCutMinigame.gd  (mushrooms)
# Slice the mushroom along the faint guide line in one smooth motion. Press at the start dot, drag
# along the dashed line to the end, keeping close to it. A big lurch off the line, or lifting the
# button before the end, crushes it. Reports finished(quality) = how cleanly you hugged the line.
class_name CleanCutMinigame
extends Control

signal finished(quality: float)

const ART := "res://Assets/Sprites/Mining/mushroom.png"   # optional; a plain cap is drawn if absent
var _tex: Texture2D = null
var _shroom := Rect2()
var _line: Array[Vector2] = []
var _cutting := false
var _idx := 0
var _dev_sum := 0.0
var _dev_n := 0
var _done := false
var _quality := 0.0
var _label := ""
var _leave_rect := Rect2()

const N := 48
const HUG := 26.0            # within this of the line = advancing
const LURCH := 46.0          # nearest point farther than this = a lurch -> crushed
const CLEAN := 20.0          # mean deviation this small ~ a perfect cut

func start(label: String, difficulty: float = 0.5) -> void:
	_label = label
	if ResourceLoader.exists(ART):
		_tex = load(ART)
	_build(clampf(difficulty, 0.0, 1.0))
	_cutting = false
	_idx = 0
	_dev_sum = 0.0
	_dev_n = 0
	_done = false
	_quality = 0.0
	set_anchors_preset(PRESET_FULL_RECT)
	size = get_viewport_rect().size
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = true
	queue_redraw()

func _build(diff: float) -> void:
	var vp := get_viewport_rect().size
	var s := 224.0
	_shroom = Rect2(vp.x * 0.5 - s * 0.5, vp.y * 0.5 - s * 0.5 + 6, s, s)
	var y0 := _shroom.position.y + s * 0.44
	var amp := lerpf(16.0, 42.0, diff)       # curvier line at higher difficulty
	var f := randf_range(1.0, 1.8)
	var ph := randf() * TAU
	_line = []
	for i in range(N):
		var t := float(i) / float(N - 1)
		var x := lerpf(_shroom.position.x + s * 0.12, _shroom.end.x - s * 0.12, t)
		var y := y0 + amp * sin(t * PI * f + ph)
		_line.append(Vector2(x, y))

func _input(event: InputEvent) -> void:
	if _done:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var m := get_global_mouse_position()
		if event.pressed:
			get_viewport().set_input_as_handled()
			if _leave_rect.has_point(m):
				_finish(0.0)
				return
			if m.distance_to(_line[0]) < 34.0:
				_cutting = true
		elif _cutting:
			if _idx < _line.size() - 4:
				_finish(0.0)                 # lifted before the end -> crushed
			_cutting = false
	elif event is InputEventMouseMotion and _cutting:
		_track(get_global_mouse_position())

func _track(m: Vector2) -> void:
	var last := _line.size() - 1
	var top := mini(_idx + 5, last)
	var adv := _idx
	var near := 1.0e9
	for j in range(_idx, top + 1):
		var d := m.distance_to(_line[j])
		if d < near:
			near = d
		if d <= HUG and j > adv:
			adv = j
	_idx = adv
	_dev_sum += near
	_dev_n += 1
	if near > LURCH:
		_finish(0.0)                          # a lurch off the line -> crushed
	elif _idx >= last:
		var avg := _dev_sum / maxf(1.0, float(_dev_n))
		_finish(clampf(1.0 - avg / CLEAN, 0.0, 1.0))
	else:
		queue_redraw()

func _finish(q: float) -> void:
	_done = true
	_quality = q
	queue_redraw()
	await get_tree().create_timer(0.7).timeout
	visible = false
	finished.emit(_quality)

func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.58))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(0, _shroom.position.y - 46), _label, HORIZONTAL_ALIGNMENT_CENTER, vp.x, 20, ViewConfig.COL_TEXT)
	draw_string(font, Vector2(0, _shroom.position.y - 24), "Press the dot, then drag along the line in one smooth cut",
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, 14, ViewConfig.COL_TEXT_OFF)
	if _tex != null:
		draw_texture_rect(_tex, _shroom, false)
	else:
		draw_rect(Rect2(_shroom.position.x + 40, _shroom.position.y + 40, _shroom.size.x - 80, _shroom.size.y * 0.4), Color(0.90, 0.30, 0.32))
	# guide line (dashed): cut part solid green, the rest faint dashes
	for i in range(_line.size() - 1):
		if i < _idx:
			draw_line(_line[i], _line[i + 1], Color(0.40, 0.85, 0.50), 4.0)
		elif i % 2 == 0:
			draw_line(_line[i], _line[i + 1], Color(0.85, 0.85, 0.92, 0.55), 2.0)
	draw_circle(_line[0], 8.0, Color(0.95, 0.80, 0.35))
	draw_circle(_line[_line.size() - 1], 6.0, ViewConfig.COL_GOLD)
	# buttons + result
	_leave_rect = _button(font, vp.x * 0.5 - 59, _shroom.end.y + 22, "LEAVE")
	if _done:
		var txt := ("Clean slice!" if _quality > 0.85 else ("Decent cut" if _quality > 0.5 else "Ragged cut")) if _quality > 0.0 else "Crushed"
		draw_string(font, Vector2(0, _shroom.end.y + 72), txt, HORIZONTAL_ALIGNMENT_CENTER, vp.x,
			22, ViewConfig.COL_GOLD if _quality > 0.0 else ViewConfig.COL_TEXT_OFF)

func _button(font: Font, x: float, y: float, label: String) -> Rect2:
	var r := Rect2(x, y, 118, 34)
	draw_rect(r, Color(0.20, 0.21, 0.27))
	draw_rect(r, ViewConfig.COL_FRAME, false, 2.0)
	draw_string(font, Vector2(r.position.x, r.position.y + 23), label, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 15, ViewConfig.COL_TEXT)
	return r
