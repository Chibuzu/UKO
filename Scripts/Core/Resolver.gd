# Resolver.gd
# THE pure rules engine: (grid, combatants, actions) -> (new state, events,
# result). Never mutates inputs; knows nothing about rendering. Spells are
# data-driven (see SpellBook.SPELLS): one "spell" category here handles them all
# via shapes + effects, so new spells need no new resolver code.
#
#   Resolver.resolve(grid, a, b, action_a, action_b, turn) -> Dictionary
#     { "a": Combatant, "b": Combatant, "events": Array, "result": String }
class_name Resolver
extends RefCounted

# While teleporting, a fighter sits on NO tile (untargetable) between its blink's
# DEPART and ARRIVE ticks. This off-board sentinel is its position during transit.
const IN_TRANSIT := Vector2i(-9999, -9999)

static func resolve(grid: Grid, in_a: Combatant, in_b: Combatant,
		seq_a: Array, seq_b: Array, _turn: int) -> Dictionary:
	var a := in_a.clone()
	var b := in_b.clone()
	var events: Array = []

	# Statuses/cooldowns applied THIS turn must not be decremented at end of it.
	var fresh := {"A": {"status": [], "cd": []}, "B": {"status": [], "cd": []}}

	# Each player commits a SEQUENCE of up to two actions. We legalize, pay, and
	# schedule them in picked order; each action's strike time is the cumulative
	# sum of the action ticks before it, so action 2 always lands after action 1
	# (the player's chosen order is honored), while the two players' sequences
	# interleave on one shared clock.
	var plan_a := _plan(a, seq_a, events)
	var plan_b := _plan(b, seq_b, events)
	a.speed_boost = false
	b.speed_boost = false

	var sched: Array = []
	sched.append_array(plan_a["entries"])
	sched.append_array(plan_b["entries"])

	# Projectile flights are expanded LIVE at cast resolution (see _launch_projectile),
	# from the caster's real tile -- so a blocked preceding move fires the bolt from
	# where the caster actually sits. The schedule starts with just the planned actions.
	sched.sort_custom(_sched_less)

	var guarding := {"A": false, "B": false}   # live shield: up while it protects
	var guard_blocked := {"A": 0, "B": 0}   # per-fighter guard refund earned (0 = nothing blocked)
	var guarded := {"A": false, "B": false}     # latch: did this fighter guard at all?
	var damaged_tick := {"A": -1, "B": -1}
	var dead_tick := {"A": -1, "B": -1}
	var proj_consumed := {}   # projectile id -> true once it has hit (and stopped) or been absorbed

	var i := 0
	while i < sched.size():
		var tick: int = sched[i]["tick"]
		var group := []
		while i < sched.size() and sched[i]["tick"] == tick:
			group.append(sched[i])
			i += 1

		# Offensive actions drop the actor's OWN guard the instant they fire, so a
		# Guard+Attack covers you only up TO (not through) your own strike. Done for
		# the whole tick-group before any effects resolve, so a foe striking on the
		# very same tick as your attack is no longer blocked.
		for s in group:
			if guarding[s["owner"]] and _is_offensive(s):
				guarding[s["owner"]] = false
				events.append(_ev("guard_dropped", tick, s["owner"]))

		for s in group:
			var actor: Combatant = a if s["owner"] == "A" else b
			var target: Combatant = b if s["owner"] == "A" else a
			if dead_tick[actor.id] != -1 and dead_tick[actor.id] < tick:
				events.append(_ev("dead_skip", tick, actor.id))
				continue
			match s["category"]:
				"guard":
					guarding[actor.id] = true
					guarded[actor.id] = true
					events.append(_ev("guard_raised", tick, actor.id))
				"pivot":
					# Rooted (grenade): feet stuck -- the pivot is blocked too, so the landed
					# root guarantees a one-action facing lock (a flank-conversion window).
					if actor.statuses.has("rooted"):
						events.append(_ev("illegal_action", tick, actor.id, {"id": "pivot", "reason": "rooted"}))
					else:
						actor.facing = s["facing"]
						events.append(_ev("pivot", tick, actor.id, {"facing": s["facing"]}))
				"move":
					if not bool(s.get("_resolved", false)):
						var a_was: Vector2i = actor.pos
						var t_was: Vector2i = target.pos
						_do_move(s, actor, target, group, grid, dead_tick, tick, events)
						if actor.pos != a_was:
							_move_into_projectile(actor, sched, tick, proj_consumed, damaged_tick, dead_tick, events)
						if target.pos != t_was:
							_move_into_projectile(target, sched, tick, proj_consumed, damaged_tick, dead_tick, events)
				"attack":
					_attack(actor, target, s, tick, guarding, guard_blocked, damaged_tick, dead_tick, events)
				"spell":
					_cast_spell(grid, actor, target, s, tick, damaged_tick, dead_tick, fresh, events)
					if Config.is_projectile(s["id"]):
						_launch_projectile(grid, s, actor, sched, i, events)
					elif Config.is_blink(s["id"]):
						_launch_blink(grid, s, actor, target, sched, i, tick, events)
				"projectile":
					_projectile_step(s, actor, target, tick, proj_consumed, grid, damaged_tick, dead_tick, events)
				"blink_arrive":
					actor.pos = _blink_settle(grid, target, s["origin"], s["dest"])   # avoid landing on the foe
					actor.facing = int(s["facing"])
					events.append(_ev("blink", tick, actor.id, {"to": actor.pos, "facing": actor.facing}))
				"rest":
					events.append(_ev("rest", tick, actor.id))
				"wait":
					# Strategic hold: WAIT resolves LATE, so queuing it before an action
					# pushes that action to land after the foe has committed (e.g. wait,
					# then strike where they moved). Still tops up a little energy.
					actor.energy = mini(Config.MAX_ENERGY, actor.energy + Config.WAIT_ENERGY)
					events.append(_ev("wait", tick, actor.id))
				"noop":
					pass

			# The grenade root bites only the target's NEXT action. A move is cancelled inside
			# _do_move (which clears the root); for any other action we clear it here -- so the
			# root can never linger past that one action to block some later move.
			if actor.statuses.has("rooted"):
				actor.statuses.erase("rooted")

	# Guard outcome. Use the LATCH, not the live shield (an offensive action may
	# have dropped it): you still earn the refund if you blocked before striking.
	for c in [a, b]:
		if guarded[c.id]:
			if guard_blocked[c.id]:
				c.energy = mini(Config.MAX_ENERGY, c.energy + guard_blocked[c.id])   # tier refund
				c.speed_boost = true
				events.append(_ev("guard_success", -1, c.id))
			else:
				events.append(_ev("guard_failed", -1, c.id))

	# Rest regen, only if uninterrupted.
	for s in sched:
		if s["category"] == "rest":
			var c: Combatant = a if s["owner"] == "A" else b
			if damaged_tick[c.id] == -1:
				_rest_regen(c, sched, s, events)
			else:
				events.append(_ev("rest_interrupted", damaged_tick[c.id], c.id))

	# End of turn: tick down statuses (skip ones applied this turn). Cooldowns
	# are aged per-action in _plan, not here.
	for c in [a, b]:
		_tick_down(c.statuses, fresh[c.id]["status"])

	# Passive energy regen: a PER-PLAYER metronome. Every ENERGY_PULSE_ACTIONS
	# non-Wait actions a fighter takes, THAT fighter alone regains energy.
	_tally_energy(a, b, plan_a["actions"], plan_b["actions"], events)

	# Rest gate: you may only REST after a full turn without taking damage. Set the
	# flag from THIS turn's damage so it gates NEXT turn's rest availability.
	a.rest_ready = (damaged_tick["A"] == -1)
	b.rest_ready = (damaged_tick["B"] == -1)

	var result := _result(a, b)
	if result != "ongoing":
		events.append(_ev("game_over", -1, "", {"result": result}))

	return {"a": a, "b": b, "events": events, "result": result}


