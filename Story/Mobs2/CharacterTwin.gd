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

# The seat beside you it wants: best flank first, nearest as the tiebreak. Its twin's
# tile is already blocked in this grid, so the two of them settle on different seats.
func _seat(pos: Vector2i, player: Combatant, grid: Grid) -> Vector2i:
	var seat := player.pos                 # hemmed in -> just come straight at you
	var best := 99999
	for t: Vector2i in _neighbours(player.pos):
		if grid.is_blocked(t):
			continue
		var score := _rank(t, player) * 100 + Grid.dist(pos, t)
		if score < best:
			best = score
			seat = t
	return seat

# One CARDINAL step toward that seat (never diagonal: a move is one tile, four ways).
func _step_toward_seat(pos: Vector2i, player: Combatant, grid: Grid) -> Vector2i:
	var goal := _seat(pos, player, grid)
	var best := pos
	var bestd := Grid.dist(pos, goal)
	for t: Vector2i in _neighbours(pos):
		if grid.is_blocked(t) or t == player.pos:
			continue
		var d := Grid.dist(t, goal)
		if d < bestd:
			bestd = d
			best = t
	return best

func _neighbours(p: Vector2i) -> Array:
	return [p + Vector2i(0, -1), p + Vector2i(1, 0), p + Vector2i(0, 1), p + Vector2i(-1, 0)]

func _has(spell: String) -> bool:
	return _loadout.has(spell)
