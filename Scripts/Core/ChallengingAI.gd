# ChallengingAI.gd
# The "Challenging" brain. Unlike Easy (a fixed reaction ladder), this one LOOKS
# AHEAD at its own options: it builds a bounded set of candidate 1-2 action
# sequences, plays each through the REAL resolver against one assumed enemy move
# (what Easy would do this turn), scores the resulting position, and keeps the
# best. Because Resolver.resolve clones its inputs and never mutates them, this
# is side-effect free and reuses the exact combat rules (no duplicated math).
#
# It does NOT model a smart/uncertain enemy — that's reserved for Hard/Extreme.
# It assumes the enemy plays simply and optimizes its response.
#
# The scoring weights below are hand-tuned starting points; tune by playtest.
class_name ChallengingAI
extends RefCounted

const W_DEAL := 1.0      # value of damage dealt to the foe
const W_TAKE := 1.25     # cost of damage taken (slightly > dealt: prefer not trading down)
const W_WIN := 1000.0    # winning / losing the duel dominates everything
const W_RES := 0.02      # tiny reward for keeping energy/mp (don't bleed dry)
const W_DIST := 0.4      # mild reward for staying close (keeps pressure on)

const DIRS := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]

static func choose_sequence(me: Combatant, foe: Combatant, grid: Grid, spells: Array) -> Array:
	# Assume the enemy plays the simple (Easy) move this turn, then optimize.
	var foe_seq := StubOpponent.choose_sequence(foe, me, grid, foe.spell_ids())

	# Start from Easy's own pick as a guaranteed-sane floor: Challenging is only
	# ever allowed to REPLACE it with something that scores strictly better.
	var best: Array = StubOpponent.choose_sequence(me, foe, grid, spells)
	var best_score := _score(me, foe, grid, best, foe_seq)

	for seq in _candidates(me, foe, grid):
		if seq.is_empty():
			continue
		var sc := _score(me, foe, grid, seq, foe_seq)
		if sc > best_score:
			best_score = sc
			best = seq
	return best

# Play my_seq vs the assumed foe_seq through the real rules; score from my side.
# me has id "B" and foe id "A" in the live game, so resolve(grid, foe, me, ...)
# preserves player order (A resolves before B on ties) exactly as in a real turn.
static func _score(me: Combatant, foe: Combatant, grid: Grid, my_seq: Array, foe_seq: Array) -> float:
	var out := Resolver.resolve(grid, foe, me, foe_seq, my_seq, 0)
	var foe_after: Combatant = out["a"]
	var me_after: Combatant = out["b"]
	var dealt := float(foe.hp - foe_after.hp)
	var taken := float(me.hp - me_after.hp)
	var s := dealt * W_DEAL - taken * W_TAKE
	match String(out["result"]):
		"b_wins": s += W_WIN
		"a_wins": s -= W_WIN
	s += float(me_after.energy + me_after.mp) * W_RES
	s -= float(Grid.dist(me_after.pos, foe_after.pos)) * W_DIST
	return s

# Bounded set of candidate sequences: each sensible first action alone, paired
# with each sensible second action (judged from the projected state), plus Rest.
static func _candidates(me: Combatant, foe: Combatant, grid: Grid) -> Array:
	var seqs: Array = [[{"id": "rest"}]]
	for a1 in _slot_actions(me, foe, grid):
		seqs.append([a1])
		var proj := me.clone()
		StubOpponent._apply_projection(proj, a1)
		for a2 in _slot_actions(proj, foe, grid):
			seqs.append([a1, a2])
	return seqs

# Sensible actions for one slot from a given state. Generic over spells (reads
# shape/needs_tile), so it works for whatever gear is equipped.
static func _slot_actions(c: Combatant, foe: Combatant, grid: Grid) -> Array:
	var acts: Array = []
	var dist := Grid.dist(c.pos, foe.pos)

	var toward := StubOpponent._step_toward(c, foe, grid)
	if toward != c.pos and c.energy >= Config.effective_move_cost(c.facing, c.pos, toward, c.statuses):
		acts.append({"id": "move", "tile": toward})

	var away := _step_away(c, foe, grid)
	if away != c.pos and c.energy >= Config.effective_move_cost(c.facing, c.pos, away, c.statuses):
		acts.append({"id": "move", "tile": away})

	if dist == 1 and Config.can_afford(c.energy, c.mp, c.statuses, "attack"):
		acts.append({"id": "attack", "tile": foe.pos})

	var face := _facing_toward(c.pos, foe.pos)
	if face != c.facing:
		acts.append({"id": "pivot", "facing": face})

	if Config.can_afford(c.energy, c.mp, c.statuses, "guard"):
		acts.append({"id": "guard"})

	for sid in c.spell_ids():
		if not StubOpponent._can_use(c, sid):
			continue
		var d := Config.def(sid)
		if d.get("needs_tile", false):
			if StubOpponent._clear_line(c, foe, grid, int(d.get("range", 1))):
				acts.append({"id": sid, "tile": foe.pos})
		else:
			acts.append({"id": sid})

	acts.append({"id": "wait"})
	return acts

# A legal neighbour that increases distance from the foe (kiting step).
static func _step_away(c: Combatant, foe: Combatant, grid: Grid) -> Vector2i:
	var best := c.pos
	var best_d := Grid.dist(c.pos, foe.pos)
	for dv in DIRS:
		var p: Vector2i = c.pos + dv
		if not grid.in_bounds(p) or grid.is_blocked(p) or p == foe.pos:
			continue
		var nd := Grid.dist(p, foe.pos)
		if nd > best_d:
			best_d = nd
			best = p
	return best

# Cardinal facing pointing at the foe (dominant axis; +y is south).
static func _facing_toward(from: Vector2i, to: Vector2i) -> int:
	var d := to - from
	if absi(d.x) >= absi(d.y):
		return Config.Facing.EAST if d.x >= 0 else Config.Facing.WEST
	return Config.Facing.SOUTH if d.y >= 0 else Config.Facing.NORTH
