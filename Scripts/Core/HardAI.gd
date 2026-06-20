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
# Pipeline (all combat through the real Resolver; candidate generation reused from
# ChallengingAI -- no duplicated rules):
#   1. Enumerate my candidate sequences (+ Challenging's pick as a floor).
#   2. Enumerate the foe's feasible replies.
#   3. Each of my moves is valued by its WORST outcome over the foe's replies
#      (minimax / robust): the transition (damage, win) plus _eval_situation of the
#      resulting position. Assuming the foe replies well is safe and un-brittle.
#   4. Mix among the near-best of my moves so I'm not a readable, rest-it-out puppet.
# Aggression is preserved not by assuming the foe is passive, but by the leaf:
# threatening positions and a winning resource race score well even under the
# foe's best reply.
class_name HardAI
extends RefCounted

const DEBUG := false   # print each move's robust value + the pick (in-engine check)

# Transition weights (damage/win) come from ChallengingAI: W_DEAL / W_TAKE / W_WIN.
# Situational weights value what raw damage can't see -- exposure, threat, the
# resource race, tempo, space. [all tunable]
const W_ENERGY := 0.08         # own-minus-foe energy
const W_MP     := 0.05         # own-minus-foe mp (gates spells)
const W_LOCK   := 0.25         # ramp per energy point below the lockout threshold
const LOCK_THRESH := 30        # below this you can't even guard (30) -- options-starved
const W_DANGER_MELEE := 0.5    # penalty per pt of BLOCKABLE (melee) damage I'm exposed to next turn
const W_DANGER_SPELL := 0.6    # per pt of UNBLOCKABLE (spell) damage -- scarier; a guard can't help
const W_PRESSURE     := 0.45   # reward per pt of damage I can actually threaten on the foe from here
const W_ATTRITION    := 8.0    # foe can't even attack (energy < cost) while I can -> winning the war
const W_TEMPO  := 0.3          # carried speed boost (successful guard). Cut from 1.0: it was
							   # enough to make a pointless guard look worthwhile.
const W_MOBILITY := 1.5        # free escape tiles, mine minus the foe's (don't get cornered)
const W_PRESS  := 0.2          # when I'm HP-ahead, reward closing in to convert the lead
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
	var foe_cands: Array = ChallengingAI._candidates(foe, me, grid)
	var my_cands: Array = [ChallengingAI.choose_sequence(me, foe, grid, spells)]
	for s in ChallengingAI._candidates(me, foe, grid):
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
		var sc := _score_rich(me, foe, grid, my_seq, foe_seq)
		worst = minf(worst, sc)
		total += sc
		n += 1
	if n == 0:                                     # foe had no candidates: score vs a rest
		return _score_rich(me, foe, grid, my_seq, [{"id": "rest"}])
	var mean := total / float(n)
	# Robust but not paranoid: mostly the worst case (safety), partly the average,
	# so a strong move isn't killed by a single unlikely counter (less passive).
	return RISK * worst + (1.0 - RISK) * mean

# Transition + situation for my_seq vs one foe reply, MY perspective. Same
# A=foe / B=me resolve order as the live game so tie-breaks stay correct.
static func _score_rich(me: Combatant, foe: Combatant, grid: Grid, my_seq: Array, foe_seq: Array) -> float:
	var out := Resolver.resolve(grid, foe, me, foe_seq, my_seq, 0)
	var foe_after: Combatant = out["a"]
	var me_after: Combatant = out["b"]
	var dealt := float(foe.hp - foe_after.hp)
	var taken := float(me.hp - me_after.hp)        # negative if I healed (rest)
	var s := dealt * ChallengingAI.W_DEAL - taken * ChallengingAI.W_TAKE
	match String(out["result"]):
		"b_wins": s += ChallengingAI.W_WIN
		"a_wins": s -= ChallengingAI.W_WIN
	s += _eval_situation(me_after, foe_after, grid)
	return s

# Value of the resulting position from `me`'s side. The heart of the strategist:
# it reads what each side can ACTUALLY do next turn (ThreatModel), not geometry in
# the abstract -- so guarding a foe that can't reach, or resting in melee, or
# ending flank-exposed all score badly because the threat math says so.
static func _eval_situation(me: Combatant, foe: Combatant, grid: Grid) -> float:
	var v := 0.0

	# Resources: differential, plus a ramp near the energy lockout. Discount the
	# lockout when the shared regen pulse is imminent (both refill soon).
	v += W_ENERGY * float(me.energy - foe.energy)
	v += W_MP * float(me.mp - foe.mp)
	var to_pulse: int = Config.ENERGY_PULSE_ACTIONS - (me.action_count % Config.ENERGY_PULSE_ACTIONS)
	var relief: float = 1.0
	if to_pulse <= 1:
		relief = 0.45
	elif to_pulse <= 2:
		relief = 0.7
	v -= W_LOCK * float(maxi(0, LOCK_THRESH - me.energy)) * relief
	v += W_LOCK * float(maxi(0, LOCK_THRESH - foe.energy)) * relief

	# Threat, both ways. danger = what the foe can land on me from here (split by
	# whether a guard could stop it); pressure = what I can land on the foe. This
	# is the term that makes facing matter (a side/back exposure raises the foe's
	# blockable damage), that makes a rest-in-melee position bad, and that keeps me
	# aggressive (ending in a position that threatens the foe is rewarded).
	var danger := ThreatModel.incoming(foe, me, grid)
	var mine := ThreatModel.incoming(me, foe, grid)
	v -= W_DANGER_MELEE * float(danger["blockable"]) + W_DANGER_SPELL * float(danger["unblockable"])
	v += W_PRESSURE * float(int(mine["blockable"]) + int(mine["unblockable"]))

	# Attrition: a foe who can't even afford to attack while I still can is losing
	# the resource war -- worth pressing, and worth trading some HP to reach.
	var foe_starved := foe.energy < Config.COST_ATTACK
	var me_starved := me.energy < Config.COST_ATTACK
	if foe_starved and not me_starved:
		v += W_ATTRITION
	elif me_starved and not foe_starved:
		v -= W_ATTRITION

	# Convert a lead: when I'm ahead on HP, reward closing the distance so I press a
	# hurt foe toward the kill instead of sitting safe and letting it rest back. This
	# is the counterweight to the worst-case view's instinct to never engage.
	var hp_adv := float(me.hp - foe.hp)
	if hp_adv > 0.0:
		var prox := 1.0 / float(1 + Grid.dist(me.pos, foe.pos))
		v += W_PRESS * hp_adv * prox

	# Initiative + space (light).
	if me.speed_boost and not foe.speed_boost:
		v += W_TEMPO
	elif foe.speed_boost and not me.speed_boost:
		v -= W_TEMPO
	v += W_MOBILITY * float(_mobility(me, foe, grid) - _mobility(foe, me, grid))
	return v

# Free orthogonal tiles `c` could step to (in bounds, not a wall, not the other
# fighter): a read of how boxed-in it is.
static func _mobility(c: Combatant, other: Combatant, grid: Grid) -> int:
	var n := 0
	for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		var p: Vector2i = c.pos + d
		if grid.in_bounds(p) and not grid.is_blocked(p) and other.pos != p:
			n += 1
	return n

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
