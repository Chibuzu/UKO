# StoryCombat.gd
# Story-mode multi-mob resolution, built ENTIRELY on top of the unmodified 2-actor
# Resolver -- nothing in the engine is changed. One story turn = the player's sequence
# resolved against EACH engaged mob in turn (player vs mob_i), which means:
#   * the player's offense -- including an AoE -- lands on EVERY mob it reaches;
#   * mobs are AWARE of each other: each is handed a grid with the others marked as
#     walls, so nobody shares a tile;
#   * MELEE mobs (no gear -> no spells) deal their damage THROUGH the Resolver, so guard,
#     flanking and the RPS loop all behave exactly as in a duel;
#   * RANGED mobs (Bat) move as a movement-only sequence and deal NO Resolver damage;
#     their strike is applied afterwards by MobBrain against the player's final tile, so
#     it's dodged by movement/walls and blocked by a correctly-faced guard.
# The player's own post-action state (one resolve, one cost) is the FIRST (nearest) one.
class_name StoryCombat
extends RefCounted

# mobs / mob_seqs / mob_types are parallel arrays, ordered by the caller (nearest first).
# Returns:
#   { "player": Combatant, "mobs": [Combatant], "primary_events": [...],
#     "dmg_by_mob": [int],   # damage each mob dealt this turn (parallel to mobs)
#     "result": "ongoing" | "player_dead" }
static func resolve_turn(grid: WorldGrid, player_in: Combatant, mobs: Array,
		player_seq: Array, mob_seqs: Array, mob_types: Array) -> Dictionary:
	var start_hp: int = player_in.hp
	var guarded: bool = _player_guarded(player_seq)
	var player_final: Combatant = player_in.clone()
	var out_mobs: Array = []
	var p_hp: Array = []                      # player hp after each pairwise resolve (melee dmg source)
	var primary_events: Array = []
	var occupied: Dictionary = {}

	for i in mobs.size():
		var g: WorldGrid = _grid_blocking_others(grid, mobs, occupied, i)
		var r: Dictionary = Resolver.resolve(g, player_in.clone(), mobs[i].clone(), player_seq, mob_seqs[i], 0)
		var p_after: Combatant = r["a"]
		var m_after: Combatant = r["b"]
		out_mobs.append(m_after)
		p_hp.append(p_after.hp)
		occupied[m_after.pos] = true
		if i == 0:
			player_final = p_after.clone()   # canonical player state (its single sequence)
			primary_events = r["events"]

	# Per-mob damage: melee comes from that pairwise resolve (guard/flank already applied);
	# ranged is computed against the player's FINAL tile, guard-aware.
	var dmg_by_mob: Array = []
	var dmg_total: int = 0
	for i in mobs.size():
		var prof: Dictionary = MobBrain.PROFILES[mob_types[i]]
		var dmg: int
		if String(prof.get("kind", "melee")) == "ranged":
			dmg = MobBrain.ranged_damage(out_mobs[i], player_final, grid, prof, guarded)
		else:
			dmg = maxi(0, start_hp - int(p_hp[i]))
		dmg_by_mob.append(dmg)
		dmg_total += dmg

	player_final.hp = maxi(0, start_hp - dmg_total)
	var result: String = "player_dead" if player_final.hp <= 0 else "ongoing"
	return {
		"player": player_final,
		"mobs": out_mobs,
		"primary_events": primary_events,
		"dmg_by_mob": dmg_by_mob,
		"result": result,
	}

# Did the player raise a guard this turn? (Its directional effect is applied per-mob.)
static func _player_guarded(player_seq: Array) -> bool:
	for a in player_seq:
		if String(a.get("id", "")) == "guard":
			return true
	return false

# A copy of the world grid with every OTHER mob's tile (and any already-resolved mob's
# new tile) blocked, so the mob being resolved -- and its brain -- treats them as walls.
static func _grid_blocking_others(base: WorldGrid, mobs: Array, occupied: Dictionary, skip: int) -> WorldGrid:
	var g: WorldGrid = WorldGrid.new()
	g.world_size = base.world_size
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
