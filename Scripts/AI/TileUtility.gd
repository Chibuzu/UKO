# TileUtility.gd
# AI INFLUENCE MAPS (new-brain step 2). Per-tile fields the new brain uses to
# decide where to stand and act. Everything is in ResourceModel value-points
# (HP-equivalent), so tile scores compose directly with the resource economy.
#
# Two raw fields, both built from the SAME reach geometry:
#   danger_field(enemy)       -> HP at RISK on each tile (enemy's reach right now)
#   strike_value_field(me,e)  -> NET value of striking the enemy FROM each tile
#                                (damage dealt minus the resources I'd spend)
#
# The strike field exploits that reach is SYMMETRIC: "I can hit the enemy from
# tile t" iff "t lies within my reach centred on the enemy". So we centre the
# one reach routine on the enemy and read the origin tiles straight off -- no
# per-tile cloning or pathfinding.
#
# tile_score() folds those with positional features (escape routes, edge-hugging,
# walls about to drop) into a single standing-value field for choosing moves.
#
# NOTE (v1): reach is computed from CURRENT positions with a free pivot assumed
# (pivot is ~free), but WITHOUT move-extension -- it does not yet model "step in,
# then hit". That one-move dilation is the obvious next knob; the goal/matrix
# layer will also reason about movement explicitly.
class_name TileUtility
extends RefCounted

const CARDINALS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

# Tile-utility feature weights, in value-points. Tune freely.
const W_OFFENSE := 1.0     # net strike value I can project from a tile
const W_SAFETY := 0.8      # HP risk from standing on a tile the enemy threatens THIS turn
const W_POTENTIAL := 0.4   # next-turn risk: a tile the enemy can only reach by closing first
const W_MOBILITY := 1.5    # per open escape route (orthogonal neighbour)
const W_EDGE := 2.0        # penalty per board edge the tile touches (corner = 2)
const W_GHOST := 999.0     # tile about to become a wall: effectively do-not-stand

# Damage (raw) or NET value (damage minus cast cost) that each affordable,
# off-cooldown OFFENSIVE action of `actor` touches when cast from `center`.
# Returns {Vector2i: value}. Used both forwards (danger, centre on the actor) and
# in reverse (strike origins, centre on the target -- reach is symmetric).
static func _reach(grid: Grid, center: Vector2i, actor: Combatant, net: bool) -> Dictionary:
	var out := {}
	# Basic melee: any orthogonal neighbour (a free pivot faces it).
	if actor.energy >= Config.COST_ATTACK:
		var v := float(Config.ATTACK_DAMAGE)
		if net:
			v -= ResourceModel.action_cost_value(actor, 0, Config.COST_ATTACK)
		for d in CARDINALS:
			var t: Vector2i = center + d
			if grid.in_bounds(t) and not grid.is_blocked(t):
				out[t] = maxf(out.get(t, -INF), v)
	# Damaging spells granted by the loadout.
	for sid in actor.spell_ids():
		var sp: Dictionary = SpellBook.SPELLS.get(sid, {})
		if sp.get("effect", {}).get("type", "") != "damage":
			continue
		if int(actor.cooldowns.get(sid, 0)) > 0:
			continue
		var mp_cost := int(sp.get("mp_cost", 0))
		var ep_cost := int(sp.get("energy_cost", 0))
		if actor.mp < mp_cost or actor.energy < ep_cost:
			continue
		var v := float(sp["effect"]["amount"])
		if net:
			v -= ResourceModel.action_cost_value(actor, mp_cost, ep_cost)
		match String(sp.get("shape", "")):
			"around":
				var r := int(sp.get("radius", Config.AROUND_RADIUS))
				for dy in range(-r, r + 1):
					for dx in range(-r, r + 1):
						if dx == 0 and dy == 0:
							continue
						var t: Vector2i = center + Vector2i(dx, dy)
						if grid.in_bounds(t):
							out[t] = maxf(out.get(t, -INF), v)
			"line":
				var rng := int(sp.get("range", 1))
				for d in CARDINALS:
					var p: Vector2i = center
					for _i in range(rng):
						p += d
						if not grid.in_bounds(p) or grid.is_blocked(p):
							break   # walls stop the line
						out[p] = maxf(out.get(p, -INF), v)
	return out

# HP at risk on every tile from `threatener`'s CURRENT position -- the strikes it
# can land THIS turn without moving. The immediate, certain threat.
static func danger_field(grid: Grid, threatener: Combatant) -> PackedFloat32Array:
	return _rasterize(_reach(grid, threatener.pos, threatener, false))

