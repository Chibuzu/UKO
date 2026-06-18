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

	sched.sort_custom(func(x, y):
		if x["tick"] != y["tick"]:
			return x["tick"] < y["tick"]
		return x["band_priority"] < y["band_priority"]
	)

	var guarding := {"A": false, "B": false}   # live shield: up while it protects
	var guard_blocked := {"A": false, "B": false}
	var guarded := {"A": false, "B": false}     # latch: did this fighter guard at all?
	var damaged_tick := {"A": -1, "B": -1}
	var dead_tick := {"A": -1, "B": -1}

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
					actor.facing = s["facing"]
					events.append(_ev("pivot", tick, actor.id, {"facing": s["facing"]}))
				"move":
					if _can_move(grid, actor, target, s["tile"]):
						actor.pos = s["tile"]
						events.append(_ev("move", tick, actor.id, {"to": s["tile"]}))
					else:
						events.append(_ev("move_blocked", tick, actor.id, {"to": s["tile"]}))
				"attack":
					_attack(actor, target, s, tick, guarding, guard_blocked, damaged_tick, dead_tick, events)
				"spell":
					_cast_spell(grid, actor, target, s, tick, damaged_tick, dead_tick, fresh, events)
				"rest":
					events.append(_ev("rest", tick, actor.id))
				"wait":
					# Do nothing this turn; act at the front of your band next turn.
					# Same flag a successful guard sets — front-of-band, never cross-band.
					actor.speed_boost = true
					events.append(_ev("wait", tick, actor.id))
				"noop":
					pass

	# Guard outcome. Use the LATCH, not the live shield (an offensive action may
	# have dropped it): you still earn the refund if you blocked before striking.
	for c in [a, b]:
		if guarded[c.id]:
			if guard_blocked[c.id]:
				c.energy = mini(Config.MAX_ENERGY, c.energy + Config.GUARD_REFUND)
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

	# Passive energy regen: a SHARED metronome. Every ENERGY_PULSE_ACTIONS
	# non-Wait actions taken by EITHER fighter, both regain energy at once.
	_tally_shared_energy(a, b, plan_a["actions"], plan_b["actions"], events)

	var result := _result(a, b)
	if result != "ongoing":
		events.append(_ev("game_over", -1, "", {"result": result}))

	return {"a": a, "b": b, "events": events, "result": result}


# ── Validation / costs ──────────────────────────────────────────────────
# vpos/vfacing are the player's PROJECTED position/facing after earlier actions
# in the same sequence (so a slot-2 move's cost/direction is judged from where
# slot-1 left them). Energy/mp/cooldowns come from c, which _pay mutates as the
# sequence is processed.
static func _legalize(c: Combatant, action: Dictionary, vpos: Vector2i, vfacing: int, events: Array) -> Dictionary:
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
	if d.get("category", "") == "move" and action.has("tile"):
		if c.energy < Config.effective_move_cost(vfacing, vpos, action["tile"], c.statuses):
			events.append(_ev("illegal_action", -1, c.id, {"reason": "cost", "id": id}))
			return {"id": "_noop"}
	elif not Config.can_afford(c.energy, c.mp, c.statuses, id):
		events.append(_ev("illegal_action", -1, c.id, {"reason": "cost", "id": id}))
		return {"id": "_noop"}
	return action

# Taking an action ages every cooldown this player holds by one (floored at 0).
static func _age_cooldowns(c: Combatant) -> void:
	for k in c.cooldowns.keys():
		c.cooldowns[k] = maxi(0, int(c.cooldowns[k]) - 1)

static func _pay(c: Combatant, action: Dictionary, vpos: Vector2i, vfacing: int) -> void:
	var id: String = action["id"]
	var d := Config.def(id)
	var ecost := Config.effective_energy_cost(id, c.statuses)
	if d.get("category", "") == "move" and action.has("tile"):
		ecost = Config.effective_move_cost(vfacing, vpos, action["tile"], c.statuses)
	c.energy = maxi(0, c.energy - ecost)
	c.mp = maxi(0, c.mp - int(d.get("mp_cost", 0)))

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

