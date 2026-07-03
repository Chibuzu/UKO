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
		player_seq: Array, mob_seqs: Array, mob_kinds: Array) -> Dictionary:
	var guarded: bool = _player_guarded(player_seq)
	var player_final: Combatant = player_in.clone()
	var out_mobs: Array = []
	var primary_events: Array = []
	var occupied: Dictionary = {}

	for i in mobs.size():
		var g: WorldGrid = _grid_blocking_others(grid, mobs, occupied, i)
		var r: Dictionary = Resolver.resolve(g, player_in.clone(), mobs[i].clone(), player_seq, mob_seqs[i], 0)
		out_mobs.append(r["b"])
		occupied[r["b"].pos] = true
		if i == 0:
			player_final = r["a"].clone()        # includes any REST regen; mobs deal no resolver dmg
			primary_events = r["events"]
			occupied[player_final.pos] = true    # your landing tile is now a wall for every other mob

	# Each mob's strike, guard-aware, against the player's final tile. A mob has 2 actions
	# per turn and an ATTACK IS one of them, so a mob that spent both actions moving (2 moves)
	# cannot also strike this turn. Its per-creature range/shape still governs whether the
	# strike from <=1 move connects.
	var dmg_by_mob: Array = []
	var dmg_total: int = 0
	var may_attack: Array = []
	for i in mobs.size():
		var attacked: bool = _move_count(mob_seqs[i]) <= 1
		may_attack.append(attacked)
		var d: int = mob_kinds[i].attack_damage(out_mobs[i], player_final, grid, guarded) if attacked else 0
		dmg_by_mob.append(d)
		dmg_total += d

	# Successful guard refunds energy, exactly like a duel: if the player guarded and a mob
	# that actually struck (spent an action attacking) hit a face the guard covers (front/side),
	# refund that tier's energy. Mob strikes bypass the resolver, so we mirror its refund here.
	var guard_refund: int = 0
	if guarded:
		for i in mobs.size():
			if may_attack[i] and mob_kinds[i].threatens(out_mobs[i].pos, player_final.pos, grid):
				var tier: String = Config.flank_tier(player_final.facing, player_final.pos, out_mobs[i].pos)
				guard_refund = maxi(guard_refund, int(Config.GUARD_REFUND_TIER.get(tier, 0)))
		if guard_refund > 0:
			player_final.energy = mini(Config.MAX_ENERGY, player_final.energy + guard_refund)

	player_final.hp = clampi(player_final.hp - dmg_total, 0, Config.MAX_HP)
	var result: String = "player_dead" if player_final.hp <= 0 else "ongoing"
	return {
		"player": player_final,
		"mobs": out_mobs,
		"primary_events": primary_events,
		"dmg_by_mob": dmg_by_mob,
		"guard_refund": guard_refund,
		"result": result,
	}

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
