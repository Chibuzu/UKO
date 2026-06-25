# PlanGenerator.gd
# AI PLAN VOCABULARY (remodel step #4, revised). Turns the raw legal-move set into
# a small, diverse set of candidate sequences for the plan matrix -- but ranks them
# TURN-AWARE so it never drops a plan the accurate evaluator would value.
#
# Why the rewrite: the first version ranked by TileUtility.standing_value, which is
# facing-/guard-/turn-blind. It pruned exactly the plans that win the hard spots --
# pivot-to-face + guard when flanked, a foot-retreat from a closing attack -- before
# the real EconomyEval matrix ever saw them. Now each candidate is scored by a cheap
# 1-ply EconomyEval against the foe's actual THREATS (rolled through the real
# Resolver), so blocking, escaping, and pressing are all visible at prune time.
#
# MODULAR: still no spell/gear ids. Legal moves come from AIToolkit (gear-generic),
# value from EconomyEval/ResourceModel/Resolver, intent only nudges via a small role
# bonus -- it no longer FILTERS, so a situational plan can never be pruned just for
# not matching the current intent.
class_name PlanGenerator
extends RefCounted

const MAX_PLANS := 6          # my plan rows for the matrix
const FOE_COLS := 6           # foe threat columns (incl. one passive)
const N_CHEAP := 14           # survivors of the cheap pre-cut that get turn-aware scoring
const PER_ROLE_CAP := 2       # at most this many picked plans sharing a salient role
const ROLE_BONUS := 6.0       # value-points nudge per favoured-role action (intent style)
const POSTURE_BONUS := 3.0    # nudge for moving the way the intent's posture wants
const SPACE_DIST := 2

const OFFENSE_ROLES := ["poke", "aoe", "attack"]
const SAFE_ROLES := ["guard", "rest", "blink"]
const ROLE_PRIORITY := ["poke", "aoe", "attack", "blink", "guard", "rest", "buff", "move", "pivot", "wait"]

# ── public API ─────────────────────────────────────────────────────────────
# My intent-aligned, diverse, TURN-AWARE-ranked plan set for the matrix rows.
static func plans(me: Combatant, foe: Combatant, grid: Grid, intent: String, threats: Array = [], k: int = MAX_PLANS) -> Array:
	var out: Array = []
	for e in plans_tagged(me, foe, grid, intent, threats, k):
		out.append(e["seq"])
	if out.is_empty():
		out = [[{"id": "wait"}]]
	return out

static func plans_tagged(me: Combatant, foe: Combatant, grid: Grid, intent: String, threats: Array = [], k: int = MAX_PLANS) -> Array:
	# The foe replies that actually hurt me -- what every one of my plans is judged
	# against. Caller may pass these in (EconomyAI reuses them as the foe columns).
	if threats.is_empty():
		threats = threat_columns(foe, me, grid, FOE_COLS)
	# Bound the turn-aware stage: a diverse superset (best per role + best overall).
	var survivors := _precut(me, foe, grid)
	var scored: Array = []
	for seq in survivors:
		scored.append({
			"seq": seq,
			"role": plan_role(seq),
			"score": _turn_aware_rank(me, foe, grid, seq, threats, intent),
		})
	scored.sort_custom(func(a, b): return a["score"] > b["score"])

	var picked: Array = []
	var role_count := {}
	for e in scored:
		if picked.size() >= k:
			break
		var r: String = e["role"]
		if int(role_count.get(r, 0)) >= PER_ROLE_CAP:
			continue
		picked.append(e)
		role_count[r] = int(role_count.get(r, 0)) + 1
	_ensure_some(picked, scored, OFFENSE_ROLES, k)
	_ensure_some(picked, scored, SAFE_ROLES, k)
	return picked

# The foe's most DANGEROUS replies (threat-focused, NOT intent-pruned) plus one
# passive column, used as the matrix's foe columns AND to rank my plans. Keeping
# this broad is what stops the AI being blind to closing attacks / flanks.
static func threat_columns(foe: Combatant, me: Combatant, grid: Grid, k: int = FOE_COLS) -> Array:
	var cands: Array = []
	for c in AIToolkit.candidates(foe, me, grid):
		if not c.is_empty():
			cands.append(c)
	if cands.is_empty():
		return [[{"id": "wait"}]]
	var ranked: Array = []
	for c in cands:
		ranked.append({"seq": c, "role": plan_role(c), "thr": _threat_rank(me, foe, grid, c)})
	ranked.sort_custom(func(a, b): return a["thr"] > b["thr"])
	var out: Array = []
	var role_count := {}
	for e in ranked:
		if out.size() >= k - 1:
			break
		var r: String = e["role"]
		if int(role_count.get(r, 0)) >= PER_ROLE_CAP:
			continue
		out.append(e["seq"])
		role_count[r] = int(role_count.get(r, 0)) + 1
	out.append([{"id": "wait"}])   # passive column: "the foe doesn't press" -> lets me value pressing
	return out

