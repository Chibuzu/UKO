# BatKind.gd
# Darting skirmisher. It wants to sit EXACTLY one tile from you and poke along a cardinal
# line -- never diagonally; walls block it (line of sight checked by the base). It does NOT
# sidestep-kite: it closes to adjacent, bites, and only backs off if you crowd it. Movement
# is a "hold at range 1" walk (approach when far, step back when the player is on top of it).
class_name BatKind
extends MobKind

func plan(mob: Combatant, player: Combatant, grid: Grid) -> Array:
	var d := Grid.dist(mob.pos, player.pos)
	if d <= 1:
		return []                                   # already in biting range: HOLD and strike
	# Spend ONE action closing (leaving the second as the strike budget), so it darts
	# in a tile and bites rather than shuffling sideways to preserve distance.
	return _one_step_toward(mob, player.pos, grid)

func _one_step_toward(mob: Combatant, target: Vector2i, grid: Grid) -> Array:
	var best := mob.pos
	var bestd := Grid.dist(mob.pos, target)
	for dir: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		var t: Vector2i = mob.pos + dir
		if grid.is_blocked(t) or t == target:
			continue
		var nd := Grid.dist(t, target)
		if nd < bestd:
			bestd = nd
			best = t
	if best == mob.pos:
		return []
	return [{ "id": "move", "tile": best }]

# Cardinal cross out to atk_range (1): the four tiles N/E/S/W.
func attack_pattern(origin: Vector2i) -> Array:
	var out: Array = []
	for step in range(1, int(prof.get("atk_range", 1)) + 1):
		for t in cardinal_ring(origin, step):
			out.append(t)
	return out
