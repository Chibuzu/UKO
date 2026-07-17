# StoryCombat.gd
# Story-mode multi-mob resolution on top of the UNMODIFIED 2-actor resolver. One turn =
# the player's sequence resolved against each engaged mob in turn, with three consequences:
#   * the player's offense (incl. AoE) lands on EVERY mob it reaches;
#   * mobs are aware of each other -- each is handed a grid with the others as walls;
#   * mobs emit MOVE-ONLY sequences, so they deal NO resolver damage. Every mob's strike is
#     applied afterwards by its MobKind (range/shape/guard per creature), against the
#     player's final tile. Because mobs never damage the player inside the resolver, the
#     player's REST regen is never interrupted -- so basing final HP on the post-resolve
#     value (not start_hp) is what makes resting heal you mid-fight.
# The player's canonical post-action state is the first (nearest) pairwise resolve.
class_name StoryCombat
extends RefCounted

# mobs / mob_seqs / mob_kinds are parallel arrays, nearest first.
# Returns { player, mobs:[Combatant], primary_events, dmg_by_mob:[int], result }.
static func resolve_turn(grid: WorldGrid, player_in: Combatant, mobs: Array,
		player_seq: Array, mob_seqs: Array, mob_kinds: Array, extra_walls: Array = []) -> Dictionary:
	var guarded: bool = _player_guarded(player_seq)
	var player_final: Combatant = player_in.clone()
	var out_mobs: Array = []
	var primary_events: Array = []
	var occupied: Dictionary = {}
	for t in extra_walls:
		occupied[t] = true            # two-tile bodies: every tail is solid ground

	var kept_resolves: Array = []            # each mob's r-dict (event harvesting below)
	for i in mobs.size():
		var g: WorldGrid = _grid_blocking_others(grid, mobs, occupied, i)
		var r: Dictionary = Resolver.resolve(g, player_in.clone(), mobs[i].clone(), player_seq, mob_seqs[i], 0)
		kept_resolves.append(r)
		out_mobs.append(r["b"])
		occupied[r["b"].pos] = true
		if i == 0:
			player_final = r["a"].clone()        # move-only mobs deal no resolver dmg; characters DO
			primary_events = r["events"]
			occupied[player_final.pos] = true    # your landing tile is now a wall for every other mob

	# Each mob's strike, guard-aware, against the player's final tile. A mob has 2 actions
	# per turn and an ATTACK IS one of them, so a mob that spent both actions moving (2 moves)
	# cannot also strike this turn. Its per-creature range/shape still governs whether the
	# strike from <=1 move connects.
	# ── strikes on REAL TICK TIMING ─────────────────────────────────────────
	# A mob's non-move actions are strikes at fixed attack-band ticks (slot 1 -> 350,
	# slot 2 -> 900). Each strike is judged against WHERE THE PLAYER WAS at that tick,
	# rebuilt from the resolve's own event stream -- so blinking behind a mob mid-turn
	# (or being IN TRANSIT at strike time) makes it genuinely MISS.
	var timeline := _player_timeline(player_in, primary_events)
	var dmg_by_mob: Array = []
	# Each character's OWN resolver events. The primary mob's are played by the event
	# player; the others had nowhere to go, so their actions were invisible -- unlogged,
	# and animated only as a net displacement (two moves collapsing into one diagonal).
	var mob_events: Array = []
	# ONLY the old move-only mobs' synthesized strike damage -- i.e. damage the resolver
	# did NOT apply itself. True-action characters are excluded by design (see below).
	var budget_dmg: int = 0
	var strikes_by_mob: Array = []
	var attempts_by_mob: Array = []
	var strike_log: Array = []
	# ── TRUE-ACTION CHARACTERS (Story/Mobs2): their attacks went THROUGH the resolver
	# like a duelist's, so we harvest the real attack_hit damage and skip the old
	# budget-strike synthesis entirely for them.
	for i in mobs.size():
		if mob_kinds[i].has_method("uses_true_actions") and mob_kinds[i].uses_true_actions():
			var hit_dmg := 0
			var tried := 0
			var own: Array = []
			for ev in kept_resolves[i]["events"]:
				if String(ev.get("owner", "")) != mobs[i].id and String(ev.get("owner", "")) != "B":
					continue
				own.append(ev)
				match String(ev.get("type", "")):
					"attack_hit":
						hit_dmg += int(ev.get("damage", 0))
						tried += 1
					"attack_whiff", "attack_blocked":
						tried += 1   # the resolver ALREADY logs a character's miss -- no extra note,
									 # or a two-bite turn reads as "missed" next to real damage
			# THE RESOLVER ALREADY APPLIED THIS DAMAGE. It must NEVER enter `budget_dmg`
			# (subtracted at the end of this function for the old move-only mobs), or a
			# character's bite lands twice. The PRIMARY mob's hit is already inside
			# player_final (cloned from its r["a"]); the others land theirs once here.
			if i > 0 and hit_dmg > 0:
				player_final.hp = maxi(0, player_final.hp - hit_dmg)
			mob_events.append(own)
			strikes_by_mob.append(1 if hit_dmg > 0 else 0)
			attempts_by_mob.append(tried)
			dmg_by_mob.append(hit_dmg)          # reported for the log/anims -- NOT re-applied
			continue
		# Strike ticks follow the mob's ACTION ORDER, not just its budget: an
		# attack in slot 1 lands at 350, in slot 2 at 900. ([attack, move] used to
		# be judged at 900 -- dodging attack-first mobs was mistimed.)
		var ticks: Array = _strike_ticks(mob_seqs[i])
		var landed: int = 0
		var d: int = 0
		for st in ticks:
			var snap := _player_at(timeline, int(st), player_final)
			if snap == null:
				strike_log.append({"mob": i, "tick": int(st), "hit": false, "why": "you were mid-blink"})
				continue                    # in transit (mid-blink): untargetable -> miss
			var hit: int = mob_kinds[i].attack_damage(out_mobs[i], snap, grid, guarded)
			if hit > 0:
				landed += 1
				d += hit
				strike_log.append({"mob": i, "tick": int(st), "hit": true, "dmg": hit})
			else:
				strike_log.append({"mob": i, "tick": int(st), "hit": false, "why": "out of reach at that tick"})
		strikes_by_mob.append(landed)
		attempts_by_mob.append(ticks.size())
		mob_events.append([])          # old move-only mobs have no resolver actions
		dmg_by_mob.append(d)
		budget_dmg += d

	# Successful guard refunds energy, exactly like a duel: if the player guarded and a mob
	# that actually struck (spent an action attacking) hit a face the guard covers (front/side),
	# refund that tier's energy. Mob strikes bypass the resolver, so we mirror its refund here.
	var guard_refund: int = 0
	if guarded:
		for i in mobs.size():
			if int(strikes_by_mob[i]) > 0 and mob_kinds[i].threatens(out_mobs[i].pos, player_final.pos, grid):
				var tier: String = Config.flank_tier(player_final.facing, player_final.pos, out_mobs[i].pos)
				guard_refund = maxi(guard_refund, int(Config.GUARD_REFUND_TIER.get(tier, 0)))
		if guard_refund > 0:
			player_final.energy = mini(Config.MAX_ENERGY, player_final.energy + guard_refund)

	player_final.hp = clampi(player_final.hp - budget_dmg, 0, Config.MAX_HP)
	var result: String = "player_dead" if player_final.hp <= 0 else "ongoing"
	return {
		"player": player_final,
		"mobs": out_mobs,
		"primary_events": primary_events,
		"mob_events": mob_events,
		"dmg_by_mob": dmg_by_mob,
		"strikes_by_mob": strikes_by_mob,
		"attempts_by_mob": attempts_by_mob,
		"strike_log": strike_log,
		"guard_refund": guard_refund,
		"result": result,
	}

