# OverworldMap.gd
# The story zone's WORLD DATA: the 60x60 wall grid plus collision queries. Pure
# data + helpers, no rendering and no actors -- so the map can be generated,
# queried, and (later) saved/streamed independently of who walks on it.
class_name OverworldMap
extends RefCounted

const SIZE := 60
const REST_COUNT := 4            # golden sanctuary tiles: rare, scattered out in the wilds
const GEM_COUNT := 16            # purple gemstone nodes: gatherable, scattered out in the wilds
const MUSHROOM_COUNT := 8        # rare mushrooms: only a handful in the whole map
const BORDER := 1                # the outer ring of tiles is always wall

# ── The BOSS PORTAL (Fra): a purple pad set INTO the right border wall. Stepping
# on it hands you to a SEPARATE small arena map (StoryController owns the world
# swap); the world map contains no boss room, and the boss spawns only there.
const BOSS_DOOR := Vector2i(59, 30)     # the purple portal, set INTO the right border wall itself

# The spawn VILLAGE: the mob-free safe zone at world center. This is a FOUNDING BLOCK -- one
# definition that world-gen, tile scatter, mob roaming, NPC placement and the controller all
# read, so the safe zone can never drift between hand-copied bounds. VILLAGE_RADIUS is kept
# separate from the view window (ViewConfig.VIEW_TILES) on purpose: they're equal today but
# conceptually independent, and coupling them would let a window resize silently move the zone.
const VILLAGE_RADIUS := 6

var blocked: Array = []          # blocked[y][x] == true -> wall
var rest_tiles: Array = []       # Vector2i sanctuary tiles (for drawing + save-independent regen)
var rest_set: Dictionary = {}    # Vector2i -> true, for O(1) "is this a rest tile?" lookups
var gem_tiles: Array = []        # Vector2i gemstone nodes (walkable overlay tiles, gatherable)
var gem_set: Dictionary = {}     # Vector2i -> true, for O(1) "is this a gemstone?" lookups
var mushroom_tiles: Array = []   # Vector2i mushroom nodes (rare, gatherable)
var mushroom_set: Dictionary = {}
var building_set: Dictionary = {}   # Vector2i -> true: village building footprints (solid; drawn as sprites)

# ── village (single source of truth) ──────────────────────────────────────────
# Static: depends only on SIZE. If the village ever moves at runtime, promote these to
# instance state (a stored center/radius) -- every caller already goes through them, so that
# change stays local to this file.
static func village_center() -> Vector2i:
	return Vector2i(9, 50)   # bottom-left corner of the world

static func in_village(t: Vector2i) -> bool:
	var c := village_center()
	return absi(t.x - c.x) <= VILLAGE_RADIUS and absi(t.y - c.y) <= VILLAGE_RADIUS

# Building layout (single source of truth for placement + collision + rendering). Houses are
# 1x2, the well 2x2, the market 2x1 (its 1x2 sprite rotated 90 to sit horizontal), player home
# 1x1. Two rows of three houses with the well centred between them; market middle-left; the
# player's home set a bit apart. One empty tile between neighbours.
static func village_buildings() -> Array:
	return [
		# top row: 5 houses (2 extra: one further left, one further right)
		{"kind": "house", "tile": Vector2i(5, 44), "w": 1, "h": 2, "variant": 0},
		{"kind": "house", "tile": Vector2i(7, 44), "w": 1, "h": 2, "variant": 1},
		{"kind": "house", "tile": Vector2i(9, 44), "w": 1, "h": 2, "variant": 2},
		{"kind": "house", "tile": Vector2i(11, 44), "w": 1, "h": 2, "variant": 0},
		{"kind": "house", "tile": Vector2i(13, 44), "w": 1, "h": 2, "variant": 1},
		{"kind": "well",   "tile": Vector2i(8, 48), "w": 2, "h": 2, "variant": 0},
		# bottom row: 5 houses
		{"kind": "house", "tile": Vector2i(5, 52), "w": 1, "h": 2, "variant": 2},
		{"kind": "house", "tile": Vector2i(7, 52), "w": 1, "h": 2, "variant": 0},
		{"kind": "house", "tile": Vector2i(9, 52), "w": 1, "h": 2, "variant": 1},
		{"kind": "house", "tile": Vector2i(11, 52), "w": 1, "h": 2, "variant": 2},
		{"kind": "house", "tile": Vector2i(13, 52), "w": 1, "h": 2, "variant": 0},
		{"kind": "market", "tile": Vector2i(3, 48), "w": 2, "h": 1, "variant": 0},
		{"kind": "player_home", "tile": Vector2i(15, 55), "w": 1, "h": 1, "variant": 0},
	]

