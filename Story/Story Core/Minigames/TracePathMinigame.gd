# TracePathMinigame.gd
# Gathering skill game: trace a wavy line from the start circle to the end with the mouse, staying
# on it. Stray too far and you slip. Same contract as GatherMinigame -- start(label, difficulty)
# then `await finished(success)` -- so the gather flow treats them interchangeably.
class_name TracePathMinigame
extends Control

signal finished(success: bool)

var _pts: Array[Vector2] = []
var _idx := 0            # furthest path point reached
var _armed := false      # true once the cursor has touched the start circle
var _done := false
var _ok := false
var _label := ""

const N := 64
const TOL := 22.0        # within this of the line (ahead of you) = on the path, advances progress
const FAIL_R := 34.0     # nearest path point farther than this = you strayed off -> slip
const START_R := 30.0
const LOOKAHEAD := 6     # how far ahead you may progress in one move (stops jumping to the end)

func start(label: String, difficulty: float = 0.5) -> void:
	_label = label
	_build_path(clampf(difficulty, 0.0, 1.0))
	_idx = 0
	_armed = false
	_done = false
	_ok = false
	set_anchors_preset(PRESET_FULL_RECT)
	size = get_viewport_rect().size            # explicit, so it covers the screen even on a CanvasLayer
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = true
	queue_redraw()

func _build_path(diff: float) -> void:
	var vp := get_viewport_rect().size
	var x0 := vp.x * 0.22
	var x1 := vp.x * 0.78
	var cy := vp.y * 0.5
	var amp := lerpf(40.0, 82.0, diff)       # wavier (harder) at higher difficulty
	var f1 := randf_range(1.5, 2.6)
	var f2 := randf_range(3.0, 5.0)
	var ph := randf() * TAU
	var a2 := randf_range(0.30, 0.60)
	_pts = []
	for i in range(N):
		var t := float(i) / float(N - 1)
		var x := lerpf(x0, x1, t)
		var y := cy + amp * (sin(t * PI * f1 + ph) * (1.0 - a2) + sin(t * PI * f2 + ph * 1.7) * a2)
		_pts.append(Vector2(x, y))

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_on_move(get_global_mouse_position())   # global pos matches the drawing coords

func _on_move(m: Vector2) -> void:
	if _done:
		return
	if not _armed:
		if m.distance_to(_pts[0]) < START_R:
			_armed = true
			queue_redraw()
		return
	var last := _pts.size() - 1
	var top := mini(_idx + LOOKAHEAD, last)
	var advanced := _idx
	var nearest := 1.0e9
	for j in range(_idx, top + 1):
		var d := m.distance_to(_pts[j])
		if d < nearest:
			nearest = d
		if d <= TOL and j > advanced:
			advanced = j
	_idx = advanced
	if nearest > FAIL_R:
		_finish(false)                       # strayed off the line
	elif _idx >= last:
		_finish(true)                        # reached the end
	else:
		queue_redraw()

func _finish(ok: bool) -> void:
	_done = true
	_ok = ok
	queue_redraw()
	await get_tree().create_timer(0.6).timeout   # hold the result a beat
	visible = false
	finished.emit(_ok)

func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.55))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(0, vp.y * 0.5 - 122), _label, HORIZONTAL_ALIGNMENT_CENTER, vp.x, 20, ViewConfig.COL_TEXT)
	draw_string(font, Vector2(0, vp.y * 0.5 - 100), "Move the cursor along the line from the circle to the end -- don't stray off",
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, 14, ViewConfig.COL_TEXT_OFF)
	# the path: traced portion green, the rest grey
	for i in range(_pts.size() - 1):
		var col := Color(0.35, 0.80, 0.42) if i < _idx else Color(0.45, 0.47, 0.55)
		draw_line(_pts[i], _pts[i + 1], col, 5.0)
	# start halo (until armed) + start / end dots
	if not _armed:
		draw_circle(_pts[0], START_R, Color(0.95, 0.80, 0.35, 0.30))
	draw_circle(_pts[0], 6.0, Color(0.95, 0.80, 0.35))
	draw_circle(_pts[_pts.size() - 1], 6.0, ViewConfig.COL_GOLD)
	if _done:
		var txt := "Success!" if _ok else "Slipped"
		var c := ViewConfig.COL_GOLD if _ok else ViewConfig.COL_TEXT_OFF
		draw_string(font, Vector2(0, vp.y * 0.5 + 122), txt, HORIZONTAL_ALIGNMENT_CENTER, vp.x, 22, c)
