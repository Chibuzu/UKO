# BatKind.gd
# Ranged skirmisher. It fights from EXACTLY two tiles away along a cardinal line
# (its attack_pattern is the radius-2 cross), firing a projectile -- it does NOT
# close to melee. It kites: backs off when the player crowds inside 2, drifts in
# when the player is farther than 2, and holds position to shoot when at range 2
# on a cardinal line. Diagonal-only positions step to line up a cardinal shot.
class_name BatKind
extends MobKind

const RANGE := 2

func plan(mob: Combatant, player: Combatant, grid: Grid) -> Array:
	# Already lined up at range 2 on a cardinal? HOLD and shoot (moves = 0 -> both
	# strike ticks fire). Otherwise reposition to keep distance 2 and get on-line.
	if _lined_up(mob.pos, player.pos, grid):
		return []
	return MobKind.kite_seq(mob, player.pos, grid, RANGE)

# True when the player sits exactly RANGE away on a straight cardinal line with LOS.
func _lined_up(from: Vector2i, ppos: Vector2i, grid: Grid) -> bool:
	if not grid.has_los(from, ppos):
		return false
	for t in cardinal_ring(from, RANGE):
		if t == ppos:
			return true
	return false

# The bat threatens the radius-2 cardinal cross (a ranged poke, not adjacency).
func attack_pattern(origin: Vector2i) -> Array:
	return cardinal_ring(origin, RANGE)
