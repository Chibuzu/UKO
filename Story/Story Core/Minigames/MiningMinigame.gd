# MiningMinigame.gd  (gemstones)
# Chip the rock without shattering the embedded gem. Each strike is aim + force: press a fracture
# spot, HOLD to charge the force meter, RELEASE to strike. Every spot shows its needed force (green)
# and a danger line (red) -- spots near the gem need a gentle tap and crack it if you overswing.
# Clear all spots before the gem's integrity breaks. Reports finished(quality) = integrity left.
class_name MiningMinigame
extends Control

signal finished(quality: float)

const ART := "res://Assets/Sprites/Mining/rock_gem.png"   # optional; a plain rock is drawn if absent
var _tex: Texture2D = null
var _rock := Rect2()
var _gem := Vector2()
var _spots: Array = []        # [{pos, target, danger, prox, cleared}]
var _integrity := 1.0
var _aim := -1
var _charging := false
var _force := 0.0
var _done := false
var _quality := 0.0
var _label := ""
var _meter := Rect2()
var _leave_rect := Rect2()

const CHARGE := 1.1           # seconds to fill the meter to full

func start(label: String, difficulty: float = 0.5) -> void:
	_label = label
	if ResourceLoader.exists(ART):
		_tex = load(ART)
	_integrity = 1.0
	_done = false
	_aim = -1
	_charging = false
	_force = 0.0
	set_anchors_preset(PRESET_FULL_RECT)
	size = get_viewport_rect().size
	mouse_filter = Control.MOUSE_FILTER_STOP
	_layout(clampf(difficulty, 0.0, 1.0))
	visible = true
	set_process(true)
	queue_redraw()

func _layout(diff: float) -> void:
	var vp := get_viewport_rect().size
	var rs := 210.0
	_rock = Rect2(vp.x * 0.5 - rs * 0.5 - 46, vp.y * 0.5 - rs * 0.5 + 6, rs, rs)
	_gem = _rock.get_center()
	_meter = Rect2(_rock.end.x + 46, _rock.position.y + 16, 28, rs - 32)
	_spots = []
	var n := 4 + int(diff * 3.0)             # 4..7 spots
	for i in range(n):
		var ang := TAU * float(i) / float(n) + randf() * 0.5
		var rad := randf_range(rs * 0.26, rs * 0.44)
		var pos := _gem + Vector2(cos(ang), sin(ang)) * rad
		var prox := clampf(1.0 - rad / (rs * 0.44), 0.0, 1.0)   # 1 = right by the gem
		var target := lerpf(0.72, 0.36, prox)                   # near the gem -> gentle
		var danger := target + lerpf(0.26, 0.12, prox)          # near the gem -> tighter window
		_spots.append({"pos": pos, "target": target, "danger": danger, "prox": prox, "cleared": false})

func _spot_at(m: Vector2) -> int:
	for i in range(_spots.size()):
		if not _spots[i]["cleared"] and m.distance_to(_spots[i]["pos"]) <= 18.0:
			return i
	return -1

func _all_cleared() -> bool:
	for s in _spots:
		if not s["cleared"]:
			return false
	return true

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
			var s := _spot_at(m)
			if s != -1:
				_aim = s
				_charging = true
				_force = 0.0
		elif _charging:
			_strike()
			_charging = false

func _process(delta: float) -> void:
	if _charging and not _done:
		_force = minf(_force + delta / CHARGE, 1.2)   # allow overshoot past 1.0
		queue_redraw()

