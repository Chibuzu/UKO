# CleanCutMinigame.gd  (mushrooms) -- ROUTE PLANNING (constrained one-stroke cut)
# Slice through EVERY point in a single drag, moving only along OPEN edges. The board is an irregular
# shape (some points missing) with WALLS blocking some connections (drawn red), so the easy "snake"
# order dead-ends -- you must plan the route. Generated from a real Hamiltonian path (walls never
# sever it) so a solution always exists. Press the glowing start, drag through all; drag back to undo.
# Lift early = ruined. Reports finished(quality).
class_name CleanCutMinigame
extends MinigameOverlay

var _cols := 4
var _rows := 4
var _present: Dictionary = {}     # cell idx -> true
var _pos: Dictionary = {}         # cell idx -> Vector2
var _blocked: Dictionary = {}     # "a-b" (a<b) -> true
var _sol: Array = []
var _path: Array[int] = []
var _start := 0
var _cutting := false
var _backtracks := 0
var _label := ""
var _leave_rect := Rect2()
var _org := Vector2()
const GAP := 78.0

func start(label: String, difficulty: float = 0.5) -> void:
	_label = label
	_cols = 4 + (1 if difficulty >= 0.6 else 0)
	_rows = 4
	_gen(clampf(difficulty, 0.0, 1.0))
	_path = [_start]
	_cutting = false
	_backtracks = 0
	_open()

func _key(a: int, b: int) -> String: return "%d-%d" % [mini(a, b), maxi(a, b)]
func _cx(i: int) -> int: return i % _cols
func _cy(i: int) -> int: return int(i / _cols)

func _grid_nbrs(i: int) -> Array:
	var out: Array = []
	var c := _cx(i)
	var r := _cy(i)
	if c > 0: out.append(i - 1)
	if c < _cols - 1: out.append(i + 1)
	if r > 0: out.append(i - _cols)
	if r < _rows - 1: out.append(i + _cols)
	return out

func _present_nbrs(i: int) -> Array:
	var out: Array = []
	for nb in _grid_nbrs(i):
		if _present.has(nb):
			out.append(nb)
	return out

func _passable(a: int, b: int) -> bool:
	return _present.has(a) and _present.has(b) and _grid_nbrs(a).has(b) and not _blocked.has(_key(a, b))

# ── generation ──
func _gen(diff: float) -> void:
	var total := _cols * _rows
	var target := clampi(int(total * 0.80), 7, total)
	for _attempt in range(120):
		_present = _random_shape(target)
		var p := _ham_shape()
		if not p.is_empty():
			_sol = p
			break
	if _sol.is_empty():                              # fallback: full grid always has a path
		_present = {}
		for i in range(total):
			_present[i] = true
		_sol = _ham_shape()
	# walls: block non-solution edges (keeps the solution path open)
	var sol_edges := {}
	for i in range(_sol.size() - 1):
		sol_edges[_key(_sol[i], _sol[i + 1])] = true
	_blocked = {}
	var block_p := lerpf(0.40, 0.68, diff)
	for a in _present.keys():
		for b in _present_nbrs(a):
			if a < b and not sol_edges.has(_key(a, b)) and randf() < block_p:
				_blocked[_key(a, b)] = true
	_start = _sol[0]
	# layout
	var vp := get_viewport_rect().size
	_org = Vector2(vp.x * 0.5 - (_cols - 1) * GAP * 0.5, vp.y * 0.5 - (_rows - 1) * GAP * 0.5 + 10.0)
	_pos = {}
	for i in _present.keys():
		_pos[i] = _org + Vector2(_cx(i) * GAP, _cy(i) * GAP)

func _random_shape(target: int) -> Dictionary:
	var total := _cols * _rows
	var s := randi() % total
	var chosen := {s: true}
	var frontier: Array = _grid_nbrs(s)
	while chosen.size() < target and not frontier.is_empty():
		var k := randi() % frontier.size()
		var c: int = frontier[k]
		frontier.remove_at(k)
		if chosen.has(c):
			continue
		chosen[c] = true
		for nb in _grid_nbrs(c):
			if not chosen.has(nb):
				frontier.append(nb)
	return chosen

func _ham_shape() -> Array:
	var cells := _present.keys()
	var total := cells.size()
	for _attempt in range(200):
		var s: int = cells[randi() % total]
		var visited := {s: true}
		var path: Array = [s]
		if _dfs(s, visited, path, total):
			return path
	return []

