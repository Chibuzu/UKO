# Grid.gd
# Static arena terrain plus pure spatial queries. Holds NO unit state and does
# NO rendering. Combatant positions are passed in when a query needs them.
class_name Grid
extends RefCounted

const SIZE := 12
const DIRS := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]

# blocked[y][x] == true means a blocker sits there (breaks LoS and movement).
var blocked: Array = []
var spawn_a: Vector2i
var spawn_b: Vector2i

func _init() -> void:
	_clear()

func _clear() -> void:
	blocked = []
	for y in range(SIZE):
		var row := []
		for x in range(SIZE):
			row.append(false)
		blocked.append(row)

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

# ── Generation (ruleset 1: 8-10% blockers, spawns must stay connected) ──
func generate(rng: RandomNumberGenerator) -> void:
	var attempts := 0
	while attempts < 200:
		attempts += 1
		_clear()
		spawn_a = Vector2i(1, SIZE / 2)
		spawn_b = Vector2i(SIZE - 2, SIZE / 2)
		var target := int(round(SIZE * SIZE * rng.randf_range(0.08, 0.10)))
		var placed := 0
		var guard := 0
		while placed < target and guard < 1000:
			guard += 1
			var p := Vector2i(rng.randi() % SIZE, rng.randi() % SIZE)
			if blocked[p.y][p.x] or p == spawn_a or p == spawn_b:
				continue
			blocked[p.y][p.x] = true
			placed += 1
		if _connected(spawn_a, spawn_b):
			return
	push_warning("Grid.generate: fell back to empty arena after 200 attempts")
	_clear()

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