# The conveyor line: from just above the market straight up to the northern edge (the main
# city, built later, will hook onto the top). These tiles are kept clear (walkable belt).
static func transport_tiles() -> Array:
	var out: Array = []
	for y in range(1, 48):
		out.append(Vector2i(3, y))
	return out

# ── generation ────────────────────────────────────────────────────────────────
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
	for i in 80:
		var cx := rng.randi_range(2, SIZE - 3)
		var cy := rng.randi_range(2, SIZE - 3)
		if in_village(Vector2i(cx, cy)):
			continue
		for j in rng.randi_range(1, 4):
			var bx := clampi(cx + rng.randi_range(-1, 1), BORDER, SIZE - 1 - BORDER)
			var by := clampi(cy + rng.randi_range(-1, 1), BORDER, SIZE - 1 - BORDER)
			if not in_village(Vector2i(bx, by)):
				blocked[by][bx] = true

	# Village buildings are solid: their footprints become walls so you can't walk through them.
	building_set = {}
	for b in village_buildings():
		for dx in range(int(b["w"])):
			for dy in range(int(b["h"])):
				var bt: Vector2i = b["tile"] + Vector2i(dx, dy)
				if bt.x >= 0 and bt.y >= 0 and bt.x < SIZE and bt.y < SIZE:
					blocked[bt.y][bt.x] = true
					building_set[bt] = true
	# The transport belt is a clear, walkable corridor from the market up to the north edge.
	for tt in transport_tiles():
		if tt.x > 0 and tt.y > 0 and tt.x < SIZE - 1 and tt.y < SIZE - 1:
			blocked[tt.y][tt.x] = false

	# BOSS PORTAL: the arena is its OWN small map (StoryController swaps worlds), so
	# nothing is carved here -- just the purple pad set into the border + its approach.
	blocked[BOSS_DOOR.y][BOSS_DOOR.x] = false       # the portal pad is steppable
	blocked[BOSS_DOOR.y][BOSS_DOOR.x - 1] = false   # guarantee a walkable approach

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
		_try_add_rest(_random_inner_tile(rr))

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
		_try_add_gem(_random_inner_tile(gr))

	# Mushrooms: rare gatherable nodes -- only MUSHROOM_COUNT in the whole map. Same wilderness
	# scatter as gems (never in the village), seeded off the map seed so a zone is consistent.
	mushroom_tiles = []
	mushroom_set = {}
	var mr := RandomNumberGenerator.new()
	mr.seed = seed_value ^ 0x1B873593
	var mtries := 0
	while mushroom_tiles.size() < MUSHROOM_COUNT and mtries < MUSHROOM_COUNT * 400:
		mtries += 1
		_try_add_mushroom(_random_inner_tile(mr))

# A random open-range tile inside the playable border (never the outer wall ring). One helper
# so every scatter pass draws from the same coordinate range.
func _random_inner_tile(rng: RandomNumberGenerator) -> Vector2i:
	return Vector2i(rng.randi_range(BORDER + 1, SIZE - 2 - BORDER), rng.randi_range(BORDER + 1, SIZE - 2 - BORDER))

# ── gemstone nodes ────────────────────────────────────────────────────────────
func _try_add_gem(t: Vector2i) -> void:
	if is_solid(t) or in_village(t) or gem_set.has(t) or rest_set.has(t):
		return
	gem_set[t] = true
	gem_tiles.append(t)

func is_gem(t: Vector2i) -> bool:
	return gem_set.has(t)

# ── mushrooms (rare gatherables) ──────────────────────────────────────────────
func _try_add_mushroom(t: Vector2i) -> void:
	if is_solid(t) or in_village(t) or gem_set.has(t) or rest_set.has(t) or mushroom_set.has(t):
		return
	mushroom_set[t] = true
	mushroom_tiles.append(t)

func is_mushroom(t: Vector2i) -> bool:
	return mushroom_set.has(t)

