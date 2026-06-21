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

# Shared action tally (mirrored on both fighters): every ENERGY_PULSE_ACTIONS
# non-Wait actions taken by either player, both regen energy.
var action_count: int = 0

# Loadout: up to four gear slots (ids into GearBook). "" = empty/neutral block.
# Spells are NOT stored on the fighter — they are derived from this gear, so
# swapping a slot swaps the spell. Slots map 1:1 to the sprite's four blocks.
var gear: Array = ["", "", "", ""]

# Equip a loadout (array of gear ids, "" for empty). Pads/truncates to 4 slots.
func equip(loadout: Array) -> void:
	gear = []
	for i in range(4):
		gear.append(String(loadout[i]) if i < loadout.size() else "")

# The spell ids this fighter can cast, in slot order (empties skipped). This is
# what the menu/AI read instead of a hardcoded list.
func spell_ids() -> Array:
	var out: Array = []
	for gid in gear:
		var sid := GearBook.spell_of(gid)
		if sid != "":
			out.append(sid)
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
	c.action_count = action_count
	c.gear = gear.duplicate()
	return c

func is_dead() -> bool:
	return hp <= 0
