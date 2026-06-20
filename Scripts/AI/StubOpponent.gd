# StubOpponent.gd
# Player B's brain. Still SIMPLE — a heuristic priority ladder, not a predictive
# or searching AI (it does not read your patterns or bluff). But it now uses
# spells sensibly: poke with the bolt at range, fall back to AoE when out of
# energy, and buff during downtime. Swap/rename this when we build a deeper AI.
#
# It obeys exactly the same rules as the player: cooldowns, MP, line-of-sight.
# The resolver still backstops anything illegal, but good picks avoid waste.
class_name StubOpponent
extends RefCounted

static func choose(me: Combatant, foe: Combatant, grid: Grid, spells: Array) -> Dictionary:
	var dist := Grid.dist(me.pos, foe.pos)
	var poke := _role(spells, "poke")     # ranged line spell, whatever its id
	var aoe := _role(spells, "aoe")       # area spell
	var buff := _role(spells, "buff")     # self buff

	# 1. Ranged poke from range 2-3 on a clear line (save melee for adjacency).
	if dist >= 2 and poke != "" and AIToolkit.can_use(me, poke):
		var rng := int(Config.def(poke).get("range", 3))
		if AIToolkit.clear_line(me, foe, grid, rng):
			return {"id": poke, "tile": foe.pos}

	# 2. Adjacent (orthogonal): basic attack is best; AoE is the no-energy backup.
	if dist == 1:
		if Config.can_afford(me.energy, me.mp, me.statuses, "attack"):
			return {"id": "attack", "tile": foe.pos}
		if aoe != "" and AIToolkit.can_use(me, aoe):
			return {"id": aoe}
		if Config.can_afford(me.energy, me.mp, me.statuses, "guard"):
			return {"id": "guard"}
		return {"id": "rest"}

	# 3. Diagonally adjacent: melee can't reach, but the 8-tile AoE can.
	if _aoe_hits(me, foe) and aoe != "" and AIToolkit.can_use(me, aoe):
		return {"id": aoe}

	# 4. Out of range: buff during downtime, otherwise approach, otherwise rest.
	if buff != "" and AIToolkit.can_use(me, buff) and not _buff_active(me, buff) and dist >= 3:
		return {"id": buff}
	var step := _step_toward(me, foe, grid)
	if step != me.pos and me.energy >= Config.effective_move_cost(me.facing, me.pos, step, me.statuses):
		return {"id": "move", "tile": step}
	return {"id": "rest"}

# Pick a two-action sequence: choose action 1, project it onto a clone, choose
# action 2 from the projected state. Rest is the whole turn (no 2nd action), and
# the AI won't take Rest as a 2nd action (same rule the player's UI enforces).
static func choose_sequence(me: Combatant, foe: Combatant, grid: Grid, spells: Array) -> Array:
	var c := me.clone()
	var seq: Array = []

	var first := choose(c, foe, grid, spells)
	seq.append(first)
	if Config.def(first.get("id", "")).get("category", "") == "rest":
		return seq

	AIToolkit.apply_projection(c, first)
	var second := choose(c, foe, grid, spells)
	if Config.def(second.get("id", "")).get("category", "") == "rest":
		return seq          # don't rest as a 2nd action; just take the one
	seq.append(second)
	return seq

# ── Helpers ─────────────────────────────────────────────────────────────
# First equipped spell whose ai_role matches the wanted role, or "" if none.
# This is how the AI copes with arbitrary gear: it asks for a ROLE, not a name.
static func _role(spells: Array, role: String) -> String:
	for id in spells:
		if String(Config.def(id).get("ai_role", "")) == role:
			return id
	return ""

# True if this buff spell's granted status is already active on the caster
# (generic: reads the spell's apply_status effect, names no specific status).
static func _buff_active(me: Combatant, buff_id: String) -> bool:
	var eff: Dictionary = Config.def(buff_id).get("effect", {})
	if String(eff.get("type", "")) == "apply_status":
		return int(me.statuses.get(String(eff.get("status", "")), 0)) > 0
	return false

# True if the foe is one of the 8 tiles surrounding the caster (AoE footprint).
static func _aoe_hits(me: Combatant, foe: Combatant) -> bool:
	var dx := absi(foe.pos.x - me.pos.x)
	var dy := absi(foe.pos.y - me.pos.y)
	return maxi(dx, dy) == 1

static func _step_toward(me: Combatant, foe: Combatant, grid: Grid) -> Vector2i:
	var best := me.pos
	var best_dist := Grid.dist(me.pos, foe.pos)
	for dv in Grid.DIRS:
		var p: Vector2i = me.pos + dv
		if not grid.in_bounds(p) or grid.is_blocked(p) or p == foe.pos:
			continue
		var nd := Grid.dist(p, foe.pos)
		if nd < best_dist:
			best_dist = nd
			best = p
	return best
