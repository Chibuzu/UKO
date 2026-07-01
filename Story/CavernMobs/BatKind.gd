# BatKind.gd
# Ranged skirmisher. Kites to hold `atk_range` tiles and pokes ONLY along cardinal lines
# (never diagonally); walls block it (line of sight is checked by the base). Movement is
# the base kite; only the plan target-distance and the attack shape differ.
class_name BatKind
extends MobKind

func plan(mob: Combatant, player: Combatant, grid: Grid) -> Array:
	return kite_seq(mob, player.pos, grid, int(prof.get("atk_range", 2)))

# A cardinal cross reaching out to atk_range (e.g. 2): the two tiles N/E/S/W at each step.
func attack_pattern(origin: Vector2i) -> Array:
	var out: Array = []
	for step in range(1, int(prof.get("atk_range", 2)) + 1):
		for t in cardinal_ring(origin, step):
			out.append(t)
	return out