func remove_mushroom(t: Vector2i) -> void:
	mushroom_set.erase(t)
	mushroom_tiles.erase(t)

# Scatter `count` MORE mushrooms (used by the night refresh).
func add_mushrooms(rng: RandomNumberGenerator, count: int) -> void:
	var target := mushroom_tiles.size() + count
	var tries := 0
	while mushroom_tiles.size() < target and tries < count * 400:
		tries += 1
		_try_add_mushroom(_random_inner_tile(rng))

func is_building(t: Vector2i) -> bool:
	return building_set.has(t)

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

# ── sanctuary (rest) tiles ────────────────────────────────────────────────────
func _try_add_rest(t: Vector2i) -> void:
	if is_solid(t) or in_village(t) or rest_set.has(t):
		return
	rest_set[t] = true
	rest_tiles.append(t)

func is_rest(t: Vector2i) -> bool:
	return rest_set.has(t)

# ── collision ─────────────────────────────────────────────────────────────────
func is_solid(t: Vector2i) -> bool:
	if t.x < 0 or t.y < 0 or t.x >= SIZE or t.y >= SIZE:
		return true
	return blocked[t.y][t.x]

# ── day/night refresh ─────────────────────────────────────────────────────────
# Re-scatter the interior walls ("blockers move"). Border, village footprints and the belt are
# preserved; gems, rest tiles, and the keep_clear tiles (+ their neighbours) stay open so nobody
# gets walled in. Caller rebuilds the grid + redraws afterwards.
func reseed_walls(rng: RandomNumberGenerator, keep_clear: Dictionary) -> void:
	var protect := {}
	for t in keep_clear:
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				protect[t + Vector2i(dx, dy)] = true
	blocked = []
	for y in SIZE:
		var row: Array = []
		for x in SIZE:
			row.append(false)
		blocked.append(row)
	for x in SIZE:
		blocked[0][x] = true
		blocked[SIZE - 1][x] = true
	for y in SIZE:
		blocked[y][0] = true
		blocked[y][SIZE - 1] = true
	for i in 80:
		var cx := rng.randi_range(2, SIZE - 3)
		var cy := rng.randi_range(2, SIZE - 3)
		if in_village(Vector2i(cx, cy)):
			continue
		for j in rng.randi_range(1, 4):
			var bx := clampi(cx + rng.randi_range(-1, 1), BORDER, SIZE - 1 - BORDER)
			var by := clampi(cy + rng.randi_range(-1, 1), BORDER, SIZE - 1 - BORDER)
			var bt := Vector2i(bx, by)
			if in_village(bt) or protect.has(bt) or gem_set.has(bt) or rest_set.has(bt):
				continue
			blocked[by][bx] = true
	for b in village_buildings():
		for dx in range(int(b["w"])):
			for dy in range(int(b["h"])):
				var vt: Vector2i = b["tile"] + Vector2i(dx, dy)
				if vt.x >= 0 and vt.y >= 0 and vt.x < SIZE and vt.y < SIZE:
					blocked[vt.y][vt.x] = true
	for tt in transport_tiles():
		if tt.x > 0 and tt.y > 0 and tt.x < SIZE - 1 and tt.y < SIZE - 1:
			blocked[tt.y][tt.x] = false

# Scatter `count` MORE resonance spots (golden rest tiles) onto open wilderness ground.
func add_rest(rng: RandomNumberGenerator, count: int) -> void:
	var target := rest_tiles.size() + count
	var tries := 0
	while rest_tiles.size() < target and tries < count * 200:
		tries += 1
		_try_add_rest(_random_inner_tile(rng))

# Scatter `count` MORE gemstone nodes onto open wilderness ground.
func add_gems(rng: RandomNumberGenerator, count: int) -> void:
	var target := gem_tiles.size() + count
	var tries := 0
	while gem_tiles.size() < target and tries < count * 200:
		tries += 1
		_try_add_gem(_random_inner_tile(rng))

func nearest_open(t: Vector2i) -> Vector2i:
	if not is_solid(t):
		return t
	for r in range(1, 8):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var n := Vector2i(clampi(t.x + dx, BORDER, SIZE - 1 - BORDER), clampi(t.y + dy, BORDER, SIZE - 1 - BORDER))
				if not is_solid(n):
					return n
	return village_center()
