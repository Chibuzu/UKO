# CharacterTwin.gd -- ONE of the two identical units that make up the cave boss.
#
# Written from scratch (Fra). It inherits nothing from the old two-tile serpent: a twin
# is a plain SINGLE-TILE character, so there is no body, no span, no tail, no pivot and
# no rigid geometry anywhere in here. It is exactly as simple as a bat.
#
# BEHAVIOUR (Fra): aggressive, permanently trying to attack, and trying to FLANK.
#   * It aims for a SEAT beside you and prefers the one that pays: your back (x2) first,
#     then a side (x1.5). It bites the moment it is in contact, every turn.
#   * It needs NO coordination code with its twin. The combat grid already blocks its
#     sibling, so when both want the same seat the second one takes the next best --
#     they split. And you cannot face two units at once, so one of them is always
#     flanking you. The pincer falls out of the geometry rather than being scripted.
#   * Range 1, ONE tile (not the ooze's four). Two actions a turn, so the pair spends
#     four against your two.
class_name CharacterTwin
extends MobKind

# The two twins are the same creature with different NERVE (Fra):
#   BRUISER -- walks straight at you and brawls. It takes the NEAREST seat, whichever it
#              is, and does not care what it costs. It is the one you can see coming.
#   FLANKER -- sneaks. It ranks seats by what they PAY (your back x2, then a side x1.5)
#              and will walk the long way round to get behind you.
# Between them you cannot face both: block the bruiser and the flanker is at your back.
enum Role { BRUISER, FLANKER }
var role: int = Role.BRUISER

# Which of its OWN ranked seats this twin claims (0 = its best, 1 = its next). All the
# "coordination" the pair has: they never talk, they just refuse to want the same tile,
# so they split on the first step instead of queueing up behind one another.
var seat_pick := 0

var _loadout: Dictionary = {}

func setup(p_type: String, p_prof: Dictionary) -> void:
	super.setup(p_type, p_prof)
	_loadout = MobSpec.row(p_type).get("loadout", {})

# StoryCombat reads this: its damage comes from the RESOLVER, skip budget strikes.
func uses_true_actions() -> bool:
	return true

# Always exactly two actions: choose, simulate the result, choose again.
func plan(mob: Combatant, player: Combatant, grid: Grid) -> Array:
	var seq: Array = []
	var pos := mob.pos
	for _slot in range(2):
		var act := _best_action(pos, player, grid)
		seq.append(act)
		if String(act["id"]) == "move":
			pos = act["tile"]              # the second choice sees where the first landed
	return seq

# Bite if you are in reach; otherwise close on the seat it wants. That is the creature.
func _best_action(pos: Vector2i, player: Combatant, grid: Grid) -> Dictionary:
	if Grid.dist(pos, player.pos) == 1 and _has("attack"):
		return { "id": "attack", "tile": player.pos }
	if _has("move"):
		var step := _step_toward_seat(pos, player, grid)
		if step != pos:
			return { "id": "move", "tile": step }
	return { "id": "wait" }

# Threat preview: the tiles it could bite from where it stands.
func attack_pattern(origin: Vector2i) -> Array:
	return cardinal_ring(origin, 1)

# ── flanking ─────────────────────────────────────────────────────────────────
# What a seat is worth: 0 = your back (x2 damage), 1 = your side (x1.5), 2 = your front
# (x1). Judged by the duel's own flank rule, so what it wants and what the engine pays
# out can never disagree.
func _rank(tile: Vector2i, player: Combatant) -> int:
	var tier := Config.flank_tier(player.facing, player.pos, tile)
	if tier == "back":
		return 0
	if tier == "side":
		return 1
	return 2

# The seat beside you this twin claims -- and the ONE place the two of them differ.
# A BRUISER scores seats purely by distance: it takes the closest, and comes straight at
# you. A FLANKER scores by what a seat PAYS first (your back, then a side) and treats
# distance as a tiebreak, so it will happily walk the long way round to reach your back.
# `seat_pick` then keeps them off each other's tile when their answers happen to agree.
func _seat(pos: Vector2i, player: Combatant, grid: Grid) -> Vector2i:
	var seats: Array = []
	for t: Vector2i in _neighbours(player.pos):
		if grid.is_blocked(t):
			continue
		var score := Grid.dist(pos, t)                       # BRUISER: just get there
		if role == Role.FLANKER:
			score = _rank(t, player) * 100 + Grid.dist(pos, t)  # FLANKER: get BEHIND them
		seats.append({ "t": t, "score": score })
	if seats.is_empty():
		return player.pos                  # hemmed in -> just come straight at you
	seats.sort_custom(func(a, b): return int(a["score"]) < int(b["score"]))
	return seats[mini(seat_pick, seats.size() - 1)]["t"]

# One CARDINAL step along the SHORTEST PATH to the seat it wants.
#
# This is a breadth-first search, NOT a greedy step. Greedy freezes: the moment its twin
# stands between it and you, no neighbour is any closer, so it finds nothing to do and
# stops acting for the rest of the fight -- which is exactly what the far twin was doing.
# A BFS walks around its sibling instead, and it can never return a diagonal because
# every edge is one of the four cardinal neighbours.
func _step_toward_seat(pos: Vector2i, player: Combatant, grid: Grid) -> Vector2i:
	var goal := _seat(pos, player, grid)
	if goal == pos:
		return pos
	var prev := { pos: pos }
	var queue: Array = [pos]
	var found := false
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if cur == goal:
			found = true
			break
		for t: Vector2i in _neighbours(cur):
			if prev.has(t) or grid.is_blocked(t) or t == player.pos:
				continue
			prev[t] = cur
			queue.append(t)
	if not found:
		return pos                         # walled in: nothing it can do this turn
	var step: Vector2i = goal               # walk the path back to our first step
	while prev[step] != pos:
		step = prev[step]
	return step

func _neighbours(p: Vector2i) -> Array:
	return [p + Vector2i(0, -1), p + Vector2i(1, 0), p + Vector2i(0, 1), p + Vector2i(-1, 0)]

func _has(spell: String) -> bool:
	return _loadout.has(spell)
