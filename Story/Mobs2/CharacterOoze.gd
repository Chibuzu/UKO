# CharacterOoze.gd -- the ooze as a TRUE CHARACTER: real resolver actions from its
# MobSpec loadout (move / attack / wait), paying real costs, resolved like a duelist.
#
# BEHAVIOR (Fra):
#   * STICK to you -- once in contact it never steps out of it, and it spits every turn.
#   * FLANK you -- it picks WHICH of the four tiles around you to take: your BACK
#     (x2 damage) first, then a SIDE (x1.5). Note the geometry: those four seats are all
#     2 tiles apart, so a seated ooze cannot change seat without breaking contact --
#     which is why flanking is decided on the APPROACH, and why the split matters (two
#     oozes can never both sit in your front arc).
#   * Its attack spits ALL FOUR of its neighbours at once (loadout: all_adjacent), so it
#     never needs to aim: only to stand in the right place. That is the whole brain.
#   * At half health it splits once into a copy (on_committed, at the bottom).
class_name CharacterOoze
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
			pos = act["tile"]                # the second choice sees where the first landed
	return seq

# The single best action from `pos` (never empty: `wait` is the floor).
func _best_action(pos: Vector2i, player: Combatant, grid: Grid) -> Dictionary:
	if Grid.dist(pos, player.pos) == 1 and _has("attack"):
		return { "id": "attack", "tile": player.pos }   # in contact: it always spits
	if _has("move"):
		var step := _close_in(pos, player, grid)
		if step != pos:
			return { "id": "move", "tile": step }
	return { "id": "wait" }

# Threat preview: every neighbour, because one spit hits them all.
func attack_pattern(origin: Vector2i) -> Array:
	return cardinal_ring(origin, 1)

# ── flanking: the ooze's whole identity is WHERE it stands ────────────────────
# How good a tile is to spit from -- 0 = your back (x2), 1 = your side (x1.5),
# 2 = your front (x1). Judged by the duel's own flank rule, so what the brain wants
# and what the engine pays out can never disagree.
func _rank(tile: Vector2i, player: Combatant) -> int:
	var tier := Config.flank_tier(player.facing, player.pos, tile)
	if tier == "back":
		return 0
	if tier == "side":
		return 1
	return 2

# One step toward the seat it wants around you.
func _close_in(pos: Vector2i, player: Combatant, grid: Grid) -> Vector2i:
	var goal := _best_seat(pos, player, grid)
	var best := pos
	var bestd := Grid.dist(pos, goal)
	for t: Vector2i in _neighbours(pos):
		if not _free(t, grid, player.pos):
			continue
		var d := Grid.dist(t, goal)
		if d < bestd:
			bestd = d
			best = t
	return best

# The tile around you it most wants: best flank first, nearest as the tiebreak.
func _best_seat(pos: Vector2i, player: Combatant, grid: Grid) -> Vector2i:
	var seat := player.pos                    # fallback: nothing free -> just come at you
	var best := 99999
	for t: Vector2i in _neighbours(player.pos):
		if not _free(t, grid, player.pos):
			continue
		var score := _rank(t, player) * 100 + Grid.dist(pos, t)
		if score < best:
			best = score
			seat = t
	return seat

# ── shared helpers ────────────────────────────────────────────────────────────
func _neighbours(p: Vector2i) -> Array:
	return [p + Vector2i(0, -1), p + Vector2i(1, 0), p + Vector2i(0, 1), p + Vector2i(-1, 0)]

func _free(t: Vector2i, grid: Grid, ppos: Vector2i) -> bool:
	return not grid.is_blocked(t) and t != ppos   # the grid already blocks other mobs

func _has(spell: String) -> bool:
	return _loadout.has(spell)

# ── the split (rule unchanged, ported from SlimeKind) ─────────────────────────
# The first time it drops to 50% HP or below it spawns a same-resource copy beside you.
# The copy is flagged so it can never split again -- no runaway.
func on_committed(entry: Dictionary, player: Combatant, ctx) -> void:
	if entry.get("no_split", false):
		return
	var c: Combatant = entry["combatant"]
	if c.is_dead():
		return
	if c.hp * 2 <= int(prof.get("hp", 100)):
		entry["no_split"] = true
		ctx.spawn_split(entry, player)
