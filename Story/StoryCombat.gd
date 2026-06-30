# StoryCombat.gd
# Story-mode multi-mob resolution, built ENTIRELY on top of the unmodified 2-actor
# Resolver -- nothing in the engine is changed. One story turn = the player's single
# action resolved against EACH engaged mob in sequence (player vs mob_i), which means:
#   * the player's offense -- including an AoE -- lands on EVERY mob it reaches, because
#     each pairwise resolve runs the player's action against that mob;
#   * every mob gets to hit the player this turn (their damage is summed onto the player);
#   * mobs are AWARE of each other: each is handed a grid with the other mobs (and any
#     already-resolved mob's new tile) marked as walls, so the existing AI routes around
#     them and no two share a tile.
# The player's own post-action state (one move, one cost) is taken from the FIRST
# (nearest) resolve; the others contribute only their mob's result + their hit on the
# player. Returns final states plus events for the controller to animate.
class_name StoryCombat
extends RefCounted

const WAIT_SEQ := [{"id": "wait"}]

# player_seq: the player's chosen sequence. mobs/mob_seqs are parallel arrays, ordered
# by the caller (nearest first). Returns:
#   { "player": Combatant, "mobs": [Combatant], "primary_events": [...],
#     "extra": [ {"index":i, "mob":Combatant, "dmg":int, "events":[...]} ],
#     "result": "ongoing" | "player_dead" }
static func resolve_turn(grid: WorldGrid, player_in: Combatant, mobs: Array,
		player_seq: Array, mob_seqs: Array) -> Dictionary:
	var start_hp: int = player_in.hp
	var player_final: Combatant = player_in.clone()
	var out_mobs: Array = []
	var primary_events: Array = []
	var extra: Array = []
	var dmg_total: int = 0
	var occupied: Dictionary = {}            # tiles taken by already-resolved mobs (their new pos)

	for i in mobs.size():
		var g: WorldGrid = _grid_blocking_others(grid, mobs, occupied, i)
		var mob_clone: Combatant = mobs[i].clone()
		var r: Dictionary = Resolver.resolve(g, player_in.clone(), mob_clone, player_seq, mob_seqs[i], 0)
		var p_after: Combatant = r["a"]
		var m_after: Combatant = r["b"]
		out_mobs.append(m_after)
		occupied[m_after.pos] = true          # later mobs won't step onto this tile
		var dmg: int = maxi(0, start_hp - p_after.hp)
		dmg_total += dmg
		if i == 0:
			player_final = p_after.clone()    # canonical player state (its single action)
			primary_events = r["events"]
		else:
			extra.append({"index": i, "mob": m_after, "dmg": dmg, "events": r["events"]})

	# The player's HP reflects EVERY mob's hit this turn (summed), not just the first.
	player_final.hp = maxi(0, start_hp - dmg_total)
	var result: String = "player_dead" if player_final.hp <= 0 else "ongoing"
	return {
		"player": player_final,
		"mobs": out_mobs,
		"primary_events": primary_events,
		"extra": extra,
		"result": result,
	}

# A copy of the world grid with every OTHER mob's tile (and any already-resolved mob's
# new tile) blocked, so the mob being resolved -- and its AI -- treats them as walls.
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
