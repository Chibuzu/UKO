# AIToolkit.gd
# Shared substrate for the AI brains: the rules-faithful helpers every brain needs
# -- project an action onto a clone, test castability, trace a clear line. These
# used to live in StubOpponent and were reached into across the class boundary by
# ChallengingAI; they now have ONE owner here, so the brains depend on a system
# rather than on each other's internals. Pure / static / no brain logic of its own.
class_name AIToolkit
extends RefCounted

# Mirror the resolver's upfront pay (+ position/facing/cooldown) so a second pick
# in a sequence is judged from where the first leaves us. Statuses are NOT applied:
# the resolver pays upfront, before a same-turn buff would discount anything.
static func apply_projection(c: Combatant, action: Dictionary) -> void:
	var id: String = action.get("id", "")
	var d := Config.def(id)
	var cat: String = d.get("category", "")
	if cat == "move" and action.has("tile"):
		c.energy = maxi(0, c.energy - Config.effective_move_cost(c.facing, c.pos, action["tile"], c.statuses))
		c.pos = action["tile"]
	elif cat == "pivot" and action.has("facing"):
		c.facing = int(action["facing"])
	elif Config.is_blink(id) and action.has("tile"):
		c.energy = maxi(0, c.energy - Config.effective_energy_cost(id, c.statuses))
		c.mp = maxi(0, c.mp - int(d.get("mp_cost", 0)))
		c.pos = action["tile"]
		if action.has("facing"):
			c.facing = int(action["facing"])
	else:
		c.energy = maxi(0, c.energy - Config.effective_energy_cost(id, c.statuses))
		c.mp = maxi(0, c.mp - int(d.get("mp_cost", 0)))
	if Config.is_spell(id):
		var cd := Config.cooldown_of(id)
		if cd > 0:
			c.cooldowns[id] = cd

# Ready = off cooldown AND affordable.
static func can_use(me: Combatant, id: String) -> bool:
	if int(me.cooldowns.get(id, 0)) > 0:
		return false
	return Config.can_afford(me.energy, me.mp, me.statuses, id)

# True if the foe sits on a clear orthogonal line within range (matches the
# resolver's bolt trace: any blocker between caster and foe stops it).
static func clear_line(me: Combatant, foe: Combatant, grid: Grid, rng: int) -> bool:
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

# ── Candidate generation ─────────────────────────────────────────────────

# Bounded set of candidate sequences: each sensible first action alone, paired
# with each sensible second action (judged from the projected state), plus Rest.
static func candidates(me: Combatant, foe: Combatant, grid: Grid) -> Array:
	var seqs: Array = []
	# REST only earns a slot if it can actually regen. At full HP and MP it heals
	# nothing and grants no energy, so offering it just lets the mixer waste a turn.
	if (me.hp < Config.MAX_HP or me.mp < Config.MAX_MP) and me.rest_ready:
		seqs.append([{"id": "rest"}])
	for a1 in slot_actions(me, foe, grid):
		# A lone WAIT at full energy banks nothing and has no later action to delay:
		# a pure pass. (A WAIT that PRECEDES another action is kept below -- it now
		# delays that action, a strategic hold.)
		if not (a1.get("id") == "wait" and me.energy >= Config.MAX_ENERGY):
			seqs.append([a1])
		var proj := me.clone()
		apply_projection(proj, a1)
		for a2 in slot_actions(proj, foe, grid):
			# A TRAILING WAIT that cannot bank energy (already capped) is a dead no-op.
			if a2.get("id") == "wait" and proj.energy >= Config.MAX_ENERGY:
				continue
			seqs.append([a1, a2])
	if seqs.is_empty():
		seqs = [[{"id": "wait"}]]   # never hand back an empty candidate set (wait is always legal)
	return seqs

# Sensible actions for one slot from a given state. Generic over spells (reads
# shape/needs_tile), so it works for whatever gear is equipped.
static func slot_actions(c: Combatant, foe: Combatant, grid: Grid) -> Array:
	var acts: Array = []
	var dist := Grid.dist(c.pos, foe.pos)

	# Every legal, affordable orthogonal step -- toward, away, AND lateral -- so the
	# scorer can pick the most efficient reposition instead of only "straight in" or
	# "straight back". Previously only toward/away were offered, so a cheaper sidestep
	# was literally impossible for the AI to choose.
	for dv in Grid.DIRS:
		var tile: Vector2i = c.pos + dv
		if not grid.in_bounds(tile) or grid.is_blocked(tile) or tile == foe.pos:
			continue
		if c.energy >= Config.effective_move_cost(c.facing, c.pos, tile, c.statuses):
			acts.append({"id": "move", "tile": tile})

	if dist == 1 and Config.can_afford(c.energy, c.mp, c.statuses, "attack"):
		acts.append({"id": "attack", "tile": foe.pos})

	var face := facing_toward(c.pos, foe.pos)
	if face != c.facing:
		acts.append({"id": "pivot", "facing": face})

	# GUARD only earns a slot when the foe actually has a blockable melee this turn.
	# Its energy refund + speed boost require a SUCCESSFUL block, so guarding with
	# nothing to block is a pure waste -- don't offer it (same hygiene as rest/wait).
	if Config.can_afford(c.energy, c.mp, c.statuses, "guard") and ThreatModel.has_melee_threat(foe, c, grid):
		acts.append({"id": "guard"})

	for sid in c.spell_ids():
		if not can_use(c, sid):
			continue
		var d := Config.def(sid)
		if Config.is_blink(sid):
			# Directional: one candidate per cardinal that has a valid landing, refaced
			# toward the foe (best for a backstab follow-up and not exposing our back).
			for dv in Grid.DIRS:
				var bl := Config.blink_landing(grid, c.pos, dv, int(d.get("range", 1)), foe.pos)
				if bl.is_empty():
					continue
				acts.append({"id": sid, "tile": bl["tile"], "facing": facing_toward(bl["tile"], foe.pos)})
			continue
		if d.get("needs_tile", false):
			if clear_line(c, foe, grid, int(d.get("range", 1))):
				acts.append({"id": sid, "tile": foe.pos})
		else:
			# An "around" (BURST) damage spell only makes sense when the foe sits in
			# its 3x3 blast (Chebyshev 1); offering it otherwise just whiffs the mp.
			if not _around_whiffs(d, c.pos, foe.pos):
				acts.append({"id": sid})

	acts.append({"id": "wait"})
	return acts

# True if `d` is an "around" damage spell whose blast wouldn't reach the foe from
# `from` -- i.e. casting it would whiff. Used to prune it from the candidate list.
static func _around_whiffs(d: Dictionary, from: Vector2i, foe_pos: Vector2i) -> bool:
	if d.get("shape", "") != "around":
		return false
	if String(d.get("effect", {}).get("type", "")) != "damage":
		return false
	# > 2, not > 1: the foe is within one step of the blast, so this hits either by
	# closing in (move -> burst) or by the foe stepping into us. Only a truly
	# unreachable burst (>=3 away) is pruned. Tighten to > 1 for hit-only-now.
	return Grid.cheb(from, foe_pos) > 2


# Cardinal facing pointing at the foe (dominant axis; +y is south).
static func facing_toward(from: Vector2i, to: Vector2i) -> int:
	var d := to - from
	if absi(d.x) >= absi(d.y):
		return Config.Facing.EAST if d.x >= 0 else Config.Facing.WEST
	return Config.Facing.SOUTH if d.y >= 0 else Config.Facing.NORTH
