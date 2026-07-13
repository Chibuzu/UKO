# MobBrain.gd
# DATA registry for story monsters plus the factory that hands back the right behavior.
# Each profile is pure data -- look (name/tint/scale), stats (hp), attack shape (atk_range,
# dmg), and a loot table -- so tuning or adding a creature is mostly an edit here; genuinely
# new behavior is one MobKind subclass + one line in make_kind(). Behavior itself lives in
# MobKind and its subclasses; this file never contains logic beyond the factory.
class_name MobBrain
extends RefCounted

const PROFILES := {
	"bat": {
		"name": "Bat", "hp": 45, "scale": 0.72, "tint": Color(0.62, 0.80, 1.00), "art": "bat",
		"atk_range": 2, "dmg": 10,
		"loot": [ { "item": "bat_wing", "chance": 0.55 } ],
	},
	"slime": {
		"name": "Slime", "hp": 80, "scale": 0.90, "tint": Color(0.55, 1.00, 0.62), "art": "ooze",
		"dmg": 15,
		"loot": [ { "item": "slime_gel", "chance": 0.70 } ],
	},
	# The boss (Fra: fight designed later -- base melee behavior as the placeholder).
	"boss": {
		"name": "WARLORD", "hp": 220, "scale": 1.5, "tint": Color(0.85, 0.55, 1.0),
		"dmg": 20,
		"loot": [ { "item": "serpent_fang", "chance": 1.00 } ],
	},
	"serpent": {
		"name": "Serpent", "art": "serpent", "tiles": 2, "hp": 100, "scale": 1.15, "tint": Color(0.90, 0.52, 0.55),
		"dmg": 15,
		"loot": [ { "item": "serpent_scale", "chance": 1.00 }, { "item": "serpent_fang", "chance": 0.20 } ],
	},
}

# The one place mapping a type id to its behavior. Add a case when you add a creature.
static func make_kind(type: String) -> MobKind:
	var k: MobKind
	match type:
		"bat":   k = BatKind.new()
		"slime": k = SlimeKind.new()
		_:       k = MobKind.new()      # serpent + fallback: base melee behavior
	k.setup(type, PROFILES.get(type, {}))
	return k