# The player's (pos, facing) at every change-tick this turn, from the pair-0 events.
# Entries: {tick, pos, facing, transit}. transit=true between blink_depart and blink.
# Mob plans are MOVE-ONLY by design (MobKind: an attack is never a resolver action).
# Strikes come from the UNUSED action budget: 2 actions per turn, moves consume them,
# what's left strikes -- in the LATER slots (you move first, then bite). So:
#   0 moves -> strikes at [350, 900];  1 move -> [900];  2 moves -> none.
static func _strike_ticks(seq: Array) -> Array:
	var budget: int = clampi(2 - _move_count(seq), 0, 2)
	if budget >= 2:
		return [350, 900]
	if budget == 1:
		return [900]
	return []

static func _player_timeline(start: Combatant, events: Array) -> Array:
	var tl: Array = [{"tick": -1, "pos": start.pos, "facing": start.facing, "transit": false}]
	for e in events:
		if String(e.get("owner", "")) != "A":
			continue
		var t := int(e.get("tick", 0))
		var last: Dictionary = tl[tl.size() - 1]
		match String(e.get("type", "")):
			"move":
				tl.append({"tick": t, "pos": e.get("to", last["pos"]), "facing": last["facing"], "transit": false})
			"pivot":
				tl.append({"tick": t, "pos": last["pos"], "facing": int(e.get("facing", last["facing"])), "transit": false})
			"blink_depart":
				tl.append({"tick": t, "pos": last["pos"], "facing": last["facing"], "transit": true})
			"blink":
				tl.append({"tick": t, "pos": e.get("to", last["pos"]), "facing": int(e.get("facing", last["facing"])), "transit": false})
	return tl

# A shallow player snapshot AT `tick` (null while in blink transit = untargetable).
static func _player_at(tl: Array, tick: int, template: Combatant) -> Combatant:
	var cur: Dictionary = tl[0]
	for entry in tl:
		if int(entry["tick"]) <= tick:
			cur = entry
		else:
			break
	if bool(cur["transit"]):
		return null
	var snap: Combatant = template.clone()
	snap.pos = cur["pos"]
	snap.facing = int(cur["facing"])
	return snap

static func _player_guarded(player_seq: Array) -> bool:
	for a in player_seq:
		if String(a.get("id", "")) == "guard":
			return true
	return false

# How many MOVE actions a sequence spends (used to reserve the mob's attack action).
static func _move_count(seq: Array) -> int:
	var n: int = 0
	for a in seq:
		if String(a.get("id", "")) == "move":
			n += 1
	return n

# World grid copy with every OTHER mob's tile (and any already-resolved mob's new tile)
# blocked, so the mob being resolved -- and its brain -- treats them as walls.
static func _grid_blocking_others(base: WorldGrid, mobs: Array, occupied: Dictionary, skip: int) -> WorldGrid:
	var g: WorldGrid = WorldGrid.new()
	g.world_size = base.world_size
	g.gem_map = base.gem_map          # keep gemstone nodes solid inside combat too
	g.blocked = []
	for row in base.blocked:
		g.blocked.append(row.duplicate())
	for i in mobs.size():
		if i == skip:
			continue
		var p: Vector2i = mobs[i].pos
		if p.x >= 0 and p.y >= 0 and p.x < g.world_size and p.y < g.world_size:
			g.blocked[p.y][p.x] = true
	for key in occupied:
		var q: Vector2i = key
		if q.x >= 0 and q.y >= 0 and q.x < g.world_size and q.y < g.world_size:
			g.blocked[q.y][q.x] = true
	return g