# ── Validation / costs ──────────────────────────────────────────────────
# vpos/vfacing are the player's PROJECTED position/facing after earlier actions
# in the same sequence (so a slot-2 move's cost/direction is judged from where
# slot-1 left them). Energy/mp/cooldowns come from c, which _pay mutates as the
# sequence is processed.
static func _legalize(c: Combatant, action: Dictionary, vpos: Vector2i, vfacing: int, events: Array, statuses: Dictionary) -> Dictionary:
	var id: String = action.get("id", "")
	var d := Config.def(id)
	if d.is_empty() or id == "_noop":
		events.append(_ev("illegal_action", -1, c.id, {"reason": "unknown", "id": id}))
		return {"id": "_noop"}
	if Config.is_spell(id) and not (id in c.spell_ids()):
		events.append(_ev("illegal_action", -1, c.id, {"reason": "no_gear", "id": id}))
		return {"id": "_noop"}
	if Config.is_spell(id) and int(c.cooldowns.get(id, 0)) > 0:
		events.append(_ev("illegal_action", -1, c.id, {"reason": "cooldown", "id": id}))
		return {"id": "_noop"}
	if d.get("once_per_match", false) and c.spent_once.has(id):
		events.append(_ev("illegal_action", -1, c.id, {"reason": "spent", "id": id}))
		return {"id": "_noop"}
	if d.get("category", "") == "rest" and not c.rest_ready:
		events.append(_ev("illegal_action", -1, c.id, {"reason": "rest_locked", "id": id}))
		return {"id": "_noop"}
	if d.get("category", "") == "move" and action.has("tile"):
		if c.energy < Config.effective_move_cost(vfacing, vpos, action["tile"], statuses):
			events.append(_ev("illegal_action", -1, c.id, {"reason": "cost", "id": id}))
			return {"id": "_noop"}
	elif not Config.can_afford(c.energy, c.mp, statuses, id):
		events.append(_ev("illegal_action", -1, c.id, {"reason": "cost", "id": id}))
		return {"id": "_noop"}
	return action

