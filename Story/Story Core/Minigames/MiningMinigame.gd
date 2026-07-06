# MiningMinigame.gd  (gemstones) -- DEDUCTION (Minesweeper of the rock)
# The rock hides fragile facets of the gem. LEFT-click a cell to chip it: safe rock reveals a NUMBER
# (how many of its 8 neighbours are fragile); a fragile cell cracks the gem. RIGHT-click flags a cell
# you've deduced is fragile (leave it be). Clear ALL the safe rock to extract the gem. Boards are
# generated to be solvable by pure reasoning from the free opening -- no guessing. Reports
# finished(quality) = gem integrity left (fewer bad chips = better gem).
class_name MiningMinigame
extends Control

signal finished(quality: float)

var _cols := 5
var _rows := 5
var _fragile: Array = []      # bool per cell
var _num: Array = []          # fragile-neighbour count per cell
var _revealed: Array = []
var _flagged: Array = []
var _integrity := 1.0
var _done := false
var _quality := 0.0
var _label := ""
var _cell := 48.0
var _org := Vector2()
var _leave_rect := Rect2()

const HIT := 0.26             # integrity lost per fragile chip

func start(label: String, difficulty: float = 0.5) -> void:
	_label = label
	_cols = 5 + int(difficulty * 2.0)      # 5..7
	_rows = 5
	_integrity = 1.0
	_done = false
	_quality = 0.0
	set_anchors_preset(PRESET_FULL_RECT)
	size = get_viewport_rect().size
	mouse_filter = Control.MOUSE_FILTER_STOP
	_gen(clampf(difficulty, 0.0, 1.0))
	var vp := get_viewport_rect().size
	_org = Vector2(vp.x * 0.5 - _cols * _cell * 0.5, vp.y * 0.5 - _rows * _cell * 0.5 + 6)
	visible = true
	queue_redraw()

# ── geometry ──
func _idx(c: int, r: int) -> int: return r * _cols + c
func _cx(i: int) -> int: return i % _cols
func _cy(i: int) -> int: return int(i / _cols)
func _nbrs(i: int) -> Array:
	var out: Array = []
	var c := _cx(i)
	var r := _cy(i)
	for dr in [-1, 0, 1]:
		for dc in [-1, 0, 1]:
			if dc == 0 and dr == 0:
				continue
			var nc: int = c + dc
			var nr: int = r + dr
			if nc >= 0 and nc < _cols and nr >= 0 and nr < _rows:
				out.append(_idx(nc, nr))
	return out

# ── generation with a deducibility guarantee ──
func _gen(diff: float) -> void:
	var total := _cols * _rows
	var mines := int(total * lerpf(0.19, 0.26, diff))
	for _attempt in range(240):
		_fragile = []
		for i in range(total):
			_fragile.append(false)
		var placed := 0
		while placed < mines:
			var k := randi() % total
			if not _fragile[k]:
				_fragile[k] = true
				placed += 1
		_compute_numbers()
		var opening := _a_zero_cell()
		if opening == -1:
			continue                     # need a free opening (a 0-cell) to start deducing
		if _deducible(opening):
			_revealed = []
			_flagged = []
			for i in range(total):
				_revealed.append(false)
				_flagged.append(false)
			_flood(opening)
			return
	# fallback (rare): use last board + open a zero if any
	_revealed = []
	_flagged = []
	for i in range(total):
		_revealed.append(false)
		_flagged.append(false)
	var o := _a_zero_cell()
	if o != -1:
		_flood(o)

func _compute_numbers() -> void:
	_num = []
	for i in range(_cols * _rows):
		var n := 0
		for nb in _nbrs(i):
			if _fragile[nb]:
				n += 1
		_num.append(n)

func _a_zero_cell() -> int:
	var zeros: Array = []
	for i in range(_cols * _rows):
		if not _fragile[i] and _num[i] == 0:
			zeros.append(i)
	if zeros.is_empty():
		return -1
	return zeros[randi() % zeros.size()]

# Simulate the basic Minesweeper solver from `opening`; true if every safe cell can be deduced.
func _deducible(opening: int) -> bool:
	var rev := {}
	var flg := {}
	_sim_flood(opening, rev)
	var changed := true
	while changed:
		changed = false
		for c in rev.keys():
			var unrev: Array = []
			var flagged := 0
			for nb in _nbrs(c):
				if flg.has(nb):
					flagged += 1
				elif not rev.has(nb):
					unrev.append(nb)
			if unrev.is_empty():
				continue
			if _num[c] == flagged:                       # rest are SAFE
				for u in unrev:
					if _fragile[u]:
						return false
					_sim_flood(u, rev)
					changed = true
			elif _num[c] - flagged == unrev.size():       # rest are FRAGILE
				for u in unrev:
					if not flg.has(u):
						flg[u] = true
						changed = true
	for i in range(_cols * _rows):
		if not _fragile[i] and not rev.has(i):
			return false
	return true

