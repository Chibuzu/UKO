# MobBrain.gd
# Per-type story enemies. This is the ONE source for what each monster is (name, look,
# HP, difficulty) and the small bit of behavior the combat engine can't express:
#   * MELEE types (Slime, Serpent) are driven by the normal difficulty AI elsewhere --
#     with NO gear equipped they simply have no spells, so they move/attack/guard/rest.
#     Their damage, guard interaction and flanking all run through the unmodified
#     Resolver exactly like a duel.
#   * RANGED types (Bat) can't be expressed by the melee AI (they kite), so they get a
#     tiny movement-only brain here and a guard-aware ranged strike applied on top of a
#     normal resolve. The strike reuses the engine's OWN flank/guard table, so guarding
#     a Bat behaves identically to guarding a melee hit (front blocks, side halves,
#     back wastes it) and simply stepping out of range dodges it.
# Nothing in the combat engine is touched.
class_name MobBrain
extends RefCounted

const PROFILES := {
	"bat": {
		"name": "Bat", "kind": "ranged", "difficulty": AI.Difficulty.EASY,
		"hp": 45, "atk_range": 2, "dmg": 10, "kite_dist": 2,
		"tint": Color(0.62, 0.80, 1.0), "scale": 0.9,
	},
	"slime": {
		"name": "Slime", "kind": "melee", "difficulty": AI.Difficulty.CHALLENGING,
		"hp": 80,
		"tint": Color(0.55, 1.0, 0.62), "scale": 1.12,
	},
	"serpent": {
		"name": "Serpent", "kind": "melee", "difficulty": AI.Difficulty.EXTREME,
		"hp": 100,
		"tint": Color(0.90, 0.52, 0.55), "scale": 1.45,
	},
}

# ── Ranged brain: a movement-only sequence that holds `kite_dist` from the player ──
# Up to two steps (the same action economy the player has). No attack action is ever
# emitted -- the strike itself is applied by ranged_damage() after the resolve.
static func kite_seq(mob: Combatant, target: Vector2i, grid: Grid, prof: Dictionary) -> Array:
	var seq: Array = []
	var c: Combatant = mob.clone()
	var kd: int = int(prof.get("kite_dist", 2))
	for _n in 2:
		var step := _kite_step(c, target, grid, kd)
		if step == c.pos:
			break
		var cost := Config.effective_move_cost(c.facing, c.pos, step, c.statuses)
		if c.energy < cost:
			break
		seq.append({"id": "move", "tile": step})
		c.energy -= cost
		c.facing = _face_dir(step - c.pos)
		c.pos = step
	if seq.is_empty():
		seq.append({"id": "wait"})     # at ideal range (or pinned): hold and poke
	return seq

# One kite step: too close -> back off, too far -> approach, at range -> hold.
static func _kite_step(c: Combatant, target: Vector2i, grid: Grid, kd: int) -> Vector2i:
	var d := Grid.dist(c.pos, target)
	if d == kd:
		return c.pos
	var want_far := d < kd
	var best := c.pos
	var best_d := d
	for n in _neighbors(c.pos):
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

# ── Ranged strike: applied to the player's FINAL position after the resolve ──
# In range + line of sight required, so movement or a wall dodges it. If the player
# guarded this turn, the engine's directional GUARD_BLOCK is applied by the flank tier
# of the Bat relative to the player's facing -- front fully blocks, side halves it.
static func ranged_damage(mob: Combatant, player: Combatant, grid: Grid, prof: Dictionary, player_guarded: bool) -> int:
	if mob.is_dead():
		return 0
	if Grid.dist(mob.pos, player.pos) > int(prof.get("atk_range", 2)):
		return 0
	if not grid.has_los(mob.pos, player.pos):
		return 0
	var dmg := int(prof.get("dmg", 10))
	if player_guarded:
		var tier := Config.flank_tier(player.facing, player.pos, mob.pos)
		var absorbed: float = float(Config.GUARD_BLOCK.get(tier, 0.0))
		dmg = int(round(dmg * (1.0 - absorbed)))
	return maxi(0, dmg)

# ── helpers ──
static func _neighbors(p: Vector2i) -> Array:
	return [p + Vector2i(0, -1), p + Vector2i(1, 0), p + Vector2i(0, 1), p + Vector2i(-1, 0)]

static func _face_dir(delta: Vector2i) -> int:
	for f in Config.FACING_VEC:
		if Config.FACING_VEC[f] == delta:
			return f
	return Config.Facing.SOUTH