# Taking an action ages every cooldown this player holds by one (floored at 0).
static func _age_cooldowns(c: Combatant) -> void:
	for k in c.cooldowns.keys():
		c.cooldowns[k] = maxi(0, int(c.cooldowns[k]) - 1)

static func _pay(c: Combatant, action: Dictionary, vpos: Vector2i, vfacing: int, statuses: Dictionary) -> int:
	var id: String = action["id"]
	var d := Config.def(id)
	var ecost := Config.effective_energy_cost(id, statuses)
	if d.get("category", "") == "move" and action.has("tile"):
		ecost = Config.effective_move_cost(vfacing, vpos, action["tile"], statuses)
	c.energy = maxi(0, c.energy - ecost)
	c.mp = maxi(0, c.mp - int(d.get("mp_cost", 0)))
	return ecost

# A "real" action counts toward the shared pulse (Wait and illegal/noop don't).
static func _real_action(action: Dictionary) -> bool:
	var cat: String = Config.def(action.get("id", "")).get("category", "")
	return cat != "" and cat != "wait" and cat != "noop"

# Offensive = a basic attack or a damaging spell. Defensive/neutral actions
# (move, pivot, buff, rest, wait) are NOT offensive and leave a guard standing.
static func _is_offensive(s: Dictionary) -> bool:
	match String(s.get("category", "")):
		"attack":
			return true
		"spell":
			return String(Config.def(s.get("id", "")).get("effect", {}).get("type", "")) == "damage"
	return false

# Per-player metronome: each fighter counts ONLY their own real actions; every
# ENERGY_PULSE_ACTIONS of them, THAT fighter alone regains energy.
static func _tally_energy(a: Combatant, b: Combatant,
		acts_a: Array, acts_b: Array, events: Array) -> void:
	_tally_one(a, acts_a, "A", events)
	_tally_one(b, acts_b, "B", events)

static func _tally_one(c: Combatant, acts: Array, id: String, events: Array) -> void:
	var count: int = c.action_count
	for act in acts:
		if _real_action(act):
			count += 1
	while count >= Config.ENERGY_PULSE_ACTIONS:
		count -= Config.ENERGY_PULSE_ACTIONS
		c.energy = mini(Config.MAX_ENERGY, c.energy + Config.ENERGY_REGEN)
		events.append(_ev("energy_pulse", -1, id, {"amount": Config.ENERGY_REGEN}))
	c.action_count = count

# Legalize, pay for, and schedule a player's whole sequence. Returns the
# scheduled entries (with cumulative strike times) and the legalized actions.
# Paying happens per action in order, so action 2's affordability sees the
# energy/mp already spent by action 1.
static func _plan(c: Combatant, seq: Array, events: Array) -> Dictionary:
	var entries: Array = []
	var acts: Array = []
	var cum := 0
	var slot := 0
	var vpos: Vector2i = c.pos      # projected position as the sequence unfolds
	var vfacing: int = c.facing
	# Plan-time statuses used ONLY for cost/legality: starts with carry-over
	# statuses (still in effect) and accumulates self-buffs that commit earlier
	# in THIS sequence, so a buff->move combo discounts the move. We never write
	# to c.statuses here -- resolution applies the real status at its own tick.
	var pstat: Dictionary = c.statuses.duplicate()
	var seen_guard := false
	var seen_no_guard_spell := false
	for raw in seq:
		var rid: String = raw.get("id", "")
		var want_guard: bool = Config.def(rid).get("category", "") == "guard"
		var want_ng := Config.is_spell(rid) and bool(Config.def(rid).get("no_guard_combo", false))
		# Guard and a no-guard-combo spell (DARK BOLT) can't share one turn: the
		# spell resolves so late that guarding into it would shield nearly the whole
		# turn. Whichever is picked SECOND is voided; the first one stands.
		if (want_guard and seen_no_guard_spell) or (want_ng and seen_guard):
			events.append(_ev("illegal_action", -1, c.id, {"reason": "no_guard_combo", "id": rid}))
			raw = {"id": "_noop"}
		# Action-based cooldowns: taking an action ages this player's cooldowns
		# by one BEFORE legalizing, so a spell cast in slot 0 is still on cooldown
		# for slot 1, and prior-turn cooldowns expire as actions accrue.
		_age_cooldowns(c)
		var act := _legalize(c, raw, vpos, vfacing, events, pstat)
		var paid := _pay(c, act, vpos, vfacing, pstat)
		# A cast goes on cooldown immediately (after the age tick, so it never
		# shortens its own cooldown), blocking a recast later in this sequence.
		var aid: String = act.get("id", "")
		if Config.is_spell(aid):
			var cdv := Config.cooldown_of(aid)
			if cdv > 0:
				c.cooldowns[aid] = cdv
			# Burn once-per-match at PLAN time (like cooldowns), so a second copy later
			# in this SAME sequence is nooped by _legalize -- fixes the double-grenade.
			if Config.def(aid).get("once_per_match", false):
				c.spent_once[aid] = true
		var boost: bool = c.speed_boost and slot == 0
		var entry := _schedule(c, act, slot, vpos, vfacing, boost)
		entry["energy_cost"] = paid   # for refund if this move fizzles at resolution
		cum += int(entry["tick"])     # this action's own duration
		entry["tick"] = cum           # strike time = cumulative (= a blink's DEPART tick)
		if Config.is_blink(aid):
			cum += Config.blink_travel(aid)   # the next action waits for the teleport to ARRIVE
		entries.append(entry)
		acts.append(act)
		# Advance the projection so the next action is judged from here.
		var cat: String = Config.def(act.get("id", "")).get("category", "")
		if cat == "move" and act.has("tile"):
			vpos = act["tile"]
		elif cat == "pivot" and act.has("facing"):
			vfacing = int(act["facing"])
		elif Config.is_blink(aid) and act.has("tile"):
			vpos = act["tile"]            # a blink relocates: plan the next action from the landing
			if act.has("facing"):
				vfacing = int(act["facing"])
		# A self-buff that commits here discounts LATER actions' energy this same
		# turn (shared helper, also used by the UI projection). Applied AFTER paying
		# for the buff itself, and only to pstat -- never c.statuses (resolution
		# still applies the real status at its tick).
		Config.apply_planned_self_buff(pstat, aid)
		# Remember a guard / no-guard-combo spell ONLY if it actually committed
		# (a cost- or cooldown-nooped pick doesn't lock out its counterpart).
		if cat == "guard":
			seen_guard = true
		elif Config.is_spell(aid) and bool(Config.def(aid).get("no_guard_combo", false)):
			seen_no_guard_spell = true
		slot += 1
	return {"entries": entries, "actions": acts}