func _strike() -> void:
	if _aim < 0:
		return
	var sp: Dictionary = _spots[_aim]
	if _force >= float(sp["target"]) - 0.10:          # enough force to chip it
		sp["cleared"] = true
		if _force > float(sp["danger"]):               # overswing -> crack the gem
			var over := _force - float(sp["danger"])
			_integrity = maxf(0.0, _integrity - over * lerpf(1.1, 2.4, float(sp["prox"])))
	_aim = -1
	_force = 0.0
	if _integrity <= 0.0:
		_finish(0.0)
	elif _all_cleared():
		_finish(_integrity)                            # quality = how intact the gem is
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
	draw_string(font, Vector2(0, _rock.position.y - 64), _label, HORIZONTAL_ALIGNMENT_CENTER, vp.x, 20, ViewConfig.COL_TEXT)
	draw_string(font, Vector2(0, _rock.position.y - 42), "Aim a spot, HOLD to build force, RELEASE -- ease off near the gem",
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, 14, ViewConfig.COL_TEXT_OFF)
	# rock (art if present, else a plain faceted stand-in)
	if _tex != null:
		draw_texture_rect(_tex, _rock, false)
	else:
		draw_rect(_rock.grow(-14), Color(0.63, 0.56, 0.69))
		draw_rect(Rect2(_gem.x - 20, _gem.y - 20, 40, 40), Color(0.50, 0.38, 0.72))
	# integrity bar
	var ib := Rect2(_rock.position.x, _rock.position.y - 22, _rock.size.x, 10)
	draw_rect(ib, Color(0.16, 0.17, 0.22))
	draw_rect(Rect2(ib.position, Vector2(ib.size.x * _integrity, ib.size.y)),
		Color(0.55, 0.42, 0.90) if _integrity > 0.35 else Color(0.90, 0.35, 0.38))
	# spots
	for i in range(_spots.size()):
		var s: Dictionary = _spots[i]
		if s["cleared"]:
			continue
		var aimed: bool = i == _aim
		draw_arc(s["pos"], 10.0, 0, TAU, 20, Color(1, 1, 1) if aimed else Color(0.85, 0.80, 0.55), 2.0)
		draw_line(s["pos"] + Vector2(-5, 0), s["pos"] + Vector2(5, 0), Color(0.9, 0.85, 0.6), 2.0)
		draw_line(s["pos"] + Vector2(0, -5), s["pos"] + Vector2(0, 5), Color(0.9, 0.85, 0.6), 2.0)
	# force meter (with the aimed spot's target + danger markers)
	draw_rect(_meter, Color(0.14, 0.15, 0.20))
	draw_rect(_meter, ViewConfig.COL_FRAME, false, 2.0)
	var fh := clampf(_force / 1.2, 0.0, 1.0) * _meter.size.y
	draw_rect(Rect2(_meter.position.x, _meter.end.y - fh, _meter.size.x, fh), Color(0.90, 0.70, 0.35))
	if _aim >= 0:
		var sp: Dictionary = _spots[_aim]
		var ty := _meter.end.y - float(sp["target"]) / 1.2 * _meter.size.y
		var dy := _meter.end.y - float(sp["danger"]) / 1.2 * _meter.size.y
		draw_line(Vector2(_meter.position.x - 4, ty), Vector2(_meter.end.x + 4, ty), Color(0.45, 0.85, 0.52), 2.0)
		draw_line(Vector2(_meter.position.x - 4, dy), Vector2(_meter.end.x + 4, dy), Color(0.90, 0.35, 0.38), 2.0)
	# buttons + result
	_leave_rect = _button(font, vp.x * 0.5 - 59, _rock.end.y + 30, "LEAVE")
	if _done:
		var txt := ("Prized gem!" if _quality > 0.85 else ("Good haul" if _quality > 0.5 else "Chipped through")) if _quality > 0.0 else "Shattered"
		draw_string(font, Vector2(0, _rock.end.y + 80), txt, HORIZONTAL_ALIGNMENT_CENTER, vp.x,
			22, ViewConfig.COL_GOLD if _quality > 0.0 else ViewConfig.COL_TEXT_OFF)

func _button(font: Font, x: float, y: float, label: String) -> Rect2:
	var r := Rect2(x, y, 118, 34)
	draw_rect(r, Color(0.20, 0.21, 0.27))
	draw_rect(r, ViewConfig.COL_FRAME, false, 2.0)
	draw_string(font, Vector2(r.position.x, r.position.y + 23), label, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 15, ViewConfig.COL_TEXT)
	return r