func _dfs(node: int, visited: Dictionary, path: Array, total: int) -> bool:
	if path.size() == total:
		return true
	var nbrs := _present_nbrs(node)
	nbrs.shuffle()
	for nb in nbrs:
		if not visited.has(nb):
			visited[nb] = true
			path.append(nb)
			if _dfs(nb, visited, path, total):
				return true
			path.pop_back()
			visited.erase(nb)
	return false

func _cell_near(m: Vector2) -> int:
	for i in _present.keys():
		if m.distance_to(_pos[i]) <= 22.0:
			return i
	return -1

func _input(event: InputEvent) -> void:
	if _done:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var m := get_global_mouse_position()
		if event.pressed:
			get_viewport().set_input_as_handled()
			if _leave_rect.has_point(m):
				_finish(0.0, 0.6)
				return
			if m.distance_to(_pos[_start]) < 24.0:
				_cutting = true
				_path = [_start]
				queue_redraw()
		elif _cutting:
			_cutting = false
			if _path.size() == _present.size():
				_finish(clampf(1.0 - _backtracks * 0.10, 0.35, 1.0), 0.6)
			else:
				_finish(0.0, 0.6)                     # lifted before finishing -> ruined
	elif event is InputEventMouseMotion and _cutting:
		_drag(get_global_mouse_position())

func _drag(m: Vector2) -> void:
	var hit := _cell_near(m)
	if hit == -1:
		return
	var cur: int = _path[_path.size() - 1]
	if _path.size() >= 2 and hit == _path[_path.size() - 2]:
		_path.pop_back()
		_backtracks += 1
		queue_redraw()
	elif not _path.has(hit) and _passable(cur, hit):
		_path.append(hit)
		if _path.size() == _present.size():
			_finish(clampf(1.0 - _backtracks * 0.10, 0.35, 1.0), 0.6)
		queue_redraw()

func _draw() -> void:
	var vp := get_viewport_rect().size
	_dim_backdrop()
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(0, _org.y - 74), _label, HORIZONTAL_ALIGNMENT_CENTER, vp.x, 20, ViewConfig.COL_TEXT)
	draw_string(font, Vector2(0, _org.y - 50), "One cut through every point. Red walls block the way -- plan your route.",
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, 14, ViewConfig.COL_TEXT_OFF)
	# edges: open (faint) vs walls (red bar across the gap)
	for a in _present.keys():
		for b in _present_nbrs(a):
			if a >= b:
				continue
			var pa: Vector2 = _pos[a]
			var pb: Vector2 = _pos[b]
			if _blocked.has(_key(a, b)):
				var mid := (pa + pb) * 0.5
				var perp := (pb - pa).orthogonal().normalized() * 12.0
				draw_line(mid - perp, mid + perp, Color(0.90, 0.35, 0.38), 3.0)
			else:
				draw_line(pa, pb, Color(0.45, 0.47, 0.56, 0.5), 2.0)
	# the cut so far
	for i in range(_path.size() - 1):
		draw_line(_pos[_path[i]], _pos[_path[i + 1]], Color(0.90, 0.35, 0.38), 6.0)
	# points
	for i in _present.keys():
		var col := Color(0.80, 0.82, 0.90)
		if i == _start:
			col = Color(0.95, 0.80, 0.35)
		elif _path.has(i):
			col = Color(0.95, 0.55, 0.55)
		draw_circle(_pos[i], 8.0, col)
	if _path.size() > 0:
		draw_arc(_pos[_path[_path.size() - 1]], 13.0, 0, TAU, 24, Color(1, 1, 1), 2.0)
	_leave_rect = _button(font, vp.x * 0.5 - 59, _org.y + (_rows - 1) * GAP + 54, "LEAVE")
	if _done:
		var txt := ("Clean slice!" if _quality > 0.85 else ("Decent cut" if _quality > 0.5 else "Ragged cut")) if _quality > 0.0 else "Ruined"
		draw_string(font, Vector2(0, _org.y + (_rows - 1) * GAP + 104), txt, HORIZONTAL_ALIGNMENT_CENTER, vp.x,
			22, ViewConfig.COL_GOLD if _quality > 0.0 else ViewConfig.COL_TEXT_OFF)

