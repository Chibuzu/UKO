# HardAI.gd
# The "Hard" brain. Where Challenging best-responds to ONE assumed enemy move,
# Hard models a DISTRIBUTION over the foe's plausible moves and maximises its
# EXPECTED score across that distribution -- so it can't be exploited by a foe
# who simply doesn't play the move Challenging assumed.
#
# Pipeline (all combat goes through the real Resolver, reusing ChallengingAI's
# candidate generator and scorer -- no duplicated rules math):
#   1. Enumerate the foe's plausible sequences (ChallengingAI._candidates, run
#      from the foe's side).
#   2. Score each FROM THE FOE'S SIDE vs my likely (Stub) move -- depth 1, no
#      regress.
#   3. Turn those scores into a probability distribution with a numerically
#      stable, HIGH-temperature softmax (broad hedging; a foe move that WINS
#      still dominates, as it should -- assume a kill gets taken).
#   4. Keep the top-K most-likely foe moves (perf) and renormalise.
#   5. For each of MY candidate sequences, compute the EXPECTED score over that
#      distribution and pick the argmax. Loss-aversion already lives in
#      W_TAKE > W_DEAL, so this is pure expected value -- no extra risk term.
#   6. Floor: never play below Challenging's own pick (evaluated in expectation).
#
# Difficulty axis: TEMP is the dial. EXTREME (later) replaces step 3-5 with a
# full payoff-matrix solve (minimax/Nash); the matrix is exactly the by-product
# of the inner loop here.
class_name HardAI
extends RefCounted

const TEMP := 6.0    # softmax temperature. Lowered from 15: high temp hedged so broadly it
					 # never committed to a punish (passive). 6 commits to your stronger moves
					 # while still mixing a little. [tune: lower = sharper/more aggressive]
const TOP_K := 12    # how many most-likely foe moves to keep for the expectation. [perf/tune]
const DEBUG := false # print the foe distribution + chosen line (in-engine verification)

# Position-eval weights. The transition (damage/win) is scored separately; these
# value what damage alone can't see -- resources, geometry, tempo. [all tunable]
const W_ENERGY := 0.08   # value of own energy minus foe's (replaces the near-zero W_RES)
const W_MP     := 0.05   # value of own mp minus foe's (mp gates spells)
const W_LOCK   := 0.6    # extra penalty per energy point below the lockout threshold
const LOCK_THRESH := 30  # below this you can't even guard (30) -- options-starved
const W_FLANK  := 6.0    # value of flank geometry, scaled by (FLANK_MULT-1) and proximity
const W_TEMPO  := 4.0    # initiative edge (acting first next turn via speed_boost)
const W_PRESS  := 5.0    # reward for closing on a low-hp foe (deny kiting/free rest)
const PRESS_HP := 40     # foe hp at/below which we actively press

static func choose_sequence(me: Combatant, foe: Combatant, grid: Grid, spells: Array) -> Array:
	# My assumed move -- used (depth 1) to judge how good each foe move is FOR THE FOE.
	var my_stub: Array = StubOpponent.choose_sequence(me, foe, grid, spells)

	# 1-2: enumerate the foe's plausible sequences, score each from the foe's side.
	var scored: Array = []     # entries: { "seq": Array, "q": float, "p": float }
	for fseq in ChallengingAI._candidates(foe, me, grid):
		if fseq.is_empty():
			continue
		scored.append({"seq": fseq, "q": _foe_score(foe, me, grid, fseq, my_stub)})
	if scored.is_empty():
		return ChallengingAI.choose_sequence(me, foe, grid, spells)   # nothing to model; defer

	# 3: numerically stable high-temperature softmax over foe quality.
	var qmax := -INF
	for e in scored:
		qmax = maxf(qmax, float(e["q"]))
	var z := 0.0
	for e in scored:
		e["p"] = exp((float(e["q"]) - qmax) / TEMP)   # subtract max -> no overflow with +-W_WIN
		z += float(e["p"])
	for e in scored:
		e["p"] = float(e["p"]) / z

	# 4: keep the top-K most-likely foe moves, renormalise.
	scored.sort_custom(func(x, y): return float(x["p"]) > float(y["p"]))
	if scored.size() > TOP_K:
		scored = scored.slice(0, TOP_K)
	var zk := 0.0
	for e in scored:
		zk += float(e["p"])
	for e in scored:
		e["p"] = float(e["p"]) / zk

	# 5: expected-score argmax over MY candidates. Challenging's pick is the floor.
	var best: Array = ChallengingAI.choose_sequence(me, foe, grid, spells)
	var best_exp := _expected(me, foe, grid, best, scored)
	for my_seq in ChallengingAI._candidates(me, foe, grid):
		if my_seq.is_empty():
			continue
		var ex := _expected(me, foe, grid, my_seq, scored)
		if ex > best_exp:
			best_exp = ex
			best = my_seq

	if DEBUG:
		_dump(scored, best, best_exp)
	return best