static func _schedule(c: Combatant, action: Dictionary, slot: int, vpos: Vector2i, vfacing: int, boost: bool = false) -> Dictionary:
	var d := Config.def(action["id"])
	var within: int = int(d["base_tick"])
	if d["category"] == "move" and action.has("tile"):
		if action["tile"] == vpos - Vector2i(Config.FACING_VEC[vfacing]):
			within += Config.BACK_MOVE_TAX
	if boost:
		within = 0   # carried guard initiative (slot 0) or a WAIT earlier this turn: front of band
	var facing := vfacing
	if action.has("facing") and (d["category"] == "pivot" or String(d.get("effect", {}).get("type", "")) == "blink"):
		facing = int(action["facing"])
	return {
		"owner": c.id,
		"id": action["id"],
		"category": d["category"],
		"tick": Config.final_tick(d["band"], within),   # own duration; _plan makes it cumulative
		"band_priority": int(Config.BAND_PRIORITY[d["band"]]),
		"tile": action.get("tile", c.pos),
		"facing": facing,
	}

# ── Basic combat ────────────────────────────────────────────────────────
static func _can_move(grid: Grid, actor: Combatant, other: Combatant, tile: Vector2i) -> bool:
	if Grid.dist(actor.pos, tile) != 1:
		return false
	if grid.is_blocked(tile):
		return false
	if other.pos == tile:
		return false
	return true

# Resolve a move with the contested-tile rules. Moving into the foe's tile is
# legal: if they both move into each other -> swap; if you move into their tile
# and they move elsewhere this same tick -> they (the one moved INTO) resolve
# first, then you take the vacated tile; if the tile is still occupied -> the
# move fizzles and its energy is refunded. (It still counts toward the shared
# pulse, which is tallied from the planned actions, not from success.)
static func _do_move(s: Dictionary, actor: Combatant, target: Combatant,
		group: Array, grid: Grid, dead_tick: Dictionary, tick: int, events: Array) -> void:
	# ROOTED (grenade): this move is cancelled and the root is spent. Covers "grenade lands before
	# your move this turn -> cancelled" and "a root carried from last turn blocks your first move".
	if actor.statuses.has("rooted"):
		actor.statuses.erase("rooted")
		events.append(_ev("move_blocked", tick, actor.id, {"reason": "rooted"}))
		s["_resolved"] = true
		actor.reroute_armed = true      # a following move this turn inherits THIS move's target
		actor.reroute_tile = s["tile"]  # (grenade spec c: double-mover advances to the first tile)
		return
	if actor.reroute_armed:
		actor.reroute_armed = false
		s["tile"] = actor.reroute_tile  # the cancelled move's destination becomes this move's
	var T: Vector2i = s["tile"]
	var foe_move = _move_in_group(group, target.id)
	var foe_unresolved := foe_move != null and not bool(foe_move.get("_resolved", false))
	# Mutual move into each other's tile -> swap, atomically.
	if target.pos == T and foe_unresolved and Vector2i(foe_move["tile"]) == actor.pos:
		var ap := actor.pos
		actor.pos = target.pos
		target.pos = ap
		s["_resolved"] = true
		foe_move["_resolved"] = true
		events.append(_ev("move", tick, actor.id, {"to": actor.pos, "swap": true}))
		events.append(_ev("move", tick, target.id, {"to": target.pos, "swap": true}))
		return
	# Foe sits on the destination and is moving elsewhere this tick: the one being
	# moved into resolves first, then we take the vacated tile.
	if target.pos == T and foe_unresolved and _alive_at(target, dead_tick, tick):
		_simple_move(foe_move, target, actor, grid, tick, events)
		foe_move["_resolved"] = true
	_simple_move(s, actor, target, grid, tick, events)

