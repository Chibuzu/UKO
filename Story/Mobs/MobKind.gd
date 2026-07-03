# MobKind.gd
# Base class for a story monster's BEHAVIOR. Every creature is a subclass that overrides a
# few hooks; the shared movement / attack / loot machinery lives here so a new creature is
# one small file (plus a line in MobBrain.make_kind). The combat engine is never touched:
#   * plan() emits ONLY move actions to the resolver -- mobs can only move & attack, and an
#     attack is not a resolver action;
#   * attack_damage() applies the strike AFTER the resolve, against the player's final
#     tile, guard-aware via the engine's own GUARD_BLOCK table -- so we fully own each
#     creature's range/shape while guard and line-of-sight still behave like a duel.
# Override points, in the order you'll usually reach for them:
#   plan(), attack_pattern(), attack_damage(), on_committed(), roll_loot().
class_name MobKind
extends RefCounted

var type: String = ""
var prof: Dictionary = {}

func setup(p_type: String, p_prof: Dictionary) -> void:
	type = p_type
	prof = p_prof

# ── hooks (override per creature) ─────────────────────────────────────────────

# Movement for the turn: a resolver MOVE-ONLY sequence (never guard/rest/attack).
# Default: close toward the player.
func plan(mob: Combatant, player: Combatant, grid: Grid) -> Array:
	return chase_seq(mob, player.pos, grid)

# The tiles this creature threatens from `origin`. Default: the 4 adjacent tiles.
func attack_pattern(origin: Vector2i) -> Array:
	return cardinal_ring(origin, 1)

# Damage dealt to the player this turn, from final positions, guard-aware. Default melee.
func attack_damage(mob: Combatant, player: Combatant, grid: Grid, guarded: bool) -> int:
	if mob.is_dead() or not threatens(mob.pos, player.pos, grid):
		return 0
	# Directional flanking, exactly like the duel: a strike into the player's side/back hurts
	# more (side 1.5x, back 2x) based on where the mob stands relative to the player's facing.
	var tier := Config.flank_tier(player.facing, player.pos, mob.pos)
	var base := int(round(float(prof.get("dmg", 15)) * float(Config.FLANK_MULT.get(tier, 1.0))))
	return apply_guard(base, player, mob.pos, guarded)

# Fired after the turn's state is committed. Hook for thresholds / splits / on-hit logic.
# `entry` is this mob's record {combatant, uv, kind, type, ...}; `ctx` is the StoryController.
func on_committed(entry: Dictionary, player: Combatant, ctx) -> void:
	pass

# Loot rolled when this creature dies: [{item, count}]. Data-driven from the profile's
# "loot" table; override for conditional drops.
func roll_loot() -> Array:
	var out: Array = []
	for drop in prof.get("loot", []):
		if randf() <= float(drop.get("chance", 1.0)):
			out.append({ "item": String(drop["item"]), "count": int(drop.get("count", 1)) })
	return out

# ── shared helpers ────────────────────────────────────────────────────────────

# Is the player on a threatened tile, with line of sight (walls block)?
func threatens(from: Vector2i, ppos: Vector2i, grid: Grid) -> bool:
	if not grid.has_los(from, ppos):
		return false
	for t in attack_pattern(from):
		if t == ppos:
			return true
	return false

# Reduce damage by the engine's directional guard table when the player guarded:
# front fully blocks, side halves, back wastes it.
static func apply_guard(dmg: int, player: Combatant, from_pos: Vector2i, guarded: bool) -> int:
	if not guarded:
		return dmg
	var tier := Config.flank_tier(player.facing, player.pos, from_pos)
	return maxi(0, int(round(dmg * (1.0 - float(Config.GUARD_BLOCK.get(tier, 0.0))))))

# The 4 cardinal tiles at exactly radius r (never diagonal).
static func cardinal_ring(o: Vector2i, r: int) -> Array:
	return [o + Vector2i(0, -r), o + Vector2i(r, 0), o + Vector2i(0, r), o + Vector2i(-r, 0)]

static func chase_seq(mob: Combatant, target: Vector2i, grid: Grid) -> Array:
	return _walk(mob, target, grid, false, 0)

static func kite_seq(mob: Combatant, target: Vector2i, grid: Grid, keep: int) -> Array:
	return _walk(mob, target, grid, true, keep)

# Up to two orthogonal steps, projecting cost/facing as it goes. chase -> minimize
# distance; kite -> hold `keep` (back off when closer, approach when farther).
static func _walk(mob: Combatant, target: Vector2i, grid: Grid, kite: bool, keep: int) -> Array:
	var seq: Array = []
	var c: Combatant = mob.clone()
	for _n in 2:
		var step := _step(c.pos, target, grid, kite, keep)
		if step == c.pos:
			break
		var cost := Config.effective_move_cost(c.facing, c.pos, step, c.statuses)
		if c.energy < cost:
			break
		seq.append({ "id": "move", "tile": step })
		c.energy -= cost
		c.facing = _face(step - c.pos)
		c.pos = step
	return seq     # empty == hold position (mobs never Wait); an in-range strike still applies

static func _step(pos: Vector2i, target: Vector2i, grid: Grid, kite: bool, keep: int) -> Vector2i:
	var d := Grid.dist(pos, target)
	if kite and d == keep:
		return pos
	var want_far := kite and d < keep
	var best := pos
	var best_d := d
	for n: Vector2i in [pos + Vector2i(0, -1), pos + Vector2i(1, 0), pos + Vector2i(0, 1), pos + Vector2i(-1, 0)]:
		if grid.is_blocked(n) or n == target:
			continue
		var nd := Grid.dist(n, target)
		if want_far:
			if nd > best_d:
				best_d = nd
				best = n
		else:
			if nd < best_d:
				best_d = nd
				best = n
	return best

static func _face(delta: Vector2i) -> int:
	for f in Config.FACING_VEC:
		if Config.FACING_VEC[f] == delta:
			return f
	return Config.Facing.SOUTH