# EXTRA HP at risk on each tile that the foe can only reach by taking one setup step
# first (paying its move cost, then striking with what's left). This is a NEXT-TURN
# possibility, not an instant hit -- callers discount it (W_POTENTIAL) and net it
# against their own riposte, so a tile the foe can close into but where you'd win the
# trade reads as safe. Affordability (move + strike costs) is enforced here.
static func potential_danger_field(grid: Grid, threatener: Combatant) -> PackedFloat32Array:
	var immediate := _reach(grid, threatener.pos, threatener, false)
	var extra := {}
	for d in CARDINALS:
		var p: Vector2i = threatener.pos + d
		if not grid.in_bounds(p) or grid.is_blocked(p):
			continue
		var mc := Config.effective_move_cost(threatener.facing, threatener.pos, p, threatener.statuses)
		if threatener.energy < mc:
			continue
		var ghost := threatener.clone()
		ghost.pos = p
		ghost.energy = threatener.energy - mc          # one action spent stepping; strike with the rest
		var rf := _reach(grid, p, ghost, false)
		for t in rf:
			var add := maxf(0.0, float(rf[t]) - float(immediate.get(t, 0.0)))   # only reach BEYOND immediate
			if add > 0.0:
				extra[t] = maxf(float(extra.get(t, 0.0)), add)
	return _rasterize(extra)

# Roughly how much I can hit a now-adjacent foe for NEXT turn (one swing, or two if
# I can afford it) -- the answer a closing enemy has to beat to make closing pay.
static func _riposte_capacity(me: Combatant) -> float:
	var swings := 2 if me.energy >= 2 * Config.COST_ATTACK else 1
	return float(Config.ATTACK_DAMAGE) * float(swings)

# Net value `me` would net by striking `enemy` FROM each origin tile.
static func strike_value_field(grid: Grid, me: Combatant, enemy: Combatant) -> PackedFloat32Array:
	return _rasterize(_reach(grid, enemy.pos, me, true))

# Standing value of each tile for `me` this turn: net offence projectable from
# it, minus HP risk there, plus escape routes, minus edge-hugging, minus walls
# about to drop. Blocked tiles score -INF (cannot stand). All in value-points.
static func tile_score(grid: Grid, me: Combatant, enemy: Combatant) -> PackedFloat32Array:
	var danger := danger_field(grid, enemy)
	var potential := potential_danger_field(grid, enemy)
	var riposte := _riposte_capacity(me)
	var strike := strike_value_field(grid, me, enemy)
	var ghosts := {}
	for g in grid.incoming_walls():
		ghosts[g] = true
	var out := PackedFloat32Array()
	out.resize(Grid.SIZE * Grid.SIZE)
	for y in range(Grid.SIZE):
		for x in range(Grid.SIZE):
			var i := y * Grid.SIZE + x
			var t := Vector2i(x, y)
			if grid.is_blocked(t):
				out[i] = -INF
				continue
			var pot := maxf(0.0, potential[i] - riposte)   # only risky if the foe out-trades my answer
			var s := W_OFFENSE * strike[i] - W_SAFETY * danger[i] - W_POTENTIAL * pot
			s += W_MOBILITY * float(_open_neighbours(grid, t))
			s -= W_EDGE * float(_edge_pressure(grid, t))
			if ghosts.has(t):
				s -= W_GHOST
			out[i] = s
	return out

# Standing value of ONE tile for `me` (self-contained; used by the plan ranker to
# score where a candidate sequence leaves us). Same formula as tile_score's cells.
static func standing_value(grid: Grid, me: Combatant, enemy: Combatant, tile: Vector2i) -> float:
	if not grid.in_bounds(tile) or grid.is_blocked(tile):
		return -INF
	var i := tile.y * Grid.SIZE + tile.x
	var danger := danger_field(grid, enemy)
	var potential := potential_danger_field(grid, enemy)
	var pot := maxf(0.0, potential[i] - _riposte_capacity(me))   # next-turn risk I can't out-trade
	# Flank exposure: standing within melee range while NOT facing the foe takes the
	# 1.5x/2x hit (FLANK_MULT). This is what makes pivot-to-face rank above an
	# identical plan that leaves my back turned -- the danger field alone is
	# facing-blind, so without this the precut can't tell guard from pivot+guard.
	var face_mult := 1.0
	if Grid.dist(tile, enemy.pos) <= 2:
		face_mult = float(Config.FLANK_MULT[Config.flank_tier(me.facing, tile, enemy.pos)])
	var my_reach := _reach(grid, enemy.pos, me, true)
	var s := W_OFFENSE * maxf(0.0, my_reach.get(tile, 0.0)) - W_SAFETY * danger[i] * face_mult - W_POTENTIAL * pot * face_mult
	s += W_MOBILITY * float(_open_neighbours(grid, tile))
	s -= W_EDGE * float(_edge_pressure(grid, tile))
	for g in grid.incoming_walls():
		if g == tile:
			s -= W_GHOST
	return s

# ── helpers ──────────────────────────────────────────────────────────────
static func _rasterize(reach: Dictionary) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(Grid.SIZE * Grid.SIZE)
	for k in reach:
		var t: Vector2i = k
		out[t.y * Grid.SIZE + t.x] = maxf(0.0, reach[k])   # field reads are >= 0
	return out

static func _open_neighbours(grid: Grid, t: Vector2i) -> int:
	var n := 0
	for d in CARDINALS:
		var p: Vector2i = t + d
		if grid.in_bounds(p) and not grid.is_blocked(p):
			n += 1
	return n

# How many board edges the tile touches: 0 interior, 1 along an edge, 2 in a corner.
static func _edge_pressure(grid: Grid, t: Vector2i) -> int:
	var e := 0
	for d in CARDINALS:
		if not grid.in_bounds(t + d):
			e += 1
	return e
