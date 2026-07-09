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
static var W_DEAL := 1.0      # value of damage dealt to the foe
static var W_TAKE := 1.25     # cost of damage taken (slightly > dealt: prefer not trading down)
const W_WIN := 1000.0    # winning / losing the duel dominates everything

# ── Situational weights (what raw damage can't see: exposure, threat, the ──
# resource race, tempo, space). [all tunable]
static var W_ENERGY := 0.08         # own-minus-foe energy
static var W_MP     := 0.05         # own-minus-foe mp (gates spells)
static var W_LOCK   := 0.25         # ramp per energy point below the lockout threshold
const LOCK_THRESH := 30        # below this you can't even guard (30) -- options-starved
static var W_DANGER_MELEE := 0.5    # penalty per pt of BLOCKABLE (melee) damage I'm exposed to next turn
static var W_DANGER_SPELL := 0.6    # per pt of UNBLOCKABLE (spell) damage -- scarier; a guard can't help
static var W_PRESSURE     := 0.45   # reward per pt of damage I can actually threaten on the foe from here
static var W_ATTRITION    := 8.0    # foe can't even attack (energy < cost) while I can -> winning the war
static var W_TEMPO  := 0.3          # carried speed boost (successful guard)
static var W_MOBILITY := 1.5        # free escape tiles, mine minus the foe's (don't get cornered)
static var W_PRESS  := 0.2          # when I'm HP-ahead, reward closing in to convert the lead
static var W_INCOMING := 6.0        # standing where the telegraph says a wall / zone ring lands next
static var W_CENTER   := 0.5        # per ring of edge-depth advantage once the zone is closing
static var W_ITEM     := 2.0        # an unspent grenade is a standing threat (option value)
static var W_LETHAL   := 2.5        # danger multiplier when the foe's incoming can KILL me outright --
									#   at one hit from death, exposure is the match, not a cost

# ── Lookahead (EXTREME's depth-2 search) [all tunable] ────────────────────
const LOOKAHEAD_DEPTH := 2   # turns EXTREME sees: 1 = shallow (this turn + heuristic);
							 #   2 = this turn + the SOLVED next-turn subgame. >2 gets costly fast.
const DEEP_CANDS := 3        # per-side candidate cap INSIDE a subgame node, so the
							 #   matrix-of-matrices stays bounded (the root never caps).
const DEEP_ITERS := 64       # regret iterations for subgame solves (tiny matrices converge fast)
static var DISCOUNT   := 0.9      # a future turn is worth slightly less than damage now

# ── Tunable-weights API (self-play tuner) + subgame cache ──────────────────
# The weights above are `static var` so the tuning harness can adjust them at
# runtime; the defaults reproduce shipped behaviour exactly.
# ── Win-probability calibration (fitted from self-play by CollectCalibration.gd).
# When CAL_A > 0, the brain's matrix payoffs become P(win): a monotone but
# NONLINEAR map, so equilibria shift exactly as they should -- ahead plays tight
# (little P(win) left to gain from risk), behind polarizes (only variance moves
# its number). This is the fear multiplier's job, derived from evidence.
static var CAL_A := 0.0
static func load_calibration() -> void:
	var cf := ConfigFile.new()
	CAL_A = float(cf.get_value("cal", "a", 0.0)) if cf.load("user://calibration.cfg") == OK else 0.0
static func to_winprob(score: float) -> float:
	return 1.0 / (1.0 + exp(-CAL_A * score))

# Snapshot of the hand-tuned defaults, so profiles can restore them at runtime.
static var DEFAULTS: Dictionary = {}
static func _static_init() -> void:
	DEFAULTS = get_weights()

const TUNABLE := ["W_DEAL", "W_TAKE", "W_ENERGY", "W_MP", "W_LOCK", "W_DANGER_MELEE",
	"W_DANGER_SPELL", "W_PRESSURE", "W_ATTRITION", "W_TEMPO", "W_MOBILITY", "W_PRESS",
	"W_INCOMING", "W_CENTER", "W_ITEM", "W_LETHAL", "DISCOUNT"]