static func _move_in_group(group: Array, owner_id: String):
	for e in group:
		if e["owner"] == owner_id and e.get("category", "") == "move":
			return e
	return null

static func _alive_at(c: Combatant, dead_tick: Dictionary, tick: int) -> bool:
	return int(dead_tick[c.id]) == -1 or int(dead_tick[c.id]) >= tick

# Move if the tile is reachable and free, else fizzle and refund the energy paid.
static func _simple_move(s: Dictionary, mover: Combatant, other: Combatant,
		grid: Grid, tick: int, events: Array) -> void:
	if _can_move(grid, mover, other, Vector2i(s["tile"])):
		mover.pos = s["tile"]
		events.append(_ev("move", tick, mover.id, {"to": s["tile"]}))
	else:
		var refund := int(s.get("energy_cost", 0))
		mover.energy = mini(Config.MAX_ENERGY, mover.energy + refund)
		events.append(_ev("move_blocked", tick, mover.id, {"to": s["tile"], "refunded": refund}))

static func _attack(attacker: Combatant, target: Combatant, s: Dictionary,
		tick: int, guarding: Dictionary, guard_blocked: Dictionary,
		damaged_tick: Dictionary, dead_tick: Dictionary, events: Array) -> void:
	# Must be adjacent to the struck tile at strike time (you may have moved).
	var dir: Vector2i = s["tile"] - attacker.pos      # direction of the swing, for the anim
	if Grid.dist(attacker.pos, s["tile"]) != 1:
		events.append(_ev("attack_whiff", tick, attacker.id, {"tile": s["tile"], "dir": dir}))
		return
	if target.pos != s["tile"]:
		events.append(_ev("attack_whiff", tick, attacker.id, {"tile": s["tile"], "dir": dir}))
		return
	var rel := _flank(target, attacker.pos)
	var dmg := int(round(Config.ATTACK_DAMAGE * float(Config.FLANK_MULT[rel])))
	if guarding[target.id]:
		# Directional guard: front fully blocks, side halves, back slips past. The
		# refund latches by tier (front 15 / side 10 / back 0) for the end-of-turn payout.
		guard_blocked[target.id] = int(Config.GUARD_REFUND_TIER[rel])
		var blocked: float = float(Config.GUARD_BLOCK[rel])
		if blocked >= 1.0:
			events.append(_ev("attack_blocked", tick, attacker.id, {"target": target.id, "dir": dir}))
			return
		dmg = int(round(dmg * (1.0 - blocked)))   # side graze / back bypass leaks through
	_apply_damage(target, dmg, tick, damaged_tick, dead_tick)
	events.append(_ev("attack_hit", tick, attacker.id, {"target": target.id, "damage": dmg, "flank": rel, "dir": dir}))

# ── Spells (data-driven) ────────────────────────────────────────────────
static func _cast_spell(grid: Grid, caster: Combatant, target: Combatant, s: Dictionary,
		tick: int, damaged_tick: Dictionary, dead_tick: Dictionary,
		fresh: Dictionary, events: Array) -> void:
	var id: String = s["id"]
	var d := Config.def(id)
	if d.get("once_per_match", false):
		caster.spent_once[id] = true   # burn the single use for the whole match

	var tiles := _shape_tiles(grid, caster, d, s.get("tile", caster.pos))
	events.append(_ev("spell_cast", tick, caster.id, {"spell": id, "tiles": tiles}))

	var eff: Dictionary = d["effect"]
	match eff["type"]:
		"blink":
			pass   # DEPART/ARRIVE handled live in the loop by _launch_blink (teleport takes travel time)
		"apply_status":
			var who: Combatant = caster if eff.get("to", "self") == "self" else target
			var st: String = eff["status"]
			who.statuses[st] = int(Config.status_def(st)["duration"])
			fresh[who.id]["status"].append(st)
			events.append(_ev("buff_applied", tick, who.id, {"status": st}))
		"damage":
			# Spell damage is flat (no flank multiplier) by design.
			if Config.is_projectile(id):
				pass   # a projectile resolves its hits through its flight steps, not here
			elif target.pos in tiles:
				var dmg := int(eff["amount"])
				_apply_damage(target, dmg, tick, damaged_tick, dead_tick)
				events.append(_ev("spell_hit", tick, caster.id, {"target": target.id, "damage": dmg, "spell": id}))
			else:
				events.append(_ev("spell_miss", tick, caster.id, {"spell": id}))

