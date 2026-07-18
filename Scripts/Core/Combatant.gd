# Combatant.gd
# Pure state for one duelist. No nodes, no drawing. The visual unit (built
# later) will mirror this; the resolver only ever works on clones of it.
class_name Combatant
extends RefCounted

var id: String          # "A" or "B"
var hp: int
var mp: int
var energy: int
var pos: Vector2i
var facing: int         # Config.Facing

# Speed boost that is ACTIVE this turn (granted by a successful guard last
# turn). The resolver reads it for tick ordering, then consumes it, and may
# set it again if a guard succeeds this turn (granting it for the next one).
var speed_boost: bool = false
var rest_ready: bool = true     # may REST only after a full turn taking no damage

# Active timed statuses: id -> turns remaining. e.g. {"energy_discount": 5}
var statuses: Dictionary = {}
# Spell cooldowns: id -> turns remaining before it can be cast again.
var cooldowns: Dictionary = {}
var spent_once: Dictionary = {}   # once_per_match items already used this match (e.g. the grenade)
# Transient (one turn only; deliberately NOT copied in clone()): when a rooted move is cancelled,
# the actor's next move inherits the cancelled move's target -- a double-mover advances to the
# FIRST tile they picked, not the second (grenade spec c).
var reroute_armed: bool = false
var reroute_tile: Vector2i = Vector2i.ZERO

# Shared action tally (mirrored on both fighters): every ENERGY_PULSE_ACTIONS
# non-Wait actions taken by either player, both regen energy.
var action_count: int = 0

# Mob attack profile (duelists keep the defaults). Set by GameController for story mobs.
var attack_power: int = 0              # 0 = the duel default (Config.ATTACK_DAMAGE). Story
                                       # units set their own from their MobSpec loadout.
var attack_range: int = 1              # bat = 2: strikes from two tiles away
var attack_all_adjacent: bool = false  # ooze = true: every attack hits ALL 4 adjacent tiles
# STORY FOOTPRINT: the unit's BODY as local offsets in its facing basis (x = its
# right, y = forward); (0,0) is `pos`. Empty = single tile -- ALWAYS empty in duels.
# Scale freely: the serpent is Resolver.shape_line(2); a big boss shape_rect(4, 4).
var body: Array = []

# Loadout: up to four gear slots (ids into GearBook). "" = empty/neutral block.
# Spells are NOT stored on the fighter — they are derived from this gear, so
# swapping a slot swaps the spell. Slots map 1:1 to the sprite's four blocks.
var gear: Array = ["", "", "", ""]

# Equip a loadout (array of gear ids, "" for empty). Pads/truncates to 4 slots.
func equip(loadout: Array) -> void:
	gear = []
	for i in range(4):
		var entry: Variant = loadout[i] if i < loadout.size() else ""
		# str() (not String()) tolerates whatever survives network serialization --
		# notably an empty slot that came back as null instead of "" -- without crashing.
		gear.append("" if entry == null else str(entry))

# The spell ids this fighter can cast, in slot order (empties skipped). This is
# what the menu/AI read instead of a hardcoded list.
func spell_ids() -> Array:
	var out: Array = []
	for gid in gear:
		var sid := GearBook.spell_of(gid)
		if sid != "":
			out.append(sid)
	out.append("grenade")   # universal once-per-match item, available to everyone (see _legalize)
	return out

# The spell in a specific block slot (0-3), or "" if empty. Used by slot-indexed
# input (key 1-4 fires whatever gear sits in that slot).
func spell_in_slot(slot: int) -> String:
	if slot < 0 or slot >= gear.size():
		return ""
	return GearBook.spell_of(gear[slot])

func _init(p_id: String, p_pos: Vector2i, p_facing: int) -> void:
	id = p_id
	pos = p_pos
	facing = p_facing
	hp = Config.MAX_HP
	mp = Config.MAX_MP
	energy = Config.MAX_ENERGY

# All world cells this unit occupies (primary first). Empty body -> just [pos].
func cells() -> Array:
	return cells_at(pos)

# The cells it WOULD occupy standing at `at` with its current facing.
func cells_at(at: Vector2i) -> Array:
	return cells_facing(at, facing)

# The cells it would occupy standing at `at` facing `f` -- the hypothetical a brain asks
# before committing. THE geometry lives here: offsets are in the facing basis (x = its
# right, y = forward), so a body rotates with its facing for free.
func cells_facing(at: Vector2i, f: int) -> Array:
	if body.is_empty():
		return [at]
	var fwd := Vector2i(Config.FACING_VEC[f])
	var right := Vector2i(-fwd.y, fwd.x)
	var out: Array = []
	for off: Vector2i in body:
		out.append(at + right * off.x + fwd * off.y)
	return out

# THE marshal dict for the C# bridge boundary (BrainBridge/ResolverBridge read
# this exact 14-key contract in CombatantFrom/FromDict). This is the ONLY place
# the GDScript side builds it -- AI.gd, BrainAgreement, BridgeBench, and the
# overnight tools all call this. Renaming a key means updating the C# readers
# in the same change (a missing key marshals as 0/false with NO error).
# GD-side only by design: the C# Combatant never serializes itself outward.
func to_bridge_dict() -> Dictionary:
	return {"id": id, "x": pos.x, "y": pos.y, "facing": facing,
		"hp": hp, "mp": mp, "energy": energy,
		"action_count": action_count, "rest_ready": rest_ready, "speed_boost": speed_boost,
		"cooldowns": cooldowns.duplicate(), "statuses": statuses.duplicate(),
		"spent_once": spent_once.duplicate(), "gear": gear.duplicate()}

func clone() -> Combatant:
	var c := Combatant.new(id, pos, facing)
	c.hp = hp
	c.mp = mp
	c.energy = energy
	c.speed_boost = speed_boost
	c.rest_ready = rest_ready
	c.statuses = statuses.duplicate()
	c.cooldowns = cooldowns.duplicate()
	c.spent_once = spent_once.duplicate()
	c.action_count = action_count
	c.attack_power = attack_power
	c.attack_range = attack_range
	c.attack_all_adjacent = attack_all_adjacent
	c.body = body.duplicate()
	c.gear = gear.duplicate()
	return c

func is_dead() -> bool:
	return hp <= 0
