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
	if dist >= 2 and poke != "" and _can_use(me, poke):
		var rng := int(Config.def(poke).get("range", 3))
		if _clear_line(me, foe, grid, rng):
			return {"id": poke, "tile": foe.pos}

	# 2. Adjacent (orthogonal): basic attack is best; AoE is the no-energy backup.
	if dist == 1:
		if Config.can_afford(me.energy, me.mp, me.statuses, "attack"):
			return {"id": "attack", "tile": foe.pos}
		if aoe != "" and _can_use(me, aoe):
			return {"id": aoe}
		if Config.can_afford(me.energy, me.mp, me.statuses, "guard"):
			return {"id": "guard"}
		return {"id": "rest"}

	# 3. Diagonally adjacent: melee can't reach, but the 8-tile AoE can.
	if _aoe_hits(me, foe) and aoe != "" and _can_use(me, aoe):
		return {"id": aoe}

	# 4. Out of range: buff during downtime, otherwise approach, otherwise rest.
	if buff != "" and _can_use(me, buff) and not _buff_active(me, buff) and dist >= 3:
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

	_apply_projection(c, first)
	var second := choose(c, foe, grid, spells)
	if Config.def(second.get("id", "")).get("category", "") == "rest":
		return seq          # don't rest as a 2nd action; just take the one
	seq.append(second)
	return seq

# Mirror the resolver's upfront pay (+ position/facing/cooldown) so the second
# pick is judged from where the first leaves us. Statuses are NOT applied: the
# resolver pays upfront, before a same-turn buff would discount anything.
static func _apply_projection(c: Combatant, action: Dictionary) -> void:
	var id: String = action.get("id", "")
	var d := Config.def(id)
	var cat: String = d.get("category", "")
	if cat == "move" and action.has("tile"):
		c.energy = maxi(0, c.energy - Config.effective_move_cost(c.facing, c.pos, action["tile"], c.statuses))
		c.pos = action["tile"]
	elif cat == "pivot" and action.has("facing"):
		c.facing = int(action["facing"])
	else:
		c.energy = maxi(0, c.energy - Config.effective_energy_cost(id, c.statuses))
		c.mp = maxi(0, c.mp - int(d.get("mp_cost", 0)))
	if Config.is_spell(id):
		var cd := Config.cooldown_of(id)
		if cd > 0:
			c.cooldowns[id] = cd

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

# Ready = off cooldown AND affordable.
static func _can_use(me: Combatant, id: String) -> bool:
	if int(me.cooldowns.get(id, 0)) > 0:
		return false
	return Config.can_afford(me.energy, me.mp, me.statuses, id)

# True if the foe sits on a clear orthogonal line within range (matches the
# resolver's bolt trace: any blocker between caster and foe stops it).
static func _clear_line(me: Combatant, foe: Combatant, grid: Grid, rng: int) -> bool:
	var dx := foe.pos.x - me.pos.x
	var dy := foe.pos.y - me.pos.y
	if dx != 0 and dy != 0:
		return false
	var dist := absi(dx) + absi(dy)
	if dist < 1 or dist > rng:
		return false
	var step := Vector2i(signi(dx), signi(dy))
	var p: Vector2i = me.pos
	for _i in range(dist):
		p += step
		if grid.is_blocked(p):
			return false
	return true

# True if the foe is one of the 8 tiles surrounding the caster (AoE footprint).
static func _aoe_hits(me: Combatant, foe: Combatant) -> bool:
	var dx := absi(foe.pos.x - me.pos.x)
	var dy := absi(foe.pos.y - me.pos.y)
	return maxi(dx, dy) == 1

static func _step_toward(me: Combatant, foe: Combatant, grid: Grid) -> Vector2i:
	var best := me.pos
	var best_dist := Grid.dist(me.pos, foe.pos)
	for dv in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		var p: Vector2i = me.pos + dv
		if not grid.in_bounds(p) or grid.is_blocked(p) or p == foe.pos:
			continue
		var nd := Grid.dist(p, foe.pos)
		if nd < best_dist:
			best_dist = nd
			best = p
	return best
