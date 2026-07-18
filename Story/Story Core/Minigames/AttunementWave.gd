# AttunementWave.gd  (resonance spots)
# Tune three sliders -- frequency, amplitude, phase -- until your wave overlays the faint target
# wave, then LOCK. A live match meter guides you; LOCK only takes when the waves align.
# Contract: start(label, difficulty) + the base finished(quality) (1.0 attuned / 0.0 not).
class_name AttunementWave
extends MinigameOverlay

# slider values 0..1 (player) and the hidden target
var _val := [0.5, 0.5, 0.5]      # freq, amp, phase
var _tgt := [0.5, 0.5, 0.5]
var _drag := -1
var _label := ""
var _need := 0.90               # match required to lock (scaled by difficulty)
var _tracks: Array[Rect2] = []
var _lock_rect := Rect2()
var _leave_rect := Rect2()
var _wave := Rect2()

func start(label: String, difficulty: float = 0.5) -> void:
	_label = label
	_need = lerpf(0.86, 0.94, clampf(difficulty, 0.0, 1.0))
	for i in range(3):
		_tgt[i] = randf_range(0.15, 0.85)
		_val[i] = randf_range(0.15, 0.85)
	_drag = -1
	_open()

func _wave_y(vals: Array, x: float) -> float:
	var freq := lerpf(0.7, 3.2, vals[0])
	var amp := lerpf(0.25, 1.0, vals[1])
	var phase: float = vals[2] * TAU
	return amp * sin(x * TAU * freq + phase)

func _match() -> float:
	var err := 0.0
	for i in range(60):
		var x := float(i) / 59.0
		err += absf(_wave_y(_val, x) - _wave_y(_tgt, x))
	err /= 60.0                       # mean |diff|, roughly 0..2
	return clampf(1.0 - err / 1.4, 0.0, 1.0)

func _input(event: InputEvent) -> void:
	if _done:
		return
	if event is InputEventMouseButton:
		var m := get_global_mouse_position()
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			get_viewport().set_input_as_handled()
			if _lock_rect.has_point(m):
				_finish(1.0 if _match() >= _need else 0.0)
				return
			if _leave_rect.has_point(m):
				_finish(0.0)
				return
			for i in range(_tracks.size()):
				var t := _tracks[i]
				if Rect2(t.position.x - 12, t.position.y - 16, t.size.x + 24, 32).has_point(m):
					_drag = i
					_set_from_mouse(m)
					return
		elif not event.pressed:
			_drag = -1
	elif event is InputEventMouseMotion and _drag >= 0:
		_set_from_mouse(get_global_mouse_position())

func _set_from_mouse(m: Vector2) -> void:
	var t := _tracks[_drag]
	_val[_drag] = clampf((m.x - t.position.x) / t.size.x, 0.0, 1.0)
	queue_redraw()

func _draw() -> void:
	var vp := get_viewport_rect().size
	_dim_backdrop()
	var font := ThemeDB.fallback_font
	var cx := vp.x * 0.5
	draw_string(font, Vector2(0, vp.y * 0.5 - 168), _label, HORIZONTAL_ALIGNMENT_CENTER, vp.x, 20, ViewConfig.COL_TEXT)
	draw_string(font, Vector2(0, vp.y * 0.5 - 146), "Tune the sliders until your wave matches the faint one, then LOCK",
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, 14, ViewConfig.COL_TEXT_OFF)
	# wave display
	_wave = Rect2(cx - 220, vp.y * 0.5 - 118, 440, 96)
	draw_rect(_wave, Color(0.10, 0.11, 0.16))
	draw_rect(_wave, ViewConfig.COL_FRAME, false, 2.0)
	_draw_wave(_tgt, Color(0.55, 0.60, 0.70, 0.7), 2.0)   # target (faint)
	_draw_wave(_val, Color(0.45, 0.85, 0.55), 3.0)        # yours
	# match meter
	var mt := _match()
	var mb := Rect2(cx - 150, _wave.end.y + 14, 300, 12)
	draw_rect(mb, Color(0.16, 0.17, 0.22))
	draw_rect(Rect2(mb.position, Vector2(mb.size.x * mt, mb.size.y)), Color(0.45, 0.85, 0.55) if mt >= _need else Color(0.90, 0.70, 0.35))
	draw_rect(Rect2(mb.position.x + mb.size.x * _need - 1, mb.position.y - 3, 2, mb.size.y + 6), Color(1, 1, 1))   # lock threshold
	# sliders
	var names := ["Frequency", "Amplitude", "Phase"]
	_tracks = []
	var sy := mb.end.y + 34
	for i in range(3):
		var t := Rect2(cx - 150, sy + i * 40, 300, 4)
		_tracks.append(t)
		draw_string(font, Vector2(t.position.x - 96, t.position.y + 6), names[i], HORIZONTAL_ALIGNMENT_LEFT, 90, 13, ViewConfig.COL_TEXT_OFF)
		draw_rect(t, Color(0.30, 0.32, 0.40))
		draw_circle(Vector2(t.position.x + _val[i] * t.size.x, t.position.y + 2), 9.0, Color(0.85, 0.87, 0.95))
	# buttons + result
	var by := sy + 3 * 40 + 8
	_lock_rect = _button(font, cx - 130, by, "LOCK")
	_leave_rect = _button(font, cx + 12, by, "LEAVE")
	if _done:
		var ok := _quality > 0.0
		draw_string(font, Vector2(0, by + 50), "Attuned!" if ok else "Out of tune", HORIZONTAL_ALIGNMENT_CENTER, vp.x,
			22, ViewConfig.COL_GOLD if ok else ViewConfig.COL_TEXT_OFF)

func _draw_wave(vals: Array, col: Color, w: float) -> void:
	var pts: PackedVector2Array = []
	for i in range(80):
		var x := float(i) / 79.0
		var y := _wave_y(vals, x)
		pts.append(Vector2(_wave.position.x + x * _wave.size.x, _wave.get_center().y - y * _wave.size.y * 0.42))
	for i in range(pts.size() - 1):
		draw_line(pts[i], pts[i + 1], col, w)