# Which tiles a spell touches, given its shape.
static func _shape_tiles(grid: Grid, caster: Combatant, d: Dictionary, target_tile: Vector2i) -> Array:
	match d.get("shape", "self"):
		"self":
			return [caster.pos]
		"blink":
			var bdir := _dir_from(caster.pos, target_tile)
			var bt := []
			var bp: Vector2i = caster.pos
			for _i in range(int(d.get("range", 1))):
				bp += bdir
				if grid.in_bounds(bp):
					bt.append(bp)
			return bt
		"around":
			var out := []
			var r := int(d.get("radius", Config.AROUND_RADIUS))
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if dx == 0 and dy == 0:
						continue
					var p: Vector2i = caster.pos + Vector2i(dx, dy)
					if grid.in_bounds(p):
						out.append(p)
			return out
		"line":
			var dir := _dir_from(caster.pos, target_tile)
			var out2 := []
			var p2: Vector2i = caster.pos
			for _i in range(int(d.get("range", 1))):
				p2 += dir
				if not grid.in_bounds(p2) or grid.is_blocked(p2):
					break          # blockers stop the line
				out2.append(p2)
			return out2
		"throw":
			# Grenade: lobbed to a CHOSEN tile within `range` orthogonally or `diag_range`
			# diagonally. Returns the path caster -> target (tile by tile) so it flies like a
			# bolt, each tile adding the tick tax. Out-of-range targets return [] (a miss).
			var gdx := target_tile.x - caster.pos.x
			var gdy := target_tile.y - caster.pos.y
			var gadx := absi(gdx)
			var gady := absi(gdy)
			var grng := int(d.get("range", 3))
			var gdrng := int(d.get("diag_range", 1))
			var is_ortho := (gdx == 0 or gdy == 0) and (gadx + gady) >= 1 and (gadx + gady) <= grng
			var is_diag := gadx == gady and gadx >= 1 and gadx <= gdrng
			if not (is_ortho or is_diag):
				return []
			var gstep := Vector2i(signi(gdx), signi(gdy))
			var gout := []
			var gp: Vector2i = caster.pos
			while gp != target_tile:
				gp += gstep
				if not grid.in_bounds(gp) or grid.is_blocked(gp):
					break          # blockers stop the throw
				gout.append(gp)
			return gout
	return []

static func _dir_from(a: Vector2i, b: Vector2i) -> Vector2i:
	var dv: Vector2i = b - a
	if absi(dv.x) >= absi(dv.y):
		return Vector2i(signi(dv.x), 0)
	return Vector2i(0, signi(dv.y))

# ── Shared helpers ──────────────────────────────────────────────────────
static func _apply_damage(target: Combatant, dmg: int, tick: int,
		damaged_tick: Dictionary, dead_tick: Dictionary) -> void:
	target.hp = maxi(0, target.hp - dmg)
	if damaged_tick[target.id] == -1:
		damaged_tick[target.id] = tick
	if target.hp <= 0 and dead_tick[target.id] == -1:
		dead_tick[target.id] = tick

# Schedule ordering: earliest tick first; ties broken by band priority. Shared by the
# initial sort and the live tail re-sort after a projectile injects its steps.
# After events are appended to `sched`, re-sort only the unprocessed tail [i, end)
# so freshly injected future events (projectile steps, blink arrivals) resolve in order.
static func _resort_tail(sched: Array, i: int) -> void:
	var tail := sched.slice(i)
	tail.sort_custom(_sched_less)
	for k in range(tail.size()):
		sched[i + k] = tail[k]

# Launch a teleport at DEPART (its scheduled tick) from the caster's LIVE tile: the
# caster vacates to IN_TRANSIT (untargetable) and an ARRIVE event is injected at
# depart + blink_travel carrying the destination. Generic for any spell flagged blink.
static func _launch_blink(grid: Grid, s: Dictionary, caster: Combatant, target: Combatant,
		sched: Array, i: int, tick: int, events: Array) -> void:
	var d := Config.def(s["id"])
	var rng := int(d.get("range", 1))
	var bdir := _dir_from(caster.pos, s.get("tile", caster.pos))
	# Only fizzle if the blink line is a genuine dead end (edge / wall with no landable tile).
	# Do NOT fizzle just because the foe is on the target tile: the FINAL landing is chosen at
	# ARRIVAL by _blink_settle, so a foe that retreats off the tile (or that we simply land
	# beside) is handled then -- and if the exact tile is still taken we settle one closer.
	if bdir == Vector2i.ZERO or not _blink_has_landing(grid, caster.pos, bdir, rng):
		events.append(_ev("blink_fizzle", tick, caster.id, {}))
		return
	var dest: Vector2i = caster.pos + bdir * rng   # intended full-range tile; settled on arrival
	var origin := caster.pos
	var face := int(s.get("facing", caster.facing))
	events.append(_ev("blink_depart", tick, caster.id, {"from": origin, "to": dest}))
	caster.pos = IN_TRANSIT                       # off the board until arrival -- untargetable
	sched.append({
		"owner": caster.id, "id": s["id"], "category": "blink_arrive",
		"tick": tick + Config.blink_travel(s["id"]), "band_priority": Config.PRIORITY_BLINK_ARRIVE,
		"dest": dest, "origin": origin, "facing": face,
	})
	_resort_tail(sched, i)

