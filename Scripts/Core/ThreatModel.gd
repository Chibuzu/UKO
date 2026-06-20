# ThreatModel.gd
# Reads what a fighter can ACTUALLY do to another THIS turn, from the real board
# and both players' resources -- so the brain reasons about the situation instead
# of guessing the foe's single move. All pure/static, grounded in the resolver's
# exact rules:
#   - melee needs orthogonal adjacency at the strike, costs energy (approach +
#     swing = 2 action slots, so reach is <=2 tiles), GUARD blocks it, and the
#     flank multiplier keys off the DEFENDER's facing (front 1.0 / side 1.5 /
#     back 2.0);
#   - BURST ("around") only hits the 8 tiles around the caster (adjacency);
#   - DARK BOLT ("line", range N) needs a clear cardinal line to the target;
#   - REST regens only if the rester takes ZERO damage all turn.
# Spell reach allows ONE setup step (move/pivot is the other slot), matching what
# a fighter can set up in a single turn. Approximations are deliberately on the
# "don't cry wolf" side so the brain doesn't turtle against threats that aren't real.
class_name ThreatModel
extends RefCounted

const DIRS := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]

# ── Melee ───────────────────────────────────────────────────────────────
# Max basic-attack damage `att` can land on `def` this turn (0 if none). Honours
# reach (<=2 tiles), energy for approach+swing, and the BEST flank att can reach
# against def's current facing.
static func melee_damage(att: Combatant, def: Combatant, grid: Grid) -> int:
	var best := 0
	for dv in DIRS:
		var t: Vector2i = def.pos + dv          # an orthogonal strike tile beside def
		if not grid.in_bounds(t) or grid.is_blocked(t):
			continue
		var cost := -1
		if att.pos == t:
			cost = Config.COST_ATTACK            # already adjacent: just swing (1 slot)
		elif Grid.dist(att.pos, t) == 1:
			# step into t, then swing (2 slots). t is orthogonally next to att.
			cost = Config.effective_move_cost(att.facing, att.pos, t, att.statuses) + Config.COST_ATTACK
		else:
			continue                              # can't both reach t and swing this turn
		if att.energy < cost:
			continue
		var rel := flank_of(def, t)
		best = maxi(best, int(round(Config.ATTACK_DAMAGE * float(Config.FLANK_MULT[rel]))))
	return best

# ── Spells ──────────────────────────────────────────────────────────────
# Max damaging-spell damage `att` can land on `def` this turn (0 if none), gated
# by mp, cooldown, shape, range and line-of-sight, allowing one setup step.
static func spell_damage(att: Combatant, def: Combatant, grid: Grid) -> int:
	var best := 0
	for sid in att.spell_ids():
		var d := Config.def(sid)
		var eff: Dictionary = d.get("effect", {})
		if String(eff.get("type", "")) != "damage":
			continue
		if int(att.cooldowns.get(sid, 0)) > 0:
			continue
		if att.mp < int(d.get("mp_cost", 0)):
			continue
		var amt := int(eff.get("amount", 0))
		match String(d.get("shape", "")):
			"around":                             # BURST: needs to be adjacent (Chebyshev 1)
				if _can_reach_adjacent(att, def, grid):
					best = maxi(best, amt)
			"line":                               # DARK BOLT: clear cardinal line within range
				if _can_line(att, def, grid, int(d.get("range", 1))):
					best = maxi(best, amt)
	return best

# ── Composite reads the brain uses ───────────────────────────────────────
# Worst-case damage `def` can take from `att` this turn, split by whether a GUARD
# would stop it (melee is blockable; spells are not).
static func incoming(att: Combatant, def: Combatant, grid: Grid) -> Dictionary:
	return {"blockable": melee_damage(att, def, grid), "unblockable": spell_damage(att, def, grid)}

# Total worst-case damage `def` can take from `att` this turn.
static func worst_damage(att: Combatant, def: Combatant, grid: Grid) -> int:
	return melee_damage(att, def, grid) + spell_damage(att, def, grid)

# Safe for `def` to REST against `att`? Only if att can deal no damage at all
# (any hit interrupts the rest, so all the hp/mp it would buy never arrives).
static func rest_safe(att: Combatant, def: Combatant, grid: Grid) -> bool:
	return worst_damage(att, def, grid) == 0

# Does `att` have a blockable MELEE threat -> is a GUARD worth anything this turn?
static func has_melee_threat(att: Combatant, def: Combatant, grid: Grid) -> bool:
	return melee_damage(att, def, grid) > 0

# ── Geometry helpers (mirror the resolver exactly) ───────────────────────
# Which face of `def` the tile `at` sits on, by def's facing: front / side / back.
static func flank_of(def: Combatant, at: Vector2i) -> String:
	var to_at: Vector2i = at - def.pos
	var f: Vector2i = Config.FACING_VEC[def.facing]
	var dot := to_at.x * f.x + to_at.y * f.y
	if dot > 0:
		return "front"
	elif dot < 0:
		return "back"
	return "side"

static func _cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

# Can `att` be within Chebyshev 1 of `def` this turn (already, or after one step)?
static func _can_reach_adjacent(att: Combatant, def: Combatant, grid: Grid) -> bool:
	if _cheb(att.pos, def.pos) <= 1:
		return true
	for dv in DIRS:
		var t: Vector2i = att.pos + dv
		if not grid.in_bounds(t) or grid.is_blocked(t) or t == def.pos:
			continue
		if att.energy >= Config.effective_move_cost(att.facing, att.pos, t, att.statuses) and _cheb(t, def.pos) <= 1:
			return true
	return false

# Can `att` put `def` on a clear cardinal line within range, now or after a step?
static func _can_line(att: Combatant, def: Combatant, grid: Grid, rng: int) -> bool:
	if _ray_hits(att.pos, def.pos, grid, rng):
		return true
	for dv in DIRS:
		var t: Vector2i = att.pos + dv
		if not grid.in_bounds(t) or grid.is_blocked(t) or t == def.pos:
			continue
		if att.energy >= Config.effective_move_cost(att.facing, att.pos, t, att.statuses) and _ray_hits(t, def.pos, grid, rng):
			return true
	return false

# Is `target` reachable from `from` along a single cardinal, within `rng`, with no
# wall in between (blockers stop the line, exactly as _shape_tiles does)?
static func _ray_hits(from: Vector2i, target: Vector2i, grid: Grid, rng: int) -> bool:
	var dv: Vector2i = target - from
	if dv.x != 0 and dv.y != 0:
		return false                              # not cardinally aligned
	if Grid.dist(from, target) > rng:
		return false
	var step := Vector2i(signi(dv.x), signi(dv.y))
	var p: Vector2i = from
	for _i in range(rng):
		p += step
		if not grid.in_bounds(p) or grid.is_blocked(p):
			return false                          # LOS blocked
		if p == target:
			return true
	return false
