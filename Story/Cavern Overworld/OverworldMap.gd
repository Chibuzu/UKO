# OverworldMap.gd
# The story zone's WORLD DATA: the 60x60 wall grid plus collision queries. Pure
# data + helpers, no rendering and no actors -- so the map can be generated,
# queried, and (later) saved/streamed independently of who walks on it.
class_name OverworldMap
extends RefCounted

const SIZE := 60
const REST_COUNT := 4            # golden sanctuary tiles: rare, scattered out in the wilds
const GEM_COUNT := 16            # purple gemstone nodes: gatherable, scattered out in the wilds

var blocked: Array = []          # blocked[y][x] == true -> wall
var rest_tiles: Array = []       # Vector2i sanctuary tiles (for drawing + save-independent regen)
var rest_set: Dictionary = {}    # Vector2i -> true, for O(1) "is this a rest tile?" lookups
var gem_tiles: Array = []        # Vector2i gemstone nodes (walkable overlay tiles, gatherable)
var gem_set: Dictionary = {}     # Vector2i -> true, for O(1) "is this a gemstone?" lookups

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

	# Gemstone nodes: purple gatherable tiles scattered through the wilds (never in the
	# village, so gathering is a step out into the world). Walkable overlay tiles like the
	# shrines -- not solid walls -- so they don't affect movement or mob pathing. Seeded off
	# the map seed so a zone regenerates the same deposits (the controller then subtracts any
	# already gathered from a save).
	gem_tiles = []
	gem_set = {}
	var gr := RandomNumberGenerator.new()
	gr.seed = seed_value ^ 0x2545F491
	var gtries := 0
	while gem_tiles.size() < GEM_COUNT and gtries < GEM_COUNT * 200:
		gtries += 1
		_try_add_gem(Vector2i(gr.randi_range(2, SIZE - 3), gr.randi_range(2, SIZE - 3)))

func _try_add_gem(t: Vector2i) -> void:
	if is_solid(t) or _in_village_rect(t) or gem_set.has(t) or rest_set.has(t):
		return
	gem_set[t] = true
	gem_tiles.append(t)

func is_gem(t: Vector2i) -> bool:
	return gem_set.has(t)

# Gathered -> the node is gone. Mutates the shared set/array IN PLACE so the WorldBoard's
# reference (assigned once) still points at the live data and redraws without it.
func remove_gem(t: Vector2i) -> void:
	if not gem_set.has(t):
		return
	gem_set.erase(t)
	gem_tiles.erase(t)

# Restore the exact set of remaining nodes from a save (in place, so shared refs survive).
func set_gems(tiles: Array) -> void:
	gem_set.clear()
	gem_tiles.clear()
	for e in tiles:
		var t := Vector2i(int(e[0]), int(e[1]))
		gem_set[t] = true
		gem_tiles.append(t)

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
