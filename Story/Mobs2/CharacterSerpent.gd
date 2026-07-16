# CharacterSerpent.gd -- the two-headed cave boss as a TRUE CHARACTER.
#
# BODY: a rigid 2-tile line (MobSpec `body_line: 2`) -- its cells are `pos` and the tile
# its facing extends into, so it stands VERTICAL facing N/S and HORIZONTAL facing E/W.
# The engine derives those cells from the unit itself, so what is drawn, what blocks,
# what is hittable and what it strikes from can never drift apart.
#
# ACTIONS (its MobSpec loadout -- it is the ONLY creature that owns `pivot`):
#   * ONE tile of movement per turn, plus one other action (Fra).
#   * Its 90-degree TURN is just move + pivot: at pos (3,3) facing N (body (3,3)+(3,2)),
#     move to (3,2) then pivot EAST -> body (3,2)+(4,2), now threatening (2,2) and (5,2).
#     No custom spell exists or is needed -- the turn IS its two actions.
#   * It bites one tile straight out past EITHER head (range 1).
#   * It has no back: an attack off its body line is a x1.5 flank (see Resolver._flank).
#
# BRAIN: a breadth-first search over (pos, facing) whose edges are whole TURNS finds the
# shortest way into a stance that threatens you, then plays that turn's two actions.
class_name CharacterSerpent
extends MobKind

const _MAX_EXPAND := 4000            # BFS safety cap (the cage is small; ample)
const _STEPS := [Vector2i.ZERO, Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const _FACINGS := [Config.Facing.NORTH, Config.Facing.EAST, Config.Facing.SOUTH, Config.Facing.WEST]

var _loadout: Dictionary = {}
var _facing: int = Config.Facing.SOUTH   # last known, for the board's threat preview

func setup(p_type: String, p_prof: Dictionary) -> void:
	super.setup(p_type, p_prof)
	_loadout = MobSpec.row(p_type).get("loadout", {})

# StoryCombat reads this: its damage comes from the RESOLVER, skip budget strikes.
func uses_true_actions() -> bool:
	return true

# The two tiles it threatens: one straight out past each head.
static func strike_tiles(pos: Vector2i, facing: int) -> Array:
	var f := Vector2i(Config.FACING_VEC[facing])
	return [pos - f, pos + f + f]

func attack_pattern(origin: Vector2i) -> Array:
	return strike_tiles(origin, _facing)

func plan(mob: Combatant, player: Combatant, grid: Grid) -> Array:
	_facing = mob.facing
	if _threatens(mob.pos, mob.facing, player.pos) and _has("attack"):
		return [_bite(player.pos), _bite(player.pos)]     # already lined up: bite twice
	var turn := _search(mob, player.pos, grid)
	return turn if not turn.is_empty() else [{ "id": "wait" }, { "id": "wait" }]

# ── the search ────────────────────────────────────────────────────────────────
func _search(mob: Combatant, player: Vector2i, grid: Grid) -> Array:
	var seen := {}
	seen[_key(mob.pos, mob.facing)] = true
	var queue: Array = []
	var first := {}                                   # state key -> the FIRST turn of its path
	for t in _turns(mob.pos, mob.facing, mob, grid, player):
		var k: int = _key(t["pos"], t["facing"])
		if seen.has(k):
			continue
		seen[k] = true
		first[k] = t
		queue.append(t)
	var expanded := 0
	while not queue.is_empty() and expanded < _MAX_EXPAND:
		var cur: Dictionary = queue.pop_front()
		expanded += 1
		var ck: int = _key(cur["pos"], cur["facing"])
		if _threatens(cur["pos"], cur["facing"], player):
			return _fill(first[ck], player)
		for t in _turns(cur["pos"], cur["facing"], mob, grid, player):
			var k2: int = _key(t["pos"], t["facing"])
			if seen.has(k2):
				continue
			seen[k2] = true
			first[k2] = first[ck]
			queue.append(t)
	return []

# Every stance reachable in ONE turn, with the actions that get there: at most one move
# (one tile) plus one other action -- so a step, a pivot, or the two together (the turn).
func _turns(pos: Vector2i, facing: int, mob: Combatant, grid: Grid, player: Vector2i) -> Array:
	var out: Array = []
	for d: Vector2i in _STEPS:
		if d != Vector2i.ZERO and not _has("move"):
			continue
		var np: Vector2i = pos + d
		if d != Vector2i.ZERO and not _fits(mob, np, facing, grid, player):
			continue                                  # the body must fit as it steps...
		for nf: int in _FACINGS:
			if nf != facing and not _has("pivot"):
				continue
			if d == Vector2i.ZERO and nf == facing:
				continue                              # not a turn at all
			if not _fits(mob, np, nf, grid, player):
				continue                              # ...and where it ends up
			var acts: Array = []
			if d != Vector2i.ZERO:
				acts.append({ "id": "move", "tile": np })
			if nf != facing:
				acts.append({ "id": "pivot", "facing": nf })
			out.append({ "pos": np, "facing": nf, "acts": acts })
	return out

# A turn always spends both slots: bite if the stance it ends in threatens you, else wait.
func _fill(turn: Dictionary, player: Vector2i) -> Array:
	var acts: Array = (turn["acts"] as Array).duplicate()
	while acts.size() < 2:
		if _threatens(turn["pos"], turn["facing"], player) and _has("attack"):
			acts.append(_bite(player))
		else:
			acts.append({ "id": "wait" })
	return acts

# ── helpers ───────────────────────────────────────────────────────────────────
func _threatens(pos: Vector2i, facing: int, player: Vector2i) -> bool:
	return player in strike_tiles(pos, facing)

# Does the whole body fit standing at `at` facing `f`? (The engine enforces this too;
# the brain never proposes an illegal stance in the first place.)
func _fits(mob: Combatant, at: Vector2i, f: int, grid: Grid, player: Vector2i) -> bool:
	for c: Vector2i in mob.cells_facing(at, f):
		if grid.is_blocked(c) or c == player:
			return false
	return true

func _bite(tile: Vector2i) -> Dictionary:
	return { "id": "attack", "tile": tile }

func _has(spell: String) -> bool:
	return _loadout.has(spell)

# Pack (pos, facing) into one int for the visited set.
func _key(pos: Vector2i, facing: int) -> int:
	return ((pos.x + 128) << 16) | ((pos.y + 128) << 2) | facing