# ── ranking ────────────────────────────────────────────────────────────────
# Cheap, NON-blind pre-cut: keep the best plan of every salient role (so pivot+guard,
# retreat, rest, etc. always survive) then fill with the top by standing value, up to
# N_CHEAP. Bounds how many plans get the (costlier) turn-aware sim.
static func _precut(me: Combatant, foe: Combatant, grid: Grid) -> Array:
	var ranked: Array = []
	for c in AIToolkit.candidates(me, foe, grid):
		if c.is_empty():
			continue
		var proj := me.clone()
		for a in c:
			AIToolkit.apply_projection(proj, a)
		var sv := TileUtility.standing_value(grid, proj, foe, proj.pos)
		if sv == -INF:
			sv = -1.0e6
		ranked.append({"seq": c, "role": plan_role(c), "sv": sv})
	ranked.sort_custom(func(a, b): return a["sv"] > b["sv"])
	var keep := {}                 # index -> true
	var seen_roles := {}
	for i in ranked.size():        # archetype coverage: best of each salient role
		var r: String = ranked[i]["role"]
		if not seen_roles.has(r):
			keep[i] = true
			seen_roles[r] = true
	for i in ranked.size():        # fill the rest with the strongest overall
		if keep.size() >= N_CHEAP:
			break
		keep[i] = true
	var out: Array = []
	for i in keep:
		out.append(ranked[i]["seq"])
	return out

# Turn-aware value of one of my plans: its average EconomyEval outcome against the
# foe's threat replies (real Resolver -> sees block/escape/flank/press), plus the
# small intent style nudge.
static func _turn_aware_rank(me: Combatant, foe: Combatant, grid: Grid, seq: Array, threats: Array, intent: String) -> float:
	var tot := 0.0
	for t in threats:
		tot += EconomyEval.score_rich(me, foe, grid, seq, t)
	var v := tot / float(maxi(1, threats.size()))
	v += ROLE_BONUS * float(_role_match(seq, intent))
	var proj := me.clone()
	for a in seq:
		AIToolkit.apply_projection(proj, a)
	v += POSTURE_BONUS * _posture_fit(intent, me.pos, foe.pos, proj.pos)
	return v

# How much HP I lose if I just WAIT while the foe plays foe_seq -- a clean,
# non-circular measure of how threatening that reply is (captures move+attack, flank).
static func _threat_rank(me: Combatant, foe: Combatant, grid: Grid, foe_seq: Array) -> float:
	var out := Resolver.resolve(grid, foe, me, foe_seq, [{"id": "wait"}], 0)
	var me_after: Combatant = out["b"]
	return float(me.hp - me_after.hp)

# ── role / posture helpers ──────────────────────────────────────────────────
static func role_of(action_id: String) -> String:
	if Config.is_spell(action_id):
		return String(SpellBook.SPELLS.get(action_id, {}).get("ai_role", "spell"))
	return String(Config.def(action_id).get("category", action_id))

static func _roles(seq: Array) -> Array:
	var out: Array = []
	for a in seq:
		var r := role_of(String(a.get("id", "")))
		if not out.has(r):
			out.append(r)
	return out

static func plan_role(seq: Array) -> String:
	var roles := _roles(seq)
	for pref in ROLE_PRIORITY:
		if roles.has(pref):
			return pref
	return "wait"

static func _role_match(seq: Array, intent: String) -> int:
	var fav := IntentSelector.favored_roles(intent)
	var n := 0
	for r in _roles(seq):
		if fav.has(r):
			n += 1
	return n

static func _posture_fit(intent: String, my_pos: Vector2i, foe_pos: Vector2i, proj_pos: Vector2i) -> float:
	var dd := float(Grid.dist(my_pos, foe_pos) - Grid.dist(proj_pos, foe_pos))   # >0 = closed in
	match IntentSelector.posture(intent):
		"close":
			return dd
		"retreat":
			return -dd
		"space":
			return -absf(float(Grid.dist(proj_pos, foe_pos) - SPACE_DIST))
		_:
			return 0.0

static func _ensure_some(picked: Array, scored: Array, group: Array, k: int) -> void:
	for e in picked:
		if e["role"] in group:
			return
	for e in scored:
		if e["role"] in group:
			if picked.size() < k:
				picked.append(e)
			else:
				picked[picked.size() - 1] = e
			return
