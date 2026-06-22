# Config.gd
# Core ENGINE numbers and the basic action schema. Spell and status CONTENT
# now lives in SpellBook.gd; Config just reads from it through the lookups
# below, so the rest of the code keeps calling Config.def(...) as before.
#
# Values tagged [PH] are placeholders to make the sim run; tune freely.
class_name Config
extends RefCounted

# ── Tick bands (ruleset 2) ──────────────────────────────────────────────
# World B order (earliest resolves first). Attack sits BEFORE Move, so melee
# lands before a target can step away (no kiting). AoE is also pre-Move (its
# control/area effects are worthless if the target relocates first). Move
# beats Special, so single-target Specials remain dodgeable. Rest resolves
# last, staying the long, interruptible commitment.
enum Band { BUFF, PIVOT, GUARD, ATTACK, AOE, MOVE, SPECIAL, REST }

const BAND_WIDTH := 100
const BAND_BASE := {
	Band.BUFF: 0, Band.PIVOT: 100, Band.GUARD: 200, Band.ATTACK: 300,
	Band.AOE: 400, Band.MOVE: 500, Band.SPECIAL: 600, Band.REST: 700,
}
const BAND_PRIORITY := {
	Band.BUFF: 0, Band.PIVOT: 1, Band.GUARD: 2, Band.ATTACK: 3,
	Band.AOE: 4, Band.MOVE: 5, Band.SPECIAL: 6, Band.REST: 7,
}

# ── Resources [PH] ──────────────────────────────────────────────────────
const MAP_ROTATE_EVERY := 5    # shift the arena quadrants one step clockwise every this many turns
const MAP_CRUSH_DAMAGE := 20   # if a rotating wall would land on you, it is suppressed and you take this
const MAX_HP := 100
const MAX_MP := 100
const MAX_ENERGY := 100
const ENERGY_REGEN := 30
const ENERGY_PULSE_ACTIONS := 6   # regen fires every 6 SHARED non-Wait actions (both fighters)
const ENERGY_PULSE_TURNS := 3     # legacy, unused (kept so any old harness still compiles)
const WAIT_ENERGY := 10           # small personal energy top-up WAIT now grants (tunable)

# ── Energy costs (ruleset 4) ────────────────────────────────────────────
# Movement cost is DIRECTIONAL (relative to facing): closing is cheap, retreat
# is expensive — this is the structural brake on kiting. The duration penalty
# on backstep is held in reserve (BACK_MOVE_TAX = 0); we lead with energy.
const COST_MOVE_FWD := 15    # toward your facing: closing distance
const COST_MOVE_SIDE := 20   # lateral: repositioning / dodging a line
const COST_MOVE_BACK := 25   # away from facing: retreat bleeds the kiter
const COST_ATTACK := 20
const COST_GUARD := 30
const GUARD_REFUND := 15
# Directional guard: fraction of an incoming melee a raised guard absorbs, by the
# attacker's flank tier vs the guarder -- front fully blocks, a side hit is halved,
# a back hit slips past. Energy refund mirrors it (front 15 / side 10 / back 0);
# a back hit refunds nothing, so the guard was simply wasted.
const GUARD_BLOCK := { "front": 1.0, "side": 0.5, "back": 0.0 }
const GUARD_REFUND_TIER := { "front": GUARD_REFUND, "side": 10, "back": 0 }
const BACK_MOVE_TAX := 0     # within-band duration penalty on backstep (reserve lever)

# ── Facing & flanking (ruleset 6) ───────────────────────────────────────
enum Facing { NORTH, EAST, SOUTH, WEST }
const FACING_VEC := {
	Facing.NORTH: Vector2i(0, -1), Facing.EAST: Vector2i(1, 0),
	Facing.SOUTH: Vector2i(0, 1), Facing.WEST: Vector2i(-1, 0),
}
const FLANK_MULT := { "front": 1.0, "side": 1.5, "back": 2.0 }
const ATTACK_DAMAGE := 15   # World B: melee no longer whiffs, so it hits for less

# Which face of a defender (facing `facing`, standing at `def_pos`) the tile
# `atk_pos` sits on: "front" / "side" / "back". THE flank rule -- the resolver's
# damage step and the AI's threat read both defer here, so the geometry has a
# single definition. Multiplier for each tier lives in FLANK_MULT above.
static func flank_tier(facing: int, def_pos: Vector2i, atk_pos: Vector2i) -> String:
	var to_atk: Vector2i = atk_pos - def_pos
	var f: Vector2i = FACING_VEC[facing]
	var dot := to_atk.x * f.x + to_atk.y * f.y
	if dot > 0:
		return "front"
	elif dot < 0:
		return "back"
	return "side"

# ── Basic actions ───────────────────────────────────────────────────────
const ACTIONS := {
	"move":  { "band": Band.MOVE,   "base_tick": 20, "energy_cost": COST_MOVE_FWD, "mp_cost": 0, "needs_tile": true,  "category": "move" },
	"pivot": { "band": Band.PIVOT,  "base_tick": 10, "energy_cost": 0, "mp_cost": 0, "needs_tile": false, "category": "pivot" },
	"attack":{ "band": Band.ATTACK, "base_tick": 50, "energy_cost": COST_ATTACK, "mp_cost": 0, "needs_tile": true, "category": "attack" },
	"guard": { "band": Band.GUARD,  "base_tick": 0,  "energy_cost": COST_GUARD, "mp_cost": 0, "needs_tile": false, "category": "guard" },
	"rest":  { "band": Band.REST,   "base_tick": 90, "energy_cost": 0, "mp_cost": 0, "needs_tile": false, "category": "rest" },
	# WAIT is a strategic HOLD: it resolves LATE (tick 580 > move 520), so queuing it
	# before an action makes that action land after the foe has moved. base_tick is
	# the knob (0-99 within the MOVE band -> 500-599). Still grants WAIT_ENERGY.
	"wait":  { "band": Band.MOVE,   "base_tick": 80, "energy_cost": 0, "mp_cost": 0, "needs_tile": false, "category": "wait" },
	"_noop": { "band": Band.BUFF,   "base_tick": 0,  "energy_cost": 0, "mp_cost": 0, "needs_tile": false, "category": "noop" },
}