static func get_weights() -> Dictionary:
	return {"W_DEAL": W_DEAL, "W_TAKE": W_TAKE, "W_ENERGY": W_ENERGY, "W_MP": W_MP,
		"W_LOCK": W_LOCK, "W_DANGER_MELEE": W_DANGER_MELEE, "W_DANGER_SPELL": W_DANGER_SPELL,
		"W_PRESSURE": W_PRESSURE, "W_ATTRITION": W_ATTRITION, "W_TEMPO": W_TEMPO,
		"W_MOBILITY": W_MOBILITY, "W_PRESS": W_PRESS, "W_INCOMING": W_INCOMING,
		"W_CENTER": W_CENTER, "W_ITEM": W_ITEM, "W_LETHAL": W_LETHAL, "DISCOUNT": DISCOUNT}

static func set_weights(w: Dictionary) -> void:
	for k in w:
		var v := float(w[k])
		match String(k):
			"W_DEAL": W_DEAL = v
			"W_TAKE": W_TAKE = v
			"W_ENERGY": W_ENERGY = v
			"W_MP": W_MP = v
			"W_LOCK": W_LOCK = v
			"W_DANGER_MELEE": W_DANGER_MELEE = v
			"W_DANGER_SPELL": W_DANGER_SPELL = v
			"W_PRESSURE": W_PRESSURE = v
			"W_ATTRITION": W_ATTRITION = v
			"W_TEMPO": W_TEMPO = v
			"W_MOBILITY": W_MOBILITY = v
			"W_PRESS": W_PRESS = v
			"W_INCOMING": W_INCOMING = v
			"W_CENTER": W_CENTER = v
			"W_ITEM": W_ITEM = v
			"W_LETHAL": W_LETHAL = v
			"DISCOUNT": DISCOUNT = v

# Per-decision transposition cache for solved subgame values. The same state is
# reached by many action orders inside one root decision, so caching its solved
# value multiplies how far a time budget reaches. Cleared by the brain per choice.
static var _sub_cache: Dictionary = {}
static func clear_cache() -> void:
	_sub_cache.clear()

# Transition + situation for my_seq vs one foe reply, MY perspective. Same
# A=foe / B=me resolve order as the live game so tie-breaks stay correct.
static func score_rich(me: Combatant, foe: Combatant, grid: Grid, my_seq: Array, foe_seq: Array) -> float:
	return score_deep(me, foe, grid, my_seq, foe_seq, 0)

# Depth-aware version. depth 0 = static leaf (identical to the old score_rich).
# depth > 0 REPLACES the static read of the resulting position with the VALUE of the
# next-turn subgame, solved as its own little equilibrium -- so EXTREME sees combos
# that take two turns to pay off (set-up -> burst, bait -> punish), not one turn + a guess.
static func score_deep(me: Combatant, foe: Combatant, grid: Grid, my_seq: Array, foe_seq: Array, depth: int) -> float:
	# Seat-correct forward model: simulate with the SAME seats as reality, so
	# within-tick tie-breaks are true for whichever chair this brain occupies.
	# (Hardcoding me-as-B was fine for the live AI -- it IS seat B -- but it
	# crippled every seat-A brain in self-play: validation exposed it by coming
	# back 10/10 seat-decided on fresh maps.)
	var out: Dictionary
	if me.id == "A":
		out = Resolver.resolve(grid, me, foe, my_seq, foe_seq, 0)
	else:
		out = Resolver.resolve(grid, foe, me, foe_seq, my_seq, 0)
	var me_a := me.id == "A"
	var foe_after: Combatant = out["b"] if me_a else out["a"]
	var me_after: Combatant = out["a"] if me_a else out["b"]
	var dealt := float(foe.hp - foe_after.hp)
	var taken := float(me.hp - me_after.hp)        # negative if I healed (rest)
	var s := dealt * W_DEAL - taken * W_TAKE
	var res := String(out["result"])
	var my_win := "a_wins" if me_a else "b_wins"
	if res == my_win:
		s += W_WIN
	elif res == "a_wins" or res == "b_wins":
		s -= W_WIN
	# Depth 0, or the duel already ended this turn -> static read of the result.
	if depth <= 0 or res == "a_wins" or res == "b_wins":
		return s + _eval_situation(me_after, foe_after, grid)
	# Deeper: the value of this position IS the equilibrium value of the next turn.
	return s + DISCOUNT * _subgame_value(me_after, foe_after, grid, depth)

