# CharacterBat.gd -- the bat as a TRUE CHARACTER: real resolver actions from its
# MobSpec loadout (move / attack / wait), paying real costs, resolved like a duelist.
#
# RULES (Fra):
#   * NO facing, NO pivot -- actions go in any direction directly.
#   * ALWAYS exactly TWO actions per turn: choose the best action, simulate its
#     result, choose the best again; `wait` fills when nothing is useful.
#   * Its identity is range: closer than 2 -> retreat; at exactly 2 on a clear
#     cardinal -> shoot; at 2 but diagonal -> step around the ring to the firing
#     line; farther -> approach.
class_name CharacterBat
extends MobKind

var _loadout: Dictionary = {}

func setup(p_type: String, p_prof: Dictionary) -> void:
	super.setup(p_type, p_prof)
	_loadout = MobSpec.row(p_type).get("loadout", {})

# StoryCombat reads this: damage comes from the RESOLVER, skip budget strikes.

func plan(mob: Combatant, player: Combatant, grid: Grid) -> Array:
	var seq: Array = []
	var pos := mob.pos                       # simulated position between the two slots
	for _slot in range(2):
		var act := _best_action(pos, player.pos, grid)
		seq.append(act)
		if String(act["id"]) == "move":
			pos = act["tile"]                # the second choice sees where the first landed
	return seq

# The single best action from `pos` (never empty: `wait` is the floor).
func _best_action(pos: Vector2i, ppos: Vector2i, grid: Grid) -> Dictionary:
	var rng := _tuning("attack", "range", 2)
	var d := Grid.dist(pos, ppos)
	if d < rng and _has("move"):
		var back := _walk_step(pos, ppos, grid, true)
		if back != pos:
			return { "id": "move", "tile": back }
	if d == rng and _has("attack") and _lined_up(pos, ppos, grid):
		return { "id": "attack", "tile": ppos }
	if d == rng and _has("move"):
		var al := _align_step(pos, ppos, rng, grid)
		if al != pos:
			return { "id": "move", "tile": al }
	if d > rng and _has("move"):
		var step := _walk_step(pos, ppos, grid, false)
		if step != pos:
			return { "id": "move", "tile": step }
	return { "id": "wait" }

# Threat preview on the board: the cardinal cross out to range.
func attack_pattern(origin: Vector2i) -> Array:
	var out: Array = []
	for r in range(1, _tuning("attack", "range", 2) + 1):
		out += cardinal_ring(origin, r)
	return out

# ── loadout access (a creature can only use what it owns) ─────────────────────
func _has(spell: String) -> bool:
	return _loadout.has(spell)

func _tuning(spell: String, key: String, fallback: int) -> int:
	return int(_loadout.get(spell, {}).get(key, fallback))

# ── geometry ───────────────────────────────────────────────────────────────────
func _lined_up(from: Vector2i, ppos: Vector2i, grid: Grid) -> bool:
	if from.x != ppos.x and from.y != ppos.y:
		return false                          # cardinal lines only
	return grid.has_los(from, ppos)

func _align_step(from: Vector2i, ppos: Vector2i, rng: int, grid: Grid) -> Vector2i:
	for dir: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		var t: Vector2i = from + dir
		if grid.is_blocked(t) or t == ppos:
			continue
		if Grid.dist(t, ppos) == rng and (t.x == ppos.x or t.y == ppos.y):
			return t
	return from

func _walk_step(from: Vector2i, target: Vector2i, grid: Grid, away: bool) -> Vector2i:
	var best := from
	var bestd := Grid.dist(from, target)
	for dir: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		var t: Vector2i = from + dir
		if grid.is_blocked(t) or t == target:
			continue
		var nd := Grid.dist(t, target)
		if (away and nd > bestd) or (not away and nd < bestd):
			bestd = nd
			best = t
	return best