func _sim_flood(c: int, rev: Dictionary) -> void:
	if rev.has(c):
		return
	rev[c] = true
	if _num[c] == 0:
		for nb in _nbrs(c):
			if not _fragile[nb]:
				_sim_flood(nb, rev)

# ── live reveal ──
func _flood(c: int) -> void:
	if _revealed[c] or _flagged[c]:
		return
	_revealed[c] = true
	if _num[c] == 0:
		for nb in _nbrs(c):
			if not _fragile[nb]:
				_flood(nb)

func _won() -> bool:
	for i in range(_cols * _rows):
		if not _fragile[i] and not _revealed[i]:
			return false
	return true

func _cell_at(m: Vector2) -> int:
	var c := int((m.x - _org.x) / _cell)
	var r := int((m.y - _org.y) / _cell)
	if c < 0 or c >= _cols or r < 0 or r >= _rows:
		return -1
	if m.x < _org.x or m.y < _org.y:
		return -1
	return _idx(c, r)

func _input(event: InputEvent) -> void:
	if _done:
		return
	if event is InputEventMouseButton and event.pressed:
		var m := get_global_mouse_position()
		if event.button_index == MOUSE_BUTTON_LEFT and _leave_rect.has_point(m):
			_finish(0.0)
			return
		var i := _cell_at(m)
		if i == -1:
			return
		get_viewport().set_input_as_handled()
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if not _revealed[i]:
				_flagged[i] = not _flagged[i]
				queue_redraw()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _revealed[i] or _flagged[i]:
				return
			if _fragile[i]:
				_revealed[i] = true                       # chipped a fragile facet -> crack
				_integrity = maxf(0.0, _integrity - HIT)
				if _integrity <= 0.0:
					_finish(0.0)
					return
			else:
				_flood(i)
			if _won():
				_finish(_integrity)
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
	draw_string(font, Vector2(0, _org.y - 64), _label, HORIZONTAL_ALIGNMENT_CENTER, vp.x, 20, ViewConfig.COL_TEXT)
	draw_string(font, Vector2(0, _org.y - 42), "Left-click chips rock (number = fragile neighbours). Right-click flags a fragile spot.",
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, 13, ViewConfig.COL_TEXT_OFF)
	# integrity bar
	var ib := Rect2(_org.x, _org.y - 22, _cols * _cell, 10)
	draw_rect(ib, Color(0.16, 0.17, 0.22))
	draw_rect(Rect2(ib.position, Vector2(ib.size.x * _integrity, ib.size.y)),
		Color(0.55, 0.42, 0.90) if _integrity > 0.35 else Color(0.90, 0.35, 0.38))
	# grid
	for i in range(_cols * _rows):
		var r := Rect2(_org.x + _cx(i) * _cell + 2, _org.y + _cy(i) * _cell + 2, _cell - 4, _cell - 4)
		if _revealed[i] and _fragile[i]:
			draw_rect(r, Color(0.50, 0.30, 0.62))
			draw_string(font, Vector2(r.position.x, r.position.y + r.size.y * 0.72), "!", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 20, Color(1, 0.8, 0.85))
		elif _revealed[i]:
			draw_rect(r, Color(0.24, 0.22, 0.30))
			if _num[i] > 0:
				draw_string(font, Vector2(r.position.x, r.position.y + r.size.y * 0.72), str(_num[i]), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 20, _num_color(_num[i]))
		else:
			draw_rect(r, Color(0.60, 0.54, 0.66))       # unchipped rock
			draw_rect(r, Color(0.70, 0.64, 0.76), false, 1.0)
			if _flagged[i]:
				draw_rect(Rect2(r.get_center() - Vector2(6, 6), Vector2(12, 12)), Color(0.90, 0.35, 0.38))
	_leave_rect = _button(font, vp.x * 0.5 - 59, _org.y + _rows * _cell + 16, "LEAVE")
	if _done:
		var txt := ("Prized gem!" if _quality > 0.85 else ("Good haul" if _quality > 0.5 else "Chipped through")) if _quality > 0.0 else "Shattered"
		draw_string(font, Vector2(0, _org.y + _rows * _cell + 66), txt, HORIZONTAL_ALIGNMENT_CENTER, vp.x,
			22, ViewConfig.COL_GOLD if _quality > 0.0 else ViewConfig.COL_TEXT_OFF)

func _num_color(n: int) -> Color:
	match n:
		1: return Color(0.55, 0.80, 0.95)
		2: return Color(0.55, 0.90, 0.55)
		3: return Color(0.95, 0.70, 0.45)
		_: return Color(0.95, 0.55, 0.60)

func _button(font: Font, x: float, y: float, label: String) -> Rect2:
	var r := Rect2(x, y, 118, 34)
	draw_rect(r, Color(0.20, 0.21, 0.27))
	draw_rect(r, ViewConfig.COL_FRAME, false, 2.0)
	draw_string(font, Vector2(r.position.x, r.position.y + 23), label, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 15, ViewConfig.COL_TEXT)
	return r
