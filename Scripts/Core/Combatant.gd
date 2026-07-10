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
var attack_range: int = 1              # bat = 2: strikes from two tiles away
var attack_all_adjacent: bool = false  # ooze = true: every attack hits ALL 4 adjacent tiles

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
	c.attack_range = attack_range
	c.attack_all_adjacent = attack_all_adjacent
	c.gear = gear.duplicate()
	return c

func is_dead() -> bool:
	return hp <= 0