# Expected score of my_seq over the foe distribution, using the position-aware
# scorer (transition + _eval_position), so the AI values where it ends up, not
# just the damage it traded this turn.
static func _expected(me: Combatant, foe: Combatant, grid: Grid, my_seq: Array, dist: Array) -> float:
	var s := 0.0
	for e in dist:
		s += float(e["p"]) * _score_rich(me, foe, grid, my_seq, e["seq"])
	return s

# Score a foe sequence FROM THE FOE'S SIDE, vs my assumed move, using the SAME
# A=foe / B=me resolve order as the live game so tie-breaks stay correct. Mirrors
# ChallengingAI._score with the perspective flipped.
static func _foe_score(foe: Combatant, me: Combatant, grid: Grid, foe_seq: Array, my_seq: Array) -> float:
	var out := Resolver.resolve(grid, foe, me, foe_seq, my_seq, 0)
	var foe_after: Combatant = out["a"]
	var me_after: Combatant = out["b"]
	var foe_dealt := float(me.hp - me_after.hp)
	var foe_taken := float(foe.hp - foe_after.hp)
	var s := foe_dealt * ChallengingAI.W_DEAL - foe_taken * ChallengingAI.W_TAKE
	match String(out["result"]):
		"a_wins": s += ChallengingAI.W_WIN
		"b_wins": s -= ChallengingAI.W_WIN
	s += _eval_position(foe_after, me_after, grid)   # foe's perspective: it wants position too
	return s

# Position-aware score of my_seq vs one foe move, MY perspective. Transition
# (damage dealt/taken/win) plus the position value of where it leaves both of us.
# Same A=foe / B=me resolve order as the live game so tie-breaks stay correct.
static func _score_rich(me: Combatant, foe: Combatant, grid: Grid, my_seq: Array, foe_seq: Array) -> float:
	var out := Resolver.resolve(grid, foe, me, foe_seq, my_seq, 0)
	var foe_after: Combatant = out["a"]
	var me_after: Combatant = out["b"]
	var dealt := float(foe.hp - foe_after.hp)
	var taken := float(me.hp - me_after.hp)   # negative if I healed (e.g. via rest)
	var s := dealt * ChallengingAI.W_DEAL - taken * ChallengingAI.W_TAKE
	match String(out["result"]):
		"b_wins": s += ChallengingAI.W_WIN
		"a_wins": s -= ChallengingAI.W_WIN
	s += _eval_position(me_after, foe_after, grid)
	return s

# Value of a position from `me`'s side: resources (non-linear near the energy
# lockout), flank geometry both ways, initiative, and pressure on a low-hp foe.
static func _eval_position(me: Combatant, foe: Combatant, grid: Grid) -> float:
	var v := 0.0
	# Resource economy, both sides. Energy near 0 is far worse than linear (you
	# lose attack/guard/move), so add a ramp below the lockout threshold.
	v += W_ENERGY * float(me.energy - foe.energy)
	v += W_MP * float(me.mp - foe.mp)
	v -= W_LOCK * float(maxi(0, LOCK_THRESH - me.energy))    # I'm options-starved
	v += W_LOCK * float(maxi(0, LOCK_THRESH - foe.energy))   # foe is -> press the attack
	# Flank geometry: reward sitting on the foe's exposed side/back, penalise
	# exposing my own. Weighted by proximity (only matters when reachable).
	var prox := 1.0 / float(1 + Grid.dist(me.pos, foe.pos))
	v += W_FLANK * (float(Config.FLANK_MULT[_flank_tier(foe, me.pos)]) - 1.0) * prox
	v -= W_FLANK * (float(Config.FLANK_MULT[_flank_tier(me, foe.pos)]) - 1.0) * prox
	# Initiative: acting first next turn is a real edge in a simultaneous game.
	if me.speed_boost and not foe.speed_boost:
		v += W_TEMPO
	elif foe.speed_boost and not me.speed_boost:
		v -= W_TEMPO
	# Pressure: when the foe is low and wants to kite/rest, reward closing so it
	# can't heal for free (the failure where it let you rest to full).
	if foe.hp <= PRESS_HP:
		v += W_PRESS * prox
	return v

# Which face of `defender` the tile `at` sits on, relative to its facing:
# "front" / "side" / "back" (back = the ×2.0 flank).
static func _flank_tier(defender: Combatant, at: Vector2i) -> String:
	var o: Vector2i = at - defender.pos
	if o == Vector2i.ZERO:
		return "front"
	var fv: Vector2i = Config.FACING_VEC[defender.facing]
	var step := Vector2i(signi(o.x), 0) if absi(o.x) >= absi(o.y) else Vector2i(0, signi(o.y))
	if step == fv:
		return "front"
	if step == -fv:
		return "back"
	return "side"

static func _dump(dist: Array, pick: Array, ex: float) -> void:
	print("[HardAI] modeled foe distribution (top %d):" % dist.size())
	for e in dist:
		print("   p=%.3f  q=%.1f  %s" % [float(e["p"]), float(e["q"]), str(e["seq"])])
	print("[HardAI] pick = %s   E[score] = %.2f" % [str(pick), ex])