# Does the blink line have at least one tile you could stand on (in-bounds, not a wall)?
# Foe occupancy is intentionally ignored here -- that is resolved at arrival.
static func _blink_has_landing(grid: Grid, from: Vector2i, dir: Vector2i, rng: int) -> bool:
	for dd in range(1, rng + 1):
		var t: Vector2i = from + dir * dd
		if grid.in_bounds(t) and not grid.is_blocked(t):
			return true
	return false

# Land on `dest`; if the target reached it first during the blink's travel time,
# settle on the nearest free tile back toward the origin (one tile closer) so the
# two fighters never share a tile. If the blinker arrives FIRST, dest is free and
# it lands normally (and the foe's later move into it fizzles, as moves already do).
static func _blink_settle(grid: Grid, foe: Combatant, origin: Vector2i, dest: Vector2i) -> Vector2i:
	var step: Vector2i = (origin - dest).sign()   # unit step back toward origin (cardinal blink)
	var cur := dest
	while true:
		if grid.in_bounds(cur) and not grid.is_blocked(cur) and foe.pos != cur:
			return cur
		if cur == origin or step == Vector2i.ZERO:
			break
		cur += step
	return origin   # whole path contested -> fall back to the vacated origin

static func _sched_less(x: Dictionary, y: Dictionary) -> bool:
	if x["tick"] != y["tick"]:
		return x["tick"] < y["tick"]
	return x["band_priority"] < y["band_priority"]

# Launch a projectile at CAST RESOLUTION, from the caster's LIVE tile -- so if a
# preceding move was blocked, the bolt fires from where the caster actually is.
# Generates the per-tile flight steps and splices them into the still-unprocessed
# tail of the schedule [i, end), re-sorting that tail so they resolve in tick order.
# Fully generic: any spell flagged `projectile` flies this way, nothing bolt-specific.
static func _launch_projectile(grid: Grid, s: Dictionary, caster: Combatant, sched: Array, i: int, events: Array) -> void:
	var pd := Config.def(s["id"])
	var pdir := _dir_from(caster.pos, s["tile"])
	var path: Array
	if String(pd.get("shape", "")) == "throw":
		# The aim was validated from the PLANNED position; if an earlier action fizzled,
		# the throw can be geometrically invalid from the LIVE tile. The shape rule is
		# the single source of truth: invalid -> a miss, never a ghost flight.
		if _shape_tiles(grid, caster, pd, s["tile"]).is_empty():
			events.append(_ev("spell_miss", int(s["tick"]), caster.id, {"spell": s["id"]}))
			return
		# Thrown (grenade): fly straight AT the target tile, diagonal steps included,
		# and land exactly there -- so a diagonal throw animates diagonally.
		path = []
		var cur: Vector2i = caster.pos
		var t := int(s["tick"])
		var tpt := int(pd.get("tick_per_tile", 0))
		var n := 0
		while cur != s["tile"] and n < 8:
			n += 1
			cur += Vector2i(signi(s["tile"].x - cur.x), signi(s["tile"].y - cur.y))
			t += tpt
			path.append({"tile": cur, "step": n, "tick": t})
	else:
		path = Config.projectile_path(grid, caster.pos, pdir,
				int(pd.get("range", 1)), int(pd.get("tick_per_tile", 0)), int(s["tick"]))
	if path.is_empty():
		return
	var pid := "%s:%d" % [caster.id, int(s["tick"])]
	var prev: Vector2i = caster.pos
	for st in path:
		sched.append({
			"owner": caster.id, "id": s["id"], "category": "projectile",
			"tick": int(st["tick"]), "band_priority": Config.PRIORITY_PROJECTILE,   # resolve AFTER same-tick dodges
			"tile": st["tile"], "from": prev, "step": int(st["step"]), "pid": pid,
			"dwell": int(pd.get("tick_per_tile", 0)),   # tile stays "hot" this long: a move onto it in-window is clipped
			"pierce": bool(pd.get("pierce", false)),
			"damage": int(pd.get("effect", {}).get("amount", 0)),
		})
		prev = st["tile"]
	_resort_tail(sched, i)   # injected steps now resolve in tick order with the rest of the tail