# ── Lookups (basic actions here + spells from SpellBook) ────────────────
static func def(id: String) -> Dictionary:
	if ACTIONS.has(id):
		return ACTIONS[id]
	if SpellBook.SPELLS.has(id):
		return SpellBook.SPELLS[id]
	return {}

static func is_spell(id: String) -> bool:
	return SpellBook.SPELLS.has(id)

static func is_blink(id: String) -> bool:
	return String(def(id).get("effect", {}).get("type", "")) == "blink"

# Total flight time of a teleport: range tiles, each `tick_per_tile` apart. A blink
# ARRIVES this many ticks after it DEPARTS (and the caster's next action waits for it).
static func blink_travel(id: String) -> int:
	return int(def(id).get("range", 1)) * int(def(id).get("tick_per_tile", 0))

# Landing tile of a fixed-distance directional blink, or {} if it cannot land.
# Travels `dist` tiles along cardinal `dir`, PHASING THROUGH whatever sits on the
# intervening tiles (wall or fighter). Only the LANDING tile must be free: in
# bounds, not a wall, not the foe. (Short range keeps the wall-hop from trivializing corners.)
static func blink_landing(grid: Grid, from: Vector2i, dir: Vector2i, dist: int, foe_pos: Vector2i) -> Dictionary:
	var land: Vector2i = from + dir * dist
	if not grid.in_bounds(land) or grid.is_blocked(land) or land == foe_pos:
		return {}
	return {"tile": land}

# True if this spell flies as a projectile (expands into per-tile flight steps)
# instead of striking its whole shape at one instant.
static func is_projectile(id: String) -> bool:
	return bool(def(id).get("projectile", false))

# A projectile's flight path from `from` along cardinal `dir`: one entry per tile,
# each `tax` ticks after the previous, the first at `launch_tick`. Stops at a wall
# or the grid edge (the bolt is absorbed). Returns [{tile, tick, step}, ...].
static func projectile_path(grid: Grid, from: Vector2i, dir: Vector2i, rng: int, tax: int, launch_tick: int) -> Array:
	var path: Array = []
	var p: Vector2i = from
	for k in range(1, rng + 1):
		p += dir
		if not grid.in_bounds(p) or grid.is_blocked(p):
			break
		path.append({"tile": p, "tick": launch_tick + (k - 1) * tax, "step": k})
	return path

static func cooldown_of(id: String) -> int:
	return int(def(id).get("cooldown", 0))

static func status_def(id: String) -> Dictionary:
	return SpellBook.STATUSES.get(id, {})

static func final_tick(band: int, within_tick: int) -> int:
	return int(BAND_BASE[band]) + clampi(within_tick, 0, BAND_WIDTH - 1)

static func effective_energy_cost(id: String, statuses: Dictionary) -> int:
	var base := int(def(id).get("energy_cost", 0))
	if base <= 0:
		return base
	var reduction := 0
	for sid in statuses:
		if int(statuses[sid]) > 0:
			reduction += int(status_def(sid).get("energy_cost_reduction", 0))
	return maxi(0, base - reduction)

static func can_afford(energy: int, mp: int, statuses: Dictionary, id: String) -> bool:
	var d := def(id)
	if d.is_empty():
		return false
	return energy >= effective_energy_cost(id, statuses) and mp >= int(d.get("mp_cost", 0))

# ── Directional movement cost ──────────────────────────────────────────
# Direction is relative to the mover's facing: the tile in front is "forward",
# directly behind is "back", the two perpendicular tiles are "side".
static func move_direction(facing: int, from: Vector2i, to: Vector2i) -> String:
	var delta := to - from
	var fwd := Vector2i(FACING_VEC[facing])
	if delta == fwd:
		return "forward"
	if delta == -fwd:
		return "back"
	return "side"

static func move_base_cost(facing: int, from: Vector2i, to: Vector2i) -> int:
	match move_direction(facing, from, to):
		"forward": return COST_MOVE_FWD
		"back": return COST_MOVE_BACK
		_: return COST_MOVE_SIDE

static func effective_move_cost(facing: int, from: Vector2i, to: Vector2i, statuses: Dictionary) -> int:
	var base := move_base_cost(facing, from, to)
	var reduction := 0
	for sid in statuses:
		if int(statuses[sid]) > 0:
			reduction += int(status_def(sid).get("energy_cost_reduction", 0))
	return maxi(0, base - reduction)

# Shared by the resolver's plan-time cost view AND the UI's projection: when a
# self-buff commits earlier in a sequence, its status is active for the REST of
# that same turn's planning, so a buff->move combo is both affordable and
# discounted in the menu and in resolution. Mutates `statuses` in place; a no-op
# for any action that isn't a self-targeted apply_status spell.
static func apply_planned_self_buff(statuses: Dictionary, action_id: String) -> void:
	if not is_spell(action_id):
		return
	var eff: Dictionary = def(action_id).get("effect", {})
	if eff.get("type", "") == "apply_status" and eff.get("to", "self") == "self":
		var st: String = eff.get("status", "")
		if st != "":
			statuses[st] = int(status_def(st).get("duration", 0))

static func energy_pulse_due(turn: int) -> bool:
	return turn > 0 and turn % ENERGY_PULSE_TURNS == 0