# Maximin value of the next turn from this position, cached by state fingerprint.
static func _subgame_value(me: Combatant, foe: Combatant, grid: Grid, depth: int) -> float:
	var key := _state_key(me, foe, grid, depth)
	if _sub_cache.has(key):
		return float(_sub_cache[key])
	var v := _subgame_value_raw(me, foe, grid, depth)
	_sub_cache[key] = v
	return v

# Both sides pick fresh candidate sequences, we solve that small (capped) matrix,
# and return what `me` can guarantee.
static func _subgame_value_raw(me: Combatant, foe: Combatant, grid: Grid, depth: int) -> float:
	var my_c := _capped_cands(me, foe, grid)
	if my_c.is_empty():
		return _eval_situation(me, foe, grid)
	var foe_c := _capped_cands(foe, me, grid)
	if foe_c.is_empty():
		foe_c = [[{"id": "rest"}]]
	var M: Array = []
	for mc in my_c:
		var row: Array = []
		for fc in foe_c:
			row.append(score_deep(me, foe, grid, mc, fc, depth - 1))
		M.append(row)
	var mix := NashSolver.solve_iters(M, DEEP_ITERS)
	return NashSolver.value_of(M, mix)

# The DEEP_CANDS strongest candidate sequences for `me`, ranked by a cheap shallow
# score against a resting foe. An approximation that keeps subgame matrices small;
# the root decision (ExtremeAI) never caps, so fidelity is kept where it matters.
static func _capped_cands(me: Combatant, foe: Combatant, grid: Grid) -> Array:
	var clean: Array = []
	for c in AIToolkit.candidates(me, foe, grid):
		if not c.is_empty():
			clean.append(c)
	if clean.size() <= DEEP_CANDS:
		return clean
	var ranked: Array = []
	for c in clean:
		ranked.append({"seq": c, "v": _cheap_rank(me, foe, grid, c)})
	ranked.sort_custom(func(x, y): return float(x["v"]) > float(y["v"]))
	var out: Array = []
	for k in range(DEEP_CANDS):
		out.append(ranked[k]["seq"])
	return out

