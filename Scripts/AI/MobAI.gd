# MobAI.gd -- story-mob brains. DESIGN RULE (Fra): monsters use ONLY their own
# toolkit -- attack, pivot, move. No guard, no rest, no spells, no grenade.
# The mob's attack PROFILE lives on the Combatant (set by GameController):
#   bat  -> attack_range = 2            (strikes from two tiles away)
#   ooze -> attack_all_adjacent = true  (every attack hits ALL 4 adjacent tiles)
# so the chooser here only needs "am I in reach?", and the Resolver does the rest.
#
# Deliberately simple and readable -- a hunting instinct, not a strategist:
#   slot: in reach & can pay -> ATTACK; else close distance (best legal step);
#   else if the foe flanks us -> PIVOT to face them; else WAIT.
# Two slots with projection between them, mirroring how duel sequences work.
class_name MobAI
extends RefCounted

static func choose_sequence(mob: String, me: Combatant, foe: Combatant, grid: Grid) -> Array:
	var seq: Array = []
	var pos := me.pos
	var facing := me.facing
	var energy := me.energy
	for _slot in range(2):
		var act := _pick(me, foe, grid, pos, facing, energy)
		seq.append(act)
		match String(act.get("id", "")):
			"move":
				energy -= Config.effective_move_cost(facing, pos, act["tile"], me.statuses)
				pos = act["tile"]
			"attack":
				energy -= Config.effective_energy_cost("attack", me.statuses)
			"pivot":
				facing = int(act["facing"])
	return seq

static func _pick(me: Combatant, foe: Combatant, grid: Grid, pos: Vector2i, facing: int, energy: int) -> Dictionary:
	var atk_cost := Config.effective_energy_cost("attack", me.statuses)
	if _in_reach(me, pos, foe.pos) and energy >= atk_cost:
		return {"id": "attack", "tile": foe.pos}
	# Close the distance: the legal step that gets nearest to the foe (stable DIRS order).
	var best_tile := pos
	var best_d := Grid.dist(pos, foe.pos)
	for dv in Grid.DIRS:
		var t: Vector2i = pos + dv
		if not grid.in_bounds(t) or grid.is_blocked(t) or t == foe.pos:
			continue
		if energy < Config.effective_move_cost(facing, pos, t, me.statuses):
			continue
		var d := Grid.dist(t, foe.pos)
		if d < best_d:
			best_d = d
			best_tile = t
	if best_tile != pos:
		return {"id": "move", "tile": best_tile}
	# Can't advance: at least face the threat (free) if they're behind/beside us.
	var want := _facing_toward(pos, foe.pos)
	if want != facing:
		return {"id": "pivot", "facing": want}
	return {"id": "wait"}

static func _in_reach(me: Combatant, pos: Vector2i, foe_pos: Vector2i) -> bool:
	if me.attack_all_adjacent:
		return Grid.dist(pos, foe_pos) == 1   # ooze: the burst catches cardinal-adjacent
	return Grid.dist(pos, foe_pos) <= me.attack_range   # bat: reach 2; default 1

static func _facing_toward(from: Vector2i, to: Vector2i) -> int:
	var d := to - from
	if absi(d.x) >= absi(d.y):
		return Config.Facing.EAST if d.x >= 0 else Config.Facing.WEST
	return Config.Facing.SOUTH if d.y >= 0 else Config.Facing.NORTH
