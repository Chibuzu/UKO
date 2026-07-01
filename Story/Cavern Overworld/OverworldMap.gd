# OverworldMap.gd
# The story zone's WORLD DATA: the 60x60 wall grid plus collision queries. Pure
# data + helpers, no rendering and no actors -- so the map can be generated,
# queried, and (later) saved/streamed independently of who walks on it.
class_name OverworldMap
extends RefCounted

const SIZE := 60
const REST_COUNT := 4            # golden sanctuary tiles: rare, scattered out in the wilds

var blocked: Array = []          # blocked[y][x] == true -> wall
var rest_tiles: Array = []       # Vector2i sanctuary tiles (for drawing + save-independent regen)
var rest_set: Dictionary = {}    # Vector2i -> true, for O(1) "is this a rest tile?" lookups

func generate(seed_value: int) -> void:
	blocked = []
	for y in SIZE:
		var row: Array = []
		for x in SIZE:
			row.append(false)
		blocked.append(row)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value             # same seed -> same zone, so it restores after a duel
	for x in SIZE:
		blocked[0][x] = true
		blocked[SIZE - 1][x] = true
	for y in SIZE:
		blocked[y][0] = true
		blocked[y][SIZE - 1] = true
	var village := Rect2i(SIZE / 2 - 6, SIZE / 2 - 6, 12, 12)   # clear spawn area
	for i in 80:
		var cx := rng.randi_range(2, SIZE - 3)
		var cy := rng.randi_range(2, SIZE - 3)
		if village.has_point(Vector2i(cx, cy)):
			continue
		for j in rng.randi_range(1, 4):
			var bx := clampi(cx + rng.randi_range(-1, 1), 1, SIZE - 2)
			var by := clampi(cy + rng.randi_range(-1, 1), 1, SIZE - 2)
			if not village.has_point(Vector2i(bx, by)):
				blocked[by][bx] = true

	# Golden sanctuary tiles: a rare scattered few, all OUT in the wilds (never in the
	# mob-free village), so mobs can always approach them -- they're a risk/reward rest, not a
	# safe haven. Placed after walls (only open ground); seeded off the map seed so a zone
	# regenerates the same shrines.
	rest_tiles = []
	rest_set = {}
	var rr := RandomNumberGenerator.new()
	rr.seed = seed_value ^ 0x51ED2701
	var tries := 0
	while rest_tiles.size() < REST_COUNT and tries < REST_COUNT * 200:
		tries += 1
		_try_add_rest(Vector2i(rr.randi_range(2, SIZE - 3), rr.randi_range(2, SIZE - 3)))

func _in_village_rect(t: Vector2i) -> bool:
	var c := SIZE / 2
	return absi(t.x - c) <= 6 and absi(t.y - c) <= 6

func _try_add_rest(t: Vector2i) -> void:
	if is_solid(t) or _in_village_rect(t) or rest_set.has(t):
		return
	rest_set[t] = true
	rest_tiles.append(t)

func is_rest(t: Vector2i) -> bool:
	return rest_set.has(t)

func is_solid(t: Vector2i) -> bool:
	if t.x < 0 or t.y < 0 or t.x >= SIZE or t.y >= SIZE:
		return true
	return blocked[t.y][t.x]

func nearest_open(t: Vector2i) -> Vector2i:
	if not is_solid(t):
		return t
	for r in range(1, 8):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var n := Vector2i(clampi(t.x + dx, 1, SIZE - 2), clampi(t.y + dy, 1, SIZE - 2))
				if not is_solid(n):
					return n
	return Vector2i(SIZE / 2, SIZE / 2)
