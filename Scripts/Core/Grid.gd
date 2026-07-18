# Grid.gd
# Static arena terrain plus pure spatial queries. Holds NO unit state and does
# NO rendering. Combatant positions are passed in when a query needs them.
class_name Grid
extends RefCounted

const SIZE := 8    # 8x8 duel arena (was 12): contact by turn 2-3, zone closes twice
const SHRINK_FLOOR := 4        # the shrinking zone stops here (4x4); never closes past it
const DIRS := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
const ROT_STEPS := 4           # quadrant cycle has 4 orientations; 4 shifts return to start
const GEN_ATTEMPTS := 200      # max arena re-rolls to find a connected layout
const GEN_PLACE_GUARD := 1000  # safety cap on blocker-placement tries per arena

# blocked[y][x] == true means a blocker sits there (breaks LoS and movement).
var blocked: Array = []
var spawn_a: Vector2i
var spawn_b: Vector2i
var base_blocked: Array = []   # canonical layout; rotations derive from this so walls return
var rot_step := 0              # 0-3: how many clockwise quadrant shifts from the canonical layout
var shrink_level := 0          # rings closed by the shrinking zone (0 = full 12x12, 4 = 4x4 floor)

func _init() -> void:
	_clear()

# A fresh SIZE x SIZE grid with no blockers.
func _blank() -> Array:
	var g: Array = []
	for y in range(SIZE):
		var row: Array = []
		for x in range(SIZE):
			row.append(false)
		g.append(row)
	return g

func _clear() -> void:
	blocked = _blank()

func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.x < SIZE and p.y >= 0 and p.y < SIZE

func is_blocked(p: Vector2i) -> bool:
	if not in_bounds(p):
		return true
	return blocked[p.y][p.x]

# Line of sight: any blocker strictly between a and b breaks it. The endpoints
# (the units themselves) never count as blockers.
# NOTE: uses a Bresenham line, which can clip a corner on pure diagonals. Fine
# for a 12x12 board; swap in a supercover walk later if it ever matters.
func has_los(a: Vector2i, b: Vector2i) -> bool:
	for tile in _line(a, b):
		if tile == a or tile == b:
			continue
		if is_blocked(tile):
			return false
	return true

static func dist(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

# Chebyshev (king-move) distance -- the radius an "around" (3x3) blast reaches.
static func cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

# How many complete outer rings are fully walled (the shrinking zone), derived
# from `blocked` so it's right live AND in replays (which restore each turn's
# wall layout). THE zone-ring geometry lives here -- views ask, never re-derive.
# (GDScript-only: Grid.cs deliberately omits generation/rotation/zone -- the
# C# Resolver never reads them.)
func closed_rings() -> int:
	var d := 0
	while d < SIZE / 2:
		var full := true
		for i in range(SIZE):
			if not blocked[d][i] or not blocked[SIZE - 1 - d][i] or not blocked[i][d] or not blocked[i][SIZE - 1 - d]:
				full = false
				break
		if not full:
			return d
		d += 1
	return d

# ── Generation (ruleset 1: 8-10% blockers, spawns must stay connected) ──
func generate(rng: RandomNumberGenerator) -> void:
	var attempts := 0
	while attempts < GEN_ATTEMPTS:
		attempts += 1
		_clear()
		spawn_a = Vector2i(Config.SPAWN_INSET, SIZE / 2)
		spawn_b = Vector2i(SIZE - 1 - Config.SPAWN_INSET, SIZE / 2)
		var target := int(round(SIZE * SIZE * rng.randf_range(Config.BLOCKER_DENSITY_MIN, Config.BLOCKER_DENSITY_MAX)))
		var placed := 0
		var guard := 0
		while placed < target and guard < GEN_PLACE_GUARD:
			guard += 1
			var p := Vector2i(rng.randi() % SIZE, rng.randi() % SIZE)
			if blocked[p.y][p.x] or p == spawn_a or p == spawn_b:
				continue
			blocked[p.y][p.x] = true
			placed += 1
		if _connected(spawn_a, spawn_b):
			base_blocked = _copy(blocked)
			return
	push_warning("Grid.generate: fell back to empty arena after 200 attempts")
	_clear()
	base_blocked = _copy(blocked)

func _connected(start: Vector2i, goal: Vector2i) -> bool:
	var seen := {start: true}
	var queue := [start]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if cur == goal:
			return true
		for d in DIRS:
			var n: Vector2i = cur + d
			if in_bounds(n) and not is_blocked(n) and not seen.has(n):
				seen[n] = true
				queue.append(n)
	return false

# Shift the arena's four quadrants one step clockwise from the CANONICAL layout (so
# walls return over a 4-step cycle, not erode). Fighters do NOT move, so a wall may
# land on an occupant
# -- those tiles are suppressed (cleared) and returned as "crushed". The connecting
# corridor rotates with the walls while the fighters stay put, so they can be
# stranded; we re-verify a path between them and carve one if rotation severed it.
func rotate_blockers(occupants: Array) -> Dictionary:
	rot_step = (rot_step + 1) % ROT_STEPS
	blocked = _cycled(base_blocked, rot_step)
	# Every rotation the zone closes one more ring, down to the SHRINK_FLOOR x SHRINK_FLOOR arena.
	var max_shrink: int = (SIZE - SHRINK_FLOOR) / 2
	if shrink_level < max_shrink:
		shrink_level += 1
	_apply_shrink_rings()   # ring walls override interior walls, so in-ring blockers simply vanish
	var positions: Array = occupants.duplicate()
	var crushed_idx: Array = []
	for i in range(positions.size()):
		var p: Vector2i = positions[i]
		if not in_bounds(p):
			continue
		if _edge_depth(p.x, p.y) < shrink_level:
			# Caught inside the closing zone -> shove to the nearest open live tile, and crush.
			var np := _nearest_open(i, positions)
			if blocked[np.y][np.x]:
				blocked[np.y][np.x] = false   # last resort: nowhere open -> clear a spot to stand
			positions[i] = np
			crushed_idx.append(i)
		elif blocked[p.y][p.x]:
			blocked[p.y][p.x] = false          # an interior wall landed on them -> suppress + crush
			crushed_idx.append(i)
	if positions.size() == 2 and not _connected(positions[0], positions[1]):
		_carve(positions[0], positions[1])
	return {"crushed_idx": crushed_idx, "positions": positions}

# Chebyshev depth of a tile from the nearest board edge (0 = outermost ring).
func _edge_depth(x: int, y: int) -> int:
	return mini(mini(x, y), mini(SIZE - 1 - x, SIZE - 1 - y))

# Close the outer `shrink_level` rings: those tiles become permanent zone walls.
func _apply_shrink_rings() -> void:
	if shrink_level <= 0:
		return
	for y in range(SIZE):
		for x in range(SIZE):
			if _edge_depth(x, y) < shrink_level:
				blocked[y][x] = true

# BFS to the nearest open, unoccupied tile inside the live zone for a shoved fighter.
func _nearest_open(idx: int, occupants: Array) -> Vector2i:
	var start: Vector2i = occupants[idx]
	var seen := {start: true}
	var q: Array = [start]
	while not q.is_empty():
		var cur: Vector2i = q.pop_front()
		if in_bounds(cur) and not blocked[cur.y][cur.x] and not _tile_taken(cur, idx, occupants):
			return cur
		for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0),
				Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
			var np: Vector2i = cur + d
			if in_bounds(np) and not seen.has(np):
				seen[np] = true
				q.append(np)
	return start

