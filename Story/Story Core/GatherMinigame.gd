# GatherMinigame.gd
# A small skill overlay that plays when you gather a node. A marker sweeps a bar; click / press
# Space when it's inside the green target zone. Emits `finished(success)`. It's a Control on a
# CanvasLayer, so it draws over the map and eats input while it's up (roam is paused by the caller).
#
# This is deliberately a self-contained "gathering game" you can reskin or swap per resource --
# the caller just does: mg.start("Gathering Mushroom", zone_width); await mg.finished.
class_name GatherMinigame
extends Control

signal finished(success: bool)

var _running := false
var _t := 0.0
var _speed := 1.5
var _marker := 0.0        # 0..1 position along the bar
var _zone_lo := 0.4
var _zone_hi := 0.6
var _label := ""
var _result_shown := false
var _result_ok := false

const BAR_W := 360.0
const BAR_H := 26.0

func start(label: String, zone_width: float = 0.20) -> void:
	_label = label
	var w: float = clampf(zone_width, 0.08, 0.4)
	_zone_lo = randf_range(0.12, 0.88 - w)
	_zone_hi = _zone_lo + w
	_speed = randf_range(1.3, 2.0)
	_t = randf() * 4.0
	_running = true
	_result_shown = false
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	visible = true
	queue_redraw()

func _process(delta: float) -> void:
	if not _running:
		return
	_t += delta * _speed
	_marker = 0.5 + 0.5 * sin(_t * PI)   # smooth back-and-forth sweep, 0..1
	queue_redraw()

func _input(event: InputEvent) -> void:
	if not _running:
		return
	var press := (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
		or (event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER])
	if press:
		get_viewport().set_input_as_handled()
		await _resolve()

func _resolve() -> void:
	_running = false
	_result_ok = _marker >= _zone_lo and _marker <= _zone_hi
	_result_shown = true
	queue_redraw()
	await get_tree().create_timer(0.6).timeout   # hold the result a beat
	visible = false
	finished.emit(_result_ok)

func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.55))          # dim the map
	var bx := vp.x * 0.5 - BAR_W * 0.5
	var by := vp.y * 0.5 - BAR_H * 0.5
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(0, by - 46), _label, HORIZONTAL_ALIGNMENT_CENTER, vp.x, 20, ViewConfig.COL_TEXT)
	draw_string(font, Vector2(0, by - 22), "Stop in the green — click or Space",
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, 14, ViewConfig.COL_TEXT_OFF)
	# bar track
	draw_rect(Rect2(bx, by, BAR_W, BAR_H), Color(0.16, 0.17, 0.22))
	draw_rect(Rect2(bx, by, BAR_W, BAR_H), ViewConfig.COL_FRAME, false, 2.0)
	# target zone
	var zx := bx + _zone_lo * BAR_W
	var zw := (_zone_hi - _zone_lo) * BAR_W
	draw_rect(Rect2(zx, by, zw, BAR_H), Color(0.35, 0.80, 0.42, 0.85))
	# marker
	var mx := bx + _marker * BAR_W
	draw_rect(Rect2(mx - 2, by - 5, 4, BAR_H + 10), Color(1, 1, 1))
	# result
	if _result_shown:
		var txt := "Success!" if _result_ok else "Missed"
		var col := ViewConfig.COL_GOLD if _result_ok else ViewConfig.COL_TEXT_OFF
		draw_string(font, Vector2(0, by + BAR_H + 34), txt, HORIZONTAL_ALIGNMENT_CENTER, vp.x, 22, col)
