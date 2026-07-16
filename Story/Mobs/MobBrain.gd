# MobBrain.gd
# DATA registry for story monsters plus the factory that hands back the right behavior.
# Each profile is pure data -- look (name/tint/scale), stats (hp), attack shape (atk_range,
# dmg), and a loot table -- so tuning or adding a creature is mostly an edit here; genuinely
# new behavior is one MobKind subclass + one line in make_kind(). Behavior itself lives in
# MobKind and its subclasses; this file never contains logic beyond the factory.
class_name MobBrain
extends RefCounted

# NOTE: species migrate to Story/Mobs2/MobSpec.gd as they become true CHARACTERS
# (real resolver actions). Migrated so far: bat. This table keeps only the rest.
const PROFILES := {
	# The boss (Fra: fight designed later -- base melee behavior as the placeholder).
	"boss": {
		"name": "WARLORD", "hp": 220, "scale": 1.5, "tint": Color(0.85, 0.55, 1.0),
		"dmg": 20,
		"loot": [ { "item": "serpent_fang", "chance": 1.00 } ],
	},
	"serpent": {
		"name": "Serpent", "art": "serpent", "tiles": 2, "hp": 100, "scale": 1.0, "tint": Color(0.90, 0.52, 0.55),
		"dmg": 15,
		"loot": [ { "item": "serpent_scale", "chance": 1.00 }, { "item": "serpent_fang", "chance": 0.20 } ],
	},
}

# THE species lookup: characters (Story/Mobs2) come from MobSpec, the rest from
# PROFILES above. Every caller uses this -- never index a table directly.
static func profile(type: String) -> Dictionary:
	if MobSpec.is_character(type):
		return MobSpec.row(type)
	return PROFILES.get(type, {})

# The one place mapping a type id to its behavior. Add a case when you add a creature.
static func make_kind(type: String) -> MobKind:
	var k: MobKind
	match type:
		"bat":     k = CharacterBat.new()  # true-action character (Story/Mobs2)
		"slime":   k = CharacterOoze.new() # true-action character (Story/Mobs2)
		"serpent": k = SerpentKind.new()   # two-tile boss: strikes straight out from both heads
		_:         k = MobKind.new()
	k.setup(type, profile(type))           # one lookup for both tables
	return k
