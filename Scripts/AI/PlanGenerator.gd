# PlanGenerator.gd
# AI PLAN VOCABULARY (new-brain step 4). Turns the raw legal-move explosion into
# a small, DIVERSE, intent-aligned set of candidate sequences -- the rows/columns
# the plan matrix (step 5) and the Nash solver will reason over. Pruning to good
# plans is what keeps the eventual mix sharp ("cast when the enemy's in range")
# instead of spreading probability over junk.
#
# MODULAR BY DESIGN:
#   * Legal sequences come from AIToolkit.candidates() -- already gear-generic
#     (it reads each spell's shape/needs_tile and only offers an action when it
#     actually reaches). We do NOT re-enumerate moves here.
#   * Intent alignment is by ROLE TAG (IntentSelector.favored_roles + a spell's
#     `ai_role`), never by spell id, so new gear participates automatically.
#   * Ranking uses ResourceModel + TileUtility, so plans are judged on the same
#     value axis as everything else.
class_name PlanGenerator
extends RefCounted

const MAX_PLANS := 6          # matrix is plans x plans; keep it small for the solver
const PER_ROLE_CAP := 2       # at most this many plans sharing a salient role (diversity)
const ROLE_BONUS := 8.0       # value-points per favoured-role action a plan contains
const POSTURE_BONUS := 3.0    # weight on moving the way the intent's posture wants
const SPEND_PENALTY := 0.25   # mild bias against burning resources during PRUNING only
const SPACE_DIST := 2         # preferred stand-off distance for "space" postures

const OFFENSE_ROLES := ["poke", "aoe", "attack"]
const SAFE_ROLES := ["guard", "rest", "blink"]

# Salient-role priority for diversity grouping + labelling (offense first).
const ROLE_PRIORITY := ["poke", "aoe", "attack", "blink", "guard", "rest", "buff", "move", "pivot", "wait"]

# Map an action id to its role tag: spells carry `ai_role`; basic actions use
# their category. This is the ONLY id->role bridge, so it stays gear-generic.
static func role_of(action_id: String) -> String:
	if Config.is_spell(action_id):
		return String(SpellBook.SPELLS.get(action_id, {}).get("ai_role", "spell"))
	return String(Config.def(action_id).get("category", action_id))

# Intent-aligned, diverse set of candidate sequences for the matrix.
static func plans(me: Combatant, foe: Combatant, grid: Grid, intent: String, k: int = MAX_PLANS) -> Array:
	var tagged := plans_tagged(me, foe, grid, intent, k)
	var out: Array = []
	for e in tagged:
		out.append(e["seq"])
	if out.is_empty():
		out = [[{"id": "wait"}]]
	return out

# Same as plans() but keeps each plan's {seq, role, score} -- handy for the matrix
# (diversity in mixing) and for logging which intent produced what.
static func plans_tagged(me: Combatant, foe: Combatant, grid: Grid, intent: String, k: int = MAX_PLANS) -> Array:
	var scored: Array = []
	for seq in AIToolkit.candidates(me, foe, grid):
		if seq.is_empty():
			continue
		scored.append({
			"seq": seq,
			"role": plan_role(seq),
			"score": _heuristic(me, foe, grid, seq, intent),
		})
	scored.sort_custom(func(a, b): return a["score"] > b["score"])

	# Greedy pick, capped per salient role so the matrix gets variety not 6 pokes.
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

	# Coverage guarantee: the matrix needs both an offensive and a safe option to
	# represent the guard/attack/dodge counterplay, even if the intent leans one way.
	_ensure_some(picked, scored, OFFENSE_ROLES, k)
	_ensure_some(picked, scored, SAFE_ROLES, k)
	return picked

# All role tags present in a sequence.
static func _roles(seq: Array) -> Array:
	var out: Array = []
	for a in seq:
		var r := role_of(String(a.get("id", "")))
		if not out.has(r):
			out.append(r)
	return out

# The sequence's salient role (offense first), for diversity + labelling.
static func plan_role(seq: Array) -> String:
	var roles := _roles(seq)
	for pref in ROLE_PRIORITY:
		if roles.has(pref):
			return pref
	return "wait"

# Prune-time heuristic (NOT the final score -- the matrix simulates that). Rewards
# landing on a strong tile, matching the intent's roles, and moving the way the
# posture wants; lightly penalises spend so equal plans prefer the cheaper one.
static func _heuristic(me: Combatant, foe: Combatant, grid: Grid, seq: Array, intent: String) -> float:
	var proj := me.clone()
	for a in seq:
		AIToolkit.apply_projection(proj, a)
	var h := TileUtility.standing_value(grid, proj, foe, proj.pos)
	h += ROLE_BONUS * float(_role_match(seq, intent))
	h += POSTURE_BONUS * _posture_fit(intent, me.pos, foe.pos, proj.pos)
	h -= SPEND_PENALTY * (ResourceModel.stock(me) - ResourceModel.stock(proj))
	return h

static func _role_match(seq: Array, intent: String) -> int:
	var fav := IntentSelector.favored_roles(intent)
	var n := 0
	for r in _roles(seq):
		if fav.has(r):
			n += 1
	return n

# How well a plan's net displacement serves the intent's posture.
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
			return 0.0   # "control": rely on standing_value's mobility/safety terms

# Make sure at least one plan with a salient role in `group` is present; if not,
# add the best-scoring such plan (swapping out the weakest pick if we're full).
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
