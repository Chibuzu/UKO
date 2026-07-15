# SerpentKind.gd  --  clean rewrite (the definitive serpent).
#
# A specular two-headed boss: a rigid 2-tile body. The two cells (X1, X2) are the
# combatant's `pos` and `pos + facing` -- deterministic, never drifts. Both cells are
# HEADS. The body is VERTICAL when facing N/S, HORIZONTAL when facing E/W.
#
# MOVES (one tile per turn):
#   STRAIGHT -- shift the whole body one tile along its axis (either direction).
#   SIDEWAYS -- a 90-degree TURN: pivot around one cell so the body ends perpendicular
#               (e.g. vertical (3,3)-(3,2) turning right-low ends horizontal (3,2)-(4,2),
#               cornering around the shared (3,2) tile).
#
# STRIKE -- 1-tile melee from BOTH heads: the tile straight out past each head, along
#           the body line. Vertical (3,3)-(3,2) threatens (3,4) and (3,1).
#
# BRAIN -- a breadth-first search over (pos, facing) states finds the SHORTEST sequence
#          of moves to a state that threatens the player, then takes its first move.
#          Never steps onto the player. Strikes the moment the player is threatened.
#
# The controller executes the descriptor plan_move() returns (a rigid 2-tile turn is
# not expressible as the engine's single-cell move), and renders the body on exactly
# the two occupied tiles -- so hit-detection and the sprite always agree.
class_name SerpentKind
extends MobKind

var tail: Vector2i = Vector2i(-99, -99)   # the body's second cell (pos + facing); set per-turn
const _MAX_EXPAND := 4000                 # BFS safety cap (the cage is tiny; ample)

# ── body geometry ─────────────────────────────────────────────────────────────
static func other_head(pos: Vector2i, facing: int) -> Vector2i:
	return pos + Vector2i(Config.FACING_VEC[facing])

static func body_cells(pos: Vector2i, facing: int) -> Array:
	return [pos, other_head(pos, facing)]

# One tile straight out past each head, extending the body line.
static func strike_tiles(a: Vector2i, b: Vector2i) -> Array:
	var axis := b - a
	return [a - axis, b + axis]

func attack_pattern(origin: Vector2i) -> Array:
	if tail == Vector2i(-99, -99) or tail == origin:
		return cardinal_ring(origin, 1)
	return strike_tiles(origin, tail)

# ── the brain ─────────────────────────────────────────────────────────────────
func plan_move(pos: Vector2i, facing: int, player: Vector2i, grid: Grid) -> Dictionary:
	tail = other_head(pos, facing)
	if _threatens(pos, facing, player):
		return {"kind": "strike"}
	# BFS: shortest path (in 1-tile moves) to any state that threatens the player.
	var seen := {}
	seen[_key(pos, facing)] = true
	var queue: Array = []
	var first := {}
	for nb in _successors(pos, facing, player, grid):
		var k: int = _key(nb["pos"], nb["facing"])
		if not seen.has(k):
			seen[k] = true
			first[k] = nb["act"]
			queue.append(nb)
	var expanded := 0
	while not queue.is_empty() and expanded < _MAX_EXPAND:
		var cur: Dictionary = queue.pop_front()
		expanded += 1
		if _threatens(cur["pos"], cur["facing"], player):
			return first[_key(cur["pos"], cur["facing"])]
		for nb in _successors(cur["pos"], cur["facing"], player, grid):
			var k2: int = _key(nb["pos"], nb["facing"])
			if not seen.has(k2):
				seen[k2] = true
				first[k2] = first[_key(cur["pos"], cur["facing"])]
				queue.append(nb)
	return {"kind": "hold"}

func _threatens(pos: Vector2i, facing: int, player: Vector2i) -> bool:
	return player in strike_tiles(pos, other_head(pos, facing))

# All legal 1-tile end-states -> [{"act":descriptor, "pos":P, "facing":F}].
func _successors(pos: Vector2i, facing: int, player: Vector2i, grid: Grid) -> Array:
	var axis := Vector2i(Config.FACING_VEC[facing])
	var out: Array = []
	# STRAIGHT: shift 1 tile along the axis, either direction. Both cells must be clear.
	for s: int in [1, -1]:
		var np: Vector2i = pos + axis * s
		var nt: Vector2i = np + axis
		if _free(np, grid, player) and _free(nt, grid, player):
			out.append({"act": {"kind": "straight", "pos": np, "facing": facing},
					"pos": np, "facing": facing})
	# TURN: pivot around a current cell to a perpendicular side. The pivot cell stays,
	# the far cell swings out; the body ends perpendicular on (pivot, far).
	var perp := Vector2i(-axis.y, axis.x)
	for pivot: Vector2i in [pos, tail]:
		for side: Vector2i in [perp, -perp]:
			var far: Vector2i = pivot + side
			if _free(far, grid, player) and _free(pivot, grid, player):
				var nf: int = _facing_of(far - pivot)
				out.append({"act": {"kind": "turn", "pos": pivot, "facing": nf},
						"pos": pivot, "facing": nf})
	return out

# ── helpers ───────────────────────────────────────────────────────────────────
func _free(t: Vector2i, grid: Grid, player: Vector2i) -> bool:
	return not grid.is_blocked(t) and t != player

func _facing_of(d: Vector2i) -> int:
	if absi(d.x) >= absi(d.y):
		return Config.Facing.EAST if d.x >= 0 else Config.Facing.WEST
	return Config.Facing.SOUTH if d.y >= 0 else Config.Facing.NORTH

# Pack (pos, facing) into one int for the visited set (grid is well under 256 wide).
func _key(pos: Vector2i, facing: int) -> int:
	return ((pos.x + 128) << 16) | ((pos.y + 128) << 2) | facing

# The engine's move-only plan() is unused; the controller drives the serpent.
func plan(mob: Combatant, player: Combatant, grid: Grid) -> Array:
	return []
