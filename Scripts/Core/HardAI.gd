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

const TEMP := 15.0   # softmax temperature. HIGH = hedge broadly across foe moves. [tune]
const TOP_K := 12    # how many most-likely foe moves to keep for the expectation. [perf/tune]
const DEBUG := false # print the foe distribution + chosen line (in-engine verification)

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

# Expected score of my_seq over the foe distribution. Reuses ChallengingAI._score
# (my perspective; its internal resolve keeps the live A=foe / B=me order).
static func _expected(me: Combatant, foe: Combatant, grid: Grid, my_seq: Array, dist: Array) -> float:
	var s := 0.0
	for e in dist:
		s += float(e["p"]) * ChallengingAI._score(me, foe, grid, my_seq, e["seq"])
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
	s += float(foe_after.energy + foe_after.mp) * ChallengingAI.W_RES
	s -= float(Grid.dist(me_after.pos, foe_after.pos)) * ChallengingAI.W_DIST
	return s

static func _dump(dist: Array, pick: Array, ex: float) -> void:
	print("[HardAI] modeled foe distribution (top %d):" % dist.size())
	for e in dist:
		print("   p=%.3f  q=%.1f  %s" % [float(e["p"]), float(e["q"]), str(e["seq"])])
	print("[HardAI] pick = %s   E[score] = %.2f" % [str(pick), ex])