# Cheap ranking for subgame capping: project the sequence and read the threat both
# ways -- NO full turn sim. Coarser than score_deep but ~free, which is what lets
# the deeper search stay affordable.
static func _cheap_rank(me: Combatant, foe: Combatant, grid: Grid, seq: Array) -> float:
	var m := me.clone()
	for a in seq:
		AIToolkit.apply_projection(m, a)
	return ThreatModel.worst_damage(m, foe, grid) * W_DEAL - ThreatModel.worst_damage(foe, m, grid) * W_TAKE

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
	# Regen is PER-PLAYER: each side's lockout pain is discounted only when ITS OWN pulse
	# is imminent. The metronome is public (action counts), so the search prices dry
	# spells correctly on both sides -- and times aggression into the foe's.
	v -= W_LOCK * float(maxi(0, LOCK_THRESH - me.energy)) * _pulse_relief(me)
	v += W_LOCK * float(maxi(0, LOCK_THRESH - foe.energy)) * _pulse_relief(foe)

	# Threat, both ways. danger = what the foe can land on me from here (split by
	# whether a guard could stop it); pressure = what I can land on the foe. This
	# is the term that makes facing matter (a side/back exposure raises the foe's
	# blockable damage), that makes a rest-in-melee position bad, and that keeps me
	# aggressive (ending in a position that threatens the foe is rewarded).
	var danger := ThreatModel.incoming(foe, me, grid)
	var mine := ThreatModel.incoming(me, foe, grid)
	var dtot := int(danger["blockable"]) + int(danger["unblockable"])
	var lethal_mult := W_LETHAL if (dtot >= me.hp and me.hp > 0) else 1.0
	# Desperation aversion: incoming threat matters more the closer `me` is to
	# death (fear = 1.0 at full hp, ~2.2 near zero). Stopgap for win-prob scoring.
	var fear := 1.0 + 1.2 * (1.0 - float(me.hp) / float(Config.MAX_HP))
	v -= ((W_DANGER_MELEE * float(danger["blockable"]) + W_DANGER_SPELL * float(danger["unblockable"])) * lethal_mult) * fear
	v += W_PRESSURE * float(int(mine["blockable"]) + int(mine["unblockable"]))

	# Attrition: a foe who can't even afford to attack while I still can is losing
	# the resource war -- worth pressing, and worth trading some HP to reach.
	var foe_starved := foe.energy < Config.COST_ATTACK
	var me_starved := me.energy < Config.COST_ATTACK
	if foe_starved and not me_starved:
		v += W_ATTRITION
	elif me_starved and not foe_starved:
		v -= W_ATTRITION

	# The arena clock. Ending the turn where the amber telegraph says a wall or the
	# next zone ring lands is priced as real danger (crush + a forced move); and once
	# the zone is closing, depth toward the never-closing centre is worth fighting for.
	var iw := _incoming_set(grid)
	if iw.has(me.pos):
		v -= W_INCOMING
	if iw.has(foe.pos):
		v += W_INCOMING
	if grid.shrink_level > 0:
		v += W_CENTER * float(grid.shrink_level) * float(_edge_depth(me.pos) - _edge_depth(foe.pos))

	# Item option value: an unspent grenade poisons the foe's movement decisions all
	# game -- holding it is worth something even before it's thrown.
	var me_g := 0.0 if me.spent_once.has("grenade") else 1.0
	var foe_g := 0.0 if foe.spent_once.has("grenade") else 1.0
	v += W_ITEM * (me_g - foe_g)

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
	for d in Grid.DIRS:
		var p: Vector2i = c.pos + d
		if grid.in_bounds(p) and not grid.is_blocked(p) and other.pos != p:
			n += 1
	return n

# Lockout relief by a fighter's OWN metronome (per-player regen): pain is discounted
# only when that fighter's next pulse is 1-2 actions away.
static func _pulse_relief(c: Combatant) -> float:
	var to_pulse: int = Config.ENERGY_PULSE_ACTIONS - (c.action_count % Config.ENERGY_PULSE_ACTIONS)
	if to_pulse <= 1:
		return 0.45
	if to_pulse <= 2:
		return 0.7
	return 1.0

# The telegraphed next walls + next zone ring, as a Vector2i set. incoming_walls() is
# O(board) and this runs per matrix cell, so it's cached per (grid, rotation, shrink)
# -- all constant while one turn is being chosen. WorldGrip returns [], so story mobs
# simply see an empty set.
static var _iw_key := ""
static var _iw_set: Dictionary = {}
static func _incoming_set(grid: Grid) -> Dictionary:
	var key := "%d|%d|%d" % [grid.get_instance_id(), grid.rot_step, grid.shrink_level]
	if key != _iw_key:
		_iw_key = key
		_iw_set = {}
		for t in grid.incoming_walls():
			_iw_set[t] = true
	return _iw_set

# Chebyshev depth from the nearest board edge (0 = outermost ring): the zone closes
# from the outside, so higher depth = safer for longer.
static func _edge_depth(p: Vector2i) -> int:
	return mini(mini(p.x, p.y), mini(Grid.SIZE - 1 - p.x, Grid.SIZE - 1 - p.y))

# Compact state fingerprint for the subgame cache. Equal strings imply equal states;
# differing dictionary orderings only ever cost a cache MISS, never a wrong hit.
static func _state_key(me: Combatant, foe: Combatant, grid: Grid, depth: int) -> String:
	return "%d|%d|%d|%s|%s" % [depth, grid.rot_step, grid.shrink_level, _c_key(me), _c_key(foe)]

static func _c_key(c: Combatant) -> String:
	return "%d,%d,%d,%d,%d,%d,%d,%d,%d,%s,%s,%s" % [c.pos.x, c.pos.y, c.facing, c.hp, c.mp,
		c.energy, c.action_count, int(c.rest_ready), int(c.speed_boost),
		str(c.cooldowns), str(c.statuses), str(c.spent_once)]