# Shared metronome: count every real action by BOTH fighters into one tally
# (mirrored on both combatants so it persists). Each full ENERGY_PULSE_ACTIONS
# pulses BOTH players' energy at once.
static func _tally_shared_energy(a: Combatant, b: Combatant,
		acts_a: Array, acts_b: Array, events: Array) -> void:
	var shared: int = a.action_count
	for act in acts_a:
		if _real_action(act):
			shared += 1
	for act in acts_b:
		if _real_action(act):
			shared += 1
	while shared >= Config.ENERGY_PULSE_ACTIONS:
		shared -= Config.ENERGY_PULSE_ACTIONS
		a.energy = mini(Config.MAX_ENERGY, a.energy + Config.ENERGY_REGEN)
		b.energy = mini(Config.MAX_ENERGY, b.energy + Config.ENERGY_REGEN)
		events.append(_ev("energy_pulse", -1, "A", {"amount": Config.ENERGY_REGEN}))
		events.append(_ev("energy_pulse", -1, "B", {"amount": Config.ENERGY_REGEN}))
	a.action_count = shared
	b.action_count = shared

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
	var seen_guard := false
	var seen_no_guard_spell := false
	for raw in seq:
		var rid: String = raw.get("id", "")
		var want_guard := Config.def(rid).get("category", "") == "guard"
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
		var act := _legalize(c, raw, vpos, vfacing, events)
		_pay(c, act, vpos, vfacing)
		# A cast goes on cooldown immediately (after the age tick, so it never
		# shortens its own cooldown), blocking a recast later in this sequence.
		var aid: String = act.get("id", "")
		if Config.is_spell(aid):
			var cdv := Config.cooldown_of(aid)
			if cdv > 0:
				c.cooldowns[aid] = cdv
		var entry := _schedule(c, act, slot, vpos, vfacing)
		cum += int(entry["tick"])     # this action's own duration
		entry["tick"] = cum           # strike time = cumulative
		entries.append(entry)
		acts.append(act)
		# Advance the projection so the next action is judged from here.
		var cat: String = Config.def(act.get("id", "")).get("category", "")
		if cat == "move" and act.has("tile"):
			vpos = act["tile"]
		elif cat == "pivot" and act.has("facing"):
			vfacing = int(act["facing"])
		# Remember a guard / no-guard-combo spell ONLY if it actually committed
		# (a cost- or cooldown-nooped pick doesn't lock out its counterpart).
		if cat == "guard":
			seen_guard = true
		elif Config.is_spell(aid) and bool(Config.def(aid).get("no_guard_combo", false)):
			seen_no_guard_spell = true
		slot += 1
	return {"entries": entries, "actions": acts}

static func _schedule(c: Combatant, action: Dictionary, slot: int, vpos: Vector2i, vfacing: int) -> Dictionary:
	var d := Config.def(action["id"])
	var within: int = int(d["base_tick"])
	if d["category"] == "move" and action.has("tile"):
		if action["tile"] == vpos - Vector2i(Config.FACING_VEC[vfacing]):
			within += Config.BACK_MOVE_TAX
	if c.speed_boost and slot == 0:
		within = 0   # Wait/guard boost: the sequence's FIRST action starts early
	var facing := vfacing
	if d["category"] == "pivot" and action.has("facing"):
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

static func _attack(attacker: Combatant, target: Combatant, s: Dictionary,
		tick: int, guarding: Dictionary, guard_blocked: Dictionary,
		damaged_tick: Dictionary, dead_tick: Dictionary, events: Array) -> void:
	# Must be adjacent to the struck tile at strike time (you may have moved).
	if Grid.dist(attacker.pos, s["tile"]) != 1:
		events.append(_ev("attack_whiff", tick, attacker.id, {"tile": s["tile"]}))
		return
	if target.pos != s["tile"]:
		events.append(_ev("attack_whiff", tick, attacker.id, {"tile": s["tile"]}))
		return
	if guarding[target.id]:
		guard_blocked[target.id] = true
		events.append(_ev("attack_blocked", tick, attacker.id, {"target": target.id}))
		return
	var rel := _flank(target, attacker.pos)
	var dmg := int(round(Config.ATTACK_DAMAGE * float(Config.FLANK_MULT[rel])))
	_apply_damage(target, dmg, tick, damaged_tick, dead_tick)
	events.append(_ev("attack_hit", tick, attacker.id, {"target": target.id, "damage": dmg, "flank": rel}))

# ── Spells (data-driven) ────────────────────────────────────────────────
static func _cast_spell(grid: Grid, caster: Combatant, target: Combatant, s: Dictionary,
		tick: int, damaged_tick: Dictionary, dead_tick: Dictionary,
		fresh: Dictionary, events: Array) -> void:
	var id: String = s["id"]
	var d := Config.def(id)

	var tiles := _shape_tiles(grid, caster, d, s.get("tile", caster.pos))
	events.append(_ev("spell_cast", tick, caster.id, {"spell": id, "tiles": tiles}))

	var eff: Dictionary = d["effect"]
	match eff["type"]:
		"apply_status":
			var who: Combatant = caster if eff.get("to", "self") == "self" else target
			var st: String = eff["status"]
			who.statuses[st] = int(Config.status_def(st)["duration"])
			fresh[who.id]["status"].append(st)
			events.append(_ev("buff_applied", tick, who.id, {"status": st}))
		"damage":
			# Spell damage is flat (no flank multiplier) by design.
			if target.pos in tiles:
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
		"around":
			var out := []
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
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

static func _flank(defender: Combatant, attacker_pos: Vector2i) -> String:
	var to_attacker: Vector2i = attacker_pos - defender.pos
	var f: Vector2i = Config.FACING_VEC[defender.facing]
	var dot := to_attacker.x * f.x + to_attacker.y * f.y
	if dot > 0:
		return "front"
	elif dot < 0:
		return "back"
	return "side"

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
