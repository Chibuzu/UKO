# Eval.gd
# Shared EVALUATION substrate for the searching brains. HARD and EXTREME must answer
# the same question -- "if I play my_seq and the foe plays foe_seq, how good is the
# resulting position for me?" -- and must answer it IDENTICALLY, or the robust argmax
# (Hard) and the equilibrium mix (Extreme) would be scoring different games. That
# per-pair scorer lives here, owned once, so both brains call the same code; each
# keeps only its DECISION RULE (Hard: robust blend; Extreme: Nash mix).
#
# Pure / static. Combat runs through the real Resolver; threats through ThreatModel.
class_name Eval
extends RefCounted

# ── Transition weights (the raw outcome of the turn) ──────────────────────
const W_DEAL := 1.0      # value of damage dealt to the foe
const W_TAKE := 1.25     # cost of damage taken (slightly > dealt: prefer not trading down)
const W_WIN := 1000.0    # winning / losing the duel dominates everything

# ── Situational weights (what raw damage can't see: exposure, threat, the ──
# resource race, tempo, space). [all tunable]
const W_ENERGY := 0.08         # own-minus-foe energy
const W_MP     := 0.05         # own-minus-foe mp (gates spells)
const W_LOCK   := 0.25         # ramp per energy point below the lockout threshold
const LOCK_THRESH := 30        # below this you can't even guard (30) -- options-starved
const W_DANGER_MELEE := 0.5    # penalty per pt of BLOCKABLE (melee) damage I'm exposed to next turn
const W_DANGER_SPELL := 0.6    # per pt of UNBLOCKABLE (spell) damage -- scarier; a guard can't help
const W_PRESSURE     := 0.45   # reward per pt of damage I can actually threaten on the foe from here
const W_ATTRITION    := 8.0    # foe can't even attack (energy < cost) while I can -> winning the war
const W_TEMPO  := 0.3          # carried speed boost (successful guard)
const W_MOBILITY := 1.5        # free escape tiles, mine minus the foe's (don't get cornered)
const W_PRESS  := 0.2          # when I'm HP-ahead, reward closing in to convert the lead

# Transition + situation for my_seq vs one foe reply, MY perspective. Same
# A=foe / B=me resolve order as the live game so tie-breaks stay correct.
static func score_rich(me: Combatant, foe: Combatant, grid: Grid, my_seq: Array, foe_seq: Array) -> float:
	var out := Resolver.resolve(grid, foe, me, foe_seq, my_seq, 0)
	var foe_after: Combatant = out["a"]
	var me_after: Combatant = out["b"]
	var dealt := float(foe.hp - foe_after.hp)
	var taken := float(me.hp - me_after.hp)        # negative if I healed (rest)
	var s := dealt * W_DEAL - taken * W_TAKE
	match String(out["result"]):
		"b_wins": s += W_WIN
		"a_wins": s -= W_WIN
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
