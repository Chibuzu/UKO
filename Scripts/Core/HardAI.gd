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
const W_LOCK   := 0.25   # penalty per energy point below lockout (rescaled from 0.6: it was
						 # dwarfing a whole attack and making the AI hoard energy / turtle)
const LOCK_THRESH := 30  # below this you can't even guard (30) -- options-starved
const W_FLANK  := 6.0    # value of flank geometry, scaled by (FLANK_MULT-1) and proximity
const W_TEMPO  := 1.0    # initiative edge. Cut from 4.0: WAIT/guard grant speed_boost, so a
						 # big tempo bonus let the AI farm +score by doing nothing (passive).
const W_PRESS  := 5.0    # reward for closing on a low-hp foe (deny kiting/free rest)
const PRESS_HP := 40     # foe hp at/below which we actively press
const W_MOBILITY := 1.2  # MAP awareness: free adjacent tiles (escape routes) mine minus foe's;
						 # rewards keeping options open and cornering the foe against walls/edges
const LOW_HP   := 35     # at/below this hp, value survival/disengagement
const W_SURVIVE := 6.0   # when low, penalise being close to the foe (make space to heal)
const ADAPT    := 0.5    # how much to trust observed foe behaviour vs the rational model [0..1]
const MIX_MARGIN := 4.0  # only moves within this of the best may be sampled (keeps it strong)
const MIX_TEMP   := 2.5   # softmax temp among near-best moves -> unpredictable without throwing games

static func choose_sequence(me: Combatant, foe: Combatant, grid: Grid, spells: Array, opp_model = null) -> Array:
	# Unconditional one-liner (NOT behind DEBUG): if this never prints in the editor's
	# Output panel when you pick Hard, choose_sequence isn't being called -> the problem
	# is routing/menu, not the eval.
	print("[HardAI] running")
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

	# 3b: ADAPT. Blend in what the foe has ACTUALLY been doing recently, so we stop
	# assuming the textbook-best move and notice e.g. that they switched to resting.
	# Empirical weight per candidate = mean recent frequency of its actions'
	# categories; mixed with the rational distribution. Both sum to 1, so does the mix.
	if opp_model != null and opp_model.is_warm():
		var emp: Array = []
		var esum := 0.0
		for e in scored:
			var w := _emp_weight(e["seq"], opp_model)
			emp.append(w)
			esum += w
		if esum > 0.0:
			for i in scored.size():
				var p_emp: float = float(emp[i]) / esum
				scored[i]["p"] = (1.0 - ADAPT) * float(scored[i]["p"]) + ADAPT * p_emp

	# 4: keep the top-K most-likely foe moves, renormalise.
	scored.sort_custom(func(x, y): return float(x["p"]) > float(y["p"]))
	if scored.size() > TOP_K:
		scored = scored.slice(0, TOP_K)
	var zk := 0.0
	for e in scored:
		zk += float(e["p"])
	for e in scored:
		e["p"] = float(e["p"]) / zk

	# 5: expected score over MY candidates, then MIX among the near-best so the AI
	# isn't a deterministic puppet you can read and rest out. Challenging's pick is
	# kept as a floor candidate.
	var cands: Array = []
	var floor_seq: Array = ChallengingAI.choose_sequence(me, foe, grid, spells)
	cands.append({"seq": floor_seq, "ex": _expected(me, foe, grid, floor_seq, scored)})
	for my_seq in ChallengingAI._candidates(me, foe, grid):
		if my_seq.is_empty():
			continue
		cands.append({"seq": my_seq, "ex": _expected(me, foe, grid, my_seq, scored)})

	var pick: Dictionary = _mix_pick(cands)
	if DEBUG:
		_dump(scored, pick["seq"], float(pick["ex"]))
	return pick["seq"]

# Pick among the near-best candidates by softmax-sampling, so closely-matched moves
# vary turn to turn instead of always the same argmax (which you can read and rest
# out). Moves more than MIX_MARGIN below the best are never chosen, so strength
# holds; among the rest, better moves are likelier. Nondeterministic by design.
static func _mix_pick(cands: Array) -> Dictionary:
	if cands.is_empty():
		return {"seq": [{"id": "rest"}], "ex": 0.0}
	var bex := -INF
	for c in cands:
		bex = maxf(bex, float(c["ex"]))
	var pool: Array = []
	var z := 0.0
	for c in cands:
		if float(c["ex"]) >= bex - MIX_MARGIN:
			var w: float = exp((float(c["ex"]) - bex) / MIX_TEMP)
			c["w"] = w
			z += w
			pool.append(c)
	if pool.is_empty() or z <= 0.0:
		return cands[0]
	var r := randf() * z
	var acc := 0.0
	for c in pool:
		acc += float(c["w"])
		if r <= acc:
			return c
	return pool[pool.size() - 1]

# Mean recent frequency of the action categories in a foe candidate sequence --
# the empirical (observed-behaviour) weight used by the ADAPT blend.
static func _emp_weight(seq: Array, opp_model) -> float:
	if seq.is_empty():
		return 0.0
	var s := 0.0
	for action in seq:
		s += opp_model.freq(OpponentModel.category_of(action))
	return s / float(seq.size())

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
	# Self-preservation: when I'm low, being close to the foe is dangerous --
	# reward making space so I can disengage and rest instead of trading blows.
	if me.hp <= LOW_HP:
		v -= W_SURVIVE * prox
	# MAP awareness: escape routes. Free orthogonal tiles I can step to minus the
	# foe's. Being cornered against walls/edges (few free tiles) is bad; pinning
	# the foe against them is good.
	v += W_MOBILITY * float(_mobility(me, foe, grid) - _mobility(foe, me, grid))
	return v

# Count of free orthogonal tiles `c` could step to: in bounds, not a wall, not
# the other fighter. A read of how boxed-in this fighter is on the current map.
static func _mobility(c: Combatant, other: Combatant, grid: Grid) -> int:
	var n := 0
	for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		var p: Vector2i = c.pos + d
		if grid.in_bounds(p) and not grid.is_blocked(p) and other.pos != p:
			n += 1
	return n

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
