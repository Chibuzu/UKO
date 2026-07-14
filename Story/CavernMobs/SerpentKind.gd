# SerpentKind.gd
# The two-headed cave boss: a rigid 2-tile body (cells = pos and pos+facing). Both
# cells are HEADS; vertical when facing N/S, horizontal when E/W. It moves ONE tile per
# turn -- straight (keeping its axis) or sideways (a 90-degree turn) -- and strikes one
# tile straight out past each head.
#
# BRAIN: a breadth-first search over (position, facing) states finds the SHORTEST move
# sequence to a state where a strike tile lands on the player, then takes the first move
# of that path. This reaches the player through the cramped cage and lines up strikes
# even in the "one tile off" cases a greedy chase gets stuck on. If the player is
# already threatened it strikes; if no path exists it holds.
class_name SerpentKind
extends MobKind

var tail: Vector2i = Vector2i(-99, -99)
const _MAX_EXPAND := 4000   # BFS safety cap (the cage is small; this is ample)

static func heads(pos: Vector2i, facing: int) -> Array:
	return [pos, pos + Vector2i(Config.FACING_VEC[facing])]

static func strike_tiles(a: Vector2i, b: Vector2i) -> Array:
	var axis := b - a
	return [a - axis, b + axis]

func attack_pattern(origin: Vector2i) -> Array:
	if tail == Vector2i(-99, -99) or tail == origin:
		return cardinal_ring(origin, 1)
	return strike_tiles(origin, tail)

func _is_strike(pos: Vector2i, facing: int, player: Vector2i) -> bool:
	return player in strike_tiles(pos, pos + Vector2i(Config.FACING_VEC[facing]))

# Legal 1-tile moves from a state -> array of {"act":Dictionary, "pos":P, "facing":F}.
func _succ(pos: Vector2i, facing: int, player: Vector2i, grid: Grid) -> Array:
	var axis := Vector2i(Config.FACING_VEC[facing])
	var out: Array = []
	# STRAIGHT one tile either way along the axis.
	for s: int in [1, -1]:
		var np: Vector2i = pos + axis * s
		var nt: Vector2i = np + axis
		if _free(np, grid, player) and _free(nt, grid, player):
			out.append({"act": {"kind": "straight", "pos": np}, "pos": np, "facing": facing})
	# TURN one tile: pivot around a current cell to a perpendicular side.
	var perp := Vector2i(-axis.y, axis.x)
	var tl := pos + axis
	for pivot: Vector2i in [pos, tl]:
		for side: Vector2i in [perp, -perp]:
			var far: Vector2i = pivot + side
			if _free(far, grid, player) and _free(pivot, grid, player):
				var nf: int = _face_of(far - pivot)
				out.append({"act": {"kind": "turn", "pos": pivot, "facing": nf}, "pos": pivot, "facing": nf})
	return out

func plan_move(pos: Vector2i, facing: int, player: Vector2i, grid: Grid) -> Dictionary:
	tail = pos + Vector2i(Config.FACING_VEC[facing])
	if _is_strike(pos, facing, player):
		return {"kind": "strike"}
	# BFS over (pos, facing); remember the FIRST action that led to each state.
	var seen := {}
	seen[[pos, facing]] = true
	var queue: Array = []
	var first := {}
	for nb in _succ(pos, facing, player, grid):
		var key := [nb["pos"], nb["facing"]]
		if not seen.has(key):
			seen[key] = true
			first[key] = nb["act"]
			queue.append(key)
	var expanded := 0
	while not queue.is_empty() and expanded < _MAX_EXPAND:
		var st: Array = queue.pop_front()
		expanded += 1
		if _is_strike(st[0], st[1], player):
			return first[st]
		for nb in _succ(st[0], st[1], player, grid):
			var key2 := [nb["pos"], nb["facing"]]
			if not seen.has(key2):
				seen[key2] = true
				first[key2] = first[st]
				queue.append(key2)
	return {"kind": "hold"}

func _free(t: Vector2i, grid: Grid, player: Vector2i) -> bool:
	return not grid.is_blocked(t) and t != player

func _face_of(d: Vector2i) -> int:
	if absi(d.x) >= absi(d.y):
		return Config.Facing.EAST if d.x >= 0 else Config.Facing.WEST
	return Config.Facing.SOUTH if d.y >= 0 else Config.Facing.NORTH

func plan(mob: Combatant, player: Combatant, grid: Grid) -> Array:
	return []
