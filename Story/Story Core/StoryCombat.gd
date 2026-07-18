# StoryCombat.gd
# Story-mode multi-mob resolution on top of the UNMODIFIED 2-actor resolver. One turn =
# the player's sequence resolved against each engaged mob in turn, with two consequences:
#   * the player's offense (incl. AoE) lands on EVERY mob it reaches;
#   * mobs are aware of each other -- each is handed a grid with the others as walls.
# Every mob is a TRUE-ACTION character (Story/Mobs2): its attacks are real resolver
# actions in its own pairwise resolve, so damage, guard blocks, flanks and misses are
# all engine outcomes -- nothing is synthesized story-side. The player's canonical
# post-action state is the first (nearest) pairwise resolve; the other pairs' hits on
# the player are applied once from their harvested attack_hit events.
class_name StoryCombat
extends RefCounted

# mobs / mob_seqs / mob_kinds are parallel arrays, nearest first.
# Returns { player, mobs:[Combatant], primary_events, mob_events, dmg_by_mob,
#           attempts_by_mob, guard_refund, result }.
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
		var _keep: Dictionary = _aimed_at(player_seq, player_in.pos)
		var g: WorldGrid = _grid_blocking_others(grid, mobs, occupied, i, _keep)
		var r: Dictionary = Resolver.resolve(g, player_in.clone(), mobs[i].clone(), player_seq, mob_seqs[i], 0)
		kept_resolves.append(r)
		out_mobs.append(r["b"])
		occupied[r["b"].pos] = true
		if i == 0:
			player_final = r["a"].clone()        # move-only mobs deal no resolver dmg; characters DO
			primary_events = r["events"]
			occupied[player_final.pos] = true    # your landing tile is now a wall for every other mob

	# ── harvest each character's OWN resolver events ────────────────────────
	# The primary mob's are played by the event player; the others are replayed by the
	# controller's 2-v-1 pass. Damage was applied by the resolver INSIDE each pair: the
	# primary's is already in player_final (cloned from its r["a"]); the other pairs'
	# hits on the player land exactly once here.
	var dmg_by_mob: Array = []
	var mob_events: Array = []
	var strikes_by_mob: Array = []      # internal: feeds the guard-refund pass below
	var attempts_by_mob: Array = []
	for i in mobs.size():
		var hit_dmg := 0
		var tried := 0
		var own: Array = []
		for ev in kept_resolves[i]["events"]:
			if String(ev.get("owner", "")) != mobs[i].id and String(ev.get("owner", "")) != "B":
				continue
			own.append(ev)
			match String(ev.get("type", "")):
				ResolverEvents.ATTACK_HIT:
					hit_dmg += int(ev.get("damage", 0))
					tried += 1
				ResolverEvents.ATTACK_WHIFF, ResolverEvents.ATTACK_BLOCKED:
					tried += 1   # the resolver ALREADY logs a character's miss -- no extra note,
					             # or a two-bite turn reads as "missed" next to real damage
		if i > 0 and hit_dmg > 0:
			player_final.hp = maxi(0, player_final.hp - hit_dmg)
		mob_events.append(own)
		strikes_by_mob.append(1 if hit_dmg > 0 else 0)
		attempts_by_mob.append(tried)
		dmg_by_mob.append(hit_dmg)          # reported for the log/anims -- NOT re-applied

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

	player_final.hp = clampi(player_final.hp, 0, Config.MAX_HP)   # belt-and-braces bound
	var result: String = "player_dead" if player_final.hp <= 0 else "ongoing"
	return {
		"player": player_final,
		"mobs": out_mobs,
		"primary_events": primary_events,
		"mob_events": mob_events,
		"dmg_by_mob": dmg_by_mob,
		"attempts_by_mob": attempts_by_mob,
		"guard_refund": guard_refund,
		"result": result,
	}

static func _player_guarded(player_seq: Array) -> bool:
	for a in player_seq:
		if String(a.get("id", "")) == "guard":
			return true
	return false

# World grid copy with every OTHER mob's tile (and any already-resolved mob's new tile)
# blocked, so the mob being resolved -- and its brain -- treats them as walls.
# Tiles the player's own aimed actions must be allowed to REACH, whoever is standing on
# them. The story fights each mob in a SEPARATE pairwise resolve, and each pair walls the
# other mobs -- so without this the same action succeeds in one pair and fails in another,
# and you get the two worst bugs of the session:
#   THROW  -- a grenade aimed at one twin found the other twin's tile "blocked", returned
#             an empty path, and reported spell_miss in the very pair that gets logged.
#   BLINK  -- a blink line crossing the other twin failed _blink_has_landing and FIZZLED,
#             so in that pair you never went off-board (IN_TRANSIT) and its attack landed
#             on you -- while the other pair blinked you away and logged it. You saw
#             yourself vanish AND take the hit, because both were true, in different pairs.
# Only the player's own aimed spells qualify. A move or a melee is still stopped by a body.
static func _aimed_at(player_seq: Array, from: Vector2i) -> Dictionary:
	var out := {}
	for a in player_seq:
		if not a.has("tile"):
			continue
		var id := String(a.get("id", ""))
		var d: Dictionary = Config.def(id)
		if String(d.get("shape", "")) in ["throw", "blink"]:
			out[Vector2i(a["tile"])] = true
			# A blink's LINE must be reachable, not just its landing -- and it has to be
			# the line the ENGINE actually walks. Resolver._dir_from SNAPS the aim to a
			# cardinal, so a diagonal aim flies along an axis. Keeping the diagonal tiles
			# open (as this first did) frees tiles the blink never visits, while the ones
			# it does visit stay walled -- it fizzles, pos never becomes IN_TRANSIT, and
			# you get hit standing still. Mirror the engine's rule exactly.
			if String(d.get("shape", "")) == "blink":
				var step := _blink_dir(from, Vector2i(a["tile"]))
				var p: Vector2i = from
				for _i in range(int(d.get("range", 1))):
					p += step
					out[p] = true
	return out


# The direction a blink ACTUALLY flies: the engine's own aim-snap rule, asked
# for instead of copied (the old duplicate carried a "change both" comment).
static func _blink_dir(from: Vector2i, to: Vector2i) -> Vector2i:
	return Resolver.dir_from(from, to)

# Build the combat grid for ONE pairwise resolve: every OTHER mob becomes a wall, so the
# two fighters in this pair cannot walk through a creature that isn't in it.
#
# `keep_open` are tiles that must NEVER become a wall no matter who stands there -- the
# tiles the player deliberately AIMED a throw at. Without it, throwing a grenade at one
# twin made its tile a wall in the OTHER twin's pair, so that pair's throw hit "a
# blocker", returned an empty path, and reported spell_miss. Since the other pair is the
# one that gets logged and animated, the grenade landed and told you it missed.
static func _grid_blocking_others(base: WorldGrid, mobs: Array, occupied: Dictionary, skip: int,
		keep_open: Dictionary = {}) -> WorldGrid:
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
		if keep_open.has(p):
			continue                      # you AIMED a throw here: it is a target, not a wall
		if p.x >= 0 and p.y >= 0 and p.x < g.world_size and p.y < g.world_size:
			g.blocked[p.y][p.x] = true
	for key in occupied:
		var q: Vector2i = key
		if q.x >= 0 and q.y >= 0 and q.x < g.world_size and q.y < g.world_size:
			g.blocked[q.y][q.x] = true
	return g