func _tile_taken(tile: Vector2i, idx: int, occupants: Array) -> bool:
	for j in range(occupants.size()):
		if j != idx and occupants[j] == tile:
			return true
	return false

# Tiles that are open NOW but become blockers at the next quadrant shift -- the
# telegraph's "incoming walls", so a fighter can step clear before it lands.
func incoming_walls() -> Array:
	var next_layout := _cycled(base_blocked, (rot_step + 1) % ROT_STEPS)
	var out: Array = []
	for y in range(SIZE):
		for x in range(SIZE):
			if next_layout[y][x] and not blocked[y][x]:
				out.append(Vector2i(x, y))
	# Telegraph the next closing ring too, so a fighter can step clear before it seals.
	var max_shrink: int = (SIZE - SHRINK_FLOOR) / 2
	if shrink_level < max_shrink:
		for y in range(SIZE):
			for x in range(SIZE):
				if _edge_depth(x, y) == shrink_level and not blocked[y][x] and not out.has(Vector2i(x, y)):
					out.append(Vector2i(x, y))
	return out

func _copy(src: Array) -> Array:
	var out: Array = []
	for row in src:
		out.append(row.duplicate())
	return out

# A deep copy of the current wall layout, so the replay can record each turn.
func snapshot() -> Array:
	return _copy(blocked)

# Restore a recorded wall layout, so a replayed turn shows the arena as it was
# then (quadrant shifts included), not the final layout.
func restore(layout: Array) -> void:
	if not layout.is_empty():
		blocked = _copy(layout)

func _cycled(base: Array, step: int) -> Array:
	var out: Array = _copy(base)
	for _i in range(step):
		out = _cycle_quadrants_cw(out)
	return out

# One clockwise QUADRANT shift. The board splits into four (SIZE/2 x SIZE/2)
# quadrants; each quadrant's contents move as a block to the next quadrant clockwise
# (top-left -> top-right -> bottom-right -> bottom-left -> top-left). The contents are
# TRANSLATED, not rotated: a tile keeps its position WITHIN its quadrant, so wall
# shapes keep their orientation -- only which quadrant they sit in changes. (A true
# 90 rotation would also turn each shape; this deliberately does not.)
func _cycle_quadrants_cw(src: Array) -> Array:
	var dst := _blank()
	var H := SIZE / 2
	for y in range(SIZE):
		for x in range(SIZE):
			var qx := 0 if x < H else 1     # which quadrant column this tile is in
			var qy := 0 if y < H else 1     # which quadrant row
			var rx := x - qx * H            # position WITHIN the quadrant (preserved)
			var ry := y - qy * H
			var nqx := 1 - qy               # clockwise quadrant move: new quadrant-col
			var nqy := qx                   #                          new quadrant-row
			dst[nqy * H + ry][nqx * H + rx] = src[y][x]
	return dst

# Clear walls along an L-path a->b so the two are reachable again. Operates on the
# derived layout only (canonical is untouched), so it is transient -- the next
# rotation re-derives from base. Only fires when a rotation strands the fighters.
func _carve(a: Vector2i, b: Vector2i) -> void:
	var x := a.x
	var y := a.y
	while x != b.x:
		x += signi(b.x - x)
		blocked[y][x] = false
	while y != b.y:
		y += signi(b.y - y)
		blocked[y][x] = false

func _line(a: Vector2i, b: Vector2i) -> Array:
	var points := []
	var dx := absi(b.x - a.x)
	var dy := absi(b.y - a.y)
	var x := a.x
	var y := a.y
	var sx := 1 if b.x > a.x else -1
	var sy := 1 if b.y > a.y else -1
	var err := dx - dy
	while true:
		points.append(Vector2i(x, y))
		if x == b.x and y == b.y:
			break
		var e2 := 2 * err
		if e2 > -dy:
			err -= dy
			x += sx
		if e2 < dx:
			err += dx
			y += sy
	return points
