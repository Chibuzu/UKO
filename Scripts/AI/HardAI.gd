# HardAI.gd
# The "Hard" brain, rebuilt as a STRATEGIST. The old version predicted the foe's
# single most-likely move and countered it, which collapsed whenever the guess was
# even slightly off (guarding a foe that can't reach, resting in melee, bursting
# out of range). This version doesn't guess one move. For each of my candidate
# sequences it asks: "against the foe's BEST possible reply, where does this leave
# me?" -- then reads the resulting SITUATION through ThreatModel: how much damage
# I'm actually exposed to, how much I actually threaten, and who is winning the
# resource war. It plays the board and both players' resources, not a prediction.
#
# Pipeline (all combat through the real Resolver; candidate generation + scoring
# reused from the shared AIToolkit / Eval modules -- no duplicated rules):
#   1. Enumerate my candidate sequences (+ Challenging's pick as a floor).
#   2. Enumerate the foe's feasible replies.
#   3. Each of my moves is valued by its WORST outcome over the foe's replies
#      (minimax / robust): the transition (damage, win) plus the shared
#      situational eval (Eval) of the resulting position. Assuming the foe replies well is safe and un-brittle.
#   4. Mix among the near-best of my moves so I'm not a readable, rest-it-out puppet.
# Aggression is preserved not by assuming the foe is passive, but by the leaf:
# threatening positions and a winning resource race score well even under the
# foe's best reply.
class_name HardAI
extends RefCounted

const DEBUG := false   # print each move's robust value + the pick (in-engine check)

# Scoring (transition weights + the per-pair scorer) lives in Eval.gd, shared with
# Extreme so both reason about the same game. What's left here is HARD's DECISION
# RULE -- how it USES that scorer:
const RISK     := 0.5          # 1.0 = pure worst-case (paranoid/passive); 0 = average case.
							   # 0.5 = robust but engages; a move that loses outright still has a
							   # catastrophic worst case (W_WIN), so this never walks into a kill.
const MIX_MARGIN := 2.5        # only moves within this of the best may be sampled (was 4: too wide,
							   # let wasteful moves leak in when nothing productive scored high)
const MIX_TEMP   := 2.5        # softmax temp among near-best moves -> unpredictable, not self-sabotaging

static func choose_sequence(me: Combatant, foe: Combatant, grid: Grid, spells: Array, opp_model = null) -> Array:
	if DEBUG:
		print("[HardAI] running")
	# 1-2: my candidate moves (Challenging's pick floored in) and the foe's replies.
	var foe_cands: Array = AIToolkit.candidates(foe, me, grid)
	var my_cands: Array = [ChallengingAI.choose_sequence(me, foe, grid, spells)]
	for s in AIToolkit.candidates(me, foe, grid):
		if not s.is_empty():
			my_cands.append(s)

	# 3: value each of my moves by its WORST outcome over the foe's feasible replies.
	var scored: Array = []
	for my_seq in my_cands:
		scored.append({"seq": my_seq, "ex": _robust_value(me, foe, grid, my_seq, foe_cands)})

	# 4: mix among the near-best so the AI isn't a deterministic, readable puppet.
	var pick: Dictionary = _mix_pick(scored)
	if DEBUG:
		_dump(scored, pick)
	return pick["seq"]

# Robust value of my_seq: the foe replies with whatever is WORST for me, so take the
# minimum score across its feasible replies. Pure prediction-free danger assessment.
static func _robust_value(me: Combatant, foe: Combatant, grid: Grid, my_seq: Array, foe_cands: Array) -> float:
	var worst := INF
	var total := 0.0
	var n := 0
	for foe_seq in foe_cands:
		if foe_seq.is_empty():
			continue
		var sc := Eval.score_rich(me, foe, grid, my_seq, foe_seq)
		worst = minf(worst, sc)
		total += sc
		n += 1
	if n == 0:                                     # foe had no candidates: score vs a rest
		return Eval.score_rich(me, foe, grid, my_seq, [{"id": "rest"}])
	var mean := total / float(n)
	# Robust but not paranoid: mostly the worst case (safety), partly the average,
	# so a strong move isn't killed by a single unlikely counter (less passive).
	return RISK * worst + (1.0 - RISK) * mean


# Sample among the near-best of my moves so closely-matched choices vary turn to
# turn instead of always the same argmax (which you can read and rest out). Moves
# more than MIX_MARGIN below the best are never chosen, so strength holds.
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

static func _dump(scored: Array, pick: Dictionary) -> void:
	print("[HardAI] move values (robust = worst-case foe reply):")
	for e in scored:
		print("   v=%.1f  %s" % [float(e["ex"]), str(e["seq"])])
	print("[HardAI] pick = %s" % str(pick["seq"]))