# A MOVE is continuous travel, so stepping onto a tile a foe's projectile is currently
# traversing (its dwell window contains this tick) gets you clipped -- unlike a blink,
# which teleports and never sweeps the space. The move-side mirror of the standing check.
static func _move_into_projectile(mover: Combatant, sched: Array, tick: int,
		consumed: Dictionary, damaged_tick: Dictionary, dead_tick: Dictionary, events: Array) -> void:
	if dead_tick[mover.id] != -1:
		return
	for e in sched:
		if e.get("category", "") != "projectile" or e["owner"] == mover.id:
			continue
		if consumed.get(e["pid"], false) or e["tile"] != mover.pos:
			continue
		if tick >= int(e["tick"]) and tick < int(e["tick"]) + int(e["dwell"]):
			var dmg := int(e["damage"])
			_apply_damage(mover, dmg, tick, damaged_tick, dead_tick)
			events.append(_ev("spell_hit", tick, mover.id, {"target": mover.id, "damage": dmg, "spell": e["id"]}))
			if not bool(e["pierce"]):
				consumed[e["pid"]] = true
			return

# One tile of a projectile's flight: if the foe stands here right now (live position,
# after any earlier move/blink this tick resolved) it takes the hit. A non-piercing
# bolt is then spent and its remaining steps are skipped.
static func _projectile_step(s: Dictionary, actor: Combatant, target: Combatant,
		tick: int, consumed: Dictionary, grid: Grid,
		damaged_tick: Dictionary, dead_tick: Dictionary, events: Array) -> void:
	var pid: String = s["pid"]
	if consumed.get(pid, false):
		return
	var tile: Vector2i = s["tile"]
	events.append(_ev("projectile_step", tick, actor.id, {"tile": tile, "from": s.get("from", tile), "step": int(s["step"]), "spell": s["id"]}))
	if target.pos == tile and dead_tick[target.id] == -1:
		var eff: Dictionary = Config.def(s["id"]).get("effect", {})
		if String(eff.get("type", "")) == "disrupt":
			_apply_disrupt(eff, s, actor, target, tick, events)
		else:
			var dmg := int(s["damage"])
			_apply_damage(target, dmg, tick, damaged_tick, dead_tick)
			events.append(_ev("spell_hit", tick, actor.id, {"target": target.id, "damage": dmg, "spell": s["id"]}))
		if not bool(s["pierce"]):
			consumed[pid] = true

# THE one place the grenade's landing rules live (root + drain + event) -- any
# future disrupt-style effect is edited here, never inlined at a hit site again.
static func _apply_disrupt(eff: Dictionary, s: Dictionary, actor: Combatant, target: Combatant, tick: int, events: Array) -> void:
	var st: String = String(eff.get("status", ""))
	if st != "":
		target.statuses[st] = int(Config.status_def(st).get("duration", 1))
	var drain := int(eff.get("energy_drain", 0))
	if drain > 0:
		target.energy = maxi(0, target.energy - drain)
	events.append(_ev("spell_hit", tick, actor.id, {"target": target.id, "damage": 0, "spell": s["id"], "disrupt": true, "drain": drain}))

static func _flank(defender: Combatant, attacker_pos: Vector2i) -> String:
	# THE flank rule lives once in Config; this is just the resolver-side adapter.
	return Config.flank_tier(defender.facing, defender.pos, attacker_pos)

static func _rest_regen(c: Combatant, sched: Array, own: Dictionary, events: Array) -> void:
	var enemy_tick := 0
	for s in sched:
		if s["owner"] != c.id:
			enemy_tick = int(s["tick"])
	var scale := float(enemy_tick) / float(Config.BAND_BASE[Config.Band.REST] + Config.BAND_WIDTH)
	scale = clampf(scale, 0.0, 1.0)
	var hp_gain := int(round(Config.MAX_HP * 0.10 * (0.5 + scale)))
	var mp_gain := int(round(Config.MAX_MP * 0.10 * (0.5 + scale)))
	c.hp = mini(Config.MAX_HP, c.hp + hp_gain)
	c.mp = mini(Config.MAX_MP, c.mp + mp_gain)
	events.append(_ev("rest_regen", int(own["tick"]), c.id, {"hp": hp_gain, "mp": mp_gain}))

static func _tick_down(timers: Dictionary, skip: Array) -> void:
	for key in timers.keys():
		if key in skip:
			continue
		timers[key] = int(timers[key]) - 1
		if timers[key] <= 0:
			timers.erase(key)

static func _result(a: Combatant, b: Combatant) -> String:
	var ad := a.is_dead()
	var bd := b.is_dead()
	if ad and bd:
		return "draw"
	if ad:
		return "b_wins"
	if bd:
		return "a_wins"
	return "ongoing"

static func _ev(type: String, tick: int, owner: String, data: Dictionary = {}) -> Dictionary:
	var e := {"type": type, "tick": tick, "owner": owner}
	for k in data:
		e[k] = data[k]
	return e
